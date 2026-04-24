import SwiftUI
import AppKit

/// Compact dashboard with a scrollable content area.
/// The dashboard doubles as the floating overlay — when pinned (via the pin
/// button in the header) its hosting window is raised to floating level and
/// kept above other apps.
struct DashboardView: View {
    @Bindable var model: UsageViewModel
    var onTogglePinSessions: (() -> Void)? = nil
    var isWindowPinned: Bool = false
    var onToggleWindowPin: (() -> Void)? = nil

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                peakCard
                weeklyCard
                fiveHourCard
                chartCard
                sessionsCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                Text("Live Claude Code sessions and Max usage")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandPalette.muted)
            }
            Spacer()
            HStack(spacing: 10) {
                IconHeaderButton(
                    systemImage: "gearshape",
                    action: SettingsLauncher.open
                )
                .help("Open TrackMeta settings")
                if let onToggleWindowPin {
                    SecondaryCapsuleButton(
                        title: isWindowPinned ? "Unpin" : "Pin",
                        systemImage: isWindowPinned ? "pin.slash.fill" : "pin.fill",
                        highlighted: isWindowPinned,
                        action: onToggleWindowPin
                    )
                    .help(isWindowPinned
                          ? "Stop floating the dashboard above other apps"
                          : "Float the dashboard above other apps")
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

    @ViewBuilder private var sessionsCard: some View {
        DashCard {
            ProjectFoldersPanel(
                model: model,
                variant: .standard,
                isPinned: model.sessionsPinned,
                onTogglePin: onTogglePinSessions
            )
        }
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

private struct IconHeaderButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 32)
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

private struct SecondaryCapsuleButton: View {
    let title: String
    let systemImage: String
    var highlighted: Bool = false
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
                        .fill(highlighted
                              ? BrandPalette.accent.opacity(0.22)
                              : (hovering ? BrandPalette.cardFillHi : BrandPalette.cardFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(highlighted ? BrandPalette.accent.opacity(0.5) : BrandPalette.border,
                                lineWidth: 1)
                )
                .foregroundStyle(highlighted ? BrandPalette.accent : BrandPalette.mutedStrong)
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
