import Foundation
import Observation

/// Ein Eintrag in der Seitenleiste unter „Favoriten“.
struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var url: URL
    var name: String

    init(url: URL, name: String? = nil) {
        self.url = url.normalizedFileURL
        self.name = name ?? FileManager.default.displayName(atPath: url.path)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// SF-Symbol passend zu bekannten Ordnern, sonst Ordnersymbol.
    var symbolName: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.normalizedFileURL
        switch url {
        case home: return "house"
        case home.appending(path: "Desktop"): return "menubar.dock.rectangle"
        case home.appending(path: "Documents"): return "doc"
        case home.appending(path: "Downloads"): return "arrow.down.circle"
        case home.appending(path: "Pictures"): return "photo"
        case home.appending(path: "Music"): return "music.note"
        case home.appending(path: "Movies"): return "film"
        case URL(filePath: "/Applications"): return "square.grid.3x3"
        case home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs"): return "icloud"
        default: return "folder"
        }
    }
}

/// Verwaltet die Favoriten und speichert sie in den UserDefaults.
@MainActor
@Observable
final class FavoritesStore {
    private(set) var items: [Favorite] = []

    private let defaultsKey = "sidebarFavorites"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = saved
        } else {
            items = Self.defaultFavorites()
        }
    }

    func contains(_ url: URL) -> Bool {
        items.contains { $0.url == url.normalizedFileURL }
    }

    /// Fügt Ordner hinzu (Dateien und Duplikate werden ignoriert).
    func add(_ urls: [URL], at index: Int? = nil) {
        var insertAt = min(index ?? items.count, items.count)
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  !contains(url) else { continue }
            items.insert(Favorite(url: url), at: insertAt)
            insertAt += 1
        }
        save()
    }

    func remove(_ favorite: Favorite) {
        items.removeAll { $0.id == favorite.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func rename(_ favorite: Favorite, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == favorite.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        items[index].name = trimmed.isEmpty ? FileManager.default.displayName(atPath: favorite.url.path) : trimmed
        save()
    }

    func resetToDefaults() {
        items = Self.defaultFavorites()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func defaultFavorites() -> [Favorite] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home,
            home.appending(path: "Desktop"),
            home.appending(path: "Documents"),
            home.appending(path: "Downloads"),
            URL(filePath: "/Applications"),
        ]
        .filter { FileManager.default.fileExists(atPath: $0.path) }
        .map { Favorite(url: $0) }
    }
}
