import SwiftUI

/// Umbenennen im Texteditor (Total Commander: „Umbenennen mit Editor“): jede Zeile ein Name,
/// frei bearbeiten (Suchen/Ersetzen ⌘F, Spaltenauswahl mit ⌥), Vorschau der Änderungen, dann übernehmen.
struct RenameEditorSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: RenameEditorRequest

    @AppStorage("renameEditor.keepExtensions") private var keepExtensions = false
    @State private var text = ""

    private struct Change: Identifiable {
        let id: URL
        let oldName: String
        let newName: String
    }

    private var originalLines: [String] {
        request.urls.map { keepExtensions ? Self.baseName($0) : $0.lastPathComponent }
    }

    private var lines: [String] {
        var result = text.components(separatedBy: "\n")
        // Ein abschließender Zeilenumbruch erzeugt keine eigene Zeile
        while result.count > request.urls.count, result.last?.isEmpty == true { result.removeLast() }
        return result
    }

    private var changes: [Change] {
        zip(request.urls, lines).compactMap { url, line in
            let newName = keepExtensions && !url.pathExtension.isEmpty && !Self.isFolder(url)
                ? line + "." + url.pathExtension : line
            return newName == url.lastPathComponent ? nil : Change(id: url, oldName: url.lastPathComponent, newName: newName)
        }
    }

    /// Probleme, die das Übernehmen verhindern
    private var problems: [String] {
        var result: [String] = []
        let lines = lines
        if lines.count != request.urls.count {
            result.append("Zeilenanzahl stimmt nicht: \(lines.count) statt \(request.urls.count). Zeilen nicht löschen oder hinzufügen.")
            return result
        }
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            result.append("Leere Namen sind nicht erlaubt.")
        }
        if lines.contains(where: { $0.contains("/") || $0.contains(":") }) {
            result.append("„/“ und „:“ sind in Namen nicht erlaubt.")
        }
        // Doppelte Zielnamen (Groß/klein wie APFS egal)
        let finalNames = zip(request.urls, lines).map { url, line in
            (keepExtensions && !url.pathExtension.isEmpty && !Self.isFolder(url) ? line + "." + url.pathExtension : line).lowercased()
        }
        if Set(finalNames).count != finalNames.count {
            result.append("Mehrere Objekte bekämen denselben Namen.")
        }
        // Konflikt mit vorhandenen Dateien, die nicht mit umbenannt werden
        let renamedNames = Set(request.urls.map { $0.lastPathComponent.lowercased() })
        for change in changes {
            let target = change.id.deletingLastPathComponent().appending(path: change.newName)
            if !renamedNames.contains(change.newName.lowercased()), FileManager.default.fileExists(atPath: target.path),
               change.newName.lowercased() != change.oldName.lowercased() {
                result.append("„\(change.newName)“ gibt es im Ordner schon.")
                break
            }
        }
        return result
    }

    var body: some View {
        let changes = changes
        let problems = problems
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Im Texteditor umbenennen (\(request.urls.count) Objekte)").font(.headline)
                Spacer()
                Toggle("Endungen nicht bearbeiten", isOn: $keepExtensions)
                    .toggleStyle(.checkbox)
                    .onChange(of: keepExtensions) { resetText() }
            }
            Text("Jede Zeile ist ein Name – Reihenfolge und Zeilenzahl nicht ändern. ⌘F sucht und ersetzt.")
                .font(.caption).foregroundStyle(.secondary)

            HSplitView {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .frame(minWidth: 280)
                List(changes) { change in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(change.oldName).strikethrough().foregroundStyle(.secondary)
                        Text(change.newName)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .overlay {
                    if changes.isEmpty {
                        Text("Noch keine Änderungen").foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 240)
            }
            .frame(minHeight: 320)

            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Button("Zurücksetzen") { resetText() }
                Spacer()
                Text("\(changes.count) Änderung(en)").foregroundStyle(.secondary)
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Umbenennen") {
                    browser.applyBatchRename(changes.map { (url: $0.id, newName: $0.newName) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(changes.isEmpty || !problems.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 620)
        .onAppear { resetText() }
    }

    private func resetText() {
        text = originalLines.joined(separator: "\n")
    }

    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private static func baseName(_ url: URL) -> String {
        isFolder(url) || url.pathExtension.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }
}
