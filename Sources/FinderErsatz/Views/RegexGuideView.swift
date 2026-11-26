import SwiftUI

/// Ausführliche deutsche Anleitung zu regulären Ausdrücken mit durchgerechneten Beispielen.
/// Jedes Beispiel zeigt, wie viele der eigenen Dateinamen es trifft, und lässt sich in die Werkstatt übernehmen.
struct RegexGuideView: View {
    let exampleNames: [String]
    let onTry: (RegexGuideExample) -> Void

    @State private var chapter: RegexGuideChapter.ID? = RegexGuideChapter.all.first?.id

    var body: some View {
        HSplitView {
            List(selection: $chapter) {
                Section("Kapitel") {
                    ForEach(RegexGuideChapter.all) { chapter in
                        Label(chapter.title, systemImage: chapter.symbol).tag(chapter.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(RegexGuideChapter.all) { chapter in
                            chapterView(chapter).id(chapter.id)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chapter) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .top) }
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chapterView(_ chapter: RegexGuideChapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(chapter.title, systemImage: chapter.symbol).font(.title2.bold())
            ForEach(Array(chapter.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(LocalizedStringKey(paragraph))   // erlaubt **fett** und `Code`
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !chapter.table.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(Array(chapter.table.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.0).font(.body.monospaced()).foregroundStyle(.blue).textSelection(.enabled)
                            Text(row.1)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            }
            ForEach(chapter.examples) { example in
                exampleView(example)
            }
        }
    }

    private func exampleView(_ example: RegexGuideExample) -> some View {
        let regex = try? NSRegularExpression(pattern: example.pattern, options: [.caseInsensitive])
        let replacement = example.replacement
        let isRename = !replacement.isEmpty || example.isRename
        let sample = RegexHelperSheet.evaluate(names: [example.sample], regex: regex, replacement: replacement,
                                               purpose: isRename ? .rename : .search).first
        let own = RegexHelperSheet.evaluate(names: exampleNames, regex: regex, replacement: replacement, purpose: .search)
        let ownHits = own.filter { !$0.matches.isEmpty }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(example.title).font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text("Muster").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                Text(RegexSyntax.highlighted(example.pattern)).font(.body.monospaced()).textSelection(.enabled)
            }
            if isRename {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ersetzen").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Text(replacement.isEmpty ? "(leer)" : replacement).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            if let sample {
                HStack(alignment: .firstTextBaseline) {
                    Text("Beispiel").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Text(sample.highlighted).font(.body.monospaced())
                    if isRename, let new = sample.substituted {
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(new).font(.body.monospaced())
                    } else {
                        Image(systemName: sample.matches.isEmpty ? "xmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(sample.matches.isEmpty ? Color.red : Color.green)
                    }
                }
            }
            Text(LocalizedStringKey(example.explanation))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !exampleNames.isEmpty {
                    Text("Trifft \(ownHits) von \(exampleNames.count) deiner Namen")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("In der Werkstatt ausprobieren") { onTry(example) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
    }
}

// MARK: - Inhalt

struct RegexGuideExample: Identifiable {
    let id = UUID()
    let title: String
    let pattern: String
    var replacement: String = ""
    /// Auch mit leerer Ersetzung als Umbenennen zeigen (Treffer wird gelöscht)
    var isRename = false
    let sample: String
    let explanation: String
}

struct RegexGuideChapter: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let paragraphs: [String]
    var table: [(String, String)] = []
    var examples: [RegexGuideExample] = []

    static let all: [RegexGuideChapter] = [
        RegexGuideChapter(
            id: "intro", title: "Was ist ein regulärer Ausdruck?", symbol: "questionmark.circle",
            paragraphs: [
                "Ein regulärer Ausdruck (kurz **Regex**) ist ein *Suchmuster* für Text. Statt nach einem festen Wort zu suchen, beschreibt man, **wie** der gesuchte Text aussieht – z. B. „vier Ziffern“, „beginnt mit IMG“ oder „endet auf .jpg“.",
                "Die meisten Zeichen stehen einfach für sich selbst: `Urlaub` findet genau „Urlaub“. Nur einige Zeichen haben eine Sonderbedeutung: `. * + ? ^ $ ( ) [ ] { } | \\`. Will man eines davon wörtlich, setzt man `\\` davor – ein echter Punkt ist also `\\.`.",
                "Beim **Umbenennen** gibt es zusätzlich die **Ersetzung**: Alles, was das Muster trifft, wird durch die Ersetzung ausgetauscht. Mit `$1`, `$2` … setzt man dort Teile wieder ein, die man im Muster mit Klammern „gemerkt“ hat.",
                "Groß-/Kleinschreibung: Mit dem Schalter **i** (Standard) ist sie egal – `jpg` findet dann auch „JPG“.",
            ],
            examples: [
                RegexGuideExample(title: "Ein festes Wort finden", pattern: "Rechnung",
                                  sample: "2025 Rechnung Strom.pdf",
                                  explanation: "Ohne Sonderzeichen wird einfach der Text gesucht – egal wo im Namen."),
            ]),
        RegexGuideChapter(
            id: "chars", title: "Zeichen und Platzhalter", symbol: "character.cursor.ibeam",
            paragraphs: [
                "Platzhalter stehen für **ein** Zeichen einer bestimmten Art. Mit eckigen Klammern baut man eigene Zeichengruppen.",
            ],
            table: [
                (".", "irgendein Zeichen (genau eines)"),
                ("\\d", "eine Ziffer 0–9"),
                ("\\D", "ein Zeichen, das keine Ziffer ist"),
                ("\\w", "ein Buchstabe, eine Ziffer oder _"),
                ("\\s", "ein Leerzeichen (oder Tab)"),
                ("[abc]", "a, b oder c"),
                ("[a-z]", "ein Kleinbuchstabe von a bis z"),
                ("[^0-9]", "alles außer Ziffern (^ direkt nach [ verneint)"),
                ("\\.", "ein echter Punkt"),
            ],
            examples: [
                RegexGuideExample(title: "Drei Ziffern hintereinander", pattern: #"\d\d\d"#,
                                  sample: "Scan_042.pdf",
                                  explanation: "Jedes `\\d` steht für eine Ziffer. Kürzer: `\\d{3}` (siehe nächstes Kapitel)."),
                RegexGuideExample(title: "Unterstrich oder Bindestrich", pattern: "[_-]", replacement: " ",
                                  sample: "mein_neues-Bild.png",
                                  explanation: "`[_-]` trifft jedes einzelne _ oder -. Ein Bindestrich am Ende der Klammer ist wörtlich gemeint."),
            ]),
        RegexGuideChapter(
            id: "quantifiers", title: "Wie oft? (Wiederholungen)", symbol: "repeat",
            paragraphs: [
                "Ein Wiederholungszeichen gilt für das Zeichen (oder die Gruppe) **direkt davor**.",
                "**Gierig und genügsam:** `.*` nimmt so viel wie möglich, `.*?` so wenig wie möglich. Das ist der häufigste Grund für überraschende Ergebnisse – siehe Beispiel.",
            ],
            table: [
                ("*", "beliebig oft, auch gar nicht"),
                ("+", "mindestens einmal"),
                ("?", "optional: null- oder einmal"),
                ("{4}", "genau 4-mal"),
                ("{2,4}", "2- bis 4-mal"),
                ("{2,}", "mindestens 2-mal"),
                ("*?  +?", "genügsam: so wenig wie möglich"),
            ],
            examples: [
                RegexGuideExample(title: "Eine Jahreszahl", pattern: #"(19|20)\d{2}"#,
                                  sample: "Urlaub Italien 2024.jpg",
                                  explanation: "19 oder 20, danach genau zwei Ziffern."),
                RegexGuideExample(title: "Gierig: bis zum LETZTEN Punkt", pattern: #"^.*\."#, isRename: true,
                                  sample: "Bericht.v2.final.pdf",
                                  explanation: "`.*` frisst so viel wie möglich – der Treffer reicht bis zum letzten Punkt. Übrig bleibt nur die Endung."),
                RegexGuideExample(title: "Genügsam: bis zum ERSTEN Punkt", pattern: #"^.*?\."#, isRename: true,
                                  sample: "Bericht.v2.final.pdf",
                                  explanation: "Mit `.*?` hört der Treffer schon am ersten Punkt auf."),
            ]),
        RegexGuideChapter(
            id: "anchors", title: "Anfang, Ende, Wortgrenzen", symbol: "arrow.left.and.right",
            paragraphs: [
                "Anker treffen kein Zeichen, sondern eine **Position**. Damit legt man fest, *wo* etwas stehen muss.",
                "Für Dateinamen besonders wichtig: `$` ist das Ende des **ganzen** Namens – also hinter der Endung. Wer „endet mit _final“ meint, muss die Endung mit einplanen: `_final(\\.[^.]+)?$`.",
            ],
            table: [
                ("^", "Anfang des Namens"),
                ("$", "Ende des Namens (nach der Endung!)"),
                ("\\b", "Wortgrenze (zwischen Buchstabe und Nicht-Buchstabe)"),
                ("\\.[^.]+$", "die Dateiendung: Punkt + alles ohne Punkt bis zum Ende"),
            ],
            examples: [
                RegexGuideExample(title: "Beginnt mit IMG", pattern: "^IMG",
                                  sample: "IMG_0815.HEIC",
                                  explanation: "Nur am Anfang – „Mein IMG.jpg“ passt nicht."),
                RegexGuideExample(title: "Nur PDFs und Word-Dateien", pattern: #"\.(pdf|docx?)$"#,
                                  sample: "Vertrag.docx",
                                  explanation: "`docx?` heißt „doc, optional mit x“. Das `$` sorgt dafür, dass es wirklich die Endung ist."),
                RegexGuideExample(title: "Ganzes Wort „Test“", pattern: #"\bTest\b"#,
                                  sample: "Test Bericht.txt",
                                  explanation: "Findet „Test“, aber nicht „Testament“ oder „Attest“."),
            ]),
        RegexGuideChapter(
            id: "groups", title: "Gruppen und Ersetzen mit $1", symbol: "rectangle.3.group",
            paragraphs: [
                "Runde Klammern `( )` fassen etwas zusammen **und merken es sich**. Die erste Klammer ist Gruppe 1, die zweite Gruppe 2 usw. (gezählt wird die öffnende Klammer von links).",
                "In der Ersetzung setzt `$1` den Inhalt von Gruppe 1 ein, `$0` den ganzen Treffer. So kann man Teile behalten, umstellen oder einrahmen.",
                "`(?:…)` gruppiert, ohne sich etwas zu merken – praktisch, wenn man nur `|` oder eine Wiederholung braucht. `|` heißt „oder“.",
                "Was nicht im Treffer liegt, bleibt unverändert. Will man den **ganzen** Namen neu bauen, muss das Muster von `^` bis `$` reichen.",
            ],
            examples: [
                RegexGuideExample(title: "Nummer behalten, Rest neu", pattern: #"^IMG_(\d+)"#, replacement: "Urlaub $1",
                                  sample: "IMG_0815.jpg",
                                  explanation: "`(\\d+)` merkt sich die Ziffern als `$1`. Die Endung liegt außerhalb des Treffers und bleibt erhalten."),
                RegexGuideExample(title: "Datum umstellen", pattern: #"(\d{2})\.(\d{2})\.(\d{4})"#, replacement: "$3-$2-$1",
                                  sample: "Rechnung 14.03.2025.pdf",
                                  explanation: "Tag, Monat, Jahr als Gruppen 1–3, neu zusammengesetzt als Jahr-Monat-Tag – so sortieren die Dateien richtig."),
                RegexGuideExample(title: "Künstler und Titel tauschen", pattern: #"^(.+?) - (.+?)(\.[^.]+)?$"#, replacement: "$2 - $1$3",
                                  sample: "Beatles - Help.mp3",
                                  explanation: "Gruppe 3 ist die Endung. Weil das Muster den ganzen Namen abdeckt, wird alles neu gebaut."),
                RegexGuideExample(title: "Treffer einklammern", pattern: #"(19|20)\d{2}"#, replacement: "($0)",
                                  sample: "Urlaub 2024.jpg",
                                  explanation: "`$0` ist der ganze Treffer – hier wird die Jahreszahl in Klammern gesetzt."),
            ]),
        RegexGuideChapter(
            id: "lookaround", title: "Vorausschau: muss / darf nicht folgen", symbol: "eye",
            paragraphs: [
                "Eine **Vorausschau** prüft, was an einer Stelle folgt, ohne es zum Treffer zu machen. `(?=…)` heißt „danach kommt …“, `(?!…)` heißt „danach kommt NICHT …“.",
                "Rückschau gibt es auch: `(?<=…)` „davor steht …“ und `(?<!…)` „davor steht nicht …“.",
                "Typischer Trick für die Suche: `^(?=.*A)(?=.*B)` findet Namen, die A **und** B enthalten – in beliebiger Reihenfolge. `^(?!.*Kopie)` findet alle Namen **ohne** „Kopie“.",
            ],
            examples: [
                RegexGuideExample(title: "Enthält Rechnung UND 2025", pattern: "^(?=.*Rechnung)(?=.*2025)",
                                  sample: "2025-01 Strom Rechnung.pdf",
                                  explanation: "Zwei Vorausschauen am Anfang – beide müssen irgendwo im Namen zutreffen."),
                RegexGuideExample(title: "Alles außer Kopien", pattern: "^(?!.*Kopie)",
                                  sample: "Bild.jpg",
                                  explanation: "Trifft jeden Namen, in dem „Kopie“ nicht vorkommt."),
                RegexGuideExample(title: "Zahl nur, wenn € folgt", pattern: #"\d+(?=\s?€)"#,
                                  sample: "Beleg 45 €.pdf",
                                  explanation: "Das € gehört nicht zum Treffer, muss aber direkt folgen."),
            ]),
        RegexGuideChapter(
            id: "pitfalls", title: "Typische Fallen", symbol: "exclamationmark.triangle",
            paragraphs: [
                "**Punkt vergessen zu schützen:** `.jpg` trifft auch „xjpg“, weil `.` jedes Zeichen ist. Richtig: `\\.jpg$`.",
                "**Endung zerstört:** `^.*$` mit Ersetzung „Neu“ macht aus „Foto.jpg“ einfach „Neu“ – ohne Endung. Die Endung als Gruppe mitnehmen: `^.*?(\\.[^.]+)?$` → `Neu$1`.",
                "**Zu gierig:** `\\(.*\\)` in „A (1) B (2)“ trifft „(1) B (2)“ am Stück. Besser: `\\([^)]*\\)` – „Klammer auf, alles außer Klammer zu, Klammer zu“.",
                "**Alle Namen gleich:** Wenn die Ersetzung keine `$`-Gruppe enthält und den ganzen Namen trifft, heißen alle Dateien gleich. Der Assistent warnt in diesem Fall vor doppelten Namen.",
                "**Verbotene Zeichen:** `/` und `:` sind in macOS-Dateinamen nicht erlaubt.",
                "**$ in der Ersetzung wörtlich:** Ein echtes Dollarzeichen schreibt man als `\\$`.",
            ],
            examples: [
                RegexGuideExample(title: "Klammern genügsam entfernen", pattern: #"\s*\([^)]*\)"#, isRename: true,
                                  sample: "Film (2019) Final (HD).mkv",
                                  explanation: "Jede Klammer wird einzeln entfernt, der Text dazwischen bleibt."),
                RegexGuideExample(title: "Ganzen Namen ersetzen, Endung behalten", pattern: #"^.*?(\.[^.]+)?$"#, replacement: "Neu$1",
                                  sample: "irgendwas.jpg",
                                  explanation: "Gruppe 1 ist die (optionale) Endung und wird wieder angehängt."),
            ]),
        RegexGuideChapter(
            id: "recipes", title: "Rezepte für Dateinamen", symbol: "book",
            paragraphs: [
                "Fertige Muster für häufige Aufgaben. Mit „In der Werkstatt ausprobieren“ übernehmen und an die eigenen Namen anpassen.",
            ],
            examples: [
                RegexGuideExample(title: "Fotos vom iPhone / von Kameras", pattern: #"^(IMG|DSC|DSCN|PXL)_?\d+"#,
                                  sample: "PXL_20250314_101530.jpg",
                                  explanation: "Typische Präfixe von Kameras und Smartphones, gefolgt von einer Nummer."),
                RegexGuideExample(title: "Bildschirmfotos umbenennen",
                                  pattern: #"^Bildschirmfoto (\d{4}-\d{2}-\d{2}) um (\d{2})\.(\d{2})\.(\d{2})"#,
                                  replacement: "$1 $2-$3-$4 Screenshot",
                                  sample: "Bildschirmfoto 2025-03-14 um 10.15.30.png",
                                  explanation: "Datum und Uhrzeit aus dem macOS-Namen übernehmen, kürzer und sortierbar."),
                RegexGuideExample(title: "Serienfolgen erkennen", pattern: #"S(\d{1,2})E(\d{1,2})"#, replacement: "Staffel $1 Folge $2",
                                  sample: "Serie.S01E05.mkv",
                                  explanation: "S01E05 wird zu „Staffel 01 Folge 05“."),
                RegexGuideExample(title: "Führende Nummer zweistellig machen", pattern: #"^(\d)(?=\D)"#, replacement: "0$1",
                                  sample: "7 Track.mp3",
                                  explanation: "Eine einzelne Ziffer am Anfang bekommt eine 0 davor, damit 07 vor 10 sortiert."),
                RegexGuideExample(title: "„Kopie“ und „(1)“ entfernen", pattern: #"( Kopie( \d+)?| \(\d+\))(\.[^.]+)?$"#, replacement: "$3",
                                  sample: "Vertrag Kopie 2.pdf",
                                  explanation: "Der Zusatz direkt vor der Endung fällt weg, die Endung ($3) bleibt."),
                RegexGuideExample(title: "Mehrere Leerzeichen zu einem", pattern: #"\s{2,}"#, replacement: " ",
                                  sample: "Mein    Dokument.txt",
                                  explanation: "Zwei oder mehr Leerzeichen werden zu einem."),
            ]),
    ]
}
