import SwiftUI

// MARK: - Attribute ändern

/// Attribute für viele Objekte auf einmal ändern (Total Commander: „Dateiattribute ändern“)
struct AttributesSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: AttributesRequest

    enum TriState: String, CaseIterable { case keep, on, off }

    @State private var setModified = false
    @State private var modified = Date.now
    @State private var setCreated = false
    @State private var created = Date.now
    @State private var setPermissions = false
    /// Bits in der Reihenfolge rwx rwx rwx (Besitzer, Gruppe, Andere)
    @State private var bits: [Bool] = Array(repeating: false, count: 9)
    @State private var locked = TriState.keep
    @State private var hidden = TriState.keep
    @State private var hideExtension = TriState.keep
    @State private var recursive = false

    private var containsFolders: Bool {
        request.urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private var mode: Int {
        bits.enumerated().reduce(0) { result, entry in entry.element ? result | (1 << (8 - entry.offset)) : result }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.urls.count == 1 ? "Attribute von „\(request.urls[0].lastPathComponent)“"
                                         : "Attribute von \(request.urls.count) Objekten")
                .font(.headline)
            Form {
                Section("Datum") {
                    HStack {
                        Toggle("Änderungsdatum", isOn: $setModified)
                        DatePicker("", selection: $modified).labelsHidden().disabled(!setModified)
                        Button("Jetzt") { modified = .now; setModified = true }
                    }
                    HStack {
                        Toggle("Erstellungsdatum", isOn: $setCreated)
                        DatePicker("", selection: $created).labelsHidden().disabled(!setCreated)
                        Button("Wie Änderung") { created = modified; setCreated = true }
                    }
                }
                Section("Rechte") {
                    Toggle("Rechte setzen (\(String(mode, radix: 8)))", isOn: $setPermissions)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        GridRow {
                            Text("")
                            Text("Lesen").font(.caption)
                            Text("Schreiben").font(.caption)
                            Text("Ausführen").font(.caption)
                        }
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                Text(["Besitzer", "Gruppe", "Andere"][row])
                                ForEach(0..<3, id: \.self) { column in
                                    Toggle("", isOn: $bits[row * 3 + column]).labelsHidden()
                                }
                            }
                        }
                    }
                    .disabled(!setPermissions)
                }
                Section("Eigenschaften") {
                    triPicker("Gesperrt (Finder-Schloss)", $locked)
                    triPicker("Unsichtbar", $hidden)
                    triPicker("Endung ausblenden", $hideExtension)
                }
                if containsFolders {
                    Toggle("Auch für alle Objekte in den Ordnern", isOn: $recursive)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") {
                    browser.applyAttributes(changes, to: request.urls)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(changes.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 520)
        .onAppear(perform: loadFromFirst)
    }

    private func triPicker(_ title: String, _ value: Binding<TriState>) -> some View {
        Picker(title, selection: value) {
            Text("nicht ändern").tag(TriState.keep)
            Text("ein").tag(TriState.on)
            Text("aus").tag(TriState.off)
        }
    }

    private var changes: AttributeChanges {
        var result = AttributeChanges()
        if setModified { result.modified = modified }
        if setCreated { result.created = created }
        if setPermissions { result.permissions = mode }
        result.locked = locked == .keep ? nil : locked == .on
        result.hidden = hidden == .keep ? nil : hidden == .on
        result.hideExtension = hideExtension == .keep ? nil : hideExtension == .on
        result.recursive = recursive
        return result
    }

    /// Startwerte vom ersten Objekt
    private func loadFromFirst() {
        guard let first = request.urls.first else { return }
        let values = try? first.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        modified = values?.contentModificationDate ?? .now
        created = values?.creationDate ?? .now
        let attributes = (try? FileManager.default.attributesOfItem(atPath: first.path)) ?? [:]
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        bits = (0..<9).map { mode & (1 << (8 - $0)) != 0 }
    }
}

// MARK: - Aufteilen

struct SplitSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: SplitRequest

    @AppStorage("split.sizeMB") private var sizeMB = 100.0
    @AppStorage("split.toOther") private var toOtherPane = true

    private static let presets: [(String, Double)] = [
        ("10 MB", 10), ("25 MB (E-Mail)", 25), ("100 MB", 100), ("700 MB (CD)", 700),
        ("1 GB", 1_000), ("4 GB (FAT32)", 4_095), ("4,7 GB (DVD)", 4_700),
    ]

    private var partSize: Int64 { Int64(max(sizeMB, 0.01) * 1_000_000) }
    private var partCount: Int64 { max(1, (request.size + partSize - 1) / partSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("„\(request.file.lastPathComponent)“ aufteilen").font(.headline)
            Text("Größe: \(request.size.formatted(.byteCount(style: .file)))").foregroundStyle(.secondary)
            HStack {
                Text("Teilgröße:")
                TextField("", value: $sizeMB, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 90)
                Text("MB")
                Menu("Vorgaben") {
                    ForEach(Self.presets, id: \.0) { preset in
                        Button(preset.0) { sizeMB = preset.1 }
                    }
                }
                .fixedSize()
            }
            Text("Ergibt \(partCount) Teile: \(request.file.lastPathComponent).001 … .\(String(format: "%03lld", partCount))")
                .font(.callout)
                .foregroundStyle(partCount > 999 ? .orange : .secondary)
            Picker("Ziel:", selection: $toOtherPane) {
                Text("Anderes Fenster (\(browser.otherPane.currentURL.lastPathComponent))").tag(true)
                Text("Gleicher Ordner").tag(false)
            }
            .pickerStyle(.radioGroup)
            Text("Zum Zusammenfügen den ersten Teil (.001) auswählen und „Dateien zusammenfügen“ wählen – auch im Terminal mit cat möglich.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Aufteilen") {
                    let folder = toOtherPane ? browser.otherPane.currentURL : request.file.deletingLastPathComponent()
                    browser.split(request.file, partSize: partSize, into: folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(partCount < 2)
            }
        }
        .padding(18)
        .frame(width: 480)
    }
}

// MARK: - Packen

struct PackSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: PackRequest

    @AppStorage("pack.format") private var formatRaw = ArchiveService.PackFormat.zip.rawValue
    @AppStorage("pack.toOther") private var toOtherPane = false
    @State private var name = ""
    @State private var password = ""

    private var format: ArchiveService.PackFormat { ArchiveService.PackFormat(rawValue: formatRaw) ?? .zip }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.sources.count == 1 ? "„\(request.sources[0].lastPathComponent)“ packen"
                                            : "\(request.sources.count) Objekte packen")
                .font(.headline)
            Form {
                Picker("Format:", selection: $formatRaw) {
                    ForEach(ArchiveService.PackFormat.allCases) { Text($0.title).tag($0.rawValue) }
                }
                HStack {
                    TextField("Name:", text: $name)
                    Text(".\(format.fileExtension)").foregroundStyle(.secondary)
                }
                Picker("Ziel:", selection: $toOtherPane) {
                    Text("Gleicher Ordner").tag(false)
                    Text("Anderes Fenster (\(browser.otherPane.currentURL.lastPathComponent))").tag(true)
                }
                if format == .zip {
                    SecureField("Passwort (optional):", text: $password)
                    Text("ZIP-Verschlüsselung ist schwach (ZipCrypto) – für Vertrauliches lieber ein verschlüsseltes Disk-Image.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("RAR kann macOS nur entpacken, nicht erstellen. Passwörter gibt es hier nur bei ZIP.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Packen") {
                    let folder = toOtherPane ? browser.otherPane.currentURL : (request.sources.first?.deletingLastPathComponent() ?? browser.activePane.currentURL)
                    let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Archiv" : name
                    let archive = FileService.uniqueURL(for: "\(base).\(format.fileExtension)", in: folder)
                    browser.pack(request.sources, to: archive, format: format, password: format == .zip ? password : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 480)
        .onAppear {
            name = request.sources.count == 1 ? request.sources[0].deletingPathExtension().lastPathComponent : "Archiv"
        }
    }
}
