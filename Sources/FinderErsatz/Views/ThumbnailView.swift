import SwiftUI
import AppKit
@preconcurrency import QuickLookThumbnailing

/// Zwischenspeicher für Vorschaubilder (Pfad + Änderungsdatum + Größe).
@MainActor
enum ThumbnailCache {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 1000
        return cache
    }()

    static func key(_ item: FileItem, size: CGFloat) -> NSString {
        "\(item.url.path)|\(item.modified.timeIntervalSince1970)|\(Int(size))" as NSString
    }
}

/// Vorschaubild über Quick Look; bis es geladen ist (oder ohne Vorschau) das Dateisymbol.
struct ThumbnailView: View {
    let item: FileItem
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? IconCache.icon(for: item.url))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: ThumbnailCache.key(item, size: size)) { await load() }
    }

    private struct Result: @unchecked Sendable { let image: CGImage? }

    private func load() async {
        let key = ThumbnailCache.key(item, size: size)
        if let cached = ThumbnailCache.cache.object(forKey: key) {
            image = cached
            return
        }
        guard !item.isBrowsableFolder else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail
        )
        let result: Result = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: Result(image: representation?.cgImage))
            }
        }
        guard let cgImage = result.image, !Task.isCancelled else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        ThumbnailCache.cache.setObject(nsImage, forKey: key)
        image = nsImage
    }
}
