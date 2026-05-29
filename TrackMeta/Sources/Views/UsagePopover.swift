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

// MARK: - Usage forecast
//
// Ordinary least-squares fit over the in-window history projects where usage
// will end up. The slope is the average burn rate across the whole window, so
// it does not collapse when the most recent samples flatten — a short pause, or
// the idle gap around an app relaunch, no longer yanks the projection back under
// 100%. The result is the endpoint of the forecast segment that begins at the
// current sample — either at the session end, or earlier if the slope would push
// usage past 100% before the window closes.

struct UsageForecast {
    let endTime: Date
    let endValue: Double
}

func linearUsageForecast(
    samples: [UsageSample],
    valueFor: (UsageSample) -> Double,
    currentTime: Date,
    currentValue: Double,
    until endTime: Date
) -> UsageForecast? {
    guard endTime > currentTime else { return nil }
    let scoped = samples.filter { $0.timestamp <= currentTime }
    guard scoped.count >= 2,
          let first = scoped.first,
          let last = scoped.last,
          last.timestamp.timeIntervalSince(first.timestamp) >= 60 else { return nil }

    let referenceTime = last.timestamp.timeIntervalSince1970
    let xs = scoped.map { $0.timestamp.timeIntervalSince1970 - referenceTime }
    let ys = scoped.map(valueFor)
    let n = Double(scoped.count)
    let meanX = xs.reduce(0, +) / n
    let meanY = ys.reduce(0, +) / n

    var num = 0.0
    var den = 0.0
    for i in xs.indices {
        let dx = xs[i] - meanX
        num += dx * (ys[i] - meanY)
        den += dx * dx
    }
    guard den > 0 else { return nil }
    let slope = num / den

    let deltaSeconds = endTime.timeIntervalSince(currentTime)
    let projectedRaw = currentValue + slope * deltaSeconds

    // If the projection rounds to 100% (within-window cap, or just close
    // enough that the label would say "100"), report the ETA when the slope
    // would actually cross 100 rather than the rounded end-of-window value.
    if slope > 0, currentValue < 100, projectedRaw.rounded() >= 100 {
        let secondsToCap = (100 - currentValue) / slope
        if secondsToCap > 0 {
            return UsageForecast(
                endTime: currentTime.addingTimeInterval(secondsToCap),
                endValue: 100
            )
        }
    }
    let clamped = min(100, max(0, projectedRaw))
    return UsageForecast(endTime: endTime, endValue: clamped)
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

    private var windowedHistory: [UsageSample] {
        history.filter { $0.timestamp >= sessionStart && $0.timestamp <= sessionEnd }
    }

    private var plottedHistory: [UsageSample] {
        let scoped = windowedHistory
        guard let last = scoped.last else { return scoped }
        guard clampedNow > last.timestamp else { return scoped }
        return scoped + [UsageSample(
            timestamp: clampedNow,
            fiveHourPercent: last.fiveHourPercent,
            sevenDayPercent: last.sevenDayPercent
        )]
    }

    private var markerSample: UsageSample? {
        plottedHistory.last
    }

    private var forecast: UsageForecast? {
        guard let marker = markerSample else { return nil }
        return linearUsageForecast(
            samples: windowedHistory,
            valueFor: { $0.fiveHourPercent },
            currentTime: marker.timestamp,
            currentValue: marker.fiveHourPercent,
            until: sessionEnd
        )
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

    private func forecastLabel(_ forecast: UsageForecast) -> String {
        if Int(forecast.endValue.rounded()) >= 100 {
            return "hits 100% at \(Self.boundaryFormatter.string(from: forecast.endTime))"
        }
        return "\(Int(forecast.endValue.rounded()))% by reset"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session pace")
                    .dsType(.labelSm)
                    .foregroundStyle(DS.Text.muted)
                Spacer()
                if let last = windowedHistory.last {
                    HStack(spacing: DS.Space.xs) {
                        Text("\(Int(last.fiveHourPercent.rounded()))% used")
                            .dsType(.bodySm)
                            .foregroundStyle(DS.Text.secondary)
                            .monospacedDigit()
                        if let forecast {
                            Text("· \(forecastLabel(forecast))")
                                .dsType(.bodySm)
                                .foregroundStyle(DS.Text.muted)
                                .monospacedDigit()
                        }
                    }
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
                .foregroundStyle(DS.Text.muted.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))

                LineMark(
                    x: .value("Time", sessionEnd),
                    y: .value("Pace", 100),
                    series: .value("Series", "pace")
                )
                .foregroundStyle(DS.Text.muted.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))

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

                if let markerSample, let forecast {
                    LineMark(
                        x: .value("Time", markerSample.timestamp),
                        y: .value("Usage", markerSample.fiveHourPercent),
                        series: .value("Series", "forecast")
                    )
                    .foregroundStyle(chartColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Time", forecast.endTime),
                        y: .value("Usage", forecast.endValue),
                        series: .value("Series", "forecast")
                    )
                    .foregroundStyle(chartColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("Forecast", forecast.endTime),
                        y: .value("Usage", forecast.endValue)
                    )
                    .symbolSize(20)
                    .foregroundStyle(chartColor.opacity(0.55))
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

// MARK: - Weekly usage chart

struct WeeklyUsageChart: View {
    let history: [UsageSample]
    let bucket: UsageBucket

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var weekStart: Date {
        if let resetsAt = bucket.resetsAt {
            return resetsAt.addingTimeInterval(-SessionWindow.sevenDaySeconds)
        }
        return history.first?.timestamp ?? now.addingTimeInterval(-SessionWindow.sevenDaySeconds)
    }

    private var weekEnd: Date {
        bucket.resetsAt ?? now
    }

    private var clampedNow: Date {
        min(max(now, weekStart), weekEnd)
    }

    private var windowedHistory: [UsageSample] {
        history.filter { $0.timestamp >= weekStart && $0.timestamp <= weekEnd }
    }

    private var plottedHistory: [UsageSample] {
        let scoped = windowedHistory
        guard let last = scoped.last else { return scoped }
        guard clampedNow > last.timestamp else { return scoped }
        return scoped + [UsageSample(
            timestamp: clampedNow,
            fiveHourPercent: last.fiveHourPercent,
            sevenDayPercent: last.sevenDayPercent
        )]
    }

    private var markerSample: UsageSample? { plottedHistory.last }

    private var forecast: UsageForecast? {
        guard let marker = markerSample else { return nil }
        return linearUsageForecast(
            samples: windowedHistory,
            valueFor: { $0.sevenDayPercent },
            currentTime: marker.timestamp,
            currentValue: marker.sevenDayPercent,
            until: weekEnd
        )
    }

    private var dayTicks: [Date] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: weekStart)
        guard var tick = cal.date(from: comps) else { return [] }
        var ticks: [Date] = []
        while tick <= weekEnd {
            if tick >= weekStart { ticks.append(tick) }
            guard let next = cal.date(byAdding: .day, value: 1, to: tick) else { break }
            tick = next
        }
        return ticks
    }

    private var chartColor: Color { usageColor(for: bucket.percent) }

    private static let forecastFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private func forecastLabel(_ forecast: UsageForecast) -> String {
        if Int(forecast.endValue.rounded()) >= 100 {
            return "hits 100% at \(Self.forecastFormatter.string(from: forecast.endTime))"
        }
        return "\(Int(forecast.endValue.rounded()))% by reset"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly pace")
                    .dsType(.labelSm)
                    .foregroundStyle(DS.Text.muted)
                Spacer()
                if let last = windowedHistory.last {
                    HStack(spacing: DS.Space.xs) {
                        Text("\(Int(last.sevenDayPercent.rounded()))% used")
                            .dsType(.bodySm)
                            .foregroundStyle(DS.Text.secondary)
                            .monospacedDigit()
                        if let forecast {
                            Text("· \(forecastLabel(forecast))")
                                .dsType(.bodySm)
                                .foregroundStyle(DS.Text.muted)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Chart {
                ForEach(plottedHistory, id: \.timestamp) { sample in
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Usage", sample.sevenDayPercent)
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
                        y: .value("Usage", sample.sevenDayPercent)
                    )
                    .foregroundStyle(chartColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                LineMark(
                    x: .value("Time", weekStart),
                    y: .value("Pace", 0),
                    series: .value("Series", "pace")
                )
                .foregroundStyle(DS.Text.muted.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))

                LineMark(
                    x: .value("Time", weekEnd),
                    y: .value("Pace", 100),
                    series: .value("Series", "pace")
                )
                .foregroundStyle(DS.Text.muted.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))

                ForEach(dayTicks, id: \.self) { tick in
                    RuleMark(x: .value("Day", tick))
                        .foregroundStyle(DS.Outline.soft.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                }

                RuleMark(x: .value("Now", clampedNow))
                    .foregroundStyle(DS.Text.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let markerSample {
                    PointMark(
                        x: .value("Current", markerSample.timestamp),
                        y: .value("Usage", markerSample.sevenDayPercent)
                    )
                    .symbolSize(34)
                    .foregroundStyle(chartColor)
                }

                if let markerSample, let forecast {
                    LineMark(
                        x: .value("Time", markerSample.timestamp),
                        y: .value("Usage", markerSample.sevenDayPercent),
                        series: .value("Series", "forecast")
                    )
                    .foregroundStyle(chartColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Time", forecast.endTime),
                        y: .value("Usage", forecast.endValue),
                        series: .value("Series", "forecast")
                    )
                    .foregroundStyle(chartColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("Forecast", forecast.endTime),
                        y: .value("Usage", forecast.endValue)
                    )
                    .symbolSize(20)
                    .foregroundStyle(chartColor.opacity(0.55))
                }
            }
            .chartXScale(domain: weekStart...weekEnd)
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: dayTicks) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated),
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
