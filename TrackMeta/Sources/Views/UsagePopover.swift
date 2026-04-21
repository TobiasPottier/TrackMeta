import SwiftUI
import Combine
import Charts

struct UsagePopover: View {
    static let preferredWidth: CGFloat = 560

    @Bindable var model: UsageViewModel
    var presenter: PopoverPresenter
    var notchAttached: Bool = false
    var notchWidth: CGFloat = 0
    var onTogglePinSessions: (() -> Void)? = nil

    // Vertical distance over which the top narrows from full width down to the notch width.
    private let neckHeight: CGFloat = 20

    private var isOpen: Bool { presenter.isOpen }

    private var panelShape: AnyShape {
        if notchAttached, notchWidth > 0 {
            return AnyShape(NotchIslandShape(
                notchWidth: notchWidth,
                neckHeight: neckHeight,
                bottomRadius: 22
            ))
        }
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 18,
            topTrailingRadius: 14,
            style: .continuous
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, notchAttached ? neckHeight + 14 : 18)
                .padding(.bottom, 14)

            Divider().background(BrandPalette.border)

            content
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

            Divider().background(BrandPalette.border)

            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
        }
        .frame(width: Self.preferredWidth)
        .background(
            LinearGradient(
                colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(.white)
        .clipShape(panelShape)
        .scaleEffect(
            x: isOpen ? 1.0 : collapsedScaleX,
            y: isOpen ? 1.0 : collapsedScaleY,
            anchor: .top
        )
        .blur(radius: isOpen ? 0 : 14)
        .opacity(isOpen ? 1.0 : 0.0)
    }

    /// Starting horizontal scale: the shape begins right at the notch's width
    /// so its top edge lines up with the visible pill.
    private var collapsedScaleX: CGFloat {
        guard notchAttached, notchWidth > 0 else { return 0.94 }
        let ratio = notchWidth / Self.preferredWidth
        return max(0.34, min(0.55, ratio + 0.02))
    }

    /// Starting vertical scale: collapsed flat against the notch so the panel
    /// feels like it's unfurling from the pill rather than appearing out of nowhere.
    private var collapsedScaleY: CGFloat {
        notchAttached ? 0.12 : 0.9
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
                UsageRow(title: "5-hour session", bucket: snap.fiveHour, sessionWindow: SessionWindow.fiveHourSeconds)
                SessionUsageChart(history: model.history, bucket: snap.fiveHour)
                UsageRow(title: "Weekly",         bucket: snap.sevenDay, sessionWindow: SessionWindow.sevenDaySeconds)
            }

            Divider()
                .background(BrandPalette.border)
                .padding(.vertical, 2)

            SessionsSection(
                sessions: model.sessions,
                isPinned: model.sessionsPinned,
                onTogglePin: onTogglePinSessions
            )
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
    let sessionWindow: TimeInterval?

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var stripeProgress: Double? {
        guard let sessionWindow else { return nil }
        return bucket.sessionProgress(at: now, windowLength: sessionWindow)
    }

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

            UsageBar(percent: bucket.percent, color: color(for: bucket.percent), stripeProgress: stripeProgress)
                .frame(height: 6)
                .onReceive(ticker) { now = $0 }

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

    private func color(for percent: Double) -> Color { usageColor(for: percent) }
}

func usageColor(for percent: Double) -> Color {
    switch percent {
    case ..<50: return Color(red: 0.34, green: 0.78, blue: 0.47)
    case ..<80: return BrandPalette.accent
    default:    return Color(red: 0.95, green: 0.35, blue: 0.35)
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
    var stripeProgress: Double? = nil

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

                if let stripeProgress {
                    let stripeWidth: CGFloat = 2
                    let x = geo.size.width * CGFloat(min(1, max(0, stripeProgress)))
                    let clampedX = min(max(stripeWidth / 2, x), geo.size.width - stripeWidth / 2)
                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: stripeWidth, height: geo.size.height + 4)
                        .offset(x: clampedX - stripeWidth / 2, y: 0)
                        .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0)
                }
            }
        }
    }
}

private struct SessionUsageChart: View {
    let history: [UsageSample]
    let bucket: UsageBucket

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var sessionStart: Date {
        if let resetsAt = bucket.resetsAt {
            return resetsAt.addingTimeInterval(-SessionWindow.fiveHourSeconds)
        }
        return history.first?.timestamp ?? now.addingTimeInterval(-SessionWindow.fiveHourSeconds)
    }

    private var sessionEnd: Date {
        bucket.resetsAt ?? now
    }

    private var chartColor: Color { usageColor(for: bucket.percent) }

    private static let boundaryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @ViewBuilder
    private func sessionBoundaryLabel(title: String, date: Date) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.55))
            Text(Self.boundaryFormatter.string(from: date))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            Capsule().fill(Color.black.opacity(0.3))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(history, id: \.timestamp) { sample in
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Usage", sample.fiveHourPercent)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [chartColor.opacity(0.35), chartColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Usage", sample.fiveHourPercent)
                    )
                    .foregroundStyle(chartColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                LineMark(
                    x: .value("Time", sessionStart),
                    y: .value("Pace", 0),
                    series: .value("Series", "pace")
                )
                .foregroundStyle(Color.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                LineMark(
                    x: .value("Time", sessionEnd),
                    y: .value("Pace", 100),
                    series: .value("Series", "pace")
                )
                .foregroundStyle(Color.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .topLeading, alignment: .trailing, spacing: 2) {
                    sessionBoundaryLabel(title: "End", date: sessionEnd)
                }

                RuleMark(x: .value("Now", min(max(now, sessionStart), sessionEnd)))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Now", min(max(now, sessionStart), sessionEnd)),
                    y: .value("Usage", bucket.percent)
                )
                .symbolSize(36)
                .foregroundStyle(chartColor)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text("\(Int(bucket.percent.rounded()))%")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(chartColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.black.opacity(0.35))
                        )
                        .overlay(
                            Capsule().stroke(chartColor.opacity(0.5), lineWidth: 0.5)
                        )
                }
            }
            .chartXScale(domain: sessionStart...sessionEnd)
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .frame(height: 180)
            .onReceive(ticker) { now = $0 }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }
}

/// Shape that sits flush against the notch: the top edge is exactly `notchWidth`
/// and fans outward over `neckHeight` to the full width, ending in rounded bottom corners.
struct NotchIslandShape: Shape {
    var notchWidth: CGFloat
    var neckHeight: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let W = rect.width
        let H = rect.height
        let r = min(bottomRadius, min(W, H) / 2)
        let nh = min(neckHeight, H - r)
        let inset = max(0, (W - notchWidth) / 2)

        // Tangent-handle lengths. Both endpoints of the neck curve carry a
        // *vertical* tangent so the curve flows continuously into the notch
        // side at the top and into the panel side at the bottom — no corner.
        let topHandle    = nh * 0.62
        let bottomHandle = nh * 0.42

        // Top-left corner of the notch
        p.move(to: CGPoint(x: inset, y: 0))

        // Neck: notch edge → full-width left side. Vertical tangents at both ends.
        p.addCurve(
            to: CGPoint(x: 0, y: nh),
            control1: CGPoint(x: inset, y: topHandle),
            control2: CGPoint(x: 0, y: nh - bottomHandle)
        )

        // Left edge down to bottom-left corner
        p.addLine(to: CGPoint(x: 0, y: H - r))
        p.addQuadCurve(
            to: CGPoint(x: r, y: H),
            control: CGPoint(x: 0, y: H)
        )

        // Bottom edge
        p.addLine(to: CGPoint(x: W - r, y: H))
        p.addQuadCurve(
            to: CGPoint(x: W, y: H - r),
            control: CGPoint(x: W, y: H)
        )

        // Right edge up to the neck
        p.addLine(to: CGPoint(x: W, y: nh))

        // Mirror neck: full-width right side → notch edge.
        p.addCurve(
            to: CGPoint(x: W - inset, y: 0),
            control1: CGPoint(x: W, y: nh - bottomHandle),
            control2: CGPoint(x: W - inset, y: topHandle)
        )

        p.closeSubpath()
        return p
    }
}
