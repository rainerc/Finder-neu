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

    /// Wo gesucht wird – wie im Finder „Dieser Mac“ oder der aktuelle Ordner.
    enum Scope: String, CaseIterable, Identifiable, Sendable, Codable {
        case thisMac, folder
        var id: String { rawValue }
    }

    var root: URL
    var term = ""
    var mode: Mode = .contains
    var caseSensitive = false
    var contentText = ""
    var encoding: TextEncoding = .utf8
    var includeHidden = false
    var scope: Scope = .folder
    /// Zusätzliche Bedingungen wie im Finder (Art, Datum, Größe, Endung, Tag …).
    var criteria: [SearchCriterion] = []
    /// true = alle Bedingungen müssen erfüllt sein, false = mindestens eine.
    var matchAll = true

    /// Für „Zuletzt benutzt“, Tags und intelligente Ordner: Anzeigename statt Ordnername.
    var title: String?
    /// Fertige Spotlight-Abfrage (mdfind-Syntax), z. B. `kMDItemUserTags == "Rot"`. Ersetzt Name/Inhalt.
    var spotlightQuery: String?
    /// Markiert den passenden Eintrag in der Seitenleiste.
    var sidebarTag: URL?

    var isEmpty: Bool {
        spotlightQuery == nil && term.trimmingCharacters(in: .whitespaces).isEmpty && contentText.isEmpty
            && !criteria.contains(where: \.isComplete)
    }

    /// Spotlight durchsucht dann den ganzen Index (statt nur ab `root`).
    var searchesEverywhere: Bool { scope == .thisMac || root.path == "/" }

    init(root: URL) {
        self.root = root
    }

    // Eigenes Decodieren: ältere gespeicherte Suchen (ohne scope/criteria) bleiben lesbar.
    enum CodingKeys: String, CodingKey {
        case root, term, mode, caseSensitive, contentText, encoding, includeHidden, scope, criteria, matchAll,
             title, spotlightQuery, sidebarTag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        root = try c.decode(URL.self, forKey: .root)
        term = try c.decodeIfPresent(String.self, forKey: .term) ?? ""
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .contains
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        contentText = try c.decodeIfPresent(String.self, forKey: .contentText) ?? ""
        encoding = try c.decodeIfPresent(TextEncoding.self, forKey: .encoding) ?? .utf8
        includeHidden = try c.decodeIfPresent(Bool.self, forKey: .includeHidden) ?? false
        scope = try c.decodeIfPresent(Scope.self, forKey: .scope) ?? (root.path == "/" ? .thisMac : .folder)
        criteria = try c.decodeIfPresent([SearchCriterion].self, forKey: .criteria) ?? []
        matchAll = try c.decodeIfPresent(Bool.self, forKey: .matchAll) ?? true
        title = try c.decodeIfPresent(String.self, forKey: .title)
        spotlightQuery = try c.decodeIfPresent(String.self, forKey: .spotlightQuery)
        sidebarTag = try c.decodeIfPresent(URL.self, forKey: .sidebarTag)
    }

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
