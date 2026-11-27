import Foundation
import AppKit

/// Führt Befehle der Befehlszeile und der Knopfleiste in der Shell aus.
/// Platzhalter (wie Total Commander „%P%N“, hier kürzer):
///   %s  ausgewählte Objekte (volle Pfade, in Anführungszeichen)   %n  nur deren Namen
///   %p  aktueller Ordner        %o  Ordner des anderen Fensters    %t  Auswahl im anderen Fenster
///   %%  ein Prozentzeichen
enum CommandRunner {
    struct Context: Sendable {
        var folder: URL
        var selection: [URL]
        var otherFolder: URL
        var otherSelection: [URL]
    }

    static let placeholderHelp: [(String, String)] = [
        ("%s", "ausgewählte Objekte (volle Pfade)"),
        ("%n", "Namen der ausgewählten Objekte"),
        ("%p", "aktueller Ordner"),
        ("%o", "Ordner des anderen Fensters"),
        ("%t", "Auswahl im anderen Fenster"),
        ("%%", "ein Prozentzeichen"),
    ]

    /// Für die Shell sicher in einfache Anführungszeichen setzen
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func expand(_ template: String, _ context: Context) -> String {
        var result = ""
        var iterator = template.makeIterator()
        while let character = iterator.next() {
            guard character == "%" else { result.append(character); continue }
            guard let code = iterator.next() else { result.append("%"); break }
            switch code {
            case "s": result += context.selection.map { quote($0.path) }.joined(separator: " ")
            case "n": result += context.selection.map { quote($0.lastPathComponent) }.joined(separator: " ")
            case "p": result += quote(context.folder.path)
            case "o": result += quote(context.otherFolder.path)
            case "t": result += context.otherSelection.map { quote($0.path) }.joined(separator: " ")
            case "%": result += "%"
            default: result += "%" + String(code)
            }
        }
        return result
    }

    struct Result: Sendable {
        var output: String
        var status: Int32
        var truncated: Bool
    }

    /// Läuft in der Login-Shell des Benutzers (PATH wie im Terminal). Abbrechbar über den Task.
    static func run(_ command: String, in folder: URL) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = URL(filePath: FileManager.default.isExecutableFile(atPath: shell) ? shell : "/bin/zsh")
            process.arguments = ["-l", "-c", command]
            process.currentDirectoryURL = folder
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let collector = OutputCollector()
            pipe.fileHandleForReading.readabilityHandler = { collector.append($0.availableData) }
            do {
                try process.run()
            } catch {
                return Result(output: error.localizedDescription, status: -1, truncated: false)
            }
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    return Result(output: collector.text + "\n[abgebrochen]", status: process.terminationStatus, truncated: collector.truncated)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
            return Result(output: collector.text, status: process.terminationStatus, truncated: collector.truncated)
        }.value
    }

    /// Öffnet ein Terminal-Fenster, wechselt in den Ordner und führt den Befehl dort aus (für interaktive Programme).
    /// Beim ersten Mal fragt macOS, ob die App Terminal steuern darf.
    static func runInTerminal(_ command: String, in folder: URL) {
        let shellLine = "cd \(quote(folder.path)) && \(command)"
        let escaped = shellLine
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { AppLauncher.openTerminal(at: folder) }
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var cut = false
        var truncated: Bool { lock.withLock { cut } }
        private static let limit = 2 * 1024 * 1024

        func append(_ chunk: Data) {
            lock.withLock {
                guard !chunk.isEmpty else { return }
                if data.count + chunk.count > Self.limit {
                    data.append(chunk.prefix(max(0, Self.limit - data.count)))
                    cut = true
                } else {
                    data.append(chunk)
                }
            }
        }

        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }
}
