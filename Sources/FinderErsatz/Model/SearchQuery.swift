import Foundation

/// Parameter einer Suche im aktuellen Ordner (rekursiv).
struct SearchQuery: Sendable, Hashable, Codable {
    enum Mode: String, CaseIterable, Identifiable, Sendable, Codable {
        case contains, wildcard, regex, spotlight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .contains: "Name enthält"
            case .wildcard: "Platzhalter (*, ?)"
            case .regex: "Regulärer Ausdruck"
            case .spotlight: "Spotlight"
            }
        }
    }

    enum TextEncoding: String, CaseIterable, Identifiable, Sendable, Codable {
        case utf8, latin1, utf16
        var id: String { rawValue }
        var title: String {
            switch self {
            case .utf8: "UTF-8"
            case .latin1: "Latin-1 / Windows"
            case .utf16: "UTF-16"
            }
        }
        var encoding: String.Encoding {
            switch self {
            case .utf8: .utf8
            case .latin1: .windowsCP1252
            case .utf16: .utf16
            }
        }
    }

    var root: URL
    var term = ""
    var mode: Mode = .contains
    var caseSensitive = false
    var contentText = ""
    var encoding: TextEncoding = .utf8
    var includeHidden = false

    /// Für „Zuletzt benutzt“, Tags und intelligente Ordner: Anzeigename statt Ordnername.
    var title: String?
    /// Fertige Spotlight-Abfrage (mdfind-Syntax), z. B. `kMDItemUserTags == "Rot"`. Ersetzt Name/Inhalt.
    var spotlightQuery: String?
    /// Markiert den passenden Eintrag in der Seitenleiste.
    var sidebarTag: URL?

    var isEmpty: Bool {
        spotlightQuery == nil && term.trimmingCharacters(in: .whitespaces).isEmpty && contentText.isEmpty
    }

    /// Spotlight durchsucht dann den ganzen Index (statt nur ab `root`).
    var searchesEverywhere: Bool { root.path == "/" }

    // MARK: Vorgefertigte Abfragen für die Seitenleiste

    static let recentsTag = URL(string: "finderersatz://recents")!

    /// Dateien, die in den letzten 30 Tagen benutzt wurden (wie „Zuletzt benutzt“ im Finder).
    static var recents: SearchQuery {
        var query = SearchQuery(root: FileManager.default.homeDirectoryForCurrentUser)
        query.title = "Zuletzt benutzt"
        query.spotlightQuery = #"kMDItemLastUsedDate >= $time.today(-30) && kMDItemContentType != "public.folder""#
        query.sidebarTag = recentsTag
        return query
    }

    static func tagTag(_ name: String) -> URL {
        URL(string: "finderersatz://tag/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")!
    }

    /// Alle Objekte mit einem Tag (auch unter dem englischen Namen gesetzte Standard-Tags).
    static func tagged(_ name: String, alternative: String? = nil) -> SearchQuery {
        var query = SearchQuery(root: URL(filePath: "/"))
        query.title = "Tag: \(name)"
        let names = [name] + (alternative.map { [$0] } ?? [])
        query.spotlightQuery = names.map { "kMDItemUserTags == \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: " || ")
        query.sidebarTag = tagTag(name)
        return query
    }
}
