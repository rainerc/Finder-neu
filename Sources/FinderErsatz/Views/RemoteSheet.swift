import SwiftUI
import AppKit

/// FTP/SFTP-Verbindungen (⇧⌘K): gespeicherte Server links, rechts der entfernte Ordner.
/// Herunterladen geht ins aktive Fenster, Hochladen nimmt dessen Auswahl.
struct RemoteSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss

    @AppStorage("remoteConnections") private var storedData = Data()
    @State private var connections: [RemoteConnection] = []
    @State private var selectedID: RemoteConnection.ID?
    @State private var editing: RemoteConnection?
    @State private var editingPassword = ""

    // Verbunden
    @State private var connected: RemoteConnection?
    @State private var password: String?
    @State private var path = "/"
    @State private var entries: [RemoteEntry] = []
    @State private var selection = Set<RemoteEntry.ID>()
    @State private var isBusy = false
    @State private var status = ""
    @State private var errorText: String?
    @State private var askPassword = false
    @State private var passwordInput = ""
    @State private var newFolderName = ""
    @State private var askNewFolder = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            detail.frame(minWidth: 520)
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 520, idealHeight: 640)
        .onAppear(perform: load)
        .sheet(item: $editing) { connection in
            editor(connection)
        }
        .alert("Passwort für \(connected?.label ?? "")", isPresented: $askPassword) {
            SecureField("Passwort", text: $passwordInput)
            Button("Verbinden") {
                if let connection = connected {
                    KeychainStore.setPassword(passwordInput, for: connection.keychainAccount)
                    password = passwordInput
                    Task { await open(connection, at: nil) }
                }
            }
            Button("Abbrechen", role: .cancel) { connected = nil }
        } message: {
            Text("Wird im Schlüsselbund gesichert.")
        }
        .alert("Neuer Ordner", isPresented: $askNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Anlegen") { Task { await makeFolder() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: Seitenleiste

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Server") {
                    ForEach(connections) { connection in
                        Label(connection.label, systemImage: connection.kind == .sftp ? "lock.shield" : "network")
                            .tag(connection.id)
                            .contextMenu {
                                Button("Bearbeiten …") { edit(connection) }
                                Button("Entfernen", role: .destructive) { remove(connection) }
                            }
                    }
                }
            }
            .onChange(of: selectedID) { _, id in
                if let connection = connections.first(where: { $0.id == id }) {
                    password = KeychainStore.password(for: connection.keychainAccount)
                    Task { await open(connection, at: nil) }
                }
            }
            Divider()
            HStack {
                Button("Neu", systemImage: "plus") {
                    edit(RemoteConnection(name: "", kind: .sftp, host: "", port: 22, user: NSUserName()))
                }
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(8)
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var detail: some View {
        if let connection = connected {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button("Nach oben", systemImage: "arrow.up") { Task { await go(to: RemoteFiles.parent(of: path)) } }
                        .disabled(path == "/" || isBusy)
                    Text(connection.label + ":").bold()
                    Text(path).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if isBusy { ProgressView().controlSize(.small) }
                    Button("Aktualisieren", systemImage: "arrow.clockwise") { Task { await go(to: path) } }
                        .disabled(isBusy)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(8)
                Divider()
                Table(entries, selection: $selection) {
                    TableColumn("Name") { entry in
                        Label(entry.name, systemImage: entry.isDirectory ? "folder.fill" : (entry.isLink ? "link" : "doc"))
                    }
                    TableColumn("Größe") { entry in
                        Text(entry.isDirectory ? "--" : entry.size.formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary)
                    }
                    .width(90)
                    TableColumn("Geändert") { entry in
                        Text(entry.modified?.formatted(date: .numeric, time: .shortened) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .width(140)
                }
                .contextMenu(forSelectionType: RemoteEntry.ID.self) { ids in
                    Button("Herunterladen ins aktive Fenster") { Task { await download(ids) } }
                    Button("Löschen …", role: .destructive) { Task { await delete(ids) } }
                } primaryAction: { ids in
                    if ids.count == 1, let entry = entries.first(where: { $0.id == ids.first }), entry.isDirectory || entry.isLink {
                        Task { await go(to: RemoteFiles.join(path, entry.name)) }
                    } else {
                        Task { await download(ids) }
                    }
                }
                Divider()
                HStack {
                    Button("Herunterladen → \(browser.activePane.currentURL.lastPathComponent)", systemImage: "arrow.down.circle") {
                        Task { await download(selection) }
                    }
                    .disabled(selection.isEmpty || isBusy)
                    Button("Hochladen (Auswahl im aktiven Fenster)", systemImage: "arrow.up.circle") {
                        Task { await upload() }
                    }
                    .disabled(browser.activePane.selectedItems.isEmpty || isBusy)
                    Button("Neuer Ordner", systemImage: "folder.badge.plus") {
                        newFolderName = ""
                        askNewFolder = true
                    }
                    .disabled(isBusy)
                    Spacer()
                }
                .padding(8)
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom], 8)
                } else if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom], 8)
                }
            }
        } else {
            ContentUnavailableView {
                Label("Keine Verbindung", systemImage: "server.rack")
            } description: {
                Text("Links einen Server wählen oder mit „Neu“ anlegen. SFTP nutzt deine SSH-Schlüssel, sonst das Passwort aus dem Schlüsselbund. FTP und FTPS laufen über curl.")
            }
        }
    }

    // MARK: Bearbeiten

    private func editor(_ connection: RemoteConnection) -> some View {
        RemoteConnectionEditor(connection: connection, password: editingPassword) { saved, newPassword in
            if let index = connections.firstIndex(where: { $0.id == saved.id }) {
                connections[index] = saved
            } else {
                connections.append(saved)
            }
            KeychainStore.setPassword(newPassword, for: saved.keychainAccount)
            persist()
            selectedID = saved.id
        }
    }

    private func edit(_ connection: RemoteConnection) {
        editingPassword = KeychainStore.password(for: connection.keychainAccount) ?? ""
        editing = connection
    }

    private func remove(_ connection: RemoteConnection) {
        KeychainStore.setPassword("", for: connection.keychainAccount)
        connections.removeAll { $0.id == connection.id }
        if connected?.id == connection.id { connected = nil }
        persist()
    }

    private func load() {
        connections = (try? JSONDecoder().decode([RemoteConnection].self, from: storedData)) ?? []
    }

    private func persist() {
        storedData = (try? JSONEncoder().encode(connections)) ?? Data()
    }

    // MARK: Verbindung

    private func open(_ connection: RemoteConnection, at startPath: String?) async {
        connected = connection
        entries = []
        selection = []
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let start = startPath ?? (connection.path.isEmpty ? try await RemoteFiles.home(connection, password: password) : connection.path)
            path = start
            entries = try await RemoteFiles.list(connection, path: start, password: password)
            status = "\(entries.count) Objekte"
        } catch {
            let message = error.localizedDescription
            if password == nil, message.localizedCaseInsensitiveContains("permission denied")
                || message.localizedCaseInsensitiveContains("login") || message.localizedCaseInsensitiveContains("access denied") {
                passwordInput = ""
                askPassword = true
            } else {
                errorText = message
            }
        }
    }

    private func go(to newPath: String) async {
        guard let connection = connected else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            entries = try await RemoteFiles.list(connection, path: newPath, password: password)
            path = newPath
            selection = []
            status = "\(entries.count) Objekte"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func download(_ ids: Set<RemoteEntry.ID>) async {
        guard let connection = connected else { return }
        let chosen = entries.filter { ids.contains($0.id) }
        let target = browser.activePane.currentURL
        let password = password
        let folder = path
        for entry in chosen {
            let local = FileService.uniqueURL(for: entry.name, in: target)
            let remote = RemoteFiles.join(folder, entry.name)
            browser.operations.enqueue(title: "Herunterladen: \(entry.name)", onSuccess: {
                ActionLog.shared.add("Heruntergeladen von \(connection.label)", details: ["\(remote) → \(ActionLog.short(local))"])
            }) { _ in
                try await RemoteFiles.download(connection, password: password, remotePath: remote, isDirectory: entry.isDirectory, to: local)
            }
        }
        status = "\(chosen.count) Download(s) in der Warteschlange"
    }

    private func upload() async {
        guard let connection = connected else { return }
        let files = browser.activePane.selectedItems.map(\.url)
        let password = password
        let folder = path
        for file in files {
            browser.operations.enqueue(title: "Hochladen: \(file.lastPathComponent)", onSuccess: {
                ActionLog.shared.add("Hochgeladen zu \(connection.label)", details: ["\(ActionLog.short(file)) → \(RemoteFiles.join(folder, file.lastPathComponent))"])
            }) { _ in
                try await RemoteFiles.upload(connection, password: password, local: file, toFolder: folder)
            }
        }
        status = "\(files.count) Upload(s) in der Warteschlange – danach „Aktualisieren“"
    }

    private func makeFolder() async {
        guard let connection = connected, !newFolderName.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await RemoteFiles.makeFolder(connection, password: password, path: RemoteFiles.join(path, newFolderName))
            await go(to: path)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ ids: Set<RemoteEntry.ID>) async {
        guard let connection = connected else { return }
        let chosen = entries.filter { ids.contains($0.id) }
        let alert = NSAlert()
        alert.messageText = chosen.count == 1 ? "„\(chosen[0].name)“ auf dem Server löschen?" : "\(chosen.count) Objekte auf dem Server löschen?"
        alert.informativeText = "Das lässt sich nicht widerrufen. Ordner müssen leer sein."
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            for entry in chosen {
                try await RemoteFiles.delete(connection, password: password, path: RemoteFiles.join(path, entry.name), isDirectory: entry.isDirectory)
            }
            ActionLog.shared.add("Auf \(connection.label) gelöscht", details: chosen.map { RemoteFiles.join(path, $0.name) })
            await go(to: path)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Server anlegen/bearbeiten
private struct RemoteConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var connection: RemoteConnection
    @State var password: String
    let onSave: (RemoteConnection, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(connection.host.isEmpty ? "Neuer Server" : "Server bearbeiten").font(.headline)
            Form {
                TextField("Name:", text: $connection.name, prompt: Text("optional"))
                Picker("Art:", selection: $connection.kind) {
                    ForEach(RemoteConnection.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: connection.kind) { _, kind in connection.port = kind.defaultPort }
                TextField("Server:", text: $connection.host, prompt: Text("z. B. example.com"))
                TextField("Port:", value: $connection.port, format: .number.grouping(.never))
                TextField("Benutzer:", text: $connection.user)
                SecureField("Passwort:", text: $password, prompt: Text(connection.kind == .sftp ? "leer = SSH-Schlüssel" : ""))
                TextField("Startordner:", text: $connection.path, prompt: Text("leer = Benutzerordner"))
            }
            Text("Das Passwort wird im macOS-Schlüsselbund gespeichert.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    onSave(connection, password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(connection.host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}
