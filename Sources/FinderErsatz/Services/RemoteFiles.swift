import Foundation
import Security

/// Gespeicherte FTP/SFTP-Verbindung. Das Passwort liegt im Schlüsselbund, nicht hier.
struct RemoteConnection: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case sftp, ftp, ftps
        var title: String {
            switch self {
            case .sftp: "SFTP (SSH)"
            case .ftp: "FTP"
            case .ftps: "FTPS (FTP mit TLS)"
            }
        }
        var defaultPort: Int { self == .sftp ? 22 : 21 }
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var host: String
    var port: Int
    var user: String
    var path: String = ""

    var keychainAccount: String { "\(kind.rawValue)://\(user)@\(host):\(port)" }
    var label: String { name.isEmpty ? "\(user)@\(host)" : name }
}

struct RemoteEntry: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let isLink: Bool
    let size: Int64
    let modified: Date?
}

/// Passwörter im Schlüsselbund (generisches Passwort, Dienst „Finder-Ersatz Verbindungen“)
enum KeychainStore {
    private static let service = "Finder-Ersatz Verbindungen"

    static func password(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !password.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// FTP/FTPS über `curl`, SFTP über `sftp` (beide bei macOS dabei). SFTP nutzt zuerst SSH-Schlüssel/Agent,
/// sonst das Passwort (über SSH_ASKPASS, nicht in der Befehlszeile sichtbar).
enum RemoteFiles {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Öffentliche Aufrufe

    static func list(_ connection: RemoteConnection, path: String, password: String?) async throws -> [RemoteEntry] {
        let output: String
        switch connection.kind {
        case .sftp:
            output = try await sftp(connection, password: password, commands: ["cd \(quote(path.isEmpty ? "." : path))", "ls -la"])
        case .ftp, .ftps:
            output = try await curl(connection, password: password, arguments: [url(connection, path, directory: true)])
        }
        return parseListing(output)
    }

    /// Aktuelles Verzeichnis nach dem Anmelden (für den Start)
    static func home(_ connection: RemoteConnection, password: String?) async throws -> String {
        guard connection.kind == .sftp else { return connection.path.isEmpty ? "/" : connection.path }
        let output = try await sftp(connection, password: password, commands: ["pwd"])
        for line in output.components(separatedBy: .newlines) {
            if let range = line.range(of: "Remote working directory: ") {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return "/"
    }

    static func download(_ connection: RemoteConnection, password: String?, remotePath: String, isDirectory: Bool, to local: URL) async throws {
        switch connection.kind {
        case .sftp:
            _ = try await sftp(connection, password: password,
                               commands: ["get \(isDirectory ? "-r " : "")-p \(quote(remotePath)) \(quote(local.path))"])
        case .ftp, .ftps:
            guard !isDirectory else { throw Failure(message: "Ordner lassen sich per FTP hier nur einzeln Datei für Datei laden.") }
            _ = try await curl(connection, password: password, arguments: ["-o", local.path, url(connection, remotePath, directory: false)])
        }
    }

    static func upload(_ connection: RemoteConnection, password: String?, local: URL, toFolder remoteFolder: String) async throws {
        let isDirectory = (try? local.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let target = join(remoteFolder, local.lastPathComponent)
        switch connection.kind {
        case .sftp:
            _ = try await sftp(connection, password: password,
                               commands: ["put \(isDirectory ? "-r " : "")-p \(quote(local.path)) \(quote(target))"])
        case .ftp, .ftps:
            guard !isDirectory else { throw Failure(message: "Ordner lassen sich per FTP hier nicht hochladen – bitte SFTP oder einzelne Dateien.") }
            _ = try await curl(connection, password: password,
                               arguments: ["--ftp-create-dirs", "-T", local.path, url(connection, target, directory: false)])
        }
    }

    static func makeFolder(_ connection: RemoteConnection, password: String?, path: String) async throws {
        switch connection.kind {
        case .sftp:
            _ = try await sftp(connection, password: password, commands: ["mkdir \(quote(path))"])
        case .ftp, .ftps:
            _ = try await curl(connection, password: password,
                               arguments: ["-Q", "MKD \(path)", url(connection, "/", directory: true), "-o", "/dev/null"])
        }
    }

    static func delete(_ connection: RemoteConnection, password: String?, path: String, isDirectory: Bool) async throws {
        switch connection.kind {
        case .sftp:
            _ = try await sftp(connection, password: password, commands: ["\(isDirectory ? "rmdir" : "rm") \(quote(path))"])
        case .ftp, .ftps:
            _ = try await curl(connection, password: password,
                               arguments: ["-Q", "\(isDirectory ? "RMD" : "DELE") \(path)", url(connection, "/", directory: true), "-o", "/dev/null"])
        }
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty || folder == "." ? name : (folder.hasSuffix("/") ? folder + name : folder + "/" + name)
    }

    static func parent(of path: String) -> String {
        guard path != "/", !path.isEmpty else { return "/" }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    // MARK: Werkzeuge

    /// sftp im Stapelbetrieb; Fehler bei Befehlen brechen ab (sftp -b)
    private static func sftp(_ connection: RemoteConnection, password: String?, commands: [String]) async throws -> String {
        var arguments = ["-b", "-", "-P", String(connection.port),
                         "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=15"]
        var environment = ProcessInfo.processInfo.environment
        var askpass: URL?
        if let password, !password.isEmpty {
            let script = FileManager.default.temporaryDirectory.appending(path: "fe-askpass-\(UUID().uuidString).sh")
            try "#!/bin/sh\nprintf '%s\\n' \"$FE_REMOTE_PASSWORD\"\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            environment["SSH_ASKPASS"] = script.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
            environment["FE_REMOTE_PASSWORD"] = password
            askpass = script
        } else {
            arguments += ["-o", "BatchMode=yes"]
        }
        defer { if let askpass { try? FileManager.default.removeItem(at: askpass) } }
        arguments.append("\(connection.user)@\(connection.host)")
        let output = try await run("/usr/bin/sftp", arguments, input: commands.joined(separator: "\n") + "\n", environment: environment)
        // sftp wiederholt die Befehle mit „sftp> “ – herausfiltern
        return output.components(separatedBy: .newlines).filter { !$0.hasPrefix("sftp>") }.joined(separator: "\n")
    }

    /// curl mit Zugangsdaten aus einer temporären .netrc (nicht in der Befehlszeile sichtbar)
    private static func curl(_ connection: RemoteConnection, password: String?, arguments: [String]) async throws -> String {
        let netrc = FileManager.default.temporaryDirectory.appending(path: "fe-netrc-\(UUID().uuidString)")
        let login = connection.user.isEmpty ? "anonymous" : connection.user
        try "machine \(connection.host) login \(login) password \(password ?? "")\n".write(to: netrc, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: netrc.path)
        defer { try? FileManager.default.removeItem(at: netrc) }
        var base = ["-s", "-S", "--connect-timeout", "15", "--netrc-file", netrc.path]
        if connection.kind == .ftps { base.append("--ssl-reqd") }
        return try await run("/usr/bin/curl", base + arguments, input: nil, environment: ProcessInfo.processInfo.environment)
    }

    private static func url(_ connection: RemoteConnection, _ path: String, directory: Bool) -> String {
        var clean = path.hasPrefix("/") ? path : "/" + path
        if directory, !clean.hasSuffix("/") { clean += "/" }
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean
        return "ftp://\(connection.host):\(connection.port)\(encoded)"
    }

    /// Für sftp-Befehle in doppelte Anführungszeichen
    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    private static func run(_ executable: String, _ arguments: [String], input: String?, environment: [String: String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.environment = environment
            let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = input == nil ? FileHandle.nullDevice : stdin
            let out = Collector(), err = Collector()
            stdout.fileHandleForReading.readabilityHandler = { out.append($0.availableData) }
            stderr.fileHandleForReading.readabilityHandler = { err.append($0.availableData) }
            try process.run()
            if let input {
                stdin.fileHandleForWriting.write(Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
            }
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    throw CancellationError()
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            out.append(stdout.fileHandleForReading.readDataToEndOfFile())
            err.append(stderr.fileHandleForReading.readDataToEndOfFile())
            guard process.terminationStatus == 0 else {
                let message = err.text.trimmingCharacters(in: .whitespacesAndNewlines)
                throw Failure(message: message.isEmpty ? "Verbindung fehlgeschlagen (Code \(process.terminationStatus))." : message)
            }
            return out.text
        }.value
    }

    // MARK: Verzeichnisliste

    nonisolated(unsafe) private static let listingPattern = try! NSRegularExpression(
        pattern: #"^([\-dlbcps])\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w{3}\s+\d{1,2}\s+(?:\d{1,2}:\d{2}|\d{4}))\s(.+)$"#)

    /// Unix-„ls -l“-Format (sftp und die meisten FTP-Server)
    static func parseListing(_ text: String) -> [RemoteEntry] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let currentYear = Calendar.current.component(.year, from: .now)
        var entries: [RemoteEntry] = []
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = listingPattern.firstMatch(in: line, range: range),
                  let typeRange = Range(match.range(at: 1), in: line),
                  let sizeRange = Range(match.range(at: 2), in: line),
                  let dateRange = Range(match.range(at: 3), in: line),
                  let nameRange = Range(match.range(at: 4), in: line) else { continue }
            let type = line[typeRange]
            var name = String(line[nameRange])
            if type == "l", let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
            guard name != ".", name != ".." else { continue }
            let dateText = line[dateRange].split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            var date: Date?
            if dateText.contains(":") {
                formatter.dateFormat = "MMM d HH:mm yyyy"
                date = formatter.date(from: "\(dateText) \(currentYear)")
                if let found = date, found > .now.addingTimeInterval(86_400) {
                    date = Calendar.current.date(byAdding: .year, value: -1, to: found)
                }
            } else {
                formatter.dateFormat = "MMM d yyyy"
                date = formatter.date(from: dateText)
            }
            entries.append(RemoteEntry(name: name, isDirectory: type == "d", isLink: type == "l",
                                       size: Int64(line[sizeRange]) ?? 0, modified: date))
        }
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
