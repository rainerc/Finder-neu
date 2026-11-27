import Foundation

/// Dateien in Teile aufteilen (name.001, name.002 …) und wieder zusammenfügen – wie im Total Commander.
enum FileSplitter {
    private static let bufferSize = 4 * 1024 * 1024

    /// Teilt `source` in Stücke zu `partSize` Bytes in den Ordner `folder`. Liefert die erzeugten Teile.
    @discardableResult
    static func split(_ source: URL, partSize: Int64, into folder: URL, progress: FileTransfer.Progress) async throws -> [URL] {
        let total = Int64((try source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard partSize > 0 else { return [] }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let partCount = max(1, Int((total + partSize - 1) / partSize))
        let digits = max(3, String(partCount).count)
        var parts: [URL] = []
        var done: Int64 = 0
        for index in 1...partCount {
            try Task.checkCancellation()
            let number = String(repeating: "0", count: max(0, digits - String(index).count)) + String(index)
            let part = folder.appending(path: "\(source.lastPathComponent).\(number)")
            guard !FileManager.default.fileExists(atPath: part.path) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "„\(part.lastPathComponent)“ gibt es im Ziel schon."])
            }
            FileManager.default.createFile(atPath: part.path, contents: nil)
            let output = try FileHandle(forWritingTo: part)
            var written: Int64 = 0
            while written < partSize {
                try Task.checkCancellation()
                let chunk = Int(min(Int64(bufferSize), partSize - written))
                guard let data = try input.read(upToCount: chunk), !data.isEmpty else { break }
                try output.write(contentsOf: data)
                written += Int64(data.count)
                done += Int64(data.count)
                await progress(done, total, part.lastPathComponent)
            }
            try output.close()
            parts.append(part)
        }
        return parts
    }

    /// Alle Teile zu einer Datei: name.001 → name.002 … (lückenlos ab der ausgewählten Nummer)
    static func parts(startingWith first: URL) -> [URL] {
        let ext = first.pathExtension
        guard let start = Int(ext), ext.allSatisfy(\.isNumber) else { return [] }
        let base = first.deletingPathExtension()
        var result: [URL] = []
        var index = start
        while true {
            let number = String(repeating: "0", count: max(0, ext.count - String(index).count)) + String(index)
            let candidate = base.appendingPathExtension(number)
            guard FileManager.default.fileExists(atPath: candidate.path) else { break }
            result.append(candidate)
            index += 1
        }
        return result
    }

    static func join(_ parts: [URL], to target: URL, progress: FileTransfer.Progress) async throws {
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "„\(target.lastPathComponent)“ gibt es im Ziel schon."])
        }
        let total = parts.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        var done: Int64 = 0
        do {
            for part in parts {
                let input = try FileHandle(forReadingFrom: part)
                defer { try? input.close() }
                while let data = try input.read(upToCount: bufferSize), !data.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: data)
                    done += Int64(data.count)
                    await progress(done, total, target.lastPathComponent)
                }
            }
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }
}
