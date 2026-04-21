import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var percent: Double {
        min(100, max(0, snapshot.fiveHour.percent))
    }

    private var sessionProgress: Double? {
        snapshot.fiveHour.sessionProgress(at: now, windowLength: SessionWindow.fiveHourSeconds)
    }

    private var timeLeftText: String? {
        guard let resetsAt = snapshot.fiveHour.resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: MenuBarIconRenderer.image(percent: percent, sessionProgress: sessionProgress))
            Text("\(Int(percent.rounded()))%")
                .monospacedDigit()
            if let timeLeftText {
                Text(timeLeftText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(ticker) { now = $0 }
    }
}

/// Renders the static tracker glyph + pill-shaped usage bar as a single NSImage.
/// MenuBarExtra labels don't reliably show multiple separate `Image(nsImage:)`
/// views when mixing template and non-template images, so we composite here.
private enum MenuBarIconRenderer {
    static let glyphSize: CGFloat = 16
    static let barWidth: CGFloat = 110
    static let barHeight: CGFloat = 8
    static let gap: CGFloat = 5

    private static var totalSize: NSSize {
        NSSize(width: glyphSize + gap + barWidth, height: glyphSize)
    }

    static func image(percent: Double, sessionProgress: Double? = nil) -> NSImage {
        let size = totalSize
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        drawGlyph(at: NSRect(x: 0, y: 0, width: glyphSize, height: glyphSize))

        let barRect = NSRect(
            x: glyphSize + gap,
            y: (glyphSize - barHeight) / 2,
            width: barWidth,
            height: barHeight
        )
        drawBar(in: barRect, percent: percent, sessionProgress: sessionProgress)

        image.isTemplate = false
        return image
    }

    private static let accentColor = NSColor(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0, alpha: 1.0)

    private static func drawGlyph(at rect: NSRect) {
        let cx = rect.midX
        let cy = rect.midY
        let stroke: CGFloat = 1.3

        NSColor.labelColor.setStroke()

        let outerR = rect.width * 0.40
        let outer = NSBezierPath(ovalIn: NSRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2))
        outer.lineWidth = stroke
        outer.stroke()

        let innerR = rect.width * 0.22
        let inner = NSBezierPath(ovalIn: NSRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        inner.lineWidth = stroke
        inner.stroke()

        let dotR = rect.width * 0.08
        accentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()

        NSColor.labelColor.setStroke()
        let ticks = NSBezierPath()
        ticks.lineWidth = stroke
        ticks.lineCapStyle = .round
        let ti = rect.width * 0.46
        let to = rect.width * 0.50
        ticks.move(to: NSPoint(x: cx, y: cy + ti));  ticks.line(to: NSPoint(x: cx, y: cy + to))
        ticks.move(to: NSPoint(x: cx, y: cy - ti));  ticks.line(to: NSPoint(x: cx, y: cy - to))
        ticks.move(to: NSPoint(x: cx + ti, y: cy));  ticks.line(to: NSPoint(x: cx + to, y: cy))
        ticks.move(to: NSPoint(x: cx - ti, y: cy));  ticks.line(to: NSPoint(x: cx - to, y: cy))
        ticks.stroke()
    }

    private static func drawBar(in rect: NSRect, percent: Double, sessionProgress: Double?) {
        let radius = rect.height / 2

        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        track.fill()

        let clamped = max(0, min(100, percent))
        let fillWidth = max(rect.height, rect.width * CGFloat(clamped / 100))
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        fillColor(for: clamped).setFill()
        fill.fill()

        if let sessionProgress {
            let progress = max(0, min(1, sessionProgress))
            let stripeWidth: CGFloat = 1.5
            let overhang: CGFloat = 1.5
            let rawX = rect.minX + rect.width * CGFloat(progress)
            let x = min(max(rect.minX + stripeWidth / 2, rawX), rect.maxX - stripeWidth / 2)
            let stripeRect = NSRect(
                x: x - stripeWidth / 2,
                y: rect.minY - overhang,
                width: stripeWidth,
                height: rect.height + overhang * 2
            )
            NSColor.labelColor.setFill()
            NSBezierPath(rect: stripeRect).fill()
        }
    }

    private static func fillColor(for percent: Double) -> NSColor {
        switch percent {
        case ..<50: return NSColor.systemGreen
        case ..<80: return NSColor.systemOrange
        default:    return NSColor.systemRed
        }
    }
}
