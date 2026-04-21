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
@Observable
final class PopoverPresenter {
    var isOpen: Bool = false
    /// When true, click-away and app-deactivation do not dismiss the panel.
    /// Explicit dismissals (status item, hotkey, pin toggle) still close it.
    var isPinned: Bool = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageViewModel()
    private let presenter = PopoverPresenter()

    private var statusItem: NSStatusItem?
    private var panel: UsagePanel?
    private var hostingController: NSHostingController<UsagePopover>?
    private var sizeObservation: NSKeyValueObservation?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastDismissAt: Date = .distantPast
    private var pendingDismissTask: Task<Void, Never>?
    private var pendingPillHideTask: Task<Void, Never>?
    private var dyingPanel: UsagePanel?

    /// Spring used for both the open and close morph — keep in sync with
    /// `UsagePopover`'s clip shape timing so the panel feels like it's
    /// physically attached to the pill.
    private static let morphAnimation: Animation = .spring(response: 0.46, dampingFraction: 0.84)
    /// Duration (seconds) the morph spring needs before the panel is
    /// effectively at rest — used to sequence `orderOut` on close.
    private static let morphSettleSeconds: Double = 0.42

    /// One pill panel per display (keyed by `CGDirectDisplayID`) so the
    /// notch UI shows on every connected screen simultaneously.
    private var pillPanels: [CGDirectDisplayID: NotchPillPanel] = [:]
    private var pillHostings: [CGDirectDisplayID: NSHostingController<NotchPillContainer>] = [:]
    private var pillSizeObservations: [CGDirectDisplayID: NSKeyValueObservation] = [:]
    private var screenParamsObserver: NSObjectProtocol?
    private var globalHotkey: GlobalHotkey?

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
            button.action = #selector(togglePanel(_:))
        }
        statusItem = item

        globalHotkey = GlobalHotkey { [weak self] in
            self?.togglePanel(nil)
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

    private func toggleSessionsPinned() {
        model.sessionsPinned.toggle()
        dismissPanel()
    }

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible {
            dismissPanel()
            return
        }
        if Date().timeIntervalSince(lastDismissAt) < 0.15 { return }
        showPanel()
    }

    private func showPanel() {
        // Cancel any in-flight close so a rapid reopen doesn't get yanked away.
        pendingDismissTask?.cancel(); pendingDismissTask = nil
        pendingPillHideTask?.cancel(); pendingPillHideTask = nil
        // Tear down any panel that's still shrinking from a previous close.
        dyingPanel?.orderOut(nil); dyingPanel = nil

        // Rebuild each time so notch state follows the current display.
        panel?.orderOut(nil)
        presenter.isOpen = false
        let panel = makePanel()
        self.panel = panel
        repositionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installMouseMonitors()

        // Animate the morph on the next runloop tick so SwiftUI has rendered
        // the collapsed (pill-sized) state first and then springs up to full.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(Self.morphAnimation) {
                self.presenter.isOpen = true
            }
        }

        // Keep the pill visible briefly so it appears to morph into the
        // expanding popup, then fade it out once the popup has covered it.
        pendingPillHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, let self else { return }
            // Only hide the pill on the screen the popover is on — leave other
            // displays' pills visible so the menu bar indicator doesn't vanish
            // everywhere when the popup opens on one screen.
            if let popoverScreen = self.panel?.screen,
               let displayID = Self.displayID(for: popoverScreen) {
                self.pillPanels[displayID]?.orderOut(nil)
            }
        }
    }

    private func dismissPanel() {
        removeMouseMonitors()
        lastDismissAt = Date()
        pendingPillHideTask?.cancel(); pendingPillHideTask = nil
        presenter.isPinned = false

        guard let panel, panel.isVisible else {
            updatePillPresentation()
            return
        }

        // Bring the pill back on screen under the popup so the popup's shrink
        // reveals the pill beneath it, creating a continuous morph.
        updatePillPresentation()
        // `updatePillPresentation` calls `orderFrontRegardless` on the pill,
        // so re-raise the popup so it shrinks *over* the pill, not under it.
        panel.orderFrontRegardless()

        withAnimation(Self.morphAnimation) {
            presenter.isOpen = false
        }

        // Release the panel after the morph animation settles.
        self.dyingPanel = panel
        self.panel = nil
        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor [weak self] in
            let nanos = UInt64(Self.morphSettleSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.dyingPanel?.orderOut(nil)
            self.dyingPanel = nil
            self.hostingController = nil
            self.sizeObservation?.invalidate()
            self.sizeObservation = nil
        }
    }

    private func makePanel() -> UsagePanel {
        let notch = Self.notchFrame(on: currentScreen())
        let notchWidth = notch?.width ?? 0
        let root = UsagePopover(
            model: model,
            presenter: presenter,
            notchAttached: notch != nil,
            notchWidth: notchWidth,
            onTogglePinSessions: { [weak self] in
                Task { @MainActor in self?.toggleSessionsPinned() }
            }
        )
        let host = NSHostingController(rootView: root)
        hostingController = host

        let fitting = host.view.fittingSize
        let contentSize = NSSize(
            width: max(fitting.width, UsagePopover.preferredWidth),
            height: max(fitting.height, 1)
        )

        let panel = UsagePanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)

        host.view.wantsLayer = true
        // Shape clipping is done in SwiftUI so we can round only the bottom corners.
        host.view.layer?.masksToBounds = false

        // Auto-resize the panel when SwiftUI content height changes (e.g. sessions load).
        host.sizingOptions = .preferredContentSize
        sizeObservation = host.observe(\.preferredContentSize, options: [.new]) { [weak self, weak panel] _, change in
            guard let self, let panel, let newSize = change.newValue, newSize.height > 0 else { return }
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel, panel.isVisible else { return }
                let width = max(newSize.width, UsagePopover.preferredWidth)
                panel.setContentSize(NSSize(width: width, height: newSize.height))
                self.repositionPanel(panel)
            }
        }

        return panel
    }

    /// Screen the popover should target. When the status item's button is
    /// hidden (because we've replaced it with a notch pill) its window may not
    /// report a meaningful screen, so fall back to the display containing the
    /// mouse cursor — that matches which pill the user just clicked / hovered.
    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let under = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return under
        }
        return statusItem?.button?.window?.screen ?? NSScreen.main
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
    /// so the pill + notch-attached popover behaves the same as on a notched MacBook.
    private static let virtualNotchWidth: CGFloat = 200

    /// Returns the notch's frame in screen coordinates.
    ///
    /// - Built-in displays with a physical notch: returns the real notch rect.
    /// - Built-in displays without a notch (older MacBooks, external-only iMac-style):
    ///   returns nil, preserving the classic menu-bar status item.
    /// - External displays: synthesizes a centered virtual notch spanning the menu bar
    ///   so the same under-the-notch UI can attach there.
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

    private func repositionPanel(_ panel: NSPanel) {
        guard let screen = currentScreen() else { return }
        let size = panel.frame.size

        if let notch = Self.notchFrame(on: screen) {
            // Center on the notch; top edge flush with the notch bottom.
            let x = notch.midX - size.width / 2
            let y = notch.minY - size.height + 2
            panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        } else {
            let vf = screen.visibleFrame
            let x = vf.midX - size.width / 2
            let y = vf.maxY - size.height - 6
            panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        }
    }

    private func installMouseMonitors() {
        removeMouseMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.presenter.isPinned else { return }
                self.dismissPanel()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if self.presenter.isPinned { return event }
            let isPillWindow = self.pillPanels.values.contains(where: { $0 === event.window })
            if event.window !== self.panel && !isPillWindow {
                self.dismissPanel()
            }
            return event
        }
    }

    private func removeMouseMonitors() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
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
                Task { @MainActor in self?.togglePanel(nil) }
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
                // SwiftUI already springs `preferredContentSize` across the
                // collapse/expand transition — snap the window every frame
                // instead of layering AppKit's own setFrame animation, which
                // competes with SwiftUI's spring and makes the pill's top edge
                // jitter during the height change.
                self?.repositionPill(notch: notch, id: id, animate: false)
            }
        }

        repositionPill(notch: notch, id: id)
        panel.orderFrontRegardless()
    }

    private func repositionPill(notch: NSRect, id: CGDirectDisplayID, animate: Bool = true) {
        guard let panel = pillPanels[id], let host = pillHostings[id] else { return }
        // Force a layout pass so `fittingSize` reflects the current SwiftUI
        // content instead of a stale pre-transition size.
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
        // Animate so the pill ↔ pinned-sessions size change glides instead of snapping.
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
    // `centerX` and anchored at `topY`. AppKit's default `setContentSize`/
    // `setFrame` preserves the window's bottom-left origin, which lets the
    // panel's top edge drop/rise as SwiftUI content grows/shrinks — the pill
    // (which renders at the top of the VStack) then appears to jump.
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
        // AppKit's default `setContentSize` preserves the bottom-left origin,
        // which shifts the top edge when height changes. Route the resize
        // through our reanchored setFrame so the top stays pinned.
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
                        sessions: model.sessions,
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
    let sessions: [ClaudeSession]
    let onCollapse: () -> Void
    let onUnpin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Sessions")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(sessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )
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
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(sessions) { session in
                        PinnedSessionRow(session: session)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
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

private struct PinnedSessionRow: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 8) {
            statusDot
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(folderLabel)
                .font(.system(size: 9).monospaced())
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(border, lineWidth: 0.5)
        )
    }

    @ViewBuilder private var statusDot: some View {
        switch session.status {
        case .working, .awaitingInput:
            PulsingDot(color: statusColor)
        case .idle:
            Circle().fill(statusColor).frame(width: 6, height: 6)
        }
    }

    private var title: String {
        session.summary ?? "--"
    }

    private var folderLabel: String {
        session.cwdDisplayName ?? String(session.sessionId.prefix(8))
    }

    private var statusColor: Color { SessionStatusPalette.color(for: session.status) }

    private var background: Color {
        switch session.status {
        case .working:       return statusColor.opacity(0.10)
        case .awaitingInput: return statusColor.opacity(0.14)
        case .idle:          return Color.white.opacity(0.04)
        }
    }

    private var border: Color {
        switch session.status {
        case .working:       return statusColor.opacity(0.30)
        case .awaitingInput: return statusColor.opacity(0.40)
        case .idle:          return statusColor.opacity(0.20)
        }
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

final class UsagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct MenuBarLabelContainer: View {
    @Bindable var model: UsageViewModel

    var body: some View {
        MenuBarLabel(snapshot: model.snapshot)
            .padding(.horizontal, 4)
    }
}
