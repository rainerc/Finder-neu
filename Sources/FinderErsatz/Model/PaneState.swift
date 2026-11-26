import Foundation
import Observation

/// Darstellung der Dateiliste.
enum ViewMode: String, CaseIterable, Identifiable {
    case list, brief, icons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "Liste"
        case .brief: "Kurz"
        case .icons: "Miniaturen"
        }
    }
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .brief: "rectangle.split.3x1"
        case .icons: "square.grid.2x2"
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
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchToken = UUID()

    /// Zeigt eine entpackte Archiv-Kopie (temporär).
    var isBrowsingArchive: Bool { ArchiveService.isInsideBrowsedArchive(currentURL) }

    /// Tab-Titel: Anzeigename des aktuellen Ordners.
    var title: String {
        currentURL.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: currentURL.path)
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
            items = loaded
            errorMessage = nil
            errorIsPermission = false
            applySort()
            selection.formIntersection(Set(items.map(\.id)))
        } catch {
            items = []
            errorMessage = Self.describe(error, for: currentURL)
            errorIsPermission = Self.isPermissionError(error)
        }
        watchCurrentFolder()
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
        let isNetwork = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
        if isNetwork {
            return "macOS hat Finder-Ersatz den Zugriff auf Netzwerkvolumes nicht erlaubt. Am dauerhaftesten: Finder-Ersatz unter „Festplattenvollzugriff“ einschalten (gilt für alle Laufwerke und bleibt auch nach Neubauten erhalten). Danach die App neu starten. \(code)"
        }
        return "Keine Berechtigung. Ggf. unter Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff erlauben und die App neu starten. \(code)"
    }

    // MARK: Suche

    func startSearch(_ query: SearchQuery) {
        guard !query.isEmpty else { return }
        cancelSearchTask()
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
        reload()
    }

    func closeSearch() {
        isSearchBarVisible = false
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
        items = folders + files
    }
}
