import SwiftUI
import AppKit

struct PaneView: View {
    @Environment(BrowserState.self) private var browser
    let side: PaneSide
    var focus: FocusState<PaneSide?>.Binding

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
            if !browser.debugHideHeader {
                Group {
                    if settings.compactLayout {
                        SlimPaneHeader(pane: pane, isActive: isActive, onActivate: { browser.activeSide = side })
                    } else {
                        PaneHeader(pane: pane, showsNewTabButton: group.tabs.count <= 1, onNewTab: {
                            browser.activeSide = side
                            browser.newTab()
                        }, onActivate: { browser.activeSide = side })
                    }
                }
                // Klick auf freie Fläche aktiviert das Fenster. Als Hintergrund, damit Knöpfe und
                // Pfad-Elemente ihre Klicks selbst bekommen (ein Gesten-Modifier darüber schluckte sie).
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { browser.activeSide = side }
                )
                Divider()
            }
            if pane.isSearchBarVisible {
                SearchBar(pane: pane)
                    .id(pane.searchBarResetToken)
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

            if browser.debugNoVSplit && !browser.showPanePreview {
                // Layout-Test: ohne VSplitView
                listArea(pane: pane, settings: settings)
            } else {
                VSplitView {
                    listArea(pane: pane, settings: settings)
                    // Vorschaubereich unten im Fenster (⌃⌘P)
                    if browser.showPanePreview {
                        PanePreview(pane: pane)
                            .frame(minHeight: 110, idealHeight: 200, maxHeight: .infinity)
                    }
                }
            }

            if !browser.debugHideStatus {
                Divider()
                PaneStatusBar(pane: pane)
            }
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

    /// Ordnerinhalt (Liste, Raster, Spalten, Galerie) bzw. Fehlermeldung
    @ViewBuilder
    private func listArea(pane: PaneState, settings: AppSettings) -> some View {
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
                fileTable(pane: pane, settings: settings)
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
    }

    // MARK: Tastatur

    private func keyHandling(_ content: some View, pane: PaneState) -> some View {
        content
            .focused(focus, equals: side)
            .onKeyPress(.tab) {
                browser.toggleActivePane()
                return .handled
            }
            // Leertaste = Schnellansicht; ⇧-Leertaste = immer Quick Look, auch bei Ordnern (XRay).
            // (⌥-Leertaste ist oft von Alfred/Spotlight belegt.)
            .onKeyPress(keys: [.space]) { press in
                browser.toggleQuickLook(forceSystemPreview: press.modifiers.contains(.shift))
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

    /// Native Liste (NSTableView) – siehe `NativeFileTable` (SwiftUIs Table ruckelte beim Verkleinern).
    private func fileTable(pane: PaneState, settings: AppSettings) -> some View {
        @Bindable var pane = pane
        return NativeFileTable(
            items: pane.items,
            selection: $pane.selection,
            sortOrder: $pane.sortOrder,
            searching: pane.activeSearch != nil,
            contentKey: pane.currentURL.path + (pane.activeSearch == nil ? "" : "#suche"),
            relativeFolder: { pane.relativeFolder(of: $0) },
            style: NativeFileTable.Style(
                listSize: settings.listSize,
                alternatingRows: settings.alternatingRows,
                folderColor: settings.folderColor.map { NSColor($0) },
                dimHidden: settings.showHiddenDimmed
            ),
            isActive: isActive,
            onActivate: { if browser.activeSide != side { browser.activeSide = side } },
            onOpen: { open($0, in: pane) },
            menu: { fileMenuEntries($0, pane: pane) },
            onKey: { key, modifiers in handleTableKey(key, modifiers: modifiers, pane: pane) }
        )
    }

    private func handleTableKey(_ key: NativeFileTable.Key, modifiers: NSEvent.ModifierFlags, pane: PaneState) -> Bool {
        switch key {
        case .tab:
            browser.toggleActivePane()
            return true
        case .space:
            // Leertaste = Schnellansicht; ⇧-Leertaste = immer Quick Look, auch bei Ordnern (XRay)
            browser.toggleQuickLook(forceSystemPreview: modifiers.contains(.shift))
            return true
        case .returnKey:
            guard !pane.selection.isEmpty else { return false }
            open(pane.selection, in: pane)
            return true
        case .backspace:
            pane.goUp()   // Backspace = übergeordneter Ordner
            return true
        }
    }

    // MARK: Kontextmenü (Liste und Raster)

    /// SwiftUI-Darstellung des Kontextmenüs (Kurz, Miniaturen, Spalten, Galerie)
    private func fileMenu(_ ids: Set<FileItem.ID>, pane: PaneState) -> some View {
        MenuEntriesView(entries: fileMenuEntries(ids, pane: pane))
    }

    /// Inhalt des Kontextmenüs – gemeinsam für die native Liste (NSMenu) und die SwiftUI-Ansichten.
    private func fileMenuEntries(_ ids: Set<FileItem.ID>, pane: PaneState) -> [MenuEntry] {
        let selected = pane.items.filter { ids.contains($0.id) }
        var entries: [MenuEntry] = []
        guard !selected.isEmpty else {
            entries += [
                .action("Neuer Ordner") {
                    browser.activeSide = side
                    browser.newFolder()
                },
                .submenu("Neue Datei", NewFileType.allCases.map { type in
                    .action(type.title) {
                        browser.activeSide = side
                        browser.newFile(type)
                    }
                }),
                .action("Einsetzen") {
                    browser.activeSide = side
                    browser.pasteFromPasteboard(move: false)
                },
                .action("Informationen") {
                    browser.activeSide = side
                    browser.showInfo()
                },
                .action("Suchen …") {
                    browser.activeSide = side
                    browser.showSearch()
                },
                .action("Ordner zu Favoriten hinzufügen") { browser.favorites.add([pane.currentURL]) },
                .action("Terminal hier öffnen") { AppLauncher.openTerminal(at: pane.currentURL) },
                .divider,
            ]
            entries += previewToggleEntries
            return entries
        }

        entries.append(.action("Öffnen") { open(ids, in: pane) })
        let folderURLs = selected.filter(\.isBrowsableFolder).map(\.url)
        if !folderURLs.isEmpty {
            entries.append(.action("In neuem Tab öffnen") {
                browser.activeSide = side
                folderURLs.forEach { browser.openInNewTab($0) }
            })
        }
        let archives = selected.map(\.url).filter(ArchiveService.isArchive)
        if !archives.isEmpty {
            entries.append(.action("Mit Standard-App öffnen") { browser.openWithDefaultApp(archives) })
        }
        let files = selected.filter { !$0.isBrowsableFolder }.map(\.url)
        if let first = files.first {
            var apps: [MenuEntry] = []
            for (index, app) in browser.applications(toOpen: first).prefix(15).enumerated() {
                let title = FileManager.default.displayName(atPath: app.path) + (index == 0 ? " (Standard)" : "")
                apps.append(.action(title, image: MenuEntry.icon(forFile: app.path)) { browser.open(files, with: app) })
            }
            apps += [.divider, .action("Andere …") { browser.open(files, choosingApplication: true) }]
            entries.append(.submenu("Öffnen mit", apps))
        }
        if selected.count == 1, selected[0].isPackage {
            entries.append(.action("Paketinhalt zeigen") {
                browser.activeSide = side
                browser.showPackageContents(selected[0].url)
            })
        }
        if pane.activeSearch != nil, selected.count == 1 {
            entries.append(.action("Im Ordner zeigen") { pane.reveal(selected[0]) })
        }
        entries.append(.action("Schnellansicht") {
            activate(pane, ids)
            browser.toggleQuickLook()
        })
        if !folderURLs.isEmpty {
            entries.append(.action("Quick Look mit XRay") {
                activate(pane, ids)
                browser.toggleQuickLook(forceSystemPreview: true)
            })
        }
        entries += previewToggleEntries
        entries.append(.action("Umbenennen …") {
            activate(pane, ids)
            browser.beginRename()
        })
        if selected.count > 1 {
            entries.append(.action("\(selected.count) Objekte umbenennen …") {
                activate(pane, ids)
                browser.beginBatchRename()
            })
        }
        entries += [
            .action("Umbenennen mit Regex …") {
                activate(pane, ids)
                browser.beginBatchRename(regex: true)
            },
            .action("Informationen") {
                activate(pane, ids)
                browser.showInfo()
            },
            .action("Duplizieren") {
                activate(pane, ids)
                browser.duplicateSelection()
            },
            .action("Alias erstellen") {
                activate(pane, ids)
                browser.makeAliasForSelection()
            },
            // Wie im Finder: mit gedrückter ⌥-Taste wird daraus „… als Pfadname kopieren“.
            .withAlternate(
                .action(selected.count == 1 ? "„\(selected[0].name)“ kopieren" : "\(selected.count) Objekte kopieren") {
                    activate(pane, ids)
                    browser.copySelectionToPasteboard()
                },
                alternate: .action(selected.count == 1 ? "„\(selected[0].name)“ als Pfadname kopieren" : "\(selected.count) Objekte als Pfadnamen kopieren") {
                    activate(pane, ids)
                    browser.copyPathsToPasteboard()
                }
            ),
            .share(selected.map(\.url)),
            .divider,
        ]
        var tagEntries: [MenuEntry] = FinderTag.allCases.map { tag in
            let isSet = selected.allSatisfy { tag.isContained(in: $0.tagList) }
            return .action(tag.rawValue + (isSet ? " ✓" : ""), image: MenuEntry.symbol("circle.fill", color: NSColor(tag.color))) {
                browser.toggleTag(tag, for: selected)
            }
        }
        tagEntries += [.divider, .action("Alle Tags entfernen") { browser.removeAllTags(for: selected) }]
        entries += [
            .submenu("Tags", tagEntries),
            .divider,
            .action("In anderes Fenster kopieren") {
                activate(pane, ids)
                browser.copyToOtherPane()
            },
            .action("In anderes Fenster verschieben") {
                activate(pane, ids)
                browser.moveToOtherPane()
            },
            .divider,
            .action("Als ZIP komprimieren") {
                activate(pane, ids)
                browser.compressSelection()
            },
        ]
        if !archives.isEmpty {
            entries += [
                .action("Entpacken (hierher)") {
                    activate(pane, ids)
                    browser.extractSelection(toOtherPane: false)
                },
                .action("Entpacken ins andere Fenster") {
                    activate(pane, ids)
                    browser.extractSelection(toOtherPane: true)
                },
            ]
        }
        entries.append(.divider)
        if !folderURLs.isEmpty {
            entries.append(.action("Zu Favoriten hinzufügen") { browser.favorites.add(folderURLs) })
        }
        entries += [
            .action("Pfad kopieren") {
                activate(pane, ids)
                browser.copyPathsToPasteboard()
            },
            .action("Terminal hier öffnen") {
                activate(pane, ids)
                browser.openTerminal()
            },
            .action("Im Finder zeigen") {
                activate(pane, ids)
                browser.revealInFinder()
            },
            .divider,
            .action("In den Papierkorb", destructive: true) {
                activate(pane, ids)
                browser.trashSelection()
            },
        ]
        return entries
    }

    /// Vorschau unten / rechts ein- und ausschalten (mit Häkchen).
    private var previewToggleEntries: [MenuEntry] {
        [
            .toggle("Vorschaubereich unten", isOn: browser.showPanePreview) { browser.showPanePreview.toggle() },
            .toggle("Vorschau-Spalte rechts", isOn: browser.showInspector) { browser.showInspector.toggle() },
        ]
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
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    /// Bei nur einem Tab ist die Tab-Leiste ausgeblendet – dann sitzt der „+“-Knopf hier.
    var showsNewTabButton = false
    var onNewTab: () -> Void = {}
    /// Fenster aktivieren (Klick in die Pfadleiste)
    var onActivate: () -> Void = {}

    var body: some View {
        HStack(spacing: 4) {
            Button("Zurück", systemImage: "chevron.left") { pane.goBack() }
                .disabled(!pane.canGoBack)
            Button("Vorwärts", systemImage: "chevron.right") { pane.goForward() }
                .disabled(!pane.canGoForward)
            Button("Nach oben", systemImage: "arrow.up") { pane.goUp() }
                .disabled(!pane.canGoUp)
            PathBar(url: pane.currentURL) { url in
                pane.navigate(to: url)
                onActivate()
            }
            Spacer(minLength: 4)
            if showsNewTabButton {
                Button("Neuer Tab", systemImage: "plus.square.on.square", action: onNewTab)
                    .help("Neuer Tab (⌘T)")
            }
            Button("Suchen", systemImage: "magnifyingglass") { pane.isSearchBarVisible.toggle() }
                .help("Suchen (⌘F)")
            // Bei schmalem Fenster wird aus den fünf Segmenten ein Menü – so bleibt der Kopf zusammendrückbar
            // und beim Verkleinern des Fensters wird nicht die Seitenleiste schmaler.
            if !browser.debugHideViewPicker {
                // Eigene Symbolknöpfe statt segmentiertem Picker in ViewThatFits: Der kostete beim Verkleinern
                // des Fensters ~20 ms pro Schritt (Layout-Test, Build 76) und ließ es ruckeln.
                ViewModeButtons(pane: pane)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

}

/// Ansicht wählen (Liste, Kurz, Miniaturen, Spalten, Galerie) – schlanke Symbolknöpfe, billig im Layout.
struct ViewModeButtons: View {
    let pane: PaneState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                let selected = pane.viewMode == mode
                Button {
                    pane.viewMode = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 18)
                        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("\(mode.title) (⌘\(index + 1))")
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }
}

/// Klickbare Pfadleiste: jeder Ordner im Pfad ist ein Sprungziel.
struct PathBar: View {
    @Environment(BrowserState.self) private var browser
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
        if browser.debugHidePathBar {
            Text(url.lastPathComponent)   // Layout-Test: einfache Pfadanzeige
                .lineLimit(1)
                .frame(minWidth: 30, maxWidth: .infinity, alignment: .leading)
        } else {
            crumbs
        }
    }

    private var crumbs: some View {
        // Ohne ScrollView: Die horizontale ScrollView hat Klicks auf die Elemente nicht weitergegeben.
        // Bei Platzmangel werden die mittleren Ordnernamen gekürzt, der aktuelle Ordner bleibt lesbar.
        HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                }
                let isCurrent = index == components.count - 1
                PathCrumb(url: component, isCurrent: isCurrent, navigate: navigate)
                    .layoutPriority(isCurrent ? 2 : (index == 0 ? 1 : 0))
            }
        }
        // Darf beliebig schmal werden (Rest wird abgeschnitten) – sonst hält der Pfad das Fenster breit
        .frame(minWidth: 30, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

/// Ein Element der Pfadleiste: Klick springt in den Ordner, Rechtsklick bietet weitere Aktionen.
private struct PathCrumb: View {
    @Environment(BrowserState.self) private var browser
    let url: URL
    let isCurrent: Bool
    let navigate: (URL) -> Void
    @State private var hovering = false

    private var name: String {
        url.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: url.path)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .frame(width: 14, height: 14)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
                .fontWeight(isCurrent ? .semibold : .regular)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        // Eigene Geste statt Button – hat Vorrang vor allen Gesten der umgebenden Ansichten.
        .highPriorityGesture(TapGesture().onEnded { open() })
        .onHover { hovering = $0 }
        .help(url.path)
        .contextMenu {
            Button("Öffnen") { open() }
            Button("In neuem Tab öffnen") {
                browser.newTab()
                browser.activePane.navigate(to: url)
            }
            Button("Im anderen Fenster öffnen") {
                browser.toggleActivePane()
                browser.activePane.navigate(to: url)
            }
            Divider()
            Button("Pfad kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func open() {
        navigate(url)
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

/// Schmaler Fensterkopf fürs ruhige Layout: nur der Pfad (links ausgerichtet), aktives Fenster farbig.
struct SlimPaneHeader: View {
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    let isActive: Bool
    var onActivate: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            if let search = pane.activeSearch {
                Image(systemName: search.spotlightQuery != nil ? "sparkle.magnifyingglass" : "magnifyingglass")
                Text(pane.title).bold().lineLimit(1)
                Spacer()
            } else {
                PathBar(url: pane.currentURL) { url in
                    pane.navigate(to: url)
                    onActivate()
                }
            }
        }
        .font(.callout)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? browser.settings.activeColor.opacity(0.08) : .clear)
    }
}
