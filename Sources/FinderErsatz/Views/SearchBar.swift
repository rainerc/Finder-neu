import SwiftUI

/// Suchleiste unter dem Fensterkopf (⌘F). Sucht rekursiv ab dem aktuellen Ordner.
struct SearchBar: View {
    @Environment(BrowserState.self) private var browser
    let pane: PaneState
    @State private var query: SearchQuery
    @FocusState private var termFocused: Bool
    @State private var regexHelperTab: RegexHelperSheet.Tab?

    init(pane: PaneState) {
        self.pane = pane
        var initial = pane.lastSearch ?? SearchQuery(root: pane.currentURL)
        initial.root = pane.currentURL
        _query = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(query.mode == .wildcard ? "z. B. *.jpg; *.png" : "Dateiname", text: $query.term)
                    .textFieldStyle(.roundedBorder)
                    .focused($termFocused)
                    .onSubmit(start)
                Picker("Modus", selection: $query.mode) {
                    ForEach(SearchQuery.Mode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                if query.mode == .regex {
                    Menu {
                        Button("Assistent: Was suchst du? …", systemImage: "wand.and.stars") { regexHelperTab = .wizard }
                        Button("Werkstatt (Muster bauen und testen) …", systemImage: "hammer") { regexHelperTab = .workshop }
                        Button("Anleitung & Beispiele …", systemImage: "book") { regexHelperTab = .guide }
                    } label: {
                        Label("Regex-Hilfe", systemImage: "wand.and.stars")
                    }
                    .fixedSize()
                    .help("Regex-Hilfe: Assistent, Werkstatt mit Live-Test, Anleitung")
                }
                Toggle("Aa", isOn: $query.caseSensitive)
                    .toggleStyle(.button)
                    .help("Groß-/Kleinschreibung beachten")
                    .disabled(query.mode == .spotlight)
                if pane.isSearchRunning {
                    Button("Stopp") { pane.cancelSearchTask() }
                } else {
                    Button("Suchen", action: start)
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.isEmpty)
                }
                Button("Sichern", systemImage: "folder.badge.gearshape") {
                    var saved = query
                    saved.root = pane.currentURL
                    browser.saveSearchQuery = saved
                    browser.saveSearchName = query.term.isEmpty ? query.contentText : query.term
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(query.isEmpty)
                .help("Suche als intelligenten Ordner in der Seitenleiste sichern")
                Button("Schließen", systemImage: "xmark.circle.fill") { pane.closeSearch() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Suche schließen (Esc)")
            }
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Enthält Text (optional)", text: $query.contentText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(start)
                if query.mode != .spotlight {
                    Picker("Kodierung", selection: $query.encoding) {
                        ForEach(SearchQuery.TextEncoding.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(query.contentText.isEmpty)
                    Toggle("Unsichtbare", isOn: $query.includeHidden)
                        .toggleStyle(.checkbox)
                }
            }
            Text("Sucht in „\(pane.title)“ und allen Unterordnern")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { termFocused = true }
        .sheet(item: $regexHelperTab) { tab in
            RegexHelperSheet(purpose: .search, sampleNames: regexSamples, pattern: query.term,
                             caseSensitive: query.caseSensitive, initialTab: tab) { pattern, _, caseSensitive in
                query.term = pattern
                query.caseSensitive = caseSensitive
            }
        }
    }

    /// Namen zum Ausprobieren: aktueller Ordner (bzw. aktuelle Treffer) plus eine Ebene darunter.
    private var regexSamples: [String] {
        var names = pane.items.map(\.name)
        if names.count < 300 {
            for folder in pane.items.filter(\.isBrowsableFolder).prefix(20) {
                names += ((try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? [])
                    .filter { !$0.hasPrefix(".") }.prefix(30)
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private func start() {
        // Immer ab dem Ordner suchen, der gerade angezeigt wird.
        query.root = pane.currentURL
        pane.startSearch(query)
    }
}
