import SwiftUI
import AppKit

/// Betrachter (⇧F3) wie Lister im Total Commander: Text mit Kodierung, Umbruch und Suche (⌘F)
/// oder Hex-Ansicht (Offset | 16 Bytes | ASCII), die auch sehr große Dateien seitenweise liest.
struct ViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ViewerRequest

    enum Mode: String { case text, hex }

    @State private var mode: Mode = .text
    @AppStorage("viewer.wrap") private var wraps = true
    @AppStorage("viewer.fontSize") private var fontSize = 12.0
    @State private var encodingIndex = 0
    @State private var data: Data?
    @State private var text = ""
    @State private var textID = UUID()
    @State private var fileSize: Int64 = 0
    @State private var loadError: String?
    @State private var hexReader: HexReader?
    @State private var gotoOffset = ""
    @State private var hexScrollTarget: Int?

    /// Text wird höchstens bis zu dieser Größe geladen (größere Dateien: Anfang + Hinweis, Hex zeigt alles)
    private static let textLimit = 16 * 1024 * 1024

    private static let encodings: [(String, String.Encoding)] = [
        ("UTF-8", .utf8), ("ISO Latin 1", .isoLatin1), ("Windows-1252", .windowsCP1252),
        ("Mac OS Roman", .macOSRoman), ("UTF-16", .utf16),
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                if let loadError {
                    ContentUnavailableView("Datei nicht lesbar", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if mode == .text {
                    ViewerTextView(text: text, textID: textID, wraps: wraps, fontSize: fontSize)
                } else if let hexReader {
                    HexTableView(reader: hexReader, fontSize: fontSize, scrollTarget: $hexScrollTarget)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 480, idealHeight: 720)
        .task { await load() }
        .onChange(of: encodingIndex) { decode() }
    }

    // MARK: Leisten

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: request.url)).resizable().frame(width: 20, height: 20)
            Text(request.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
            Spacer()
            Picker("Ansicht", selection: $mode) {
                Text("Text").tag(Mode.text)
                Text("Hex").tag(Mode.hex)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if mode == .text {
                Picker("Kodierung", selection: $encodingIndex) {
                    ForEach(Self.encodings.indices, id: \.self) { Text(Self.encodings[$0].0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle("Umbruch", isOn: $wraps)
                    .toggleStyle(.checkbox)
            } else {
                TextField("Offset", text: $gotoOffset, prompt: Text("Offset (hex)"))
                    .frame(width: 110)
                    .onSubmit { jumpToOffset() }
            }
            Button("Kleiner", systemImage: "textformat.size.smaller") { fontSize = max(8, fontSize - 1) }
                .labelStyle(.iconOnly)
            Button("Größer", systemImage: "textformat.size.larger") { fontSize = min(32, fontSize + 1) }
                .labelStyle(.iconOnly)
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    private var statusBar: some View {
        HStack {
            Text(fileSize.formatted(.byteCount(style: .file)) + " (\(fileSize.formatted()) Byte)")
            if mode == .text, fileSize > Int64(Self.textLimit) {
                Text("· Text zeigt die ersten \(Int64(Self.textLimit).formatted(.byteCount(style: .file))) – Hex zeigt alles")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if mode == .text { Text("⌘F sucht im Text").foregroundStyle(.secondary) }
            Button("Mit Standard-App öffnen") { NSWorkspace.shared.open(request.url) }
                .buttonStyle(.link)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: Laden

    private func load() async {
        let url = request.url
        let limit = Self.textLimit
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(Data, Int64), Error> in
            Result {
                let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: limit) ?? Data()
                return (data, size)
            }
        }.value
        switch result {
        case .success(let (loaded, size)):
            data = loaded
            fileSize = size
            hexReader = try? HexReader(url: url, size: size)
            // Binärdatei (NUL-Bytes am Anfang)? Dann gleich Hex zeigen.
            if loaded.prefix(8192).contains(0) {
                mode = .hex
                if loaded.count >= 2, loaded[loaded.startIndex] == 0xFF || loaded[loaded.startIndex] == 0xFE {
                    encodingIndex = 4   // UTF-16 mit BOM
                    mode = .text
                }
            }
            decode()
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private func decode() {
        guard let data else { return }
        let encoding = Self.encodings[encodingIndex].1
        if let decoded = String(data: data, encoding: encoding) {
            text = decoded
        } else if encoding == .utf8, let decoded = String(data: data, encoding: .windowsCP1252) {
            // Kein gültiges UTF-8 (oder bei der Grenze abgeschnitten) → Windows-1252
            text = decoded
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        textID = UUID()
    }

    private func jumpToOffset() {
        let cleaned = gotoOffset.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "0x", with: "")
        guard let offset = Int(cleaned, radix: 16) else { NSSound.beep(); return }
        hexScrollTarget = offset / HexReader.bytesPerRow
    }
}

// MARK: - Text

/// Nur lesbares NSTextView mit Suchleiste (⌘F) und umschaltbarem Zeilenumbruch.
struct ViewerTextView: NSViewRepresentable {
    let text: String
    let textID: UUID
    let wraps: Bool
    let fontSize: Double

    final class Coordinator {
        var textID: UUID?
        var wraps: Bool?
        var fontSize: Double?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.isRichText = false
            textView.textContainerInset = NSSize(width: 6, height: 6)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        if coordinator.fontSize != fontSize {
            coordinator.fontSize = fontSize
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if coordinator.textID != textID {
            coordinator.textID = textID
            textView.string = text
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.scroll(.zero)
        }
        if coordinator.wraps != wraps {
            coordinator.wraps = wraps
            let huge = CGFloat.greatestFiniteMagnitude
            if wraps {
                scrollView.hasHorizontalScroller = false
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
                textView.textContainer?.widthTracksTextView = true
                textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: huge)
                textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: textView.frame.height))
            } else {
                scrollView.hasHorizontalScroller = true
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = []
                textView.maxSize = NSSize(width: huge, height: huge)
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(width: huge, height: huge)
            }
        }
    }
}

// MARK: - Hex

/// Liest eine Datei seitenweise (64 KB, kleiner Zwischenspeicher) für die Hex-Ansicht.
@MainActor
final class HexReader {
    static let bytesPerRow = 16
    private static let pageSize = 64 * 1024

    let size: Int64
    private let handle: FileHandle
    private var pages: [Int: Data] = [:]
    private var pageOrder: [Int] = []

    init(url: URL, size: Int64) throws {
        self.handle = try FileHandle(forReadingFrom: url)
        self.size = size
    }

    var rowCount: Int { Int((size + Int64(Self.bytesPerRow) - 1) / Int64(Self.bytesPerRow)) }

    private func page(_ index: Int) -> Data {
        if let cached = pages[index] { return cached }
        let data: Data
        do {
            try handle.seek(toOffset: UInt64(index * Self.pageSize))
            data = try handle.read(upToCount: Self.pageSize) ?? Data()
        } catch {
            data = Data()
        }
        pages[index] = data
        pageOrder.append(index)
        if pageOrder.count > 64 { pages[pageOrder.removeFirst()] = nil }
        return data
    }

    /// Bytes einer Zeile (bis zu 16)
    func bytes(row: Int) -> [UInt8] {
        let offset = row * Self.bytesPerRow
        let pageIndex = offset / Self.pageSize
        let data = page(pageIndex)
        let start = offset - pageIndex * Self.pageSize
        guard start < data.count else { return [] }
        let end = min(start + Self.bytesPerRow, data.count)
        return Array(data[(data.startIndex + start)..<(data.startIndex + end)])
    }

    /// „0000001f0  48 65 6c 6c 6f 20 57 6f  72 6c 64 0a 00 00 00 00  |Hello World.....|“
    func line(row: Int) -> String {
        let bytes = bytes(row: row)
        var hex = ""
        for index in 0..<Self.bytesPerRow {
            if index == 8 { hex += " " }
            hex += index < bytes.count ? String(format: "%02x ", bytes[index]) : "   "
        }
        let ascii = String(bytes.map { (0x20..<0x7F).contains($0) ? Character(UnicodeScalar($0)) : "." })
        return String(format: "%08llx  ", Int64(row * Self.bytesPerRow)) + hex + " |" + ascii + "|"
    }
}

/// Hex-Ansicht als NSTableView: nur sichtbare Zeilen werden gelesen und gezeichnet.
struct HexTableView: NSViewRepresentable {
    let reader: HexReader
    let fontSize: Double
    @Binding var scrollTarget: Int?

    func makeCoordinator() -> Coordinator { Coordinator(reader: reader) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hex"))
        column.title = "Offset    00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  ASCII"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.allowsMultipleSelection = true
        context.coordinator.tableView = tableView
        context.coordinator.apply(fontSize: fontSize)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.apply(fontSize: fontSize)
        if let row = scrollTarget, let tableView = context.coordinator.tableView {
            let target = min(max(row, 0), max(reader.rowCount - 1, 0))
            tableView.scrollRowToVisible(target)
            tableView.selectRowIndexes([target], byExtendingSelection: false)
            Task { @MainActor in scrollTarget = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let reader: HexReader
        weak var tableView: NSTableView?
        private var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        private var fontSize: Double = 0

        init(reader: HexReader) { self.reader = reader }

        func apply(fontSize: Double) {
            guard fontSize != self.fontSize, let tableView else { return }
            self.fontSize = fontSize
            font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            tableView.rowHeight = ceil(fontSize * 1.45)
            // Breite einer vollen Zeile (78 Zeichen)
            let width = ("0" as NSString).size(withAttributes: [.font: font]).width * 80 + 16
            tableView.tableColumns.first?.width = width
            tableView.tableColumns.first?.minWidth = width
            tableView.reloadData()
        }

        func numberOfRows(in tableView: NSTableView) -> Int { reader.rowCount }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("hexCell")
            let field: NSTextField
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
                field = reused
            } else {
                field = NSTextField(labelWithString: "")
                field.identifier = identifier
                field.lineBreakMode = .byClipping
            }
            field.font = font
            field.stringValue = reader.line(row: row)
            return field
        }
    }
}
