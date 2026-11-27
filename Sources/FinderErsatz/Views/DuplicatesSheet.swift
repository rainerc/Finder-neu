import SwiftUI
import AppKit

/// „Doppelte Dateien suchen“: Gruppen gleicher Dateien anzeigen, überzählige markieren und in den Papierkorb legen.
struct DuplicatesSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let request: DuplicatesRequest

    @AppStorage("duplicates.method") private var methodRaw = DuplicateOptions.Method.content.rawValue
    @AppStorage("duplicates.minSize") private var minSize = 1
    @AppStorage("duplicates.hidden") private var includeHidden = false

    @State private var groups: [DuplicateGroup] = []
    @State private var scanned = 0
    @State private var isRunning = false
    @State private var runToken = UUID()
    @State private var marked = Set<URL>()
    @State private var confirmTrash = false
    @State private var useBothFolders = true

    private var options: DuplicateOptions {
        DuplicateOptions(method: DuplicateOptions.Method(rawValue: methodRaw) ?? .content,
                         minSize: Int64(minSize), includeHidden: includeHidden)
    }

    private var folders: [URL] {
        useBothFolders ? request.folders : Array(request.folders.prefix(1))
    }

    private struct TaskKey: Equatable {
        let options: DuplicateOptions
        let folders: [URL]
        let token: UUID
    }

    private var markedSize: Int64 {
        groups.flatMap(\.files).filter { marked.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(request.folders, id: \.self) { folder in
                    Text(RecentFolders.displayPath(folder)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(folders.contains(folder) ? .primary : .tertiary)
                }
            }
            .font(.callout)
            HStack(spacing: 14) {
                Picker("Gleich bedeutet", selection: $methodRaw) {
                    ForEach(DuplicateOptions.Method.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .fixedSize()
                Picker("Mindestgröße", selection: $minSize) {
                    Text("alle").tag(1)
                    Text("ab 100 KB").tag(100_000)
                    Text("ab 1 MB").tag(1_000_000)
                    Text("ab 100 MB").tag(100_000_000)
                }
                .fixedSize()
                Toggle("Unsichtbare Dateien", isOn: $includeHidden)
                if request.folders.count > 1 {
                    Toggle("Auch im anderen Fenster", isOn: $useBothFolders)
                }
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
                Button("Neu suchen", systemImage: "arrow.clockwise") { runToken = UUID() }
                    .disabled(isRunning)
            }
            Divider()
            summary
            list
            Divider()
            actions
        }
        .padding(16)
        .frame(minWidth: 820, idealWidth: 940, minHeight: 500, idealHeight: 660)
        .task(id: TaskKey(options: options, folders: folders, token: runToken)) { await run() }
        .confirmationDialog("\(marked.count) Datei(en) in den Papierkorb legen?", isPresented: $confirmTrash) {
            Button("In den Papierkorb", role: .destructive) {
                browser.trash(Array(marked))
                marked.removeAll()
                runToken = UUID()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Gibt \(markedSize.formatted(.byteCount(style: .file))) frei. Lässt sich mit ⌘Z widerrufen.")
        }
    }

    // MARK: Teile

    private var summary: some View {
        HStack {
            if isRunning {
                Text("Suche läuft …").foregroundStyle(.secondary)
            } else {
                let wasted = groups.reduce(Int64(0)) { $0 + $1.wasted }
                Text("\(scanned) Dateien geprüft · \(groups.count) Gruppen · \(groups.reduce(0) { $0 + $1.files.count }) Dateien · \(wasted.formatted(.byteCount(style: .file))) doppelt belegt")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !marked.isEmpty {
                Text("\(marked.count) markiert (\(markedSize.formatted(.byteCount(style: .file))))")
            }
        }
        .font(.callout)
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.files) { file in
                        row(file)
                    }
                } header: {
                    Text("\(group.files.count)× „\(group.files[0].name)“ – \(group.size.formatted(.byteCount(style: .file))) je Datei")
                }
            }
        }
        .overlay {
            if !isRunning && groups.isEmpty {
                ContentUnavailableView("Keine doppelten Dateien", systemImage: "checkmark.circle",
                                       description: Text("\(scanned) Dateien geprüft."))
            }
        }
    }

    private func row(_ file: DuplicateFile) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { marked.contains(file.url) },
                set: { if $0 { marked.insert(file.url) } else { marked.remove(file.url) } }
            ))
            .labelsHidden()
            Image(nsImage: IconCache.icon(for: file.url))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(RecentFolders.displayPath(file.url.deletingLastPathComponent()))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(file.modified.formatted(date: .numeric, time: .shortened))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .contextMenu {
            Button("Öffnen") { NSWorkspace.shared.open(file.url) }
            Button("Im Fenster zeigen") {
                browser.activePane.navigate(to: file.url.deletingLastPathComponent())
                browser.activePane.selection = [file.url]
                dismiss()
            }
            Button("Pfad kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
        }
    }

    private var actions: some View {
        HStack {
            Menu("Markieren") {
                Button("Alle außer der ältesten je Gruppe") { markAllExcept(keepOldest: true) }
                Button("Alle außer der neuesten je Gruppe") { markAllExcept(keepOldest: false) }
                Divider()
                Button("Markierung aufheben") { marked.removeAll() }
            }
            .fixedSize()
            .disabled(groups.isEmpty)
            Spacer()
            Button("Markierte in den Papierkorb …", systemImage: "trash") { confirmTrash = true }
                .disabled(marked.isEmpty || isRunning || groupsWithAllMarked > 0)
                .help(groupsWithAllMarked > 0
                      ? "In \(groupsWithAllMarked) Gruppe(n) sind alle Dateien markiert – mindestens eine muss bleiben"
                      : "Markierte Dateien in den Papierkorb legen (widerrufbar)")
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Logik

    /// Gruppen, in denen keine Datei übrig bliebe – dann wird der Papierkorb-Knopf gesperrt
    private var groupsWithAllMarked: Int {
        groups.filter { group in group.files.allSatisfy { marked.contains($0.url) } }.count
    }

    private func markAllExcept(keepOldest: Bool) {
        var result = Set<URL>()
        for group in groups {
            // Dateien sind nach Datum aufsteigend sortiert
            let keep = keepOldest ? group.files.first : group.files.last
            for file in group.files where file.url != keep?.url { result.insert(file.url) }
        }
        marked = result
    }

    private func run() async {
        isRunning = true
        let current = options, targets = folders
        let result = await Task.detached(priority: .userInitiated) {
            DuplicateFinder.find(in: targets, options: current)
        }.value
        guard !Task.isCancelled else { return }
        groups = result.groups
        scanned = result.scanned
        let existing = Set(result.groups.flatMap(\.files).map(\.url))
        marked.formIntersection(existing)
        isRunning = false
    }
}
