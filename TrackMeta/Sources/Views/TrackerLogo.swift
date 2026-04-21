import SwiftUI

/// Official TrackMeta logo — a radar/crosshair "tracker" mark.
/// Mirrors the #09 "Tracker" design from `logo-ideas.html`.
struct TrackerLogo: View {
    var size: CGFloat = 28
    var accent: Color = BrandPalette.accent
    var ring: Color = BrandPalette.ringLight
    var filled: Bool = true

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let stroke = max(1.2, s * 0.055)

            // Outer ring
            let outerR = s * 0.38
            ctx.stroke(
                Path(ellipseIn: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2)),
                with: .color(ring),
                lineWidth: stroke
            )

            // Inner ring
            let innerR = s * 0.23
            ctx.stroke(
                Path(ellipseIn: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(ring),
                lineWidth: stroke
            )

            // Center dot
            let dotR = s * 0.08
            let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
            if filled {
                ctx.fill(Path(ellipseIn: dotRect), with: .color(accent))
            } else {
                ctx.stroke(Path(ellipseIn: dotRect), with: .color(accent), lineWidth: stroke)
            }

            // Crosshair ticks (N/S/E/W)
            let tickInner = s * 0.44
            let tickOuter = s * 0.50
            var ticks = Path()
            ticks.move(to: CGPoint(x: cx, y: cy - tickOuter)); ticks.addLine(to: CGPoint(x: cx, y: cy - tickInner))
            ticks.move(to: CGPoint(x: cx, y: cy + tickInner)); ticks.addLine(to: CGPoint(x: cx, y: cy + tickOuter))
            ticks.move(to: CGPoint(x: cx - tickOuter, y: cy)); ticks.addLine(to: CGPoint(x: cx - tickInner, y: cy))
            ticks.move(to: CGPoint(x: cx + tickInner, y: cy)); ticks.addLine(to: CGPoint(x: cx + tickOuter, y: cy))
            ctx.stroke(ticks, with: .color(ring), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

enum BrandPalette {
    static let accent       = Color(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0) // Claude orange
    static let accentSoft   = Color(red: 0xE8/255.0, green: 0xB0/255.0, blue: 0x8E/255.0)
    static let accentPale   = Color(red: 0xF3/255.0, green: 0xD6/255.0, blue: 0xC2/255.0)
    static let ringLight    = Color(white: 0.92)
    static let panelTop     = Color(red: 0x1B/255.0, green: 0x1E/255.0, blue: 0x24/255.0)
    static let panelBottom  = Color(red: 0x12/255.0, green: 0x13/255.0, blue: 0x17/255.0)
    static let border       = Color(red: 0x23/255.0, green: 0x26/255.0, blue: 0x2D/255.0)
    static let muted        = Color(red: 0x8A/255.0, green: 0x8F/255.0, blue: 0x98/255.0)
}

#Preview {
    HStack(spacing: 20) {
        TrackerLogo(size: 64)
        TrackerLogo(size: 32)
        TrackerLogo(size: 18)
    }
    .padding()
    .background(Color.black)
}
