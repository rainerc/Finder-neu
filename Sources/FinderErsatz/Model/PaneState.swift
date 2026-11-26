import Foundation
import Observation

/// Zustand eines einzelnen Dateifensters (linke oder rechte Seite).
@MainActor
@Observable
final class PaneState: Identifiable {
    let id = UUID()

    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    var selection = Set<FileItem.ID>()
    var sortOrder: [KeyPathComparator<FileItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)] {
        didSet { applySort() }
    }
    private(set) var showHidden = false
    private(set) var errorMessage: String?

    /// Tab-Titel: Anzeigename des aktuellen Ordners.
    var title: String {
        currentURL.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: currentURL.path)
    }

    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var watchedURL: URL?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    var selectedItems: [FileItem] { items.filter { selection.contains($0.id) } }

    init(url: URL) {
        self.currentURL = url.normalizedFileURL
        reload()
    }

    // MARK: Navigation

    func navigate(to url: URL) {
        let target = url.normalizedFileURL
        guard target != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = target
        selection.removeAll()
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = previous
        selection.removeAll()
        reload()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        currentURL = next
        selection.removeAll()
        reload()
    }

    func goUp() {
        guard canGoUp else { return }
        let child = currentURL
        navigate(to: currentURL.deletingLastPathComponent())
        selection = [child]
    }

    func toggleHidden() {
        showHidden.toggle()
        reload()
    }

    // MARK: Laden

    func reload() {
        do {
            let loaded = try FileService.contents(of: currentURL, includeHidden: showHidden)
            items = loaded
            errorMessage = nil
            applySort()
            selection.formIntersection(Set(items.map(\.id)))
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
        watchCurrentFolder()
    }

    // MARK: Live-Aktualisierung

    private func watchCurrentFolder() {
        guard watchedURL != currentURL else { return }
        watchedURL = currentURL
        watcher = DirectoryWatcher(url: currentURL) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    /// Fasst schnell aufeinanderfolgende Änderungen zusammen (z. B. beim Kopieren vieler Dateien).
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func applySort() {
        // Ordner immer zuerst, danach nach gewählter Spalte.
        let folders = items.filter(\.isBrowsableFolder).sorted(using: sortOrder)
        let files = items.filter { !$0.isBrowsableFolder }.sorted(using: sortOrder)
        items = folders + files
    }
}
