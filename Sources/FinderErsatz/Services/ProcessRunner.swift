import Foundation

/// Startet Kommandozeilen-Werkzeuge (ditto, tar, zip, mdfind) und wartet auf das Ende.
/// Synchron – aus einem Hintergrund-Task aufrufen. Wird der Task abgebrochen, wird der Prozess beendet.
enum ProcessRunner {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
        var value: Data { lock.withLock { data } }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let out = Collector(), err = Collector()
        stdout.fileHandleForReading.readabilityHandler = { out.append($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { err.append($0.availableData) }

        try process.run()
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit()
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        out.append(stdout.fileHandleForReading.readDataToEndOfFile())
        err.append(stderr.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else {
            let tool = (executable as NSString).lastPathComponent
            let message = String(decoding: err.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: "\(tool) ist fehlgeschlagen (Code \(process.terminationStatus)): \(message)")
        }
        return String(decoding: out.value, as: UTF8.self)
    }
}
