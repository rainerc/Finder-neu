import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var browser: BrowserState?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌘W abfangen, bevor das Standardmenü „Fenster schließen“ greift:
        // schließt nur den aktiven Tab; beim letzten Tab passiert nichts (Beenden mit ⌘Q).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let browser = self?.browser, NSApp.keyWindow?.attachedSheet == nil else { return false }
                if !browser.closeTab() { NSSound.beep() }
                return true
            }
            return handled ? nil : event
        }

        // Nötig, wenn die App per `swift run` ohne .app-Bundle startet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Eigene Tabs statt macOS-Fenster-Tabs (sonst Konflikt mit ⌘T).
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // Temporär entpackte Archive aufräumen.
        try? FileManager.default.removeItem(at: ArchiveService.browseRoot)
    }
}

@main
struct FinderErsatzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browser = BrowserState()

    var body: some Scene {
        WindowGroup("Finder-Ersatz") {
            ContentView()
                .environment(browser)
                .onAppear { appDelegate.browser = browser }
                .frame(minWidth: 900, minHeight: 500)
        }
        .defaultSize(width: 1200, height: 720)
        .commands { BrowserCommands(browser: browser, settings: browser.settings) }

        Settings {
            SettingsView()
                .environment(browser.settings)
        }
    }
}

/// Menübefehle. Tastenkürzel kommen aus den Einstellungen (änderbar unter ⌘, → Tastenkürzel).
struct BrowserCommands: Commands {
    let browser: BrowserState
    let settings: AppSettings

    private func item(_ action: ShortcutAction, _ perform: @escaping () -> Void) -> some View {
        Button(action.title, action: perform)
            .keyboardShortcut(settings.keyboardShortcut(for: action))
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            item(.newTab) { browser.newTab() }
            // ⌘W wird im AppDelegate abgefangen (sonst schließt das Standardmenü das Fenster).
            Button("Tab schließen (⌘W)") { _ = browser.closeTab() }
            Divider()
            item(.newFolder) { browser.newFolder() }
        }
        CommandGroup(after: .textEditing) {
            item(.search) { browser.showSearch() }
        }
        CommandMenu("Ablage-Aktionen") {
            item(.copy) { browser.copyToOtherPane() }
            item(.move) { browser.moveToOtherPane() }
            item(.rename) { browser.beginRename() }
            item(.quickLook) { browser.toggleQuickLook() }
            item(.trash) { browser.trashSelection() }
            Divider()
            item(.compress) { browser.compressSelection() }
            item(.extractHere) { browser.extractSelection(toOtherPane: false) }
            item(.extractToOther) { browser.extractSelection(toOtherPane: true) }
            Divider()
            item(.reveal) { browser.revealInFinder() }
            item(.terminal) { browser.openTerminal() }
        }
        CommandMenu("Gehe zu") {
            item(.connectServer) {
                NotificationCenter.default.post(name: .connectToServer, object: nil)
            }
            Divider()
            item(.back) { browser.activePane.goBack() }
            item(.forward) { browser.activePane.goForward() }
            item(.up) { browser.activePane.goUp() }
            Divider()
            item(.switchPane) { browser.toggleActivePane() }
            item(.nextTab) { browser.nextTab() }
            item(.previousTab) { browser.previousTab() }
            item(.syncPanes) { browser.syncOtherPane() }
            item(.swapPanes) { browser.swapPanes() }
            Divider()
            item(.addFavorite) { browser.addSelectionToFavorites() }
        }
        CommandGroup(after: .toolbar) {
            item(.viewList) { browser.setViewMode(.list) }
            item(.viewBrief) { browser.setViewMode(.brief) }
            item(.viewIcons) { browser.setViewMode(.icons) }
            Divider()
            item(.toggleHidden) { browser.activePane.toggleHidden() }
            item(.reload) { browser.reloadAll() }
        }
    }
}

extension Notification.Name {
    /// Öffnet den Dialog „Mit Server verbinden“ in der Seitenleiste.
    static let connectToServer = Notification.Name("connectToServer")
}
