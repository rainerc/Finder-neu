import Foundation
import Observation

/// Ein laufender Kopier-/Verschiebe-Auftrag mit Fortschritt.
@MainActor
@Observable
final class FileJob: Identifiable {
    let id = UUID()
    let title: String
    private(set) var completedBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var currentName = ""
    private(set) var isCancelling = false

    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(title: String) { self.title = title }

    var fraction: Double {
        totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0
    }

    func update(done: Int64, total: Int64, name: String) {
        completedBytes = done
        totalBytes = total
        currentName = name
    }

    func cancel() {
        isCancelling = true
        task?.cancel()
    }
}

/// Warteschlange: Aufträge laufen nacheinander im Hintergrund, die Oberfläche bleibt bedienbar.
@MainActor
@Observable
final class FileOperationQueue {
    private(set) var jobs: [FileJob] = []

    /// Wird nach jedem Auftrag aufgerufen (Fehlermeldung oder nil).
    @ObservationIgnored var onFinish: ((String?) -> Void)?

    /// Vorheriger Auftrag – der neue wartet darauf, damit nichts gleichzeitig auf dieselben Dateien zugreift.
    @ObservationIgnored private var lastTask: Task<Void, Never>?

    func enqueue(title: String, items: [TransferItem]) {
        guard !items.isEmpty else { return }
        let job = FileJob(title: title)
        jobs.append(job)
        let previous = lastTask
        let task = Task.detached { [weak self] in
            await previous?.value
            var errorText: String?
            do {
                try await FileTransfer.run(items) { done, total, name in
                    await job.update(done: done, total: total, name: name)
                }
            } catch is CancellationError {
                // Vom Benutzer abgebrochen
            } catch {
                errorText = error.localizedDescription
            }
            await self?.finish(job, error: errorText)
        }
        job.task = task
        lastTask = task
    }

    private func finish(_ job: FileJob, error: String?) {
        jobs.removeAll { $0.id == job.id }
        onFinish?(error)
    }
}
