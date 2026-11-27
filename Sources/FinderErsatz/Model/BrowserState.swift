import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers

enum PaneSide: Hashable { case left, right }

/// Dialog vor dem Kopieren/Verschieben (F5/F6): Ziel und ggf. neuer Name sind änderbar.
struct BatchRenameRequest: Identifiable {
    let id = UUID()
    let items: [FileItem]
    /// Direkt im Regex-Modus öffnen (aus dem einfachen Umbenennen-Dialog oder Kontextmenü).
    var startWithRegex = false
}

struct TransferRequest: Identifiable {
    let id = UUID()
    let sources: [URL]
    let move: Bool
    var destinationPath: String
    var newName: String

    var isSingle: Bool { sources.count == 1 }
}

/// Rückfrage, wenn im Ziel schon Objekte mit gleichem Namen liegen.
struct ConflictRequest: Identifiable {
    let id = UUID()
    let title: String
    let items: [TransferItem]
    let conflictNames: [String]
}

enum ConflictResolution { case replace, skip, keepBoth }

/// Gesamtzustand: zwei Seiten mit Tabs, eine davon aktiv.
@MainActor
@Observable
final class BrowserState {
    var left: PaneGroup
    var right: PaneGroup
    var activeSide: PaneSide = .left
    let favorites = FavoritesStore()
    let smartFolders = SmartFolderStore()
    let operations = FileOperationQueue()
    let network = NetworkBrowser()
    let settings = AppSettings()

    /// Fehlermeldung für einen Alert im Hauptfenster.
    var alertMessage: String?

    /// Umbenennen-Dialog
    var renameTarget: FileItem?
    var renameText = ""

        /// Stapel-Umbenennen (mehrere Objekte)
    var batchRenameRequest: BatchRenameRequest?

    /// Kopieren/Verschieben-Dialog und Konfliktabfrage und Konfliktabfrage
    var transferRequest: TransferRequest?
    var conflictRequest: ConflictRequest?

    /// Widerrufen (⌘Z)
    private(set) var undoStack: [UndoableAction] = []
    var undoTitle: String? { undoStack.last.map { "Widerrufen: \($0.title)" } }

    /// „Gehe zu Ordner“ (⇧⌘G)
    var goToFolderVisible = false
    var goToFolderPath = ""

    /// Informationsfenster (⌘I)
    var infoItem: FileItem?

    /// Kurze Rückmeldung in der Aktionsleiste, z. B. „Pfad kopiert“.
    private(set) var flashMessage: String?
    @ObservationIgnored private var flashToken = UUID()

    // Layout-Test (Hilfe → Layout-Test): Teile abschalten, um Ruckeln beim Verkleinern einzugrenzen. Nicht gespeichert.
    var debugHideHeader = false
    var debugHidePathBar = false
    var debugHideViewPicker = false
    var debugHideStatus = false
    var debugHideBottomBars = false
    var debugPlainPaneStack = false
    var debugNoVSplit = false

    var debugFlagsDescription: String {
        let flags: [(Bool, String)] = [
            (debugHideHeader, "Fensterkopf aus"), (debugHidePathBar, "Pfadleiste aus"),
            (debugHideViewPicker, "Ansicht-Auswahl aus"), (debugHideStatus, "Statuszeile aus"),
            (debugHideBottomBars, "Aktionsleiste/Aufträge aus"), (debugPlainPaneStack, "HStack statt HSplitView"),
            (debugNoVSplit, "ohne VSplitView"),
        ]
        let active = flags.filter { $0.0 }.map { $0.1 }
        return active.isEmpty ? "keine" : active.joined(separator: ", ")
    }

    /// Mindestbreite des Fensterinhalts (Seitenleiste + 500 + Vorschau-Spalte), gesetzt von `MainSplitViewController`.
    /// Läuft über SwiftUI (`ContentView.frame(minWidth:)`), weil SwiftUI `contentMinSize` sonst mit eigenem Wert überschreibt.
    var layoutMinWidth: CGFloat = 660

    /// Vorschau-Spalte rechts (⇧⌘P), zeigt das ausgewählte Objekt des aktiven Fensters.
    var showInspector = UserDefaults.standard.bool(forKey: "showInspector") {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }

    /// Vorschaubereich unten in beiden Dateifenstern (⌃⌘P).
    var showPanePreview = UserDefaults.standard.bool(forKey: "showPanePreview") {
        didSet { UserDefaults.standard.set(showPanePreview, forKey: "showPanePreview") }
    }


    /// Für AppleScript: das im Fenster angezeigte BrowserState. Wird in `ContentView.onAppear` gesetzt –
    /// nicht im init, weil SwiftUI den `@State`-Startwert mehrfach erzeugen kann (die Extra-Instanzen verschwinden wieder).
    static weak var current: BrowserState?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        left = PaneGroup(url: home)
        right = PaneGroup(url: home.appending(path: "Downloads"))
        settings.onFolderSizeSettingChanged = { [weak self] in self?.reloadAll() }
        operations.onFinish = { [weak self] error in
            if let error { self?.alertMessage = error }
            self?.reloadAll()
        }
    }

    func group(_ side: PaneSide) -> PaneGroup { side == .left ? left : right }
    func pane(_ side: PaneSide) -> PaneState { group(side).current }

    /// Erstes ausgewähltes Objekt im aktiven Fenster, sonst dessen Ordner.
    /// Wird dem Fenster als „Dokument“ gemeldet (representedURL → AXDocument),
    /// damit Hookmark & Co. es ohne eigenes Skript erkennen.
    var focusedItemURL: URL {
        activePane.selectedItems.first?.url ?? activePane.currentURL
    }

    var activeGroup: PaneGroup { group(activeSide) }
    var activePane: PaneState { activeGroup.current }
    var otherPane: PaneState { group(activeSide == .left ? .right : .left).current }

    func toggleActivePane() { activeSide = activeSide == .left ? .right : .left }

    func syncOtherPane() { otherPane.navigate(to: activePane.currentURL) }

    func swapPanes() {
        let oldLeft = left
        left = right
        right = oldLeft
    }

    func reloadAll() {
        left.current.reload()
        right.current.reload()
    }

    // MARK: Tabs

    func newTab() { activeGroup.newTab() }

    /// Schließt den aktiven Tab. Der letzte Tab einer Seite bleibt offen (Rückgabe `false`).
    @discardableResult
    func closeTab() -> Bool {
        activeGroup.close(activeGroup.selectedID)
    }

    func nextTab() { activeGroup.selectNext() }
    func previousTab() { activeGroup.selectPrevious() }

    /// Öffnet einen Ordner in einem neuen Tab der aktiven Seite.
    func openInNewTab(_ url: URL) { activeGroup.newTab(url: url) }

    // MARK: Öffnen, Schnellansicht, Terminal

    func open(_ item: FileItem, in pane: PaneState) {
        if item.isBrowsableFolder {
            pane.navigate(to: item.url)
        } else if ArchiveService.isArchive(item.url) {
            browseArchive(item.url, in: pane)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Öffnet eine Datei mit der Standard-App (auch Archive, statt sie zu durchsuchen).
    func openWithDefaultApp(_ urls: [URL]) {
        urls.forEach { NSWorkspace.shared.open($0) }
    }

    // MARK: Suche, Ansicht

    func showSearch() {
        activePane.isSearchBarVisible = true
    }

    func setViewMode(_ mode: ViewMode) {
        activePane.viewMode = mode
    }

    // MARK: Archive

    /// Komprimiert die Auswahl als ZIP in den aktuellen Ordner.
    func compressSelection() {
        let pane = activePane
        let sources = pane.selectedItems.map(\.url)
        guard !sources.isEmpty else { return }
        let name = sources.count == 1 ? "\(sources[0].lastPathComponent).zip" : "Archiv.zip"
        let archive = FileService.uniqueURL(for: name, in: pane.currentURL)
        operations.enqueue(title: "Komprimieren: \(archive.lastPathComponent)", onSuccess: {
            pane.reload()
            pane.selection = [archive.normalizedFileURL]
        }) { _ in
            try ArchiveService.compress(sources, to: archive)
        }
    }

    /// Entpackt ausgewählte Archive in je einen eigenen Ordner – hier oder im anderen Fenster.
    func extractSelection(toOtherPane: Bool) {
        let archives = activePane.selectedItems.map(\.url).filter(ArchiveService.isArchive)
        guard !archives.isEmpty else {
            alertMessage = "Bitte ein Archiv auswählen (zip, tar.gz, 7z, rar …)."
            return
        }
        let target = toOtherPane ? otherPane.currentURL : activePane.currentURL
        for archive in archives {
            let folder = FileService.uniqueURL(for: ArchiveService.baseName(of: archive), in: target)
            operations.enqueue(title: "Entpacken: \(archive.lastPathComponent)") { _ in
                try ArchiveService.extract(archive, to: folder)
            }
        }
    }

    /// „Archiv wie Ordner öffnen“: entpackt eine temporäre Kopie und zeigt sie an.
    func browseArchive(_ archive: URL, in pane: PaneState) {
        let folder = ArchiveService.browseFolder(for: archive)
        operations.enqueue(title: "Öffne Archiv: \(archive.lastPathComponent)", onSuccess: {
            pane.navigate(to: folder)
        }) { _ in
            try ArchiveService.extract(archive, to: folder)
        }
    }

    /// Leertaste: bei genau einem Ordner die eigene, schnelle Ordnervorschau (XRay & Co. durchsuchen den ganzen Baum
    /// und brauchen bei großen Ordnern sehr lange), sonst Quick Look. `forceSystemPreview` (⇧-Leertaste, ⌘Y) = immer Quick Look.
    func toggleQuickLook(forceSystemPreview: Bool = false) {
        if folderPreviewURL != nil { folderPreviewURL = nil; return }
        let selected = activePane.selectedItems
        if !forceSystemPreview, !settings.folderPreviewUsesQuickLook, !QuickLookController.shared.isVisible,
           selected.count == 1, selected[0].isBrowsableFolder {
            folderPreviewURL = selected[0].url
            return
        }
        QuickLookController.shared.toggle(selected.map(\.url))
    }

    /// Eigene Ordnervorschau (Leertaste auf Ordner).
    var folderPreviewURL: URL?

    func openTerminal() {
        let folder = activePane.selectedItems.first(where: \.isBrowsableFolder)?.url ?? activePane.currentURL
        AppLauncher.openTerminal(at: folder)
    }

    // MARK: Kopieren / Verschieben

    func copyToOtherPane() { prepareTransfer(move: false) }
    func moveToOtherPane() { prepareTransfer(move: true) }

    private func prepareTransfer(move: Bool) {
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        transferRequest = TransferRequest(
            sources: urls,
            move: move,
            destinationPath: otherPane.currentURL.path,
            newName: urls.count == 1 ? urls[0].lastPathComponent : ""
        )
    }

    /// Bestätigung aus dem F5/F6-Dialog.
    func confirmTransfer(_ request: TransferRequest) {
        transferRequest = nil
        let path = (request.destinationPath as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            alertMessage = "Der Zielordner „\(path)“ existiert nicht."
            return
        }
        let folder = URL(filePath: path).normalizedFileURL
        let name = request.newName.trimmingCharacters(in: .whitespaces)
        let items = request.sources.map { source in
            let targetName = request.isSingle && !name.isEmpty ? name : source.lastPathComponent
            return TransferItem(source: source, destination: folder.appending(path: targetName), move: request.move)
        }
        if items.contains(where: { $0.source.normalizedFileURL == $0.destination.normalizedFileURL }) {
            alertMessage = "Quelle und Ziel sind identisch."
            return
        }
        let verb = request.move ? "Verschieben" : "Kopieren"
        enqueue(title: "\(verb) nach „\(folder.lastPathComponent)“", items: items)
    }

    /// Drag & Drop: gleiches Volume → verschieben, anderes Volume → kopieren (wie im Finder).
    func drop(_ urls: [URL], into pane: PaneState) -> Bool {
        let folder = pane.currentURL
        let sources = urls.filter { $0.deletingLastPathComponent().normalizedFileURL != folder }
        guard !sources.isEmpty else { return false }
        let items = sources.map {
            TransferItem(source: $0, destination: folder.appending(path: $0.lastPathComponent),
                         move: FileService.sameVolume($0, folder))
        }
        enqueue(title: "Ablegen in „\(folder.lastPathComponent)“", items: items)
        return true
    }

    /// Prüft auf Namenskonflikte und startet den Auftrag – oder fragt vorher nach.
    private func enqueue(title: String, items: [TransferItem]) {
        let conflicts = items.filter { FileManager.default.fileExists(atPath: $0.destination.path) }
        if conflicts.isEmpty {
            enqueueRecordingUndo(title: title, items: items)
        } else {
            conflictRequest = ConflictRequest(title: title, items: items,
                                              conflictNames: conflicts.map(\.destination.lastPathComponent))
        }
    }

    func resolveConflicts(_ resolution: ConflictResolution) {
        guard let request = conflictRequest else { return }
        conflictRequest = nil
        let fm = FileManager.default
        let items: [TransferItem] = request.items.compactMap { item in
            guard fm.fileExists(atPath: item.destination.path) else { return item }
            var resolved = item
            switch resolution {
            case .replace:
                resolved.replaceExisting = true
            case .skip:
                return nil
            case .keepBoth:
                resolved.destination = FileService.uniqueURL(
                    for: item.destination.lastPathComponent,
                    in: item.destination.deletingLastPathComponent()
                )
            }
            return resolved
        }
        enqueueRecordingUndo(title: request.title, items: items)
    }

    /// Startet Kopieren/Bewegen und merkt sich danach, wie es rückgängig zu machen ist.
    private func enqueueRecordingUndo(title: String, items: [TransferItem]) {
        operations.enqueue(title: title, items: items, onSuccess: { [weak self] in
            let moved = items.filter(\.move).map { (from: $0.source, to: $0.destination) }
            let created = items.filter { !$0.move }.map(\.destination)
            if !moved.isEmpty { self?.recordUndo(.moved(moved)) }
            if !created.isEmpty { self?.recordUndo(.created(created)) }
        })
    }

    // MARK: Netzwerk

    /// Verbindet mit einem Server/einer Freigabe und öffnet sie danach im aktiven Fenster.
    func connect(to url: URL) {
        NetworkMounter.mount(url) { [weak self] mounted, error in
            guard let self else { return }
            if let error {
                self.alertMessage = error
            } else if let first = mounted.first {
                self.activePane.navigate(to: first)
            }
        }
    }

    // MARK: Widerrufen

    func recordUndo(_ action: UndoableAction) {
        undoStack.append(action)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let action = undoStack.popLast() else { NSSound.beep(); return }
        run { try action.revert() }
    }

    // MARK: Zwischenablage (wie im Finder)

    /// ⌘C: ausgewählte Objekte als Dateien in die Zwischenablage.
    func copySelectionToPasteboard() {
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    /// ⌘V kopiert, ⌥⌘V bewegt die Dateien aus der Zwischenablage in den aktuellen Ordner.
    func pasteFromPasteboard(move: Bool) {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                     options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { NSSound.beep(); return }
        let folder = activePane.currentURL
        let items = urls.map { source -> TransferItem in
            var destination = folder.appending(path: source.lastPathComponent)
            // Einsetzen im selben Ordner = Duplikat mit freiem Namen
            if !move, source.deletingLastPathComponent().normalizedFileURL == folder {
                destination = FileService.uniqueURL(for: source.lastPathComponent, in: folder)
            }
            return TransferItem(source: source, destination: destination, move: move)
        }.filter { $0.source.normalizedFileURL != $0.destination.normalizedFileURL }
        guard !items.isEmpty else { return }
        enqueue(title: move ? "Bewegen nach „\(folder.lastPathComponent)“" : "Einsetzen in „\(folder.lastPathComponent)“", items: items)
    }

    /// ⌥⌘C: Pfade der Auswahl (oder des Ordners) als Text kopieren.
    func copyPathsToPasteboard() {
        let paths = activePane.selectedItems.map(\.url.path)
        let text = (paths.isEmpty ? [activePane.currentURL.path] : paths).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(paths.count > 1 ? "\(paths.count) Pfade kopiert" : "Pfad kopiert: \(text)")
    }

    /// Kurze Rückmeldung in der Aktionsleiste (verschwindet nach 2,5 s).
    func flash(_ message: String) {
        flashMessage = message
        let token = UUID()
        flashToken = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if self?.flashToken == token { self?.flashMessage = nil }
        }
    }

    func selectAll() {
        activePane.selection = Set(activePane.items.map(\.id))
    }

    // MARK: Duplizieren, Alias, Öffnen mit, Paketinhalt, Gehe zu

    func duplicateSelection() {
        let pane = activePane
        let urls = pane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        run {
            var created: [URL] = []
            defer { if !created.isEmpty { recordUndo(.created(created)) } }
            for url in urls { created.append(try FileService.duplicate(url)) }
            pane.reload()
            pane.selection = Set(created.map(\.normalizedFileURL))
        }
    }

    func makeAliasForSelection() {
        let pane = activePane
        let urls = pane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        run {
            var created: [URL] = []
            defer { if !created.isEmpty { recordUndo(.created(created)) } }
            for url in urls { created.append(try FileService.makeAlias(url)) }
            pane.reload()
            pane.selection = Set(created.map(\.normalizedFileURL))
        }
    }

    /// Apps, die die Datei öffnen können; Standard-App zuerst.
    func applications(toOpen url: URL) -> [URL] {
        let all = NSWorkspace.shared.urlsForApplications(toOpen: url)
        guard let preferred = NSWorkspace.shared.urlForApplication(toOpen: url) else { return all }
        return [preferred] + all.filter { $0.normalizedFileURL != preferred.normalizedFileURL }
    }

    func open(_ urls: [URL], with application: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }

    /// „Andere …“: App per Dialog wählen.
    func open(_ urls: [URL], choosingApplication: Bool) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Öffnen"
        if panel.runModal() == .OK, let app = panel.url { open(urls, with: app) }
    }

    func showPackageContents(_ url: URL) {
        activePane.navigate(to: url)
    }

    func showGoToFolder() {
        goToFolderPath = activePane.currentURL.path
        goToFolderVisible = true
    }

    func commitGoToFolder() {
        goToFolderVisible = false
        let path = (goToFolderPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            alertMessage = "„\(path)“ wurde nicht gefunden."
            return
        }
        let url = URL(filePath: path).normalizedFileURL
        if isDir.boolValue {
            activePane.navigate(to: url)
        } else {
            activePane.navigate(to: url.deletingLastPathComponent())
            activePane.selection = [url]
        }
    }

    // MARK: Informationen, Tags

    func showInfo() {
        infoItem = activePane.selectedItems.first ?? FileItem(url: activePane.currentURL)
    }

    /// Schaltet einen Farb-Tag für alle ausgewählten Objekte um.
    func toggleTag(_ tag: FinderTag, for items: [FileItem]) {
        guard !items.isEmpty else { return }
        let add = !items.allSatisfy { tag.isContained(in: $0.tagList) }
        run {
            for item in items {
                var tags = item.tagList.filter { !tag.isContained(in: [$0]) }
                if add { tags.append(tag.rawValue) }
                try FileService.setTags(tags, for: item.url)
            }
        }
    }

    func removeAllTags(for items: [FileItem]) {
        run { for item in items { try FileService.setTags([], for: item.url) } }
    }

    // MARK: Weitere Dateioperationen

    func trashSelection() {
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        run {
            var pairs: [(original: URL, inTrash: URL)] = []
            defer { if !pairs.isEmpty { recordUndo(.trashed(pairs)) } }
            for url in urls {
                if let inTrash = try FileService.trash(url) { pairs.append((original: url, inTrash: inTrash)) }
            }
        }
    }

    func newFolder() {
        let pane = activePane
        run {
            let url = try FileService.createFolder(in: pane.currentURL)
            recordUndo(.created([url]))
            pane.reload()
            pane.selection = [url.normalizedFileURL]
        }
    }

    func beginRename() {
        let selected = activePane.selectedItems
        if selected.count > 1 {
            beginBatchRename()
            return
        }
        guard let item = selected.first else { return }
        renameTarget = item
        renameText = item.name
    }

    func commitRename() {
        guard let item = renameTarget else { return }
        renameTarget = nil
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != item.name else { return }
        let pane = activePane
        run {
            let url = try FileService.rename(item.url, to: newName)
            recordUndo(.rename(from: item.url, to: url))
            pane.reload()
            pane.selection = [url.normalizedFileURL]
        }
    }

    // MARK: Stapel-Umbenennen

    func beginBatchRename(regex: Bool = false) {
        let selected = activePane.selectedItems
        guard !selected.isEmpty else { NSSound.beep(); return }
        renameTarget = nil
        batchRenameRequest = BatchRenameRequest(items: selected, startWithRegex: regex)
    }

    /// Benennt mehrere Objekte um. Zuerst auf vorläufige Namen, damit sich Ziel- und Quellnamen nicht in die Quere kommen
    /// (z. B. „Bild 1“ → „Bild 2“ und „Bild 2“ → „Bild 3“). Als ein Schritt widerrufbar.
    func applyBatchRename(_ renames: [(url: URL, newName: String)]) {
        let pane = activePane
        let changes = renames.filter { $0.url.lastPathComponent != $0.newName }
        guard !changes.isEmpty else { return }
        run {
            let fm = FileManager.default
            // Schritt 1: vorläufige Namen
            var temporary: [(original: URL, temp: URL, newName: String)] = []
            do {
                for change in changes {
                    let temp = try FileService.rename(change.url, to: ".umbenennen-\(UUID().uuidString)")
                    temporary.append((change.url, temp, change.newName))
                }
            } catch {
                for entry in temporary.reversed() { try? fm.moveItem(at: entry.temp, to: entry.original) }
                throw error
            }
            // Schritt 2: endgültige Namen
            var done: [(from: URL, to: URL)] = []
            for (index, entry) in temporary.enumerated() {
                do {
                    let final = try FileService.rename(entry.temp, to: entry.newName)
                    done.append((entry.original, final))
                } catch {
                    // Rest zurück auf die alten Namen, Erledigtes bleibt widerrufbar.
                    for rest in temporary[index...] { try? fm.moveItem(at: rest.temp, to: rest.original) }
                    if !done.isEmpty { recordUndo(.moved(done)) }
                    throw error
                }
            }
            recordUndo(.moved(done))
            pane.reload()
            pane.selection = Set(done.map { $0.to.normalizedFileURL })
        }
    }

    // MARK: Zuletzt benutzt, Tags, intelligente Ordner

    func showRecents() {
        showQuery(.recents, sortOrder: [KeyPathComparator(\FileItem.accessed, order: .reverse)])
    }

    func showTag(_ name: String, alternative: String? = nil) {
        showQuery(.tagged(name, alternative: alternative))
    }

    /// „Suche sichern“: Name abfragen (Dialog in ContentView), dann als intelligenten Ordner speichern.
    var saveSearchName = ""
    var saveSearchQuery: SearchQuery?

    func requestSaveSearch() {
        let pane = activePane
        guard let query = pane.activeSearch ?? pane.lastSearch else {
            NSSound.beep(); return
        }
        saveSearchQuery = query
        saveSearchName = query.title ?? (query.term.isEmpty ? query.contentText : query.term)
    }

    func commitSaveSearch() {
        guard let query = saveSearchQuery else { return }
        saveSearchQuery = nil
        let name = saveSearchName.trimmingCharacters(in: .whitespaces)
        smartFolders.add(name: name.isEmpty ? "Suche" : name, query: query)
    }

    func showSmartFolder(_ folder: SmartFolder) {
        showQuery(folder.displayQuery)
    }

    /// Intelligenten Ordner mit geöffneter Suchleiste zeigen, damit sich die Kriterien ändern lassen.
    func editSmartFolder(_ folder: SmartFolder) {
        let pane = activePane
        pane.startSearch(folder.displayQuery)
        pane.editingSmartFolder = folder.id
        pane.searchBarResetToken = UUID()
        pane.isSearchBarVisible = true
    }

    /// Neue Suche wie im Finder: Suchleiste mit „Dieser Mac“ und einer ersten Bedingungszeile.
    func newFinderSearch() {
        let pane = activePane
        var query = SearchQuery(root: pane.currentURL)
        query.scope = .thisMac
        query.criteria = [SearchCriterion(attribute: .kind)]
        pane.closeSearch()
        pane.lastSearch = query
        pane.searchBarResetToken = UUID()
        pane.isSearchBarVisible = true
    }

    /// Zeigt das Ergebnis einer Abfrage im aktiven Fenster (ohne Suchleiste).
    func showQuery(_ query: SearchQuery, sortOrder: [KeyPathComparator<FileItem>]? = nil) {
        let pane = activePane
        pane.isSearchBarVisible = false
        pane.editingSmartFolder = nil
        pane.startSearch(query, sortOrder: sortOrder)
    }

    /// Ausgewählte Ordner – oder, ohne Auswahl, den aktuellen Ordner – zu den Favoriten hinzufügen.
    func addSelectionToFavorites() {
        let folders = activePane.selectedItems.filter(\.isBrowsableFolder).map(\.url)
        favorites.add(folders.isEmpty ? [activePane.currentURL] : folders)
    }

    func revealInFinder() {
        let urls = activePane.selectedItems.map(\.url)
        if urls.isEmpty {
            NSWorkspace.shared.open(activePane.currentURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    /// Führt eine schnelle Operation direkt aus, zeigt Fehler an und lädt beide Fenster neu.
    private func run(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            alertMessage = error.localizedDescription
        }
        reloadAll()
    }
}
