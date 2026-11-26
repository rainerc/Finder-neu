import SwiftUI
import AppKit

/// Ansichten „Kurz“ (mehrspaltige Namensliste wie im Commander) und „Miniaturen“ (Vorschaubilder).
struct FileGridView<Menu: View>: View {
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    let mode: ViewMode
    let onOpen: (Set<FileItem.ID>) -> Void
    @ViewBuilder let menu: (Set<FileItem.ID>) -> Menu

    @State private var anchor: FileItem.ID?

    private var settings: AppSettings { browser.settings }

    var body: some View {
        Group {
            if mode == .brief {
                ScrollView(.horizontal) {
                    LazyHGrid(rows: [GridItem(.adaptive(minimum: rowHeight, maximum: rowHeight), spacing: 0)],
                              alignment: .top, spacing: 4) {
                        ForEach(pane.items) { item in
                            briefCell(item)
                        }
                    }
                    .padding(4)
                }
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 8)], spacing: 10) {
                        ForEach(pane.items) { item in
                            iconCell(item)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu { menu([]) }
    }

    private var rowHeight: CGFloat { settings.listSize.iconSize + 8 }

    // MARK: Zellen

    private func briefCell(_ item: FileItem) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: settings.listSize.iconSize, height: settings.listSize.iconSize)
            Text(item.name)
                .font(settings.listSize.font)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(nameColor(item))
            TagDots(tags: item.tagList)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(width: 230, height: rowHeight)
        .background(selectionBackground(item))
        .opacity(dimmed(item) ? 0.55 : 1)
        .modifier(CellInteraction(item: item, pane: pane, anchor: $anchor, onOpen: onOpen, menu: menu))
    }

    private func iconCell(_ item: FileItem) -> some View {
        VStack(spacing: 4) {
            ThumbnailView(item: item, size: 72)
                .overlay(alignment: .bottomTrailing) { TagDots(tags: item.tagList) }
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .foregroundStyle(nameColor(item))
        }
        .padding(6)
        .frame(width: 112, height: 116, alignment: .top)
        .background(selectionBackground(item))
        .opacity(dimmed(item) ? 0.55 : 1)
        .modifier(CellInteraction(item: item, pane: pane, anchor: $anchor, onOpen: onOpen, menu: menu))
    }

    private func selectionBackground(_ item: FileItem) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(pane.selection.contains(item.id) ? Color.accentColor.opacity(0.25) : .clear)
    }

    private func nameColor(_ item: FileItem) -> Color {
        if item.isBrowsableFolder, let color = settings.folderColor { return color }
        return .primary
    }

    private func dimmed(_ item: FileItem) -> Bool { item.isHidden && settings.showHiddenDimmed }
}

/// Klick = auswählen, ⌘-Klick = hinzufügen/entfernen, ⇧-Klick = Bereich, Doppelklick = öffnen.
struct CellInteraction<Menu: View>: ViewModifier {
    let item: FileItem
    let pane: PaneState
    @Binding var anchor: FileItem.ID?
    let onOpen: (Set<FileItem.ID>) -> Void
    let menu: (Set<FileItem.ID>) -> Menu

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onOpen([item.id]) }
            .onTapGesture { select() }
            .draggable(item.url)
            .contextMenu {
                menu(pane.selection.contains(item.id) ? pane.selection : [item.id])
            }
    }

    private func select() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if pane.selection.contains(item.id) { pane.selection.remove(item.id) } else { pane.selection.insert(item.id) }
            anchor = item.id
        } else if flags.contains(.shift), let anchor,
                  let from = pane.items.firstIndex(where: { $0.id == anchor }),
                  let to = pane.items.firstIndex(where: { $0.id == item.id }) {
            pane.selection = Set(pane.items[min(from, to)...max(from, to)].map(\.id))
        } else {
            pane.selection = [item.id]
            anchor = item.id
        }
    }
}
