import SwiftUI
import AppKit

/// „Verzeichnisse vergleichen“: linkes und rechtes Fenster gegenüberstellen, Unterschiede anzeigen
/// und gezielt in eine Richtung kopieren oder beide Seiten synchronisieren.
struct CompareSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: CompareRequest

    @AppStorage("compare.recursive") private var recursive = false
    @AppStorage("compare.method") private var methodRaw = CompareOptions.Method.dateAndSize.rawValue
    @AppStorage("compare.hidden") private var includeHidden = false
    @AppStorage("compare.showSame") private var showSame = false

    @State private var entries: [CompareEntry] = []
    @State private var isRunning = false
    @State private var runToken = UUID()
    @State private var selection = Set<CompareEntry.ID>()
    @State private var pendingCopy: PendingCopy?

    /// Rückfrage vor dem Kopieren
    struct PendingCopy: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let toRight: [CompareEntry]
        let toLeft: [CompareEntry]
    }

    private var options: CompareOptions {
        CompareOptions(recursive: recursive,
                       method: CompareOptions.Method(rawValue: methodRaw) ?? .dateAndSize,
                       includeHidden: includeHidden)
    }

    private var visibleEntries: [CompareEntry] {
        showSame ? entries : entries.filter { $0.status != .same }
    }

    private var selectedEntries: [CompareEntry] {
        entries.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            optionsRow
            Divider()
            summary
            list
            Divider()
            actions
        }
        .padding(16)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 480, idealHeight: 620)
        .task(id: TaskKey(options: options, token: runToken)) { await run() }
        .confirmationDialog(pendingCopy?.title ?? "", isPresented: Binding(
            get: { pendingCopy != nil }, set: { if !$0 { pendingCopy = nil } }
        ), presenting: pendingCopy) { pending in
            Button("Kopieren") { perform(pending) }
            Button("Abbrechen", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    private struct TaskKey: Equatable {
        let options: CompareOptions
        let token: UUID
    }

    // MARK: Teile

    private var header: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("Links:").foregroundStyle(.secondary)
                Text(RecentFolders.displayPath(request.left)).lineLimit(1).truncationMode(.middle)
            }
            GridRow {
                Text("Rechts:").foregroundStyle(.secondary)
                Text(RecentFolders.displayPath(request.right)).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.callout)
    }

    private var optionsRow: some View {
        HStack(spacing: 14) {
            Picker("Vergleichen nach", selection: $methodRaw) {
                ForEach(CompareOptions.Method.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .fixedSize()
            Toggle("Unterordner einbeziehen", isOn: $recursive)
            Toggle("Unsichtbare Dateien", isOn: $includeHidden)
            Spacer()
            if isRunning {
                ProgressView().controlSize(.small)
            }
            Button("Neu vergleichen", systemImage: "arrow.clockwise") { runToken = UUID() }
                .disabled(isRunning)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ForEach(CompareEntry.Status.allCases, id: \.self) { status in
                let count = entries.filter { $0.status == status }.count
                Label("\(status.title): \(count)", systemImage: status.symbol)
                    .foregroundStyle(count == 0 ? Color.secondary : color(for: status))
            }
            Spacer()
            Toggle("Gleiche anzeigen", isOn: $showSame)
        }
        .font(.callout)
    }

    private var list: some View {
        Table(visibleEntries, selection: $selection) {
            TableColumn("") { entry in
                Image(systemName: entry.status.symbol)
                    .foregroundStyle(color(for: entry.status))
                    .help(entry.status.title)
            }
            .width(24)
            TableColumn("Name") { entry in
                Label {
                    Text(entry.relativePath).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: entry.isDirectory ? "folder" : "doc")
                }
            }
            .width(min: 200, ideal: 320)
            TableColumn("Status") { entry in
                Text(entry.status.title).foregroundStyle(color(for: entry.status))
            }
            .width(min: 90, ideal: 110)
            TableColumn("Links") { entry in sideText(entry.left) }
                .width(min: 150, ideal: 200)
            TableColumn("Rechts") { entry in sideText(entry.right) }
                .width(min: 150, ideal: 200)
        }
        .overlay {
            if !isRunning && visibleEntries.isEmpty {
                ContentUnavailableView(entries.isEmpty ? "Keine Objekte" : "Keine Unterschiede",
                                       systemImage: "checkmark.circle",
                                       description: Text(entries.isEmpty ? "Beide Ordner sind leer." : "Die Ordner stimmen überein."))
            }
        }
        .contextMenu(forSelectionType: CompareEntry.ID.self) { ids in
            let chosen = entries.filter { ids.contains($0.id) }
            Button("Nach rechts kopieren") { askCopy(chosen, toRight: true) }
                .disabled(chosen.allSatisfy { $0.left == nil })
            Button("Nach links kopieren") { askCopy(chosen, toRight: false) }
                .disabled(chosen.allSatisfy { $0.right == nil })
            Divider()
            Button("In den Fenstern zeigen") { reveal(chosen) }
        }
    }

    private var actions: some View {
        HStack {
            Button("Unterschiede in den Fenstern auswählen") {
                browser.markDifferences()
                dismiss()
            }
            .help("Wählt in beiden Fenstern alles aus, was sich unterscheidet (nur die oberste Ebene)")
            Spacer()
            let chosen = selection.isEmpty ? visibleEntries : selectedEntries
            Button("Nach rechts kopieren", systemImage: "arrow.right") { askCopy(chosen, toRight: true) }
                .disabled(isRunning || !chosen.contains { $0.left != nil && $0.status != .same })
                .help(selection.isEmpty ? "Alles, was links vorhanden und rechts fehlt oder anders ist" : "Ausgewählte Zeilen")
            Button("Nach links kopieren", systemImage: "arrow.left") { askCopy(chosen, toRight: false) }
                .disabled(isRunning || !chosen.contains { $0.right != nil && $0.status != .same })
            Button("Synchronisieren …", systemImage: "arrow.left.arrow.right") { askSync(chosen) }
                .disabled(isRunning || !chosen.contains { $0.status.syncDirectionToRight != nil })
                .help("Fehlendes und Neueres jeweils auf die andere Seite kopieren – die neuere Version gewinnt")
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Hilfen

    private func sideText(_ side: CompareEntry.Side?) -> some View {
        Group {
            if let side {
                Text(side.isDirectory ? "Ordner" : side.size.formatted(.byteCount(style: .file)))
                    + Text("  ")
                    + Text(side.modified.formatted(date: .numeric, time: .shortened)).foregroundStyle(.secondary)
            } else {
                Text("–").foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }

    private func color(for status: CompareEntry.Status) -> Color {
        switch status {
        case .leftOnly, .rightOnly: .blue
        case .leftNewer, .rightNewer: .orange
        case .different: .red
        case .same: .secondary
        }
    }

    private func run() async {
        isRunning = true
        let left = request.left, right = request.right, current = options
        let result = await Task.detached(priority: .userInitiated) {
            FolderCompare.compare(left: left, right: right, options: current)
        }.value
        guard !Task.isCancelled else { return }
        entries = result
        selection.formIntersection(Set(result.map(\.id)))
        isRunning = false
    }

    private func askCopy(_ chosen: [CompareEntry], toRight: Bool) {
        let candidates = chosen.filter { $0.status != .same && (toRight ? $0.left : $0.right) != nil }
        guard !candidates.isEmpty else { return }
        let replacing = candidates.filter { (toRight ? $0.right : $0.left) != nil }.count
        let direction = toRight ? "nach rechts" : "nach links"
        var message = "\(candidates.count) Objekt(e) werden \(direction) kopiert."
        if replacing > 0 {
            message += " \(replacing) davon ersetzen ein vorhandenes Objekt – die alte Version kommt in den Papierkorb."
        }
        let older = candidates.filter { $0.status == (toRight ? .rightNewer : .leftNewer) }.count
        if older > 0 {
            message += " Achtung: Bei \(older) Objekt(en) ist die Zielseite neuer."
        }
        pendingCopy = PendingCopy(title: "\(candidates.count) Objekt(e) \(direction) kopieren?", message: message,
                                  toRight: toRight ? candidates : [], toLeft: toRight ? [] : candidates)
    }

    private func askSync(_ chosen: [CompareEntry]) {
        let toRight = chosen.filter { $0.status.syncDirectionToRight == true }
        let toLeft = chosen.filter { $0.status.syncDirectionToRight == false }
        let unclear = chosen.filter { $0.status == .different }.count
        guard !toRight.isEmpty || !toLeft.isEmpty else { return }
        var message = "Nach rechts: \(toRight.count), nach links: \(toLeft.count). Ersetzte Objekte kommen in den Papierkorb."
        if unclear > 0 {
            message += " \(unclear) Objekt(e) mit gleichem Datum, aber anderem Inhalt bleiben unverändert – bitte einzeln entscheiden."
        }
        pendingCopy = PendingCopy(title: "Ordner synchronisieren?", message: message, toRight: toRight, toLeft: toLeft)
    }

    private func perform(_ pending: PendingCopy) {
        if !pending.toRight.isEmpty {
            browser.copyCompared(pending.toRight, toRight: true, leftRoot: request.left, rightRoot: request.right)
        }
        if !pending.toLeft.isEmpty {
            browser.copyCompared(pending.toLeft, toRight: false, leftRoot: request.left, rightRoot: request.right)
        }
        pendingCopy = nil
        // Nach dem Kopieren neu vergleichen (die Aufträge laufen im Hintergrund)
        Task { @MainActor in
            while !browser.operations.jobs.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
            }
            runToken = UUID()
        }
    }

    /// Ausgewählte Objekte in den Fenstern zeigen: jeweils den übergeordneten Ordner öffnen und auswählen.
    private func reveal(_ chosen: [CompareEntry]) {
        if let left = chosen.compactMap(\.left).first {
            let pane = browser.pane(.left)
            pane.navigate(to: left.url.deletingLastPathComponent())
            pane.selection = Set(chosen.compactMap(\.left?.url))
        }
        if let right = chosen.compactMap(\.right).first {
            let pane = browser.pane(.right)
            pane.navigate(to: right.url.deletingLastPathComponent())
            pane.selection = Set(chosen.compactMap(\.right?.url))
        }
        dismiss()
    }
}
