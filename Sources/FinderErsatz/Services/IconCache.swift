import AppKit

/// Zwischenspeicher für Datei-Symbole. `NSWorkspace.icon(forFile:)` ist spürbar langsam und wurde bei jeder
/// Auswahländerung für alle sichtbaren Zeilen erneut aufgerufen – das machte das Durchklicken träge.
@MainActor
enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 5000
        return cache
    }()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Nach Änderungen am Objekt (z. B. eigenes Ordnersymbol) neu laden lassen.
    static func invalidate(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}
