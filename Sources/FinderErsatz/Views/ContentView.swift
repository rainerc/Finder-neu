import SwiftUI
import AppKit
import QuickLook

struct ContentView: View {
    @Environment(BrowserState.self) private var browser
    @FocusState private var focusedPane: PaneSide?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var browser = browser

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if AppEnvironment.isRunningUnbundled {
                    UnbundledBanner()
                    Divider()
                }
                HSplitView {
                    PaneView(side: .left, focus: $focusedPane)
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                    PaneView(side: .right, focus: $focusedPane)
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                JobsPanel(queue: browser.operations)
                if browser.settings.showActionBar {
                    ActionBar()
                } else if let message = browser.flashMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $browser.showInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 220, ideal: 300, max: 480)
            }
        }
        // Mindestgröße wie im Finder: Seitenleiste (bis 320) + zwei Fenster (je 240) + ggf. Vorschau-Spalte (220)
        .frame(minWidth: browser.showInspector ? 1060 : 840, minHeight: 500)
        .preferredColorScheme(browser.settings.appearance.colorScheme)
        // Fenstertitel wie im Finder: Ordner des aktiven Fensters, darunter der volle Pfad
        .navigationTitle(browser.activePane.title)
        .navigationSubtitle(windowSubtitle)
        .onAppear {
            BrowserState.current = browser
            focusedPane = browser.activeSide
            updateRepresentedURL(browser.focusedItemURL)
        }
        .task(id: browser.focusedItemURL) {
            // Titelleisten-Symbol erst setzen, wenn die Auswahl kurz stehen bleibt (spart Arbeit beim Durchklicken)
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { updateRepresentedURL(browser.focusedItemURL) }
        }
        .onChange(of: focusedPane) { _, side in
            if let side { browser.activeSide = side }
        }
        .onChange(of: browser.activeSide) { _, side in focusedPane = side }
        .toolbar {
            if browser.settings.compactLayout {
                // Ruhiges Layout: Navigation und Ansicht für das aktive Fenster in der Fensterleiste
                ToolbarItemGroup(placement: .navigation) {
                    Button("Zurück", systemImage: "chevron.left") { browser.activePane.goBack() }
                        .disabled(!browser.activePane.canGoBack)
                        .help("Zurück (⌘[)")
                    Button("Vorwärts", systemImage: "chevron.right") { browser.activePane.goForward() }
                        .disabled(!browser.activePane.canGoForward)
                        .help("Vorwärts (⌘])")
                    Button("Nach oben", systemImage: "arrow.up") { browser.activePane.goUp() }
                        .disabled(!browser.activePane.canGoUp)
                        .help("Übergeordneter Ordner (⌘↑)")
                }
                ToolbarItemGroup {
                    Picker("Ansicht", selection: Binding(get: { browser.activePane.viewMode },
                                                         set: { browser.setViewMode($0) })) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Ansicht des aktiven Fensters (⌘1–⌘5)")
                    Button("Suchen", systemImage: "magnifyingglass") { browser.activePane.isSearchBarVisible.toggle() }
                        .help("Im aktiven Fenster suchen (⌘F)")
                    Button("Neuer Tab", systemImage: "plus.square.on.square") { browser.newTab() }
                        .help("Neuer Tab im aktiven Fenster (⌘T)")
                }
            }
            ToolbarItemGroup {
                ShareLink(items: browser.activePane.selectedItems.map(\.url)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .disabled(browser.activePane.selectedItems.isEmpty)
                .help("Auswahl teilen (AirDrop, Mail, Nachrichten …)")
                Button("Fenster tauschen", systemImage: "arrow.left.arrow.right") { browser.swapPanes() }
                    .help("Linkes und rechtes Fenster tauschen (⌘U)")
                Button("Gleicher Ordner", systemImage: "equal.square") { browser.syncOtherPane() }
                    .help("Anderes Fenster auf denselben Ordner setzen (⌘=)")
                Button("Unsichtbare Dateien", systemImage: browser.activePane.showHidden ? "eye" : "eye.slash") {
                    browser.activePane.toggleHidden()
                }
                .help("Unsichtbare Dateien im aktiven Fenster ein-/ausblenden (⇧⌘.)")
                Button("Vorschaubereich unten", systemImage: "rectangle.bottomthird.inset.filled") { browser.showPanePreview.toggle() }
                    .help("Vorschaubereich unten in den Fenstern ein-/ausblenden (⌃⌘P)")
                Button("Vorschau", systemImage: "sidebar.trailing") { browser.showInspector.toggle() }
                    .help("Vorschau-Spalte ein-/ausblenden (⇧⌘P)")
            }
        }
        .alert(
            "Aktion fehlgeschlagen",
            isPresented: Binding(get: { browser.alertMessage != nil },
                                 set: { if !$0 { browser.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(browser.alertMessage ?? "")
        }
        .sheet(item: $browser.transferRequest) { request in
            TransferSheet(request: request)
                .environment(browser)
        }
        .alert(
            "Objekte bereits vorhanden",
            isPresented: Binding(get: { browser.conflictRequest != nil },
                                 set: { if !$0 { browser.conflictRequest = nil } }),
            presenting: browser.conflictRequest
        ) { _ in
            Button("Ersetzen", role: .destructive) { browser.resolveConflicts(.replace) }
            Button("Beide behalten") { browser.resolveConflicts(.keepBoth) }
            Button("Überspringen") { browser.resolveConflicts(.skip) }
            Button("Abbrechen", role: .cancel) { browser.conflictRequest = nil }
        } message: { request in
            let names = request.conflictNames.prefix(5).map { "„\($0)“" }.joined(separator: ", ")
            let more = request.conflictNames.count > 5 ? " und \(request.conflictNames.count - 5) weitere" : ""
            Text("Im Ziel gibt es bereits \(names)\(more). Ersetzte Objekte kommen in den Papierkorb.")
        }
        .sheet(isPresented: Binding(get: { browser.folderPreviewURL != nil },
                                    set: { if !$0 { browser.folderPreviewURL = nil } })) {
            if let url = browser.folderPreviewURL {
                FolderPreviewSheet(url: url)
                    .environment(browser)
            }
        }
        .sheet(item: $browser.batchRenameRequest) { request in
            BatchRenameSheet(request: request)
                .environment(browser)
        }
        .alert(
            "Intelligenten Ordner sichern",
            isPresented: Binding(get: { browser.saveSearchQuery != nil },
                                 set: { if !$0 { browser.saveSearchQuery = nil } })
        ) {
            TextField("Name", text: $browser.saveSearchName)
            Button("Sichern") { browser.commitSaveSearch() }
            Button("Abbrechen", role: .cancel) { browser.saveSearchQuery = nil }
        } message: {
            Text("Die Suche erscheint in der Seitenleiste unter „Intelligente Ordner“ und wird bei jedem Klick neu ausgeführt.")
        }
        .sheet(item: $browser.infoItem) { item in
            InfoSheet(item: item)
                .environment(browser)
        }
        .alert("Gehe zu Ordner", isPresented: $browser.goToFolderVisible) {
            TextField("/Pfad/zum/Ordner oder ~/…", text: $browser.goToFolderPath)
            Button("Öffnen") { browser.commitGoToFolder() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Pfad eingeben, z. B. ~/Library oder /Volumes")
        }
        .alert(
            "Umbenennen",
            isPresented: Binding(get: { browser.renameTarget != nil },
                                 set: { if !$0 { browser.renameTarget = nil } })
        ) {
            TextField("Neuer Name", text: $browser.renameText)
            Button("Umbenennen") { browser.commitRename() }
            Button("Erweitert (Regex, Nummerieren) …") { browser.beginBatchRename(regex: true) }
            Button("Abbrechen", role: .cancel) { browser.renameTarget = nil }
        }
    }
}

extension ContentView {
    /// Pfad des aktiven Fensters (mit ~ für den Benutzerordner); bei Treffern einer Suche deren Ort.
    var windowSubtitle: String {
        let pane = browser.activePane
        let path = pane.activeSearch.map { $0.searchesEverywhere ? "Alle Volumes" : $0.root.path } ?? pane.currentURL.path
        return (path as NSString).abbreviatingWithTildeInPath
    }
}

/// Meldet macOS (und damit Hookmark per Bedienungshilfen) das ausgewählte Objekt als Dokument des Fensters.
@MainActor
private func updateRepresentedURL(_ url: URL) {
    let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    window?.representedURL = url
}

/// Untere Aktionsleiste, angelehnt an klassische Zwei-Fenster-Dateimanager.
struct ActionBar: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        HStack(spacing: 8) {
            Button("F2 Umbenennen") { browser.beginRename() }
            Button("F3 Ansicht") { browser.toggleQuickLook() }
            Button("F5 Kopieren →") { browser.copyToOtherPane() }
            Button("F6 Verschieben →") { browser.moveToOtherPane() }
            Button("⇧⌘N Neuer Ordner") { browser.newFolder() }
            Button("⌘⌫ Papierkorb") { browser.trashSelection() }
            Spacer()
            if let message = browser.flashMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.green)
            } else {
                Text("⇥ Fenster wechseln · ⌃⇥ Tab wechseln")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Erkennt, ob die App ohne .app-Bundle läuft (z. B. `swift run` oder `.build/debug/FinderErsatz`).
/// Dann gelten die macOS-Freigaben (Netzwerkvolumes, Festplattenvollzugriff) der installierten App nicht.
enum AppEnvironment {
    static let installedAppURL = URL(filePath: "/Applications/Finder-Ersatz.app")
    static var isRunningUnbundled: Bool { Bundle.main.bundleURL.pathExtension != "app" }
}

/// Warnhinweis oben, wenn die App ohne Bundle läuft – mit Knopf zum Wechsel auf die installierte App.
private struct UnbundledBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Läuft als Test-Build ohne App-Bundle (\(Bundle.main.executablePath ?? "?")). Netzlaufwerke und andere macOS-Freigaben funktionieren so nicht.")
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
            if FileManager.default.fileExists(atPath: AppEnvironment.installedAppURL.path) {
                Button("Installierte App starten") {
                    Task { @MainActor in
                        _ = try? await NSWorkspace.shared.openApplication(
                            at: AppEnvironment.installedAppURL,
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                        NSApp.terminate(nil)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.15))
    }
}
