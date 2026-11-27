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
        let criteria = query.criteria.filter(\.isComplete)
        if query.mode == .spotlight
            || ((!criteria.isEmpty || query.scope == .thisMac) && canUseSpotlight(query)) {
            try spotlight(query, criteria: criteria, onBatch: onBatch)
            return
        }
        let matchesName = try nameMatcher(for: query)
        let needle = query.contentText

        var options: FileManager.DirectoryEnumerationOptions = []
        if !query.includeHidden { options.insert(.skipsHiddenFiles) }
        let keys = Array(SearchCriterion.resourceKeys)
        let keySet = SearchCriterion.resourceKeys
        guard let enumerator = FileManager.default.enumerator(
            at: query.root, includingPropertiesForKeys: keys, options: options,
            errorHandler: { _, _ in true }   // unlesbare Ordner überspringen
        ) else { return }

        var batch: [FileItem] = []
        var total = 0
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard matchesName(url.lastPathComponent) else { continue }
            if !criteria.isEmpty {
                guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
                let check: (SearchCriterion) -> Bool = { criterion in
                    if criterion.attribute == .contents {
                        let found = contentMatches(url, needle: criterion.text, query: query)
                        return criterion.textOperator == .notContains ? !found : found
                    }
                    return criterion.matches(url, values: values, caseSensitive: query.caseSensitive)
                }
                guard query.matchAll ? criteria.allSatisfy(check) : criteria.contains(where: check) else { continue }
            }
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

    /// Spotlight ist für „Dieser Mac“ und lokale Volumes sinnvoll; Netzwerkfreigaben sind meist nicht indiziert.
    private static func canUseSpotlight(_ query: SearchQuery) -> Bool {
        if query.searchesEverywhere { return true }
        return (try? query.root.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true
    }

    /// Nutzt `mdfind` (Spotlight-Index): sehr schnell. Baut aus Suchbegriff, Inhalt und Bedingungszeilen
    /// eine Abfrage; Platzhalter und reguläre Ausdrücke werden danach an den Namen geprüft.
    private static func spotlight(_ query: SearchQuery, criteria: [SearchCriterion],
                                  onBatch: @Sendable ([FileItem]) -> Void) throws {
        let flags = query.caseSensitive ? "" : "cd"
        let term = SearchCriterion.escape(query.term.trimmingCharacters(in: .whitespaces))
        var parts: [String] = []
        if !term.isEmpty {
            switch query.mode {
            case .contains:
                parts.append("kMDItemFSName == \"*\(term)*\"\(flags)")
            case .spotlight:
                parts.append("(kMDItemFSName == \"*\(term)*\"cd || kMDItemTextContent == \"*\(term)*\"cd)")
            case .wildcard, .regex:
                break   // wird unten an den Namen geprüft
            }
        }
        if !query.contentText.isEmpty {
            parts.append("kMDItemTextContent == \"*\(SearchCriterion.escape(query.contentText))*\"\(flags)")
        }
        let conditions = criteria.compactMap { $0.spotlightCondition(caseSensitive: query.caseSensitive) }
        if !conditions.isEmpty {
            parts.append("(" + conditions.joined(separator: query.matchAll ? " && " : " || ") + ")")
        }
        if parts.isEmpty { parts.append("kMDItemFSName == \"*\"") }

        var arguments: [String] = []
        if !query.searchesEverywhere { arguments += ["-onlyin", query.root.path] }
        arguments.append(parts.joined(separator: " && "))
        let output = try ProcessRunner.run("/usr/bin/mdfind", arguments)

        let needsNameCheck = !term.isEmpty && (query.mode == .wildcard || query.mode == .regex)
        let matchesName: (String) -> Bool = try needsNameCheck ? nameMatcher(for: query) : { _ in true }
        var batch: [FileItem] = []
        var total = 0
        for line in output.split(separator: "\n") {
            if Task.isCancelled { break }
            let path = String(line)
            if !query.includeHidden, path.contains("/.") { continue }
            let url = URL(filePath: path)
            guard matchesName(url.lastPathComponent), let item = FileItem(url: url) else { continue }
            batch.append(item)
            total += 1
            if batch.count >= 200 { onBatch(batch); batch.removeAll() }
            if total >= maxResults { break }
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
