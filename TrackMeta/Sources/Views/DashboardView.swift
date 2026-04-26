import SwiftUI
import AppKit

/// The dashboard is the editorial frame for the app — a single, monochrome
/// canvas that lets the data take center stage. Cards are outline-only by
/// default; the amber primary is reserved for the active "needs input" hero
/// stat and the Refresh CTA.
struct DashboardView: View {
    @Bindable var model: UsageViewModel
    var onTogglePinSessions: (() -> Void)? = nil
    var isWindowPinned: Bool = false
    var onToggleWindowPin: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                heroSection
                metaRow
                chartSection
                sessionsSection
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Surface.base.ignoresSafeArea())
        .foregroundStyle(DS.Text.primary)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                TrackerLogo(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("TrackMeta")
                        .dsType(.labelSm)
                        .foregroundStyle(DS.Text.muted)
                    Text("Dashboard")
                        .dsType(.headlineLg)
                        .foregroundStyle(DS.Text.primary)
                }
            }
            Spacer()
            HStack(spacing: DS.Space.xs) {
                Button(action: SettingsLauncher.open) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(DSIconButtonStyle())
                .help("Open TrackMeta settings")

                if let onToggleWindowPin {
                    Button(action: onToggleWindowPin) {
                        Image(systemName: isWindowPinned ? "pin.slash.fill" : "pin.fill")
                    }
                    .buttonStyle(DSIconButtonStyle(highlighted: isWindowPinned))
                    .help(isWindowPinned
                          ? "Stop floating the dashboard above other apps"
                          : "Float the dashboard above other apps")
                }

                Button(action: model.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DSPrimaryButtonStyle())
            }
        }
    }

    // MARK: - Hero (5-hour) section
    //
    // The 5-hour usage gauge is the editorial centerpiece. It gets oversized
    // type, generous whitespace, and a thin outline frame.

    @ViewBuilder private var heroSection: some View {
        switch model.state {
        case .idle, .loading:
            LoadingRow()
                .dsCard(.outline, radius: DS.Radius.lg, padding: DS.Space.lg)
        case .failed(let message):
            FailureRow(message: message)
                .dsCard(.outline, radius: DS.Radius.lg, padding: DS.Space.lg)
        case .loaded(let snap):
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if snap.isUsageCapReached {
                    UsageCapBanner(snapshot: snap)
                }
                UsageRow(
                    title: "5-hour session",
                    bucket: snap.fiveHour,
                    sessionWindow: SessionWindow.fiveHourSeconds,
                    style: .hero
                )
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Outline.soft.opacity(0.55), lineWidth: 1)
            )
        }
    }

    // MARK: - Meta row (peak + weekly side-by-side)
    //
    // The two sibling cards now share the same inner anatomy: an icon-led
    // header, a primary value, and a thin contextual line. Heights match via
    // `.frame(maxHeight: .infinity)` on the inner content.

    @ViewBuilder private var metaRow: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            PeakHoursIndicator()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DS.Space.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(DS.Outline.soft.opacity(0.55), lineWidth: 1)
                )

            Group {
                switch model.state {
                case .idle, .loading:
                    LoadingRow()
                case .failed(let message):
                    FailureRow(message: message)
                case .loaded(let snap):
                    UsageRow(
                        title: "Weekly",
                        bucket: snap.sevenDay,
                        sessionWindow: SessionWindow.sevenDaySeconds,
                        style: .compact,
                        icon: "calendar"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DS.Space.md)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Outline.soft.opacity(0.55), lineWidth: 1)
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Chart

    @ViewBuilder private var chartSection: some View {
        if case .loaded(let snap) = model.state {
            SessionUsageChart(history: model.history, bucket: snap.fiveHour)
                .dsCard(.outline, radius: DS.Radius.lg, padding: DS.Space.md)
        } else {
            HStack {
                Spacer()
                Text("Chart unavailable")
                    .dsType(.bodySm)
                    .foregroundStyle(DS.Text.muted)
                Spacer()
            }
            .frame(height: 200)
            .dsCard(.outline, radius: DS.Radius.lg, padding: DS.Space.md)
        }
    }

    // MARK: - Sessions

    @ViewBuilder private var sessionsSection: some View {
        ProjectFoldersPanel(
            model: model,
            variant: .standard,
            isPinned: model.sessionsPinned,
            onTogglePin: onTogglePinSessions
        )
    }
}

// MARK: - Inline status rows

private struct LoadingRow: View {
    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ProgressView().controlSize(.small)
            Text("Loading usage…")
                .dsType(.bodyMd)
                .foregroundStyle(DS.Text.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FailureRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DS.Status.danger)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't load usage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Text.primary)
                Text(message)
                    .dsType(.bodySm)
                    .foregroundStyle(DS.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Settings launcher

enum SettingsLauncher {
    static func open() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
