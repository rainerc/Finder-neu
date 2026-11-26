import Foundation

/// Einfaches „Widerrufen“ für Dateioperationen (⌘Z).
enum UndoableAction {
    case rename(from: URL, to: URL)
    case moved([(from: URL, to: URL)])
    case trashed([(original: URL, inTrash: URL)])
    case created([URL])

    var title: String {
        switch self {
        case .rename: "Umbenennen"
        case .moved: "Bewegen"
        case .trashed: "In den Papierkorb legen"
        case .created: "Erstellen"
        }
    }

    /// Macht die Aktion rückgängig.
    func revert() throws {
        let fm = FileManager.default
        switch self {
        case let .rename(from, to):
            try fm.moveItem(at: to, to: from)
        case let .moved(pairs):
            for pair in pairs.reversed() { try fm.moveItem(at: pair.to, to: pair.from) }
        case let .trashed(pairs):
            for pair in pairs.reversed() { try fm.moveItem(at: pair.inTrash, to: pair.original) }
        case let .created(urls):
            // Erstelltes nicht endgültig löschen, sondern in den Papierkorb.
            for url in urls where fm.fileExists(atPath: url.path) { try FileService.trash(url) }
        }
    }
}
