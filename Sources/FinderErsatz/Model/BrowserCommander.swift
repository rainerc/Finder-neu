import AppKit

// Total-Commander-Runde 2: Favoriten-Menü, Auswahl wiederherstellen, Auswählen nach Eigenschaften,
// synchrones Blättern, Prüfsummen, Betrachter.

struct SelectRequest: Identifiable {
    let id = UUID()
    /// true = auswählen, false = Auswahl aufheben
    let select: Bool
}

struct ChecksumRequest: Identifiable {
    let id = UUID()
    let files: [URL]
}

struct ViewerRequest: Identifiable {
    let id = UUID()
    let url: URL
}

extension BrowserState {

    // MARK: Favoriten-Menü per Tastatur (Total Commander: Strg+D)

    /// Klappt ein Menü mit Favoriten (Ziffern 1–9), zuletzt besuchten Ordnern und Volumes an der Maus auf.
    /// Auswahl öffnet den Ordner im aktiven Fenster.
    func showFavoritesMenu() {
        let menu = NSMenu(title: "Favoriten")
        menu.autoenablesItems = false
        let pane = activePane

        func entry(_ title: String, _ url: URL, key: String = "") -> NSMenuItem {
            let image = IconCache.icon(for: url).copy() as? NSImage
            image?.size = NSSize(width: 16, height: 16)
            let item = ClosureMenuItem(title: title, image: image) { pane.navigate(to: url) }
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = []
            item.toolTip = url.path
            return item
        }

        let header = NSMenuItem(title: "Favoriten", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if favorites.items.isEmpty {
            let empty = NSMenuItem(title: "Noch keine Favoriten", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, favorite) in favorites.items.enumerated() {
            menu.addItem(entry(favorite.name, favorite.url, key: index < 9 ? "\(index + 1)" : ""))
        }
        menu.addItem(.separator())

        let current = pane.currentURL
        let isFavorite = favorites.items.contains { $0.url.normalizedFileURL == current }
        let add = ClosureMenuItem(title: "„\(pane.title)“ zu Favoriten hinzufügen",
                                  image: NSImage(systemSymbolName: "star", accessibilityDescription: nil)) { [weak self] in
            self?.favorites.add([current])
            self?.flash("„\(current.lastPathComponent)“ zu Favoriten hinzugefügt")
        }
        add.keyEquivalent = "+"
        add.keyEquivalentModifierMask = []
        add.isEnabled = !isFavorite && pane.activeSearch == nil
        menu.addItem(add)

        // Zuletzt besuchte Ordner
        let recents = RecentFolders.shared.urls.filter { $0 != current }.prefix(15)
        if !recents.isEmpty {
            let recentItem = NSMenuItem(title: "Zuletzt besucht", action: nil, keyEquivalent: "")
            recentItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            let submenu = NSMenu()
            for url in recents {
                submenu.addItem(entry(RecentFolders.displayPath(url), url))
            }
            recentItem.submenu = submenu
            menu.addItem(recentItem)
        }

        // Volumes
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                             options: [.skipHiddenVolumes]) ?? []
        if !volumes.isEmpty {
            let volumeItem = NSMenuItem(title: "Volumes", action: nil, keyEquivalent: "")
            volumeItem.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)
            let submenu = NSMenu()
            for url in volumes {
                let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
                submenu.addItem(entry(name, url))
            }
            volumeItem.submenu = submenu
            menu.addItem(volumeItem)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Auswahl wiederherstellen

    func restoreSelection() {
        let count = activePane.restoreSelection()
        if count == 0 {
            NSSound.beep()
            flash("Keine gemerkte Auswahl in diesem Ordner")
        } else {
            flash("Auswahl wiederhergestellt (\(count))")
        }
    }

    // MARK: Auswählen nach Eigenschaften

    /// Wählt im aktiven Fenster alle passenden Objekte aus (bzw. ab). Inhaltssuche läuft im Hintergrund.
    func applySelection(_ criteria: SelectCriteria, select: Bool) {
        let pane = activePane
        pane.rememberSelection()
        let candidates = pane.items.filter { criteria.matchesWithoutContent($0) }
        let finish: @MainActor @Sendable ([FileItem.ID]) -> Void = { [weak self] ids in
            if select {
                pane.selection.formUnion(ids)
            } else {
                pane.selection.subtract(ids)
            }
            self?.flash("\(ids.count) Objekt(e) \(select ? "ausgewählt" : "abgewählt")")
        }
        guard criteria.usesContent else {
            finish(candidates.map(\.id))
            return
        }
        flash("Durchsuche Inhalt von \(candidates.count) Datei(en) …")
        Task.detached(priority: .userInitiated) {
            let ids = candidates.filter { criteria.contentMatches($0) }.map(\.id)
            await finish(ids)
        }
    }

    // MARK: Synchrones Blättern (Total Commander: „Synchrones Wechseln“)

    func toggleSyncBrowsing() {
        syncBrowsing.toggle()
        flash(syncBrowsing ? "Synchrones Blättern an – das andere Fenster folgt" : "Synchrones Blättern aus")
    }

    /// Wird von `PaneState` bei jedem Ordnerwechsel gerufen. Folgt nur dem aktiven Fenster
    /// (der Wechsel im anderen Fenster löst deshalb keine Schleife aus).
    func paneDidChangeFolder(_ pane: PaneState, from old: URL) {
        guard syncBrowsing, pane === activePane, pane.activeSearch == nil else { return }
        let other = otherPane
        let new = pane.currentURL
        let oldParts = old.standardizedFileURL.pathComponents
        let newParts = new.standardizedFileURL.pathComponents
        var target = other.currentURL
        if newParts.count > oldParts.count, Array(newParts.prefix(oldParts.count)) == oldParts {
            // In Unterordner gewechselt → gleichnamigen Unterordner im anderen Fenster öffnen
            for component in newParts.dropFirst(oldParts.count) {
                target = target.appending(path: component)
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
                flash("Synchrones Blättern: „\(new.lastPathComponent)“ gibt es im anderen Fenster nicht")
                return
            }
        } else if oldParts.count > newParts.count, Array(oldParts.prefix(newParts.count)) == newParts {
            // Nach oben gewechselt → im anderen Fenster genauso viele Ebenen nach oben
            for _ in 0..<(oldParts.count - newParts.count) where target.path != "/" {
                target = target.deletingLastPathComponent()
            }
        } else {
            // Woanders hingesprungen: das andere Fenster bleibt, wo es ist
            return
        }
        other.navigate(to: target)
    }

    // MARK: Prüfsummen und Betrachter

    func showChecksums() {
        let files = activePane.selectedItems.filter { !$0.isBrowsableFolder }.map(\.url)
        guard !files.isEmpty else {
            NSSound.beep()
            flash("Für Prüfsummen bitte eine oder mehrere Dateien auswählen")
            return
        }
        checksumRequest = ChecksumRequest(files: files)
    }

    func showViewer() {
        guard let file = activePane.selectedItems.first(where: { !$0.isBrowsableFolder }) else {
            NSSound.beep()
            flash("Bitte eine Datei auswählen")
            return
        }
        viewerRequest = ViewerRequest(url: file.url)
    }
}

/// Bedingungen des Dialogs „Auswählen …“: alle gesetzten müssen zutreffen.
struct SelectCriteria: Sendable {
    enum Kind: String, CaseIterable, Sendable { case all, files, folders }

    var patterns: [String] = []
    var kind: Kind = .all
    var minSize: Int64?
    var maxSize: Int64?
    var modifiedAfter: Date?
    var modifiedBefore: Date?
    var content: String?
    var contentIgnoresCase = true

    var usesContent: Bool { !(content ?? "").isEmpty }

    func matchesWithoutContent(_ item: FileItem) -> Bool {
        switch kind {
        case .all: break
        case .files: if item.isBrowsableFolder { return false }
        case .folders: if !item.isBrowsableFolder { return false }
        }
        if !patterns.isEmpty {
            let matches = patterns.contains { NSPredicate(format: "SELF LIKE[cd] %@", $0).evaluate(with: item.name) }
            if !matches { return false }
        }
        // Größe: bei Ordnern nur, wenn sie berechnet ist
        if minSize != nil || maxSize != nil {
            if item.isDirectory && !item.folderSizeKnown { return false }
            if let minSize, item.size <= minSize { return false }
            if let maxSize, item.size >= maxSize { return false }
        }
        if let modifiedAfter, item.modified < modifiedAfter { return false }
        if let modifiedBefore, item.modified >= modifiedBefore { return false }
        if usesContent && item.isDirectory { return false }
        return true
    }

    /// Enthält die Datei den Text? Bis 32 MB als Text (UTF-8, sonst Latin-1), größere nur byteweise (UTF-8).
    func contentMatches(_ item: FileItem) -> Bool {
        guard let content, !content.isEmpty,
              let data = try? Data(contentsOf: item.url, options: .mappedIfSafe) else { return false }
        if data.count <= 32 * 1024 * 1024 {
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return text.range(of: content, options: contentIgnoresCase ? [.caseInsensitive, .diacriticInsensitive] : []) != nil
        }
        return data.range(of: Data(content.utf8)) != nil
    }
}
