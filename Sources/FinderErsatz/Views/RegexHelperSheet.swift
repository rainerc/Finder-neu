import SwiftUI
import AppKit

/// Regex-Werkstatt nach dem Vorbild von regex101: links Muster, Ersetzung und Testnamen mit farbig markierten
/// Treffern und Gruppen, rechts Erklärung des Musters, Treffer-Details und eine durchsuchbare Kurzreferenz.
/// Testnamen sind die echten Dateinamen (aktueller Ordner bzw. Auswahl) und lassen sich bearbeiten und ergänzen.
struct RegexHelperSheet: View {
    enum Purpose { case search, rename }

    @Environment(\.dismiss) private var dismiss
    let purpose: Purpose
    let onApply: (_ pattern: String, _ replacement: String, _ caseSensitive: Bool) -> Void

    @State private var pattern: String
    @State private var replacement: String
    @State private var caseSensitive: Bool
    @State private var testText: String
    @State private var editingTests = false
    @State private var exampleName = ""
    @State private var referenceFilter = ""
    @State private var showOnlyMatches = false

    init(purpose: Purpose, sampleNames: [String], pattern: String = "", replacement: String = "",
         caseSensitive: Bool = false,
         onApply: @escaping (_ pattern: String, _ replacement: String, _ caseSensitive: Bool) -> Void) {
        self.purpose = purpose
        self.onApply = onApply
        _pattern = State(initialValue: pattern)
        _replacement = State(initialValue: replacement)
        _caseSensitive = State(initialValue: caseSensitive)
        _testText = State(initialValue: sampleNames.prefix(500).joined(separator: "\n"))
        _exampleName = State(initialValue: sampleNames.first ?? "")
    }

    private var testNames: [String] {
        testText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private var compiled: Result<NSRegularExpression, Error>? {
        guard !pattern.isEmpty else { return nil }
        return Result { try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]) }
    }

    private var regex: NSRegularExpression? {
        if case .some(.success(let regex)) = compiled { return regex }
        return nil
    }

    var body: some View {
        let results = evaluate()
        VStack(spacing: 0) {
            HSplitView {
                leftColumn(results)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                rightColumn(results)
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text(purpose == .search ? "Das Muster wird für die Suche übernommen."
                                        : "Muster und Ersetzung werden ins Umbenennen übernommen.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") {
                    onApply(pattern, replacement, caseSensitive)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(regex == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 960, idealWidth: 1100, minHeight: 680, idealHeight: 780)
    }

    // MARK: Linke Spalte: Muster, Ersetzung, Testnamen

    private func leftColumn(_ results: [MatchResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Regulärer Ausdruck").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("/").font(.title3.monospaced()).foregroundStyle(.secondary)
                TextField("z. B. ^IMG_(\\d+)", text: $pattern)
                    .font(.title3.monospaced())
                    .textFieldStyle(.plain)
                Text("/" + (caseSensitive ? "" : "i")).font(.title3.monospaced()).foregroundStyle(.secondary)
                Toggle("i", isOn: Binding(get: { !caseSensitive }, set: { caseSensitive = !$0 }))
                    .toggleStyle(.button)
                    .help("i = Groß-/Kleinschreibung ignorieren")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor, lineWidth: 1.5))
            // Muster farbig (Syntaxhervorhebung)
            if !pattern.isEmpty {
                Text(RegexSyntax.highlighted(pattern))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            statusLine(results)

            if purpose == .rename {
                Text("Ersetzung").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("z. B. Foto $1   ($0 = ganzer Treffer, $1 … = Gruppen)", text: $replacement)
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Testnamen (\(testNames.count))").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Toggle("Nur Treffer", isOn: $showOnlyMatches).toggleStyle(.checkbox).disabled(editingTests)
                Toggle("Bearbeiten", isOn: $editingTests).toggleStyle(.button)
                    .help("Testnamen ändern oder eigene hinzufügen (ein Name pro Zeile)")
            }
            if editingTests {
                TextEditor(text: $testText)
                    .font(.body.monospaced())
                    .border(Color.secondary.opacity(0.3))
            } else {
                List(results.filter { !showOnlyMatches || !$0.matches.isEmpty }) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.highlighted).font(.body.monospaced()).lineLimit(1)
                        if purpose == .rename, let renamed = result.substituted, renamed != result.name {
                            Text("→ " + renamed).font(.callout.monospaced()).foregroundStyle(.green).lineLimit(1)
                        }
                    }
                }
                .listStyle(.bordered)
            }
        }
        .padding(12)
    }

    private var borderColor: Color {
        switch compiled {
        case .none: .secondary.opacity(0.4)
        case .some(.failure): .orange
        case .some(.success): .accentColor
        }
    }

    @ViewBuilder
    private func statusLine(_ results: [MatchResult]) -> some View {
        switch compiled {
        case .none:
            Text("Muster eingeben oder rechts aus der Kurzreferenz anklicken.")
                .font(.caption).foregroundStyle(.secondary)
        case .some(.failure(let error)):
            Label("Ungültig: \((error as NSError).localizedDescription)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .some(.success(let regex)):
            let hits = results.filter { !$0.matches.isEmpty }.count
            let total = results.reduce(0) { $0 + $1.matches.count }
            Label("\(hits) von \(results.count) Namen passen · \(total) Treffer · \(regex.numberOfCaptureGroups) Gruppen",
                  systemImage: hits > 0 ? "checkmark.circle.fill" : "circle")
                .font(.caption).foregroundStyle(hits > 0 ? .green : .secondary)
        }
    }

    // MARK: Rechte Spalte: Erklärung, Treffer, Kurzreferenz

    private func rightColumn(_ results: [MatchResult]) -> some View {
        VStack(spacing: 0) {
            GroupBox("Erklärung") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if pattern.isEmpty {
                            Text("Hier erscheint, was jedes Stück des Musters bedeutet.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(RegexSyntax.tokens(pattern).enumerated()), id: \.offset) { _, token in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(token.text)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(token.kind.color)
                                    .frame(minWidth: 60, alignment: .leading)
                                Text(token.explanation).font(.callout)
                            }
                            .padding(.leading, CGFloat(token.depth) * 14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 140, maxHeight: .infinity)

            GroupBox("Treffer-Details") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        let matched = results.filter { !$0.matches.isEmpty }.prefix(50)
                        if matched.isEmpty {
                            Text(regex == nil ? "–" : "Kein Name passt.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(matched)) { result in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).font(.caption.bold()).lineLimit(1)
                                ForEach(Array(result.matches.enumerated()), id: \.offset) { index, match in
                                    Text("Treffer \(index + 1): „\(match.text)“  Pos. \(match.range.location)–\(match.range.location + match.range.length)")
                                        .font(.caption.monospaced())
                                    ForEach(Array(match.groups.enumerated()), id: \.offset) { groupIndex, group in
                                        Text("   $\(groupIndex + 1) = " + (group.map { "„\($0)“" } ?? "(leer)"))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(RegexSyntax.groupColor(groupIndex + 1))
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 120, maxHeight: .infinity)

            GroupBox("Kurzreferenz") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Suchen, z. B. Zahl, Datum, Gruppe …", text: $referenceFilter)
                            .textFieldStyle(.roundedBorder)
                        Menu("Vorlagen") {
                            ForEach(RegexPreset.all(for: purpose)) { preset in
                                Button(preset.title) {
                                    pattern = preset.pattern
                                    if purpose == .rename { replacement = preset.replacement }
                                }
                            }
                        }
                        .fixedSize()
                    }
                    HStack {
                        Picker("Aus Beispiel", selection: $exampleName) {
                            ForEach(Array(Set(testNames)).sorted().prefix(200), id: \.self) { Text($0).tag($0) }
                        }
                        Button("Ableiten") { pattern = RegexInference.pattern(from: exampleName) }
                            .disabled(exampleName.isEmpty)
                            .help("Muster aus diesem Namen erzeugen: Zahlen und Datum werden zu Gruppen")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredReference) { block in
                                Button {
                                    pattern += block.snippet
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(block.snippet)
                                            .font(.callout.monospaced())
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 130, alignment: .leading)
                                        Text(block.title + " – " + block.explanation)
                                            .font(.callout)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Klicken fügt „\(block.snippet)“ am Ende des Musters ein")
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: .infinity)
        }
        .padding(12)
    }

    private var filteredReference: [RegexBuildingBlock] {
        let filter = referenceFilter.trimmingCharacters(in: .whitespaces)
        guard !filter.isEmpty else { return RegexBuildingBlock.all }
        return RegexBuildingBlock.all.filter {
            $0.title.localizedCaseInsensitiveContains(filter)
                || $0.explanation.localizedCaseInsensitiveContains(filter)
                || $0.snippet.contains(filter)
        }
    }

    // MARK: Auswertung

    struct MatchInfo {
        let range: NSRange
        let text: String
        let groups: [String?]
    }

    struct MatchResult: Identifiable {
        let id: Int
        let name: String
        let matches: [MatchInfo]
        let highlighted: AttributedString
        let substituted: String?
    }

    private func evaluate() -> [MatchResult] {
        let regex = self.regex   // einmal übersetzen, nicht pro Name
        return testNames.enumerated().map { index, name in
            guard let regex else {
                return MatchResult(id: index, name: name, matches: [], highlighted: AttributedString(name), substituted: nil)
            }
            let whole = NSRange(name.startIndex..., in: name)
            let found = regex.matches(in: name, range: whole)
            let ns = name as NSString
            var text = AttributedString(name)
            var infos: [MatchInfo] = []
            for match in found {
                if let r = Range(match.range, in: text) {
                    text[r].swiftUI.backgroundColor = Color.yellow.opacity(0.35)
                }
                var groups: [String?] = []
                if match.numberOfRanges > 1 {
                    for g in 1..<match.numberOfRanges {
                        let gr = match.range(at: g)
                        guard gr.location != NSNotFound else { groups.append(nil); continue }
                        groups.append(ns.substring(with: gr))
                        if let r = Range(gr, in: text) {
                            text[r].swiftUI.backgroundColor = RegexSyntax.groupColor(g).opacity(0.35)
                        }
                    }
                }
                infos.append(MatchInfo(range: match.range, text: ns.substring(with: match.range), groups: groups))
            }
            let substituted = purpose == .rename
                ? regex.stringByReplacingMatches(in: name, range: whole, withTemplate: replacement)
                : nil
            return MatchResult(id: index, name: name, matches: infos, highlighted: text, substituted: substituted)
        }
    }
}

// MARK: - Syntax: Zerlegen, Erklären, Einfärben

enum RegexSyntax {
    enum Kind {
        case anchor, characterClass, quantifier, group, alternation, escape, literal, any

        var color: Color {
            switch self {
            case .anchor: .purple
            case .characterClass: .blue
            case .quantifier: .orange
            case .group: .green
            case .alternation: .red
            case .escape: .teal
            case .literal: .primary
            case .any: .pink
            }
        }
    }

    struct Token {
        let text: String
        let explanation: String
        let kind: Kind
        let depth: Int
    }

    static func groupColor(_ index: Int) -> Color {
        let colors: [Color] = [.green, .blue, .orange, .purple, .pink, .teal, .red, .brown]
        return colors[(max(index, 1) - 1) % colors.count]
    }

    /// Muster mit eingefärbten Bausteinen.
    static func highlighted(_ pattern: String) -> AttributedString {
        var result = AttributedString()
        for token in tokens(pattern) {
            var part = AttributedString(token.text)
            part.swiftUI.foregroundColor = token.kind.color
            result += part
        }
        return result
    }

    /// Zerlegt das Muster in Bausteine mit deutscher Erklärung (deckt die gängige Syntax ab).
    static func tokens(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(pattern)
        var i = 0
        var depth = 0
        var group = 0

        func add(_ text: String, _ explanation: String, _ kind: Kind, depth d: Int? = nil) {
            tokens.append(Token(text: text, explanation: explanation, kind: kind, depth: d ?? depth))
        }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case "^": add("^", "Anfang des Namens", .anchor); i += 1
            case "$": add("$", "Ende des Namens", .anchor); i += 1
            case ".": add(".", "ein beliebiges Zeichen", .any); i += 1
            case "|": add("|", "ODER – das Linke oder das Rechte", .alternation); i += 1
            case "(":
                var text = "("
                let explanation: String
                let rest = String(chars[(i + 1)...].prefix(3))
                if rest.hasPrefix("?:") {
                    text = "(?:"; explanation = "Gruppe (wird nicht als $n gemerkt)"
                } else if rest.hasPrefix("?=") {
                    text = "(?="; explanation = "danach muss folgen … (wird nicht mitgenommen)"
                } else if rest.hasPrefix("?!") {
                    text = "(?!"; explanation = "danach darf NICHT folgen …"
                } else if rest.hasPrefix("?<") && !rest.hasPrefix("?<=") && !rest.hasPrefix("?<!") {
                    var name = ""
                    var j = i + 3
                    while j < chars.count, chars[j] != ">" { name.append(chars[j]); j += 1 }
                    group += 1
                    text = "(?<\(name)>"; explanation = "benannte Gruppe „\(name)“ = $\(group)"
                } else {
                    group += 1
                    explanation = "Beginn von Gruppe $\(group) (wird gemerkt)"
                }
                add(text, explanation, .group)
                i += text.count
                depth += 1
            case ")":
                depth = max(depth - 1, 0)
                add(")", "Ende der Gruppe", .group)
                i += 1
            case "*", "+", "?":
                var text = String(c)
                if i + 1 < chars.count, chars[i + 1] == "?" { text += "?" }
                let lazy = text.count == 2 ? ", so wenig wie möglich" : ""
                let explanation = switch c {
                case "*": "das Vorige beliebig oft (auch gar nicht)\(lazy)"
                case "+": "das Vorige einmal oder öfter\(lazy)"
                default: "das Vorige darf fehlen\(lazy)"
                }
                add(text, explanation, .quantifier)
                i += text.count
            case "{":
                var text = "{"
                var j = i + 1
                while j < chars.count, chars[j] != "}" { text.append(chars[j]); j += 1 }
                if j < chars.count { text.append("}") }
                let inner = text.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                let bounds = inner.split(separator: ",", omittingEmptySubsequences: false)
                let explanation: String
                if bounds.count == 1 { explanation = "das Vorige genau \(inner)-mal" }
                else if bounds.count == 2, bounds[1].isEmpty { explanation = "das Vorige mindestens \(bounds[0])-mal" }
                else if bounds.count == 2 { explanation = "das Vorige \(bounds[0]) bis \(bounds[1])-mal" }
                else { explanation = "Wiederholung" }
                add(text, explanation, .quantifier)
                i = j + 1
            case "[":
                var text = "["
                var j = i + 1
                if j < chars.count, chars[j] == "^" { text.append("^"); j += 1 }
                if j < chars.count, chars[j] == "]" { text.append("]"); j += 1 }
                while j < chars.count, chars[j] != "]" {
                    if chars[j] == "\\", j + 1 < chars.count { text.append(chars[j]); j += 1 }
                    text.append(chars[j]); j += 1
                }
                if j < chars.count { text.append("]") }
                let inner = String(text.dropFirst().dropLast())
                let explanation = inner.hasPrefix("^")
                    ? "ein Zeichen, das NICHT in [\(inner.dropFirst())] vorkommt"
                    : "ein Zeichen aus [\(inner)]"
                add(text, explanation, .characterClass)
                i = j + 1
            case "\\":
                guard i + 1 < chars.count else { add("\\", "unvollständiges Escape", .escape); i += 1; break }
                let e = chars[i + 1]
                let explanation: String
                var kind: Kind = .characterClass
                switch e {
                case "d": explanation = "eine Ziffer 0–9"
                case "D": explanation = "ein Zeichen, das keine Ziffer ist"
                case "w": explanation = "ein Buchstabe, eine Ziffer oder _"
                case "W": explanation = "ein Zeichen außer Buchstabe/Ziffer/_"
                case "s": explanation = "ein Leerraum (Leerzeichen, Tab)"
                case "S": explanation = "ein Zeichen außer Leerraum"
                case "b": explanation = "Wortgrenze"; kind = .anchor
                case "B": explanation = "keine Wortgrenze"; kind = .anchor
                case "1"..."9": explanation = "dasselbe wie Gruppe $\(e) noch einmal"; kind = .group
                default: explanation = "das Zeichen „\(e)“ (wörtlich)"; kind = .escape
                }
                add("\\" + String(e), explanation, kind)
                i += 2
            default:
                // Zusammenhängenden normalen Text zusammenfassen
                var text = ""
                while i < chars.count, !"^$.|()*+?{[\\".contains(chars[i]) {
                    text.append(chars[i]); i += 1
                }
                // Ein Quantor danach gilt nur für das letzte Zeichen
                if text.count > 1, i < chars.count, "*+?{".contains(chars[i]) {
                    let last = text.removeLast()
                    add(text, "der Text „\(text)“", .literal)
                    add(String(last), "das Zeichen „\(last)“", .literal)
                } else {
                    add(text, text.count == 1 ? "das Zeichen „\(text)“" : "der Text „\(text)“", .literal)
                }
            }
        }
        return tokens
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
        .init(title: "Gruppe ohne Merken", snippet: "(?:)", explanation: "fasst zusammen, ohne $n"),
        .init(title: "Benannte Gruppe", snippet: "(?<name>)", explanation: "Gruppe mit Namen"),
        .init(title: "Ziffer", snippet: "\\d", explanation: "genau eine Ziffer"),
        .init(title: "Keine Ziffer", snippet: "\\D", explanation: "ein Zeichen außer Ziffer"),
        .init(title: "Wortzeichen", snippet: "\\w", explanation: "Buchstabe, Ziffer oder _"),
        .init(title: "Kein Leerzeichen", snippet: "\\S", explanation: "ein Zeichen außer Leerraum"),
        .init(title: "Wortgrenze", snippet: "\\b", explanation: "Anfang oder Ende eines Wortes"),
        .init(title: "Zeichenauswahl", snippet: "[abc]", explanation: "a, b oder c"),
        .init(title: "Zeichenbereich", snippet: "[a-z]", explanation: "ein Kleinbuchstabe a bis z"),
        .init(title: "Ausschluss", snippet: "[^abc]", explanation: "alles außer a, b, c"),
        .init(title: "Beliebig oft *", snippet: "*", explanation: "das Vorige 0-mal oder öfter"),
        .init(title: "Mindestens einmal +", snippet: "+", explanation: "das Vorige 1-mal oder öfter"),
        .init(title: "Genau n-mal", snippet: "{2}", explanation: "das Vorige genau 2-mal"),
        .init(title: "n bis m-mal", snippet: "{1,3}", explanation: "das Vorige 1- bis 3-mal"),
        .init(title: "So wenig wie möglich", snippet: "*?", explanation: "„faul“ – kürzester Treffer"),
        .init(title: "Gefolgt von", snippet: "(?=)", explanation: "danach muss … folgen"),
        .init(title: "Nicht gefolgt von", snippet: "(?!)", explanation: "danach darf … nicht folgen"),
        .init(title: "Gleiche Gruppe nochmal", snippet: "\\1", explanation: "Inhalt von $1 wiederholt"),
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
