import AppKit
import SwiftUI

/// Schwebende Ablage für den Drop Stack (wie Yoink): kleines Fenster am rechten Bildschirmrand, über allen
/// Programmen und auf allen Spaces, plus Symbol in der Menüleiste. Funktioniert auch ohne offenes App-Fenster
/// (die App läuft dann weiter). Erscheint auf Wunsch automatisch, sobald irgendwo Dateien gezogen werden.
@MainActor
final class DropShelfController: NSObject {
    static let shared = DropShelfController()

    static let enabledKey = "dropShelf.enabled"
    static let triggerKey = "dropShelf.trigger"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Wann die Ablage von selbst erscheint
    enum Trigger: String, CaseIterable {
        case shake, drag, off
        var title: String {
            switch self {
            case .shake: "Beim Schütteln einer gezogenen Datei"
            case .drag: "Sobald Dateien gezogen werden"
            case .off: "Nie (nur per Menüleiste)"
            }
        }
    }
    static var trigger: Trigger {
        Trigger(rawValue: UserDefaults.standard.string(forKey: triggerKey) ?? "") ?? .shake
    }

    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var lastDragChange = NSPasteboard(name: .drag).changeCount
    private var shownByDrag = false
    // Schütteln erkennen: Richtungswechsel der Maus (waagerecht, je ≥ 40 pt) innerhalb kurzer Zeit
    private var lastX: CGFloat = 0
    private var direction = 0
    private var turnX: CGFloat = 0
    private var reversals: [Date] = []

    var isVisible: Bool { panel?.isVisible == true }

    /// Beim Start und nach Änderung der Einstellung aufrufen
    func apply() {
        if Self.isEnabled { install() } else { uninstall() }
    }

    private func install() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Drop Stack")
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        }
        if dragMonitor == nil {
            // Globale Maus-Monitore brauchen keine Bedienungshilfen-Freigabe (nur Tastatur-Monitore)
            dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
                MainActor.assumeIsolated { DropShelfController.shared.mouseDragged() }
            }
            upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
                MainActor.assumeIsolated { DropShelfController.shared.dragEnded() }
            }
        }
    }

    private func uninstall() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        dragMonitor = nil
        upMonitor = nil
        panel?.orderOut(nil)
    }

    // MARK: Fenster

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { position(panel) }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        shownByDrag = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 380),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "Drop Stack"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 180, height: 200)
        panel.setFrameAutosaveName("DropShelfPanel")
        panel.contentView = NSHostingView(rootView: DropShelfView())
        return panel
    }

    /// Erstes Zeigen: rechts am Bildschirmrand, mittig (danach merkt sich das Fenster seinen Platz)
    private func position(_ panel: NSPanel) {
        guard UserDefaults.standard.string(forKey: "NSWindow Frame DropShelfPanel") == nil,
              let screen = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 12, y: screen.midY - size.height / 2))
    }

    // MARK: Automatisch beim Ziehen

    private func mouseDragged() {
        let trigger = Self.trigger
        guard trigger != .off, !isVisible else { return }
        // Nur bei einem laufenden Ziehen von Dateien (das Drag-Pasteboard wurde seit dem letzten Loslassen neu befüllt)
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != lastDragChange,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        if trigger == .shake, !detectShake() { return }
        shownByDrag = true
        show()
    }

    private func detectShake() -> Bool {
        let x = NSEvent.mouseLocation.x
        defer { lastX = x }
        let dx = x - lastX
        guard abs(dx) >= 2 else { return false }
        let newDirection = dx > 0 ? 1 : -1
        if newDirection != direction {
            if direction != 0, abs(lastX - turnX) >= 40 { reversals.append(.now) }
            turnX = lastX
            direction = newDirection
        }
        reversals.removeAll { Date.now.timeIntervalSince($0) > 0.8 }
        guard reversals.count >= 3 else { return false }
        reversals.removeAll()
        return true
    }

    private func dragEnded() {
        lastDragChange = NSPasteboard(name: .drag).changeCount
        direction = 0
        reversals.removeAll()
        guard shownByDrag else { return }
        // Nichts abgelegt → nach kurzer Zeit wieder ausblenden (wie Yoink)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if self.shownByDrag, DropStack.shared.items.isEmpty { self.hide() }
            self.shownByDrag = false
        }
    }

    // MARK: Menüleiste

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggle()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let count = DropStack.shared.items.count
        menu.addItem(withTitle: count == 1 ? "1 Datei im Drop Stack" : "\(count) Dateien im Drop Stack", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item(isVisible ? "Ablage ausblenden" : "Ablage zeigen") { DropShelfController.shared.toggle() })
        let triggerMenu = NSMenu()
        for trigger in Trigger.allCases {
            let entry = item(trigger.title) {
                UserDefaults.standard.set(trigger.rawValue, forKey: DropShelfController.triggerKey)
            }
            entry.state = Self.trigger == trigger ? .on : .off
            triggerMenu.addItem(entry)
        }
        let triggerItem = NSMenuItem(title: "Automatisch zeigen", action: nil, keyEquivalent: "")
        triggerItem.submenu = triggerMenu
        menu.addItem(triggerItem)
        menu.addItem(item("Drop Stack leeren") { DropStack.shared.clear() })
        menu.addItem(.separator())
        menu.addItem(item("Finder-Ersatz öffnen") { DropShelfController.openMainWindow() })
        menu.addItem(item("Finder-Ersatz beenden") { NSApp.terminate(nil) })
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func item(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
        let target = ClosureTarget(action)
        item.target = target
        item.representedObject = target   // hält das Ziel am Leben
        return item
    }

    /// Hauptfenster wieder öffnen, auch wenn alle Fenster geschlossen sind (löst „Wiedereröffnen“ aus)
    static func openMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private final class ClosureTarget: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor @objc func run() { action() }
}

/// Inhalt der schwebenden Ablage
struct DropShelfView: View {
    private var stack: DropStack { DropStack.shared }
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 22)   // Platz für die (transparente) Titelleiste
            if stack.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Dateien hierher ziehen")
                        .font(.callout)
                    Text("Sie bleiben an ihrem Ort und lassen sich später gesammelt wieder herausziehen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(stack.items, id: \.self) { url in
                            ShelfRow(url: url, isSelected: stack.selection.contains(url))
                        }
                    }
                    .padding(6)
                }
                Divider()
                HStack(spacing: 8) {
                    MultiFileDragHandle(urls: { DropStack.shared.chosen })
                        .frame(width: 28, height: 28)
                        .help("Ziehen: \(stack.selection.isEmpty ? "alle" : "die ausgewählten") Dateien zusammen herausziehen")
                    Text(stack.selection.isEmpty ? "\(stack.items.count) Dateien" : "\(stack.selection.count) von \(stack.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let browser = BrowserState.current {
                        Button("Ins aktive Fenster kopieren", systemImage: "doc.on.doc") { browser.transferDropStack(move: false) }
                            .labelStyle(.iconOnly)
                            .help("In den Ordner des aktiven Finder-Ersatz-Fensters kopieren")
                    }
                    Button("Leeren", systemImage: "xmark.bin") { stack.clear() }
                        .labelStyle(.iconOnly)
                        .help("Drop Stack leeren (die Dateien selbst bleiben unverändert)")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
        .frame(minWidth: 180, minHeight: 200)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            stack.add(files)
            return true
        } isTargeted: { isTargeted = $0 }
        .onAppear { stack.prune() }
    }
}

private struct ShelfRow: View {
    let url: URL
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .frame(width: 24, height: 24)
            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .help(url.path)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onTapGesture {
            let stack = DropStack.shared
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if stack.selection.contains(url) { stack.selection.remove(url) } else { stack.selection.insert(url) }
            } else {
                stack.selection = stack.selection == [url] ? [] : [url]
            }
        }
        .draggable(url)
        .contextMenu {
            Button("Öffnen") { NSWorkspace.shared.open(url) }
            Button("Im Finder-Ersatz zeigen") {
                DropShelfController.openMainWindow()
                BrowserState.current?.revealDropStackItem(url)
            }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Aus dem Drop Stack entfernen") { DropStack.shared.remove([url]) }
        }
    }
}
