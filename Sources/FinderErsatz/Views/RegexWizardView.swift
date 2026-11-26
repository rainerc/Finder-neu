import SwiftUI

/// Geführter Einstieg in den Regex-Assistenten: Ziel auswählen („Was möchtest du tun?“), ein paar einfache
/// Felder ausfüllen – die App baut daraus Muster und Ersetzung und zeigt sofort, was mit den echten Namen passiert.
struct RegexWizardView: View {
    let purpose: RegexHelperSheet.Purpose
    let testNames: [String]
    let onUse: (_ pattern: String, _ replacement: String) -> Void
    let onRefine: (_ pattern: String, _ replacement: String) -> Void

    @State private var goal: WizardGoal?
    @State private var text1 = ""
    @State private var text2 = ""
    @State private var separator = " - "
    @State private var dateInput: DateFormatChoice = .dayMonthYear
    @State private var dateOutput: DateFormatChoice = .isoDashes
    @State private var unifySpaces = true
    @State private var unifyUnderscores = true
    @State private var unifyDashes = false
    @State private var digitCount = 0

    init(purpose: RegexHelperSheet.Purpose, testNames: [String],
         onUse: @escaping (_ pattern: String, _ replacement: String) -> Void,
         onRefine: @escaping (_ pattern: String, _ replacement: String) -> Void) {
        self.purpose = purpose
        self.testNames = testNames
        self.onUse = onUse
        self.onRefine = onRefine
        _goal = State(initialValue: WizardGoal.goals(for: purpose).first)
    }

    var body: some View {
        HSplitView {
            List(selection: $goal) {
                Section(purpose == .search ? "Welche Dateien suchst du?" : "Was soll mit den Namen passieren?") {
                    ForEach(WizardGoal.goals(for: purpose)) { goal in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(goal.title)
                                Text(goal.example).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: goal.symbol)
                        }
                        .tag(goal)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: goal) { _, _ in
                text1 = ""
                text2 = ""
            }
            .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)

            if let goal {
                detail(goal)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Links ein Ziel auswählen")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Rechte Seite: Felder, erzeugtes Muster, Vorschau

    private func detail(_ goal: WizardGoal) -> some View {
        let built = build(goal)
        let regex = built.pattern.isEmpty ? nil : try? NSRegularExpression(pattern: built.pattern, options: [.caseInsensitive])
        let results = RegexHelperSheet.evaluate(names: testNames, regex: regex, replacement: built.replacement, purpose: purpose)
        let affected = results.filter { result in
            purpose == .search ? !result.matches.isEmpty : (result.substituted.map { $0 != result.name } ?? false)
        }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(goal.title, systemImage: goal.symbol).font(.title2.bold())
                Text(goal.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Beispiel: \(goal.example)").font(.callout.monospaced()).foregroundStyle(.secondary)
            }

            GroupBox("1. Angaben") {
                fields(goal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }

            GroupBox("2. So sieht der reguläre Ausdruck aus") {
                VStack(alignment: .leading, spacing: 6) {
                    if built.pattern.isEmpty {
                        Text("Bitte oben die Angaben ausfüllen.").foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Muster").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                            Text(RegexSyntax.highlighted(built.pattern)).font(.body.monospaced()).textSelection(.enabled)
                        }
                        if purpose == .rename {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Ersetzen").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                                Text(built.replacement.isEmpty ? "(nichts – Treffer wird gelöscht)" : built.replacement)
                                    .font(.body.monospaced())
                                    .foregroundStyle(built.replacement.isEmpty ? .secondary : .primary)
                                    .textSelection(.enabled)
                            }
                        }
                        Text(built.explanation)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup("Jeden Baustein einzeln erklären") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(RegexSyntax.tokens(built.pattern).enumerated()), id: \.offset) { _, token in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(token.text)
                                            .font(.body.monospaced())
                                            .foregroundStyle(token.kind.color)
                                            .frame(minWidth: 60, alignment: .leading)
                                        Text(token.explanation).font(.callout)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                preview(results, affected: affected.count)
            } label: {
                HStack {
                    Text("3. Vorschau mit deinen Dateinamen")
                    Spacer()
                    if regex != nil {
                        Text(purpose == .search ? "\(affected.count) von \(results.count) Namen gefunden"
                                                : "\(affected.count) von \(results.count) Namen ändern sich")
                            .font(.caption)
                            .foregroundStyle(affected.isEmpty ? Color.orange : Color.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if let regex, purpose == .rename {
                    let warnings = RegexWarnings.check(results: results, regex: regex, replacement: built.replacement, purpose: purpose)
                    if let first = warnings.first {
                        Label(first, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                }
                Spacer()
                Button("In der Werkstatt verfeinern …") { onRefine(built.pattern, built.replacement) }
                    .disabled(regex == nil)
                    .help("Muster in die Werkstatt übernehmen und dort weiter anpassen")
                Button("Verwenden") { onUse(built.pattern, built.replacement) }
                    .buttonStyle(.borderedProminent)
                    .disabled(regex == nil)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func preview(_ results: [RegexHelperSheet.MatchResult], affected: Int) -> some View {
        if results.isEmpty {
            Text("Keine Testnamen vorhanden – in der Werkstatt lassen sich eigene Namen eintragen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // Betroffene Namen zuerst, damit man die Wirkung sofort sieht
                    let sorted = results.sorted { lhs, rhs in
                        isAffected(lhs) && !isAffected(rhs)
                    }
                    ForEach(sorted.prefix(200)) { result in
                        HStack(spacing: 8) {
                            Image(systemName: isAffected(result) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isAffected(result) ? Color.green : Color.secondary)
                            Text(result.highlighted).font(.callout.monospaced()).lineLimit(1)
                            if purpose == .rename, let new = result.substituted, new != result.name {
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                Text(new).font(.callout.monospaced()).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }

    private func isAffected(_ result: RegexHelperSheet.MatchResult) -> Bool {
        purpose == .search ? !result.matches.isEmpty : (result.substituted.map { $0 != result.name } ?? false)
    }

    // MARK: Eingabefelder je Ziel

    @ViewBuilder
    private func fields(_ goal: WizardGoal) -> some View {
        switch goal.kind {
        case .replaceText:
            LabeledContent("Suchen nach") { TextField("z. B. IMG", text: $text1) }
            LabeledContent("Ersetzen durch") { TextField("z. B. Urlaub (leer = löschen)", text: $text2) }
        case .removeText:
            LabeledContent("Diesen Text entfernen") { TextField("z. B. _final", text: $text1) }
        case .insertFront:
            LabeledContent("Vorne einfügen") { TextField("z. B. 2025 Urlaub ", text: $text1) }
        case .insertBack:
            LabeledContent("Vor der Endung einfügen") { TextField("z. B.  (bearbeitet)", text: $text1) }
            Text("Die Endung (.jpg, .pdf …) bleibt erhalten.").font(.caption).foregroundStyle(.secondary)
        case .changeExtension:
            LabeledContent("Alte Endung") { TextField("leer = jede Endung, z. B. jpeg", text: $text1) }
            LabeledContent("Neue Endung") { TextField("z. B. jpg", text: $text2) }
        case .keepNumber:
            LabeledContent("Neuer Name vor der Nummer") { TextField("z. B. Urlaub ", text: $text1) }
            LabeledContent("Nach der Nummer") { TextField("optional", text: $text2) }
            Text("Aus „IMG_1234.jpg“ wird z. B. „Urlaub 1234.jpg“ – die erste Zahl im Namen bleibt erhalten.")
                .font(.caption).foregroundStyle(.secondary)
        case .reorderDate:
            Picker("Datum steht im Namen als", selection: $dateInput) {
                ForEach(DateFormatChoice.inputs) { Text($0.title).tag($0) }
            }
            Picker("Umstellen auf", selection: $dateOutput) {
                ForEach(DateFormatChoice.outputs) { Text($0.title).tag($0) }
            }
            Text("Tipp: „JJJJ-MM-TT“ sortiert sich automatisch richtig nach Datum.")
                .font(.caption).foregroundStyle(.secondary)
        case .swapParts:
            LabeledContent("Trennzeichen zwischen den Teilen") { TextField("z. B.  - ", text: $separator) }
            Text("Aus „Künstler - Titel.mp3“ wird „Titel - Künstler.mp3“. Getauscht wird am ersten Trennzeichen.")
                .font(.caption).foregroundStyle(.secondary)
        case .unifySeparators:
            HStack {
                Toggle("Leerzeichen", isOn: $unifySpaces)
                Toggle("Unterstriche _", isOn: $unifyUnderscores)
                Toggle("Bindestriche -", isOn: $unifyDashes)
            }
            LabeledContent("Ersetzen durch") { TextField("z. B. _ oder Leerzeichen", text: $text1) }
            Text("Mehrere hintereinander werden zu einem. Punkte bleiben unverändert, damit die Endung erhalten bleibt.")
                .font(.caption).foregroundStyle(.secondary)
        case .removeLeadingNumber, .removeBrackets, .removeCopySuffix, .collapseSpaces,
             .containsDate, .copies:
            Text("Keine Angaben nötig.").foregroundStyle(.secondary)
        case .extensions:
            LabeledContent("Endungen") { TextField("z. B. jpg, png, heic", text: $text1) }
            Text("Mehrere mit Komma trennen.").font(.caption).foregroundStyle(.secondary)
        case .startsWith:
            LabeledContent("Name beginnt mit") { TextField("z. B. Rechnung", text: $text1) }
        case .endsWith:
            LabeledContent("Name endet mit (vor der Endung)") { TextField("z. B. _final", text: $text1) }
        case .contains:
            LabeledContent("Name enthält") { TextField("z. B. Steuer", text: $text1) }
        case .containsAll:
            LabeledContent("Erstes Wort") { TextField("z. B. Rechnung", text: $text1) }
            LabeledContent("Zweites Wort") { TextField("z. B. 2025", text: $text2) }
            Text("Beide müssen vorkommen – egal in welcher Reihenfolge.").font(.caption).foregroundStyle(.secondary)
        case .containsAny:
            LabeledContent("Eines dieser Wörter") { TextField("z. B. Rechnung, Quittung, Beleg", text: $text1) }
        case .containsNot:
            LabeledContent("Name enthält NICHT") { TextField("z. B. Kopie", text: $text1) }
        case .containsNumber:
            Stepper(value: $digitCount, in: 0...12) {
                Text(digitCount == 0 ? "Beliebig viele Ziffern" : "Genau \(digitCount) Ziffern am Stück")
            }
        }
    }

    // MARK: Muster bauen

    struct Built {
        var pattern: String
        var replacement: String
        var explanation: String
    }

    private func esc(_ text: String) -> String { NSRegularExpression.escapedPattern(for: text) }
    private func escTemplate(_ text: String) -> String { NSRegularExpression.escapedTemplate(for: text) }

    private func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func build(_ goal: WizardGoal) -> Built {
        let ext = #"(\.[^.]+)?$"#
        switch goal.kind {
        case .replaceText:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: esc(text1), replacement: escTemplate(text2),
                         explanation: "Jedes Vorkommen von „\(text1)“ wird durch „\(text2)“ ersetzt. Sonderzeichen wie . ( ) werden automatisch mit \\ geschützt.")
        case .removeText:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: esc(text1), replacement: "",
                         explanation: "Jedes Vorkommen von „\(text1)“ wird gelöscht (Ersetzung ist leer).")
        case .insertFront:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "^", replacement: escTemplate(text1),
                         explanation: "^ ist der Anfang des Namens. Dort wird „\(text1)“ eingesetzt.")
        case .insertBack:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "^(.*?)" + ext, replacement: "$1" + escTemplate(text1) + "$2",
                         explanation: "Gruppe 1 (.*?) ist der Name ohne Endung, Gruppe 2 die Endung. Dazwischen wird „\(text1)“ eingesetzt: $1\(text1)$2.")
        case .changeExtension:
            guard !text2.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            let from = text1.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let to = text2.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let pattern = from.isEmpty ? #"\.[^.]+$"# : #"\."# + esc(from) + "$"
            return Built(pattern: pattern, replacement: "." + escTemplate(to),
                         explanation: from.isEmpty
                            ? "\\.[^.]+$ ist der letzte Punkt mit allem danach (die Endung). Sie wird zu „.\(to)“."
                            : "Nur Namen, die auf „.\(from)“ enden, bekommen die Endung „.\(to)“. $ heißt: ganz am Ende.")
        case .keepNumber:
            return Built(pattern: #"^\D*(\d+).*?"# + ext,
                         replacement: escTemplate(text1) + "$1" + escTemplate(text2) + "$2",
                         explanation: "\\D* überspringt alles bis zur ersten Ziffer, (\\d+) merkt sich die Nummer als Gruppe 1, (\\.[^.]+)? die Endung als Gruppe 2. Neuer Name: „\(text1)“ + Nummer + „\(text2)“ + Endung.")
        case .reorderDate:
            let input = dateInput
            let output = dateOutput
            let template = output.template(year: input.yearGroup, month: input.monthGroup, day: input.dayGroup)
            return Built(pattern: input.pattern, replacement: template,
                         explanation: "Jahr, Monat und Tag werden als Gruppen gemerkt ($\(input.yearGroup) = Jahr, $\(input.monthGroup) = Monat, $\(input.dayGroup) = Tag) und in neuer Reihenfolge zusammengesetzt: \(template).")
        case .swapParts:
            guard !separator.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "^(.+?)" + esc(separator) + "(.+?)" + ext,
                         replacement: "$2" + escTemplate(separator) + "$1$3",
                         explanation: "(.+?) vor dem Trennzeichen ist Gruppe 1, danach Gruppe 2, die Endung Gruppe 3. Ersetzt wird durch $2\(separator)$1$3 – also vertauscht.")
        case .unifySeparators:
            var chars = ""
            if unifySpaces { chars += " " }
            if unifyUnderscores { chars += "_" }
            if unifyDashes { chars += "-" }   // Bindestrich zuletzt: in [ ] dann wörtlich
            guard !chars.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "[\(chars)]+", replacement: escTemplate(text1),
                         explanation: "[\(chars)]+ trifft ein oder mehrere dieser Zeichen hintereinander. Jede solche Stelle wird zu „\(text1)“.")
        case .removeLeadingNumber:
            return Built(pattern: #"^\d+[\s._-]*"#, replacement: "",
                         explanation: "^\\d+ sind Ziffern am Anfang, [\\s._-]* danach folgende Leerzeichen, Punkte, Unterstriche oder Bindestriche. Alles wird entfernt.")
        case .removeBrackets:
            return Built(pattern: #"\s*[\(\[][^\)\]]*[\)\]]"#, replacement: "",
                         explanation: "Eine öffnende Klammer ( oder [, beliebiger Inhalt ohne schließende Klammer, dann ) oder ]. Davor stehende Leerzeichen werden mit entfernt.")
        case .removeCopySuffix:
            return Built(pattern: #"( Kopie( \d+)?| copy( \d+)?| \(\d+\))"# + ext, replacement: "$4",
                         explanation: "Trifft „ Kopie“, „ Kopie 2“, „ copy“ oder „ (1)“ direkt vor der Endung. Ersetzt wird nur durch die Endung ($4).")
        case .collapseSpaces:
            return Built(pattern: #"\s{2,}"#, replacement: " ",
                         explanation: "\\s{2,} sind zwei oder mehr Leerzeichen hintereinander. Sie werden zu einem einzigen.")
        case .extensions:
            let items = list(text1).map { esc($0.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
            guard !items.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            let pattern = items.count == 1 ? #"\."# + items[0] + "$" : #"\.("# + items.joined(separator: "|") + ")$"
            return Built(pattern: pattern, replacement: "",
                         explanation: "\\. ist ein echter Punkt, \(items.count > 1 ? "(…|…) heißt „eines davon“, " : "")$ heißt: ganz am Ende des Namens.")
        case .startsWith:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "^" + esc(text1), replacement: "",
                         explanation: "^ ist der Anfang des Namens – der Name muss mit „\(text1)“ beginnen.")
        case .endsWith:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: esc(text1) + ext, replacement: "",
                         explanation: "„\(text1)“ muss direkt vor der Endung (oder ganz am Ende) stehen. (\\.[^.]+)?$ ist die optionale Endung.")
        case .contains:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: esc(text1), replacement: "",
                         explanation: "Ohne ^ und $ darf „\(text1)“ irgendwo im Namen stehen.")
        case .containsAll:
            guard !text1.isEmpty, !text2.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "^(?=.*" + esc(text1) + ")(?=.*" + esc(text2) + ")", replacement: "",
                         explanation: "(?=.*…) ist eine Vorausschau: „irgendwo weiter hinten steht …“. Zwei davon hintereinander verlangen beide Wörter in beliebiger Reihenfolge.")
        case .containsAny:
            let items = list(text1).map(esc)
            guard !items.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "(" + items.joined(separator: "|") + ")", replacement: "",
                         explanation: "| heißt „oder“: eines der Wörter muss vorkommen.")
        case .containsNot:
            guard !text1.isEmpty else { return Built(pattern: "", replacement: "", explanation: "") }
            return Built(pattern: "^(?!.*" + esc(text1) + ")", replacement: "",
                         explanation: "(?!.*…) ist eine verneinte Vorausschau: Der Name passt nur, wenn „\(text1)“ nirgends vorkommt.")
        case .containsNumber:
            let pattern = digitCount == 0 ? #"\d+"# : #"(?<!\d)\d{\#(digitCount)}(?!\d)"#
            return Built(pattern: pattern, replacement: "",
                         explanation: digitCount == 0
                            ? "\\d ist eine Ziffer, + heißt „eine oder mehr“."
                            : "\\d{\(digitCount)} sind genau \(digitCount) Ziffern; (?<!\\d) und (?!\\d) stellen sicher, dass davor und danach keine weitere Ziffer steht.")
        case .containsDate:
            return Built(pattern: #"\d{4}-\d{2}-\d{2}|\d{1,2}\.\d{1,2}\.\d{4}|(19|20)\d{6}"#, replacement: "",
                         explanation: "Drei Varianten mit | (oder): 2025-03-14, 14.3.2025 oder 20250314.")
        case .copies:
            return Built(pattern: #"( Kopie( \d+)?| copy( \d+)?| \(\d+\))(\.[^.]+)?$"#, replacement: "",
                         explanation: "Findet Duplikate wie „Bild Kopie.jpg“, „Bild Kopie 2.jpg“ oder „Bild (1).jpg“.")
        }
    }
}

// MARK: - Ziele

struct WizardGoal: Identifiable, Hashable {
    enum Kind: Hashable {
        // Umbenennen
        case replaceText, removeText, insertFront, insertBack, changeExtension, keepNumber, reorderDate,
             swapParts, unifySeparators, removeLeadingNumber, removeBrackets, removeCopySuffix, collapseSpaces
        // Suchen
        case extensions, startsWith, endsWith, contains, containsAll, containsAny, containsNot,
             containsNumber, containsDate, copies
    }

    let kind: Kind
    let title: String
    let symbol: String
    let example: String
    let help: String
    var id: Kind { kind }

    static func goals(for purpose: RegexHelperSheet.Purpose) -> [WizardGoal] {
        purpose == .rename ? renameGoals : searchGoals
    }

    static let renameGoals: [WizardGoal] = [
        WizardGoal(kind: .replaceText, title: "Text ersetzen", symbol: "arrow.left.arrow.right",
                   example: "IMG_0042.jpg → Urlaub_0042.jpg",
                   help: "Ein bestimmtes Wort oder Zeichen überall im Namen durch etwas anderes ersetzen."),
        WizardGoal(kind: .removeText, title: "Text entfernen", symbol: "eraser",
                   example: "Bericht_final.pdf → Bericht.pdf",
                   help: "Einen bestimmten Text aus allen Namen löschen."),
        WizardGoal(kind: .insertFront, title: "Vorne etwas einfügen", symbol: "text.insert",
                   example: "Strand.jpg → 2025 Strand.jpg",
                   help: "Vor jeden Namen denselben Text setzen, z. B. ein Datum oder Projektkürzel."),
        WizardGoal(kind: .insertBack, title: "Vor der Endung einfügen", symbol: "text.append",
                   example: "Brief.docx → Brief (alt).docx",
                   help: "Text ans Ende des Namens hängen – aber vor .jpg, .pdf usw."),
        WizardGoal(kind: .changeExtension, title: "Endung ändern", symbol: "doc.badge.gearshape",
                   example: "Foto.jpeg → Foto.jpg",
                   help: "Die Dateiendung umbenennen. Achtung: Der Inhalt wird dabei nicht umgewandelt."),
        WizardGoal(kind: .keepNumber, title: "Nummer behalten, Rest neu", symbol: "number",
                   example: "IMG_1234.JPG → Urlaub 1234.JPG",
                   help: "Die erste Zahl im Namen bleibt, alles andere wird durch einen neuen Namen ersetzt."),
        WizardGoal(kind: .reorderDate, title: "Datum umstellen", symbol: "calendar",
                   example: "Rechnung 14.03.2025.pdf → Rechnung 2025-03-14.pdf",
                   help: "Ein Datum im Namen in eine andere Reihenfolge bringen – am besten Jahr zuerst, dann sortiert es richtig."),
        WizardGoal(kind: .swapParts, title: "Teile tauschen", symbol: "arrow.triangle.swap",
                   example: "Beatles - Help.mp3 → Help - Beatles.mp3",
                   help: "Zwei durch ein Trennzeichen getrennte Teile vertauschen."),
        WizardGoal(kind: .unifySeparators, title: "Trennzeichen vereinheitlichen", symbol: "line.3.horizontal",
                   example: "mein_tolles  Bild.png → mein tolles Bild.png",
                   help: "Leerzeichen, Unterstriche und Bindestriche durch ein einheitliches Zeichen ersetzen."),
        WizardGoal(kind: .removeLeadingNumber, title: "Nummerierung vorne entfernen", symbol: "list.number",
                   example: "01 - Intro.mp3 → Intro.mp3",
                   help: "Ziffern am Anfang samt folgenden Trennzeichen entfernen."),
        WizardGoal(kind: .removeBrackets, title: "Klammern entfernen", symbol: "parentheses",
                   example: "Film (2019) [HD].mkv → Film.mkv",
                   help: "Alles in runden oder eckigen Klammern samt Klammern löschen."),
        WizardGoal(kind: .removeCopySuffix, title: "„Kopie“ / „(1)“ entfernen", symbol: "doc.on.doc",
                   example: "Bild Kopie 2.jpg → Bild.jpg",
                   help: "Zusätze, die macOS oder Browser beim Duplizieren anhängen, wieder entfernen."),
        WizardGoal(kind: .collapseSpaces, title: "Doppelte Leerzeichen", symbol: "space",
                   example: "Mein   Text.txt → Mein Text.txt",
                   help: "Mehrere Leerzeichen hintereinander zu einem zusammenfassen."),
    ]

    static let searchGoals: [WizardGoal] = [
        WizardGoal(kind: .extensions, title: "Bestimmte Endungen", symbol: "doc",
                   example: "jpg, png → Foto.jpg, Logo.png",
                   help: "Alle Dateien mit einer oder mehreren Endungen finden."),
        WizardGoal(kind: .startsWith, title: "Name beginnt mit …", symbol: "text.alignleft",
                   example: "Rechnung → Rechnung 2025.pdf",
                   help: "Nur Namen, die mit einem bestimmten Text anfangen."),
        WizardGoal(kind: .endsWith, title: "Name endet mit …", symbol: "text.alignright",
                   example: "_final → Bericht_final.pdf",
                   help: "Nur Namen, die (vor der Endung) mit einem bestimmten Text aufhören."),
        WizardGoal(kind: .contains, title: "Name enthält …", symbol: "text.magnifyingglass",
                   example: "Steuer → Steuererklärung.pdf",
                   help: "Der Text darf irgendwo im Namen stehen."),
        WizardGoal(kind: .containsAll, title: "Enthält beide Wörter", symbol: "plus.circle",
                   example: "Rechnung + 2025 → 2025 Rechnung Strom.pdf",
                   help: "Beide Wörter müssen vorkommen, die Reihenfolge ist egal."),
        WizardGoal(kind: .containsAny, title: "Enthält eines der Wörter", symbol: "questionmark.circle",
                   example: "Rechnung, Beleg → Beleg Tanken.pdf",
                   help: "Mindestens eines der Wörter muss vorkommen."),
        WizardGoal(kind: .containsNot, title: "Enthält NICHT …", symbol: "minus.circle",
                   example: "Kopie → alle außer „Bild Kopie.jpg“",
                   help: "Alle Namen, in denen ein bestimmter Text nicht vorkommt."),
        WizardGoal(kind: .containsNumber, title: "Enthält eine Zahl", symbol: "number",
                   example: "4 Ziffern → Urlaub 2025.jpg",
                   help: "Namen mit Ziffern – auf Wunsch genau so viele am Stück, z. B. Jahreszahlen."),
        WizardGoal(kind: .containsDate, title: "Enthält ein Datum", symbol: "calendar",
                   example: "Scan 2025-03-14.pdf, Brief 14.3.2025.docx",
                   help: "Namen mit Datum in üblichen Schreibweisen."),
        WizardGoal(kind: .copies, title: "Kopien / Duplikate", symbol: "doc.on.doc",
                   example: "Bild Kopie.jpg, Bild (1).jpg",
                   help: "Dateien, die nach einem Duplikat aussehen."),
    ]
}

// MARK: - Datumsformate

enum DateFormatChoice: String, Identifiable, Hashable {
    case dayMonthYear, dayMonthYearDash, isoDashes, compact, isoUnderscore, germanDots

    var id: String { rawValue }

    static let inputs: [DateFormatChoice] = [.dayMonthYear, .dayMonthYearDash, .isoDashes, .compact]
    static let outputs: [DateFormatChoice] = [.isoDashes, .compact, .isoUnderscore, .germanDots]

    var title: String {
        switch self {
        case .dayMonthYear: "TT.MM.JJJJ (14.03.2025)"
        case .dayMonthYearDash: "TT-MM-JJJJ oder TT_MM_JJJJ (14-03-2025)"
        case .isoDashes: "JJJJ-MM-TT (2025-03-14)"
        case .compact: "JJJJMMTT (20250314)"
        case .isoUnderscore: "JJJJ_MM_TT (2025_03_14)"
        case .germanDots: "TT.MM.JJJJ (14.03.2025)"
        }
    }

    /// Muster zum Erkennen (nur für Eingabeformate sinnvoll)
    var pattern: String {
        switch self {
        case .dayMonthYear, .germanDots: #"(\d{1,2})\.(\d{1,2})\.(\d{4})"#
        case .dayMonthYearDash: #"(\d{1,2})[-_](\d{1,2})[-_](\d{4})"#
        case .isoDashes: #"(\d{4})-(\d{2})-(\d{2})"#
        case .isoUnderscore: #"(\d{4})_(\d{2})_(\d{2})"#
        case .compact: #"((?:19|20)\d{2})(\d{2})(\d{2})"#
        }
    }

    var yearGroup: Int { [DateFormatChoice.isoDashes, .compact, .isoUnderscore].contains(self) ? 1 : 3 }
    var monthGroup: Int { 2 }
    var dayGroup: Int { [DateFormatChoice.isoDashes, .compact, .isoUnderscore].contains(self) ? 3 : 1 }

    /// Ersetzung für dieses Ausgabeformat
    func template(year: Int, month: Int, day: Int) -> String {
        switch self {
        case .isoDashes: "$\(year)-$\(month)-$\(day)"
        case .compact: "$\(year)$\(month)$\(day)"
        case .isoUnderscore: "$\(year)_$\(month)_$\(day)"
        case .dayMonthYear, .germanDots, .dayMonthYearDash: "$\(day).$\(month).$\(year)"
        }
    }
}
