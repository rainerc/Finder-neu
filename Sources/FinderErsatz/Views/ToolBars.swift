import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Befehlszeile

/// Befehlszeile unter den Fenstern (Total Commander): läuft im Ordner des aktiven Fensters,
/// ↑/↓ blättern im Verlauf, ⌘↩ führt im Terminal aus, Platzhalter %s %n %p %o %t.
struct CommandLineBar: View {
    @Environment(BrowserState.self) private var browser
    @State private var input = ""
    @State private var historyIndex: Int?
    @FocusState private var focused: Bool
    @AppStorage("commandHistory") private var historyData = Data()

    private var history: [String] {
        (try? JSONDecoder().decode([String].self, from: historyData)) ?? []
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(prompt)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 260, alignment: .trailing)
                .help(browser.activePane.currentURL.path)
            TextField("", text: $input, prompt: Text("Befehl – z. B. ls -la, open %s, cd .. (⌘↩ im Terminal)"))
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .focused($focused)
                .onSubmit { submit(inTerminal: false) }
                .onKeyPress(.upArrow) { step(-1); return .handled }
                .onKeyPress(.downArrow) { step(1); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    submit(inTerminal: true)
                    return .handled
                }
            Menu {
                Section("Platzhalter einfügen") {
                    ForEach(CommandRunner.placeholderHelp, id: \.0) { entry in
                        Button("\(entry.0)  \(entry.1)") { input += (input.isEmpty || input.hasSuffix(" ") ? "" : " ") + entry.0 }
                    }
                }
                Button("Ausgewählte Pfade einfügen") {
                    let paths = CommandRunner.expand("%s", browser.commandContext)
                    input += (input.isEmpty || input.hasSuffix(" ") ? "" : " ") + paths
                }
                if !history.isEmpty {
                    Section("Zuletzt") {
                        ForEach(history.suffix(10).reversed(), id: \.self) { entry in
                            Button(entry) { input = entry }
                        }
                    }
                }
            } label: {
                Image(systemName: "percent")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Platzhalter und Verlauf")
            Button("Im Terminal", systemImage: "apple.terminal") { submit(inTerminal: true) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Im Terminal ausführen (⌘↩) – für interaktive Programme")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .onChange(of: browser.commandLineFocusRequest) { focused = true }
    }

    private var prompt: String {
        ActionLog.short(browser.activePane.currentURL) + " %"
    }

    private func submit(inTerminal: Bool) {
        let command = input.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        var list = history.filter { $0 != command }
        list.append(command)
        historyData = (try? JSONEncoder().encode(Array(list.suffix(50)))) ?? Data()
        historyIndex = nil
        input = ""
        browser.runCommandLine(command, inTerminal: inTerminal)
    }

    private func step(_ delta: Int) {
        let list = history
        guard !list.isEmpty else { return }
        let next = (historyIndex ?? list.count) + delta
        if next >= list.count {
            historyIndex = nil
            input = ""
        } else {
            historyIndex = max(0, next)
            input = list[max(0, next)]
        }
    }
}

/// Ausgabe des letzten Befehls (zuklappbar)
struct CommandOutputPanel: View {
    @Environment(BrowserState.self) private var browser
    let output: CommandOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if output.isRunning {
                    ProgressView().controlSize(.mini)
                } else if output.status == 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                Text(output.command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let status = output.status, status != 0 {
                    Text("Code \(status)").font(.caption).foregroundStyle(.red)
                }
                if output.truncated {
                    Text("(gekürzt)").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                if output.isRunning {
                    Button("Stopp") { browser.stopCommand() }
                        .controlSize(.small)
                } else {
                    Button("Kopieren", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output.text, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Ausgabe kopieren")
                }
                Button("Schließen", systemImage: "xmark") {
                    browser.stopCommand()
                    browser.commandOutput = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            ScrollView {
                Text(output.text.isEmpty ? (output.isRunning ? "läuft …" : "(keine Ausgabe)") : output.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: 140)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }
}

// MARK: - Knopfleiste

/// Eigene Knopfleiste über den Fenstern. Programme hineinziehen fügt sie hinzu,
/// Dateien auf einen Knopf ziehen übergibt sie dem Programm bzw. Befehl.
struct ButtonBarView: View {
    @Environment(BrowserState.self) private var browser
    private var store: ButtonBarStore { .shared }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.buttons) { button in
                ToolButtonView(button: button)
            }
            Button("Knopf hinzufügen", systemImage: "plus") { browser.editButton() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Neuen Knopf anlegen – oder ein Programm aus dem Finder auf die Leiste ziehen")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension == "app" }
            apps.forEach { store.addApplication($0) }
            return !apps.isEmpty
        }
    }
}

private struct ToolButtonView: View {
    @Environment(BrowserState.self) private var browser
    let button: ToolButton
    @State private var isTargeted = false

    var body: some View {
        Button {
            browser.perform(button)
        } label: {
            HStack(spacing: 4) {
                icon
                Text(button.title).lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isTargeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .dropDestination(for: URL.self) { urls, _ in
            browser.perform(button, files: urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button("Bearbeiten …") { browser.editButton(button) }
            Button("Nach links") { ButtonBarStore.shared.move(button.id, by: -1) }
            Button("Nach rechts") { ButtonBarStore.shared.move(button.id, by: 1) }
            Divider()
            Button("Entfernen", role: .destructive) { ButtonBarStore.shared.remove(button.id) }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if button.kind == .app {
            Image(nsImage: IconCache.icon(for: URL(filePath: button.appPath)))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: button.symbol.isEmpty ? "terminal" : button.symbol)
        }
    }

    private var helpText: String {
        switch button.kind {
        case .app: button.passSelection ? "Öffnet die Auswahl mit \(button.title)" : "Startet \(button.title)"
        case .command: button.command + (button.runInTerminal ? "  (im Terminal)" : "")
        }
    }
}

/// Knopf anlegen/bearbeiten
struct ButtonEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ButtonEditorRequest
    @State private var button: ToolButton

    init(request: ButtonEditorRequest) {
        self.request = request
        _button = State(initialValue: request.button)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.isNew ? "Neuer Knopf" : "Knopf bearbeiten").font(.headline)
            Form {
                TextField("Titel:", text: $button.title)
                Picker("Art:", selection: $button.kind) {
                    Text("Programm").tag(ToolButton.Kind.app)
                    Text("Befehl (Shell)").tag(ToolButton.Kind.command)
                }
                .pickerStyle(.segmented)
                if button.kind == .app {
                    HStack {
                        TextField("Programm:", text: $button.appPath)
                        Button("Auswählen …") { chooseApp() }
                    }
                    Toggle("Ausgewählte Dateien an das Programm übergeben", isOn: $button.passSelection)
                } else {
                    TextField("Befehl:", text: $button.command, prompt: Text("z. B. du -sh %s"))
                        .font(.system(.body, design: .monospaced))
                    Toggle("Im Terminal ausführen (für interaktive Programme)", isOn: $button.runInTerminal)
                    TextField("Symbol (SF Symbol):", text: $button.symbol, prompt: Text("terminal"))
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(CommandRunner.placeholderHelp, id: \.0) { entry in
                            Text("\(entry.0)  \(entry.1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                if !request.isNew {
                    Button("Entfernen", role: .destructive) {
                        ButtonBarStore.shared.remove(button.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    ButtonBarStore.shared.upsert(button)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(button.title.isEmpty || (button.kind == .app ? button.appPath.isEmpty : button.command.isEmpty))
            }
        }
        .padding(18)
        .frame(width: 520)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        button.appPath = url.path
        if button.title.isEmpty || button.title == "Neuer Knopf" {
            button.title = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
    }
}
