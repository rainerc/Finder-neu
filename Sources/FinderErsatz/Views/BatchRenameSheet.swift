import SwiftUI
import AppKit

/// Stapel-Umbenennen wie im Finder: Text ersetzen, Text hinzufügen oder neu nummerieren – mit Vorschau.
struct BatchRenameSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: BatchRenameRequest

    enum Mode: String, CaseIterable, Identifiable {
        case replace, regex, add, format
        var id: String { rawValue }
        var title: String {
            switch self {
            case .replace: "Text ersetzen"
            case .regex: "Regex"
            case .add: "Text hinzufügen"
            case .format: "Formatieren"
            }
        }
    }

    enum Position: String, CaseIterable, Identifiable {
        case before, after
        var id: String { rawValue }
        var title: String { self == .before ? "vor dem Namen" : "nach dem Namen" }
    }

    @State private var mode: Mode
    @State private var find = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var addText = ""
    @State private var addPosition: Position = .after
    @State private var baseName = "Datei"
    @State private var separator = " "
    @State private var startNumber = 1
    @State private var digits = 2
    @State private var numberPosition: Position = .after
    @State private var keepExtension = true
    @State private var regexPattern = ""
    @State private var regexReplacement = ""
    @State private var regexCaseSensitive = false
    @State private var regexHelperTab: RegexHelperSheet.Tab?

    init(request: BatchRenameRequest) {
        self.request = request
        _mode = State(initialValue: request.startWithRegex ? .regex : .replace)
    }

    var body: some View {
        let preview = previewNames
        let problem = validate(preview)
        VStack(alignment: .leading, spacing: 12) {
            Text(request.items.count == 1 ? "„\(request.items[0].name)“ umbenennen" : "\(request.items.count) Objekte umbenennen")
                .font(.headline)
            Picker("Art", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Form {
                switch mode {
                case .replace:
                    TextField("Suchen", text: $find)
                    TextField("Ersetzen durch", text: $replacement)
                    Toggle("Groß-/Kleinschreibung beachten", isOn: $caseSensitive)
                case .regex:
                    TextField("Muster", text: $regexPattern)
                        .font(.body.monospaced())
                    TextField("Ersetzen durch ($1, $2 …)", text: $regexReplacement)
                        .font(.body.monospaced())
                    Toggle("Groß-/Kleinschreibung beachten", isOn: $regexCaseSensitive)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hilfe beim Finden des Musters").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Assistent …", systemImage: "wand.and.stars") { regexHelperTab = .wizard }
                                .help("Ziel wählen (z. B. Datum umstellen, Teile tauschen) – die App baut das Muster")
                            Button("Werkstatt …", systemImage: "hammer") { regexHelperTab = .workshop }
                                .help("Muster selbst bauen und live an den Namen testen (wie regex101)")
                            Button("Anleitung …", systemImage: "book") { regexHelperTab = .guide }
                                .help("Ausführliche Erklärung mit Beispielen")
                        }
                    }
                case .add:
                    TextField("Text", text: $addText)
                    Picker("Position", selection: $addPosition) {
                        ForEach(Position.allCases) { Text($0.title).tag($0) }
                    }
                case .format:
                    TextField("Name", text: $baseName)
                    TextField("Trennzeichen", text: $separator)
                    Stepper("Beginnen bei \(startNumber)", value: $startNumber, in: 0...99_999)
                    Stepper("Stellen: \(digits) (z. B. \(String(repeating: "0", count: max(digits - 1, 0)))1)", value: $digits, in: 1...6)
                    Picker("Nummer", selection: $numberPosition) {
                        ForEach(Position.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Dateiendung beibehalten", isOn: $keepExtension)
            }
            .formStyle(.grouped)

            Text("Vorschau").font(.subheadline.bold())
            List(Array(zip(request.items, preview).enumerated()), id: \.offset) { _, pair in
                HStack {
                    Text(pair.0.name).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(pair.1).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(pair.1 == pair.0.name ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
            .frame(minHeight: 160)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Umbenennen") {
                    browser.applyBatchRename(zip(request.items, preview).map { (url: $0.0.url, newName: $0.1) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || zip(request.items, preview).allSatisfy { $0.0.name == $0.1 })
            }
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .sheet(item: $regexHelperTab) { tab in
            RegexHelperSheet(purpose: .rename, sampleNames: request.items.map { split($0).0 },
                             pattern: regexPattern, replacement: regexReplacement,
                             caseSensitive: regexCaseSensitive, initialTab: tab) { pattern, replacement, caseSensitive in
                regexPattern = pattern
                regexReplacement = replacement
                regexCaseSensitive = caseSensitive
            }
        }
    }

    // MARK: Namen berechnen

    private var previewNames: [String] {
        request.items.enumerated().map { index, item in
            let (stem, ext) = split(item)
            let newStem: String
            switch mode {
            case .replace:
                if find.isEmpty {
                    newStem = stem
                } else {
                    newStem = stem.replacingOccurrences(of: find, with: replacement,
                                                        options: caseSensitive ? [] : [.caseInsensitive])
                }
            case .regex:
                if let regex = compiledRegex {
                    newStem = regex.stringByReplacingMatches(in: stem, range: NSRange(stem.startIndex..., in: stem),
                                                             withTemplate: regexReplacement)
                } else {
                    newStem = stem
                }
            case .add:
                newStem = addPosition == .before ? addText + stem : stem + addText
            case .format:
                let number = String(format: "%0\(digits)ld", startNumber + index)
                newStem = numberPosition == .after ? baseName + separator + number : number + separator + baseName
            }
            return ext.isEmpty ? newStem : "\(newStem).\(ext)"
        }
    }

    private var compiledRegex: NSRegularExpression? {
        guard !regexPattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: regexPattern, options: regexCaseSensitive ? [] : [.caseInsensitive])
    }

    /// Name ohne und mit Endung. Bei „Endung beibehalten“ wird nur der Teil vor der Endung verändert.
    private func split(_ item: FileItem) -> (String, String) {
        let ext = (item.name as NSString).pathExtension
        guard keepExtension, !ext.isEmpty, !item.isBrowsableFolder else { return (item.name, "") }
        return ((item.name as NSString).deletingPathExtension, ext)
    }

    private func validate(_ names: [String]) -> String? {
        if mode == .regex, !regexPattern.isEmpty, compiledRegex == nil { return "Ungültiger regulärer Ausdruck." }
        if names.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) { return "Leere Namen sind nicht erlaubt." }
        if names.contains(where: { $0.contains("/") || $0.contains(":") }) { return "Namen dürfen kein „/“ oder „:“ enthalten." }
        if names.contains(where: { $0.hasPrefix(".") }) { return "Namen mit „.“ am Anfang wären unsichtbar." }
        var seen = Set<String>()
        for (item, name) in zip(request.items, names) {
            let key = item.url.deletingLastPathComponent().appending(path: name).path.lowercased()
            if !seen.insert(key).inserted { return "Mehrere Objekte bekämen den Namen „\(name)“." }
        }
        let sources = Set(request.items.map { $0.url.path.lowercased() })
        for (item, name) in zip(request.items, names) where name != item.name {
            let target = item.url.deletingLastPathComponent().appending(path: name)
            if !sources.contains(target.path.lowercased()), FileManager.default.fileExists(atPath: target.path) {
                return "„\(name)“ gibt es bereits."
            }
        }
        return nil
    }
}
