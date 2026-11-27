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

    /// Billige Größenauskunft: Ohne diese Methode fragt SwiftUI bei jedem Frame des Live-Resize die
    /// `fittingSize` der ganzen AppKit-Hierarchie ab (Auto Layout über drei NSHostingViews) → Ruckeln.
    /// Die Mindestbreite kommt stattdessen über `browser.layoutMinWidth`.
    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: MainSplitViewController, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1200, height: proposal.height ?? 720)
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
    private weak var observedWindow: NSWindow?
    /// Zeitpunkte der Fenster-Größenänderungen während des Ziehens (für die Diagnose)
    private var resizeStamps: [TimeInterval] = []
    static var lastResizeStats = "noch keine Messung (einmal am Fensterrand ziehen)"

    init(browser: BrowserState, inspectorVisible: Bool) {
        self.browser = browser

        sidebarItem = NSSplitViewItem(sidebarWithViewController: MainSplitViewController.host(SidebarView(), name: "Seitenleiste", browser: browser, width: 200))
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)

        contentItem = NSSplitViewItem(viewController: MainSplitViewController.host(PanesArea(), name: "Inhalt", browser: browser, width: 700))
        contentItem.minimumThickness = MainSplitViewController.contentMinWidth
        // Niedrigste Priorität → wird beim Verkleinern/Vergrößern des Fensters zuerst angepasst
        contentItem.holdingPriority = .defaultLow

        inspectorItem = NSSplitViewItem(inspectorWithViewController: MainSplitViewController.host(
            InspectorColumn(), name: "Vorschau-Spalte", browser: browser, width: 300))
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
    private static func host(_ root: some View, name: String, browser: BrowserState, width: CGFloat) -> NSViewController {
        let controller = NSHostingController(rootView: AnyView(root.environment(browser)))
        controller.sizingOptions = []
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        // In einen Messbehälter packen: misst beim Ziehen am Fensterrand, wie lange das Layout dieses Bereichs dauert
        return MeasuredController(child: controller, name: name, width: width)
    }

    /// Tabellen (SwiftUI-`Table` = NSTableView) wie im Finder: beim Ändern der Fensterbreite nur die letzte Spalte
    /// anpassen statt alle Spalten (sonst müssen bei jedem Schritt alle sichtbaren Zellen neu gelayoutet werden).
    /// Abschalten: `defaults write com.example.FinderErsatz tableLastColumnOnly -bool NO`
    static var tableLastColumnOnly: Bool {
        UserDefaults.standard.object(forKey: "tableLastColumnOnly") as? Bool ?? true
    }

    private func adjustTables() {
        guard Self.tableLastColumnOnly else { return }
        for table in Self.subviews(of: NSTableView.self, in: contentItem.viewController.view)
        where table.columnAutoresizingStyle != .lastColumnOnlyAutoresizingStyle {
            table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        }
    }

    private static func subviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        var result: [T] = []
        if let match = view as? T { result.append(match) }
        for sub in view.subviews { result += subviews(of: type, in: sub) }
        return result
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
        observeWindow()
        updateWindowMinSize()
    }

    private func observeWindow() {
        guard let window = view.window, window !== observedWindow else { return }
        let center = NotificationCenter.default
        if let old = observedWindow {
            for name in [NSWindow.willStartLiveResizeNotification, NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
                center.removeObserver(self, name: name, object: old)
            }
        }
        observedWindow = window
        center.addObserver(self, selector: #selector(windowWillStartLiveResize(_:)), name: NSWindow.willStartLiveResizeNotification, object: window)
        center.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: window)
        center.addObserver(self, selector: #selector(windowDidEndLiveResize(_:)), name: NSWindow.didEndLiveResizeNotification, object: window)
    }

    @objc private func windowWillStartLiveResize(_ note: Notification) {
        adjustTables()
        LayoutTimer.reset()
        resizeStamps = [ProcessInfo.processInfo.systemUptime]
    }

    @objc private func windowDidResize(_ note: Notification) {
        if view.window?.inLiveResize == true { resizeStamps.append(ProcessInfo.processInfo.systemUptime) }
    }

    @objc private func windowDidEndLiveResize(_ note: Notification) {
        let intervals = zip(resizeStamps.dropFirst(), resizeStamps).map { ($0 - $1) * 1000 }
        if !intervals.isEmpty {
            let average = intervals.reduce(0, +) / Double(intervals.count)
            let slow = intervals.filter { $0 > 33 }.count
            Self.lastResizeStats = "\(intervals.count) Schritte, Ø \(Int(average)) ms, max \(Int(intervals.max() ?? 0)) ms, \(slow) über 33 ms"
        }
        resizeStamps = []
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
                publishMinWidth(needed)
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
        publishMinWidth(size.width)
    }

    /// An SwiftUI weitergeben (asynchron – kann während eines Layout-/Update-Durchgangs aufgerufen werden)
    private func publishMinWidth(_ width: CGFloat) {
        guard browser.layoutMinWidth != width else { return }
        Task { @MainActor [browser] in
            if browser.layoutMinWidth != width { browser.layoutMinWidth = width }
        }
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
        lines.append("Letztes Ziehen am Fensterrand: \(lastResizeStats)")
        lines.append(contentsOf: LayoutTimer.summary())
        if let controller = current {
            let tables = subviews(of: NSTableView.self, in: controller.contentItem.viewController.view)
            let styles = tables.map { table in
                "\(table.numberOfColumns) Spalten/\(table.rows(in: table.visibleRect).length) sichtbare Zeilen/Stil \(table.columnAutoresizingStyle.rawValue)"
            }
            lines.append("Tabellen im Inhalt: \(tables.count)\(styles.isEmpty ? "" : " – " + styles.joined(separator: "; ")) (Stil 4 = nur letzte Spalte; tableLastColumnOnly = \(tableLastColumnOnly))")
            let panes = [controller.browser.pane(.left), controller.browser.pane(.right)]
            lines.append("Ansicht links/rechts: \(panes.map { "\($0.viewMode)" }.joined(separator: " / ")), Objekte: \(panes.map { String($0.items.count) }.joined(separator: " / ")), Vorschaubereich unten: \(controller.browser.showPanePreview)")
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

/// Hält einen Bereich (NSHostingController) und misst beim Live-Resize die Layout-Zeit seines Teilbaums.
@MainActor
final class MeasuredController: NSViewController {
    private let child: NSViewController
    private let name: String
    private let initialWidth: CGFloat

    init(child: NSViewController, name: String, width: CGFloat) {
        self.child = child
        self.name = name
        self.initialWidth = width
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    override func loadView() {
        let container = MeasuringView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 600))
        container.name = name
        addChild(child)
        child.view.frame = container.bounds
        child.view.autoresizingMask = [.width, .height]
        container.addSubview(child.view)
        container.content = child.view
        view = container
    }
}

@MainActor
final class MeasuringView: NSView {
    var name = ""
    weak var content: NSView?

    override func layout() {
        super.layout()
        guard let content else { return }
        if content.frame != bounds { content.frame = bounds }
        guard window?.inLiveResize == true else { return }
        // Teilbaum jetzt (statt später im selben Durchgang) layouten, damit die Zeit diesem Bereich zugeordnet wird
        let start = ProcessInfo.processInfo.systemUptime
        content.layoutSubtreeIfNeeded()
        LayoutTimer.record(name, ms: (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
}

/// Sammelt Layout-Zeiten je Bereich während eines Live-Resize (für die Layout-Diagnose).
@MainActor
enum LayoutTimer {
    private static var samples: [String: [Double]] = [:]
    private static var order: [String] = []

    static func reset() { samples = [:] }

    static func record(_ name: String, ms: Double) {
        if !order.contains(name) { order.append(name) }
        samples[name, default: []].append(ms)
    }

    static func summary() -> [String] {
        order.compactMap { name in
            guard let values = samples[name], !values.isEmpty else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return "  Layout \(name): \(values.count)×, Ø \(String(format: "%.1f", average)) ms, max \(Int(values.max() ?? 0)) ms"
        }
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
