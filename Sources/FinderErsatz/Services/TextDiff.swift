import Foundation

/// Zeilenweiser Vergleich zweier Texte für die Nebeneinander-Ansicht (wie „Nach Inhalt vergleichen“ im Total Commander).
enum TextDiff {
    enum Kind: Sendable { case same, changed, leftOnly, rightOnly }

    struct Row: Identifiable, Sendable {
        let id: Int
        let leftNumber: Int?
        let rightNumber: Int?
        let left: String?
        let right: String?
        let kind: Kind
    }

    struct Result: Sendable {
        var rows: [Row] = []
        /// Zeilenindizes, an denen ein Block von Unterschieden beginnt (zum Springen)
        var blockStarts: [Int] = []
        var changedCount = 0
        var leftOnlyCount = 0
        var rightOnlyCount = 0
        var isIdentical: Bool { changedCount == 0 && leftOnlyCount == 0 && rightOnlyCount == 0 }
    }

    /// Größte Datei, die noch als Text verglichen wird
    static let maxBytes = 8 * 1024 * 1024

    enum LoadResult: Sendable {
        case text(String)
        case binary
        case tooLarge(Int64)
        case failed(String)
    }

    static func load(_ url: URL) -> LoadResult {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if size > maxBytes { return .tooLarge(size) }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return .failed(error.localizedDescription) }
        // Nullbytes in den ersten 8 KB → Binärdatei
        if data.prefix(8192).contains(0) { return .binary }
        if let text = String(data: data, encoding: .utf8) { return .text(text) }
        if let text = String(data: data, encoding: .windowsCP1252) { return .text(text) }
        return .binary
    }

    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    static func compare(_ leftText: String, _ rightText: String, ignoreWhitespace: Bool, ignoreCase: Bool) -> Result {
        let left = lines(leftText)
        let right = lines(rightText)
        func key(_ line: String) -> String {
            var value = line
            if ignoreWhitespace { value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            if ignoreCase { value = value.lowercased() }
            return value
        }
        let leftKeys = left.map(key)
        let rightKeys = right.map(key)
        let difference = rightKeys.difference(from: leftKeys)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }

        var result = Result()
        var i = 0, j = 0
        var previousWasDiff = false
        while i < left.count || j < right.count {
            let row: Row
            let index = result.rows.count
            if i < left.count, removed.contains(i), j < right.count, inserted.contains(j) {
                row = Row(id: index, leftNumber: i + 1, rightNumber: j + 1, left: left[i], right: right[j], kind: .changed)
                result.changedCount += 1
                i += 1; j += 1
            } else if i < left.count, removed.contains(i) {
                row = Row(id: index, leftNumber: i + 1, rightNumber: nil, left: left[i], right: nil, kind: .leftOnly)
                result.leftOnlyCount += 1
                i += 1
            } else if j < right.count, inserted.contains(j) {
                row = Row(id: index, leftNumber: nil, rightNumber: j + 1, left: nil, right: right[j], kind: .rightOnly)
                result.rightOnlyCount += 1
                j += 1
            } else if i < left.count, j < right.count {
                row = Row(id: index, leftNumber: i + 1, rightNumber: j + 1, left: left[i], right: right[j], kind: .same)
                i += 1; j += 1
            } else if i < left.count {
                // Sollte nicht vorkommen (alles Übrige ist entfernt) – sicherheitshalber als „nur links“
                row = Row(id: index, leftNumber: i + 1, rightNumber: nil, left: left[i], right: nil, kind: .leftOnly)
                result.leftOnlyCount += 1
                i += 1
            } else {
                row = Row(id: index, leftNumber: nil, rightNumber: j + 1, left: nil, right: right[j], kind: .rightOnly)
                result.rightOnlyCount += 1
                j += 1
            }
            let isDiff = row.kind != .same
            if isDiff && !previousWasDiff { result.blockStarts.append(index) }
            previousWasDiff = isDiff
            result.rows.append(row)
        }
        return result
    }
}
