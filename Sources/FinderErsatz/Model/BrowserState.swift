import Foundation
import AppKit
import Observation

enum PaneSide: Hashable { case left, right }

/// Dialog vor dem Kopieren/Verschieben (F5/F6): Ziel und ggf. neuer Name sind änderbar.
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
    let operations = FileOperationQueue()

    /// Fehlermeldung für einen Alert im Hauptfenster.
    var alertMessage: String?

    /// Umbenennen-Dialog
    var renameTarget: FileItem?
    var renameText = ""

    /// Kopieren/Verschieben-Dialog und Konfliktabfrage
    var transferRequest: TransferRequest?
    var conflictRequest: ConflictRequest?

    /// Schnellansicht (Quick Look)
    var previewURL: URL?
    var previewItems: [URL] = []

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        left = PaneGroup(url: home)
        right = PaneGroup(url: home.appending(path: "Downloads"))
        operations.onFinish = { [weak self] error in
            if let error { self?.alertMessage = error }
            self?.reloadAll()
        }
    }

    func group(_ side: PaneSide) -> PaneGroup { side == .left ? left : right }
    func pane(_ side: PaneSide) -> PaneState { group(side).current }

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

    /// Schließt den aktiven Tab; beim letzten Tab wird das Fenster geschlossen.
    func closeTabOrWindow() {
        if !activeGroup.close(activeGroup.selectedID) {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    func nextTab() { activeGroup.selectNext() }
    func previousTab() { activeGroup.selectPrevious() }

    /// Öffnet einen Ordner in einem neuen Tab der aktiven Seite.
    func openInNewTab(_ url: URL) { activeGroup.newTab(url: url) }

    // MARK: Öffnen, Schnellansicht, Terminal

    func open(_ item: FileItem, in pane: PaneState) {
        if item.isBrowsableFolder {
            pane.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func toggleQuickLook() {
        if previewURL != nil {
            previewURL = nil
            return
        }
        let urls = activePane.selectedItems.map(\.url)
        guard let first = urls.first else { return }
        previewItems = urls
        previewURL = first
    }

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
            operations.enqueue(title: title, items: items)
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
        operations.enqueue(title: request.title, items: items)
    }

    // MARK: Weitere Dateioperationen

    func trashSelection() {
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        run { try urls.forEach(FileService.trash) }
    }

    func newFolder() {
        let pane = activePane
        run {
            let url = try FileService.createFolder(in: pane.currentURL)
            pane.reload()
            pane.selection = [url.normalizedFileURL]
        }
    }

    func beginRename() {
        guard let item = activePane.selectedItems.first else { return }
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
            pane.reload()
            pane.selection = [url.normalizedFileURL]
        }
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
