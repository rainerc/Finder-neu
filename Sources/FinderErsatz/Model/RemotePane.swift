import AppKit

/// Ein Dateifenster, das einen FTP/SFTP-Server zeigt (statt eines Ordners auf dem Mac).
/// Hängt an `PaneState.remote`; F5/F6, F7, F8 und F2 gehen dann an den Server.
@MainActor
@Observable
final class RemoteBrowser {
    let connection: RemoteConnection
    var password: String?
    private(set) var path = "/"
    private(set) var entries: [RemoteEntry] = []
    var selection = Set<RemoteEntry.ID>()
    private(set) var isBusy = false
    var errorText: String?
    var status = ""
    private var backStack: [String] = []

    init(connection: RemoteConnection) {
        self.connection = connection
        password = KeychainStore.password(for: connection.keychainAccount)
    }

    var selectedEntries: [RemoteEntry] { entries.filter { selection.contains($0.id) } }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoUp: Bool { path != "/" && !path.isEmpty }

    /// Anmelden und Startordner zeigen. Fragt bei Anmeldefehlern nach dem Passwort.
    func start() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        while true {
            do {
                var start = connection.path
                if start.isEmpty { start = try await RemoteFiles.home(connection, password: password) }
                entries = try await RemoteFiles.list(connection, path: start, password: password)
                path = start
                status = "\(entries.count) Objekte"
                return
            } catch {
                let message = error.localizedDescription
                guard Self.isLoginError(message), let entered = Self.askPassword(for: connection, message: message) else {
                    errorText = message
                    return
                }
                password = entered
                KeychainStore.setPassword(entered, for: connection.keychainAccount)
            }
        }
    }

    func go(to newPath: String, recordHistory: Bool = true) async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let listed = try await RemoteFiles.list(connection, path: newPath, password: password)
            if recordHistory, newPath != path { backStack.append(path) }
            entries = listed
            path = newPath
            selection = []
            status = "\(entries.count) Objekte"
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Neu laden, Auswahl behalten, soweit noch vorhanden
    func reload() async {
        let kept = selection
        isBusy = true
        defer { isBusy = false }
        do {
            entries = try await RemoteFiles.list(connection, path: path, password: password)
            selection = kept.intersection(entries.map(\.id))
            errorText = nil
            status = "\(entries.count) Objekte"
        } catch {
            errorText = error.localizedDescription
        }
    }

    func goUp() { Task { await go(to: RemoteFiles.parent(of: path)) } }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        Task { await go(to: previous, recordHistory: false) }
    }

    func open(_ entry: RemoteEntry) {
        Task { await go(to: RemoteFiles.join(path, entry.name)) }
    }

    func fullPath(_ entry: RemoteEntry) -> String { RemoteFiles.join(path, entry.name) }

    static func isLoginError(_ message: String) -> Bool {
        ["permission denied", "login", "access denied", "authentication", "530"].contains {
            message.localizedCaseInsensitiveContains($0)
        }
    }

    static func askPassword(for connection: RemoteConnection, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Passwort für \(connection.label)"
        alert.informativeText = "Anmeldung fehlgeschlagen: \(message)\n\nDas Passwort wird im Schlüsselbund gesichert."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Anmelden")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }
}

extension BrowserState {

    /// Server in einem Dateifenster öffnen (Standard: aktives Fenster)
    func openRemote(_ connection: RemoteConnection, side: PaneSide? = nil) {
        let target = pane(side ?? activeSide)
        target.selection = []
        let remote = RemoteBrowser(connection: connection)
        target.remote = remote
        if let side { activeSide = side }
        Task { await remote.start() }
    }

    func closeRemote(in pane: PaneState) {
        pane.remote = nil
        pane.reload()
    }

    // MARK: F5/F6 zwischen Mac und Server

    /// Wird von F5/F6 aufgerufen. Liefert true, wenn ein Server beteiligt ist (dann ist alles erledigt).
    func remoteTransfer(move: Bool) -> Bool {
        if let remote = activePane.remote {
            if otherPane.remote != nil {
                alertMessage = "Kopieren direkt von Server zu Server geht nicht – bitte über einen Ordner auf dem Mac."
            } else {
                download(remote.selectedEntries, from: remote, to: otherPane, move: move)
            }
            return true
        }
        if let remote = otherPane.remote {
            upload(activePane.selectedItems.map(\.url), from: activePane, to: remote, move: move)
            return true
        }
        return false
    }

    private func download(_ chosen: [RemoteEntry], from remote: RemoteBrowser, to pane: PaneState, move: Bool) {
        guard !chosen.isEmpty else { NSSound.beep(); return }
        let folder = pane.currentURL
        let existing = chosen.filter { FileManager.default.fileExists(atPath: folder.appending(path: $0.name).path) }
        guard let replace = askReplace(existing.map(\.name), where: "im Ordner „\(folder.lastPathComponent)“") else { return }
        let connection = remote.connection, password = remote.password
        let entries = replace ? chosen : chosen.filter { entry in !existing.contains(entry) }
        guard !entries.isEmpty else { flash("Nichts zu tun – alles übersprungen"); return }
        for entry in entries {
            let source = remote.fullPath(entry)
            let local = folder.appending(path: entry.name)
            let verb = move ? "Verschieben" : "Herunterladen"
            operations.enqueue(title: "\(verb): \(entry.name) von \(connection.label)", onSuccess: { [weak remote] in
                ActionLog.shared.add("\(verb) von \(connection.label)", details: ["\(source) → \(ActionLog.short(local))"])
                pane.reload()
                if move, let remote { Task { await remote.reload() } }
            }) { _ in
                try await RemoteFiles.download(connection, password: password, remotePath: source,
                                               isDirectory: entry.isDirectory, to: local)
                if move {
                    try await RemoteFiles.deleteRecursively(connection, password: password, path: source, isDirectory: entry.isDirectory)
                }
            }
        }
    }

    func upload(_ files: [URL], from pane: PaneState, to remote: RemoteBrowser, move: Bool) {
        guard !files.isEmpty else { NSSound.beep(); return }
        pane.rememberSelection()
        let names = Set(remote.entries.map(\.name))
        let existing = files.filter { names.contains($0.lastPathComponent) }
        guard let replace = askReplace(existing.map(\.lastPathComponent), where: "auf \(remote.connection.label)") else { return }
        let connection = remote.connection, password = remote.password, folder = remote.path
        let chosen = replace ? files : files.filter { !existing.contains($0) }
        guard !chosen.isEmpty else { flash("Nichts zu tun – alles übersprungen"); return }
        for file in chosen {
            let target = RemoteFiles.join(folder, file.lastPathComponent)
            let verb = move ? "Verschieben" : "Hochladen"
            operations.enqueue(title: "\(verb): \(file.lastPathComponent) nach \(connection.label)", onSuccess: { [weak self, weak remote] in
                ActionLog.shared.add("\(verb) nach \(connection.label)", details: ["\(ActionLog.short(file)) → \(target)"])
                if move { self?.trash([file]) }
                if let remote { Task { await remote.reload() } }
                pane.reload()
            }) { _ in
                try await RemoteFiles.upload(connection, password: password, local: file, toFolder: folder)
            }
        }
    }

    /// nil = abbrechen, true = ersetzen, false = vorhandene überspringen
    private func askReplace(_ names: [String], where place: String) -> Bool? {
        guard !names.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "„\(names[0])“ gibt es \(place) schon."
                                             : "\(names.count) Objekte gibt es \(place) schon."
        alert.informativeText = names.prefix(8).joined(separator: "\n") + (names.count > 8 ? "\n…" : "")
        alert.addButton(withTitle: "Ersetzen")
        alert.addButton(withTitle: "Überspringen")
        alert.addButton(withTitle: "Abbrechen")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    // MARK: F7, F8, F2 auf dem Server

    func remoteNewFolder(_ remote: RemoteBrowser) {
        guard let name = askText(title: "Neuer Ordner auf \(remote.connection.label)", value: "Neuer Ordner", button: "Anlegen") else { return }
        Task {
            do {
                try await RemoteFiles.makeFolder(remote.connection, password: remote.password, path: RemoteFiles.join(remote.path, name))
                ActionLog.shared.add("Ordner angelegt auf \(remote.connection.label)", details: [RemoteFiles.join(remote.path, name)])
                await remote.reload()
                remote.selection = [name]
            } catch {
                remote.errorText = error.localizedDescription
            }
        }
    }

    func remoteDelete(_ remote: RemoteBrowser) {
        let chosen = remote.selectedEntries
        guard !chosen.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = chosen.count == 1 ? "„\(chosen[0].name)“ auf dem Server löschen?"
                                              : "\(chosen.count) Objekte auf dem Server löschen?"
        alert.informativeText = "Das lässt sich nicht widerrufen – auf dem Server gibt es keinen Papierkorb. Ordner werden samt Inhalt gelöscht."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let connection = remote.connection, password = remote.password
        let paths = chosen.map { (remote.fullPath($0), $0.isDirectory) }
        operations.enqueue(title: "Löschen auf \(connection.label) (\(chosen.count))", onSuccess: { [weak remote] in
            ActionLog.shared.add("Auf \(connection.label) gelöscht", details: paths.map { $0.0 })
            if let remote { Task { await remote.reload() } }
        }) { _ in
            for (path, isDirectory) in paths {
                try await RemoteFiles.deleteRecursively(connection, password: password, path: path, isDirectory: isDirectory)
            }
        }
    }

    func remoteRename(_ remote: RemoteBrowser) {
        guard let entry = remote.selectedEntries.first, remote.selectedEntries.count == 1 else { NSSound.beep(); return }
        guard let name = askText(title: "Umbenennen auf \(remote.connection.label)", value: entry.name, button: "Umbenennen"),
              name != entry.name else { return }
        Task {
            do {
                try await RemoteFiles.rename(remote.connection, password: remote.password,
                                             from: remote.fullPath(entry), to: RemoteFiles.join(remote.path, name))
                ActionLog.shared.add("Umbenannt auf \(remote.connection.label)", details: ["\(entry.name) → \(name)"])
                await remote.reload()
                remote.selection = [name]
            } catch {
                remote.errorText = error.localizedDescription
            }
        }
    }

    private func askText(title: String, value: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains("/") else { return nil }
        return text
    }
}
