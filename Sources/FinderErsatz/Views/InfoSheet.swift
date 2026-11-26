import SwiftUI
import AppKit

/// „Informationen“ (⌘I): Details zu einem Objekt, inkl. berechneter Ordnergröße und Tags.
struct InfoSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let item: FileItem
    @State private var folderSize: Int64?
    @State private var tags: [String]

    init(item: FileItem) {
        self.item = item
        _tags = State(initialValue: item.tagList)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title3.bold()).lineLimit(2)
                    Text(item.kind).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(FinderTag.allCases) { tag in
                    let active = tag.isContained(in: tags)
                    Button {
                        browser.toggleTag(tag, for: [item])
                        tags = FileItem(url: item.url)?.tagList ?? tags
                    } label: {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 16, height: 16)
                            .overlay {
                                if active {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tag.rawValue)
                }
            }

            Form {
                LabeledContent("Größe", value: sizeText)
                LabeledContent("Ort") {
                    Text(item.url.deletingLastPathComponent().path)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                LabeledContent("Erstellt", value: item.created.formatted(date: .long, time: .shortened))
                LabeledContent("Geändert", value: item.modified.formatted(date: .long, time: .shortened))
                LabeledContent("Zuletzt geöffnet", value: item.accessed.formatted(date: .long, time: .shortened))
                if !item.tags.isEmpty { LabeledContent("Tags", value: tags.joined(separator: ", ")) }
                LabeledContent("Rechte", value: item.permissions)
                LabeledContent("Eigentümer", value: item.owner)
                if !item.isBrowsableFolder, let app = NSWorkspace.shared.urlForApplication(toOpen: item.url) {
                    LabeledContent("Öffnen mit", value: FileManager.default.displayName(atPath: app.path))
                }
            }
            .formStyle(.columns)

            HStack {
                Button("Im Finder-Informationsfenster") {
                    // Finder-Fenster für Dinge, die wir (noch) nicht bearbeiten, z. B. Rechte ändern
                    let script = "tell application \"Finder\" to open information window of (POSIX file \"\(item.url.path)\" as alias)"
                    NSAppleScript(source: script)?.executeAndReturnError(nil)
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            guard item.isDirectory else { return }
            let url = item.url
            folderSize = await Task.detached { FileTransfer.size(of: url) }.value
        }
    }

    private var sizeText: String {
        if item.isDirectory {
            guard let folderSize else { return "Wird berechnet …" }
            return "\(folderSize.formatted(.byteCount(style: .file))) (\(folderSize.formatted()) Byte)"
        }
        return "\(item.size.formatted(.byteCount(style: .file))) (\(item.size.formatted()) Byte)"
    }
}
