import Foundation

/// Git-Status einer Datei bzw. eines Ordners (Ordner: „geändert“, wenn darin etwas geändert ist)
enum GitFileStatus: String, Sendable, Hashable {
    case modified, added, renamed, deleted, untracked, conflicted, ignored

    /// Kurzzeichen wie in VS Code/`git status -s`
    var letter: String {
        switch self {
        case .modified: "M"
        case .added: "A"
        case .renamed: "R"
        case .deleted: "D"
        case .untracked: "U"
        case .conflicted: "!"
        case .ignored: "I"
        }
    }

    var title: String {
        switch self {
        case .modified: "geändert"
        case .added: "neu hinzugefügt"
        case .renamed: "umbenannt"
        case .deleted: "gelöscht"
        case .untracked: "neu (nicht in Git)"
        case .conflicted: "Konflikt"
        case .ignored: "ignoriert"
        }
    }
}

/// Zustand eines Git-Repositorys: Branch, Vorsprung/Rückstand und Status je Pfad (relativ zur Wurzel)
struct GitRepoInfo: Sendable {
    let root: URL
    var branch: String
    var ahead = 0
    var behind = 0
    /// Pfad → Status; Ordner (unverfolgt/ignoriert) enden auf „/“
    var entries: [String: GitFileStatus] = [:]
    /// Ordner, in denen etwas geändert ist (ohne „/“)
    var dirtyFolders: Set<String> = []
    /// Ganze Ordner, die ignoriert bzw. unverfolgt sind (mit „/“)
    var wholeFolders: [(path: String, status: GitFileStatus)] = []

    var summary: String {
        var text = branch
        if ahead > 0 { text += " ↑\(ahead)" }
        if behind > 0 { text += " ↓\(behind)" }
        let changed = entries.values.filter { $0 != .ignored }.count
        if changed > 0 { text += " · \(changed) Änderung\(changed == 1 ? "" : "en")" }
        return text
    }
}

enum GitStatusService {
    /// git suchen, ohne den „Entwicklerwerkzeuge installieren“-Dialog von /usr/bin/git auszulösen
    static let gitPath: String? = {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: path) {
            return path
        }
        let toolsInstalled = fm.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/git")
            || fm.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/git")
        return toolsInstalled ? "/usr/bin/git" : nil
    }()

    /// Nächster Ordner nach oben, der „.git“ enthält
    static func repositoryRoot(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: current.appending(path: ".git").path) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == "/" { return nil }
            current = parent
        }
    }

    static func load(root: URL) -> GitRepoInfo? {
        guard let git = gitPath,
              let output = try? ProcessRunner.run(git, ["-C", root.path, "status", "--porcelain=v1", "-z",
                                                        "--branch", "--ignored", "--untracked-files=normal"]) else { return nil }
        var info = GitRepoInfo(root: root, branch: "")
        var records = output.components(separatedBy: "\0")[...]
        while let record = records.popFirst() {
            guard record.count >= 3 else { continue }
            if record.hasPrefix("## ") {
                parseBranch(String(record.dropFirst(3)), into: &info)
                continue
            }
            let x = record[record.startIndex]
            let y = record[record.index(after: record.startIndex)]
            let path = String(record.dropFirst(3))
            if x == "R" || x == "C" { _ = records.popFirst() }   // ursprünglicher Name folgt
            let status: GitFileStatus
            switch (x, y) {
            case ("?", "?"): status = .untracked
            case ("!", "!"): status = .ignored
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): status = .conflicted
            case ("A", _): status = .added
            case ("R", _), ("C", _): status = .renamed
            case ("D", _), (_, "D"): status = .deleted
            default: status = .modified
            }
            info.entries[path] = status
            if path.hasSuffix("/"), status == .ignored || status == .untracked {
                info.wholeFolders.append((path, status))
            }
            if status != .ignored {
                // Alle übergeordneten Ordner als „darin geändert“ merken
                var components = path.split(separator: "/").dropLast()
                while !components.isEmpty {
                    info.dirtyFolders.insert(components.joined(separator: "/"))
                    components = components.dropLast()
                }
            }
        }
        if info.branch.isEmpty { info.branch = "?" }
        return info
    }

    /// „main...origin/main [ahead 1, behind 2]“ / „No commits yet on main“ / „HEAD (no branch)“
    private static func parseBranch(_ line: String, into info: inout GitRepoInfo) {
        var head = line
        if let bracket = head.range(of: " [") {
            let details = head[bracket.upperBound...].dropLast()
            for part in details.components(separatedBy: ", ") {
                let pieces = part.split(separator: " ")
                guard pieces.count == 2, let number = Int(pieces[1]) else { continue }
                if pieces[0] == "ahead" { info.ahead = number }
                if pieces[0] == "behind" { info.behind = number }
            }
            head = String(head[..<bracket.lowerBound])
        }
        if head.hasPrefix("No commits yet on ") {
            info.branch = String(head.dropFirst("No commits yet on ".count))
        } else if head.hasPrefix("HEAD (no branch)") {
            info.branch = "losgelöster HEAD"
        } else {
            info.branch = head.components(separatedBy: "...").first ?? head
        }
    }

    static func status(for url: URL, isDirectory: Bool, in info: GitRepoInfo) -> GitFileStatus? {
        let rootPath = info.root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        let relative = String(path.dropFirst(rootPath.count + 1))
        if relative == ".git" { return .ignored }
        if let status = info.entries[relative] ?? (isDirectory ? info.entries[relative + "/"] : nil) {
            return status
        }
        // Liegt in einem ganz ignorierten/unverfolgten Ordner
        if let folder = info.wholeFolders.first(where: { relative.hasPrefix($0.path) }) {
            return folder.status
        }
        if isDirectory, info.dirtyFolders.contains(relative) { return .modified }
        return nil
    }
}
