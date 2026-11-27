import SwiftUI
import AppKit

/// Datum für Dateinamen (Umbenennen): Quelle und Format. Doppelpunkte sind in Dateinamen nicht erlaubt.
enum DateStamp {
    enum Source: String, CaseIterable, Identifiable {
        case today, modified, created
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: "Heute"
            case .modified: "Änderungsdatum"
            case .created: "Erstellungsdatum"
            }
        }
        func date(for item: FileItem) -> Date {
            switch self {
            case .today: Date()
            case .modified: item.modified
            case .created: item.created
            }
        }
    }

    enum Format: String, CaseIterable, Identifiable {
        case isoDate = "yyyy-MM-dd"
        case compact = "yyyyMMdd"
        case german = "dd.MM.yyyy"
        case isoDateTime = "yyyy-MM-dd HH-mm"
        case yearMonth = "yyyy-MM"
        case year = "yyyy"
        var id: String { rawValue }

        func string(from date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = rawValue
            return formatter.string(from: date)
        }

        /// Beispiel fürs Menü, z. B. „2026-11-27“
        var example: String { string(from: Date()) }
    }
}

/// Einfaches Umbenennen (F2) mit „Datum einfügen“. Ersetzt den früheren Alert, weil ein Alert keine Menüs kann.
struct RenameSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let item: FileItem

    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var browser = browser
        VStack(alignment: .leading, spacing: 12) {
            Text("„\(item.name)“ umbenennen").font(.headline)
            TextField("Neuer Name", text: $browser.renameText, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(minWidth: 380)
                .onSubmit(commit)
            HStack {
                Menu {
                    ForEach(DateStamp.Source.allCases) { source in
                        Section(source.title) {
                            ForEach(DateStamp.Format.allCases) { format in
                                Button(format.string(from: source.date(for: item))) {
                                    insert(format.string(from: source.date(for: item)))
                                }
                            }
                        }
                    }
                } label: {
                    Label("Datum einfügen", systemImage: "calendar.badge.plus")
                }
                .fixedSize()
                .help("Fügt das Datum an der Schreibmarke ein (ohne Schreibmarke vor dem Namen)")
                Spacer()
            }
            HStack {
                Button("Erweitert (Regex, Nummerieren, Datum) …") {
                    dismiss()
                    // Erst nach dem Schließen dieses Sheets das nächste zeigen
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        browser.beginBatchRename()
                    }
                }
                Spacer()
                Button("Abbrechen", role: .cancel) {
                    browser.renameTarget = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Umbenennen", action: commit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            focused = true
            // Wie im Finder: nur den Namen ohne Endung markieren
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                let text = browser.renameText
                selection = TextSelection(range: text.startIndex..<stemEnd(of: text))
            }
        }
    }

    private func commit() {
        browser.commitRename()
        dismiss()
    }

    /// Ende des Namens vor der Endung (bei Ordnern das Ende)
    private func stemEnd(of text: String) -> String.Index {
        guard !item.isBrowsableFolder, let dot = text.lastIndex(of: "."), dot != text.startIndex else { return text.endIndex }
        return dot
    }

    /// Text an der Schreibmarke einfügen (ersetzt eine Markierung); Leerzeichen zu Nachbarn ergänzen.
    private func insert(_ stamp: String) {
        var text = browser.renameText
        var lower = 0
        var upper = 0
        if let selection, case let .selection(range) = selection.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            lower = text.distance(from: text.startIndex, to: range.lowerBound)
            upper = text.distance(from: text.startIndex, to: range.upperBound)
            // Ganzer Name ohne Endung markiert (Startzustand): nicht ersetzen, sondern davor einfügen
            if lower == 0, upper == text.distance(from: text.startIndex, to: stemEnd(of: text)), upper > 0 { upper = 0 }
        }
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        let separators: Set<Character> = [" ", "-", "_", "."]
        var piece = stamp
        if start > text.startIndex, !separators.contains(text[text.index(before: start)]) { piece = " " + piece }
        if end < text.endIndex, !separators.contains(text[end]) { piece += " " }
        text.replaceSubrange(start..<end, with: piece)
        browser.renameText = text
        let caret = text.index(text.startIndex, offsetBy: lower + piece.count)
        selection = TextSelection(insertionPoint: caret)
    }
}
