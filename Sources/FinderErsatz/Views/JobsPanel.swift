import SwiftUI

/// Zeigt laufende Kopier-/Verschiebe-Aufträge mit Fortschritt und Abbrechen-Knopf.
struct JobsPanel: View {
    let queue: FileOperationQueue

    var body: some View {
        if !queue.jobs.isEmpty {
            VStack(spacing: 6) {
                ForEach(queue.jobs) { job in
                    JobRow(job: job)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
        }
    }
}

private struct JobRow: View {
    let job: FileJob

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(job.title).font(.callout)
                    Spacer()
                    if job.totalBytes > 0 {
                        Text(progressText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if job.totalBytes > 0 {
                    ProgressView(value: job.fraction).progressViewStyle(.linear)
                } else {
                    ProgressView().progressViewStyle(.linear)   // unbestimmt (z. B. Packen)
                }
                Text(job.isCancelling ? "Wird abgebrochen …" : job.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Abbrechen", systemImage: "xmark.circle.fill") { job.cancel() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(job.isCancelling)
        }
    }

    private var progressText: String {
        let done = job.completedBytes.formatted(.byteCount(style: .file))
        let total = job.totalBytes.formatted(.byteCount(style: .file))
        return "\(done) von \(total)"
    }
}
