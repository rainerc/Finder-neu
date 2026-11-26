import SwiftUI
import AppKit

/// Galerie-Ansicht wie im Finder: großes Vorschaubild des ausgewählten Objekts, darunter eine Leiste mit Miniaturen.
struct GalleryView<Menu: View>: View {
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    let onOpen: (Set<FileItem.ID>) -> Void
    @ViewBuilder let menu: (Set<FileItem.ID>) -> Menu

    @State private var anchor: FileItem.ID?

    private var focused: FileItem? {
        pane.items.last { pane.selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                VStack(spacing: 8) {
                    if let item = focused {
                        // Größe in 64er-Schritten, damit beim Ziehen am Fenster nicht ständig neu gerendert wird
                        let side = max(64, (min(geometry.size.width - 40, geometry.size.height - 70) / 64).rounded(.down) * 64)
                        ThumbnailView(item: item, size: side)
                            .shadow(radius: 4)
                            .onTapGesture(count: 2) { onOpen([item.id]) }
                            .draggable(item.url)
                            .contextMenu { menu(pane.selection) }
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(item.kind) – \(item.sizeText) – \(item.modified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(pane.items.isEmpty ? "Ordner ist leer" : "Kein Objekt ausgewählt")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(pane.items) { item in
                            ThumbnailView(item: item, size: 64)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(pane.selection.contains(item.id) ? Color.accentColor.opacity(0.35) : .clear)
                                )
                                .overlay(alignment: .bottomTrailing) { TagDots(tags: item.tagList) }
                                .help(item.name)
                                .id(item.id)
                                .modifier(CellInteraction(item: item, pane: pane, anchor: $anchor, onOpen: onOpen, menu: menu))
                        }
                    }
                    .padding(8)
                }
                .frame(height: 92)
                .onChange(of: pane.selection) { _, selection in
                    if let id = focused?.id, selection.contains(id) {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu { menu([]) }
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: pane.currentURL) { selectFirstIfNeeded() }
    }

    private func selectFirstIfNeeded() {
        if pane.selection.isEmpty, let first = pane.items.first { pane.selection = [first.id] }
    }
}
