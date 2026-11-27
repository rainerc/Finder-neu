import Foundation
import UniformTypeIdentifiers

/// Eine Bedingungszeile wie in der Finder-Suche: „Art ist Bild“, „Änderungsdatum innerhalb der letzten 7 Tage“ …
/// Wird zur Laufzeit in eine Spotlight-Abfrage übersetzt (relative Datumsangaben bleiben dadurch aktuell)
/// oder – auf Netzwerkvolumes ohne Spotlight-Index – direkt an den Dateien geprüft.
struct SearchCriterion: Identifiable, Hashable, Codable, Sendable {
    enum Attribute: String, CaseIterable, Identifiable, Codable, Sendable {
        case kind, name, fileExtension, contents, modified, created, lastOpened, size, tag
        var id: String { rawValue }
        var title: String {
            switch self {
            case .kind: "Art"
            case .name: "Name"
            case .fileExtension: "Dateiendung"
            case .contents: "Inhalt"
            case .modified: "Änderungsdatum"
            case .created: "Erstellungsdatum"
            case .lastOpened: "Zuletzt geöffnet"
            case .size: "Größe"
            case .tag: "Tag"
            }
        }
        var isDate: Bool { [Attribute.modified, .created, .lastOpened].contains(self) }
        var isText: Bool { [Attribute.name, .fileExtension, .contents, .tag].contains(self) }
    }

    enum TextOperator: String, CaseIterable, Identifiable, Codable, Sendable {
        case contains, begins, ends, equals, notContains
        var id: String { rawValue }
        var title: String {
            switch self {
            case .contains: "enthält"
            case .begins: "beginnt mit"
            case .ends: "endet mit"
            case .equals: "ist"
            case .notContains: "enthält nicht"
            }
        }
    }

    enum DateOperator: String, CaseIterable, Identifiable, Codable, Sendable {
        case withinLast, today, yesterday, thisWeek, thisMonth, thisYear, inYear, before, after, exactly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .withinLast: "innerhalb der letzten"
            case .today: "heute"
            case .yesterday: "gestern"
            case .thisWeek: "diese Woche"
            case .thisMonth: "diesen Monat"
            case .thisYear: "dieses Jahr"
            case .inYear: "im Jahr"
            case .before: "vor dem"
            case .after: "nach dem"
            case .exactly: "am"
            }
        }
    }

    enum DateUnit: String, CaseIterable, Identifiable, Codable, Sendable {
        case days, weeks, months, years
        var id: String { rawValue }
        var title: String {
            switch self {
            case .days: "Tage"
            case .weeks: "Wochen"
            case .months: "Monate"
            case .years: "Jahre"
            }
        }
        var component: Calendar.Component {
            switch self {
            case .days: .day
            case .weeks: .weekOfYear
            case .months: .month
            case .years: .year
            }
        }
    }

    enum SizeOperator: String, CaseIterable, Identifiable, Codable, Sendable {
        case greater, less
        var id: String { rawValue }
        var title: String { self == .greater ? "größer als" : "kleiner als" }
    }

    enum SizeUnit: String, CaseIterable, Identifiable, Codable, Sendable {
        case kb, mb, gb
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
        var bytes: Double {
            switch self {
            case .kb: 1_000
            case .mb: 1_000_000
            case .gb: 1_000_000_000
            }
        }
    }

    enum Kind: String, CaseIterable, Identifiable, Codable, Sendable {
        case folder, image, movie, audio, pdf, text, document, presentation, spreadsheet, archive, application
        var id: String { rawValue }
        var title: String {
            switch self {
            case .folder: "Ordner"
            case .image: "Bild"
            case .movie: "Film"
            case .audio: "Musik / Audio"
            case .pdf: "PDF"
            case .text: "Text"
            case .document: "Dokument (Word, Pages …)"
            case .presentation: "Präsentation"
            case .spreadsheet: "Tabelle"
            case .archive: "Archiv (ZIP …)"
            case .application: "Programm"
            }
        }
        /// Spotlight-Typen (kMDItemContentTypeTree) bzw. UTTypes für die direkte Prüfung
        var typeIdentifiers: [String] {
            switch self {
            case .folder: ["public.folder"]
            case .image: ["public.image"]
            case .movie: ["public.movie"]
            case .audio: ["public.audio"]
            case .pdf: ["com.adobe.pdf"]
            case .text: ["public.text"]
            case .document: ["com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document",
                             "com.apple.iwork.pages.sffpages", "com.apple.pages.document", "public.rtf",
                             "org.oasis-open.opendocument.text"]
            case .presentation: ["public.presentation"]
            case .spreadsheet: ["public.spreadsheet"]
            case .archive: ["public.archive"]
            case .application: ["com.apple.application"]
            }
        }
    }

    var id = UUID()
    var attribute: Attribute = .kind
    var textOperator: TextOperator = .contains
    var text = ""
    var kind: Kind = .image
    var dateOperator: DateOperator = .withinLast
    var amount = 7
    var dateUnit: DateUnit = .days
    var date = Date()
    var sizeOperator: SizeOperator = .greater
    var size = 10.0
    var sizeUnit: SizeUnit = .mb

    init(attribute: Attribute = .kind) {
        self.attribute = attribute
    }

    /// Hat die Zeile genug Angaben, um gesucht zu werden?
    var isComplete: Bool {
        attribute.isText ? !text.trimmingCharacters(in: .whitespaces).isEmpty : true
    }

    // MARK: Zeitraum

    /// Zeitraum [von, bis) für die Datumsbedingungen, zum Zeitpunkt der Suche berechnet.
    func dateRange(now: Date = Date(), calendar: Calendar = .current) -> (from: Date?, to: Date?) {
        let today = calendar.startOfDay(for: now)
        switch dateOperator {
        case .withinLast:
            return (calendar.date(byAdding: dateUnit.component, value: -max(amount, 0), to: now), nil)
        case .today:
            return (today, nil)
        case .yesterday:
            return (calendar.date(byAdding: .day, value: -1, to: today), today)
        case .thisWeek:
            return (calendar.dateInterval(of: .weekOfYear, for: now)?.start, nil)
        case .thisMonth:
            return (calendar.dateInterval(of: .month, for: now)?.start, nil)
        case .thisYear:
            return (calendar.dateInterval(of: .year, for: now)?.start, nil)
        case .inYear:
            let start = calendar.date(from: DateComponents(year: amount, month: 1, day: 1))
            return (start, start.flatMap { calendar.date(byAdding: .year, value: 1, to: $0) })
        case .before:
            return (nil, calendar.startOfDay(for: date))
        case .after:
            return (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)), nil)
        case .exactly:
            let start = calendar.startOfDay(for: date)
            return (start, calendar.date(byAdding: .day, value: 1, to: start))
        }
    }

    // MARK: Spotlight

    /// Bedingung in mdfind-Syntax, z. B. `kMDItemContentTypeTree == "public.image"`.
    func spotlightCondition(caseSensitive: Bool) -> String? {
        guard isComplete else { return nil }
        let flags = caseSensitive ? "" : "cd"
        switch attribute {
        case .kind:
            let parts = kind.typeIdentifiers.map { "kMDItemContentTypeTree == \"\($0)\"" }
            return parts.count == 1 ? parts[0] : "(" + parts.joined(separator: " || ") + ")"
        case .name:
            return textCondition("kMDItemFSName", flags: flags)
        case .contents:
            return textCondition("kMDItemTextContent", flags: flags)
        case .tag:
            return textCondition("kMDItemUserTags", flags: flags)
        case .fileExtension:
            let ext = Self.escape(text.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
            return "kMDItemFSName == \"*.\(ext)\"c"
        case .modified, .created, .lastOpened:
            let key = switch attribute {
            case .modified: "kMDItemFSContentChangeDate"
            case .created: "kMDItemFSCreationDate"
            default: "kMDItemLastUsedDate"
            }
            let range = dateRange()
            var parts: [String] = []
            if let from = range.from { parts.append("\(key) >= $time.iso(\(Self.iso(from)))") }
            if let to = range.to { parts.append("\(key) < $time.iso(\(Self.iso(to)))") }
            return parts.isEmpty ? nil : "(" + parts.joined(separator: " && ") + ")"
        case .size:
            let bytes = Int64(size * sizeUnit.bytes)
            return "kMDItemFSSize \(sizeOperator == .greater ? ">" : "<") \(bytes)"
        }
    }

    private func textCondition(_ key: String, flags: String) -> String {
        let value = Self.escape(text.trimmingCharacters(in: .whitespaces))
        switch textOperator {
        case .contains: return "\(key) == \"*\(value)*\"\(flags)"
        case .begins: return "\(key) == \"\(value)*\"\(flags)"
        case .ends: return "\(key) == \"*\(value)\"\(flags)"
        case .equals: return "\(key) == \"\(value)\"\(flags)"
        case .notContains: return "\(key) != \"*\(value)*\"\(flags)"
        }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: Direkte Prüfung (ohne Spotlight, z. B. auf dem NAS)

    static let resourceKeys: Set<URLResourceKey> = [
        .nameKey, .contentTypeKey, .contentModificationDateKey, .creationDateKey, .contentAccessDateKey,
        .fileSizeKey, .tagNamesKey, .isDirectoryKey, .isRegularFileKey,
    ]

    /// Prüft die Bedingung an einer Datei. Inhalt wird nicht hier, sondern in `FileSearch` geprüft.
    func matches(_ url: URL, values: URLResourceValues, caseSensitive: Bool) -> Bool {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
        switch attribute {
        case .kind:
            if kind == .folder { return values.isDirectory == true }
            guard let type = values.contentType else { return false }
            return kind.typeIdentifiers.contains { identifier in
                UTType(identifier).map { type.conforms(to: $0) } ?? false
            }
        case .name:
            return textMatches(values.name ?? url.lastPathComponent, options: options)
        case .fileExtension:
            let ext = text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return url.pathExtension.compare(ext, options: [.caseInsensitive]) == .orderedSame
        case .tag:
            let tags = values.tagNames ?? []
            if textOperator == .notContains {
                return !tags.contains { $0.range(of: text, options: options) != nil }
            }
            return tags.contains { textMatches($0, options: options) }
        case .contents:
            return true
        case .modified, .created, .lastOpened:
            let value: Date? = switch attribute {
            case .modified: values.contentModificationDate
            case .created: values.creationDate
            default: values.contentAccessDate
            }
            guard let value else { return false }
            let range = dateRange()
            if let from = range.from, value < from { return false }
            if let to = range.to, value >= to { return false }
            return true
        case .size:
            guard values.isRegularFile == true else { return false }
            let bytes = Double(values.fileSize ?? 0)
            let limit = size * sizeUnit.bytes
            return sizeOperator == .greater ? bytes > limit : bytes < limit
        }
    }

    private func textMatches(_ candidate: String, options: String.CompareOptions) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespaces)
        switch textOperator {
        case .contains: return candidate.range(of: needle, options: options) != nil
        case .begins: return candidate.range(of: needle, options: options.union(.anchored)) != nil
        case .ends: return candidate.range(of: needle, options: options.union([.anchored, .backwards])) != nil
        case .equals: return candidate.compare(needle, options: options) == .orderedSame
        case .notContains: return candidate.range(of: needle, options: options) == nil
        }
    }
}
