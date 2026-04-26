import SwiftUI
import Combine
import Charts

// MARK: - Usage cap banner

struct UsageCapBanner: View {
    let snapshot: UsageSnapshot

    private var resetText: String? {
        [snapshot.fiveHour.resetsAt, snapshot.sevenDay.resetsAt]
            .compactMap { $0 }
            .min()
            .map { "Next reset \(Self.resetFormatter.string(from: $0))" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Status.danger)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Usage cap reached")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Text.primary)
                if let resetText {
                    Text(resetText)
                        .dsType(.bodySm)
                        .foregroundStyle(DS.Text.muted)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Status.danger.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Status.danger.opacity(0.30), lineWidth: 1)
        )
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()
}

// MARK: - Usage row

enum UsageRowStyle {
    case hero       // 5-hour gauge — display-size numerals, anchored reset clock
    case compact    // weekly / sibling — icon + heading + thin bar
}

struct UsageRow: View {
    let title: String
    let bucket: UsageBucket
    let sessionWindow: TimeInterval?
    var style: UsageRowStyle = .hero
    var icon: String = "gauge.with.needle"

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var stripeProgress: Double? {
        guard let sessionWindow else { return nil }
        return bucket.sessionProgress(at: now, windowLength: sessionWindow)
    }

    private var percent: Double { bucket.percent }
    private var barColor: Color { usageColor(for: percent) }

    var body: some View {
        Group {
            switch style {
            case .hero:    heroBody
            case .compact: compactBody
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: Hero
    //
    // Display-size numeral on the left, an editorial "resets in" clock on the
    // right, with the bar spanning the full width below. The right-hand clock
    // anchors the empty space the old layout left dangling.

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .dsType(.labelSm)
                    .foregroundStyle(DS.Text.muted)
                Spacer()
                if percent >= 80 {
                    DSChip(text: percent >= 95 ? "Critical" : "Approaching cap",
                           tone: percent >= 95 ? .danger : .warning)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                heroNumeral
                Spacer(minLength: DS.Space.lg)
                if let reset = bucket.resetsAt {
                    resetClock(target: reset)
                }
            }

            UsageBar(percent: percent,
                     color: barColor,
                     stripeProgress: stripeProgress)
                .frame(height: 6)
        }
    }

    private var heroNumeral: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text("\(Int(percent.rounded()))")
                .font(.system(size: 64, weight: .semibold))
                .tracking(-2.4)
                .monospacedDigit()
                .foregroundStyle(DS.Text.primary)
            Text("%")
                .font(.system(size: 22, weight: .regular))
                .tracking(-0.6)
                .foregroundStyle(DS.Text.muted)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func resetClock(target: Date) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Resets in")
                .dsType(.labelSm)
                .foregroundStyle(DS.Text.muted)
            Text(Self.timeLeft(until: target, fromDate: now))
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(DS.Text.secondary)
            Text(Self.absoluteResetText(target))
                .dsType(.bodySm)
                .foregroundStyle(DS.Text.muted)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Compact

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .center, spacing: DS.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.Text.muted)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(barColor)
            }

            UsageBar(percent: percent,
                     color: barColor,
                     stripeProgress: stripeProgress)
                .frame(height: 4)
                .padding(.leading, 26) // align under text, not icon

            if let reset = bucket.resetsAt {
                Text(Self.compactResetText(reset, fromDate: now))
                    .dsType(.bodySm)
                    .foregroundStyle(DS.Text.muted)
                    .monospacedDigit()
                    .padding(.leading, 26)
            }
        }
    }

    // MARK: - Helpers

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private static func absoluteResetText(_ date: Date) -> String {
        "at \(resetFormatter.string(from: date))"
    }

    private static func compactResetText(_ date: Date, fromDate ref: Date) -> String {
        "Resets \(resetFormatter.string(from: date)) · \(timeLeft(until: date, fromDate: ref)) left"
    }

    private static func timeLeft(until date: Date, fromDate ref: Date) -> String {
        let seconds = Int(date.timeIntervalSince(ref))
        guard seconds > 0 else { return "0m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// Usage bar color ramp. The Modern Refinement palette restricts chroma — at
/// healthy levels we render in the soft amber primary, deepening to red only
/// at the warning threshold so the gauge still communicates urgency.
func usageColor(for percent: Double) -> Color {
    switch percent {
    case ..<50: return DS.Status.success
    case ..<80: return DS.Primary.accent
    default:    return DS.Status.danger
    }
}

// MARK: - Peak hours indicator

struct PeakHoursIndicator: View {
    private let window = PeakHoursWindow.claudeDefault

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var status: PeakHoursStatus { window.status(at: now) }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: status.isPeakNow ? "wave.3.right" : "moon.stars")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(status.isPeakNow ? DS.Primary.accent : DS.Text.muted)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DS.Space.xs) {
                    Text(status.isPeakNow ? "Peak hours" : "Off-peak")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Text.primary)

                    if status.isPeakNow {
                        DSChip(text: "Now", tone: .accent)
                    }
                }

                Text(subtitle)
                    .dsType(.bodySm)
                    .foregroundStyle(DS.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
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

// MARK: - Usage bar

private struct UsageBar: View {
    let percent: Double
    let color: Color
    var stripeProgress: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Surface.containerHigh)

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
                        .fill(DS.Text.primary)
                        .frame(width: stripeWidth, height: geo.size.height + 4)
                        .offset(x: clampedX - stripeWidth / 2, y: 0)
                }
            }
        }
    }
}

// MARK: - Session usage chart

struct SessionUsageChart: View {
    let history: [UsageSample]
    let bucket: UsageBucket

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sessionStart: Date {
        if let resetsAt = bucket.resetsAt {
            return resetsAt.addingTimeInterval(-SessionWindow.fiveHourSeconds)
        }
        return history.first?.timestamp ?? now.addingTimeInterval(-SessionWindow.fiveHourSeconds)
    }

    private var sessionEnd: Date {
        bucket.resetsAt ?? now
    }

    private var clampedNow: Date {
        min(max(now, sessionStart), sessionEnd)
    }

    private var plottedHistory: [UsageSample] {
        guard let last = history.last else { return history }
        guard clampedNow > last.timestamp else { return history }
        return history + [UsageSample(timestamp: clampedNow, fiveHourPercent: last.fiveHourPercent)]
    }

    private var markerSample: UsageSample? {
        guard let last = history.last else { return nil }
        return UsageSample(timestamp: max(last.timestamp, clampedNow), fiveHourPercent: last.fiveHourPercent)
    }

    private var hourTicks: [Date] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: sessionStart)
        guard var tick = cal.date(from: comps) else { return [] }
        var ticks: [Date] = []
        while tick <= sessionEnd {
            if tick >= sessionStart { ticks.append(tick) }
            tick = tick.addingTimeInterval(3600)
        }
        return ticks
    }

    private var chartColor: Color { usageColor(for: bucket.percent) }

    private static let boundaryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session pace")
                    .dsType(.labelSm)
                    .foregroundStyle(DS.Text.muted)
                Spacer()
                if let last = history.last {
                    Text("\(Int(last.fiveHourPercent.rounded()))% used")
                        .dsType(.bodySm)
                        .foregroundStyle(DS.Text.secondary)
                        .monospacedDigit()
                }
            }

            Chart {
                ForEach(plottedHistory, id: \.timestamp) { sample in
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Usage", sample.fiveHourPercent)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [chartColor.opacity(0.22), chartColor.opacity(0.0)],
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
                .foregroundStyle(DS.Outline.soft.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

                LineMark(
                    x: .value("Time", sessionEnd),
                    y: .value("Pace", 100),
                    series: .value("Series", "pace")
                )
                .foregroundStyle(DS.Outline.soft.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

                ForEach(hourTicks, id: \.self) { tick in
                    RuleMark(x: .value("Hour", tick))
                        .foregroundStyle(DS.Outline.soft.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                }

                RuleMark(x: .value("Now", clampedNow))
                    .foregroundStyle(DS.Text.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let markerSample {
                    PointMark(
                        x: .value("Current", markerSample.timestamp),
                        y: .value("Usage", markerSample.fiveHourPercent)
                    )
                    .symbolSize(34)
                    .foregroundStyle(chartColor)
                }
            }
            .chartXScale(domain: sessionStart...sessionEnd)
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: hourTicks) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(),
                                   collisionResolution: .disabled)
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(DS.Text.muted.opacity(0.7))
                }
            }
            .frame(height: 180)
            .onReceive(ticker) { now = $0 }
        }
    }
}
