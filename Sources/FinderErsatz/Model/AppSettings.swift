import SwiftUI
import AppKit
import Observation

/// Darstellungs- und Tastatur-Einstellungen, gespeichert in den UserDefaults.
@MainActor
@Observable
final class AppSettings {
    enum ListSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: "Klein"
            case .medium: "Normal"
            case .large: "Groß"
            }
        }
        var font: Font {
            switch self {
            case .small: .callout
            case .medium: .body
            case .large: .title3
            }
        }
        var iconSize: CGFloat {
            switch self {
            case .small: 14
            case .medium: 16
            case .large: 20
            }
        }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "Wie System"
            case .light: "Hell"
            case .dark: "Dunkel"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private let defaults = UserDefaults.standard

    var listSize: ListSize { didSet { defaults.set(listSize.rawValue, forKey: "listSize") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var alternatingRows: Bool { didSet { defaults.set(alternatingRows, forKey: "alternatingRows") } }
    var showHiddenDimmed: Bool { didSet { defaults.set(showHiddenDimmed, forKey: "showHiddenDimmed") } }
    /// Farbe der Markierung des aktiven Fensters (Hex, leer = Systemakzentfarbe).
    var activeColorHex: String { didSet { defaults.set(activeColorHex, forKey: "activeColorHex") } }
    /// Farbe für Ordnernamen (Hex, leer = Standard).
    var folderColorHex: String { didSet { defaults.set(folderColorHex, forKey: "folderColorHex") } }
    /// Leertaste auf Ordnern: Quick Look (z. B. XRay, langsam bei großen Ordnern) statt eigener schneller Vorschau.
    var folderPreviewUsesQuickLook: Bool {
        didSet { defaults.set(folderPreviewUsesQuickLook, forKey: "folderPreviewUsesQuickLook") }
    }
    /// Ruhiges Layout: eine gemeinsame Symbolleiste fürs aktive Fenster, schmale Fensterköpfe, keine F-Tasten-Leiste.
    var compactLayout: Bool {
        didSet {
            defaults.set(compactLayout, forKey: "compactLayout")
            showActionBar = !compactLayout
        }
    }
    /// Leiste mit F2/F3/F5 … unten im Fenster.
    var showActionBar: Bool { didSet { defaults.set(showActionBar, forKey: "showActionBar") } }
    /// Ordnername als Überschrift über jedem Fenster (der Fenstertitel zeigt nur das aktive)
    var showPaneTitles: Bool { didSet { defaults.set(showPaneTitles, forKey: "showPaneTitles") } }
    /// Ordnergrößen in den Listen im Hintergrund berechnen (nur lokale Laufwerke).
    var calculateFolderSizes: Bool {
        didSet {
            defaults.set(calculateFolderSizes, forKey: Self.calculateFolderSizesKey)
            onFolderSizeSettingChanged?()
        }
    }
    static let calculateFolderSizesKey = "calculateFolderSizes"
    @ObservationIgnored var onFolderSizeSettingChanged: (() -> Void)?
    /// Eigene Tastenkürzel; fehlt ein Eintrag, gilt der Standard. `nil`-Wert = bewusst ohne Kürzel.
    private(set) var customShortcuts: [ShortcutAction: Shortcut?] = [:]

    init() {
        listSize = ListSize(rawValue: defaults.string(forKey: "listSize") ?? "") ?? .medium
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        alternatingRows = defaults.object(forKey: "alternatingRows") as? Bool ?? true
        showHiddenDimmed = defaults.object(forKey: "showHiddenDimmed") as? Bool ?? true
        activeColorHex = defaults.string(forKey: "activeColorHex") ?? ""
        folderColorHex = defaults.string(forKey: "folderColorHex") ?? ""
        // Ordnergrößen wie im Finder standardmäßig anzeigen (register: gilt auch für `UserDefaults.bool` in PaneState)
        defaults.register(defaults: [Self.calculateFolderSizesKey: true])
        calculateFolderSizes = defaults.bool(forKey: Self.calculateFolderSizesKey)
        compactLayout = defaults.bool(forKey: "compactLayout")
        showActionBar = defaults.object(forKey: "showActionBar") as? Bool ?? true
        showPaneTitles = defaults.object(forKey: "showPaneTitles") as? Bool ?? true
        folderPreviewUsesQuickLook = defaults.bool(forKey: "folderPreviewUsesQuickLook")
        if let data = defaults.data(forKey: "customShortcuts"),
           let stored = try? JSONDecoder().decode([String: Shortcut?].self, from: data) {
            for (key, value) in stored {
                if let action = ShortcutAction(rawValue: key) { customShortcuts[action] = value }
            }
        }
    }

    // MARK: Farben

    var activeColor: Color {
        get { Color(hex: activeColorHex) ?? .accentColor }
        set { activeColorHex = newValue.hexString ?? "" }
    }

    var folderColor: Color? {
        Color(hex: folderColorHex)
    }

    var folderColorBinding: Color {
        get { Color(hex: folderColorHex) ?? .primary }
        set { folderColorHex = newValue.hexString ?? "" }
    }

    // MARK: Tastenkürzel

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        if let custom = customShortcuts[action] { return custom }
        return action.defaultShortcut
    }

    func keyboardShortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        shortcut(for: action)?.keyboardShortcut
    }

    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        // Kürzel ist eindeutig: bei anderen Befehlen entfernen.
        if let shortcut {
            for other in ShortcutAction.allCases where other != action && self.shortcut(for: other) == shortcut {
                customShortcuts[other] = .some(nil)
            }
        }
        customShortcuts[action] = .some(shortcut)
        saveShortcuts()
    }

    func resetShortcut(_ action: ShortcutAction) {
        customShortcuts.removeValue(forKey: action)
        saveShortcuts()
    }

    func resetAllShortcuts() {
        customShortcuts.removeAll()
        saveShortcuts()
    }

    func isCustom(_ action: ShortcutAction) -> Bool { customShortcuts[action] != nil }

    private func saveShortcuts() {
        let stored = Dictionary(uniqueKeysWithValues: customShortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: "customShortcuts")
        }
    }
}

extension Color {
    /// Aus „#RRGGBB“; nil bei leerem/ungültigem Wert.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
