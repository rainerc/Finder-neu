import Foundation
import AppKit
import Observation

enum PaneSide: Hashable { case left, right }

/// Gesamtzustand: zwei Fenster, eines davon aktiv.
@MainActor
@Observable
final class BrowserState {
    var left: PaneState
    var right: PaneState
    var activeSide: PaneSide = .left
    let favorites = FavoritesStore()

    /// Fehlermeldung für einen Alert im Hauptfenster.
    var alertMessage: String?

    /// Umbenennen-Dialog
    var renameTarget: FileItem?
    var renameText = ""

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        left = PaneState(url: home)
        right = PaneState(url: home.appending(path: "Downloads"))
    }

    var activePane: PaneState { activeSide == .left ? left : right }
    var otherPane: PaneState { activeSide == .left ? right : left }

    func pane(_ side: PaneSide) -> PaneState { side == .left ? left : right }

    func toggleActivePane() { activeSide = activeSide == .left ? .right : .left }

    func syncOtherPane() { otherPane.navigate(to: activePane.currentURL) }

    func swapPanes() {
        let oldLeft = left
        left = right
        right = oldLeft
    }

    func reloadAll() {
        left.reload()
        right.reload()
    }

    // MARK: Dateioperationen

    func open(_ item: FileItem, in pane: PaneState) {
        if item.isBrowsableFolder {
            pane.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func copyToOtherPane() { transfer(move: false) }
    func moveToOtherPane() { transfer(move: true) }

    private func transfer(move: Bool) {
        let source = activePane, target = otherPane
        let urls = source.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        guard source.currentURL != target.currentURL else {
            alertMessage = "Quelle und Ziel sind derselbe Ordner."
            return
        }
        run {
            for url in urls {
                if move {
                    try FileService.move(url, into: target.currentURL)
                } else {
                    try FileService.copy(url, into: target.currentURL)
                }
            }
        }
    }

    /// Drag & Drop: gleiches Volume → verschieben, anderes Volume → kopieren (wie im Finder).
    func drop(_ urls: [URL], into pane: PaneState) -> Bool {
        let target = pane.currentURL
        let sources = urls.filter { $0.deletingLastPathComponent().normalizedFileURL != target }
        guard !sources.isEmpty else { return false }
        run {
            for url in sources {
                if FileService.sameVolume(url, target) {
                    try FileService.move(url, into: target)
                } else {
                    try FileService.copy(url, into: target)
                }
            }
        }
        return true
    }

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

    /// Führt eine Operation aus, zeigt Fehler an und lädt beide Fenster neu.
    private func run(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            alertMessage = error.localizedDescription
        }
        reloadAll()
    }
}
