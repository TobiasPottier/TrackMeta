import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    private var percent: Double {
        min(100, max(0, snapshot.fiveHour.percent))
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: MenuBarIconRenderer.image(percent: percent))
            Text("\(Int(percent.rounded()))%")
                .monospacedDigit()
        }
    }
}

/// Renders the static tracker glyph + pill-shaped usage bar as a single NSImage.
/// MenuBarExtra labels don't reliably show multiple separate `Image(nsImage:)`
/// views when mixing template and non-template images, so we composite here.
private enum MenuBarIconRenderer {
    static let glyphSize: CGFloat = 16
    static let barWidth: CGFloat = 60
    static let barHeight: CGFloat = 8
    static let gap: CGFloat = 5

    private static var totalSize: NSSize {
        NSSize(width: glyphSize + gap + barWidth, height: glyphSize)
    }

    static func image(percent: Double) -> NSImage {
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
        drawBar(in: barRect, percent: percent)

        image.isTemplate = false
        return image
    }

    private static func drawGlyph(at rect: NSRect) {
        let cx = rect.midX
        let cy = rect.midY
        let stroke: CGFloat = 1.3

        let glyphColor = NSColor.labelColor
        glyphColor.setStroke()
        glyphColor.setFill()

        let outerR = rect.width * 0.40
        let outer = NSBezierPath(ovalIn: NSRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2))
        outer.lineWidth = stroke
        outer.stroke()

        let innerR = rect.width * 0.22
        let inner = NSBezierPath(ovalIn: NSRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        inner.lineWidth = stroke
        inner.stroke()

        let dotR: CGFloat = 1.4
        NSBezierPath(ovalIn: NSRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()

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

    private static func drawBar(in rect: NSRect, percent: Double) {
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
    }

    private static func fillColor(for percent: Double) -> NSColor {
        switch percent {
        case ..<50: return NSColor.systemGreen
        case ..<80: return NSColor.systemOrange
        default:    return NSColor.systemRed
        }
    }
}
