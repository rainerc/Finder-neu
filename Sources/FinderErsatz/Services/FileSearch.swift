import Foundation

/// Durchsucht einen Ordner rekursiv nach Name und/oder Inhalt. Läuft synchron –
/// aufrufen aus einem Hintergrund-Task; Abbruch über `Task.cancel()`.
enum FileSearch {
    static let maxResults = 5000
    static let maxContentFileSize: Int64 = 50 * 1024 * 1024

    struct InvalidPattern: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(_ query: SearchQuery, onBatch: @Sendable ([FileItem]) -> Void) throws {
        if let raw = query.spotlightQuery {
            try spotlight(raw: raw, root: query.searchesEverywhere ? nil : query.root, onBatch: onBatch)
            return
        }
        if query.mode == .spotlight {
            try spotlight(query, onBatch: onBatch)
            return
        }
        let matchesName = try nameMatcher(for: query)
        let needle = query.contentText

        var options: FileManager.DirectoryEnumerationOptions = []
        if !query.includeHidden { options.insert(.skipsHiddenFiles) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: query.root, includingPropertiesForKeys: keys, options: options,
            errorHandler: { _, _ in true }   // unlesbare Ordner überspringen
        ) else { return }

        var batch: [FileItem] = []
        var total = 0
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard matchesName(url.lastPathComponent) else { continue }
            if !needle.isEmpty {
                guard contentMatches(url, needle: needle, query: query) else { continue }
            }
            guard let item = FileItem(url: url) else { continue }
            batch.append(item)
            total += 1
            if batch.count >= 50 {
                onBatch(batch)
                batch.removeAll()
            }
            if total >= maxResults { break }
        }
        if !batch.isEmpty { onBatch(batch) }
    }

    // MARK: Name

    private static func nameMatcher(for query: SearchQuery) throws -> (String) -> Bool {
        let term = query.term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return { _ in true } }
        let regexOptions: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]

        switch query.mode {
        case .contains, .spotlight:
            let options: String.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
            return { $0.range(of: term, options: options) != nil }
        case .wildcard:
            // Mehrere Muster mit ; trennen, z. B. „*.jpg; *.png“
            let patterns = term.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let regexes = try patterns.map { pattern in
                let escaped = NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: ".*")
                    .replacingOccurrences(of: "\\?", with: ".")
                return try NSRegularExpression(pattern: "^\(escaped)$", options: regexOptions)
            }
            return { name in
                let range = NSRange(name.startIndex..., in: name)
                return regexes.contains { $0.firstMatch(in: name, range: range) != nil }
            }
        case .regex:
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: term, options: regexOptions)
            } catch {
                throw InvalidPattern(message: "Ungültiger regulärer Ausdruck: \(term)")
            }
            return { name in regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil }
        }
    }

    // MARK: Inhalt

    private static func contentMatches(_ url: URL, needle: String, query: SearchQuery) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              Int64(values.fileSize ?? 0) <= maxContentFileSize,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let text: String?
        switch query.encoding {
        case .utf8: text = String(decoding: data, as: UTF8.self)
        default: text = String(data: data, encoding: query.encoding.encoding)
        }
        guard let text else { return false }
        let options: String.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
        return text.range(of: needle, options: options) != nil
    }

    // MARK: Spotlight

    /// Nutzt `mdfind` (Spotlight-Index): sehr schnell, durchsucht Name und Inhalt indizierter Dateien.
    private static func spotlight(_ query: SearchQuery, onBatch: @Sendable ([FileItem]) -> Void) throws {
        let term = query.term.trimmingCharacters(in: .whitespaces)
        var arguments = ["-onlyin", query.root.path]
        if !query.contentText.isEmpty {
            arguments.append(term.isEmpty ? query.contentText : "\(term) \(query.contentText)")
        } else {
            arguments += ["-name", term]
        }
        let output = try ProcessRunner.run("/usr/bin/mdfind", arguments)
        let paths = output.split(separator: "\n").prefix(maxResults)
        var batch: [FileItem] = []
        for path in paths {
            if Task.isCancelled { break }
            if let item = FileItem(url: URL(filePath: String(path))) { batch.append(item) }
            if batch.count >= 200 { onBatch(batch); batch.removeAll() }
        }
        if !batch.isEmpty { onBatch(batch) }
    }

    /// Fertige Spotlight-Abfrage (Zuletzt benutzt, Tags, intelligente Ordner).
    private static func spotlight(raw: String, root: URL?, onBatch: @Sendable ([FileItem]) -> Void) throws {
        var arguments: [String] = []
        if let root { arguments += ["-onlyin", root.path] }
        arguments.append(raw)
        let output = try ProcessRunner.run("/usr/bin/mdfind", arguments)
        var batch: [FileItem] = []
        for path in output.split(separator: "\n").prefix(maxResults) {
            if Task.isCancelled { break }
            if let item = FileItem(url: URL(filePath: String(path))) { batch.append(item) }
            if batch.count >= 200 { onBatch(batch); batch.removeAll() }
        }
        if !batch.isEmpty { onBatch(batch) }
    }
}
