import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let size: Int64
    let modified: Date
    let kind: String

    /// Ordner, in die man hineinnavigiert (Pakete wie .app gelten als Datei).
    var isBrowsableFolder: Bool { isDirectory && !isPackage }

    static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    init?(url: URL) {
        guard let v = try? url.resourceValues(forKeys: Set(Self.resourceKeys)) else { return nil }
        self.url = url.normalizedFileURL
        self.name = v.name ?? url.lastPathComponent
        self.isDirectory = v.isDirectory ?? false
        self.isPackage = v.isPackage ?? false
        self.isHidden = v.isHidden ?? url.lastPathComponent.hasPrefix(".")
        self.size = Int64(v.fileSize ?? 0)
        self.modified = v.contentModificationDate ?? .distantPast
        self.kind = v.localizedTypeDescription ?? (isDirectory ? "Ordner" : "Dokument")
    }

    var sizeText: String {
        isBrowsableFolder ? "--" : size.formatted(.byteCount(style: .file))
    }
}

extension URL {
    /// Einheitliche Form ohne abschließenden Schrägstrich, damit Vergleiche/Auswahl zuverlässig sind.
    var normalizedFileURL: URL {
        URL(filePath: standardizedFileURL.path, directoryHint: .notDirectory)
    }
}
