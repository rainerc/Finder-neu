import SwiftUI
import AppKit

/// Zwei Dateien zeilenweise nebeneinander vergleichen; Unterschiede farbig, Springen zum nächsten Unterschied.
struct FileCompareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: FileCompareRequest

    @AppStorage("fileCompare.ignoreWhitespace") private var ignoreWhitespace = false
    @AppStorage("fileCompare.ignoreCase") private var ignoreCase = false

    private enum Phase: Sendable {
        case loading
        case text(TextDiff.Result)
        case binary(equal: Bool)
        case message(String)
    }

    @State private var state: Phase = .loading
    @State private var currentBlock = -1

    private struct TaskKey: Equatable {
        let ignoreWhitespace: Bool
        let ignoreCase: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                fileHeader(request.left, side: "Links")
                fileHeader(request.right, side: "Rechts")
            }
            HStack(spacing: 14) {
                Toggle("Leerzeichen ignorieren", isOn: $ignoreWhitespace)
                Toggle("Groß/klein ignorieren", isOn: $ignoreCase)
                Spacer()
                summary
            }
            .font(.callout)
            Divider()
            content
            Divider()
            HStack {
                Button("Links öffnen") { NSWorkspace.shared.open(request.left) }
                Button("Rechts öffnen") { NSWorkspace.shared.open(request.right) }
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 520, idealHeight: 720)
        .task(id: TaskKey(ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase)) { await run() }
    }

    // MARK: Teile

    private func fileHeader(_ url: URL, side: String) -> some View {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(side): \(url.lastPathComponent)").font(.headline).lineLimit(1).truncationMode(.middle)
            Text(RecentFolders.displayPath(url.deletingLastPathComponent()))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Text("\(Int64(values?.fileSize ?? 0).formatted(.byteCount(style: .file))) · \(values?.contentModificationDate?.formatted(date: .numeric, time: .shortened) ?? "–")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var summary: some View {
        switch state {
        case let .text(result) where result.isIdentical:
            Label("Inhalt gleich", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .text(result):
            Text("\(result.changedCount) geändert · \(result.leftOnlyCount) nur links · \(result.rightOnlyCount) nur rechts")
                .foregroundStyle(.secondary)
            Button("Vorheriger Unterschied", systemImage: "chevron.up") { jump(-1, in: result) }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(result.blockStarts.isEmpty)
            Button("Nächster Unterschied", systemImage: "chevron.down") { jump(1, in: result) }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(result.blockStarts.isEmpty)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView("Vergleiche …").frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .message(text):
            ContentUnavailableView("Kein Textvergleich möglich", systemImage: "doc.questionmark", description: Text(text))
        case let .binary(equal):
            ContentUnavailableView(equal ? "Dateien sind gleich" : "Dateien unterscheiden sich",
                                   systemImage: equal ? "checkmark.circle" : "xmark.circle",
                                   description: Text("Mindestens eine Datei ist keine Textdatei – Byte für Byte verglichen."))
        case let .text(result):
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(result.rows) { row in
                            DiffRowView(row: row, highlighted: currentBlockRow(result) == row.id)
                                .id(row.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: currentBlock) { _, block in
                    guard block >= 0, block < result.blockStarts.count else { return }
                    withAnimation { proxy.scrollTo(result.blockStarts[block], anchor: .center) }
                }
            }
        }
    }

    // MARK: Logik

    private func currentBlockRow(_ result: TextDiff.Result) -> Int? {
        currentBlock >= 0 && currentBlock < result.blockStarts.count ? result.blockStarts[currentBlock] : nil
    }

    private func jump(_ step: Int, in result: TextDiff.Result) {
        guard !result.blockStarts.isEmpty else { return }
        let count = result.blockStarts.count
        currentBlock = currentBlock < 0 ? (step > 0 ? 0 : count - 1) : (currentBlock + step + count) % count
    }

    private func run() async {
        state = .loading
        currentBlock = -1
        let left = request.left, right = request.right
        let whitespace = ignoreWhitespace, caseInsensitive = ignoreCase
        let newState: Phase = await Task.detached(priority: .userInitiated) { () -> Phase in
            switch (TextDiff.load(left), TextDiff.load(right)) {
            case let (.text(a), .text(b)):
                return .text(TextDiff.compare(a, b, ignoreWhitespace: whitespace, ignoreCase: caseInsensitive))
            case (.failed(let error), _), (_, .failed(let error)):
                return .message(error)
            case (.tooLarge, _), (_, .tooLarge):
                let equal = (try? Data(contentsOf: left, options: .mappedIfSafe)) == (try? Data(contentsOf: right, options: .mappedIfSafe))
                return .binary(equal: equal)
            default:
                let equal = (try? Data(contentsOf: left, options: .mappedIfSafe)) == (try? Data(contentsOf: right, options: .mappedIfSafe))
                return .binary(equal: equal)
            }
        }.value
        guard !Task.isCancelled else { return }
        state = newState
        if case let .text(result) = newState, !result.blockStarts.isEmpty { currentBlock = 0 }
    }
}

/// Eine Zeile der Nebeneinander-Ansicht
private struct DiffRowView: View {
    let row: TextDiff.Row
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 0) {
            half(number: row.leftNumber, text: row.left, color: leftColor)
            Divider()
            half(number: row.rightNumber, text: row.right, color: rightColor)
        }
        .font(.system(.callout, design: .monospaced))
        .overlay(alignment: .leading) {
            if highlighted { Rectangle().fill(Color.accentColor).frame(width: 3) }
        }
    }

    private var leftColor: Color {
        switch row.kind {
        case .same: .clear
        case .changed: .orange.opacity(0.18)
        case .leftOnly: .red.opacity(0.16)
        case .rightOnly: .gray.opacity(0.08)
        }
    }

    private var rightColor: Color {
        switch row.kind {
        case .same: .clear
        case .changed: .orange.opacity(0.18)
        case .leftOnly: .gray.opacity(0.08)
        case .rightOnly: .green.opacity(0.18)
        }
    }

    private func half(number: Int?, text: String?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .trailing)
            Text(text ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        .background(color)
    }
}
