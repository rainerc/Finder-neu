import Foundation

/// Parameter einer Suche im aktuellen Ordner (rekursiv).
struct SearchQuery: Sendable, Equatable {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
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

    enum TextEncoding: String, CaseIterable, Identifiable, Sendable {
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

    var isEmpty: Bool {
        term.trimmingCharacters(in: .whitespaces).isEmpty && contentText.isEmpty
    }
}
