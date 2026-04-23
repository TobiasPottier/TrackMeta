import SwiftUI
import AppKit

/// Two-pane dashboard: a fixed navigation rail and a scrollable content area.
/// Matches the 2026 midnight-blue redesign — sidebar with logo/nav/footer on
/// the left, and a stacked set of status + usage + sessions cards on the right.
struct DashboardView: View {
    @Bindable var model: UsageViewModel
    var onTogglePinSessions: (() -> Void)? = nil
    var onToggleAgentsPanel: (() -> Void)? = nil

    @State private var selectedNav: NavItem = .dashboard
    @State private var launchError: String?

    // Orchestrator sheet state
    @State private var orchestratorFolder: URL?
    @State private var isOrchestrating = false
    @State private var orchestratorError: String?

    private let orchestratorClient = OrchestratorClient()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                selected: $selectedNav,
                agentsConnected: model.sessions.count
            )
            .frame(width: 216)

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandPalette.sidebar.ignoresSafeArea())
        .foregroundStyle(.white)
        .alert("Couldn't launch iTerm",
               isPresented: Binding(
                get: { launchError != nil },
                set: { if !$0 { launchError = nil } }
               ),
               presenting: launchError) { _ in
            Button("OK", role: .cancel) { launchError = nil }
        } message: { message in
            Text(message)
        }
        .alert("Orchestration failed",
               isPresented: Binding(
                get: { orchestratorError != nil },
                set: { if !$0 { orchestratorError = nil } }
               ),
               presenting: orchestratorError) { _ in
            Button("OK", role: .cancel) { orchestratorError = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: Binding(
            get: { orchestratorFolder != nil },
            set: { if !$0 { orchestratorFolder = nil } }
        )) {
            if let folder = orchestratorFolder {
                orchestratorSheetContent(folder: folder)
            }
        }
    }

    @ViewBuilder private func orchestratorSheetContent(folder: URL) -> some View {
        if isOrchestrating {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Asking Claude to plan your sessions…")
                    .font(.system(size: 13))
                    .foregroundStyle(BrandPalette.muted)
            }
            .frame(width: 520, height: 160)
            .background(BrandPalette.cardFill)
        } else {
            OrchestratorSheet(
                initialFolder: folder,
                onSubmit: { resolvedFolder, prompt in
                    orchestratorFolder = nil
                    Task { await runOrchestration(folder: resolvedFolder, prompt: prompt) }
                },
                onCancel: { orchestratorFolder = nil }
            )
        }
    }

    @ViewBuilder private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedNav {
                case .agents:
                    agentsContent
                default:
                    dashboardContent
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var dashboardContent: some View {
        header(title: "Dashboard", subtitle: "Overview of your sessions and agents", showOrchestrate: false)
        peakCard
        fiveHourCard
        chartCard
        weeklyCard
        projectsFoldersCard
    }

    @ViewBuilder private var agentsContent: some View {
        header(title: "Agents", subtitle: "Live agents with current 5-hour usage", showOrchestrate: true)
        compactFiveHourCard
        compactChartCard
        projectsFoldersCard
    }

    // MARK: - Header

    private func header(title: String, subtitle: String, showOrchestrate: Bool = false) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(BrandPalette.muted)
            }
            Spacer()
            HStack(spacing: 10) {
                if showOrchestrate, let onToggleAgentsPanel {
                    SecondaryCapsuleButton(
                        title: "Float",
                        systemImage: "macwindow.on.rectangle",
                        action: onToggleAgentsPanel
                    )
                    .help("Open agents as a floating overlay window that stays on top")
                }

                SecondaryCapsuleButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    action: model.refresh
                )
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder private var peakCard: some View {
        DashCard {
            PeakHoursIndicator()
        }
    }

    @ViewBuilder private var fiveHourCard: some View {
        DashCard {
            switch model.state {
            case .idle, .loading:
                LoadingRow()
            case .failed(let message):
                FailureRow(message: message)
            case .loaded(let snap):
                VStack(alignment: .leading, spacing: 12) {
                    if snap.isUsageCapReached {
                        UsageCapBanner(snapshot: snap)
                    }
                    UsageRow(
                        title: "5-hour session",
                        bucket: snap.fiveHour,
                        sessionWindow: SessionWindow.fiveHourSeconds
                    )
                }
            }
        }
    }

    @ViewBuilder private var chartCard: some View {
        if case .loaded(let snap) = model.state {
            SessionUsageChart(history: model.history, bucket: snap.fiveHour)
                .frame(maxWidth: .infinity)
        } else {
            DashCard {
                HStack {
                    Spacer()
                    Text("Chart unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(BrandPalette.muted)
                    Spacer()
                }
                .frame(height: 220)
            }
        }
    }

    @ViewBuilder private var compactFiveHourCard: some View {
        DashCard(padding: 12) {
            switch model.state {
            case .idle, .loading:
                LoadingRow()
            case .failed(let message):
                FailureRow(message: message)
            case .loaded(let snap):
                VStack(alignment: .leading, spacing: 8) {
                    if snap.isUsageCapReached {
                        UsageCapBanner(snapshot: snap)
                    }
                    UsageRow(
                        title: "5-hour session",
                        bucket: snap.fiveHour,
                        sessionWindow: SessionWindow.fiveHourSeconds,
                        resetPlacement: .topCentered
                    )
                }
            }
        }
    }

    @ViewBuilder private var compactChartCard: some View {
        if case .loaded(let snap) = model.state {
            SessionUsageChart(history: model.history, bucket: snap.fiveHour)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var weeklyCard: some View {
        DashCard {
            switch model.state {
            case .idle, .loading:
                LoadingRow()
            case .failed(let message):
                FailureRow(message: message)
            case .loaded(let snap):
                UsageRow(
                    title: "Weekly",
                    bucket: snap.sevenDay,
                    sessionWindow: SessionWindow.sevenDaySeconds
                )
            }
        }
    }

    @ViewBuilder private var projectsFoldersCard: some View {
        DashCard {
            ProjectFoldersPanel(
                model: model,
                variant: .standard,
                isPinned: model.sessionsPinned,
                onTogglePin: onTogglePinSessions,
                onOrchestrate: { folder in orchestratorFolder = folder },
                onLaunchAgent: { folder, split in launchAgent(folder: folder, split: split) }
            )
        }
    }

    // MARK: - Actions

    private func launchAgent(folder: URL, split: ITermSplit?) {
        do {
            try ITermLauncher.launch(folder: folder, command: "csp", split: split)
        } catch {
            launchError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func runOrchestration(folder: URL, prompt: String) async {
        isOrchestrating = true
        defer { isOrchestrating = false }
        do {
            let actions = try await orchestratorClient.orchestrate(userPrompt: prompt, folder: folder)
            for action in actions {
                try ITermLauncher.launch(folder: folder, command: action.shellCommand, split: action.iTermSplit)
            }
        } catch {
            orchestratorError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - Navigation rail

enum NavItem: String, CaseIterable, Identifiable {
    case dashboard, agents, projects, sessions, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .agents:    return "Agents"
        case .projects:  return "Projects"
        case .sessions:  return "Sessions"
        case .settings:  return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .agents:    return "cpu"
        case .projects:  return "folder"
        case .sessions:  return "rectangle.stack"
        case .settings:  return "gearshape"
        }
    }
}

private struct Sidebar: View {
    @Binding var selected: NavItem
    let agentsConnected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(NavItem.allCases) { item in
                    SidebarRow(
                        item: item,
                        isSelected: item == selected,
                        action: { selected = item }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            footer
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BrandPalette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(BrandPalette.borderSoft)
                .frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            TrackerLogo(size: 28)
            Text("TrackMeta")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.white)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(agentsConnected > 0 ? Color.green : BrandPalette.muted.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text("\(agentsConnected) agent\(agentsConnected == 1 ? "" : "s") connected")
                    .font(.system(size: 11))
                    .foregroundStyle(BrandPalette.mutedStrong)
            }

            Button {
                SettingsLauncher.open()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book")
                        .font(.system(size: 10))
                    Text("View documentation")
                        .font(.system(size: 11))
                }
                .foregroundStyle(BrandPalette.muted)
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(BrandPalette.borderSoft)
                .padding(.vertical, 2)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BrandPalette.accent, BrandPalette.accent.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initials)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(userLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Claude Max")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandPalette.muted)
                }
            }
        }
    }

    private var userLabel: String {
        NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
    }

    private var initials: String {
        let name = userLabel
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        let joined = letters.joined()
        return joined.isEmpty ? "•" : joined.uppercased()
    }
}

private struct SidebarRow: View {
    let item: NavItem
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : BrandPalette.mutedStrong)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? BrandPalette.accent.opacity(0.14)
                          : (hovering ? Color.white.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? BrandPalette.accent.opacity(0.32) : Color.clear,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Reusable card

struct DashCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BrandPalette.border, lineWidth: 1)
            )
    }
}

// MARK: - Buttons

private struct PrimaryCapsuleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [
                            BrandPalette.accent,
                            BrandPalette.accent.opacity(hovering ? 0.92 : 0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: BrandPalette.accent.opacity(0.35), radius: 10, x: 0, y: 4)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SecondaryCapsuleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? BrandPalette.cardFillHi : BrandPalette.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BrandPalette.border, lineWidth: 1)
                )
                .foregroundStyle(BrandPalette.mutedStrong)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Inline status rows

private struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading usage…")
                .font(.system(size: 12))
                .foregroundStyle(BrandPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FailureRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't load usage")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(BrandPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Settings launcher

private enum SettingsLauncher {
    static func open() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
