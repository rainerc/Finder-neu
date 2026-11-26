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
                HSplitView {
                    PaneView(side: .left, focus: $focusedPane)
                        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    PaneView(side: .right, focus: $focusedPane)
                        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                JobsPanel(queue: browser.operations)
                ActionBar()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(browser.settings.appearance.colorScheme)
        .onAppear {
            BrowserState.current = browser
            focusedPane = browser.activeSide
            updateRepresentedURL(browser.focusedItemURL)
        }
        .onChange(of: browser.focusedItemURL) { _, url in updateRepresentedURL(url) }
        .onChange(of: focusedPane) { _, side in
            if let side { browser.activeSide = side }
        }
        .onChange(of: browser.activeSide) { _, side in focusedPane = side }
        .toolbar {
            ToolbarItemGroup {
                Button("Fenster tauschen", systemImage: "arrow.left.arrow.right") { browser.swapPanes() }
                    .help("Linkes und rechtes Fenster tauschen (⌘U)")
                Button("Gleicher Ordner", systemImage: "equal.square") { browser.syncOtherPane() }
                    .help("Anderes Fenster auf denselben Ordner setzen (⌘=)")
                Button("Unsichtbare Dateien", systemImage: browser.activePane.showHidden ? "eye" : "eye.slash") {
                    browser.activePane.toggleHidden()
                }
                .help("Unsichtbare Dateien im aktiven Fenster ein-/ausblenden (⇧⌘.)")
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
        .quickLookPreview($browser.previewURL, in: browser.previewItems)
        .alert(
            "Umbenennen",
            isPresented: Binding(get: { browser.renameTarget != nil },
                                 set: { if !$0 { browser.renameTarget = nil } })
        ) {
            TextField("Neuer Name", text: $browser.renameText)
            Button("Umbenennen") { browser.commitRename() }
            Button("Abbrechen", role: .cancel) { browser.renameTarget = nil }
        }
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
            Text("⇥ Fenster wechseln · ⌃⇥ Tab wechseln")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
