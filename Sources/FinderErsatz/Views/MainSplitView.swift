import SwiftUI
import AppKit

/// Fensterlayout wie in Mail/DEVONthink: AppKit-`NSSplitViewController` mit Seitenleiste, Inhalt (zwei Fenster)
/// und Vorschau-Spalte. Beim Verkleinern des Fensters wird nur der Inhalt schmaler – Seitenleiste und
/// Vorschau-Spalte haben eine höhere Halte-Priorität und behalten ihre Breite.
///
/// Vorher: SwiftUI-`NavigationSplitView` + `.inspector`. Dort ließ sich das Verhalten beim Verkleinern nicht
/// steuern (Seitenleisten wurden zuerst schmaler, Größenänderung ruckelte).
struct MainSplitView: NSViewControllerRepresentable {
    let browser: BrowserState
    /// Wird aus `ContentView.body` übergeben, damit SwiftUI bei Änderung `updateNSViewController` aufruft.
    let inspectorVisible: Bool

    func makeNSViewController(context: Context) -> MainSplitViewController {
        MainSplitViewController(browser: browser, inspectorVisible: inspectorVisible)
    }

    func updateNSViewController(_ controller: MainSplitViewController, context: Context) {
        controller.setInspectorVisible(inspectorVisible)
    }
}

@MainActor
final class MainSplitViewController: NSSplitViewController {
    /// Das zuletzt erzeugte Layout (für Menübefehl „Seitenleiste ein-/ausblenden“ und die Diagnose)
    static weak var current: MainSplitViewController?

    /// Mindestbreite des Inhalts (beide Dateifenster je 240 + Trennlinie)
    static let contentMinWidth: CGFloat = 500
    static let minHeight: CGFloat = 500

    private let browser: BrowserState
    private let sidebarItem: NSSplitViewItem
    private let contentItem: NSSplitViewItem
    private let inspectorItem: NSSplitViewItem
    private var didSetInitialWidths = false

    init(browser: BrowserState, inspectorVisible: Bool) {
        self.browser = browser

        sidebarItem = NSSplitViewItem(sidebarWithViewController: MainSplitViewController.host(SidebarView(), browser: browser, width: 200))
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)

        contentItem = NSSplitViewItem(viewController: MainSplitViewController.host(PanesArea(), browser: browser, width: 700))
        contentItem.minimumThickness = MainSplitViewController.contentMinWidth
        // Niedrigste Priorität → wird beim Verkleinern/Vergrößern des Fensters zuerst angepasst
        contentItem.holdingPriority = .defaultLow

        inspectorItem = NSSplitViewItem(inspectorWithViewController: MainSplitViewController.host(
            InspectorColumn(), browser: browser, width: 300))
        inspectorItem.minimumThickness = 220
        inspectorItem.maximumThickness = 480
        // Nur per Knopf/Menü (⇧⌘P) ein-/ausblenden, nicht durch Ziehen – so bleibt `showInspector` stimmig.
        inspectorItem.canCollapse = false
        inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        inspectorItem.isCollapsed = !inspectorVisible

        super.init(nibName: nil, bundle: nil)
        Self.current = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    /// SwiftUI-Inhalt ohne eigene Größenvorgaben: Breite bestimmt allein die Split-View
    /// (sonst drückt SwiftUI Mindest-/Idealgrößen als Constraints hinein → Ruckeln, falsche Bereiche schrumpfen).
    private static func host(_ root: some View, browser: BrowserState, width: CGFloat) -> NSViewController {
        let controller = NSHostingController(rootView: AnyView(root.environment(browser)))
        controller.sizingOptions = []
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)
        NotificationCenter.default.addObserver(self, selector: #selector(splitViewDidResize(_:)),
                                               name: NSSplitView.didResizeSubviewsNotification, object: splitView)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !didSetInitialWidths {
            didSetInitialWidths = true
            splitView.setPosition(200, ofDividerAt: 0)
            if !inspectorItem.isCollapsed {
                splitView.setPosition(splitView.bounds.width - 300 - splitView.dividerThickness, ofDividerAt: 1)
            }
        }
        updateWindowMinSize()
    }

    func setInspectorVisible(_ visible: Bool) {
        guard inspectorItem.isCollapsed == visible else { return }
        // Reicht der Platz nicht, das Fenster vorher verbreitern (wie Mail) statt den Inhalt zu quetschen.
        if visible, let window = view.window {
            let needed = Self.contentMinWidth + sideWidth(includingInspector: false)
                + inspectorWidthWhenShown + splitView.dividerThickness
            let content = window.contentRect(forFrameRect: window.frame)
            if content.width < needed {
                var frame = window.frame
                frame.size.width += needed - content.width
                if let screen = window.screen?.visibleFrame, frame.maxX > screen.maxX {
                    frame.origin.x = max(screen.minX, screen.maxX - frame.width)
                }
                window.contentMinSize.width = needed
                window.setFrame(frame, display: true, animate: false)
            }
        }
        inspectorItem.animator().isCollapsed = !visible
    }

    @objc func toggleSidebarFromMenu() {
        toggleSidebar(nil)
    }

    private var inspectorWidthWhenShown: CGFloat {
        let width = inspectorItem.viewController.view.frame.width
        return min(max(width, inspectorItem.minimumThickness), inspectorItem.maximumThickness)
    }

    /// Breite von Seitenleiste (und ggf. Vorschau-Spalte) samt Trennlinien
    private func sideWidth(includingInspector: Bool) -> CGFloat {
        var width: CGFloat = 0
        if !sidebarItem.isCollapsed {
            width += sidebarItem.viewController.view.frame.width + splitView.dividerThickness
        }
        if includingInspector, !inspectorItem.isCollapsed {
            width += inspectorItem.viewController.view.frame.width + splitView.dividerThickness
        }
        return width
    }

    @objc private func splitViewDidResize(_ note: Notification) {
        updateWindowMinSize()
    }

    /// Fenster nie schmaler als: aktuelle Seitenleiste + Mindestinhalt + aktuelle Vorschau-Spalte.
    /// Während des Ziehens am Fensterrand bleibt der Wert fest (sonst ruckelt es).
    private func updateWindowMinSize() {
        guard let window = view.window, !window.inLiveResize else { return }
        let size = NSSize(width: ceil(Self.contentMinWidth + sideWidth(includingInspector: true)), height: Self.minHeight)
        if window.contentMinSize != size { window.contentMinSize = size }
    }

    // MARK: Diagnose

    /// Text für „Hilfe → Layout-Diagnose kopieren“ (Rainer kann ihn bei Problemen schicken).
    static func diagnosticReport() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        var lines = [
            "Finder-Ersatz Build \(info["CFBundleVersion"] as? String ?? "?"), Commit \(info["FEGitCommit"] as? String ?? "?")",
            "Layout: NSSplitViewController (MainSplitView)",
        ]
        guard let controller = current, let window = controller.view.window else {
            lines.append("Kein Hauptfenster gefunden")
            return lines.joined(separator: "\n")
        }
        lines.append("Fenster: \(format(window.frame.size)), contentMinSize: \(format(window.contentMinSize)), minSize: \(format(window.minSize)), inLiveResize: \(window.inLiveResize)")
        let names = ["Seitenleiste", "Inhalt", "Vorschau-Spalte"]
        for (index, item) in controller.splitViewItems.enumerated() {
            let name = index < names.count ? names[index] : "Element \(index)"
            lines.append("\(name): Breite \(Int(item.viewController.view.frame.width)), min \(Int(item.minimumThickness)), max \(item.maximumThickness < 0 ? "–" : String(Int(item.maximumThickness))), Halte-Priorität \(Int(item.holdingPriority.rawValue)), eingeklappt: \(item.isCollapsed)")
        }
        // Alle Split-Views im Fenster (auch die SwiftUI-HSplitView der beiden Dateifenster)
        if let root = window.contentView {
            for split in splitViews(in: root) {
                let widths = split.arrangedSubviews.map { String(Int($0.frame.width)) }.joined(separator: " | ")
                lines.append("NSSplitView \(type(of: split)) (Delegate \(split.delegate.map { String(describing: type(of: $0)) } ?? "–")): \(widths)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ size: NSSize) -> String { "\(Int(size.width))×\(Int(size.height))" }

    private static func splitViews(in view: NSView) -> [NSSplitView] {
        var result: [NSSplitView] = []
        if let split = view as? NSSplitView { result.append(split) }
        for sub in view.subviews { result += splitViews(in: sub) }
        return result
    }
}

/// Vorschau-Spalte: nur aufgebaut, wenn sichtbar (sonst würde sie im eingeklappten Zustand weiter Vorschauen laden).
private struct InspectorColumn: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        ZStack {
            if browser.showInspector {
                InspectorView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Mittlerer Bereich: zwei Dateifenster, Aufträge, Aktionsleiste.
struct PanesArea: View {
    @Environment(BrowserState.self) private var browser
    @FocusState private var focusedPane: PaneSide?

    var body: some View {
        VStack(spacing: 0) {
            if AppEnvironment.isRunningUnbundled {
                UnbundledBanner()
                Divider()
            }
            HSplitView {
                PaneView(side: .left, focus: $focusedPane)
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                PaneView(side: .right, focus: $focusedPane)
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            JobsPanel(queue: browser.operations)
            if browser.settings.showActionBar {
                ActionBar()
            } else if let message = browser.flashMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedPane = browser.activeSide }
        .onChange(of: focusedPane) { _, side in
            if let side { browser.activeSide = side }
        }
        .onChange(of: browser.activeSide) { _, side in focusedPane = side }
    }
}
