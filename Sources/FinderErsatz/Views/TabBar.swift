import SwiftUI

/// Tab-Leiste einer Seite. Wird nur angezeigt, wenn mehr als ein Tab offen ist (wie im Finder).
struct TabBar: View {
    let group: PaneGroup
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 1) {
            ForEach(group.tabs) { tab in
                TabButton(
                    title: tab.title,
                    isSelected: tab.id == group.selectedID,
                    select: {
                        onActivate()
                        group.select(tab.id)
                    },
                    close: { _ = group.close(tab.id) }
                )
            }
            Button("Neuer Tab", systemImage: "plus") {
                onActivate()
                group.newTab()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .help("Neuer Tab (⌘T)")
        }
        .frame(height: 26)
        .background(.bar)
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Tab schließen (⌘W)")

            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}
