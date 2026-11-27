import Foundation

/// Übernimmt die Einstellungen (Favoriten, Drop Stack, Verbindungen, Spalten, Fensterpositionen …)
/// einmalig aus der alten Bundle-ID `com.example.FinderErsatz`, als Twinfold eine eigene bekam.
/// Läuft vor allem anderen (erste gespeicherte Eigenschaft von `FinderErsatzApp`), damit
/// `AppSettings`, `@AppStorage` und die Stores schon die übernommenen Werte lesen.
enum DefaultsMigration {
    static let oldDomain = "com.example.FinderErsatz"
    static let markerKey = "migratedFromFinderErsatz"

    static func run() {
        let defaults = UserDefaults.standard
        guard let newDomain = Bundle.main.bundleIdentifier, newDomain != oldDomain,
              !defaults.bool(forKey: markerKey) else { return }
        let existing = defaults.persistentDomain(forName: newDomain) ?? [:]
        if let old = defaults.persistentDomain(forName: oldDomain) {
            for (key, value) in old where existing[key] == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: markerKey)
    }
}
