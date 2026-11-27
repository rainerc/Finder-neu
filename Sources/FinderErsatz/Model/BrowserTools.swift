import AppKit

// Total-Commander-Runde 3: Befehlszeile, Knopfleiste, Umbenennen im Texteditor.

/// Ausgabe des letzten Befehls (Befehlszeile oder Knopf)
struct CommandOutput: Identifiable {
    let id = UUID()
    var command: String
    var folder: URL
    var text = ""
    var status: Int32?
    var truncated = false
    var isRunning: Bool { status == nil }
}

struct RenameEditorRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ButtonEditorRequest: Identifiable {
    let id = UUID()
    let button: ToolButton
    let isNew: Bool
}

extension BrowserState {

    /// Platzhalter-Kontext aus beiden Fenstern
    var commandContext: CommandRunner.Context {
        CommandRunner.Context(folder: activePane.currentURL,
                              selection: activePane.selectedItems.map(\.url),
                              otherFolder: otherPane.currentURL,
                              otherSelection: otherPane.selectedItems.map(\.url))
    }

    // MARK: Befehlszeile

    /// Führt eine Eingabe der Befehlszeile aus. `cd` wechselt den Ordner des aktiven Fensters selbst.
    func runCommandLine(_ input: String, inTerminal: Bool = false) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let pane = activePane
        if trimmed == "cd" || trimmed.hasPrefix("cd ") {
            changeDirectory(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces), pane: pane)
            return
        }
        runShell(CommandRunner.expand(trimmed, commandContext), in: pane.currentURL, inTerminal: inTerminal)
    }

    private func changeDirectory(_ argument: String, pane: PaneState) {
        var path = argument
        if (path.hasPrefix("'") && path.hasSuffix("'")) || (path.hasPrefix("\"") && path.hasSuffix("\"")), path.count >= 2 {
            path = String(path.dropFirst().dropLast())
        }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        let target: URL
        if path.isEmpty || path == "~" {
            target = FileManager.default.homeDirectoryForCurrentUser
        } else if path == "-" {
            pane.goBack()
            return
        } else if path.hasPrefix("/") || path.hasPrefix("~") {
            target = URL(filePath: (path as NSString).expandingTildeInPath)
        } else {
            target = pane.currentURL.appending(path: path).standardizedFileURL
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            NSSound.beep()
            flash("cd: „\(path)“ gibt es nicht")
            return
        }
        pane.navigate(to: target)
    }

    /// Shell-Befehl im Hintergrund (Ausgabe unter den Fenstern) oder im Terminal
    func runShell(_ command: String, in folder: URL, inTerminal: Bool) {
        ActionLog.shared.add(inTerminal ? "Befehl im Terminal" : "Befehl", details: [command, "in \(ActionLog.short(folder))"])
        if inTerminal {
            CommandRunner.runInTerminal(command, in: folder)
            return
        }
        commandTask?.cancel()
        commandOutput = CommandOutput(command: command, folder: folder)
        commandTask = Task { [weak self] in
            let result = await CommandRunner.run(command, in: folder)
            guard let self, !Task.isCancelled || result.output.hasSuffix("[abgebrochen]") else { return }
            if self.commandOutput?.command == command {
                self.commandOutput?.text = result.output
                self.commandOutput?.status = result.status
                self.commandOutput?.truncated = result.truncated
            }
            if result.status != 0 {
                ActionLog.shared.add("Befehl beendet mit Code \(result.status)", details: [command], isError: true)
            }
            self.reloadAll()
        }
    }

    func stopCommand() {
        commandTask?.cancel()
    }

    func focusCommandLine() {
        if !settings.showCommandLine { settings.showCommandLine = true }
        commandLineFocusRequest += 1
    }

    // MARK: Knopfleiste

    /// Knopf ausführen. `files`: per Ziehen auf den Knopf abgelegte Dateien statt der Auswahl.
    func perform(_ button: ToolButton, files: [URL]? = nil) {
        var context = commandContext
        if let files { context.selection = files }
        switch button.kind {
        case .app:
            let app = URL(filePath: button.appPath)
            guard FileManager.default.fileExists(atPath: app.path) else {
                alertMessage = "Das Programm „\(button.appPath)“ gibt es nicht mehr."
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            if button.passSelection, !context.selection.isEmpty {
                NSWorkspace.shared.open(context.selection, withApplicationAt: app, configuration: configuration)
                ActionLog.shared.add("Geöffnet mit \(button.title)", details: context.selection.map { ActionLog.short($0) })
            } else if app.lastPathComponent == "Terminal.app" {
                AppLauncher.openTerminal(at: context.folder)
            } else {
                NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            }
        case .command:
            guard !button.command.isEmpty else { return }
            runShell(CommandRunner.expand(button.command, context), in: context.folder, inTerminal: button.runInTerminal)
        }
    }

    func editButton(_ button: ToolButton? = nil) {
        if let button {
            buttonEditorRequest = ButtonEditorRequest(button: button, isNew: false)
        } else {
            buttonEditorRequest = ButtonEditorRequest(
                button: ToolButton(title: "Neuer Knopf", kind: .command, command: "", symbol: "terminal"), isNew: true)
        }
    }

    // MARK: Umbenennen im Texteditor

    /// Ausgewählte Objekte (ohne Auswahl: alle im Ordner) zeilenweise im Editor umbenennen
    func showRenameEditor() {
        let pane = activePane
        let urls = pane.selectedItems.isEmpty ? pane.items.map(\.url) : pane.items.filter { pane.selection.contains($0.id) }.map(\.url)
        guard !urls.isEmpty, pane.activeSearch == nil || !pane.selectedItems.isEmpty else { NSSound.beep(); return }
        pane.rememberSelection()
        renameEditorRequest = RenameEditorRequest(urls: urls)
    }
}
