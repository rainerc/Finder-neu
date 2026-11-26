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
    let created: Date
    let accessed: Date
    let fileExtension: String
    let tags: String
    let tagList: [String]
    let permissions: String
    let owner: String

    /// Ordner, in die man hineinnavigiert (Pakete wie .app gelten als Datei).
    var isBrowsableFolder: Bool { isDirectory && !isPackage }

    static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
        .creationDateKey, .contentAccessDateKey, .tagNamesKey,
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
        self.created = v.creationDate ?? .distantPast
        self.accessed = v.contentAccessDate ?? .distantPast
        self.fileExtension = (isDirectory && !isPackage) ? "" : url.pathExtension.lowercased()
        self.tagList = v.tagNames ?? []
        self.tags = tagList.joined(separator: ", ")
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        self.permissions = Self.permissionString(mode, isDirectory: isDirectory)
        self.owner = attributes[.ownerAccountName] as? String ?? ""
    }

    /// z. B. „drwxr-xr-x (755)“
    private static func permissionString(_ mode: Int, isDirectory: Bool) -> String {
        let symbols = ["r", "w", "x"]
        var text = isDirectory ? "d" : "-"
        for shift in stride(from: 8, through: 0, by: -1) {
            text += mode & (1 << shift) != 0 ? symbols[(8 - shift) % 3] : "-"
        }
        return "\(text) (\(String(mode & 0o777, radix: 8)))"
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
