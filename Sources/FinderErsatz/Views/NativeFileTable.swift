import SwiftUI
import AppKit

/// Listenansicht als native `NSTableView` (wie im Finder).
///
/// Grund: SwiftUIs `Table` baut bei jeder Breitenänderung jede sichtbare Zelle neu auf (bei Rainer ~2 ms pro Zeile,
/// Fenster-Verkleinern ruckelte mit ~100 ms pro Schritt). AppKit-Zellen sind dagegen sehr billig.
struct NativeFileTable: NSViewRepresentable {
    enum Key { case tab, space, returnKey, backspace }

    struct Style: Equatable {
        var listSize: AppSettings.ListSize
        var alternatingRows: Bool
        var folderColor: NSColor?
        var dimHidden: Bool
    }

    let items: [FileItem]
    @Binding var selection: Set<FileItem.ID>
    @Binding var sortOrder: [KeyPathComparator<FileItem>]
    let searching: Bool
    /// Ändert sich beim Ordnerwechsel → Liste springt nach oben
    let contentKey: String
    let relativeFolder: (FileItem) -> String
    let style: Style
    let isActive: Bool
    let onActivate: () -> Void
    let onOpen: (Set<FileItem.ID>) -> Void
    let menu: (Set<FileItem.ID>) -> [MenuEntry]
    /// Liefert true, wenn die Taste verarbeitet wurde
    let onKey: (Key, NSEvent.ModifierFlags) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = FileTableView()
        table.coordinator = coordinator
        table.style = .inset
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsColumnSelection = false
        table.allowsTypeSelect = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.intercellSpacing = NSSize(width: 8, height: 0)

        for column in FileColumn.all {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.minWidth = column.minWidth
            tableColumn.width = column.width
            tableColumn.isHidden = column.hiddenByDefault
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.id, ascending: true)
            if column.alignRight { tableColumn.headerCell.alignment = .right }
            table.addTableColumn(tableColumn)
        }
        // Reihenfolge, Breite und Sichtbarkeit der Spalten merkt sich AppKit (beide Fenster gemeinsam)
        table.autosaveName = "FileListColumns"
        table.autosaveTableColumns = true

        let headerMenu = NSMenu()
        headerMenu.delegate = coordinator
        table.headerView?.menu = headerMenu

        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        coordinator.tableView = table
        coordinator.apply(self, initial: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.apply(self, initial: false)
    }

    /// Nimmt einfach den angebotenen Platz – sonst misst SwiftUI bei jedem Layout-Durchgang die AppKit-Ansicht aus.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? 300)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: NativeFileTable
        weak var tableView: FileTableView?
        private var items: [FileItem] = []
        private var style: Style?
        private var searching = false
        private var contentKey = ""
        private var wasActive = false
        private var isSyncing = false

        init(parent: NativeFileTable) {
            self.parent = parent
        }

        var selectedIDs: Set<FileItem.ID> {
            guard let tableView else { return [] }
            return Set(tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].id : nil })
        }

        /// Übernimmt den Zustand aus SwiftUI (Objekte, Auswahl, Sortierung, Darstellung).
        func apply(_ parent: NativeFileTable, initial: Bool) {
            self.parent = parent
            guard let tableView else { return }
            isSyncing = true
            defer { isSyncing = false }

            var needsReload = false
            if parent.style != style || parent.searching != searching {
                style = parent.style
                searching = parent.searching
                tableView.usesAlternatingRowBackgroundColors = parent.style.alternatingRows
                tableView.rowHeight = Self.rowHeight(for: parent.style.listSize, searching: parent.searching)
                needsReload = true
            }
            if parent.items != items {
                items = parent.items
                needsReload = true
            }
            if needsReload { tableView.reloadData() }

            if parent.contentKey != contentKey {
                contentKey = parent.contentKey
                if !initial, !items.isEmpty { tableView.scrollRowToVisible(0) }
            }

            // Sortierung → Pfeil im Spaltenkopf
            if let comparator = parent.sortOrder.first, let key = FileColumn.key(for: comparator) {
                let ascending = comparator.order == .forward
                let current = tableView.sortDescriptors.first
                if current?.key != key || current?.ascending != ascending {
                    tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
                }
            }

            // Auswahl
            var wanted = IndexSet()
            if !parent.selection.isEmpty {
                for (index, item) in items.enumerated() where parent.selection.contains(item.id) { wanted.insert(index) }
            }
            if wanted != tableView.selectedRowIndexes {
                tableView.selectRowIndexes(wanted, byExtendingSelection: false)
                if let first = wanted.first { tableView.scrollRowToVisible(first) }
            }

            // Aktives Fenster bekommt den Tastaturfokus (z. B. nach ⇥), außer jemand tippt gerade in einem Textfeld
            if parent.isActive && !wasActive {
                Task { @MainActor [weak tableView] in
                    guard let tableView, let window = tableView.window else { return }
                    if window.firstResponder is NSText { return }
                    if window.firstResponder !== tableView { window.makeFirstResponder(tableView) }
                }
            }
            wasActive = parent.isActive
        }

        static func rowHeight(for size: AppSettings.ListSize, searching: Bool) -> CGFloat {
            let font = FileColumn.font(for: size)
            let line = ceil(font.ascender - font.descender + font.leading)
            let base = max(size.iconSize, line) + 6
            return searching ? base + 14 : base
        }

        // MARK: Daten

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < items.count, let style else { return nil }
            let item = items[row]
            let id = tableColumn.identifier.rawValue
            let font = FileColumn.font(for: style.listSize)

            if id == "name" {
                let identifier = NSUserInterfaceItemIdentifier("cell.name")
                let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NameCellView ?? {
                    let cell = NameCellView()
                    cell.identifier = identifier
                    return cell
                }()
                cell.configure(item: item, font: font, iconSize: style.listSize.iconSize,
                               folderColor: style.folderColor,
                               subtitle: searching ? parent.relativeFolder(item) : nil)
                cell.alphaValue = item.isHidden && style.dimHidden ? 0.55 : 1
                return cell
            }

            let identifier = NSUserInterfaceItemIdentifier("cell.text")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? TextCellView ?? {
                let cell = TextCellView()
                cell.identifier = identifier
                return cell
            }()
            let column = FileColumn.byID[id]
            cell.configure(text: column?.text(item) ?? "",
                           font: id == "permissions" ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font,
                           alignRight: column?.alignRight ?? false)
            cell.alphaValue = item.isHidden && style.dimHidden ? 0.55 : 1
            return cell
        }

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            guard tableColumn?.identifier.rawValue == "name", row < items.count else { return nil }
            return items[row].name
        }

        /// Ziehen aus der Liste (Finder, andere Apps, anderes Fenster)
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < items.count else { return nil }
            return items[row].url as NSURL
        }

        // MARK: Auswahl & Sortierung

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing else { return }
            let ids = selectedIDs
            if ids != parent.selection { parent.selection = ids }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isSyncing, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
                  let comparator = FileColumn.comparator(for: key, ascending: descriptor.ascending) else { return }
            parent.sortOrder = [comparator]
        }

        // MARK: Aktionen

        @objc func doubleClicked(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0 else { return }
            parent.onOpen(selectedIDs)
        }

        func contextMenu(forClickedRow row: Int) -> NSMenu? {
            guard let tableView else { return nil }
            parent.onActivate()
            if row >= 0 {
                if !tableView.selectedRowIndexes.contains(row) {
                    tableView.selectRowIndexes([row], byExtendingSelection: false)
                }
            } else {
                tableView.deselectAll(nil)
            }
            return NativeMenu.make(parent.menu(row >= 0 ? selectedIDs : []), anchor: tableView)
        }

        func handleKey(_ key: Key, modifiers: NSEvent.ModifierFlags) -> Bool {
            parent.onKey(key, modifiers)
        }

        // MARK: Spaltenkopf-Menü (Spalten ein-/ausblenden)

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            for column in FileColumn.all where column.id != "name" {
                guard let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.id)) else { continue }
                let item = ClosureMenuItem(title: column.title, image: nil) { [weak tableColumn] in
                    tableColumn?.isHidden.toggle()
                }
                item.state = tableColumn.isHidden ? .off : .on
                menu.addItem(item)
            }
        }
    }
}

// MARK: Tabelle

/// NSTableView mit Tastatur (⇥, Leertaste, Return, Rücktaste), Kontextmenü und Fenster-Aktivierung.
final class FileTableView: NSTableView {
    weak var coordinator: NativeFileTable.Coordinator?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            Task { @MainActor [weak self] in self?.coordinator?.parent.onActivate() }
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.parent.onActivate()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key: NativeFileTable.Key?
        switch event.keyCode {
        case 48 where modifiers.isEmpty: key = .tab
        case 49 where modifiers.subtracting(.shift).isEmpty: key = .space
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty: key = .returnKey
        case 51 where modifiers.isEmpty: key = .backspace
        default: key = nil
        }
        if let key, coordinator?.handleKey(key, modifiers: modifiers) == true { return }
        super.keyDown(with: event)
    }

    override func layout() {
        LayoutTimer.measure("davon Tabellen (ohne Zellen)", in: self) { super.layout() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return coordinator?.contextMenu(forClickedRow: row(at: point))
    }
}

// MARK: Zellen

final class TextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .secondaryLabelColor
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        textField = label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    func configure(text: String, font: NSFont, alignRight: Bool) {
        if label.stringValue != text { label.stringValue = text }
        if label.font != font { label.font = font }
        label.alignment = alignRight ? .right : .left
        contentChanged = true
        needsLayout = true
    }

    private var laidOutSize = NSSize.zero
    private var contentChanged = true

    override func layout() {
        super.layout()
        // Nur neu anordnen, wenn sich Größe oder Inhalt geändert haben (beim Verkleinern ändert sich meist nichts)
        guard contentChanged || bounds.size != laidOutSize else { return }
        LayoutTimer.measure("davon Zellen", in: self) {
            let height = ceil(label.intrinsicContentSize.height)
            label.frame = NSRect(x: 0, y: floor((bounds.height - height) / 2), width: bounds.width, height: height)
        }
        laidOutSize = bounds.size
        contentChanged = false
    }
}

final class NameCellView: NSTableCellView {
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let dots = TagDotsView()
    private var iconSize: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.lineBreakMode = .byTruncatingHead
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = NSFont.preferredFont(forTextStyle: .caption1)
        for view in [icon, nameLabel, subtitleLabel, dots] as [NSView] { addSubview(view) }
        imageView = icon
        textField = nameLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    func configure(item: FileItem, font: NSFont, iconSize: CGFloat, folderColor: NSColor?, subtitle: String?) {
        icon.image = IconCache.icon(for: item.url)
        self.iconSize = iconSize
        if nameLabel.stringValue != item.name { nameLabel.stringValue = item.name }
        if nameLabel.font != font { nameLabel.font = font }
        nameLabel.textColor = item.isBrowsableFolder ? (folderColor ?? .labelColor) : .labelColor
        dots.colors = item.tagList.compactMap { FinderTag.color(for: $0).map { NSColor($0) } }
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.stringValue = subtitle ?? ""
        contentChanged = true
        needsLayout = true
    }

    private var laidOutSize = NSSize.zero
    private var contentChanged = true

    override func layout() {
        super.layout()
        guard contentChanged || bounds.size != laidOutSize else { return }
        LayoutTimer.measure("davon Zellen", in: self) { arrange() }
        laidOutSize = bounds.size
        contentChanged = false
    }

    private func arrange() {
        icon.frame = NSRect(x: 2, y: floor((bounds.height - iconSize) / 2), width: iconSize, height: iconSize)
        let textX = iconSize + 8
        let available = max(0, bounds.width - textX)
        let dotsWidth = dots.intrinsicContentSize.width
        let nameHeight = ceil(nameLabel.intrinsicContentSize.height)
        // Ohne Tags: volle Breite. Mit Tags: so breit wie der Text (gemessen am Text selbst – intrinsicContentSize
        // eines kürzenden Labels hängt von seinem alten Rahmen ab und schnitt Namen fälschlich ab).
        var nameWidth = available
        if dotsWidth > 0 {
            let textWidth = ceil(nameLabel.attributedStringValue.size().width) + 6
            nameWidth = min(textWidth, max(0, available - dotsWidth - 4))
        }
        if subtitleLabel.isHidden {
            nameLabel.frame = NSRect(x: textX, y: floor((bounds.height - nameHeight) / 2), width: nameWidth, height: nameHeight)
        } else {
            let subtitleHeight = ceil(subtitleLabel.intrinsicContentSize.height)
            let top = floor((bounds.height - nameHeight - subtitleHeight) / 2)
            // NSTableCellView ist nicht gespiegelt: y zählt von unten
            subtitleLabel.frame = NSRect(x: textX, y: top, width: available, height: subtitleHeight)
            nameLabel.frame = NSRect(x: textX, y: top + subtitleHeight, width: nameWidth, height: nameHeight)
        }
        dots.frame = NSRect(x: nameLabel.frame.maxX + 4, y: nameLabel.frame.midY - 5, width: dotsWidth, height: 10)
    }
}

/// Farbpunkte der Finder-Tags (max. 3, leicht überlappend)
final class TagDotsView: NSView {
    var colors: [NSColor] = [] {
        didSet {
            if colors != oldValue {
                isHidden = colors.isEmpty
                needsDisplay = true
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        let count = min(colors.count, 3)
        return NSSize(width: count == 0 ? 0 : CGFloat(count) * 6 + 3, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, color) in colors.prefix(3).enumerated() {
            let rect = NSRect(x: CGFloat(index) * 6, y: 0.5, width: 9, height: 9)
            let path = NSBezierPath(ovalIn: rect)
            color.setFill()
            path.fill()
            NSColor.textBackgroundColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

// MARK: Spalten

@MainActor
struct FileColumn {
    let id: String
    let title: String
    let minWidth: CGFloat
    let width: CGFloat
    var hiddenByDefault = false
    var alignRight = false
    let keyPath: PartialKeyPath<FileItem>
    let text: (FileItem) -> String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMMyyyyjjmm")
        return formatter
    }()

    private static func date(_ date: Date) -> String {
        date == .distantPast ? "--" : dateFormatter.string(from: date)
    }

    static let all: [FileColumn] = [
        FileColumn(id: "name", title: "Name", minWidth: 160, width: 260, keyPath: \FileItem.name) { $0.name },
        FileColumn(id: "modified", title: "Änderungsdatum", minWidth: 110, width: 140, keyPath: \FileItem.modified) { FileColumn.date($0.modified) },
        FileColumn(id: "size", title: "Größe", minWidth: 60, width: 80, alignRight: true, keyPath: \FileItem.size) { $0.sizeText },
        FileColumn(id: "kind", title: "Art", minWidth: 80, width: 120, keyPath: \FileItem.kind) { $0.kind },
        FileColumn(id: "created", title: "Erstellt", minWidth: 110, width: 140, hiddenByDefault: true, keyPath: \FileItem.created) { FileColumn.date($0.created) },
        FileColumn(id: "accessed", title: "Zuletzt geöffnet", minWidth: 110, width: 140, hiddenByDefault: true, keyPath: \FileItem.accessed) { FileColumn.date($0.accessed) },
        FileColumn(id: "extension", title: "Erweiterung", minWidth: 50, width: 70, hiddenByDefault: true, keyPath: \FileItem.fileExtension) { $0.fileExtension },
        FileColumn(id: "tags", title: "Tags", minWidth: 60, width: 100, hiddenByDefault: true, keyPath: \FileItem.tags) { $0.tags },
        FileColumn(id: "permissions", title: "Rechte", minWidth: 110, width: 130, hiddenByDefault: true, keyPath: \FileItem.permissions) { $0.permissions },
        FileColumn(id: "owner", title: "Eigentümer", minWidth: 70, width: 90, hiddenByDefault: true, keyPath: \FileItem.owner) { $0.owner },
    ]

    static let byID: [String: FileColumn] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Spalten-ID zur Sortierung (für den Pfeil im Spaltenkopf)
    static func key(for comparator: KeyPathComparator<FileItem>) -> String? {
        all.first { $0.keyPath == comparator.keyPath }?.id
    }

    /// Sortierung wie bisher bei SwiftUIs `TableColumn(value:)`: Texte „natürlich“ (Datei2 vor Datei10)
    static func comparator(for key: String, ascending: Bool) -> KeyPathComparator<FileItem>? {
        let order: SortOrder = ascending ? .forward : .reverse
        switch key {
        case "name": return KeyPathComparator(\FileItem.name, comparator: .localizedStandard, order: order)
        case "modified": return KeyPathComparator(\FileItem.modified, order: order)
        case "size": return KeyPathComparator(\FileItem.size, order: order)
        case "kind": return KeyPathComparator(\FileItem.kind, comparator: .localizedStandard, order: order)
        case "created": return KeyPathComparator(\FileItem.created, order: order)
        case "accessed": return KeyPathComparator(\FileItem.accessed, order: order)
        case "extension": return KeyPathComparator(\FileItem.fileExtension, comparator: .localizedStandard, order: order)
        case "tags": return KeyPathComparator(\FileItem.tags, comparator: .localizedStandard, order: order)
        case "permissions": return KeyPathComparator(\FileItem.permissions, comparator: .localizedStandard, order: order)
        case "owner": return KeyPathComparator(\FileItem.owner, comparator: .localizedStandard, order: order)
        default: return nil
        }
    }

    static func font(for size: AppSettings.ListSize) -> NSFont {
        switch size {
        case .small: NSFont.preferredFont(forTextStyle: .callout)
        case .medium: NSFont.preferredFont(forTextStyle: .body)
        case .large: NSFont.preferredFont(forTextStyle: .title3)
        }
    }
}
