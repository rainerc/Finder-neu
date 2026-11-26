import SwiftUI
import AppKit

/// Schnelle Ordnervorschau für die Leertaste: Inhalt der obersten Ebene, sofort da.
/// (Quick-Look-Erweiterungen wie XRay durchsuchen den ganzen Baum und brauchen bei großen Ordnern sehr lange.)
struct FolderPreviewSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let url: URL

    @State private var items: [FileItem] = []
    @State private var error: String?
    @State private var folderSize: Int64?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(FileManager.default.displayName(atPath: url.path)).font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Öffnen") {
                    browser.activePane.navigate(to: url)
                    dismiss()
                }
                Button("Quick Look") {
                    dismiss()
                    QuickLookController.shared.show([url])
                }
                .help("Systemvorschau (z. B. XRay) – kann bei großen Ordnern dauern (⌥-Leertaste)")
            }
            .padding(12)
            Divider()
            if let error {
                ContentUnavailableView("Nicht lesbar", systemImage: "lock.fill", description: Text(error))
            } else {
                Table(items) {
                    TableColumn("Name") { item in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(item.name).lineLimit(1)
                            TagDots(tags: item.tagList)
                        }
                    }
                    .width(min: 180, ideal: 300)
                    TableColumn("Geändert") { item in
                        Text(item.modified, format: .dateTime.day().month().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 110, ideal: 140)
                    TableColumn("Größe") { item in
                        Text(item.sizeText).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Art") { item in
                        Text(item.kind).foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 120)
                }
            }
        }
        .frame(width: 720, height: 480)
        .onKeyPress(keys: [.space, .escape]) { _ in
            dismiss()
            return .handled
        }
        .task {
            do {
                let order = KeyPathComparator(\FileItem.name, comparator: .localizedStandard)
                let loaded = try FileService.contents(of: url, includeHidden: browser.activePane.showHidden)
                items = loaded.filter(\.isBrowsableFolder).sorted(using: order)
                    + loaded.filter { !$0.isBrowsableFolder }.sorted(using: order)
            } catch {
                self.error = error.localizedDescription
            }
            folderSize = await FileTransfer.folderSize(of: url)
        }
    }

    private var summary: String {
        let folders = items.filter(\.isBrowsableFolder).count
        var text = "\(items.count) Objekte (\(folders) Ordner)"
        if let folderSize { text += " · \(folderSize.formatted(.byteCount(style: .file))) gesamt" }
        return text
    }
}
