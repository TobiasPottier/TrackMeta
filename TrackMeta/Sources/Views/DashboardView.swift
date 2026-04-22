import SwiftUI

struct DashboardView: View {
    @Bindable var model: UsageViewModel
    var onTogglePinSessions: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                usageCard

                SessionsSection(
                    sessions: model.sessions,
                    isPinned: model.sessionsPinned,
                    onTogglePin: onTogglePinSessions,
                    onDismissSession: { model.dismissSession($0) }
                )
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BrandPalette.border, lineWidth: 1)
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(
                colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 12) {
            TrackerLogo(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("TrackMeta")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                Text("Dashboard")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandPalette.muted)
            }
            Spacer()
            Button(action: model.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PeakHoursIndicator()

            switch model.state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading usage…")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

            case .failed(let message):
                failure(message)

            case .loaded(let snap):
                if snap.isUsageCapReached {
                    UsageCapBanner(snapshot: snap)
                }
                UsageRow(title: "5-hour session", bucket: snap.fiveHour, sessionWindow: SessionWindow.fiveHourSeconds)
                SessionUsageChart(history: model.history, bucket: snap.fiveHour)
                UsageRow(title: "Weekly", bucket: snap.sevenDay, sessionWindow: SessionWindow.sevenDaySeconds)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }

    private func failure(_ message: String) -> some View {
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
