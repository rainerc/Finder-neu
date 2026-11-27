import SwiftUI
import AppKit

/// Alle Befehle, deren Tastenkürzel man in den Einstellungen ändern kann.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case newTab, newFolder, newFile, copy, move, rename, quickLook, systemQuickLook, trash, compress, extractHere, extractToOther
    case copyFiles, pasteFiles, moveFilesHere, duplicate, makeAlias, copyPath, copyNames, getInfo, goToFolder, selectAll, undo
    case selectPattern, deselectPattern, deselectAll, invertSelection, selectSameExtension
    case search, newSmartFolder, saveSearch, reveal, terminal, batchRename, recents
    case back, forward, up, switchPane, nextTab, previousTab, syncPanes, swapPanes, addFavorite, connectServer
    case compareFolders, markDifferences, quickFilter, branchView, compareFiles, findDuplicates
    case favoritesMenu, restoreSelection, syncBrowsing, checksums, viewer, packageContents
    case commandLine, toggleButtonBar, actionLog, renameInEditor, viewTree
    case showOnlySelected, changeAttributes, splitFile, joinFiles, packArchive, listArchive, connectRemote
    case addToDropStack, toggleDropStack, toggleDropShelf
    case viewList, viewBrief, viewIcons, viewColumns, viewGallery, toggleSidebar, toggleInspector, togglePanePreview, toggleHidden, reload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: "Neuer Tab"
        case .newFolder: "Neuer Ordner"
        case .newFile: "Neue Textdatei"
        case .copy: "In anderes Fenster kopieren"
        case .move: "In anderes Fenster verschieben"
        case .rename: "Umbenennen"
        case .quickLook: "Schnellansicht"
        case .systemQuickLook: "Quick Look mit XRay (auch Ordner)"
        case .trash: "In den Papierkorb"
        case .compress: "Als ZIP komprimieren"
        case .extractHere: "Entpacken (hierher)"
        case .extractToOther: "Entpacken ins andere Fenster"
        case .copyFiles: "Kopieren (Zwischenablage)"
        case .pasteFiles: "Einsetzen"
        case .moveFilesHere: "Objekt hierher bewegen"
        case .duplicate: "Duplizieren"
        case .makeAlias: "Alias erstellen"
        case .copyPath: "Pfad kopieren"
        case .copyNames: "Name(n) kopieren"
        case .selectPattern: "Auswählen …"
        case .deselectPattern: "Auswahl aufheben …"
        case .deselectAll: "Nichts auswählen"
        case .invertSelection: "Auswahl umkehren"
        case .selectSameExtension: "Alle mit derselben Endung auswählen"
        case .getInfo: "Informationen"
        case .goToFolder: "Gehe zu Ordner …"
        case .selectAll: "Alles auswählen"
        case .undo: "Widerrufen"
        case .search: "Suchen"
        case .newSmartFolder: "Neuer intelligenter Ordner"
        case .saveSearch: "Suche als intelligenten Ordner sichern"
        case .batchRename: "Mehrere umbenennen …"
        case .recents: "Zuletzt benutzt"
        case .reveal: "Im Finder zeigen"
        case .terminal: "Terminal hier öffnen"
        case .back: "Zurück"
        case .forward: "Vorwärts"
        case .up: "Übergeordneter Ordner"
        case .switchPane: "Fenster wechseln"
        case .nextTab: "Nächster Tab"
        case .previousTab: "Vorheriger Tab"
        case .syncPanes: "Anderes Fenster auf gleichen Ordner"
        case .swapPanes: "Fenster tauschen"
        case .compareFolders: "Verzeichnisse vergleichen …"
        case .markDifferences: "Unterschiede markieren"
        case .quickFilter: "Schnellfilter"
        case .branchView: "Zweigansicht (alle Dateien aus Unterordnern)"
        case .compareFiles: "Dateien nach Inhalt vergleichen …"
        case .findDuplicates: "Doppelte Dateien suchen …"
        case .favoritesMenu: "Favoriten-Menü"
        case .restoreSelection: "Auswahl wiederherstellen"
        case .syncBrowsing: "Synchrones Blättern"
        case .checksums: "Prüfsummen …"
        case .viewer: "Betrachter (Text/Hex)"
        case .packageContents: "Paketinhalt anzeigen"
        case .commandLine: "Befehlszeile"
        case .toggleButtonBar: "Knopfleiste ein-/ausblenden"
        case .actionLog: "Protokoll der Dateiaktionen …"
        case .renameInEditor: "Im Texteditor umbenennen …"
        case .viewTree: "Ansicht: Ordnerbaum"
        case .showOnlySelected: "Nur Ausgewähltes anzeigen"
        case .changeAttributes: "Attribute ändern …"
        case .splitFile: "Datei aufteilen …"
        case .joinFiles: "Dateien zusammenfügen …"
        case .packArchive: "Packen …"
        case .listArchive: "Archivinhalt auflisten"
        case .connectRemote: "FTP/SFTP-Verbindung …"
        case .addToDropStack: "Zur Sammelablage hinzufügen"
        case .toggleDropStack: "Sammelablage ein-/ausblenden"
        case .toggleDropShelf: "Schwebende Ablage zeigen/ausblenden"
        case .addFavorite: "Zu Favoriten hinzufügen"
        case .connectServer: "Mit Server verbinden"
        case .viewList: "Ansicht: Liste"
        case .viewBrief: "Ansicht: Kurz"
        case .viewIcons: "Ansicht: Miniaturen"
        case .viewColumns: "Ansicht: Spalten"
        case .viewGallery: "Ansicht: Galerie"
        case .toggleSidebar: "Seitenleiste ein-/ausblenden"
        case .toggleInspector: "Vorschau-Spalte rechts"
        case .togglePanePreview: "Vorschaubereich unten"
        case .toggleHidden: "Unsichtbare Dateien ein/aus"
        case .reload: "Aktualisieren"
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .newTab: Shortcut("t", .command)
        case .newFolder: Shortcut("n", [.command, .shift])
        case .newFile: Shortcut("n", [.control, .shift, .command])
        case .copy: Shortcut(functionKey: 5)
        case .move: Shortcut(functionKey: 6)
        case .rename: Shortcut(functionKey: 2)
        case .quickLook: Shortcut(functionKey: 3)
        case .systemQuickLook: Shortcut("y", .command)
        case .trash: Shortcut(Shortcut.deleteKey, .command)
        case .compress: nil
        case .extractHere: nil
        case .extractToOther: nil
        case .copyFiles: Shortcut("c", .command)
        case .pasteFiles: Shortcut("v", .command)
        case .moveFilesHere: Shortcut("v", [.command, .option])
        case .duplicate: Shortcut("d", .command)
        case .makeAlias: Shortcut("a", [.control, .command])
        case .copyPath: Shortcut("c", [.command, .option])
        case .copyNames: Shortcut("c", [.command, .control, .shift])
        case .selectPattern: Shortcut("+", .command)
        case .deselectPattern: Shortcut("-", .command)
        case .deselectAll: Shortcut("a", [.command, .shift])
        case .invertSelection: Shortcut("i", [.command, .shift])
        case .selectSameExtension: Shortcut("e", [.command, .control])
        case .getInfo: Shortcut("i", .command)
        case .goToFolder: Shortcut("g", [.command, .shift])
        case .selectAll: Shortcut("a", .command)
        case .undo: Shortcut("z", .command)
        case .search: Shortcut("f", .command)
        case .newSmartFolder: Shortcut("n", [.control, .command])
        case .saveSearch: nil
        case .batchRename: Shortcut(functionKey: 2, .shift)
        case .recents: Shortcut("f", [.command, .shift])
        case .reveal: Shortcut("r", [.command, .option])
        case .terminal: Shortcut("t", [.command, .option])
        case .back: Shortcut("[", .command)
        case .forward: Shortcut("]", .command)
        case .up: Shortcut(Shortcut.upArrowKey, .command)
        case .switchPane: Shortcut("\t", .option)
        case .nextTab: Shortcut("\t", .control)
        case .previousTab: Shortcut("\t", [.control, .shift])
        case .syncPanes: Shortcut("=", .command)
        case .swapPanes: Shortcut("u", .command)
        case .compareFolders: Shortcut("d", [.command, .shift])
        case .markDifferences: Shortcut("d", [.command, .control])
        case .quickFilter: Shortcut("j", .command)
        case .branchView: Shortcut("b", [.command, .control])
        case .compareFiles: Shortcut("d", [.command, .control, .shift])
        case .findDuplicates: nil
        case .favoritesMenu: Shortcut("g", [.command, .control])
        case .restoreSelection: Shortcut("r", [.command, .control])
        case .syncBrowsing: Shortcut("y", [.command, .control])
        case .checksums: Shortcut("k", [.command, .control])
        case .viewer: Shortcut(functionKey: 3, .shift)
        case .packageContents: Shortcut("o", [.command, .control])
        case .commandLine: Shortcut("x", [.command, .control])
        case .toggleButtonBar: nil
        case .actionLog: Shortcut("l", [.command, .control, .shift])
        case .renameInEditor: Shortcut(functionKey: 2, .control)
        case .viewTree: Shortcut("6", .command)
        case .showOnlySelected: Shortcut("i", [.command, .control])
        case .changeAttributes: nil
        case .splitFile: nil
        case .joinFiles: nil
        case .packArchive: Shortcut(functionKey: 5, .control)
        case .listArchive: nil
        case .connectRemote: Shortcut("k", [.command, .control, .shift])
        case .addToDropStack: Shortcut("j", [.command, .control])
        case .toggleDropStack: Shortcut("j", [.command, .control, .shift])
        case .toggleDropShelf: nil
        case .addFavorite: Shortcut("t", [.control, .command])
        case .connectServer: Shortcut("k", .command)
        case .viewList: Shortcut("1", .command)
        case .viewBrief: Shortcut("2", .command)
        case .viewIcons: Shortcut("3", .command)
        case .viewColumns: Shortcut("4", .command)
        case .viewGallery: Shortcut("5", .command)
        case .toggleSidebar: Shortcut("s", [.control, .command])
        case .toggleInspector: Shortcut("p", [.command, .shift])
        case .togglePanePreview: Shortcut("p", [.command, .control])
        case .toggleHidden: Shortcut(".", [.command, .shift])
        case .reload: Shortcut("r", .command)
        }
    }
}

/// Ein Tastenkürzel: Taste (als Zeichen, Sondertasten als Unicode-Funktionstasten-Code) + Modifier.
struct Shortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt   // NSEvent.ModifierFlags.rawValue (nur ⌘⌥⌃⇧)

    static let deleteKey = "\u{8}"
    static let upArrowKey = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
    }

    init(functionKey number: Int, _ modifiers: NSEvent.ModifierFlags = []) {
        self.init(String(Character(UnicodeScalar(NSF1FunctionKey + number - 1)!)), modifiers)
    }

    /// Aus einem Tastendruck (Aufnahme in den Einstellungen).
    init?(event: NSEvent) {
        guard let raw = event.characters(byApplyingModifiers: [])?.lowercased(), let first = raw.first else { return nil }
        var key = String(first)
        if key == "\u{7F}" { key = Shortcut.deleteKey }   // Rückschritttaste
        self.init(key, event.modifierFlags)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var keyboardShortcut: KeyboardShortcut {
        var mods: EventModifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: mods)
    }

    /// Anzeige wie in macOS-Menüs, z. B. „⇧⌘N“ oder „F5“.
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(key)
    }

    private static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return key }
        let value = Int(scalar.value)
        if value >= NSF1FunctionKey && value <= NSF35FunctionKey { return "F\(value - NSF1FunctionKey + 1)" }
        switch value {
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case 0x8, 0x7F: return "⌫"
        case 0x9: return "⇥"
        case 0xD: return "↩"
        case 0x1B: return "⎋"
        case 0x20: return "Leertaste"
        default: return key.uppercased()
        }
    }
}
