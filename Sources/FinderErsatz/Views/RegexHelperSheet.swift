import SwiftUI
import AppKit

/// Regex-Assistent für Suche und Stapel-Umbenennen:
/// Bausteine zum Anklicken, fertige Vorlagen, Erklärung auf Deutsch, Muster aus einem Beispielnamen ableiten
/// und ein Live-Test gegen echte Dateinamen (Treffer markiert, Gruppen $1 … und – beim Umbenennen – das Ergebnis).
struct RegexHelperSheet: View {
    enum Purpose { case search, rename }

    @Environment(\.dismiss) private var dismiss
    let purpose: Purpose
    /// Dateinamen zum Ausprobieren (aktueller Ordner bzw. ausgewählte Objekte).
    let sampleNames: [String]
    let onApply: (_ pattern: String, _ replacement: String, _ caseSensitive: Bool) -> Void

    @State private var pattern: String
    @State private var replacement: String
    @State private var caseSensitive: Bool
    @State private var exampleName = ""
    @State private var showOnlyMatches = false

    init(purpose: Purpose, sampleNames: [String], pattern: String = "", replacement: String = "",
         caseSensitive: Bool = false,
         onApply: @escaping (_ pattern: String, _ replacement: String, _ caseSensitive: Bool) -> Void) {
        self.purpose = purpose
        self.sampleNames = Array(sampleNames.prefix(500))
        self.onApply = onApply
        _pattern = State(initialValue: pattern)
        _replacement = State(initialValue: replacement)
        _caseSensitive = State(initialValue: caseSensitive)
        _exampleName = State(initialValue: sampleNames.first ?? "")
    }

    private var regex: Result<NSRegularExpression, Error>? {
        guard !pattern.isEmpty else { return nil }
        return Result { try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(purpose == .search ? "Regex-Assistent – Suche" : "Regex-Assistent – Umbenennen").font(.headline)

            // Muster und Ersetzung
            HStack {
                TextField("Regulärer Ausdruck, z. B. ^IMG_(\\d+)", text: $pattern)
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .help("Groß-/Kleinschreibung beachten")
                Button("Leeren") { pattern = "" }
            }
            if purpose == .rename {
                HStack {
                    TextField("Ersetzen durch, z. B. Foto $1", text: $replacement)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                    Text("$1, $2 … = Inhalt der Klammer-Gruppen, $0 = ganzer Treffer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            statusLine

            // Bausteine
            GroupBox("Bausteine (klicken fügt am Ende ein)") {
                FlowRow(items: RegexBuildingBlock.all) { block in
                    Button(block.title) { pattern += block.snippet }
                        .help("\(block.snippet) – \(block.explanation)")
                }
            }

            // Vorlagen und Ableiten
            HStack(alignment: .top, spacing: 10) {
                GroupBox("Vorlagen") {
                    Menu("Vorlage wählen …") {
                        ForEach(RegexPreset.all(for: purpose)) { preset in
                            Button(preset.title) {
                                pattern = preset.pattern
                                if purpose == .rename { replacement = preset.replacement }
                            }
                        }
                    }
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Muster aus Beispielname ableiten") {
                    HStack {
                        Picker("Beispiel", selection: $exampleName) {
                            ForEach(Array(Set(sampleNames)).sorted().prefix(200), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        Button("Ableiten") { pattern = RegexInference.pattern(from: exampleName) }
                            .disabled(exampleName.isEmpty)
                            .help("Zahlen werden zu (\\d+), Datum zu (\\d{4})-(\\d{2})-(\\d{2}), die Endung bleibt fest")
                    }
                }
            }

            // Erklärung
            if !pattern.isEmpty {
                GroupBox("Was das Muster bedeutet") {
                    Text(RegexExplainer.explain(pattern))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            // Live-Test
            HStack {
                Text("Test an \(sampleNames.count) Namen").font(.subheadline.bold())
                Spacer()
                Toggle("Nur Treffer zeigen", isOn: $showOnlyMatches).toggleStyle(.checkbox)
            }
            List(testRows, id: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.highlighted).font(.callout.monospaced()).lineLimit(1)
                    if !row.groups.isEmpty {
                        Text(row.groups.enumerated().map { "$\($0.offset + 1) = „\($0.element)“" }.joined(separator: "   "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if purpose == .rename, let renamed = row.renamed, renamed != row.name {
                        Text("→ \(renamed)").font(.caption.monospaced()).foregroundStyle(.green)
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") {
                    onApply(pattern, replacement, caseSensitive)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pattern.isEmpty || { if case .some(.failure) = regex { return true }; return false }())
            }
        }
        .padding(16)
        .frame(width: 760, height: 720)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch regex {
        case .none:
            Text("Muster eingeben, Baustein anklicken oder aus einem Beispiel ableiten.")
                .font(.caption).foregroundStyle(.secondary)
        case .some(.failure(let error)):
            Label("Ungültig: \((error as NSError).localizedDescription)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .some(.success):
            let count = testRows(all: true).filter(\.matched).count
            Label("\(count) von \(sampleNames.count) Namen passen", systemImage: count > 0 ? "checkmark.circle.fill" : "circle")
                .font(.caption).foregroundStyle(count > 0 ? .green : .secondary)
        }
    }

    // MARK: Test

    struct TestRow {
        let name: String
        let matched: Bool
        let highlighted: AttributedString
        let groups: [String]
        let renamed: String?
    }

    private var testRows: [TestRow] { testRows(all: !showOnlyMatches) }

    private func testRows(all: Bool) -> [TestRow] {
        guard case .success(let regex)? = regex else {
            return sampleNames.map { TestRow(name: $0, matched: false, highlighted: AttributedString($0), groups: [], renamed: nil) }
        }
        return sampleNames.compactMap { name in
            let range = NSRange(name.startIndex..., in: name)
            let matches = regex.matches(in: name, range: range)
            guard all || !matches.isEmpty else { return nil }
            var text = AttributedString(name)
            for match in matches {
                if let ar = Range(match.range, in: text) {
                    text[ar].swiftUI.backgroundColor = Color.yellow.opacity(0.45)
                    text[ar].swiftUI.foregroundColor = Color.black
                }
            }
            var groups: [String] = []
            if let first = matches.first, first.numberOfRanges > 1 {
                for index in 1..<first.numberOfRanges {
                    let r = first.range(at: index)
                    groups.append(r.location == NSNotFound ? "" : (name as NSString).substring(with: r))
                }
            }
            let renamed = purpose == .rename
                ? regex.stringByReplacingMatches(in: name, range: range, withTemplate: replacement)
                : nil
            return TestRow(name: name, matched: !matches.isEmpty, highlighted: text, groups: groups, renamed: renamed)
        }
    }
}

// MARK: - Bausteine, Vorlagen, Ableiten, Erklären

struct RegexBuildingBlock: Identifiable {
    let title: String
    let snippet: String
    let explanation: String
    var id: String { title }

    static let all: [RegexBuildingBlock] = [
        .init(title: "Anfang ^", snippet: "^", explanation: "Name beginnt hier"),
        .init(title: "Ende $", snippet: "$", explanation: "Name endet hier"),
        .init(title: "Zahl", snippet: "\\d+", explanation: "eine oder mehrere Ziffern"),
        .init(title: "Zahl merken", snippet: "(\\d+)", explanation: "Ziffern als Gruppe $n"),
        .init(title: "Buchstaben", snippet: "[A-Za-zÄÖÜäöüß]+", explanation: "ein oder mehrere Buchstaben"),
        .init(title: "Beliebiger Text", snippet: ".*", explanation: "beliebig viele beliebige Zeichen"),
        .init(title: "Text merken", snippet: "(.*)", explanation: "beliebiger Text als Gruppe $n"),
        .init(title: "Leerzeichen", snippet: "\\s", explanation: "ein Leerzeichen"),
        .init(title: "Punkt", snippet: "\\.", explanation: "ein echter Punkt"),
        .init(title: "Unterstrich/Bindestrich", snippet: "[_-]", explanation: "_ oder -"),
        .init(title: "Datum JJJJ-MM-TT", snippet: "(\\d{4})-(\\d{2})-(\\d{2})", explanation: "Datum, Jahr/Monat/Tag als Gruppen"),
        .init(title: "Datum TT.MM.JJJJ", snippet: "(\\d{2})\\.(\\d{2})\\.(\\d{4})", explanation: "deutsches Datum"),
        .init(title: "Endung", snippet: "\\.(\\w+)$", explanation: "Dateiendung als Gruppe"),
        .init(title: "Bilder", snippet: "\\.(jpe?g|png|heic|gif|tiff?)$", explanation: "gängige Bildformate"),
        .init(title: "Oder |", snippet: "|", explanation: "das eine oder das andere"),
        .init(title: "Optional ?", snippet: "?", explanation: "das Vorige darf fehlen"),
        .init(title: "Gruppe ( )", snippet: "()", explanation: "Klammer-Gruppe, wird zu $n"),
    ]
}

struct RegexPreset: Identifiable {
    let title: String
    let pattern: String
    let replacement: String
    var id: String { title }

    static func all(for purpose: RegexHelperSheet.Purpose) -> [RegexPreset] {
        purpose == .search ? search : rename
    }

    static let search: [RegexPreset] = [
        .init(title: "Bilder (jpg, png, heic …)", pattern: "\\.(jpe?g|png|heic|gif|tiff?)$", replacement: ""),
        .init(title: "PDF-Dateien", pattern: "\\.pdf$", replacement: ""),
        .init(title: "Name enthält ein Datum JJJJ-MM-TT", pattern: "\\d{4}-\\d{2}-\\d{2}", replacement: ""),
        .init(title: "Name beginnt mit einer Zahl", pattern: "^\\d", replacement: ""),
        .init(title: "Kopien („Kopie“, „copy“, „(1)“)", pattern: "(Kopie|copy| \\(\\d+\\))", replacement: ""),
        .init(title: "Ohne Endung", pattern: "^[^.]+$", replacement: ""),
    ]

    static let rename: [RegexPreset] = [
        .init(title: "IMG_1234.jpg → Foto 1234.jpg", pattern: "^IMG_(\\d+)", replacement: "Foto $1"),
        .init(title: "Leerzeichen → Unterstrich", pattern: "\\s", replacement: "_"),
        .init(title: "Unterstrich → Leerzeichen", pattern: "_", replacement: " "),
        .init(title: "Datum TT.MM.JJJJ → JJJJ-MM-TT", pattern: "(\\d{2})\\.(\\d{2})\\.(\\d{4})", replacement: "$3-$2-$1"),
        .init(title: "Zahl am Anfang entfernen", pattern: "^\\d+[\\s_-]*", replacement: ""),
        .init(title: "„ Kopie“ / „ copy“ entfernen", pattern: "\\s(Kopie|copy)(\\s\\d+)?", replacement: ""),
        .init(title: "Teil vor und nach „-“ tauschen", pattern: "^(.*?)\\s*-\\s*(.*?)(\\.\\w+)?$", replacement: "$2 - $1$3"),
    ]
}

/// Leitet aus einem Beispielnamen ein Muster ab: Datum und Zahlen werden zu Gruppen, Text bleibt fest, Endung am Ende.
enum RegexInference {
    static func pattern(from name: String) -> String {
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var result = "^"
        var rest = Substring(stem)
        while !rest.isEmpty {
            if let date = rest.prefixMatch(of: #/\d{4}-\d{2}-\d{2}/#) {
                result += "(\\d{4})-(\\d{2})-(\\d{2})"
                rest = rest[date.range.upperBound...]
            } else if let digits = rest.prefixMatch(of: #/\d+/#) {
                result += "(\\d+)"
                rest = rest[digits.range.upperBound...]
            } else if let spaces = rest.prefixMatch(of: #/\s+/#) {
                result += "\\s+"
                rest = rest[spaces.range.upperBound...]
            } else {
                let char = rest.removeFirst()
                result += NSRegularExpression.escapedPattern(for: String(char))
            }
        }
        if !ext.isEmpty { result += "\\." + NSRegularExpression.escapedPattern(for: ext) }
        return result + "$"
    }
}

/// Erklärt ein Muster Stück für Stück auf Deutsch (deckt die gängigen Bausteine ab).
enum RegexExplainer {
    static func explain(_ pattern: String) -> String {
        var parts: [String] = []
        var index = pattern.startIndex
        var group = 0
        func next() -> Character? { index < pattern.endIndex ? pattern[index] : nil }
        while index < pattern.endIndex {
            let char = pattern[index]
            index = pattern.index(after: index)
            switch char {
            case "^": parts.append("am Anfang des Namens")
            case "$": parts.append("am Ende des Namens")
            case ".": parts.append("ein beliebiges Zeichen")
            case "|": parts.append("ODER")
            case "(":
                if pattern[index...].hasPrefix("?:") {
                    index = pattern.index(index, offsetBy: 2)
                    parts.append("Beginn einer Gruppe (nicht gemerkt)")
                } else {
                    group += 1
                    parts.append("Beginn von Gruppe $\(group)")
                }
            case ")": parts.append("Ende der Gruppe")
            case "*": parts.append("(beliebig oft, auch gar nicht)")
            case "+": parts.append("(einmal oder öfter)")
            case "?": parts.append(parts.last?.hasPrefix("(") == true ? "(so wenig wie möglich)" : "(darf fehlen)")
            case "{":
                var quantity = ""
                while let c = next(), c != "}" { quantity.append(c); index = pattern.index(after: index) }
                if next() == "}" { index = pattern.index(after: index) }
                let bounds = quantity.split(separator: ",", omittingEmptySubsequences: false)
                if bounds.count == 1 { parts.append("(genau \(quantity)-mal)") }
                else if bounds[1].isEmpty { parts.append("(mindestens \(bounds[0])-mal)") }
                else { parts.append("(\(bounds[0]) bis \(bounds[1])-mal)") }
            case "[":
                var set = ""
                while let c = next(), c != "]" {
                    set.append(c); index = pattern.index(after: index)
                    if c == "\\", let escaped = next() { set.append(escaped); index = pattern.index(after: index) }
                }
                if next() == "]" { index = pattern.index(after: index) }
                parts.append(set.hasPrefix("^") ? "ein Zeichen außer [\(set.dropFirst())]" : "ein Zeichen aus [\(set)]")
            case "\\":
                guard let escaped = next() else { parts.append("\\"); break }
                index = pattern.index(after: index)
                switch escaped {
                case "d": parts.append("eine Ziffer")
                case "D": parts.append("ein Zeichen, das keine Ziffer ist")
                case "w": parts.append("ein Buchstabe, eine Ziffer oder _")
                case "W": parts.append("ein Sonderzeichen")
                case "s": parts.append("ein Leerzeichen")
                case "S": parts.append("ein Zeichen außer Leerzeichen")
                case "b": parts.append("Wortgrenze")
                default: parts.append("das Zeichen „\(escaped)“")
                }
            default:
                // Zusammenhängenden normalen Text zusammenfassen
                if let last = parts.last, last.hasPrefix("der Text „"), last.hasSuffix("“") {
                    parts[parts.count - 1] = String(last.dropLast()) + String(char) + "“"
                } else {
                    parts.append("der Text „\(char)“")
                }
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Einfacher Zeilenumbruch für Knöpfe.
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { content($0) }
        }
        .controlSize(.small)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
