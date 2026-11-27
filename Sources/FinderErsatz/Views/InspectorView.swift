import SwiftUI
import AppKit
import Quartz
import CoreServices

/// Vorschau-Spalte rechts (⇧⌘P) wie im Finder: echte Quick-Look-Vorschau und Metadaten
/// des ausgewählten Objekts im aktiven Fenster (ohne Auswahl: der aktuelle Ordner).
struct InspectorView: View {
    @Environment(BrowserState.self) private var browser

    private var item: FileItem? {
        let pane = browser.activePane
        return pane.selectedItems.first ?? FileItem(url: pane.currentURL)
    }

    var body: some View {
        if let item {
            InspectorContent(item: item, selectionCount: browser.activePane.selectedItems.count)
                .id(item.url)
        } else {
            ContentUnavailableView("Keine Vorschau", systemImage: "eye.slash")
        }
    }
}

private struct InspectorContent: View {
    @Environment(BrowserState.self) private var browser
    let item: FileItem
    let selectionCount: Int

    @State private var folderSize: Int64?
    @State private var folderSizeSkipped = false
    @State private var metadata: [SpotlightMetadata.Entry] = []

    var body: some View {
        VStack(spacing: 0) {
            DeferredQuickLook(item: item)
                .frame(minHeight: 180, idealHeight: 260, maxHeight: 360)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline).lineLimit(3).textSelection(.enabled)
                        Text(item.kind + (selectionCount > 1 ? " – \(selectionCount) Objekte ausgewählt" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.tagList.isEmpty {
                        HStack(spacing: 4) {
                            TagDots(tags: item.tagList)
                            Text(item.tags).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 5) {
                        row("Größe", sizeText)
                        row("Ort", item.url.deletingLastPathComponent().path)
                        row("Erstellt", item.created.formatted(date: .abbreviated, time: .shortened))
                        row("Geändert", item.modified.formatted(date: .abbreviated, time: .shortened))
                        if item.accessed > .distantPast {
                            row("Geöffnet", item.accessed.formatted(date: .abbreviated, time: .shortened))
                        }
                        ForEach(metadata) { entry in
                            row(entry.label, entry.value)
                        }
                        row("Rechte", item.permissions)
                    }
                    .font(.caption)
                    HStack {
                        Button("Öffnen") { NSWorkspace.shared.open(item.url) }
                        Button("Informationen") { browser.infoItem = item }
                        Button("Im Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            // Erst laden, wenn die Auswahl kurz stehen bleibt – beim Durchklicken nicht jedes Objekt auswerten.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            metadata = SpotlightMetadata.entries(for: item.url)
            guard item.isBrowsableFolder else { return }
            folderSize = await FileTransfer.folderSize(of: item.url)
            folderSizeSkipped = folderSize == nil && !Task.isCancelled
        }
    }

    private var sizeText: String {
        guard item.isBrowsableFolder else { return item.size.formatted(.byteCount(style: .file)) }
        if folderSizeSkipped { return "– (Netzlaufwerk, siehe ⌘I)" }
        guard let folderSize else { return "Wird berechnet …" }
        return folderSize.formatted(.byteCount(style: .file))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(4)
        }
    }
}

/// Zusätzliche Angaben aus Spotlight (Abmessungen, Dauer, Herkunft …), soweit vorhanden.
enum SpotlightMetadata {
    struct Entry: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    static func entries(for url: URL) -> [Entry] {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return [] }
        func value(_ key: CFString) -> Any? { MDItemCopyAttribute(item, key) }
        var result: [Entry] = []
        if let width = value(kMDItemPixelWidth) as? NSNumber, let height = value(kMDItemPixelHeight) as? NSNumber {
            result.append(Entry(label: "Abmessungen", value: "\(width.intValue) × \(height.intValue)"))
        }
        if let duration = value(kMDItemDurationSeconds) as? NSNumber {
            let seconds = Duration.seconds(duration.doubleValue)
            result.append(Entry(label: "Dauer", value: seconds.formatted(.time(pattern: duration.doubleValue >= 3600 ? .hourMinuteSecond : .minuteSecond))))
        }
        if let pages = value(kMDItemNumberOfPages) as? NSNumber {
            result.append(Entry(label: "Seiten", value: pages.stringValue))
        }
        if let authors = value(kMDItemAuthors) as? [String], !authors.isEmpty {
            result.append(Entry(label: "Autor", value: authors.joined(separator: ", ")))
        }
        if let make = value(kMDItemAcquisitionModel) as? String {
            result.append(Entry(label: "Kamera", value: make))
        }
        if let version = value(kMDItemVersion) as? String {
            result.append(Entry(label: "Version", value: version))
        }
        if let origins = value(kMDItemWhereFroms) as? [String], let first = origins.first {
            result.append(Entry(label: "Herkunft", value: first))
        }
        if let used = value(kMDItemLastUsedDate) as? Date {
            result.append(Entry(label: "Zuletzt benutzt", value: used.formatted(date: .abbreviated, time: .shortened)))
        }
        return result
    }
}

/// Quick-Look-Vorschau, die erst startet, wenn die Auswahl kurz stehen bleibt. Bei Ordnern nur das Symbol:
/// Quick Look würde dort XRay starten, das den ganzen Ordnerbaum durchsucht (sehr träge).
struct DeferredQuickLook: View {
    @Environment(BrowserState.self) private var browser
    let item: FileItem
    @State private var ready = false

    var body: some View {
        Group {
            if ready, !item.isBrowsableFolder || browser.settings.folderPreviewUsesQuickLook {
                QuickLookPreview(url: item.url)
            } else {
                Image(nsImage: IconCache.icon(for: item.url))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 128, maxHeight: 128)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.url) {
            ready = false
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { ready = true }
        }
    }
}

/// Echte Quick-Look-Vorschau (blättern in PDFs, Videos abspielen usw.).
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = false
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if view.previewItem?.previewItemURL != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

/// Vorschaubereich unten in einem Dateifenster: links die Quick-Look-Vorschau, rechts die wichtigsten Angaben.
struct PanePreview: View {
    let pane: PaneState

    var body: some View {
        let selected = pane.selectedItems
        // ZStack statt Group: Eine Group mit if/else reicht ihre wechselnden Kinder direkt an die VSplitView
        // weiter. Die baut dann beim Auswählen ihre Bereiche neu auf, und die Dateiliste springt nach oben.
        ZStack {
            if let item = selected.last {
                PanePreviewContent(item: item, selectionCount: selected.count)
                    .id(item.url)
            } else {
                Text(pane.items.isEmpty ? "Keine Objekte" : "Objekt auswählen, um es hier anzuzeigen")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct PanePreviewContent: View {
    let item: FileItem
    let selectionCount: Int
    @State private var metadata: [SpotlightMetadata.Entry] = []
    @State private var folderSize: Int64?
    @State private var folderSizeSkipped = false

    var body: some View {
        HStack(spacing: 0) {
            DeferredQuickLook(item: item)
                .frame(minWidth: 160, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.headline).lineLimit(2).textSelection(.enabled)
                    Text(item.kind + (selectionCount > 1 ? " – \(selectionCount) ausgewählt" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 3) {
                        GridRow {
                            Text("Größe").foregroundStyle(.secondary)
                            Text(sizeText)
                        }
                        GridRow {
                            Text("Geändert").foregroundStyle(.secondary)
                            Text(item.modified.formatted(date: .abbreviated, time: .shortened))
                        }
                        GridRow {
                            Text("Erstellt").foregroundStyle(.secondary)
                            Text(item.created.formatted(date: .abbreviated, time: .shortened))
                        }
                        ForEach(metadata) { entry in
                            GridRow {
                                Text(entry.label).foregroundStyle(.secondary)
                                Text(entry.value).lineLimit(2).textSelection(.enabled)
                            }
                        }
                    }
                    .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 240)
        }
        .task {
            // Erst laden, wenn die Auswahl kurz stehen bleibt – beim Durchklicken nicht jedes Objekt auswerten.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            metadata = SpotlightMetadata.entries(for: item.url)
            guard item.isBrowsableFolder else { return }
            folderSize = await FileTransfer.folderSize(of: item.url)
            folderSizeSkipped = folderSize == nil && !Task.isCancelled
        }
    }

    private var sizeText: String {
        guard item.isBrowsableFolder else { return item.size.formatted(.byteCount(style: .file)) }
        if folderSizeSkipped { return "– (Netzlaufwerk, siehe ⌘I)" }
        return folderSize.map { $0.formatted(.byteCount(style: .file)) } ?? "Wird berechnet …"
    }
}
