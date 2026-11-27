import Foundation
import CryptoKit

/// Einstellungen für „Doppelte Dateien suchen“.
struct DuplicateOptions: Sendable, Hashable {
    enum Method: String, CaseIterable, Identifiable, Sendable {
        case content, nameAndSize, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .content: "Gleicher Inhalt"
            case .nameAndSize: "Gleicher Name und Größe"
            case .name: "Gleicher Name"
            }
        }
    }

    var method: Method = .content
    var minSize: Int64 = 1
    var includeHidden = false
}

struct DuplicateFile: Identifiable, Sendable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let files: [DuplicateFile]
    var size: Int64 { files.first?.size ?? 0 }
    /// Platz, der frei würde, wenn nur eine Datei übrig bleibt
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

/// Sucht doppelte Dateien in Ordnern (rekursiv). Läuft synchron – aus einem Hintergrund-Task aufrufen.
enum DuplicateFinder {
    static let maxFiles = 300_000

    static func find(in folders: [URL], options: DuplicateOptions) -> (groups: [DuplicateGroup], scanned: Int) {
        let files = collect(folders, options: options)
        var groups: [[DuplicateFile]]
        switch options.method {
        case .name:
            groups = Array(Dictionary(grouping: files) { $0.name.lowercased() }.values)
        case .nameAndSize:
            groups = Array(Dictionary(grouping: files) { "\($0.name.lowercased())|\($0.size)" }.values)
        case .content:
            // Erst nach Größe, dann nach Prüfsumme der ersten 64 KB, zuletzt nach Prüfsumme der ganzen Datei
            let bySize = Dictionary(grouping: files, by: \.size).values.filter { $0.count > 1 }
            var result: [[DuplicateFile]] = []
            for sameSize in bySize {
                if Task.isCancelled { break }
                let byHead = Dictionary(grouping: sameSize) { hash($0.url, limit: 64 * 1024) ?? "?\($0.url.path)" }
                for candidates in byHead.values where candidates.count > 1 {
                    if Task.isCancelled { break }
                    if candidates[0].size <= 64 * 1024 {
                        result.append(candidates)   // Kopf = ganze Datei
                    } else {
                        let byFull = Dictionary(grouping: candidates) { hash($0.url, limit: nil) ?? "?\($0.url.path)" }
                        result += byFull.values.filter { $0.count > 1 }
                    }
                }
            }
            groups = result
        }
        let duplicates = groups
            .filter { $0.count > 1 }
            .map { DuplicateGroup(files: $0.sorted { $0.modified < $1.modified }) }
            .sorted { $0.wasted > $1.wasted }
        return (duplicates, files.count)
    }

    private static func collect(_ folders: [URL], options: DuplicateOptions) -> [DuplicateFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }
        var seen = Set<String>()
        var result: [DuplicateFile] = []
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                                  options: enumOptions, errorHandler: { _, _ in true })
            else { continue }
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled || result.count >= maxFiles { return result }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= options.minSize else { continue }
                let normalized = url.normalizedFileURL
                guard seen.insert(normalized.path).inserted else { continue }   // überlappende Ordner
                result.append(DuplicateFile(url: normalized, size: size,
                                            modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return result
    }

    /// SHA-256 der Datei (oder der ersten `limit` Bytes)
    private static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            guard let chunk = try? handle.read(upToCount: min(1 << 20, remaining)), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
