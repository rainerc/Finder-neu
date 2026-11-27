import SwiftUI

/// „Auswählen …“ / „Auswahl aufheben …“ (⌘+ / ⌘−) wie im Total Commander:
/// Namensmuster plus optional Größe, Änderungsdatum, Inhalt und Art. Alle gesetzten Bedingungen müssen zutreffen.
struct SelectSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: SelectRequest

    @State private var pattern = "*"
    @AppStorage("select.kind") private var kind = SelectCriteria.Kind.all.rawValue
    @AppStorage("select.useSize") private var useSize = false
    @AppStorage("select.sizeLarger") private var sizeLarger = true
    @AppStorage("select.sizeValue") private var sizeValue = 1.0
    @AppStorage("select.sizeUnit") private var sizeUnit = 2   // 0 Byte, 1 KB, 2 MB, 3 GB
    @AppStorage("select.useDate") private var useDate = false
    /// 0 in den letzten N Tagen, 1 vor mehr als N Tagen, 2 nach Datum, 3 vor Datum
    @AppStorage("select.dateMode") private var dateMode = 0
    @AppStorage("select.days") private var days = 7
    @State private var date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @AppStorage("select.useContent") private var useContent = false
    @State private var content = ""
    @AppStorage("select.ignoreCase") private var ignoreCase = true

    private static let units: [(String, Int64)] = [("Byte", 1), ("KB", 1_000), ("MB", 1_000_000), ("GB", 1_000_000_000)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.select ? "Auswählen" : "Auswahl aufheben").font(.headline)

            Form {
                TextField("Name:", text: $pattern, prompt: Text("z. B. *.jpg; *.png"))
                    .help("* steht für beliebige Zeichen, ? für genau eines. Mehrere Muster mit ; trennen")
                Picker("Art:", selection: $kind) {
                    Text("Dateien und Ordner").tag(SelectCriteria.Kind.all.rawValue)
                    Text("Nur Dateien").tag(SelectCriteria.Kind.files.rawValue)
                    Text("Nur Ordner").tag(SelectCriteria.Kind.folders.rawValue)
                }

                HStack {
                    Toggle("Größe", isOn: $useSize)
                    Picker("", selection: $sizeLarger) {
                        Text("größer als").tag(true)
                        Text("kleiner als").tag(false)
                    }
                    .labelsHidden().fixedSize()
                    TextField("", value: $sizeValue, format: .number)
                        .frame(width: 70)
                    Picker("", selection: $sizeUnit) {
                        ForEach(Self.units.indices, id: \.self) { Text(Self.units[$0].0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }

                HStack {
                    Toggle("Geändert", isOn: $useDate)
                    Picker("", selection: $dateMode) {
                        Text("in den letzten").tag(0)
                        Text("vor mehr als").tag(1)
                        Text("nach dem").tag(2)
                        Text("vor dem").tag(3)
                    }
                    .labelsHidden().fixedSize()
                    if dateMode < 2 {
                        TextField("", value: $days, format: .number).frame(width: 50)
                        Text("Tagen")
                    } else {
                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }

                HStack {
                    Toggle("Inhalt enthält", isOn: $useContent)
                    TextField("", text: $content, prompt: Text("Text"))
                        .frame(minWidth: 160)
                    Toggle("Groß/klein egal", isOn: $ignoreCase)
                }
            }

            Text(hint).font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.select ? "Auswählen" : "Abwählen") {
                    browser.selectPatternText = pattern
                    browser.applySelection(criteria, select: request.select)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear { pattern = browser.selectPatternText }
    }

    private var hint: String {
        var text = "Alle gesetzten Bedingungen müssen zutreffen."
        if useSize { text += " Ordner zählen bei der Größe nur, wenn ihre Größe berechnet ist." }
        if useContent { text += " Die Inhaltssuche prüft nur Dateien und läuft im Hintergrund." }
        return text
    }

    private var criteria: SelectCriteria {
        var result = SelectCriteria()
        result.patterns = pattern.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "*" && $0 != "*.*" }
        result.kind = SelectCriteria.Kind(rawValue: kind) ?? .all
        if useSize {
            let bytes = Int64(max(sizeValue, 0) * Double(Self.units[min(max(sizeUnit, 0), 3)].1))
            if sizeLarger { result.minSize = bytes } else { result.maxSize = bytes }
        }
        if useDate {
            let reference = dateMode < 2
                ? Calendar.current.date(byAdding: .day, value: -max(days, 0), to: .now) ?? .now
                : date
            if dateMode == 0 || dateMode == 2 { result.modifiedAfter = reference } else { result.modifiedBefore = reference }
        }
        if useContent, !content.isEmpty {
            result.content = content
            result.contentIgnoresCase = ignoreCase
        }
        return result
    }
}
