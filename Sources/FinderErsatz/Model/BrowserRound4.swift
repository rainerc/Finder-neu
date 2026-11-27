import AppKit

// Total-Commander-Runde 4: Nur Ausgewähltes, Attribute ändern, Aufteilen/Zusammenfügen, Packen in weitere Formate.

struct AttributesRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct SplitRequest: Identifiable {
    let id = UUID()
    let file: URL
    let size: Int64
}

struct PackRequest: Identifiable {
    let id = UUID()
    let sources: [URL]
}

/// Gewünschte Änderungen aus dem Attribute-Dialog (nil = nicht ändern)
struct AttributeChanges: Sendable {
    var modified: Date?
    var created: Date?
    /// POSIX-Rechte, z. B. 0o644
    var permissions: Int?
    /// Ordner bekommen bei Rechten automatisch x, wo r gesetzt ist (wie chmod -R u+rwX)
    var folderExecutable = true
    var locked: Bool?
    var hidden: Bool?
    var hideExtension: Bool?
    var recursive = false

    var isEmpty: Bool {
        modified == nil && created == nil && permissions == nil && locked == nil && hidden == nil && hideExtension == nil
    }

    /// Wendet die Änderungen an; liefert die Anzahl geänderter Objekte und die Fehler
    func apply(to urls: [URL]) -> (count: Int, errors: [String]) {
        var count = 0
        var errors: [String] = []
        let fm = FileManager.default
        var all: [URL] = []
        for url in urls {
            all.append(url)
            if recursive, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let child as URL in enumerator { all.append(child) }
            }
        }
        for url in all {
            do {
                // Gesperrte Objekte zuerst entsperren, sonst schlagen die anderen Änderungen fehl
                if locked == false { try setValues(url) { $0.isUserImmutable = false } }
                var attributes: [FileAttributeKey: Any] = [:]
                if let modified { attributes[.modificationDate] = modified }
                if let created { attributes[.creationDate] = created }
                if let permissions {
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    var mode = permissions
                    if isDir, folderExecutable {
                        // r → auch x, damit Ordner betretbar bleiben
                        if mode & 0o400 != 0 { mode |= 0o100 }
                        if mode & 0o040 != 0 { mode |= 0o010 }
                        if mode & 0o004 != 0 { mode |= 0o001 }
                    }
                    attributes[.posixPermissions] = NSNumber(value: mode)
                }
                if !attributes.isEmpty { try fm.setAttributes(attributes, ofItemAtPath: url.path) }
                if let hidden { try setValues(url) { $0.isHidden = hidden } }
                if let hideExtension { try setValues(url) { $0.hasHiddenExtension = hideExtension } }
                if locked == true { try setValues(url) { $0.isUserImmutable = true } }
                count += 1
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (count, errors)
    }

    private func setValues(_ url: URL, _ change: (inout URLResourceValues) -> Void) throws {
        var values = URLResourceValues()
        change(&values)
        var target = url
        try target.setResourceValues(values)
    }
}

extension BrowserState {

    // MARK: Nur Ausgewähltes

    func toggleShowOnlySelected() {
        let pane = activePane
        if pane.onlySelectedIDs == nil, pane.selection.isEmpty {
            NSSound.beep()
            flash("Erst Objekte auswählen – dann zeigt ⌃⌘I nur diese")
            return
        }
        pane.toggleShowOnlySelected()
    }

    // MARK: Attribute

    func showAttributes() {
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { NSSound.beep(); return }
        activePane.rememberSelection()
        attributesRequest = AttributesRequest(urls: urls)
    }

    func applyAttributes(_ changes: AttributeChanges, to urls: [URL]) {
        guard !changes.isEmpty else { return }
        operations.enqueue(title: "Attribute ändern (\(urls.count))", onSuccess: { [weak self] in
            self?.reloadAll()
        }) { _ in
            let result = changes.apply(to: urls)
            await MainActor.run {
                ActionLog.shared.add("Attribute geändert (\(result.count))",
                                     details: urls.prefix(50).map { ActionLog.short($0) } + result.errors,
                                     isError: !result.errors.isEmpty)
            }
            if !result.errors.isEmpty {
                throw CocoaError(.fileWriteNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "\(result.errors.count) Objekt(e) ließen sich nicht ändern:\n"
                        + result.errors.prefix(5).joined(separator: "\n"),
                ])
            }
        }
    }

    // MARK: Aufteilen / Zusammenfügen

    func showSplit() {
        guard let item = activePane.selectedItems.first(where: { !$0.isDirectory }) else {
            NSSound.beep()
            flash("Bitte eine Datei zum Aufteilen auswählen")
            return
        }
        splitRequest = SplitRequest(file: item.url, size: item.size)
    }

    func split(_ file: URL, partSize: Int64, into folder: URL) {
        // Namen der Teile vorab bestimmen (für Widerrufen/Protokoll nach dem Ende)
        let total = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let count = max(1, Int((total + partSize - 1) / max(partSize, 1)))
        let digits = max(3, String(count).count)
        let parts = (1...count).map { index in
            folder.appending(path: "\(file.lastPathComponent).\(String(repeating: "0", count: max(0, digits - String(index).count)) + String(index))")
        }
        operations.enqueue(title: "Aufteilen: \(file.lastPathComponent)", onSuccess: { [weak self] in
            self?.recordUndo(.created(parts), logTitle: "Aufgeteilt: \(file.lastPathComponent) in \(parts.count) Teile")
            self?.reloadAll()
        }) { progress in
            try await FileSplitter.split(file, partSize: partSize, into: folder, progress: progress)
        }
    }

    /// Ausgewählte .001-Datei (oder irgendein Teil) → alle Teile ins andere Fenster zusammenfügen
    func joinSelectedParts() {
        guard let selected = activePane.selectedItems.first(where: { !$0.isDirectory && Int($0.fileExtension) != nil }) else {
            NSSound.beep()
            flash("Bitte den ersten Teil auswählen (z. B. „Film.mkv.001“)")
            return
        }
        // Vom ersten Teil aus suchen
        let base = selected.url.deletingPathExtension()
        let digits = selected.fileExtension.count
        let first = base.appendingPathExtension(String(repeating: "0", count: max(0, digits - 1)) + "1")
        let parts = FileSplitter.parts(startingWith: FileManager.default.fileExists(atPath: first.path) ? first : selected.url)
        guard !parts.isEmpty else { NSSound.beep(); return }
        let target = otherPane.currentURL.appending(path: base.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            alertMessage = "„\(target.lastPathComponent)“ gibt es im anderen Fenster schon."
            return
        }
        operations.enqueue(title: "Zusammenfügen: \(target.lastPathComponent) (\(parts.count) Teile)", onSuccess: { [weak self] in
            self?.recordUndo(.created([target]), logTitle: "Zusammengefügt: \(target.lastPathComponent) aus \(parts.count) Teilen")
            self?.reloadAll()
        }) { progress in
            try await FileSplitter.join(parts, to: target, progress: progress)
        }
    }

    // MARK: Packen

    func showPack() {
        let sources = activePane.selectedItems.map(\.url)
        guard !sources.isEmpty else { NSSound.beep(); return }
        activePane.rememberSelection()
        packRequest = PackRequest(sources: sources)
    }

    func pack(_ sources: [URL], to archive: URL, format: ArchiveService.PackFormat, password: String?) {
        operations.enqueue(title: "Packen: \(archive.lastPathComponent)", onSuccess: { [weak self] in
            self?.recordUndo(.created([archive]), logTitle: "Gepackt: \(archive.lastPathComponent) (\(sources.count) Objekte)")
            self?.reloadAll()
        }) { _ in
            do {
                try ArchiveService.pack(sources, to: archive, format: format, password: password)
            } catch {
                try? FileManager.default.removeItem(at: archive)
                throw error
            }
        }
    }

    func listSelectedArchive() {
        guard let archive = activePane.selectedItems.first(where: { ArchiveService.isArchive($0.url) }) else {
            NSSound.beep()
            flash("Bitte ein Archiv auswählen")
            return
        }
        runShell(ArchiveService.listCommand(for: archive.url), in: activePane.currentURL, inTerminal: false)
    }
}
