import SwiftUI
import AppKit

/// Sammelablage unter den Fenstern: Dateien hineinziehen (oder ⌃⌘J), später gesammelt ins aktive Fenster
/// kopieren/verschieben oder per Griff alle zusammen in eine andere App ziehen.
struct DropStackBar: View {
    @Environment(BrowserState.self) private var browser
    private var stack: DropStack { DropStack.shared }
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Image(systemName: "tray.full")
                    .font(.title3)
                Text("Sammelablage").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 64)
            .help("Dateien hier sammeln: hineinziehen oder auswählen und ⌃⌘J")

            if stack.items.isEmpty {
                Text("Dateien hierher ziehen oder auswählen und ⌃⌘J drücken. Sie bleiben an ihrem Ort, bis du sie gesammelt kopierst, verschiebst oder herausziehst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(stack.items, id: \.self) { url in
                            DropStackChip(url: url, isSelected: stack.selection.contains(url))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity)

                // Griff: alle (bzw. die ausgewählten) zusammen herausziehen
                MultiFileDragHandle(urls: { stack.chosen })
                    .frame(width: 30, height: 30)
                    .help("Ziehen: \(stack.selection.isEmpty ? "alle" : "die ausgewählten") Dateien zusammen herausziehen (z. B. in Mail oder den Finder)")

                Button(stack.selection.count == stack.items.count ? "Keine" : "Alle", systemImage: "checkmark.circle") {
                    if stack.selection.count == stack.items.count { stack.selection.removeAll() } else { stack.selectAll() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Alle Einträge auswählen bzw. Auswahl aufheben")
                VStack(alignment: .leading, spacing: 2) {
                    Button("Hierher kopieren", systemImage: "doc.on.doc") { browser.transferDropStack(move: false) }
                    Button("Hierher verschieben", systemImage: "arrow.right.doc.on.clipboard") { browser.transferDropStack(move: true) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("In den Ordner des aktiven Fensters (\(browser.activePane.title)) – ohne Auswahl alle Einträge")
                Menu {
                    Button("Alle auswählen") { stack.selection = Set(stack.items) }
                    Button("Auswahl aufheben") { stack.selection.removeAll() }
                    Divider()
                    Button("Ausgewählte entfernen") { stack.remove(Array(stack.selection)) }
                        .disabled(stack.selection.isEmpty)
                    Button("Nicht mehr vorhandene entfernen") { stack.prune() }
                    Button("Sammelablage leeren") { stack.clear() }
                    Divider()
                    Button("Sammelablage ausblenden") { browser.settings.showDropStack = false }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 54)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            stack.add(files)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Ein Eintrag: Symbol + Name; Klick wählt aus (⌘ für mehrere), Doppelklick zeigt im aktiven Fenster, einzeln herausziehbar
private struct DropStackChip: View {
    @Environment(BrowserState.self) private var browser
    let url: URL
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .frame(width: 20, height: 20)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6))
        .help(url.path)
        .contentShape(Rectangle())
        // Nur ein Tap-Erkenner: ein zusätzlicher Doppelklick-Erkenner lässt SwiftUI jeden Einzelklick verzögern
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                browser.revealDropStackItem(url)
            } else {
                DropStack.shared.click(url, modifiers: NSEvent.modifierFlags)
            }
        }
        .draggable(url)
        .contextMenu {
            Button("Im aktiven Fenster zeigen") { browser.revealDropStackItem(url) }
            Button("Öffnen") { NSWorkspace.shared.open(url) }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Aus der Sammelablage entfernen") { DropStack.shared.remove([url]) }
        }
    }
}

/// Zieh-Griff für mehrere Dateien auf einmal (SwiftUIs `.draggable` kann nur ein Objekt)
struct MultiFileDragHandle: NSViewRepresentable {
    let urls: () -> [URL]

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.urls = urls
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.urls = urls
    }

    final class HandleView: NSView, NSDraggingSource {
        var urls: (() -> [URL])?
        private let imageView = NSImageView()

        override init(frame: NSRect) {
            super.init(frame: frame)
            imageView.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Alle ziehen")
            imageView.symbolConfiguration = .init(pointSize: 18, weight: .regular)
            imageView.contentTintColor = .secondaryLabelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

        override func mouseDragged(with event: NSEvent) {
            guard let files = urls?(), !files.isEmpty else { return }
            let location = convert(event.locationInWindow, from: nil)
            let items: [NSDraggingItem] = files.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let offset = CGFloat(min(index, 5)) * 4
                item.setDraggingFrame(NSRect(x: location.x - 16 + offset, y: location.y - 16 - offset, width: 32, height: 32),
                                      contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        nonisolated func draggingSession(_ session: NSDraggingSession,
                                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .move, .link, .generic]
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
