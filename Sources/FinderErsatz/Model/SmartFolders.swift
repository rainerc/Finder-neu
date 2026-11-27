import Foundation
import Observation

/// Gespeicherte Suche („intelligenter Ordner“) in der Seitenleiste.
struct SmartFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var query: SearchQuery

    var sidebarTag: URL { URL(string: "finderersatz://smart/\(id.uuidString)")! }

    /// Abfrage zum Anzeigen: mit Namen als Titel und Markierung in der Seitenleiste.
    var displayQuery: SearchQuery {
        var result = query
        result.title = name
        result.sidebarTag = sidebarTag
        return result
    }
}

/// Verwaltet die intelligenten Ordner und speichert sie in den UserDefaults.
@MainActor
@Observable
final class SmartFolderStore {
    private(set) var items: [SmartFolder] = []
    private let defaultsKey = "smartFolders"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([SmartFolder].self, from: data) {
            items = saved
        }
    }

    func add(name: String, query: SearchQuery) {
        var stored = query
        stored.title = nil
        stored.sidebarTag = nil
        items.append(SmartFolder(name: name, query: stored))
        save()
    }

    /// Suchkriterien eines intelligenten Ordners ersetzen (nach „Bearbeiten“).
    func update(_ id: SmartFolder.ID, query: SearchQuery) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var stored = query
        stored.title = nil
        stored.sidebarTag = nil
        items[index].query = stored
        save()
    }

    func rename(_ folder: SmartFolder, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == folder.id }), !name.isEmpty else { return }
        items[index].name = name
        save()
    }

    func remove(_ folder: SmartFolder) {
        items.removeAll { $0.id == folder.id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func folder(for tag: URL) -> SmartFolder? {
        items.first { $0.sidebarTag == tag }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
