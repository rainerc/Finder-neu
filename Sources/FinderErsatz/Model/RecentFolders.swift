import Foundation
import Observation

/// Zuletzt besuchte Ordner (beide Fenster gemeinsam, neueste zuerst) – wie im Verzeichnis-Menü von Commander One.
@MainActor
@Observable
final class RecentFolders {
    static let shared = RecentFolders()
    static let maxCount = 20

    private(set) var urls: [URL] = []
    private let defaultsKey = "recentFolders"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        urls = paths.map { URL(filePath: $0).normalizedFileURL }
    }

    func record(_ url: URL) {
        let target = url.normalizedFileURL
        // Entpackte Archiv-Kopien (temporär) nicht merken
        guard !ArchiveService.isInsideBrowsedArchive(target) else { return }
        if urls.first == target { return }
        urls.removeAll { $0 == target }
        urls.insert(target, at: 0)
        if urls.count > Self.maxCount { urls.removeLast(urls.count - Self.maxCount) }
        UserDefaults.standard.set(urls.map(\.path), forKey: defaultsKey)
    }

    func clear() {
        urls.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Anzeige wie „Macintosh HD/Users/…“ (Pfad im Benutzerordner mit ~)
    static func displayPath(_ url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}
