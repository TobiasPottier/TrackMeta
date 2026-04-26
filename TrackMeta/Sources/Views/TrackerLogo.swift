import SwiftUI

/// TrackMeta logo — concentric rings + amber pulse dot. Redesigned for the
/// Modern Refinement system: thin strokes, monochrome neutrals, the amber
/// accent confined to the center mark.
struct TrackerLogo: View {
    var size: CGFloat = 28
    var accent: Color = DS.Primary.accent
    var ring: Color = DS.Text.primary
    var filled: Bool = true

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let stroke = max(1.0, s * 0.045)

            // Outer ring (faint)
            let outerR = s * 0.40
            ctx.stroke(
                Path(ellipseIn: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2)),
                with: .color(ring.opacity(0.45)),
                lineWidth: stroke
            )

            // Inner ring (slightly stronger)
            let innerR = s * 0.24
            ctx.stroke(
                Path(ellipseIn: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(ring.opacity(0.7)),
                lineWidth: stroke
            )

            // Center dot (the only chromatic mark)
            let dotR = s * 0.085
            let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
            if filled {
                ctx.fill(Path(ellipseIn: dotRect), with: .color(accent))
            } else {
                ctx.stroke(Path(ellipseIn: dotRect), with: .color(accent), lineWidth: stroke)
            }

            // Crosshair ticks (architectural metadata)
            let tickInner = s * 0.46
            let tickOuter = s * 0.50
            var ticks = Path()
            ticks.move(to: CGPoint(x: cx, y: cy - tickOuter)); ticks.addLine(to: CGPoint(x: cx, y: cy - tickInner))
            ticks.move(to: CGPoint(x: cx, y: cy + tickInner)); ticks.addLine(to: CGPoint(x: cx, y: cy + tickOuter))
            ticks.move(to: CGPoint(x: cx - tickOuter, y: cy)); ticks.addLine(to: CGPoint(x: cx - tickInner, y: cy))
            ticks.move(to: CGPoint(x: cx + tickInner, y: cy)); ticks.addLine(to: CGPoint(x: cx + tickOuter, y: cy))
            ctx.stroke(ticks,
                       with: .color(ring.opacity(0.5)),
                       style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Legacy palette mapped onto the Modern Refinement tokens. Kept so existing
/// view code keeps compiling — new code should reference `DS.*` directly.
enum BrandPalette {
    static let accent       = DS.Primary.accent
    static let accentSoft   = DS.Primary.accentPale
    static let accentPale   = DS.Primary.accentPale
    static let ringLight    = DS.Text.primary

    /// "Panel" tones now resolve to the unified surface (no gradient) so the
    /// app reads as a single editorial canvas rather than a layered widget.
    static let panelTop     = DS.Surface.base
    static let panelBottom  = DS.Surface.base
    static let sidebar      = DS.Surface.containerLowest
    static let cardFill     = DS.Surface.containerLow
    static let cardFillHi   = DS.Surface.container

    static let border       = DS.Outline.soft.opacity(0.55)
    static let borderSoft   = DS.Outline.soft.opacity(0.35)

    static let muted        = DS.Text.muted
    static let mutedStrong  = DS.Text.secondary
}

#Preview {
    HStack(spacing: 20) {
        TrackerLogo(size: 64)
        TrackerLogo(size: 32)
        TrackerLogo(size: 18)
    }
    .padding()
    .background(DS.Surface.base)
}
