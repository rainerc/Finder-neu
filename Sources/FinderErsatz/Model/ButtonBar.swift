import AppKit
import Observation

/// Ein Knopf der eigenen Knopfleiste: startet ein Programm (optional mit der Auswahl) oder einen Shell-Befehl.
struct ToolButton: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case app, command }

    var id = UUID()
    var title: String
    var kind: Kind
    /// Programm (.app) bei `kind == .app`
    var appPath: String = ""
    /// Ausgewählte Dateien an das Programm übergeben
    var passSelection = true
    /// Shell-Befehl mit Platzhaltern (%s, %n, %p, %o, %t) bei `kind == .command`
    var command: String = ""
    /// Befehl im Terminal statt im Hintergrund ausführen (für interaktive Programme)
    var runInTerminal = false
    /// SF-Symbol für Befehle (Programme zeigen ihr eigenes Symbol)
    var symbol: String = "terminal"
}

@MainActor
@Observable
final class ButtonBarStore {
    static let shared = ButtonBarStore()
    private static let key = "toolButtons"

    var buttons: [ToolButton] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([ToolButton].self, from: data) {
            buttons = stored
        } else {
            buttons = Self.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(buttons) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func upsert(_ button: ToolButton) {
        if let index = buttons.firstIndex(where: { $0.id == button.id }) {
            buttons[index] = button
        } else {
            buttons.append(button)
        }
    }

    func remove(_ id: ToolButton.ID) {
        buttons.removeAll { $0.id == id }
    }

    func move(_ id: ToolButton.ID, by offset: Int) {
        guard let index = buttons.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), buttons.count - 1)
        guard target != index else { return }
        let button = buttons.remove(at: index)
        buttons.insert(button, at: target)
    }

    /// Programm per Ziehen auf die Leiste hinzufügen
    func addApplication(_ url: URL) {
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        buttons.append(ToolButton(title: name, kind: .app, appPath: url.path))
    }

    private static var defaults: [ToolButton] {
        var result: [ToolButton] = []
        let workspace = NSWorkspace.shared
        if let terminal = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            result.append(ToolButton(title: "Terminal", kind: .app, appPath: terminal.path, passSelection: false))
        }
        if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            result.append(ToolButton(title: "TextEdit", kind: .app, appPath: textEdit.path))
        }
        result.append(ToolButton(title: "Größe", kind: .command, command: "du -sh %s", symbol: "scalemass"))
        result.append(ToolButton(title: "Git-Status", kind: .command, command: "git status", symbol: "arrow.triangle.branch"))
        return result
    }
}
