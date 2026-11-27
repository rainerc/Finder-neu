import SwiftUI
import AppKit

/// Ein Kontextmenü-Eintrag. Das Datei-Kontextmenü wird einmal als Liste solcher Einträge beschrieben und dann
/// als SwiftUI-Menü (Raster-, Spalten-, Galerieansicht) oder als `NSMenu` (native Listenansicht) dargestellt.
indirect enum MenuEntry {
    case action(String, image: NSImage? = nil, destructive: Bool = false, perform: () -> Void)
    /// Eintrag mit Alternative bei gedrückter ⌥-Taste (wie im Finder „… als Pfadname kopieren“)
    case withAlternate(MenuEntry, alternate: MenuEntry)
    case toggle(String, isOn: Bool, perform: () -> Void)
    case submenu(String, [MenuEntry])
    case share([URL])
    case divider

    /// Symbol eines SF-Symbols, optional eingefärbt (z. B. Farbpunkte für Tags)
    static func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        guard let color else { return image }
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }

    /// App-Symbol in Menügröße
    static func icon(forFile path: String) -> NSImage {
        let image = (NSWorkspace.shared.icon(forFile: path).copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

// MARK: SwiftUI

struct MenuEntriesView: View {
    let entries: [MenuEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            MenuEntryView(entry: entry)
        }
    }
}

struct MenuEntryView: View {
    let entry: MenuEntry

    var body: some View {
        switch entry {
        case let .action(title, image, destructive, perform):
            Button(role: destructive ? .destructive : nil) {
                perform()
            } label: {
                if let image {
                    Label { Text(title) } icon: { Image(nsImage: image) }
                } else {
                    Text(title)
                }
            }
        case let .withAlternate(primary, alternate):
            MenuEntryView(entry: primary)
                .modifierKeyAlternate(.option) {
                    MenuEntryView(entry: alternate)
                }
        case let .toggle(title, isOn, perform):
            Button {
                perform()
            } label: {
                if isOn {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
        case let .submenu(title, children):
            Menu(title) {
                MenuEntriesView(entries: children)
            }
        case let .share(urls):
            ShareLink(items: urls) {
                Label("Teilen …", systemImage: "square.and.arrow.up")
            }
        case .divider:
            Divider()
        }
    }
}

// MARK: AppKit

@MainActor
enum NativeMenu {
    /// Baut ein `NSMenu`. `anchor` ist die Ansicht, an der „Teilen …“ seine Auswahl zeigt.
    static func make(_ entries: [MenuEntry], anchor: NSView?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries { add(entry, to: menu, anchor: anchor) }
        return menu
    }

    private static func add(_ entry: MenuEntry, to menu: NSMenu, anchor: NSView?) {
        switch entry {
        case let .action(title, image, _, perform):
            menu.addItem(ClosureMenuItem(title: title, image: image, perform: perform))
        case let .withAlternate(primary, alternate):
            add(primary, to: menu, anchor: anchor)
            let countBefore = menu.items.count
            add(alternate, to: menu, anchor: anchor)
            if menu.items.count > countBefore, let item = menu.items.last {
                item.isAlternate = true
                item.keyEquivalentModifierMask = .option
            }
        case let .toggle(title, isOn, perform):
            let item = ClosureMenuItem(title: title, image: nil, perform: perform)
            item.state = isOn ? .on : .off
            menu.addItem(item)
        case let .submenu(title, children):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = make(children, anchor: anchor)
            menu.addItem(item)
        case let .share(urls):
            menu.addItem(ClosureMenuItem(title: "Teilen …", image: MenuEntry.symbol("square.and.arrow.up")) { [weak anchor] in
                guard let anchor else { return }
                let picker = NSSharingServicePicker(items: urls)
                var point = NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
                if let window = anchor.window {
                    point = anchor.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                }
                picker.show(relativeTo: NSRect(origin: point, size: NSSize(width: 1, height: 1)), of: anchor, preferredEdge: .maxY)
            })
        case .divider:
            menu.addItem(.separator())
        }
    }
}

/// Menüeintrag, der eine Closure ausführt.
final class ClosureMenuItem: NSMenuItem {
    private let perform: () -> Void

    init(title: String, image: NSImage?, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(ClosureMenuItem.run(_:)), keyEquivalent: "")
        self.target = self
        self.image = image
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    @objc private func run(_ sender: Any?) { perform() }
}
