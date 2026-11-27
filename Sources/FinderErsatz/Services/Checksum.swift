import Foundation
import CryptoKit

/// Prüfsummen (MD5, SHA-1, SHA-256, SHA-512) wie im Total Commander – berechnen und aus .md5/.sha*-Dateien prüfen.
enum Checksum {
    enum Algorithm: String, CaseIterable, Identifiable, Sendable {
        case md5, sha1, sha256, sha512
        var id: String { rawValue }
        var title: String {
            switch self {
            case .md5: "MD5"
            case .sha1: "SHA-1"
            case .sha256: "SHA-256"
            case .sha512: "SHA-512"
            }
        }
        /// Endung der Prüfsummendatei
        var fileExtension: String { rawValue }

        /// Erkennt das Verfahren an der Länge der Hex-Zeichenkette
        init?(hexLength: Int) {
            switch hexLength {
            case 32: self = .md5
            case 40: self = .sha1
            case 64: self = .sha256
            case 128: self = .sha512
            default: return nil
            }
        }
    }

    /// Prüfsumme einer Datei, blockweise gelesen (auch große Dateien). Abbrechbar.
    static func compute(_ algorithm: Algorithm, of url: URL) throws -> String {
        switch algorithm {
        case .md5: try hash(Insecure.MD5.self, url)
        case .sha1: try hash(Insecure.SHA1.self, url)
        case .sha256: try hash(SHA256.self, url)
        case .sha512: try hash(SHA512.self, url)
        }
    }

    private static func hash<H: HashFunction>(_ type: H.Type, _ url: URL) throws -> String {
        var hasher = H()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1 << 20), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Ist das eine Prüfsummendatei (.md5, .sha1, .sha256, .sha512)?
    static func isChecksumFile(_ url: URL) -> Bool {
        Algorithm(rawValue: url.pathExtension.lowercased()) != nil
    }

    struct Entry: Sendable, Identifiable {
        let id = UUID()
        let name: String
        let expected: String
        let algorithm: Algorithm
    }

    /// Liest Zeilen im GNU-Format („hash  name“ bzw. „hash *name“) und BSD-Format („SHA256 (name) = hash“).
    static func parse(_ text: String, fallback: Algorithm?) -> [Entry] {
        var entries: [Entry] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close,
               let equals = line.range(of: "=", range: close..<line.endIndex) {
                // BSD: SHA256 (datei.txt) = abc…
                let name = String(line[line.index(after: open)..<close])
                let hash = line[equals.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
                if let algorithm = Algorithm(hexLength: hash.count) ?? fallback {
                    entries.append(Entry(name: name, expected: hash, algorithm: algorithm))
                }
                continue
            }
            // GNU: abc…  datei.txt
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let hash = String(line[..<space]).lowercased()
            var name = line[space...].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            guard hash.allSatisfy(\.isHexDigit), let algorithm = Algorithm(hexLength: hash.count) ?? fallback else { continue }
            entries.append(Entry(name: name, expected: hash, algorithm: algorithm))
        }
        return entries
    }

    /// Inhalt einer Prüfsummendatei im GNU-Format (wie `shasum`/`md5sum`)
    static func fileContents(_ results: [(name: String, hash: String)]) -> String {
        results.map { "\($0.hash)  \($0.name)" }.joined(separator: "\n") + "\n"
    }
}
