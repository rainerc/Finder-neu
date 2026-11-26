import SwiftUI

/// Suchleiste unter dem Fensterkopf (⌘F). Sucht rekursiv ab dem aktuellen Ordner.
struct SearchBar: View {
    let pane: PaneState
    @State private var query: SearchQuery
    @FocusState private var termFocused: Bool

    init(pane: PaneState) {
        self.pane = pane
        var initial = pane.lastSearch ?? SearchQuery(root: pane.currentURL)
        initial.root = pane.activeSearch?.root ?? pane.currentURL
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
            Text("Sucht in „\(query.root.lastPathComponent.isEmpty ? "/" : query.root.lastPathComponent)“ und allen Unterordnern")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { termFocused = true }
    }

    private func start() {
        pane.startSearch(query)
    }
}
