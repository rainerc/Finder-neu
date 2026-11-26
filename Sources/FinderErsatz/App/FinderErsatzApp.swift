import SwiftUI
import AppKit

@MainActor
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
@MainActor
struct BrowserCommands: Commands {
    let browser: BrowserState
    let settings: AppSettings

    /// Steht der Cursor in einem Textfeld (z. B. Suche, Umbenennen)?
    private var textEditing: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

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
        // Bearbeiten-Menü: in Textfeldern normales Text-Verhalten, sonst Dateien (wie im Finder).
        CommandGroup(replacing: .undoRedo) {
            Button(browser.undoTitle ?? "Widerrufen") {
                if textEditing { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { browser.undo() }
            }
            .keyboardShortcut(settings.keyboardShortcut(for: .undo))
            Button("Wiederholen") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Ausschneiden") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button(ShortcutAction.copyFiles.title) {
                if textEditing { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) } else { browser.copySelectionToPasteboard() }
            }
            .keyboardShortcut(settings.keyboardShortcut(for: .copyFiles))
            Button(ShortcutAction.pasteFiles.title) {
                if textEditing { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) } else { browser.pasteFromPasteboard(move: false) }
            }
            .keyboardShortcut(settings.keyboardShortcut(for: .pasteFiles))
            item(.moveFilesHere) { browser.pasteFromPasteboard(move: true) }
            Button(ShortcutAction.selectAll.title) {
                if textEditing { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) } else { browser.selectAll() }
            }
            .keyboardShortcut(settings.keyboardShortcut(for: .selectAll))
            Divider()
            item(.copyPath) { browser.copyPathsToPasteboard() }
        }
        CommandGroup(after: .textEditing) {
            item(.search) { browser.showSearch() }
        }
        CommandGroup(after: .newItem) {
            Divider()
            item(.duplicate) { browser.duplicateSelection() }
            item(.makeAlias) { browser.makeAliasForSelection() }
            item(.getInfo) { browser.showInfo() }
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
            item(.goToFolder) { browser.showGoToFolder() }
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

// MARK: AppleScript (für Hookmark: „selected paths“, „current folder“)
// Direkt an NSApplication, damit Cocoa Scripting die Werte per KVC findet
// (der von SwiftUI eingesetzte App-Delegate ist ein Proxy und leitet KVC nicht zuverlässig weiter).
extension NSApplication {
    /// Ausgewählte Objekte im aktiven Fenster; ohne Auswahl der aktuelle Ordner.
    @objc var selectedPaths: [String] {
        guard let browser = BrowserState.current else { return [] }
        let selected = browser.activePane.selectedItems.map(\.url.path)
        return selected.isEmpty ? [browser.activePane.currentURL.path] : selected
    }

    @objc var currentFolderPath: String {
        BrowserState.current?.activePane.currentURL.path ?? ""
    }

    /// Diagnose: `osascript -e 'tell application "/Applications/Finder-Ersatz.app" to get debug info'`
    @objc var scriptingDebugInfo: String {
        guard let browser = BrowserState.current else { return "BrowserState.current = nil (Fenster noch nicht erschienen?)" }
        let pane = browser.activePane
        return "aktiv: \(browser.activeSide == .left ? "links" : "rechts"), Ordner: \(pane.currentURL.path), "
            + "Objekte: \(pane.items.count), ausgewählt: \(pane.selection.count), Fenster: \(NSApp.windows.count)"
    }
}
