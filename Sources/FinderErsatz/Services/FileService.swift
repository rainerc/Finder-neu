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

    /// Zweigansicht: alle Dateien aus dem Ordner und allen Unterordnern (ohne die Ordner selbst, Pakete als Datei).
    /// Läuft im Hintergrund; höchstens `limit` Objekte.
    static func branchContents(of directory: URL, includeHidden: Bool, limit: Int = 20_000) -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: FileItem.resourceKeys, options: options,
            errorHandler: { _, _ in true }
        ) else { return [] }
        var result: [FileItem] = []
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled || result.count >= limit { break }
            guard let item = FileItem(url: url), !item.isBrowsableFolder else { continue }
            result.append(item)
        }
        return result
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

    /// Neue (meist leere) Datei mit eindeutigem Namen anlegen.
    static func createFile(_ type: NewFileType, in directory: URL) throws -> URL {
        let url = uniqueURL(for: type.fileName, in: directory)
        guard FileManager.default.createFile(atPath: url.path, contents: type.contents) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
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

/// Dateitypen für „Neue Datei“ (Ablage-Menü, Kontextmenü)
enum NewFileType: String, CaseIterable, Identifiable {
    case text, markdown, rtf, html, csv, json, empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Textdatei (.txt)"
        case .markdown: "Markdown (.md)"
        case .rtf: "RTF-Dokument (.rtf)"
        case .html: "HTML-Datei (.html)"
        case .csv: "CSV-Tabelle (.csv)"
        case .json: "JSON-Datei (.json)"
        case .empty: "Leere Datei ohne Endung"
        }
    }

    var fileName: String {
        switch self {
        case .text: "Neue Textdatei.txt"
        case .markdown: "Neue Datei.md"
        case .rtf: "Neues Dokument.rtf"
        case .html: "Neue Seite.html"
        case .csv: "Neue Tabelle.csv"
        case .json: "Neue Datei.json"
        case .empty: "Neue Datei"
        }
    }

    /// Minimaler gültiger Inhalt (RTF/HTML/JSON öffnen sonst je nach App mit Fehler)
    var contents: Data {
        switch self {
        case .rtf: Data("{\\rtf1\\ansi\\deff0 }".utf8)
        case .html: Data("<!DOCTYPE html>\n<html lang=\"de\">\n<head><meta charset=\"utf-8\"><title></title></head>\n<body>\n</body>\n</html>\n".utf8)
        case .json: Data("{}\n".utf8)
        default: Data()
        }
    }
}
