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

    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
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
