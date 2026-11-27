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
        if initial.spotlightQuery != nil {
            // „Zuletzt benutzt“/Tags lassen sich nicht bearbeiten – mit leerer Suche beginnen
            initial = SearchQuery(root: pane.currentURL)
        }
        if pane.editingSmartFolder == nil {
            initial.root = pane.currentURL
        }
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
                if let editing = pane.editingSmartFolder {
                    Button("Änderungen sichern") {
                        browser.smartFolders.update(editing, query: query)
                        start()
                        browser.flash("Intelligenter Ordner aktualisiert")
                    }
                    .disabled(query.isEmpty)
                    .help("Geänderte Kriterien im intelligenten Ordner speichern")
                }
                Button(pane.editingSmartFolder == nil ? "Sichern …" : "Als neuen sichern …",
                       systemImage: "folder.badge.gearshape") {
                    var saved = query
                    if pane.editingSmartFolder == nil { saved.root = pane.currentURL }
                    saved.title = nil
                    browser.saveSearchQuery = saved
                    browser.saveSearchName = suggestedName
                }
                .disabled(query.isEmpty)
                .help("Suche als intelligenten Ordner in der Seitenleiste sichern – er zeigt bei jedem Öffnen die aktuellen Treffer")
                Button("Schließen", systemImage: "xmark.circle.fill") { pane.closeSearch() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Suche schließen (Esc)")
            }
            HStack(spacing: 8) {
                Text("Suchen in:").foregroundStyle(.secondary)
                Picker("Suchen in", selection: $query.scope) {
                    Text("Dieser Mac").tag(SearchQuery.Scope.thisMac)
                    Text("„\(folderName)“").tag(SearchQuery.Scope.folder)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if query.criteria.count > 1 {
                    Picker("Verknüpfung", selection: $query.matchAll) {
                        Text("Alle Bedingungen erfüllt").tag(true)
                        Text("Mindestens eine erfüllt").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Button("Bedingung", systemImage: "plus.circle") { addCriterion(after: nil) }
                    .help("Weitere Bedingung hinzufügen, z. B. Art, Datum, Größe, Tag")
            }
            ForEach($query.criteria) { $criterion in
                SearchCriterionRow(criterion: $criterion,
                                   onAdd: { addCriterion(after: criterion.id) },
                                   onRemove: { query.criteria.removeAll { $0.id == criterion.id } })
                    .onSubmit(start)
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
            Text(scopeDescription)
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
        // Ab dem Ordner suchen, der gerade angezeigt wird (beim Bearbeiten eines intelligenten Ordners: dessen Ordner).
        if pane.editingSmartFolder == nil { query.root = pane.currentURL }
        pane.startSearch(query)
    }

    private var folderName: String {
        let url = pane.editingSmartFolder == nil ? pane.currentURL : query.root
        return FileManager.default.displayName(atPath: url.path)
    }

    private var scopeDescription: String {
        let base = query.scope == .thisMac
            ? "Sucht auf diesem Mac (Spotlight-Index)"
            : "Sucht in „\(folderName)“ und allen Unterordnern"
        let active = query.criteria.filter(\.isComplete).count
        return active == 0 ? base : base + " · \(active) Bedingung\(active == 1 ? "" : "en")"
    }

    private var suggestedName: String {
        if !query.term.isEmpty { return query.term }
        if !query.contentText.isEmpty { return query.contentText }
        return query.criteria.first.map(SearchCriterionRow.summary) ?? "Suche"
    }

    private func addCriterion(after id: SearchCriterion.ID?) {
        // Nächste sinnvolle Eigenschaft vorschlagen (wie im Finder: Art, dann Datum …)
        let used = Set(query.criteria.map(\.attribute))
        let next = [SearchCriterion.Attribute.kind, .modified, .name, .size, .tag, .created, .lastOpened,
                    .fileExtension, .contents].first { !used.contains($0) } ?? .name
        let criterion = SearchCriterion(attribute: next)
        if let id, let index = query.criteria.firstIndex(where: { $0.id == id }) {
            query.criteria.insert(criterion, at: index + 1)
        } else {
            query.criteria.append(criterion)
        }
    }
}

/// Eine Bedingungszeile: [Eigenschaft] [Vergleich] [Wert]  (−) (+)
struct SearchCriterionRow: View {
    @Binding var criterion: SearchCriterion
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("Eigenschaft", selection: $criterion.attribute) {
                ForEach(SearchCriterion.Attribute.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)
            valueEditor
            Spacer(minLength: 0)
            Button("Entfernen", systemImage: "minus.circle", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Bedingung entfernen")
            Button("Hinzufügen", systemImage: "plus.circle", action: onAdd)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Bedingung darunter hinzufügen")
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch criterion.attribute {
        case .kind:
            Text("ist").foregroundStyle(.secondary)
            Picker("Art", selection: $criterion.kind) {
                ForEach(SearchCriterion.Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case .name, .contents, .tag:
            Picker("Vergleich", selection: $criterion.textOperator) {
                ForEach(SearchCriterion.TextOperator.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField(criterion.attribute == .tag ? "z. B. Rot, Wichtig" : "Text", text: $criterion.text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 260)
        case .fileExtension:
            Text("ist").foregroundStyle(.secondary)
            TextField("z. B. pdf", text: $criterion.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        case .modified, .created, .lastOpened:
            Picker("Zeitraum", selection: $criterion.dateOperator) {
                ForEach(SearchCriterion.DateOperator.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            switch criterion.dateOperator {
            case .withinLast:
                TextField("Anzahl", value: $criterion.amount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Picker("Einheit", selection: $criterion.dateUnit) {
                    ForEach(SearchCriterion.DateUnit.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            case .before, .after, .exactly:
                DatePicker("Datum", selection: $criterion.date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            default:
                EmptyView()
            }
        case .size:
            Picker("Vergleich", selection: $criterion.sizeOperator) {
                ForEach(SearchCriterion.SizeOperator.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("Größe", value: $criterion.size, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Picker("Einheit", selection: $criterion.sizeUnit) {
                ForEach(SearchCriterion.SizeUnit.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// Kurzbeschreibung, z. B. „Art: Bild“ – als Namensvorschlag beim Sichern.
    static func summary(_ criterion: SearchCriterion) -> String {
        switch criterion.attribute {
        case .kind: return criterion.kind.title
        case .name, .contents, .tag, .fileExtension: return "\(criterion.attribute.title): \(criterion.text)"
        case .modified, .created, .lastOpened:
            let when = criterion.dateOperator == .withinLast
                ? "letzte \(criterion.amount) \(criterion.dateUnit.title)"
                : criterion.dateOperator.title
            return "\(criterion.attribute.title) \(when)"
        case .size: return "\(criterion.sizeOperator.title) \(criterion.size.formatted()) \(criterion.sizeUnit.title)"
        }
    }
}
