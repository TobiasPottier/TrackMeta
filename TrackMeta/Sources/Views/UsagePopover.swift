import SwiftUI
import Combine
import Charts

struct UsageCapBanner: View {
    let snapshot: UsageSnapshot

    private var resetText: String? {
        [snapshot.fiveHour.resetsAt, snapshot.sevenDay.resetsAt]
            .compactMap { $0 }
            .min()
            .map { "Next reset \(Self.resetFormatter.string(from: $0))" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "gauge.high")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text("Usage cap reached")
                    .font(.system(size: 12, weight: .semibold))
                if let resetText {
                    Text(resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(BrandPalette.muted)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()
}

struct UsageRow: View {
    let title: String
    let bucket: UsageBucket
    let sessionWindow: TimeInterval?
    var resetPlacement: ResetPlacement = .bottom

    enum ResetPlacement { case bottom, topCentered }

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var stripeProgress: Double? {
        guard let sessionWindow else { return nil }
        return bucket.sessionProgress(at: now, windowLength: sessionWindow)
    }

    private var resetText: String? {
        guard let reset = bucket.resetsAt else { return nil }
        return "Resets \(Self.resetFormatter.string(from: reset)) · \(Self.timeLeft(until: reset)) left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if resetPlacement == .topCentered, let text = resetText {
                    Text(text)
                        .font(.system(size: 10))
                        .foregroundStyle(BrandPalette.muted)
                        .monospacedDigit()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(bucket.percent.rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(for: bucket.percent))
                }
            }

            UsageBar(percent: bucket.percent, color: color(for: bucket.percent), stripeProgress: stripeProgress)
                .frame(height: 6)
                .onReceive(ticker) { now = $0 }

            if resetPlacement == .bottom, let text = resetText {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(BrandPalette.muted)
                    .monospacedDigit()
            }
        }
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

struct PeakHoursIndicator: View {
    private let window = PeakHoursWindow.claudeDefault

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                ForEach(plottedHistory, id: \.timestamp) { sample in
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

                ForEach(hourTicks, id: \.self) { tick in
                    RuleMark(x: .value("Hour", tick))
                        .foregroundStyle(Color.white.opacity(0.12))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                }

                RuleMark(x: .value("Now", clampedNow))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let markerSample {
                    PointMark(
                        x: .value("Current", markerSample.timestamp),
                        y: .value("Usage", markerSample.fiveHourPercent)
                    )
                    .symbolSize(36)
                    .foregroundStyle(chartColor)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Text("\(Int(markerSample.fiveHourPercent.rounded()))%")
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
            }
            .chartXScale(domain: sessionStart...sessionEnd)
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: hourTicks) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), collisionResolution: .disabled)
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.40))
                }
            }
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
