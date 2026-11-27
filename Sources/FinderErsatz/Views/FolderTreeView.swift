import SwiftUI
import AppKit

/// Ordnerbaum als Ansicht (⌘6, Total Commander: Baum im Fenster). Wurzel ist der aktuelle Ordner,
/// Unterordner klappen auf. Ein Klick auf einen Ordner zeigt ihn im anderen Fenster (abschaltbar),
/// Doppelklick/Return öffnet ihn in diesem Fenster.
struct FolderTreePane: View {
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    let side: PaneSide
    @AppStorage("tree.followOther") private var followOther = true
    @AppStorage("tree.showFiles") private var showFiles = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("Anderes Fenster folgt", isOn: $followOther)
                    .help("Ein Klick auf einen Ordner zeigt seinen Inhalt im anderen Fenster")
                Toggle("Dateien zeigen", isOn: $showFiles)
                Spacer()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            Divider()
            FolderTreeView(
                root: pane.currentURL,
                showHidden: pane.showHidden,
                showFiles: showFiles,
                reloadToken: pane.allItems.count,
                onSelect: { url, isFolder in select(url, isFolder: isFolder) },
                onOpen: { url, isFolder in open(url, isFolder: isFolder) },
                menu: { url, isFolder in menu(for: url, isFolder: isFolder) }
            )
        }
    }

    private var otherPane: PaneState { browser.pane(side == .left ? .right : .left) }

    private func select(_ url: URL, isFolder: Bool) {
        browser.activeSide = side
        // Objekte der obersten Ebene auch im Fenster auswählen – dann gehen F5, F2 usw. darauf
        let normalized = url.normalizedFileURL
        pane.selection = normalized.deletingLastPathComponent() == pane.currentURL ? [normalized] : []
        if followOther, isFolder {
            otherPane.navigate(to: url)
        }
    }

    private func open(_ url: URL, isFolder: Bool) {
        browser.activeSide = side
        if isFolder {
            pane.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func menu(for url: URL, isFolder: Bool) -> NSMenu {
        var entries: [MenuEntry] = []
        if isFolder {
            entries.append(.action("Öffnen") { open(url, isFolder: true) })
            entries.append(.action("Im anderen Fenster öffnen") { otherPane.navigate(to: url) })
            entries.append(.action("Terminal hier öffnen") { AppLauncher.openTerminal(at: url) })
        } else {
            entries.append(.action("Öffnen") { NSWorkspace.shared.open(url) })
        }
        entries.append(.divider)
        entries.append(.action("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        entries.append(.action("Pfad kopieren") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        })
        return NativeMenu.make(entries, anchor: nil)
    }
}

/// NSOutlineView mit faul geladenen Knoten
struct FolderTreeView: NSViewRepresentable {
    let root: URL
    let showHidden: Bool
    let showFiles: Bool
    /// Ändert sich, wenn der Ordner neu geladen wurde → Baum neu aufbauen
    let reloadToken: Int
    let onSelect: (URL, Bool) -> Void
    let onOpen: (URL, Bool) -> Void
    let menu: (URL, Bool) -> NSMenu

    final class Node: NSObject {
        let url: URL
        let name: String
        let isFolder: Bool
        var children: [Node]?

        init(url: URL, name: String, isFolder: Bool) {
            self.url = url
            self.name = name
            self.isFolder = isFolder
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = TreeOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .plain
        outline.rowHeight = 22
        outline.autoresizesOutlineColumn = true
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.coordinator = context.coordinator
        context.coordinator.outline = outline

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onOpen = onOpen
        coordinator.menuProvider = menu
        let key = "\(root.path)|\(showHidden)|\(showFiles)|\(reloadToken)"
        guard key != coordinator.key else { return }
        let sameRoot = coordinator.rootURL == root
        let expanded = sameRoot ? coordinator.expandedURLs() : []
        coordinator.key = key
        coordinator.rootURL = root
        coordinator.showHidden = showHidden
        coordinator.showFiles = showFiles
        coordinator.roots = coordinator.loadChildren(of: root)
        coordinator.outline?.reloadData()
        coordinator.restoreExpanded(expanded)
    }

    final class TreeOutlineView: NSOutlineView {
        weak var coordinator: Coordinator?

        override func keyDown(with event: NSEvent) {
            // Return öffnet, sonst Standard (Pfeile klappen auf/zu)
            if event.keyCode == 36 || event.keyCode == 76, let node = item(atRow: selectedRow) as? Node {
                coordinator?.onOpen?(node.url, node.isFolder)
                return
            }
            super.keyDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let row = self.row(at: convert(event.locationInWindow, from: nil))
            guard row >= 0, let node = item(atRow: row) as? Node else { return nil }
            selectRowIndexes([row], byExtendingSelection: false)
            return coordinator?.menuProvider?(node.url, node.isFolder)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outline: NSOutlineView?
        var roots: [Node] = []
        var key = ""
        var rootURL: URL?
        var showHidden = false
        var showFiles = false
        var onSelect: ((URL, Bool) -> Void)?
        var onOpen: ((URL, Bool) -> Void)?
        var menuProvider: ((URL, Bool) -> NSMenu)?

        func loadChildren(of url: URL) -> [Node] {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .localizedNameKey]
            let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options) else {
                return []
            }
            let nodes: [Node] = urls.compactMap { child in
                let values = try? child.resourceValues(forKeys: Set(keys))
                let isFolder = values?.isDirectory == true && values?.isPackage != true
                guard isFolder || showFiles else { return nil }
                return Node(url: child, name: values?.localizedName ?? child.lastPathComponent, isFolder: isFolder)
            }
            // Ordner zuerst, dann wie im Finder sortiert
            return nodes.sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        private func children(of item: Any?) -> [Node] {
            guard let node = item as? Node else { return roots }
            if node.children == nil { node.children = node.isFolder ? loadChildren(of: node.url) : [] }
            return node.children ?? []
        }

        func expandedURLs() -> Set<URL> {
            guard let outline else { return [] }
            var result = Set<URL>()
            for row in 0..<outline.numberOfRows {
                if let node = outline.item(atRow: row) as? Node, outline.isItemExpanded(node) { result.insert(node.url) }
            }
            return result
        }

        func restoreExpanded(_ urls: Set<URL>) {
            guard let outline, !urls.isEmpty else { return }
            var row = 0
            while row < outline.numberOfRows {
                if let node = outline.item(atRow: row) as? Node, urls.contains(node.url) {
                    outline.expandItem(node)
                }
                row += 1
            }
        }

        // MARK: Datenquelle

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Node)?.isFolder ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("treeCell")
            let cell: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let image = NSImageView()
                let text = NSTextField(labelWithString: "")
                text.lineBreakMode = .byTruncatingMiddle
                image.translatesAutoresizingMaskIntoConstraints = false
                text.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.addSubview(text)
                cell.imageView = image
                cell.textField = text
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
                    text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = node.name
            cell.imageView?.image = IconCache.icon(for: node.url)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            onSelect?(node.url, node.isFolder)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let outline, outline.clickedRow >= 0, let node = outline.item(atRow: outline.clickedRow) as? Node else { return }
            onOpen?(node.url, node.isFolder)
        }
    }
}
