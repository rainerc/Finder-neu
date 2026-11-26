import Foundation

/// Kapselt alle Zugriffe auf das Dateisystem.
enum FileService {
    static func contents(of directory: URL, includeHidden: Bool) throws -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: FileItem.resourceKeys,
            options: options
        )
        return urls.compactMap(FileItem.init(url:))
    }

    static func copy(_ source: URL, into directory: URL) throws {
        let target = uniqueURL(for: source.lastPathComponent, in: directory)
        try FileManager.default.copyItem(at: source, to: target)
    }

    static func move(_ source: URL, into directory: URL) throws {
        let target = uniqueURL(for: source.lastPathComponent, in: directory)
        try FileManager.default.moveItem(at: source, to: target)
    }

    /// Legt in den Papierkorb und liefert den neuen Ort (für „Widerrufen“).
    @discardableResult
    static func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    /// Wie der Finder: „Name Kopie.ext“, „Name Kopie 2.ext“ …
    static func duplicate(_ url: URL) throws -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(base) Kopie" : "\(base) Kopie.\(ext)"
        let target = uniqueURL(for: name, in: url.deletingLastPathComponent())
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    /// Finder-Alias („Name Alias“) im selben Ordner.
    static func makeAlias(_ url: URL) throws -> URL {
        let target = uniqueURL(for: "\(url.lastPathComponent) Alias", in: url.deletingLastPathComponent())
        let data = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: target)
        return target
    }

    /// Finder-Tags setzen (ersetzt alle Tags der Datei).
    static func setTags(_ tags: [String], for url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    @discardableResult
    static func createFolder(in directory: URL) throws -> URL {
        let url = uniqueURL(for: "Neuer Ordner", in: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func rename(_ url: URL, to newName: String) throws -> URL {
        let target = url.deletingLastPathComponent().appending(path: newName)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let va = try? a.resourceValues(forKeys: key).volumeIdentifier,
              let vb = try? b.resourceValues(forKeys: key).volumeIdentifier else { return false }
        return va.isEqual(vb)
    }

    /// Liefert „Name“, „Name 2“, „Name 3“ … – je nachdem, was im Ziel noch frei ist.
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appending(path: name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appending(path: newName)
            counter += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
