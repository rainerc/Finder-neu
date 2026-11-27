import SwiftUI
import AppKit

/// Überschreiben-Dialog wie im Total Commander: je Konflikt Vorschau, Größe und Datum beider Dateien,
/// Entscheidung pro Zeile oder für alle (auch „nur ältere ersetzen“).
struct ConflictSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: ConflictRequest

    @State private var choices: [URL: ConflictResolution] = [:]
    @State private var fileCompare: FileCompareRequest?

    /// Nur die Objekte, deren Ziel schon existiert
    private var conflicts: [Conflict] {
        request.items.compactMap { item in
            guard FileManager.default.fileExists(atPath: item.destination.path) else { return nil }
            return Conflict(item: item)
        }
    }

    struct Conflict: Identifiable {
        let item: TransferItem
        let source: Info
        let target: Info
        var id: URL { item.destination }

        struct Info {
            let fileItem: FileItem?
            let size: Int64
            let modified: Date
            let isDirectory: Bool
        }

        init(item: TransferItem) {
            self.item = item
            source = Self.info(item.source)
            target = Self.info(item.destination)
        }

        private static func info(_ url: URL) -> Info {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            return Info(fileItem: FileItem(url: url), size: Int64(values?.fileSize ?? 0),
                        modified: values?.contentModificationDate ?? .distantPast,
                        isDirectory: values?.isDirectory ?? false)
        }

        /// Ist die vorhandene Datei älter als die neue (mit 2 s Spielraum)?
        var targetIsOlder: Bool { target.modified.addingTimeInterval(2) < source.modified }
        var targetIsNewer: Bool { source.modified.addingTimeInterval(2) < target.modified }
        var sameDate: Bool { abs(target.modified.timeIntervalSince(source.modified)) <= 2 }
    }

    var body: some View {
        let conflicts = conflicts
        VStack(alignment: .leading, spacing: 12) {
            Text(conflicts.count == 1 ? "„\(conflicts[0].item.destination.lastPathComponent)“ ist im Ziel bereits vorhanden"
                                      : "\(conflicts.count) Objekte sind im Ziel bereits vorhanden")
                .font(.headline)
            Text(request.title).font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Für alle:").foregroundStyle(.secondary)
                Button("Ersetzen") { setAll(conflicts) { _ in .replace } }
                Button("Nur ältere ersetzen") { setAll(conflicts) { $0.targetIsOlder ? .replace : .skip } }
                    .help("Ersetzt nur, wenn die vorhandene Datei älter ist als die neue – sonst überspringen")
                Button("Außer neuere") { setAll(conflicts) { $0.targetIsNewer ? .skip : .replace } }
                    .help("Ersetzt alles, nur wenn die vorhandene Datei neuer ist, wird sie behalten")
                Button("Überspringen") { setAll(conflicts) { _ in .skip } }
                Button("Beide behalten") { setAll(conflicts) { _ in .keepBoth } }
            }
            .controlSize(.small)

            List(conflicts) { conflict in
                row(conflict)
            }
            .frame(minHeight: 160)

            HStack {
                Text(summary(conflicts)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen", role: .cancel) {
                    browser.conflictRequest = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Fortfahren") {
                    let current = choices
                    browser.resolveConflicts { current[$0.destination] ?? .skip }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 360, idealHeight: CGFloat(min(260 + conflicts.count * 72, 680)))
        .onAppear {
            // Vorgabe: ersetzen – nur wenn die vorhandene Datei neuer ist, überspringen
            setAll(conflicts) { $0.targetIsNewer ? .skip : .replace }
        }
        .sheet(item: $fileCompare) { request in FileCompareSheet(request: request) }
    }

    // MARK: Zeile

    private func row(_ conflict: Conflict) -> some View {
        HStack(alignment: .center, spacing: 12) {
            side(conflict.source, title: "Neu", url: conflict.item.source,
                 badge: conflict.sameDate ? nil : (conflict.targetIsOlder ? "neuer" : "älter"),
                 badgeColor: conflict.targetIsOlder ? .green : .orange)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            side(conflict.target, title: "Vorhanden", url: conflict.item.destination,
                 badge: conflict.sameDate ? (conflict.source.size == conflict.target.size ? "gleich" : "gleiches Datum") : nil,
                 badgeColor: .secondary)
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { choices[conflict.id] ?? .skip },
                set: { choices[conflict.id] = $0 }
            )) {
                Text("Ersetzen").tag(ConflictResolution.replace)
                Text("Überspringen").tag(ConflictResolution.skip)
                Text("Beide behalten").tag(ConflictResolution.keepBoth)
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !conflict.source.isDirectory && !conflict.target.isDirectory {
                Button("Inhalt vergleichen …") {
                    fileCompare = FileCompareRequest(left: conflict.item.source, right: conflict.item.destination)
                }
            }
            Button("Neue Datei öffnen") { NSWorkspace.shared.open(conflict.item.source) }
            Button("Vorhandene Datei öffnen") { NSWorkspace.shared.open(conflict.item.destination) }
        }
    }

    private func side(_ info: Conflict.Info, title: String, url: URL, badge: String?, badgeColor: Color) -> some View {
        HStack(spacing: 8) {
            if let fileItem = info.fileItem {
                ThumbnailView(item: fileItem, size: 48)
            } else {
                Image(nsImage: IconCache.icon(for: url)).resizable().frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .background(badgeColor.opacity(0.2), in: Capsule())
                    }
                }
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(info.isDirectory ? "Ordner" : info.size.formatted(.byteCount(style: .file)))
                    .font(.caption).foregroundStyle(.secondary)
                Text(info.modified.formatted(date: .numeric, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 190, alignment: .leading)
        }
    }

    // MARK: Logik

    private func setAll(_ conflicts: [Conflict], _ decide: (Conflict) -> ConflictResolution) {
        var result: [URL: ConflictResolution] = [:]
        for conflict in conflicts { result[conflict.id] = decide(conflict) }
        choices = result
    }

    private func summary(_ conflicts: [Conflict]) -> String {
        let replace = conflicts.filter { choices[$0.id] == .replace }.count
        let keep = conflicts.filter { choices[$0.id] == .keepBoth }.count
        let skip = conflicts.count - replace - keep
        let others = request.items.count - conflicts.count
        var parts = ["\(replace) ersetzen", "\(skip) überspringen", "\(keep) beide behalten"]
        if others > 0 { parts.append("\(others) ohne Konflikt") }
        return parts.joined(separator: " · ") + ". Ersetzte Objekte kommen in den Papierkorb."
    }
}
