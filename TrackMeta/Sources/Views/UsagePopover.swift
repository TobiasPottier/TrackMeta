import SwiftUI
import Combine

struct UsagePopover: View {
    @Bindable var model: UsageViewModel

    @State private var isOpen: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider().background(BrandPalette.border)

            content
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().background(BrandPalette.border)

            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(.white)
        .scaleEffect(isOpen ? 1.0 : 0.92, anchor: .top)
        .opacity(isOpen ? 1.0 : 0.0)
        .offset(y: isOpen ? 0 : -8)
        .onAppear {
            isOpen = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                isOpen = true
            }
        }
        .onDisappear {
            isOpen = false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TrackerLogo(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("TrackMeta")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                Text("Claude Max usage")
                    .font(.system(size: 11))
                    .foregroundStyle(BrandPalette.muted)
            }
            Spacer()
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandPalette.muted)
                    .padding(6)
                    .background(
                        Circle().fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                UsageRow(title: "5-hour session", bucket: snap.fiveHour)
                UsageRow(title: "Weekly",         bucket: snap.sevenDay)
            }
        }
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

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrandPalette.muted)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrandPalette.muted)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
    }
}

private struct UsageRow: View {
    let title: String
    let bucket: UsageBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(bucket.percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: bucket.percent))
            }

            UsageBar(percent: bucket.percent, color: color(for: bucket.percent))
                .frame(height: 6)

            if let reset = bucket.resetsAt {
                Text("Resets \(Self.resetFormatter.string(from: reset)) · \(Self.timeLeft(until: reset)) left")
                    .font(.system(size: 10))
                    .foregroundStyle(BrandPalette.muted)
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private static func timeLeft(until date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "0m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func color(for percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(red: 0.34, green: 0.78, blue: 0.47)
        case ..<80: return BrandPalette.accent
        default:    return Color(red: 0.95, green: 0.35, blue: 0.35)
        }
    }
}

private struct PeakHoursIndicator: View {
    private let window = PeakHoursWindow.claudeDefault

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var status: PeakHoursStatus { window.status(at: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.isPeakNow
                  ? "exclamationmark.triangle.fill"
                  : "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(status.isPeakNow ? .orange : BrandPalette.muted)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(status.isPeakNow ? "Peak hours — expect tighter limits" : "Off-peak")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(status.isPeakNow ? .orange : .white)

                    if status.isPeakNow {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.orange)
                            )
                    }
                }

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(BrandPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(status.isPeakNow
                      ? Color.orange.opacity(0.10)
                      : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(status.isPeakNow
                        ? Color.orange.opacity(0.35)
                        : BrandPalette.border,
                        lineWidth: 1)
        )
        .onReceive(ticker) { now = $0 }
    }

    private var subtitle: String {
        let base = window.formattedWindow()
        guard let boundary = status.nextBoundary else { return base }
        let verb = status.isPeakNow ? "ends" : "starts"
        return "\(base) · \(verb) \(Self.relative(boundary, from: now))"
    }

    private static func relative(_ date: Date, from ref: Date) -> String {
        let seconds = Int(date.timeIntervalSince(ref))
        guard seconds > 0 else { return "soon" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h >= 24 {
            let d = h / 24
            let rh = h % 24
            return rh > 0 ? "in \(d)d \(rh)h" : "in \(d)d"
        }
        if h > 0 { return "in \(h)h \(m)m" }
        return "in \(m)m"
    }
}

private struct UsageBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(
                            geo.size.height,
                            geo.size.width * CGFloat(max(0, min(100, percent)) / 100)
                        )
                    )
            }
        }
    }
}
