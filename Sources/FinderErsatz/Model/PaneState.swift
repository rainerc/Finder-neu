import Foundation
import Observation

/// Darstellung der Dateiliste.
enum ViewMode: String, CaseIterable, Identifiable {
    case list, brief, icons, columns, gallery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "Liste"
        case .brief: "Kurz"
        case .icons: "Miniaturen"
        case .columns: "Spalten"
        case .gallery: "Galerie"
        }
    }
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .brief: "text.alignleft"
        case .icons: "square.grid.2x2"
        case .columns: "rectangle.split.3x1"
        case .gallery: "photo.on.rectangle"
        }
    }
}

/// Zustand eines einzelnen Dateifensters (linke oder rechte Seite).
@MainActor
@Observable
final class PaneState: Identifiable {
    let id = UUID()

    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    var selection = Set<FileItem.ID>()
    var sortOrder: [KeyPathComparator<FileItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)] {
        didSet { applySort() }
    }
    private(set) var showHidden = false
    private(set) var errorMessage: String?
    /// Fehler kommt vom macOS-Datenschutz (nicht vom Dateisystem) – dann Knopf zu den Systemeinstellungen zeigen.
    private(set) var errorIsPermission = false
    var viewMode: ViewMode = .list

    // Suche
    var isSearchBarVisible = false
    private(set) var activeSearch: SearchQuery?
    private(set) var isSearchRunning = false
    var lastSearch: SearchQuery?
    /// Wird gerade ein intelligenter Ordner bearbeitet? Dann sichert die Suchleiste in diesen Ordner.
    var editingSmartFolder: UUID?
    /// Neu setzen, damit die Suchleiste ihre Felder aus `lastSearch` neu lädt.
    var searchBarResetToken = UUID()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchToken = UUID()

    /// Zeigt eine entpackte Archiv-Kopie (temporär).
    var isBrowsingArchive: Bool { ArchiveService.isInsideBrowsedArchive(currentURL) }

    /// Tab-Titel: Anzeigename des aktuellen Ordners.
    var title: String {
        if let title = activeSearch?.title { return title }
        return currentURL.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: currentURL.path)
    }

    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var watchedURL: URL?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    var selectedItems: [FileItem] { items.filter { selection.contains($0.id) } }

    init(url: URL) {
        self.currentURL = url.normalizedFileURL
        reload()
    }

    // MARK: Navigation

    func navigate(to url: URL) {
        let target = url.normalizedFileURL
        guard target != currentURL else { return }
        stopSearch()
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = target
        selection.removeAll()
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        stopSearch()
        forwardStack.append(currentURL)
        currentURL = previous
        selection.removeAll()
        reload()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        stopSearch()
        backStack.append(currentURL)
        currentURL = next
        selection.removeAll()
        reload()
    }

    func goUp() {
        guard canGoUp else { return }
        let child = currentURL
        navigate(to: currentURL.deletingLastPathComponent())
        selection = [child]
    }

    func toggleHidden() {
        showHidden.toggle()
        reload()
    }

    // MARK: Laden

    func reload() {
        if activeSearch != nil {
            // Während einer Suche: nur gelöschte/verschobene Treffer entfernen.
            items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
            return
        }
        do {
            let loaded = try FileService.contents(of: currentURL, includeHidden: showHidden)
            // Nichts Sichtbares geändert (z. B. nur unsichtbare Dateien im Benutzerordner wie .zsh_history):
            // Liste nicht neu setzen – sonst baut die Tabelle neu auf und die Markierung kann unter dem Mauszeiger springen.
            if errorMessage == nil, isUnchanged(loaded) {
                watchCurrentFolder()
                return
            }
            items = loaded
            errorMessage = nil
            errorIsPermission = false
            applyFolderSizes()
            applySort()
            selection.formIntersection(Set(items.map(\.id)))
        } catch {
            items = []
            errorMessage = Self.describe(error, for: currentURL)
            errorIsPermission = Self.isPermissionError(error)
        }
        watchCurrentFolder()
    }

    /// Gleiche Objekte mit gleichen angezeigten Werten wie bisher? (Ordnergrößen bleiben unberücksichtigt.)
    private func isUnchanged(_ loaded: [FileItem]) -> Bool {
        guard !items.isEmpty, loaded.count == items.count else { return false }
        let current = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return loaded.allSatisfy { new in
            guard let old = current[new.id] else { return false }
            return old.name == new.name && old.modified == new.modified && old.tagList == new.tagList
                && old.isHidden == new.isHidden && old.kind == new.kind
                && (new.isBrowsableFolder || old.size == new.size)
        }
    }

    /// Bei fehlender Berechtigung auf Netzlaufwerken erklären, wo man sie in macOS erteilt.
    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        return nsError.code == NSFileReadNoPermissionError
            || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EPERM))
    }

    private static func describe(_ error: Error, for url: URL) -> String {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let isPermission = nsError.code == NSFileReadNoPermissionError
            || (underlying?.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(underlying?.code ?? 0))
        let code = "(\(nsError.domain) \(nsError.code)" + (underlying.map { ", \($0.domain) \($0.code)" } ?? "") + ")"
        guard isPermission else { return "\(error.localizedDescription) \(code)" }
        if AppEnvironment.isRunningUnbundled {
            return "Die App läuft als Test-Build ohne App-Bundle (\(Bundle.main.executablePath ?? "?")) – dafür gelten die macOS-Freigaben nicht. Bitte die installierte App /Applications/Finder-Ersatz.app starten (Knopf oben im Fenster). \(code)"
        }
        let isNetwork = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
        if isNetwork {
            return "macOS hat Finder-Ersatz den Zugriff auf Netzwerkvolumes nicht erlaubt. Am dauerhaftesten: Finder-Ersatz unter „Festplattenvollzugriff“ einschalten (gilt für alle Laufwerke und bleibt auch nach Neubauten erhalten). Danach die App neu starten. \(code)"
        }
        return "Keine Berechtigung. Ggf. unter Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff erlauben und die App neu starten. \(code)"
    }

    // MARK: Ordnergrößen

    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    /// Bereits berechnete Ordnergrößen (gültig, solange sich das Änderungsdatum des Ordners nicht ändert).
    @ObservationIgnored private var folderSizeCache: [URL: (modified: Date, size: Int64)] = [:]

    /// Setzt bekannte Größen sofort und berechnet die übrigen im Hintergrund.
    private func applyFolderSizes() {
        sizeTask?.cancel()
        guard UserDefaults.standard.bool(forKey: AppSettings.calculateFolderSizesKey) else { return }
        // Auf Netzlaufwerken wäre das sehr langsam.
        guard (try? currentURL.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) != false else { return }
        var missing: [URL] = []
        for index in items.indices where items[index].isBrowsableFolder {
            if let cached = folderSizeCache[items[index].url], cached.modified == items[index].modified {
                items[index].size = cached.size
                items[index].folderSizeKnown = true
            } else {
                missing.append(items[index].url)
            }
        }
        guard !missing.isEmpty else { return }
        let folder = currentURL
        sizeTask = Task.detached(priority: .utility) { [weak self] in
            for url in missing {
                if Task.isCancelled { return }
                let size = FileTransfer.size(of: url)
                if Task.isCancelled { return }
                await self?.setFolderSize(size, for: url, in: folder)
            }
            await self?.folderSizesFinished(in: folder)
        }
    }

    private func setFolderSize(_ size: Int64, for url: URL, in folder: URL) {
        guard folder == currentURL, activeSearch == nil,
              let index = items.firstIndex(where: { $0.id == url }) else { return }
        folderSizeCache[url] = (items[index].modified, size)
        guard !items[index].folderSizeKnown || items[index].size != size else { return }
        items[index].size = size
        items[index].folderSizeKnown = true
    }

    private func folderSizesFinished(in folder: URL) {
        guard folder == currentURL, activeSearch == nil else { return }
        applySort()   // falls nach Größe sortiert ist
    }

    // MARK: Suche

    /// Sortierung vor einer Abfrage mit eigener Sortierung (z. B. „Zuletzt benutzt“), wird danach wiederhergestellt.
    @ObservationIgnored private var sortOrderBeforeSearch: [KeyPathComparator<FileItem>]?

    func startSearch(_ query: SearchQuery, sortOrder customSort: [KeyPathComparator<FileItem>]? = nil) {
        guard !query.isEmpty else { return }
        cancelSearchTask()
        sizeTask?.cancel()
        if let customSort {
            if sortOrderBeforeSearch == nil { sortOrderBeforeSearch = sortOrder }
            sortOrder = customSort
        } else if let previous = sortOrderBeforeSearch {
            sortOrderBeforeSearch = nil
            sortOrder = previous
        }
        let token = UUID()
        searchToken = token
        lastSearch = query
        activeSearch = query
        items = []
        selection = []
        errorMessage = nil
        isSearchRunning = true
        searchTask = Task.detached { [weak self] in
            var failure: String?
            do {
                try FileSearch.run(query) { batch in
                    Task { @MainActor in self?.appendSearchResults(batch, token: token) }
                }
            } catch {
                failure = error.localizedDescription
            }
            await self?.searchFinished(token: token, error: failure)
        }
    }

    func cancelSearchTask() {
        searchTask?.cancel()
        searchTask = nil
        isSearchRunning = false
    }

    /// Beendet die Suche und zeigt wieder den Ordnerinhalt.
    func stopSearch() {
        guard activeSearch != nil || isSearchRunning else { return }
        cancelSearchTask()
        searchToken = UUID()
        activeSearch = nil
        if let previous = sortOrderBeforeSearch {
            sortOrderBeforeSearch = nil
            sortOrder = previous
        }
        reload()
    }

    func closeSearch() {
        isSearchBarVisible = false
        editingSmartFolder = nil
        stopSearch()
    }

    private func appendSearchResults(_ batch: [FileItem], token: UUID) {
        guard token == searchToken else { return }
        items += batch
        if items.count <= 2000 { applySort() }
    }

    private func searchFinished(token: UUID, error: String?) {
        guard token == searchToken else { return }
        isSearchRunning = false
        searchTask = nil
        applySort()
        if let error { errorMessage = error }
    }

    /// Pfad eines Treffers relativ zum Suchordner (für die Anzeige).
    func relativeFolder(of item: FileItem) -> String {
        guard let root = activeSearch?.root.path else { return "" }
        let parent = item.url.deletingLastPathComponent().path
        guard parent.hasPrefix(root) else { return parent }
        let rest = String(parent.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rest.isEmpty ? "." : rest
    }

    /// Springt zum Ordner eines Treffers und markiert ihn.
    func reveal(_ item: FileItem) {
        stopSearch()
        navigate(to: item.url.deletingLastPathComponent())
        selection = [item.id]
    }

    // MARK: Live-Aktualisierung

    private func watchCurrentFolder() {
        guard watchedURL != currentURL else { return }
        watchedURL = currentURL
        watcher = DirectoryWatcher(url: currentURL) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    /// Fasst schnell aufeinanderfolgende Änderungen zusammen (z. B. beim Kopieren vieler Dateien).
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, self?.activeSearch == nil else { return }
            self?.reload()
        }
    }

    private func applySort() {
        // Ordner immer zuerst, danach nach gewählter Spalte.
        let folders = items.filter(\.isBrowsableFolder).sorted(using: sortOrder)
        let files = items.filter { !$0.isBrowsableFolder }.sorted(using: sortOrder)
        let sorted = folders + files
        // Nur neu setzen, wenn sich die Reihenfolge ändert (jede Zuweisung lässt die Tabelle neu aufbauen).
        if sorted.map(\.id) != items.map(\.id) || sorted.count != items.count {
            items = sorted
        }
    }
}
