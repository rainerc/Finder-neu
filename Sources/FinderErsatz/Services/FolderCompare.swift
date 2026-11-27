import Foundation

/// Einstellungen für „Verzeichnisse vergleichen“.
struct CompareOptions: Sendable, Equatable, Hashable {
    enum Method: String, CaseIterable, Identifiable, Sendable {
        case dateAndSize, size, content
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dateAndSize: "Datum und Größe"
            case .size: "Nur Größe"
            case .content: "Inhalt (Byte für Byte)"
            }
        }
    }

    var recursive = false
    var method: Method = .dateAndSize
    var includeHidden = false
}

/// Ergebnis für ein Objekt (Pfad relativ zu den beiden verglichenen Ordnern).
struct CompareEntry: Identifiable, Sendable, Hashable {
    enum Status: String, CaseIterable, Sendable {
        case leftOnly, rightOnly, leftNewer, rightNewer, different, same

        var title: String {
            switch self {
            case .leftOnly: "nur links"
            case .rightOnly: "nur rechts"
            case .leftNewer: "links neuer"
            case .rightNewer: "rechts neuer"
            case .different: "unterschiedlich"
            case .same: "gleich"
            }
        }

        var symbol: String {
            switch self {
            case .leftOnly: "arrow.left.square.fill"
            case .rightOnly: "arrow.right.square.fill"
            case .leftNewer: "chevron.left.2"
            case .rightNewer: "chevron.right.2"
            case .different: "exclamationmark.triangle.fill"
            case .same: "equal"
            }
        }

        /// Richtung, in die „Synchronisieren“ kopiert (nil = nichts tun bzw. nicht eindeutig)
        var syncDirectionToRight: Bool? {
            switch self {
            case .leftOnly, .leftNewer: true
            case .rightOnly, .rightNewer: false
            case .different, .same: nil
            }
        }
    }

    struct Side: Sendable, Hashable {
        let url: URL
        let isDirectory: Bool
        let size: Int64
        let modified: Date
    }

    let relativePath: String
    let left: Side?
    let right: Side?
    let status: Status

    var id: String { relativePath }
    var name: String { (relativePath as NSString).lastPathComponent }
    var isDirectory: Bool { (left ?? right)?.isDirectory ?? false }
}

/// Vergleicht zwei Ordner (linkes/rechtes Fenster). Läuft synchron – aus einem Hintergrund-Task aufrufen;
/// Abbruch über `Task.cancel()`.
enum FolderCompare {
    /// Änderungsdaten innerhalb dieser Spanne gelten als gleich (FAT/SMB speichern nur auf 2 s genau)
    static let dateTolerance: TimeInterval = 2

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]

    static func compare(left: URL, right: URL, options: CompareOptions) -> [CompareEntry] {
        var result: [CompareEntry] = []
        compareLevel(relative: "", left: left, right: right, options: options, into: &result)
        return result
    }

    private static func compareLevel(relative: String, left: URL, right: URL, options: CompareOptions,
                                     into result: inout [CompareEntry]) {
        if Task.isCancelled { return }
        let leftItems = contents(of: left, options: options)
        let rightItems = contents(of: right, options: options)
        let names = Set(leftItems.keys).union(rightItems.keys)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        for name in names {
            if Task.isCancelled { return }
            let path = relative.isEmpty ? name : relative + "/" + name
            let l = leftItems[name]
            let r = rightItems[name]
            switch (l, r) {
            case let (l?, nil):
                result.append(CompareEntry(relativePath: path, left: l, right: nil, status: .leftOnly))
            case let (nil, r?):
                result.append(CompareEntry(relativePath: path, left: nil, right: r, status: .rightOnly))
            case let (l?, r?):
                if l.isDirectory && r.isDirectory {
                    // Ordner, die es auf beiden Seiten gibt: nur bei „Unterordner einbeziehen“ hineinschauen
                    if options.recursive {
                        compareLevel(relative: path, left: l.url, right: r.url, options: options, into: &result)
                    }
                } else if l.isDirectory != r.isDirectory {
                    result.append(CompareEntry(relativePath: path, left: l, right: r, status: .different))
                } else {
                    result.append(CompareEntry(relativePath: path, left: l, right: r,
                                               status: status(l, r, method: options.method)))
                }
            case (nil, nil):
                break
            }
        }
    }

    private static func status(_ l: CompareEntry.Side, _ r: CompareEntry.Side,
                               method: CompareOptions.Method) -> CompareEntry.Status {
        let sameDate = abs(l.modified.timeIntervalSince(r.modified)) <= dateTolerance
        let equal: Bool = switch method {
        case .dateAndSize: l.size == r.size && sameDate
        case .size: l.size == r.size
        case .content: l.size == r.size && sameContent(l.url, r.url)
        }
        if equal { return .same }
        if sameDate { return .different }
        return l.modified > r.modified ? .leftNewer : .rightNewer
    }

    private static func contents(of folder: URL, options: CompareOptions) -> [String: CompareEntry.Side] {
        var fileOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { fileOptions.insert(.skipsHiddenFiles) }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                   options: fileOptions)) ?? []
        var result: [String: CompareEntry.Side] = [:]
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            // Pakete (z. B. .app) wie Dateien behandeln: Größe/Datum des Pakets, nicht hineinschauen
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            result[url.lastPathComponent] = CompareEntry.Side(
                url: url.normalizedFileURL,
                isDirectory: isDirectory,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast
            )
        }
        return result
    }

    /// Inhalt in Blöcken von 1 MB vergleichen
    private static func sameContent(_ a: URL, _ b: URL) -> Bool {
        guard let ha = try? FileHandle(forReadingFrom: a), let hb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? ha.close(); try? hb.close() }
        while true {
            if Task.isCancelled { return false }
            let da = try? ha.read(upToCount: 1 << 20)
            let db = try? hb.read(upToCount: 1 << 20)
            if da != db { return false }
            if da == nil || da?.isEmpty == true { return true }
        }
    }
}
