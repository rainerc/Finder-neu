import Foundation

/// Übernimmt Server aus dem FileZilla-Server-Manager (`~/.config/filezilla/sitemanager.xml` oder eine
/// über „Datei → Exportieren …“ gesicherte XML-Datei). Passwörter (Base64) gehen in den Schlüsselbund;
/// mit FileZilla-Masterpasswort verschlüsselte Passwörter werden beim ersten Verbinden abgefragt.
enum FileZillaImport {
    struct Site {
        var connection: RemoteConnection
        var password: String?
    }

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/filezilla/sitemanager.xml")
    }

    static func sites(from file: URL) throws -> [Site] {
        let document = try XMLDocument(contentsOf: file, options: [])
        guard let root = document.rootElement() else { return [] }
        var result: [Site] = []
        collect(root, folder: [], into: &result)
        return result
    }

    private static func collect(_ element: XMLElement, folder: [String], into result: inout [Site]) {
        for child in element.children ?? [] {
            guard let child = child as? XMLElement else { continue }
            switch child.name {
            case "Servers":
                collect(child, folder: folder, into: &result)
            case "Folder":
                // Ordnername steht als Text direkt im <Folder>-Element (vor den Kindern)
                let name = (child.children ?? [])
                    .filter { $0.kind == .text }
                    .compactMap(\.stringValue)
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                collect(child, folder: name.isEmpty ? folder : folder + [name], into: &result)
            case "Server":
                if let site = site(from: child, folder: folder) { result.append(site) }
            default:
                break
            }
        }
    }

    private static func value(_ element: XMLElement, _ name: String) -> String? {
        element.elements(forName: name).first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func site(from server: XMLElement, folder: [String]) -> Site? {
        guard let host = value(server, "Host"), !host.isEmpty else { return nil }
        // Protocol: 0 FTP (TLS wenn möglich), 1 SFTP, 3 FTPS implizit, 4 FTPES explizit, 6 FTP unverschlüsselt
        let kind: RemoteConnection.Kind
        switch Int(value(server, "Protocol") ?? "0") ?? 0 {
        case 1: kind = .sftp
        case 3, 4: kind = .ftps
        default: kind = .ftp
        }
        let port = Int(value(server, "Port") ?? "") ?? kind.defaultPort
        let logonType = Int(value(server, "Logontype") ?? "1") ?? 1
        let user = logonType == 0 ? "anonymous" : (value(server, "User") ?? "")
        let name = value(server, "Name") ?? host
        var password: String?
        if let pass = server.elements(forName: "Pass").first, let text = pass.stringValue, !text.isEmpty {
            let encoding = pass.attribute(forName: "encoding")?.stringValue
            if encoding == "base64" {
                password = Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) }
            } else if encoding == nil {
                password = text   // alte Versionen: Klartext
            }   // "crypt" = Masterpasswort, nicht lesbar
        }
        let connection = RemoteConnection(
            name: (folder + [name]).joined(separator: " / "),
            kind: kind, host: host, port: port, user: user,
            path: remotePath(value(server, "RemoteDir") ?? ""))
        return Site(connection: connection, password: password)
    }

    /// FileZillas Pfadformat: „Typ Präfixlänge [Präfix] Länge Teil Länge Teil …“, z. B. „1 0 4 home 3 bob“ → /home/bob
    static func remotePath(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var rest = Substring(text)
        func number() -> Int? {
            rest = rest.drop { $0 == " " }
            let digits = rest.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            rest = rest.dropFirst(digits.count)
            return value
        }
        func chunk(_ length: Int) -> String? {
            guard rest.first == " " else { return nil }
            rest = rest.dropFirst()
            guard rest.count >= length else { return nil }
            let part = rest.prefix(length)
            rest = rest.dropFirst(length)
            return String(part)
        }
        guard number() != nil, let prefixLength = number() else { return "" }
        if prefixLength > 0, chunk(prefixLength) == nil { return "" }
        var segments: [String] = []
        while let length = number(), let segment = chunk(length) {
            segments.append(segment)
        }
        return "/" + segments.joined(separator: "/")
    }
}
