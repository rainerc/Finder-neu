import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nötig, wenn die App per `swift run` ohne .app-Bundle startet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Eigene Tabs statt macOS-Fenster-Tabs (sonst Konflikt mit ⌘T).
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FinderErsatzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browser = BrowserState()

    var body: some Scene {
        WindowGroup("Finder-Ersatz") {
            ContentView()
                .environment(browser)
                .frame(minWidth: 900, minHeight: 500)
        }
        .defaultSize(width: 1200, height: 720)
        .commands { BrowserCommands(browser: browser) }
    }
}

/// Menübefehle mit Tastenkürzeln im Stil klassischer Zwei-Fenster-Dateimanager.
struct BrowserCommands: Commands {
    let browser: BrowserState

    private static func fKey(_ code: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(code)!))
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Neuer Tab") { browser.newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Tab schließen") { browser.closeTabOrWindow() }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Neuer Ordner") { browser.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Ablage-Aktionen") {
            Button("In anderes Fenster kopieren") { browser.copyToOtherPane() }
                .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [])
            Button("In anderes Fenster verschieben") { browser.moveToOtherPane() }
                .keyboardShortcut(Self.fKey(NSF6FunctionKey), modifiers: [])
            Button("Umbenennen …") { browser.beginRename() }
                .keyboardShortcut(Self.fKey(NSF2FunctionKey), modifiers: [])
            Button("Schnellansicht") { browser.toggleQuickLook() }
                .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [])
            Button("In den Papierkorb") { browser.trashSelection() }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Im Finder zeigen") { browser.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Terminal hier öffnen") { browser.openTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
        CommandMenu("Gehe zu") {
            Button("Zurück") { browser.activePane.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Vorwärts") { browser.activePane.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Übergeordneter Ordner") { browser.activePane.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Divider()
            Button("Fenster wechseln") { browser.toggleActivePane() }
                .keyboardShortcut(.tab, modifiers: .option)
            Button("Nächster Tab") { browser.nextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Vorheriger Tab") { browser.previousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Anderes Fenster auf gleichen Ordner") { browser.syncOtherPane() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Fenster tauschen") { browser.swapPanes() }
                .keyboardShortcut("u", modifiers: .command)
            Divider()
            Button("Zu Favoriten hinzufügen") { browser.addSelectionToFavorites() }
                .keyboardShortcut("t", modifiers: [.control, .command])
        }
        CommandGroup(after: .toolbar) {
            Button("Unsichtbare Dateien ein/aus") { browser.activePane.toggleHidden() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Aktualisieren") { browser.reloadAll() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}
