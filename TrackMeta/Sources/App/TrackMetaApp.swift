import SwiftUI
import AppKit

@main
struct TrackMetaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageViewModel()

    private var statusItem: NSStatusItem?

    /// One pill panel per display (keyed by `CGDirectDisplayID`) so the
    /// notch UI shows on every connected screen simultaneously.
    private var pillPanels: [CGDirectDisplayID: NotchPillPanel] = [:]
    private var pillHostings: [CGDirectDisplayID: NSHostingController<NotchPillContainer>] = [:]
    private var pillSizeObservations: [CGDirectDisplayID: NSKeyValueObservation] = [:]
    private var screenParamsObserver: NSObjectProtocol?
    private var globalHotkey: GlobalHotkey?

    private var dashboardWindow: NSWindow?
    private var dashboardPinned: Bool = UserDefaults.standard.bool(forKey: "TrackMeta.dashboardPinned")
    private static let pinnedKey = "TrackMeta.dashboardPinned"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let host = NSHostingView(rootView: MenuBarLabelContainer(model: model))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.target = self
            button.action = #selector(toggleDashboard(_:))
        }
        statusItem = item

        globalHotkey = GlobalHotkey { [weak self] in
            self?.toggleDashboard(nil)
        }

        updatePillPresentation()
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updatePillPresentation() }
        }
    }

    @objc private func toggleDashboard(_ sender: Any?) {
        if let window = dashboardWindow, window.isVisible {
            window.close()
            return
        }
        openDashboard()
    }

    private func openDashboard() {
        NSApp.setActivationPolicy(.regular)

        if let window = dashboardWindow {
            applyPinnedBehavior(to: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: makeDashboardRoot())
        // Don't let SwiftUI's fitting size drive the window — we want a full
        // dashboard-sized window, not one that shrink-wraps the content.
        host.sizingOptions = []

        let initialSize = NSSize(width: 920, height: 700)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TrackMeta Dashboard"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0x0B/255.0, green: 0x11/255.0, blue: 0x1E/255.0, alpha: 1.0)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = host
        window.setContentSize(initialSize)
        window.minSize = NSSize(width: 720, height: 540)
        window.center()
        window.delegate = dashboardWindowDelegate

        dashboardWindow = window
        applyPinnedBehavior(to: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeDashboardRoot() -> DashboardView {
        DashboardView(
            model: model,
            onTogglePinSessions: { [weak self] in
                Task { @MainActor in self?.model.sessionsPinned.toggle() }
            },
            isWindowPinned: dashboardPinned,
            onToggleWindowPin: { [weak self] in
                Task { @MainActor in self?.toggleDashboardPinned() }
            }
        )
    }

    private func toggleDashboardPinned() {
        dashboardPinned.toggle()
        UserDefaults.standard.set(dashboardPinned, forKey: Self.pinnedKey)
        if let window = dashboardWindow {
            applyPinnedBehavior(to: window)
        }
        refreshDashboardRoot()
    }

    /// Raises the dashboard above other apps when pinned, otherwise restores
    /// normal window behavior.
    private func applyPinnedBehavior(to window: NSWindow) {
        if dashboardPinned {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
        }
    }

    private func refreshDashboardRoot() {
        guard let host = dashboardWindow?.contentViewController as? NSHostingController<DashboardView> else { return }
        host.rootView = makeDashboardRoot()
    }

    private func dashboardDidClose() {
        dashboardWindow = nil
        updateActivationPolicy()
    }

    private lazy var dashboardWindowDelegate: DashboardWindowDelegate = {
        DashboardWindowDelegate { [weak self] in
            Task { @MainActor in self?.dashboardDidClose() }
        }
    }()

    /// Returns to accessory (no Dock icon) when the dashboard window is closed.
    private func updateActivationPolicy() {
        if dashboardWindow?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func toggleSessionsPinned() {
        model.sessionsPinned.toggle()
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// True if the given screen is the built-in (laptop) display.
    private static func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    /// Width of the synthetic notch rendered on external (non-built-in) displays
    /// so the pill behaves the same as on a notched MacBook.
    private static let virtualNotchWidth: CGFloat = 200

    /// Returns the notch's frame in screen coordinates.
    private static func notchFrame(on screen: NSScreen?) -> NSRect? {
        guard let screen else { return nil }
        if isBuiltInDisplay(screen) {
            guard screen.safeAreaInsets.top > 0 else { return nil }
            let left = screen.auxiliaryTopLeftArea ?? .zero
            let right = screen.auxiliaryTopRightArea ?? .zero
            guard left.width > 0, right.width > 0 else { return nil }
            let minX = left.maxX
            let maxX = right.minX
            let y = screen.frame.maxY - screen.safeAreaInsets.top
            return NSRect(x: minX, y: y, width: maxX - minX, height: screen.safeAreaInsets.top)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard menuBarHeight > 0 else { return nil }
        let width = virtualNotchWidth
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - menuBarHeight
        return NSRect(x: x, y: y, width: width, height: menuBarHeight)
    }

    // MARK: - Notch pill

    /// Shows one collapsed pill per connected display that has a real or
    /// synthetic notch. The menu-bar status item is hidden whenever at least
    /// one pill is shown, so the indicator never appears in two places.
    /// Displays without a notch (older built-in) keep the classic status item.
    private func updatePillPresentation() {
        let targets: [(screen: NSScreen, notch: NSRect, id: CGDirectDisplayID)] =
            NSScreen.screens.compactMap { screen in
                guard let notch = Self.notchFrame(on: screen),
                      let id = Self.displayID(for: screen) else { return nil }
                return (screen, notch, id)
            }

        let activeIDs = Set(targets.map(\.id))
        for (id, panel) in pillPanels where !activeIDs.contains(id) {
            panel.orderOut(nil)
            pillPanels.removeValue(forKey: id)
            pillHostings.removeValue(forKey: id)
            pillSizeObservations[id]?.invalidate()
            pillSizeObservations.removeValue(forKey: id)
        }

        if targets.isEmpty {
            statusItem?.button?.isHidden = false
            return
        }
        statusItem?.button?.isHidden = true
        for target in targets {
            showPill(notch: target.notch, on: target.screen, id: target.id)
        }
    }

    private func showPill(notch: NSRect, on screen: NSScreen, id: CGDirectDisplayID) {
        let container = NotchPillContainer(
            model: model,
            notchWidth: notch.width,
            onTap: { [weak self] in
                Task { @MainActor in self?.openDashboard() }
            },
            onUnpin: { [weak self] in
                Task { @MainActor in self?.toggleSessionsPinned() }
            }
        )

        let host: NSHostingController<NotchPillContainer>
        if let existing = pillHostings[id] {
            existing.rootView = container
            host = existing
        } else {
            host = NSHostingController(rootView: container)
            pillHostings[id] = host
        }
        host.sizingOptions = .preferredContentSize

        let panel = pillPanels[id] ?? NotchPillPanel(
            contentRect: NSRect(x: 0, y: 0, width: notch.width, height: 14),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = model.sessionsPinned
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.centerX = notch.midX
        panel.topY = notch.minY + 2
        panel.contentViewController = host
        pillPanels[id] = panel

        host.view.wantsLayer = true
        host.view.layer?.masksToBounds = false

        pillSizeObservations[id]?.invalidate()
        pillSizeObservations[id] = host.observe(\.preferredContentSize, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.repositionPill(notch: notch, id: id, animate: false)
            }
        }

        repositionPill(notch: notch, id: id)
        panel.orderFrontRegardless()
    }

    private func repositionPill(notch: NSRect, id: CGDirectDisplayID, animate: Bool = true) {
        guard let panel = pillPanels[id], let host = pillHostings[id] else { return }
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.view.fittingSize
        let width = max(fitting.width, notch.width)
        let height = max(fitting.height, 14)
        let x = notch.midX - width / 2
        let y = notch.minY - height + 2
        let target = NSRect(
            x: x.rounded(),
            y: y.rounded(),
            width: width,
            height: height
        )
        let shouldAnimate = animate && panel.isVisible && panel.frame != target
        panel.setFrame(target, display: true, animate: shouldAnimate)
    }
}

final class NotchPillPanel: NSPanel {
    /// Horizontal center the panel should always align to — matches `notch.midX`
    /// for the display this panel lives on. Set by `showPill` before the panel
    /// is made visible.
    var centerX: CGFloat?
    /// Screen-space Y the panel's top edge should always align to — matches
    /// `notch.minY + 2` for the display this panel lives on.
    var topY: CGFloat?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Any resize path — our `repositionPill`, `sizingOptions = .preferredContentSize`
    // auto-resize, or AppKit internal — must leave the panel centered on
    // `centerX` and anchored at `topY`.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(reanchored(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(reanchored(frameRect), display: flag, animate: animateFlag)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(reanchoredOrigin(for: frame.size))
    }

    override func setContentSize(_ size: NSSize) {
        let contentDelta = NSSize(
            width: frame.width - contentRect(forFrameRect: frame).width,
            height: frame.height - contentRect(forFrameRect: frame).height
        )
        let newSize = NSSize(
            width: size.width + contentDelta.width,
            height: size.height + contentDelta.height
        )
        let rect = NSRect(origin: frame.origin, size: newSize)
        super.setFrame(reanchored(rect), display: true)
    }

    private func reanchored(_ rect: NSRect) -> NSRect {
        var r = rect
        r.origin = reanchoredOrigin(for: r.size)
        return r
    }

    private func reanchoredOrigin(for size: NSSize) -> NSPoint {
        var origin = frame.origin
        if let centerX {
            origin.x = (centerX - size.width / 2).rounded()
        }
        if let topY {
            origin.y = (topY - size.height).rounded()
        }
        return origin
    }
}

struct NotchPillContainer: View {
    @Bindable var model: UsageViewModel
    let notchWidth: CGFloat
    let onTap: () -> Void
    let onUnpin: () -> Void

    // Fixed container width so toggling between collapsed/expanded sessions
    // doesn't change the panel's preferred size (prevents AppKit left-jumps).
    private let containerWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            NotchPillView(snapshot: model.snapshot, action: onTap)
                .frame(width: notchWidth, height: 14)

            sessionsLayer
                .padding(.top, 2)
        }
        .frame(width: containerWidth)
    }

    /// The conditional sessions UI lives in its own animation scope so the
    /// pill above is never a descendant of a springing `.animation` modifier.
    @ViewBuilder
    private var sessionsLayer: some View {
        Group {
            if model.sessionsPinned {
                if model.sessionsPinnedCollapsed {
                    SessionDotsCapsule(
                        sessions: model.sessions,
                        onExpand: { model.sessionsPinnedCollapsed = false }
                    )
                    .transition(sessionsTransition)
                } else {
                    PinnedSessionsDrawer(
                        model: model,
                        onCollapse: { model.sessionsPinnedCollapsed = true },
                        onUnpin: onUnpin
                    )
                    .transition(sessionsTransition)
                }
            }
        }
        .animation(
            .spring(response: 0.5, dampingFraction: 0.84),
            value: model.sessionsPinned
        )
        .animation(
            .spring(response: 0.45, dampingFraction: 0.86),
            value: model.sessionsPinnedCollapsed
        )
    }

    private var sessionsTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.85, anchor: .top)
                .combined(with: .opacity),
            removal: .scale(scale: 0.9, anchor: .top)
                .combined(with: .opacity)
        )
    }
}

private struct SessionDotsCapsule: View {
    let sessions: [ClaudeSession]
    let onExpand: () -> Void

    private let dotSize: CGFloat = 6
    private let dotSpacing: CGFloat = 4

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: dotSpacing) {
                if sessions.isEmpty {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: dotSize, height: dotSize)
                } else {
                    ForEach(sessions) { session in
                        Circle()
                            .fill(SessionStatusPalette.color(for: session.status))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.black.opacity(0.85))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Expand sessions")
    }
}

private struct PinnedSessionsDrawer: View {
    @Bindable var model: UsageViewModel
    let onCollapse: () -> Void
    let onUnpin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Collapse sessions")
                Spacer()
                Button(action: onUnpin) {
                    Image(systemName: "pin.slash.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Unpin sessions")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ProjectFoldersPanel(model: model, variant: .compact)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 4)
    }
}

private struct NotchPillView: View {
    let snapshot: UsageSnapshot
    let action: () -> Void

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var bucket: UsageBucket { snapshot.fiveHour }
    private var percent: Double { bucket.percent }
    private var color: Color { usageColor(for: percent) }
    private var stripeProgress: Double? {
        bucket.sessionProgress(at: now, windowLength: SessionWindow.fiveHourSeconds)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                MiniUsageBar(percent: percent, color: color, stripeProgress: stripeProgress)
                    .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .onReceive(ticker) { now = $0 }
    }
}

private struct MiniUsageBar: View {
    let percent: Double
    let color: Color
    var stripeProgress: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(
                        width: max(
                            geo.size.height,
                            geo.size.width * CGFloat(max(0, min(100, percent)) / 100)
                        )
                    )
                if let stripeProgress {
                    let stripeWidth: CGFloat = 1.5
                    let x = geo.size.width * CGFloat(min(1, max(0, stripeProgress)))
                    let clampedX = min(max(stripeWidth / 2, x), geo.size.width - stripeWidth / 2)
                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: stripeWidth, height: geo.size.height + 2)
                        .offset(x: clampedX - stripeWidth / 2, y: 0)
                }
            }
        }
    }
}

final class DashboardWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct MenuBarLabelContainer: View {
    @Bindable var model: UsageViewModel

    var body: some View {
        MenuBarLabel(snapshot: model.snapshot)
            .padding(.horizontal, 4)
    }
}
