import SwiftUI
import AppKit

/// Breite einer Spalte der Spaltenansicht.
private let columnWidth: CGFloat = 220

/// Spaltenansicht wie im Finder: links die übergeordneten Ordner, dann der aktuelle Ordner,
/// rechts daneben der Inhalt des ausgewählten Ordners bzw. eine Vorschau der ausgewählten Datei.
///
/// Modell: Die Spalte „aktueller Ordner“ ist immer `pane.currentURL` mit `pane.selection`.
/// Ein Klick in eine andere Spalte setzt deren Ordner als aktuellen Ordner und wählt das Objekt aus –
/// damit funktionieren Kopieren, F5/F6, Pfadleiste usw. unverändert.
struct ColumnBrowserView<Menu: View>: View {
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    let side: PaneSide
    let onOpen: (Set<FileItem.ID>) -> Void
    @ViewBuilder let menu: (Set<FileItem.ID>) -> Menu

    @State private var anchor: FileItem.ID?


    /// Ordner von „/“ bis zum Elternordner des aktuellen Ordners.
    private var ancestors: [URL] {
        var result: [URL] = []
        var current = pane.currentURL
        while current.path != "/" {
            current = current.deletingLastPathComponent().normalizedFileURL
            result.insert(current, at: 0)
        }
        return result
    }

    private var selectedSingle: FileItem? {
        let selected = pane.selectedItems
        return selected.count == 1 ? selected[0] : nil
    }

    var body: some View {
        let chain = ancestors + [pane.currentURL]
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(ancestors.enumerated()), id: \.element) { index, folder in
                        FolderColumn(folder: folder, highlighted: chain[index + 1], showHidden: pane.showHidden,
                                     refresh: pane.items.count) { url in
                            select(url, in: folder)
                        } onOpen: { url in
                            select(url, in: folder)
                            onOpen([url])
                        }
                        Divider()
                    }
                    currentColumn
                    Divider()
                    trailingColumn
                        .id("end")
                }
            }
            .defaultScrollAnchor(.trailing)
            .onChange(of: pane.currentURL) { scrollToEnd(proxy) }
            .onChange(of: pane.selection) { scrollToEnd(proxy) }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu { menu([]) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("end", anchor: .trailing) }
    }

    /// Objekt in einer anderen Spalte angeklickt: deren Ordner wird zum aktuellen Ordner.
    private func select(_ url: URL, in folder: URL) {
        browser.activeSide = side
        if folder != pane.currentURL { pane.navigate(to: folder) }
        pane.selection = [url]
    }

    // MARK: Aktueller Ordner (Mehrfachauswahl, Drag & Drop, Kontextmenü)

    private var currentColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(pane.items) { item in
                        ColumnRow(item: item, isSelected: pane.selection.contains(item.id), isOnPath: false)
                            .id(item.id)
                            .modifier(CellInteraction(item: item, pane: pane, anchor: $anchor, onOpen: onOpen, menu: menu))
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: pane.selection) { _, selection in
                if selection.count == 1, let id = selection.first { proxy.scrollTo(id) }
            }
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
    }

    // MARK: Inhalt des ausgewählten Ordners oder Vorschau

    @ViewBuilder
    private var trailingColumn: some View {
        if let item = selectedSingle, item.isBrowsableFolder {
            FolderColumn(folder: item.url, highlighted: nil, showHidden: pane.showHidden, refresh: 0) { url in
                select(url, in: item.url)
            } onOpen: { url in
                select(url, in: item.url)
                onOpen([url])
            }
        } else if let item = selectedSingle {
            ColumnPreview(item: item)
        } else {
            Color.clear.frame(width: columnWidth)
        }
    }
}

/// Eine Spalte mit dem Inhalt eines (nicht aktuellen) Ordners.
private struct FolderColumn: View {
    let folder: URL
    let highlighted: URL?
    let showHidden: Bool
    /// Ändert sich, wenn der aktuelle Ordner neu geladen wurde – dann auch diese Spalte neu laden.
    let refresh: Int
    let onSelect: (URL) -> Void
    let onOpen: (URL) -> Void

    @State private var items: [FileItem] = []
    @State private var failed = false

    private struct LoadKey: Hashable { let folder: URL; let hidden: Bool; let refresh: Int }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if failed {
                        Label("Nicht lesbar", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    ForEach(items) { item in
                        ColumnRow(item: item, isSelected: false, isOnPath: item.url == highlighted)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onOpen(item.url) }
                            .onTapGesture { onSelect(item.url) }
                            .draggable(item.url)
                    }
                }
                .padding(.vertical, 2)
            }
            .task(id: LoadKey(folder: folder, hidden: showHidden, refresh: refresh)) {
                load()
                if let highlighted { proxy.scrollTo(highlighted, anchor: .center) }
            }
        }
        .frame(width: columnWidth)
    }

    private func load() {
        do {
            let loaded = try FileService.contents(of: folder, includeHidden: showHidden)
            let order = KeyPathComparator(\FileItem.name, comparator: .localizedStandard)
            items = loaded.filter(\.isBrowsableFolder).sorted(using: order)
                + loaded.filter { !$0.isBrowsableFolder }.sorted(using: order)
            failed = false
        } catch {
            items = []
            failed = true
        }
    }
}

/// Zeile einer Spalte: Symbol, Name, Pfeil bei Ordnern.
private struct ColumnRow: View {
    @Environment(BrowserState.self) private var browser
    let item: FileItem
    let isSelected: Bool
    /// Ordner liegt auf dem Pfad zum aktuellen Ordner (schwächer markiert).
    let isOnPath: Bool

    var body: some View {
        let settings = browser.settings
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(for: item.url))
                .resizable()
                .frame(width: settings.listSize.iconSize, height: settings.listSize.iconSize)
            Text(item.name)
                .font(settings.listSize.font)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.isBrowsableFolder ? (settings.folderColor ?? .primary) : .primary)
            TagDots(tags: item.tagList)
            Spacer(minLength: 0)
            if item.isBrowsableFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : isOnPath ? Color.secondary.opacity(0.2) : .clear)
        )
        .padding(.horizontal, 4)
        .opacity(item.isHidden && settings.showHiddenDimmed ? 0.55 : 1)
    }
}

/// Letzte Spalte bei ausgewählter Datei: großes Vorschaubild und Eckdaten.
private struct ColumnPreview: View {
    let item: FileItem

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 10) {
                ThumbnailView(item: item, size: 200)
                    .padding(.top, 16)
                Text(item.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text("\(item.kind) – \(item.sizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        Text("Erstellt").foregroundStyle(.secondary)
                        Text(item.created, format: .dateTime.day().month().year().hour().minute())
                    }
                    GridRow {
                        Text("Geändert").foregroundStyle(.secondary)
                        Text(item.modified, format: .dateTime.day().month().year().hour().minute())
                    }
                    if item.accessed > .distantPast {
                        GridRow {
                            Text("Geöffnet").foregroundStyle(.secondary)
                            Text(item.accessed, format: .dateTime.day().month().year().hour().minute())
                        }
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 280)
    }
}
