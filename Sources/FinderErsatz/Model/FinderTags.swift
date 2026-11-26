import SwiftUI

/// Die sieben Standard-Tags des Finders mit ihren Farben (deutsche und englische Namen).
enum FinderTag: String, CaseIterable, Identifiable {
    case red = "Rot", orange = "Orange", yellow = "Gelb", green = "Grün", blue = "Blau", purple = "Lila", gray = "Grau"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }

    private static let englishNames: [String: FinderTag] = [
        "Red": .red, "Orange": .orange, "Yellow": .yellow, "Green": .green,
        "Blue": .blue, "Purple": .purple, "Gray": .gray, "Grey": .gray,
    ]

    /// Farbe zu einem Tag-Namen (nil bei eigenen Tags ohne Farbe).
    static func color(for name: String) -> Color? {
        (FinderTag(rawValue: name) ?? englishNames[name])?.color
    }

    /// Prüft, ob ein Tag (in irgendeiner Sprache) in der Liste ist.
    func isContained(in names: [String]) -> Bool {
        names.contains { FinderTag(rawValue: $0) == self || Self.englishNames[$0] == self }
    }
}

/// Farbige Punkte für die Tags einer Datei (wie im Finder neben dem Namen).
struct TagDots: View {
    let tags: [String]

    var body: some View {
        let colors = tags.compactMap(FinderTag.color(for:))
        if !colors.isEmpty {
            HStack(spacing: -3) {
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(Color(nsColor: .textBackgroundColor), lineWidth: 1))
                        .frame(width: 9, height: 9)
                }
            }
        }
    }
}
