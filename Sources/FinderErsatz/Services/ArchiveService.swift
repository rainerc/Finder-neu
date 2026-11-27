import Foundation

/// Packen und Entpacken mit den Bordmitteln von macOS (ditto, zip, tar) – ohne Fremdbibliotheken.
/// `tar` (libarchive) entpackt außer tar/gz/bz2/xz auch 7z und viele RAR-Archive.
enum ArchiveService {
    /// Dateiendungen, die als Archiv erkannt werden (Kleinschreibung).
    static let extensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "7z", "rar", "cpio", "xar"]

    static func isArchive(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Name ohne Archiv-Endung(en), z. B. „Fotos.tar.gz“ → „Fotos“.
    static func baseName(of url: URL) -> String {
        var name = url.lastPathComponent
        for _ in 0..<2 {
            let ext = (name as NSString).pathExtension.lowercased()
            guard extensions.contains(ext) else { break }
            name = (name as NSString).deletingPathExtension
        }
        return name.isEmpty ? url.lastPathComponent : name
    }

    /// ZIP-Archiv erstellen. Ein Objekt: wie der Finder per `ditto`; mehrere: per `zip`.
    static func compress(_ sources: [URL], to archive: URL) throws {
        guard let first = sources.first else { return }
        if sources.count == 1 {
            try ProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, archive.path])
        } else {
            let names = sources.map(\.lastPathComponent)
            try ProcessRunner.run("/usr/bin/zip", ["-r", "-y", "-q", archive.path] + names, in: first.deletingLastPathComponent())
        }
    }

    /// Formate zum Packen. RAR kann macOS nur lesen, nicht schreiben.
    enum PackFormat: String, CaseIterable, Identifiable, Sendable {
        case zip, sevenZip = "7z", tarGz = "tar.gz", tarBz2 = "tar.bz2", tarXz = "tar.xz", tar
        var id: String { rawValue }
        var fileExtension: String { rawValue }
        var title: String {
            switch self {
            case .zip: "ZIP"
            case .sevenZip: "7z"
            case .tarGz: "tar.gz (gzip)"
            case .tarBz2: "tar.bz2 (bzip2)"
            case .tarXz: "tar.xz (xz, sehr klein)"
            case .tar: "tar (unkomprimiert)"
            }
        }
    }

    /// Packen in beliebigem Format. ZIP ohne Passwort wie bisher (ditto/zip), mit Passwort per `zip -P`;
    /// 7z und tar.* über libarchive (`tar -a` wählt das Format anhand der Endung).
    static func pack(_ sources: [URL], to archive: URL, format: PackFormat, password: String?) throws {
        guard let first = sources.first else { return }
        let folder = first.deletingLastPathComponent()
        switch format {
        case .zip:
            if let password, !password.isEmpty {
                try ProcessRunner.run("/usr/bin/zip", ["-r", "-y", "-q", "-P", password, archive.path] + sources.map(\.lastPathComponent), in: folder)
            } else {
                try compress(sources, to: archive)
            }
        default:
            // Je Objekt eigenes -C, damit auch Objekte aus verschiedenen Ordnern (Zweigansicht) gehen
            var arguments = ["-a", "-c", "-f", archive.path]
            for source in sources {
                arguments += ["-C", source.deletingLastPathComponent().path, source.lastPathComponent]
            }
            try ProcessRunner.run("/usr/bin/tar", arguments, in: folder)
        }
    }

    /// Shell-Befehl, der den Inhalt eines Archivs auflistet (für die Ausgabe unter den Fenstern)
    static func listCommand(for archive: URL) -> String {
        archive.pathExtension.lowercased() == "zip"
            ? "/usr/bin/unzip -l \(CommandRunner.quote(archive.path))"
            : "/usr/bin/tar -tvf \(CommandRunner.quote(archive.path))"
    }

    /// Entpackt in den (neu angelegten) Zielordner.
    static func extract(_ archive: URL, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if archive.pathExtension.lowercased() == "zip" {
            try ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        } else {
            try ProcessRunner.run("/usr/bin/tar", ["-x", "-f", archive.path, "-C", folder.path])
        }
    }

    /// Ordner für „Archiv wie Ordner öffnen“: entpackte Kopie im temporären Verzeichnis.
    static var browseRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "FinderErsatz-Archive")
    }

    static func browseFolder(for archive: URL) -> URL {
        browseRoot.appending(path: UUID().uuidString).appending(path: baseName(of: archive))
    }

    static func isInsideBrowsedArchive(_ url: URL) -> Bool {
        url.normalizedFileURL.path.hasPrefix(browseRoot.normalizedFileURL.path + "/")
    }
}
