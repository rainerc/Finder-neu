import Foundation
import Observation

/// Protokoll aller Dateiaktionen (Total Commander: Protokolldatei). Bleibt über Neustarts erhalten:
/// je Eintrag eine JSON-Zeile in ~/Library/Application Support/Finder-Ersatz/Aktionen.jsonl.
@MainActor
@Observable
final class ActionLog {
    static let shared = ActionLog()

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var title: String
        var details: [String]
        var isError = false
    }

    private(set) var entries: [Entry] = []
    private static let keepInMemory = 3000

    @ObservationIgnored let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "Finder-Ersatz/Aktionen.jsonl")
    }()

    private init() {
        load()
    }

    func add(_ title: String, details: [String] = [], isError: Bool = false) {
        let entry = Entry(date: .now, title: title, details: details, isError: isError)
        entries.append(entry)
        if entries.count > Self.keepInMemory { entries.removeFirst(entries.count - Self.keepInMemory) }
        append(entry)
    }

    /// Beschreibung einer widerrufbaren Aktion (Pfade mit ~ abgekürzt)
    func add(_ action: UndoableAction, title: String? = nil) {
        switch action {
        case let .rename(from, to):
            add(title ?? "Umbenannt", details: ["\(Self.short(from)) → \(to.lastPathComponent)"])
        case let .moved(pairs):
            let sameFolder = pairs.allSatisfy { $0.from.deletingLastPathComponent() == $0.to.deletingLastPathComponent() }
            add(title ?? (sameFolder ? "Umbenannt (\(pairs.count))" : "Bewegt (\(pairs.count))"),
                details: pairs.map { sameFolder ? "\(Self.short($0.from)) → \($0.to.lastPathComponent)"
                                                : "\(Self.short($0.from)) → \(Self.short($0.to))" })
        case let .trashed(pairs):
            add(title ?? "In den Papierkorb (\(pairs.count))", details: pairs.map { Self.short($0.original) })
        case let .created(urls):
            add(title ?? "Erstellt (\(urls.count))", details: urls.map { Self.short($0) })
        }
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Alles als lesbarer Text (zum Kopieren)
    func text(for entries: [Entry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.map { entry in
            ([formatter.string(from: entry.date) + "  " + (entry.isError ? "FEHLER " : "") + entry.title]
             + entry.details.map { "        " + $0 }).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func short(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    // MARK: Datei

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        let lines = data.split(separator: UInt8(ascii: "\n")).suffix(Self.keepInMemory)
        entries = lines.compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }

    private func append(_ entry: Entry) {
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.append(UInt8(ascii: "\n"))
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
