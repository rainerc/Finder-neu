import Foundation

/// Protokoll der letzten Kopier-/Verschiebe-Vorgänge inkl. Überschreiben-Entscheidungen.
/// Threadsicher, weil `FileTransfer` im Hintergrund schreibt. Hilfe → „Kopier-Diagnose kopieren“.
final class TransferLog: @unchecked Sendable {
    static let shared = TransferLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func add(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append("\(formatter.string(from: Date()))  \(message)")
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
    }

    var report: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.isEmpty ? "(noch keine Kopiervorgänge)" : lines.joined(separator: "\n")
    }

    /// Kurzbeschreibung einer Datei: Größe und Änderungsdatum (oder „fehlt“)
    static func describe(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else {
            return "\(url.path) [fehlt]"
        }
        let kind = values.isDirectory == true ? "Ordner" : "\(values.fileSize ?? 0) B"
        let date = values.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
        return "\(url.path) [\(kind), \(date)]"
    }
}
