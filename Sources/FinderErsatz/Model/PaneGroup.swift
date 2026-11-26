import Foundation
import Observation

/// Eine Seite (links oder rechts) mit mehreren Tabs. Jeder Tab ist ein eigenes `PaneState`.
@MainActor
@Observable
final class PaneGroup {
    private(set) var tabs: [PaneState]
    private(set) var selectedID: PaneState.ID

    init(url: URL) {
        let first = PaneState(url: url)
        tabs = [first]
        selectedID = first.id
    }

    var current: PaneState {
        tabs.first { $0.id == selectedID } ?? tabs[0]
    }

    private var currentIndex: Int {
        tabs.firstIndex { $0.id == selectedID } ?? 0
    }

    /// Neuer Tab rechts vom aktuellen, standardmäßig mit demselben Ordner.
    func newTab(url: URL? = nil) {
        let tab = PaneState(url: url ?? current.currentURL)
        tabs.insert(tab, at: currentIndex + 1)
        selectedID = tab.id
    }

    /// Schließt einen Tab. Gibt `false` zurück, wenn es der letzte war (der bleibt offen).
    @discardableResult
    func close(_ id: PaneState.ID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)
        if id == selectedID {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
        return true
    }

    func select(_ id: PaneState.ID) {
        if tabs.contains(where: { $0.id == id }) { selectedID = id }
    }

    func selectNext() {
        selectedID = tabs[(currentIndex + 1) % tabs.count].id
    }

    func selectPrevious() {
        selectedID = tabs[(currentIndex - 1 + tabs.count) % tabs.count].id
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
}
