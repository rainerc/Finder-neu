import SwiftUI
import AppKit
import Combine

/// Linke Seitenleiste wie im Finder: eigene Favoriten und Orte (Volumes).
/// Ein Klick öffnet den Ordner im gerade aktiven Fenster.
struct SidebarView: View {
    @Environment(BrowserState.self) private var browser
    @State private var volumes: [URL] = []
    @State private var shares: [URL] = []
    @State private var showConnect = false
    @State private var serverAddress = "smb://"
    @State private var cloudFolders: [URL] = []
    @State private var renaming: Favorite?
    @State private var renameText = ""
    @State private var renamingSmart: SmartFolder?
    // Auf-/zugeklappte Abschnitte (bleiben gespeichert)
    @AppStorage("sidebar.favorites") private var showFavorites = true
    @AppStorage("sidebar.smart") private var showSmart = true
    @AppStorage("sidebar.tags") private var showTags = true
    @AppStorage("sidebar.cloud") private var showCloud = true
    @AppStorage("sidebar.network") private var showNetwork = true
    @AppStorage("sidebar.places") private var showPlaces = true

    private var favorites: FavoritesStore { browser.favorites }

    /// Markiert den Eintrag, der dem Ordner des aktiven Fensters entspricht.
    private var selection: Binding<URL?> {
        Binding(
            get: { browser.activePane.activeSearch?.sidebarTag ?? browser.activePane.currentURL },
            set: { url in if let url { open(url) } }
        )
    }

    /// Ordner öffnen – oder bei „finderersatz://…“ eine Abfrage (Zuletzt benutzt, Tag, intelligenter Ordner) zeigen.
    private func open(_ url: URL) {
        guard url.scheme == "finderersatz" else {
            browser.activePane.navigate(to: url)
            return
        }
        if url == SearchQuery.recentsTag {
            browser.showRecents()
        } else if let tag = FinderTag.allCases.first(where: { SearchQuery.tagTag($0.rawValue) == url }) {
            browser.showTag(tag.rawValue, alternative: tag.englishName)
        } else if let folder = browser.smartFolders.folder(for: url) {
            browser.showSmartFolder(folder)
        }
    }

    var body: some View {
        List(selection: selection) {
            Section("Favoriten", isExpanded: $showFavorites) {
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

            Section("Intelligente Ordner", isExpanded: $showSmart) {
                Label("Zuletzt benutzt", systemImage: "clock")
                    .tag(SearchQuery.recentsTag)
                    .help("Dateien, die in den letzten 30 Tagen geöffnet wurden (⇧⌘F)")
                ForEach(browser.smartFolders.items) { folder in
                    Label(folder.name, systemImage: "gearshape")
                        .tag(folder.sidebarTag)
                        .help(smartFolderHelp(folder))
                        .contextMenu {
                            Button("Im anderen Fenster öffnen") {
                                browser.toggleActivePane()
                                browser.showSmartFolder(folder)
                            }
                            Button("Suchkriterien bearbeiten …") { browser.editSmartFolder(folder) }
                            Button("Umbenennen …") {
                                renameText = folder.name
                                renamingSmart = folder
                            }
                            Divider()
                            Button("Entfernen", role: .destructive) { browser.smartFolders.remove(folder) }
                        }
                }
                .onMove { browser.smartFolders.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    browser.newFinderSearch()
                } label: {
                    Label("Neuer intelligenter Ordner …", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Suche mit Bedingungen (Art, Datum, Größe …) anlegen und als intelligenten Ordner sichern (⌃⌘N)")
            }

            Section("Tags", isExpanded: $showTags) {
                ForEach(FinderTag.allCases) { tag in
                    Label {
                        Text(tag.rawValue)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(tag.color)
                    }
                    .tag(SearchQuery.tagTag(tag.rawValue))
                    .help("Alle Objekte mit dem Tag „\(tag.rawValue)“ (Spotlight)")
                }
            }

            if !cloudFolders.isEmpty {
                Section("Cloud", isExpanded: $showCloud) {
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

            Section("Netzwerk", isExpanded: $showNetwork) {
                ForEach(shares, id: \.self) { share in
                    Label(volumeName(share), systemImage: "server.rack")
                        .help(remoteAddress(share) ?? share.path)
                        .tag(share.normalizedFileURL)
                        .contextMenu {
                            Button("Zu Favoriten hinzufügen") { favorites.add([share]) }
                            Button("Im anderen Fenster öffnen") { browser.otherPane.navigate(to: share) }
                            if let address = remoteAddress(share) {
                                Button("Adresse kopieren") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(address, forType: .string)
                                }
                            }
                            Divider()
                            Button("Trennen") { eject(share) }
                        }
                }
                ForEach(browser.network.servers) { server in
                    Button {
                        if let url = server.url { browser.connect(to: url) }
                    } label: {
                        Label(server.name, systemImage: "network")
                    }
                    .buttonStyle(.plain)
                    .help("Verbinden mit \(server.name) (\(server.kind.rawValue.uppercased()))")
                    .contextMenu {
                        Button("Verbinden …") { if let url = server.url { browser.connect(to: url) } }
                        if let url = server.url {
                            Button("Adresse kopieren") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            }
                        }
                    }
                }
                Button("Mit Server verbinden …", systemImage: "plus.circle") { showConnect = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }

            Section("Orte", isExpanded: $showPlaces) {
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
            browser.network.start()
            reloadVolumes()
            reloadCloudFolders()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in reloadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in reloadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in reloadVolumes() }
        .alert(
            "Intelligenten Ordner umbenennen",
            isPresented: Binding(get: { renamingSmart != nil }, set: { if !$0 { renamingSmart = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") {
                if let folder = renamingSmart { browser.smartFolders.rename(folder, to: renameText) }
                renamingSmart = nil
            }
            Button("Abbrechen", role: .cancel) { renamingSmart = nil }
        }
        .alert("Mit Server verbinden", isPresented: $showConnect) {
            TextField("smb://server/freigabe", text: $serverAddress)
            Button("Verbinden") { connect() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("z. B. smb://nas.local/daten oder afp://server. Anmeldung und Freigabe wählt macOS.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectToServer)) { _ in showConnect = true }
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

    private static let volumeKeys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeURLForRemountingKey,
    ]

    /// Teilt die eingehängten Volumes auf: lokale Laufwerke unter „Orte“, Netzwerkfreigaben unter „Netzwerk“.
    private func reloadVolumes() {
        let all = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.volumeKeys, options: []) ?? []
        var local: [URL] = []
        var network: [URL] = []
        for url in all {
            guard let values = try? url.resourceValues(forKeys: Set(Self.volumeKeys)) else { continue }
            if values.volumeIsLocal == false {
                // Automounter-Pfade (/net, /home, /Network) ausblenden – das sind keine echten Freigaben.
                let path = url.path
                if path == "/net" || path == "/home" || path.hasPrefix("/Network") || path.hasPrefix("/System") { continue }
                network.append(url)
            } else if values.volumeIsBrowsable == true {
                local.append(url)
            }
        }
        volumes = local
        shares = network.sorted { volumeName($0).localizedStandardCompare(volumeName($1)) == .orderedAscending }
    }

    /// z. B. „smb://nas.local/daten“ (ohne Benutzername)
    private func remoteAddress(_ url: URL) -> String? {
        guard let remote = try? url.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting,
              var components = URLComponents(url: remote, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        return components.string
    }

    private func connect() {
        let address = serverAddress.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: address), url.scheme != nil, url.host != nil else {
            browser.alertMessage = "Ungültige Serveradresse „\(address)“."
            return
        }
        // macOS übernimmt Anmeldung und Freigabeauswahl; danach öffnet sich die Freigabe im aktiven Fenster.
        browser.connect(to: url)
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

    private func smartFolderHelp(_ folder: SmartFolder) -> String {
        let query = folder.query
        var parts: [String] = []
        if !query.term.isEmpty { parts.append("„\(query.term)“ (\(query.mode.title))") }
        if !query.contentText.isEmpty { parts.append("enthält „\(query.contentText)“") }
        parts += query.criteria.filter(\.isComplete).map(SearchCriterionRow.summary)
        parts.append(query.searchesEverywhere ? "auf diesem Mac" : "in \(query.root.path)")
        return parts.joined(separator: ", ")
    }
}
