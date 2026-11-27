import AppKit

/// Sammelablage (wie in Path Finder): Ablage zum Sammeln von Dateien aus verschiedenen Ordnern.
/// Die Dateien bleiben, wo sie sind – gemerkt werden nur die Pfade (UserDefaults „dropStack“).
/// Danach alles auf einmal herauskopieren/-verschieben oder herausziehen (Finder, Mail …).
@MainActor
@Observable
final class DropStack {
    static let shared = DropStack()

    private(set) var items: [URL] = []
    var selection = Set<URL>()

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: "dropStack") ?? []
        items = paths.map { URL(filePath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    @ObservationIgnored private var anchor: URL?

    /// Klick auf einen Eintrag: ⌘ = hinzufügen/entfernen, ⇧ = Bereich ab dem letzten Klick, sonst nur dieser
    func click(_ url: URL, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor, let from = items.firstIndex(of: anchor), let to = items.firstIndex(of: url) {
            selection = Set(items[min(from, to)...max(from, to)])
            return
        }
        if modifiers.contains(.command) {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
        } else {
            selection = [url]
        }
        anchor = url
    }

    func selectAll() { selection = Set(items) }

    /// Ausgewählte Einträge – oder alle, wenn nichts ausgewählt ist
    var chosen: [URL] {
        let selected = items.filter { selection.contains($0) }
        return selected.isEmpty ? items : selected
    }

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls.map(\.normalizedFileURL) where !items.contains(url) {
            items.append(url)
            added += 1
        }
        save()
        return added
    }

    func remove(_ urls: [URL]) {
        let removing = Set(urls.map(\.normalizedFileURL))
        items.removeAll { removing.contains($0) }
        selection.subtract(removing)
        save()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        save()
    }

    /// Nach dem Verschieben die neuen Orte merken
    func relocate(_ moves: [(from: URL, to: URL)]) {
        for move in moves {
            if let index = items.firstIndex(of: move.from.normalizedFileURL) {
                items[index] = move.to.normalizedFileURL
            }
        }
        selection.removeAll()
        save()
    }

    /// Entfernt Einträge, die es nicht mehr gibt (gelöscht, umbenannt)
    func prune() {
        let before = items.count
        items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        if items.count != before { save() }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: "dropStack")
    }
}

extension BrowserState {

    /// ⌃⌘J: Auswahl des aktiven Fensters in die Sammelablage
    func addSelectionToDropStack() {
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else {
            NSSound.beep()
            flash("Erst Dateien auswählen – ⌃⌘J legt sie in die Sammelablage")
            return
        }
        let added = DropStack.shared.add(urls)
        settings.showDropStack = true
        flash(added == 0 ? "Schon in der Sammelablage" : "\(added) in die Sammelablage gelegt (\(DropStack.shared.items.count) insgesamt)")
    }

    /// Inhalt der Sammelablage (Auswahl oder alles) ins aktive Fenster kopieren/verschieben
    func transferDropStack(move: Bool) {
        let stack = DropStack.shared
        stack.prune()
        let sources = stack.chosen
        guard !sources.isEmpty else { NSSound.beep(); return }
        if let remote = activePane.remote {
            upload(sources, from: activePane, to: remote, move: move)
            if move { stack.remove(sources) }
            return
        }
        let folder = activePane.currentURL
        let items = sources.map { TransferItem(source: $0, destination: folder.appending(path: $0.lastPathComponent), move: move) }
            .filter { $0.source.normalizedFileURL != $0.destination.normalizedFileURL }
        guard !items.isEmpty else {
            flash("Die Dateien liegen schon in diesem Ordner")
            return
        }
        enqueue(title: "Sammelablage \(move ? "verschieben" : "kopieren") nach „\(folder.lastPathComponent)“", items: items)
        if move { stack.relocate(items.map { (from: $0.source, to: $0.destination) }) }
    }

    /// Eintrag im aktiven Fenster zeigen (Ordner öffnen, Datei auswählen)
    func revealDropStackItem(_ url: URL) {
        let pane = activePane
        pane.navigate(to: url.deletingLastPathComponent())
        pane.selection = [url.normalizedFileURL]
    }
}
