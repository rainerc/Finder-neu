import SwiftUI
import AppKit

struct PaneView: View {
    @Environment(BrowserState.self) private var browser
    let side: PaneSide
    var focus: FocusState<PaneSide?>.Binding

    private var isActive: Bool { browser.activeSide == side }

    var body: some View {
        @Bindable var pane = browser.pane(side)

        VStack(spacing: 0) {
            PaneHeader(pane: pane)
                .contentShape(Rectangle())
                .onTapGesture { browser.activeSide = side }
            Divider()

            if let error = pane.errorMessage {
                ContentUnavailableView("Ordner nicht lesbar", systemImage: "lock.fill", description: Text(error))
            } else {
                Table(of: FileItem.self, selection: $pane.selection, sortOrder: $pane.sortOrder) {
                    TableColumn("Name", value: \.name) { item in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(item.name)
                                .lineLimit(1)
                                .opacity(item.isHidden ? 0.55 : 1)
                        }
                    }
                    .width(min: 160, ideal: 260)
                    TableColumn("Änderungsdatum", value: \.modified) { item in
                        Text(item.modified, format: .dateTime.day().month().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 110, ideal: 140)
                    TableColumn("Größe", value: \.size) { item in
                        Text(item.sizeText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Art", value: \.kind) { item in
                        Text(item.kind).foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 120)
                } rows: {
                    ForEach(pane.items) { item in
                        TableRow(item).draggable(item.url)
                    }
                }
                .contextMenu(forSelectionType: FileItem.ID.self) { ids in
                    if !ids.isEmpty {
                        Button("Öffnen") { open(ids, in: pane) }
                        Button("Umbenennen …") { browser.beginRename() }
                        Divider()
                        Button("In anderes Fenster kopieren") { browser.copyToOtherPane() }
                        Button("In anderes Fenster verschieben") { browser.moveToOtherPane() }
                        Divider()
                        Button("Pfad kopieren") { copyPaths(ids) }
                        Button("Im Finder zeigen") { browser.revealInFinder() }
                        Divider()
                        Button("In den Papierkorb", role: .destructive) { browser.trashSelection() }
                    } else {
                        Button("Neuer Ordner") { browser.newFolder() }
                    }
                } primaryAction: { ids in
                    // Doppelklick oder Return
                    open(ids, in: pane)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    browser.drop(urls, into: pane)
                }
                .focused(focus, equals: side)
                .onKeyPress(.tab) {
                    browser.toggleActivePane()
                    return .handled
                }
                .onKeyPress(.delete, phases: .down) { press in
                    guard press.modifiers.isEmpty else { return .ignored }
                    pane.goUp()   // Backspace = übergeordneter Ordner
                    return .handled
                }
            }

            Divider()
            PaneStatusBar(pane: pane)
        }
        .overlay(alignment: .top) {
            // Markierung des aktiven Fensters
            Rectangle()
                .fill(isActive ? Color.accentColor : .clear)
                .frame(height: 3)
        }
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

    private func copyPaths(_ ids: Set<FileItem.ID>) {
        let text = ids.map(\.path).sorted().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct PaneHeader: View {
    let pane: PaneState

    var body: some View {
        HStack(spacing: 4) {
            Button("Zurück", systemImage: "chevron.left") { pane.goBack() }
                .disabled(!pane.canGoBack)
            Button("Vorwärts", systemImage: "chevron.right") { pane.goForward() }
                .disabled(!pane.canGoForward)
            Button("Nach oben", systemImage: "arrow.up") { pane.goUp() }
                .disabled(!pane.canGoUp)
            FavoritesMenu(pane: pane)
            PathBar(url: pane.currentURL) { pane.navigate(to: $0) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct FavoritesMenu: View {
    let pane: PaneState

    private struct Favorite: Identifiable {
        let title: String, icon: String, url: URL
        var id: String { title }
        init(_ title: String, _ icon: String, _ url: URL) { self.title = title; self.icon = icon; self.url = url }
    }

    private var favorites: [Favorite] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return [
            Favorite("Benutzerordner", "house", home),
            Favorite("Schreibtisch", "menubar.dock.rectangle", home.appending(path: "Desktop")),
            Favorite("Dokumente", "doc", home.appending(path: "Documents")),
            Favorite("Downloads", "arrow.down.circle", home.appending(path: "Downloads")),
            Favorite("Programme", "square.grid.3x3", URL(filePath: "/Applications")),
            Favorite("iCloud Drive", "icloud", home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")),
            Favorite("Volumes", "externaldrive", URL(filePath: "/Volumes")),
            Favorite("Startvolume", "internaldrive", URL(filePath: "/")),
        ]
    }

    var body: some View {
        Menu {
            ForEach(favorites) { fav in
                Button(fav.title, systemImage: fav.icon) { pane.navigate(to: fav.url) }
            }
        } label: {
            Label("Favoriten", systemImage: "star")
        }
        .menuIndicator(.hidden)
        .fixedSize()
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
            Text("\(pane.items.count) Objekte")
            if !selected.isEmpty {
                Text("· \(selected.count) ausgewählt")
                if bytes > 0 { Text("(\(bytes.formatted(.byteCount(style: .file))))") }
            }
            Spacer()
            if pane.showHidden { Image(systemName: "eye").help("Unsichtbare Dateien sichtbar") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
