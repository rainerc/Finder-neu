import SwiftUI
import AppKit

/// Prüfsummen berechnen (⌃⌘K) – oder, wenn eine .md5/.sha*-Datei ausgewählt ist, die darin genannten Dateien prüfen.
struct ChecksumSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: ChecksumRequest

    @AppStorage("checksum.algorithm") private var algorithmRaw = Checksum.Algorithm.sha256.rawValue
    @State private var rows: [Row] = []
    @State private var isRunning = false
    @State private var compareText = ""

    struct Row: Identifiable {
        let id = UUID()
        let name: String
        var hash: String?
        var expected: String?
        var error: String?

        var status: Status {
            if error != nil { return .error }
            guard let hash else { return .pending }
            guard let expected else { return .none }
            return hash == expected ? .ok : .mismatch
        }
    }

    enum Status { case pending, none, ok, mismatch, error }

    private var algorithm: Checksum.Algorithm { Checksum.Algorithm(rawValue: algorithmRaw) ?? .sha256 }

    /// Genau eine Prüfsummendatei ausgewählt → Prüfmodus
    private var verifyFile: URL? {
        request.files.count == 1 && Checksum.isChecksumFile(request.files[0]) ? request.files[0] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verifyFile != nil ? "Prüfsummen prüfen: \(verifyFile!.lastPathComponent)" : "Prüfsummen")
                    .font(.headline)
                Spacer()
                if verifyFile == nil {
                    Picker("Verfahren", selection: $algorithmRaw) {
                        ForEach(Checksum.Algorithm.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            List(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    statusIcon(row.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        if let error = row.error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        } else if let hash = row.hash {
                            Text(hash)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("wird berechnet …").font(.caption).foregroundStyle(.secondary)
                        }
                        if row.status == .mismatch, let expected = row.expected {
                            Text("erwartet: \(expected)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    if let hash = row.hash {
                        Button("Kopieren", systemImage: "doc.on.doc") { copy(hash) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Prüfsumme kopieren")
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 180)

            if verifyFile == nil {
                HStack {
                    Text("Vergleichen mit:")
                    TextField("", text: $compareText, prompt: Text("erwartete Prüfsumme einfügen"))
                        .font(.system(.body, design: .monospaced))
                    Button("Einsetzen") {
                        compareText = NSPasteboard.general.string(forType: .string)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                }
                if let result = compareResult {
                    Label(result.text, systemImage: result.ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundStyle(result.ok ? .green : .red)
                }
            } else {
                Text(verifySummary).font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                if isRunning { ProgressView().controlSize(.small) }
                Spacer()
                if verifyFile == nil {
                    Button("Alle kopieren") {
                        copy(Checksum.fileContents(rows.compactMap { row in row.hash.map { (name: row.name, hash: $0) } }))
                    }
                    .disabled(isRunning)
                    Button("Als \(algorithm.title)-Datei sichern …") { save() }
                        .disabled(isRunning)
                }
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 360)
        .task(id: algorithmRaw) { await run() }
    }

    // MARK: Anzeige

    @ViewBuilder
    private func statusIcon(_ status: Status) -> some View {
        switch status {
        case .pending: Image(systemName: "hourglass").foregroundStyle(.secondary)
        case .none: Image(systemName: "number").foregroundStyle(.secondary)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .mismatch: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var compareResult: (ok: Bool, text: String)? {
        let wanted = compareText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        if let row = rows.first(where: { $0.hash == wanted }) {
            return (true, "Stimmt überein: \(row.name)")
        }
        if let other = Checksum.Algorithm(hexLength: wanted.count), other != algorithm {
            return (false, "Das sieht nach \(other.title) aus – oben das Verfahren umstellen")
        }
        return (false, "Keine Datei hat diese Prüfsumme")
    }

    private var verifySummary: String {
        let ok = rows.filter { $0.status == .ok }.count
        let bad = rows.filter { $0.status == .mismatch }.count
        let errors = rows.filter { $0.status == .error }.count
        if rows.isEmpty { return isRunning ? "" : "Keine Einträge in der Datei erkannt." }
        return "\(ok) in Ordnung · \(bad) abweichend · \(errors) fehlend/unlesbar"
    }

    // MARK: Berechnen

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        if let verifyFile {
            await verify(verifyFile)
            return
        }
        rows = request.files.map { Row(name: $0.lastPathComponent) }
        let algorithm = algorithm
        for (index, url) in request.files.enumerated() {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                Result { try Checksum.compute(algorithm, of: url) }
            }.value
            if Task.isCancelled { return }
            switch result {
            case .success(let hash): rows[index].hash = hash
            case .failure(let error): rows[index].error = error.localizedDescription
            }
        }
    }

    private func verify(_ file: URL) async {
        guard let text = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)) else {
            rows = [Row(name: file.lastPathComponent, error: "Datei nicht lesbar")]
            return
        }
        let entries = Checksum.parse(text, fallback: Checksum.Algorithm(rawValue: file.pathExtension.lowercased()))
        rows = entries.map { Row(name: $0.name, expected: $0.expected) }
        let folder = file.deletingLastPathComponent()
        for (index, entry) in entries.enumerated() {
            let url = folder.appending(path: entry.name)
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                Result { try Checksum.compute(entry.algorithm, of: url) }
            }.value
            if Task.isCancelled { return }
            switch result {
            case .success(let hash): rows[index].hash = hash
            case .failure: rows[index].error = "fehlt oder nicht lesbar"
            }
        }
    }

    // MARK: Aktionen

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        browser.flash("Prüfsumme kopiert")
    }

    private func save() {
        let results = rows.compactMap { row in row.hash.map { (name: row.name, hash: $0) } }
        guard let first = request.files.first, !results.isEmpty else { return }
        let folder = first.deletingLastPathComponent()
        let baseName = request.files.count == 1 ? first.lastPathComponent : folder.lastPathComponent
        let target = FileService.uniqueURL(for: "\(baseName).\(algorithm.fileExtension)", in: folder)
        do {
            try Checksum.fileContents(results).write(to: target, atomically: true, encoding: .utf8)
            browser.recordUndo(.created([target]))
            browser.flash("Gesichert: \(target.lastPathComponent)")
            browser.reloadAll()
        } catch {
            browser.alertMessage = error.localizedDescription
        }
    }
}
