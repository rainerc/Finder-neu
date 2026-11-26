import SwiftUI

struct ContentView: View {
    @Environment(BrowserState.self) private var browser
    @FocusState private var focusedPane: PaneSide?

    var body: some View {
        @Bindable var browser = browser

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    PaneView(side: .left, focus: $focusedPane)
                        .frame(minWidth: 350)
                    PaneView(side: .right, focus: $focusedPane)
                        .frame(minWidth: 350)
                }
                Divider()
                ActionBar()
            }
        }
        .onAppear { focusedPane = browser.activeSide }
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

/// Untere Aktionsleiste, angelehnt an klassische Zwei-Fenster-Dateimanager.
struct ActionBar: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        HStack(spacing: 8) {
            Button("F2 Umbenennen") { browser.beginRename() }
            Button("F5 Kopieren →") { browser.copyToOtherPane() }
            Button("F6 Verschieben →") { browser.moveToOtherPane() }
            Button("⇧⌘N Neuer Ordner") { browser.newFolder() }
            Button("⌘⌫ Papierkorb") { browser.trashSelection() }
            Spacer()
            Text("⌃⇥ Fenster wechseln")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
