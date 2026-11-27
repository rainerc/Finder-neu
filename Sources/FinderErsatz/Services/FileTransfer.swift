import Foundation

/// Ein einzelner Auftrag: Quelle → vollständige Ziel-URL (inkl. Name).
struct TransferItem: Sendable {
    let source: URL
    var destination: URL
    let move: Bool
    var replaceExisting = false
}

/// Kopiert/verschiebt im Hintergrund mit Fortschritt in Bytes. Abbruch über `Task.cancel()`.
enum FileTransfer {
    typealias Progress = @Sendable (_ done: Int64, _ total: Int64, _ currentName: String) async -> Void

    private final class Counter {
        var done: Int64 = 0
        let total: Int64
        init(total: Int64) { self.total = total }
    }

    static func run(_ items: [TransferItem], progress: Progress) async throws {
        let fm = FileManager.default
        let fastMoves = items.map { $0.move && FileService.sameVolume($0.source, $0.destination.deletingLastPathComponent()) }
        var total: Int64 = 0
        for (item, fast) in zip(items, fastMoves) where !fast {
            total += size(of: item.source)
        }
        let counter = Counter(total: total)
        await progress(0, total, items.first?.source.lastPathComponent ?? "")

        for (item, fast) in zip(items, fastMoves) {
            try Task.checkCancellation()
            if item.destination.path.hasPrefix(item.source.path + "/") {
                throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                    NSLocalizedDescriptionKey: "„\(item.source.lastPathComponent)“ kann nicht in sich selbst kopiert werden.",
                ])
            }
            let log = TransferLog.shared
            log.add("  \(item.move ? "Bewegen" : "Kopieren"): \(item.source.path) → \(item.destination.path)\(item.replaceExisting ? " (ersetzen)" : "")")
            if item.replaceExisting, fm.fileExists(atPath: item.destination.path) {
                guard item.source.standardizedFileURL.path != item.destination.standardizedFileURL.path else {
                    log.add("    übersprungen: Quelle = Ziel")
                    continue
                }
                do {
                    try fm.trashItem(at: item.destination, resultingItemURL: nil)
                    log.add("    altes Ziel in den Papierkorb")
                } catch {
                    // Netzwerkvolumes/USB-Sticks haben oft keinen Papierkorb → direkt löschen (wie der Finder)
                    log.add("    Papierkorb ging nicht (\(error.localizedDescription)) → lösche direkt")
                    try fm.removeItem(at: item.destination)
                }
            } else if fm.fileExists(atPath: item.destination.path) {
                log.add("    Ziel existiert, aber „ersetzen“ ist nicht gesetzt")
            }
            if fast {
                try fm.moveItem(at: item.source, to: item.destination)
                await progress(counter.done, counter.total, item.source.lastPathComponent)
                continue
            }
            do {
                try await copyTree(item.source, to: item.destination, counter: counter, progress: progress)
            } catch {
                log.add("    Fehler: \(error.localizedDescription)")
                throw error
            }
            if item.move {
                try fm.removeItem(at: item.source)
            }
            log.add("    fertig: \(TransferLog.describe(item.destination))")
        }
    }

    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]

    private static func copyTree(_ source: URL, to destination: URL, counter: Counter, progress: Progress) async throws {
        try Task.checkCancellation()
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: keys)

        if values.isDirectory == true, values.isSymbolicLink != true {
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
            let children = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: Array(keys), options: [])
            for child in children {
                try await copyTree(child, to: destination.appending(path: child.lastPathComponent), counter: counter, progress: progress)
            }
            // Rechte, Datum, erweiterte Attribute und Tags des Ordners übernehmen.
            _ = copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_STAT))
        } else {
            await progress(counter.done, counter.total, source.lastPathComponent)
            try fm.copyItem(at: source, to: destination)
            counter.done += Int64(values.fileSize ?? 0)
            await progress(counter.done, counter.total, source.lastPathComponent)
        }
    }

    /// Gesamtgröße einer Datei oder eines Ordners (rekursiv).
    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return Int64(values.fileSize ?? 0) }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let child as URL in enumerator {
                if Task.isCancelled { break }   // z. B. Auswahl gewechselt
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    /// Ordnergröße im Hintergrund. Wird die aufrufende Aufgabe abgebrochen (Auswahl gewechselt, Ansicht geschlossen),
    /// bricht auch die Berechnung ab – sonst liefen beim Durchblättern viele Ordner-Scans gleichzeitig weiter.
    /// Auf Netzlaufwerken nur mit `allowNetwork`, weil das dort sehr lange dauert und die Verbindung ausbremst.
    static func folderSize(of url: URL, allowNetwork: Bool = false) async -> Int64? {
        if !allowNetwork, (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false { return nil }
        let task = Task.detached(priority: .utility) { FileTransfer.size(of: url) }
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        return Task.isCancelled ? nil : result
    }
}
