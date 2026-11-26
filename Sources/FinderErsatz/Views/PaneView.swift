import SwiftUI
import AppKit

struct PaneView: View {
    @Environment(BrowserState.self) private var browser
    let side: PaneSide
    var focus: FocusState<PaneSide?>.Binding
    @AppStorage("tableColumns") private var columnData = Data()

    private var isActive: Bool { browser.activeSide == side }

    var body: some View {
        @Bindable var pane = browser.pane(side)
        let group = browser.group(side)
        let settings = browser.settings

        VStack(spacing: 0) {
            if group.tabs.count > 1 {
                TabBar(group: group) { browser.activeSide = side }
                Divider()
            }
            PaneHeader(pane: pane, showsNewTabButton: group.tabs.count <= 1) {
                browser.activeSide = side
                browser.newTab()
            }
                .contentShape(Rectangle())
                .onTapGesture { browser.activeSide = side }
            Divider()
            if pane.isSearchBarVisible {
                SearchBar(pane: pane)
                    .id(pane.id)
                Divider()
            }
            if pane.isBrowsingArchive {
                Label("Entpackte Kopie eines Archivs – Änderungen wirken sich nicht auf das Archiv aus.", systemImage: "archivebox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.yellow.opacity(0.15))
                Divider()
            }

            VSplitView {
                Group {
                    if let error = pane.errorMessage {
                        ContentUnavailableView {
                            Label("Ordner nicht lesbar", systemImage: "lock.fill")
                        } description: {
                            Text(error)
                        } actions: {
                            if pane.errorIsPermission {
                                Button("Festplattenvollzugriff öffnen") {
                                    SystemSettings.open(.fullDiskAccess)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Erneut versuchen") { pane.reload() }
                            }
                        }
                    } else if pane.activeSearch != nil, pane.items.isEmpty, !pane.isSearchRunning {
                        ContentUnavailableView.search
                    } else if pane.viewMode == .list || pane.activeSearch != nil {
                        keyHandling(fileTable(pane: pane, settings: settings), pane: pane)
                    } else if pane.viewMode == .columns {
                        keyHandling(
                            ColumnBrowserView(pane: pane, side: side, onOpen: { open($0, in: pane) }) { ids in
                                fileMenu(ids, pane: pane)
                            }
                            .focusable()
                            .focusEffectDisabled(),
                            pane: pane
                        )
                    } else if pane.viewMode == .gallery {
                        keyHandling(
                            GalleryView(pane: pane, onOpen: { open($0, in: pane) }) { ids in
                                fileMenu(ids, pane: pane)
                            }
                            .focusable()
                            .focusEffectDisabled(),
                            pane: pane
                        )
                    } else {
                        keyHandling(
                            FileGridView(pane: pane, mode: pane.viewMode, onOpen: { open($0, in: pane) }) { ids in
                                fileMenu(ids, pane: pane)
                            }
                            .focusable()
                            .focusEffectDisabled(),
                            pane: pane
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // Liste füllt immer die volle Höhe
                .dropDestination(for: URL.self) { urls, _ in
                    _ = browser.drop(urls, into: pane)
                }
                .frame(minHeight: 120)

                // Vorschaubereich unten im Fenster (⌃⌘P)
                if browser.showPanePreview {
                    PanePreview(pane: pane)
                        .frame(minHeight: 110, idealHeight: 200, maxHeight: .infinity)
                }
            }

            Divider()
            PaneStatusBar(pane: pane)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: pane.selection) {
            // Offenes Quick-Look-Fenster folgt der Auswahl im aktiven Fenster (wie im Finder).
            if isActive { QuickLookController.shared.update(pane.selectedItems.map(\.url)) }
        }
        .overlay(alignment: .top) {
            // Markierung des aktiven Fensters
            Rectangle()
                .fill(isActive ? settings.activeColor : .clear)
                .frame(height: 3)
        }
    }

    // MARK: Tastatur

    private func keyHandling(_ content: some View, pane: PaneState) -> some View {
        content
            .focused(focus, equals: side)
            .onKeyPress(.tab) {
                browser.toggleActivePane()
                return .handled
            }
            .onKeyPress(.space) {
                browser.toggleQuickLook()   // Leertaste = Schnellansicht
                return .handled
            }
            .onKeyPress(.return) {
                guard pane.viewMode != .list, pane.activeSearch == nil, !pane.selection.isEmpty else { return .ignored }
                open(pane.selection, in: pane)
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                guard pane.viewMode != .list, pane.activeSearch == nil, press.modifiers.isEmpty else { return .ignored }
                if pane.viewMode == .columns, press.key == .leftArrow {
                    pane.goUp()   // Spalte nach links: übergeordneter Ordner, bisheriger Ordner bleibt markiert
                } else if pane.viewMode == .columns, press.key == .rightArrow {
                    // Spalte nach rechts: in den markierten Ordner, erstes Objekt auswählen
                    let selected = pane.selectedItems
                    guard selected.count == 1, selected[0].isBrowsableFolder else { return .handled }
                    pane.navigate(to: selected[0].url)
                    if let first = pane.items.first { pane.selection = [first.id] }
                } else {
                    moveSelection(in: pane, forward: press.key == .rightArrow || press.key == .downArrow)
                }
                return .handled
            }
            .onKeyPress(.delete, phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                pane.goUp()   // Backspace = übergeordneter Ordner
                return .handled
            }
    }

    // MARK: Liste

    @ViewBuilder
    private func fileTable(pane: PaneState, settings: AppSettings) -> some View {
        @Bindable var pane = pane
        let searching = pane.activeSearch != nil
        Table(of: FileItem.self, selection: $pane.selection, sortOrder: $pane.sortOrder,
              columnCustomization: columnCustomization) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: settings.listSize.iconSize, height: settings.listSize.iconSize)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(item.name)
                                .lineLimit(1)
                                .foregroundStyle(item.isBrowsableFolder ? (settings.folderColor ?? .primary) : .primary)
                            TagDots(tags: item.tagList)
                        }
                        if searching {
                            Text(pane.relativeFolder(of: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                    .opacity(item.isHidden && settings.showHiddenDimmed ? 0.55 : 1)
                }
            }
            .width(min: 160, ideal: 260)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)   // Name lässt sich nicht ausblenden
            TableColumn("Änderungsdatum", value: \.modified) { item in
                Text(item.modified, format: .dateTime.day().month().year().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            .customizationID("modified")
            TableColumn("Größe", value: \.size) { item in
                Text(item.sizeText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            .customizationID("size")
            TableColumn("Art", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            .customizationID("kind")
            // Zusätzliche Spalten – per Rechtsklick auf den Spaltenkopf einblenden
            TableColumn("Erstellt", value: \.created) { item in
                Text(item.created, format: .dateTime.day().month().year().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            .customizationID("created")
            .defaultVisibility(.hidden)
            TableColumn("Zuletzt geöffnet", value: \.accessed) { item in
                Text(item.accessed, format: .dateTime.day().month().year().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            .customizationID("accessed")
            .defaultVisibility(.hidden)
            TableColumn("Erweiterung", value: \.fileExtension) { item in
                Text(item.fileExtension).foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)
            .customizationID("extension")
            .defaultVisibility(.hidden)
            TableColumn("Tags", value: \.tags) { item in
                Text(item.tags).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 100)
            .customizationID("tags")
            .defaultVisibility(.hidden)
            TableColumn("Rechte", value: \.permissions) { item in
                Text(item.permissions).monospaced().foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
            .customizationID("permissions")
            .defaultVisibility(.hidden)
            TableColumn("Eigentümer", value: \.owner) { item in
                Text(item.owner).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            .customizationID("owner")
            .defaultVisibility(.hidden)
        } rows: {
            ForEach(pane.items) { item in
                TableRow(item).draggable(item.url)
            }
        }
        .font(settings.listSize.font)
        .alternatingRowBackgrounds(settings.alternatingRows ? .enabled : .disabled)
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            fileMenu(ids, pane: pane)
        } primaryAction: { ids in
            // Doppelklick oder Return
            open(ids, in: pane)
        }
    }

    /// Sichtbarkeit, Reihenfolge und Breite der Spalten – für beide Fenster gemeinsam gespeichert.
    private var columnCustomization: Binding<TableColumnCustomization<FileItem>> {
        Binding(
            get: { (try? JSONDecoder().decode(TableColumnCustomization<FileItem>.self, from: columnData)) ?? TableColumnCustomization() },
            set: { columnData = (try? JSONEncoder().encode($0)) ?? Data() }
        )
    }

    // MARK: Kontextmenü (Liste und Raster)

    @ViewBuilder
    private func fileMenu(_ ids: Set<FileItem.ID>, pane: PaneState) -> some View {
        let selected = pane.items.filter { ids.contains($0.id) }
        if !selected.isEmpty {
            Button("Öffnen") { open(ids, in: pane) }
            let folderURLs = selected.filter(\.isBrowsableFolder).map(\.url)
            if !folderURLs.isEmpty {
                Button("In neuem Tab öffnen") {
                    browser.activeSide = side
                    folderURLs.forEach { browser.openInNewTab($0) }
                }
            }
            let archives = selected.map(\.url).filter(ArchiveService.isArchive)
            if !archives.isEmpty {
                Button("Mit Standard-App öffnen") { browser.openWithDefaultApp(archives) }
            }
            let files = selected.filter { !$0.isBrowsableFolder }.map(\.url)
            if let first = files.first {
                Menu("Öffnen mit") {
                    ForEach(Array(browser.applications(toOpen: first).prefix(15).enumerated()), id: \.offset) { index, app in
                        Button {
                            browser.open(files, with: app)
                        } label: {
                            Label {
                                Text(FileManager.default.displayName(atPath: app.path) + (index == 0 ? " (Standard)" : ""))
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            }
                        }
                    }
                    Divider()
                    Button("Andere …") { browser.open(files, choosingApplication: true) }
                }
            }
            if selected.count == 1, selected[0].isPackage {
                Button("Paketinhalt zeigen") {
                    browser.activeSide = side
                    browser.showPackageContents(selected[0].url)
                }
            }
            if pane.activeSearch != nil, selected.count == 1 {
                Button("Im Ordner zeigen") { pane.reveal(selected[0]) }
            }
            Button("Schnellansicht") {
                activate(pane, ids)
                browser.toggleQuickLook()
            }
            Button("Umbenennen …") {
                activate(pane, ids)
                browser.beginRename()
            }
            if selected.count > 1 {
                Button("\(selected.count) Objekte umbenennen …") {
                    activate(pane, ids)
                    browser.beginBatchRename()
                }
            }
            Button("Informationen") {
                activate(pane, ids)
                browser.showInfo()
            }
            Button("Duplizieren") {
                activate(pane, ids)
                browser.duplicateSelection()
            }
            Button("Alias erstellen") {
                activate(pane, ids)
                browser.makeAliasForSelection()
            }
            Button(selected.count == 1 ? "„\(selected[0].name)“ kopieren" : "\(selected.count) Objekte kopieren") {
                activate(pane, ids)
                browser.copySelectionToPasteboard()
            }
            // Wie im Finder: mit gedrückter ⌥-Taste wird daraus „… als Pfadname kopieren“.
            .modifierKeyAlternate(.option) {
                Button(selected.count == 1 ? "„\(selected[0].name)“ als Pfadname kopieren" : "\(selected.count) Objekte als Pfadnamen kopieren") {
                    activate(pane, ids)
                    browser.copyPathsToPasteboard()
                }
            }
            ShareLink(items: selected.map(\.url)) {
                Label("Teilen …", systemImage: "square.and.arrow.up")
            }
            Divider()
            Menu("Tags") {
                ForEach(FinderTag.allCases) { tag in
                    Button {
                        browser.toggleTag(tag, for: selected)
                    } label: {
                        Label {
                            Text(tag.rawValue + (selected.allSatisfy { tag.isContained(in: $0.tagList) } ? " ✓" : ""))
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(tag.color)
                        }
                    }
                }
                Divider()
                Button("Alle Tags entfernen") { browser.removeAllTags(for: selected) }
            }
            Divider()
            Button("In anderes Fenster kopieren") {
                activate(pane, ids)
                browser.copyToOtherPane()
            }
            Button("In anderes Fenster verschieben") {
                activate(pane, ids)
                browser.moveToOtherPane()
            }
            Divider()
            Button("Als ZIP komprimieren") {
                activate(pane, ids)
                browser.compressSelection()
            }
            if !archives.isEmpty {
                Button("Entpacken (hierher)") {
                    activate(pane, ids)
                    browser.extractSelection(toOtherPane: false)
                }
                Button("Entpacken ins andere Fenster") {
                    activate(pane, ids)
                    browser.extractSelection(toOtherPane: true)
                }
            }
            Divider()
            if !folderURLs.isEmpty {
                Button("Zu Favoriten hinzufügen") { browser.favorites.add(folderURLs) }
            }
            Button("Pfad kopieren") {
                activate(pane, ids)
                browser.copyPathsToPasteboard()
            }
            Button("Terminal hier öffnen") {
                activate(pane, ids)
                browser.openTerminal()
            }
            Button("Im Finder zeigen") {
                activate(pane, ids)
                browser.revealInFinder()
            }
            Divider()
            Button("In den Papierkorb", role: .destructive) {
                activate(pane, ids)
                browser.trashSelection()
            }
        } else {
            Button("Neuer Ordner") {
                browser.activeSide = side
                browser.newFolder()
            }
            Button("Einsetzen") {
                browser.activeSide = side
                browser.pasteFromPasteboard(move: false)
            }
            Button("Informationen") {
                browser.activeSide = side
                browser.showInfo()
            }
            Button("Suchen …") {
                browser.activeSide = side
                browser.showSearch()
            }
            Button("Ordner zu Favoriten hinzufügen") { browser.favorites.add([pane.currentURL]) }
            Button("Terminal hier öffnen") { AppLauncher.openTerminal(at: pane.currentURL) }
        }
    }

    /// Kontextmenü-Aktionen wirken auf die angeklickten Objekte in diesem Fenster.
    private func activate(_ pane: PaneState, _ ids: Set<FileItem.ID>) {
        browser.activeSide = side
        if !ids.isSubset(of: pane.selection) { pane.selection = ids }
    }

    /// Pfeiltasten in den Rasteransichten: vorheriges/nächstes Objekt.
    private func moveSelection(in pane: PaneState, forward: Bool) {
        guard !pane.items.isEmpty else { return }
        let current = pane.items.lastIndex { pane.selection.contains($0.id) }
        let next: Int
        if let current {
            next = forward ? min(current + 1, pane.items.count - 1) : max(current - 1, 0)
        } else {
            next = 0
        }
        pane.selection = [pane.items[next].id]
    }

    private func open(_ ids: Set<FileItem.ID>, in pane: PaneState) {
        browser.activeSide = side
        let items = pane.items.filter { ids.contains($0.id) }
        // Mehrere Ordner: nur den ersten betreten; Dateien alle öffnen.
        if let folder = items.first(where: \.isBrowsableFolder), items.count == 1 || items.allSatisfy(\.isBrowsableFolder) {
            browser.open(folder, in: pane)
        } else {
            items.filter { !$0.isBrowsableFolder }.forEach { browser.open($0, in: pane) }
        }
    }
}

struct PaneHeader: View {
    let pane: PaneState
    /// Bei nur einem Tab ist die Tab-Leiste ausgeblendet – dann sitzt der „+“-Knopf hier.
    var showsNewTabButton = false
    var onNewTab: () -> Void = {}

    var body: some View {
        HStack(spacing: 4) {
            Button("Zurück", systemImage: "chevron.left") { pane.goBack() }
                .disabled(!pane.canGoBack)
            Button("Vorwärts", systemImage: "chevron.right") { pane.goForward() }
                .disabled(!pane.canGoForward)
            Button("Nach oben", systemImage: "arrow.up") { pane.goUp() }
                .disabled(!pane.canGoUp)
            PathBar(url: pane.currentURL) { pane.navigate(to: $0) }
            Spacer(minLength: 4)
            if showsNewTabButton {
                Button("Neuer Tab", systemImage: "plus.square.on.square", action: onNewTab)
                    .help("Neuer Tab (⌘T)")
            }
            Button("Suchen", systemImage: "magnifyingglass") { pane.isSearchBarVisible.toggle() }
                .help("Suchen (⌘F)")
            Picker("Ansicht", selection: Bindable(pane).viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Ansicht: Liste (⌘1), Kurz (⌘2), Miniaturen (⌘3), Spalten (⌘4), Galerie (⌘5)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// Klickbare Pfadleiste: jeder Ordner im Pfad ist ein Sprungziel.
struct PathBar: View {
    let url: URL
    let navigate: (URL) -> Void

    private var components: [URL] {
        var result: [URL] = []
        var current = url
        while true {
            result.insert(current, at: 0)
            if current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                    }
                    Button {
                        navigate(component)
                    } label: {
                        HStack(spacing: 3) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: component.path))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(component.path == "/" ? "Macintosh HD" : component.lastPathComponent)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
    }
}

struct PaneStatusBar: View {
    let pane: PaneState

    var body: some View {
        let selected = pane.selectedItems
        let bytes = selected.filter { !$0.isBrowsableFolder }.reduce(Int64(0)) { $0 + $1.size }
        HStack {
            if pane.isSearchRunning {
                ProgressView().controlSize(.mini)
                Text("Suche läuft … \(pane.items.count) Treffer")
            } else if pane.activeSearch != nil {
                Text("\(pane.items.count) Treffer")
                if pane.items.count >= FileSearch.maxResults { Text("(Maximum erreicht)") }
            } else {
                Text("\(pane.items.count) Objekte")
            }
            if !selected.isEmpty {
                Text("· \(selected.count) ausgewählt")
                if bytes > 0 { Text("(\(bytes.formatted(.byteCount(style: .file))))") }
            }
            Spacer()
            if pane.activeSearch != nil, !pane.isSearchBarVisible {
                Button("Zurück zum Ordner", systemImage: "xmark.circle.fill") { pane.stopSearch() }
                    .buttonStyle(.borderless)
                    .help("Ergebnisliste schließen und wieder „\(pane.currentURL.lastPathComponent)“ zeigen")
            }
            if pane.showHidden { Image(systemName: "eye").help("Unsichtbare Dateien sichtbar") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
