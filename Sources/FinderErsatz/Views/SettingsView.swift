import SwiftUI
import AppKit

/// Einstellungen (⌘,): Darstellung und Tastenkürzel.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Darstellung", systemImage: "paintpalette") }
            ShortcutSettings()
                .tabItem { Label("Tastenkürzel", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 520)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Erscheinungsbild", selection: $settings.appearance) {
                ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("Schriftgröße der Listen", selection: $settings.listSize) {
                ForEach(AppSettings.ListSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Abwechselnde Zeilenfarben", isOn: $settings.alternatingRows)
            Toggle("Unsichtbare Dateien abgeblendet zeigen", isOn: $settings.showHiddenDimmed)

            Section("Farben") {
                HStack {
                    ColorPicker("Markierung des aktiven Fensters", selection: $settings.activeColor, supportsOpacity: false)
                    Button("Standard") { settings.activeColorHex = "" }
                        .disabled(settings.activeColorHex.isEmpty)
                }
                HStack {
                    ColorPicker("Farbe der Ordnernamen", selection: $settings.folderColorBinding, supportsOpacity: false)
                    Button("Standard") { settings.folderColorHex = "" }
                        .disabled(settings.folderColorHex.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var recording: ShortcutAction?

    var body: some View {
        VStack(spacing: 0) {
            List(ShortcutAction.allCases) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    ShortcutRecorder(action: action, recording: $recording)
                    Button("Zurücksetzen", systemImage: "arrow.uturn.backward") { settings.resetShortcut(action) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .opacity(settings.isCustom(action) ? 1 : 0)
                        .disabled(!settings.isCustom(action))
                        .help("Standard wiederherstellen")
                }
            }
            Divider()
            HStack {
                Text("Feld anklicken und neue Tastenkombination drücken. ⌫ entfernt das Kürzel, Esc bricht ab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Alle zurücksetzen") { settings.resetAllShortcuts() }
            }
            .padding(10)
        }
    }
}

/// Zeigt das Kürzel; nach Klick wird die nächste Tastenkombination aufgenommen.
private struct ShortcutRecorder: View {
    @Environment(AppSettings.self) private var settings
    let action: ShortcutAction
    @Binding var recording: ShortcutAction?
    @State private var monitor: Any?

    private var isRecording: Bool { recording == action }

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Taste drücken …" : (settings.shortcut(for: action)?.display ?? "–"))
                .monospaced()
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? Color.accentColor : nil)
        .onChange(of: recording) { _, new in
            if new != action { removeMonitor() }
        }
        .onDisappear { removeMonitor() }
    }

    private func start() {
        recording = action
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let shortcut = Shortcut(event: event)
            MainActor.assumeIsolated {
                if keyCode == 53 {                      // Esc: abbrechen
                    stop()
                } else if (keyCode == 51 || keyCode == 117) && flags.isEmpty {   // ⌫ / Entf: Kürzel entfernen
                    settings.setShortcut(nil, for: action)
                    stop()
                } else if let shortcut {
                    settings.setShortcut(shortcut, for: action)
                    stop()
                }
            }
            return nil   // Taste nicht weiterreichen, solange aufgenommen wird
        }
    }

    private func stop() {
        removeMonitor()
        if recording == action { recording = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
