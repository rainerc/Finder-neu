import SwiftUI
import AppKit
import Combine

/// Linke Seitenleiste wie im Finder: eigene Favoriten und Orte (Volumes).
/// Ein Klick öffnet den Ordner im gerade aktiven Fenster.
struct SidebarView: View {
    @Environment(BrowserState.self) private var browser
    @State private var volumes: [URL] = []
    @State private var cloudFolders: [URL] = []
    @State private var renaming: Favorite?
    @State private var renameText = ""

    private var favorites: FavoritesStore { browser.favorites }

    /// Markiert den Eintrag, der dem Ordner des aktiven Fensters entspricht.
    private var selection: Binding<URL?> {
        Binding(
            get: { browser.activePane.currentURL },
            set: { url in if let url { browser.activePane.navigate(to: url) } }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Favoriten") {
                ForEach(favorites.items) { favorite in
                    Label(favorite.name, systemImage: favorite.symbolName)
                        .opacity(favorite.exists ? 1 : 0.4)
                        .help(favorite.url.path)
                        .tag(favorite.url)
                        .contextMenu { favoriteMenu(favorite) }
                }
                .onMove { favorites.move(fromOffsets: $0, toOffset: $1) }
                .dropDestination(for: URL.self) { urls, offset in
                    favorites.add(urls, at: offset)
                }
            }

            if !cloudFolders.isEmpty {
                Section("Cloud") {
                    ForEach(cloudFolders, id: \.self) { folder in
                        Label(cloudName(folder), systemImage: cloudSymbol(folder))
                            .help(folder.path)
                            .tag(folder.normalizedFileURL)
                            .contextMenu {
                                Button("Zu Favoriten hinzufügen") { favorites.add([folder]) }
                                Button("Im anderen Fenster öffnen") { browser.otherPane.navigate(to: folder) }
                            }
                    }
                }
            }

            Section("Orte") {
                ForEach(volumes, id: \.self) { volume in
                    Label(volumeName(volume), systemImage: volume.path == "/" ? "internaldrive" : "externaldrive")
                        .tag(volume.normalizedFileURL)
                        .contextMenu {
                            Button("Zu Favoriten hinzufügen") { favorites.add([volume]) }
                            Button("Im anderen Fenster öffnen") { browser.otherPane.navigate(to: volume) }
                            if volume.path != "/" {
                                Divider()
                                Button("Auswerfen") { eject(volume) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Aktuellen Ordner hinzufügen", systemImage: "plus") {
                    favorites.add([browser.activePane.currentURL])
                }
                .help("Ordner des aktiven Fensters zu den Favoriten hinzufügen (⌃⌘T)")
                .disabled(favorites.contains(browser.activePane.currentURL))
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
        }
        .onAppear {
            reloadVolumes()
            reloadCloudFolders()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in reloadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in reloadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in reloadVolumes() }
        .alert(
            "Favorit umbenennen",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") {
                if let renaming { favorites.rename(renaming, to: renameText) }
                renaming = nil
            }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        } message: {
            Text("Ändert nur den Namen in der Seitenleiste, nicht den Ordner.")
        }
    }

    @ViewBuilder
    private func favoriteMenu(_ favorite: Favorite) -> some View {
        Button("Im anderen Fenster öffnen") { browser.otherPane.navigate(to: favorite.url) }
        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([favorite.url]) }
        Divider()
        Button("Umbenennen …") {
            renameText = favorite.name
            renaming = favorite
        }
        Button("Aus Favoriten entfernen", role: .destructive) { favorites.remove(favorite) }
        Divider()
        Button("Standard-Favoriten wiederherstellen") { favorites.resetToDefaults() }
    }

    private func reloadVolumes() {
        volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeLocalizedNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []
    }

    /// iCloud Drive und alle Cloud-Anbieter, die sich über macOS einbinden (Dropbox, Google Drive, OneDrive, Box …).
    private func reloadCloudFolders() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var result: [URL] = []
        let iCloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) { result.append(iCloud) }
        let cloudStorage = home.appending(path: "Library/CloudStorage")
        if let providers = try? fm.contentsOfDirectory(at: cloudStorage, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            result += providers.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        cloudFolders = result
    }

    private func cloudName(_ url: URL) -> String {
        if url.lastPathComponent == "com~apple~CloudDocs" { return "iCloud Drive" }
        // Ordner heißen z. B. „GoogleDrive-name@example.com“ oder „OneDrive-Persönlich“.
        let name = url.lastPathComponent
        guard let dash = name.firstIndex(of: "-") else { return name }
        let provider = String(name[..<dash])
        let account = String(name[name.index(after: dash)...])
        return "\(provider) (\(account))"
    }

    private func cloudSymbol(_ url: URL) -> String {
        url.lastPathComponent == "com~apple~CloudDocs" ? "icloud" : "cloud"
    }

    private func volumeName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? url.lastPathComponent
    }

    private func eject(_ volume: URL) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        } catch {
            browser.alertMessage = error.localizedDescription
        }
    }
}
