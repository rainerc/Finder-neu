import AppKit
import Quartz

/// Natives Quick-Look-Fenster (QLPreviewPanel) wie im Finder.
/// Ersetzt SwiftUIs `.quickLookPreview`, das bei Ordnern (z. B. mit XRay) sehr lange zum Öffnen brauchte.
///
/// Der Controller hängt sich in die Responder-Kette des Hauptfensters, damit das Panel ihn als Steuerung findet.
/// Pfeiltasten im Panel werden ans Hauptfenster weitergereicht (Auswahl wandert mit, wie im Finder).
@MainActor
final class QuickLookController: NSResponder, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    /// Wird nur auf dem Main-Thread geändert; das Panel liest es ebenfalls auf dem Main-Thread.
    nonisolated(unsafe) private var urls: [URL] = []
    private weak var sourceWindow: NSWindow?

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    func toggle(_ urls: [URL]) {
        if isVisible {
            QLPreviewPanel.shared()?.orderOut(nil)
        } else {
            show(urls)
        }
    }

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let panel = QLPreviewPanel.shared() else { return }
        install(in: window)
        self.urls = urls
        // Falls das Panel uns schon als Steuerung kennt: direkt verbinden.
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    /// Auswahl hat sich geändert, während das Panel offen ist.
    func update(_ urls: [URL]) {
        guard isVisible, !urls.isEmpty, urls != self.urls, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    private func install(in window: NSWindow) {
        sourceWindow = window
        var responder: NSResponder? = window.nextResponder
        while let current = responder {
            if current === self { return }
            responder = current.nextResponder
        }
        nextResponder = window.nextResponder
        window.nextResponder = self
    }

    // MARK: QLPreviewPanelController (informelles Protokoll über die Responder-Kette)

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel?.dataSource = self
            panel?.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel?.dataSource = nil
            panel?.delegate = nil
        }
    }

    // MARK: Datenquelle

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }

    // MARK: Tastatur im Panel

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        nonisolated(unsafe) let keyEvent = event
        return MainActor.assumeIsolated {
            switch keyEvent.keyCode {
            case 49:   // Leertaste schließt
                QLPreviewPanel.shared()?.orderOut(nil)
                return true
            case 123, 124, 125, 126:   // Pfeiltasten: Auswahl im Dateifenster bewegen
                guard urls.count <= 1, let window = sourceWindow else { return false }
                window.sendEvent(keyEvent)
                return true
            default:
                return false
            }
        }
    }
}
