import SwiftUI
import AppKit

/// Protokoll aller Dateiaktionen (⌃⇧⌘L): neueste oben, durchsuchbar, Pfade anklickbar.
struct ActionLogSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var onlyErrors = false
    @State private var confirmClear = false

    private var log: ActionLog { .shared }

    private var shown: [ActionLog.Entry] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        return log.entries.reversed().filter { entry in
            (!onlyErrors || entry.isError)
                && (needle.isEmpty || entry.title.localizedStandardContains(needle)
                    || entry.details.contains { $0.localizedStandardContains(needle) })
        }
    }

    var body: some View {
        let shown = shown
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Protokoll der Dateiaktionen").font(.headline)
                Spacer()
                Toggle("Nur Fehler", isOn: $onlyErrors).toggleStyle(.checkbox)
                TextField("Suchen", text: $filter, prompt: Text("Name, Ordner, Aktion …"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            if shown.isEmpty {
                ContentUnavailableView("Keine Einträge", systemImage: "list.bullet.rectangle",
                                       description: Text(log.entries.isEmpty ? "Kopieren, Umbenennen, Löschen usw. erscheinen hier." : "Nichts passt zur Suche."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            if entry.isError {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            Text(entry.title).bold()
                            Spacer()
                            Text(entry.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        ForEach(Array(entry.details.prefix(20).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .contextMenu {
                                    if let url = revealURL(line) {
                                        Button("Im aktiven Fenster zeigen") { reveal(url) }
                                    }
                                    Button("Zeile kopieren") { copy(line) }
                                }
                        }
                        if entry.details.count > 20 {
                            Text("… und \(entry.details.count - 20) weitere").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                Text("\(log.entries.count) Einträge").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Leeren …") { confirmClear = true }
                    .disabled(log.entries.isEmpty)
                Button("Als Text kopieren") { copy(log.text(for: Array(shown.reversed()))) }
                    .disabled(shown.isEmpty)
                Button("Protokolldatei zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
                }
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 440, idealHeight: 620)
        .confirmationDialog("Protokoll leeren?", isPresented: $confirmClear) {
            Button("Leeren", role: .destructive) { log.clear() }
        } message: {
            Text("Alle Einträge werden gelöscht. Die Dateien selbst bleiben unverändert.")
        }
    }

    /// Erster Pfad einer Detailzeile (bei „a → b“ das Ziel, wenn es ein Pfad ist)
    private func revealURL(_ line: String) -> URL? {
        let parts = line.components(separatedBy: " → ")
        let candidate = parts.count == 2 && (parts[1].hasPrefix("/") || parts[1].hasPrefix("~"))
            ? parts[1]
            : parts.count == 2 ? (parts[0] as NSString).deletingLastPathComponent + "/" + parts[1] : parts[0]
        guard candidate.hasPrefix("/") || candidate.hasPrefix("~") else { return nil }
        let url = URL(filePath: (candidate as NSString).expandingTildeInPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func reveal(_ url: URL) {
        let pane = browser.activePane
        pane.navigate(to: url.deletingLastPathComponent())
        pane.selection = [url.normalizedFileURL]
        dismiss()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
