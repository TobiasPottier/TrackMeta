import SwiftUI

/// Modern Refinement design tokens — Slate-950 + Signal Green (IDE/terminal).
///
/// Anchored on a deep slate surface with a signal-green accent reserved for
/// primary actions and active states. Depth comes from tonal layering and
/// 1px low-contrast outlines, not shadows.
enum DS {

    // MARK: - Surfaces

    enum Surface {
        static let base               = Color(hex: 0x0F172A)
        static let dim                = Color(hex: 0x0B1220)
        static let bright             = Color(hex: 0x3A475F)
        static let containerLowest    = Color(hex: 0x020617)
        static let containerLow       = Color(hex: 0x131C33)
        static let container          = Color(hex: 0x1B2336)
        static let containerHigh      = Color(hex: 0x232D44)
        static let containerHighest   = Color(hex: 0x2D3850)
    }

    // MARK: - Foreground

    enum Text {
        /// Primary content (#F8FAFC — slate-50)
        static let primary       = Color(hex: 0xF8FAFC)
        /// Secondary metadata (#CBD5E1 — slate-300)
        static let secondary     = Color(hex: 0xCBD5E1)
        /// Muted / deactivated (#94A3B8 — slate-400)
        static let muted         = Color(hex: 0x94A3B8)
        /// Very low contrast, structural marks (#475569 — slate-600)
        static let faint         = Color(hex: 0x475569)
        /// Near-black with a green undertone for text on the accent.
        static let onPrimary     = Color(hex: 0x02110A)
    }

    // MARK: - Brand

    enum Primary {
        /// Signal green — the only chromatic accent. Use sparingly.
        static let accent        = Color(hex: 0x22C55E)
        /// Soft tint for tinted backgrounds (12–22% alpha applied at site).
        static let accentSoft    = Color(hex: 0x22C55E)
        /// High contrast pale variant for hover/glow.
        static let accentPale    = Color(hex: 0x86EFAC)
        static let onAccent      = Color(hex: 0x02110A)
    }

    // MARK: - Outlines

    enum Outline {
        /// Defining outline (#475569 — slate-600). Use at low opacity for chrome.
        static let strong        = Color(hex: 0x475569)
        /// Subtle structural border (#1E293B — slate-800).
        static let soft          = Color(hex: 0x1E293B)
    }

    // MARK: - Status

    enum Status {
        static let success       = Color(hex: 0x5EEAD4)   // teal-300 — distinct from the green accent
        static let warning       = Color(hex: 0xFBBF24)   // amber-400 — approaching cap
        static let danger        = Color(hex: 0xF87171)   // red-400 — softened error
    }

    // MARK: - Radii

    enum Radius {
        static let sm: CGFloat   = 2
        static let base: CGFloat = 4
        static let md: CGFloat   = 6
        static let lg: CGFloat   = 8
        static let xl: CGFloat   = 12
    }

    // MARK: - Spacing (8px rhythm)

    enum Space {
        static let xxs: CGFloat  = 4
        static let xs: CGFloat   = 8
        static let sm: CGFloat   = 12
        static let md: CGFloat   = 16
        static let lg: CGFloat   = 24
        static let xl: CGFloat   = 32
        static let xxl: CGFloat  = 48
        static let section: CGFloat = 64
    }

    // MARK: - Typography
    //
    // Inter isn't bundled; fall back to the system font with the same weights
    // and explicit tracking values. The Modern Refinement aesthetic is carried
    // by weight contrast + letter-spacing, which SF Pro supports cleanly.

    enum TextStyle {
        case display
        case headlineLg
        case headlineMd
        case bodyLg
        case bodyMd
        case bodySm
        case labelSm
        case mono
    }
}

extension View {
    /// Apply a typographic style from the design system.
    @ViewBuilder
    func dsType(_ style: DS.TextStyle) -> some View {
        switch style {
        case .display:
            self.font(.system(size: 56, weight: .bold))
                .tracking(-1.6)
                .lineSpacing(2)
        case .headlineLg:
            self.font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
        case .headlineMd:
            self.font(.system(size: 20, weight: .semibold))
                .tracking(-0.2)
        case .bodyLg:
            self.font(.system(size: 15, weight: .regular))
        case .bodyMd:
            self.font(.system(size: 13, weight: .regular))
        case .bodySm:
            self.font(.system(size: 11, weight: .regular))
        case .labelSm:
            self.font(.system(size: 10, weight: .medium))
                .tracking(0.9)
                .textCase(.uppercase)
        case .mono:
            self.font(.system(size: 11, weight: .regular, design: .monospaced))
        }
    }
}

// MARK: - Card chrome
//
// Cards default to "no fill" — just a 1px outline. This keeps the layout
// feeling light and editorial. Use `.elevated` only for grouping highly
// complex content.

enum DSCardStyle {
    case outline
    case elevated
    case tinted
}

struct DSCardModifier: ViewModifier {
    var style: DSCardStyle = .outline
    var radius: CGFloat = DS.Radius.lg
    var padding: CGFloat = DS.Space.md
    var hovering: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }

    private var fill: Color {
        switch style {
        case .outline:  return Color.clear
        case .elevated: return DS.Surface.containerLow
        case .tinted:   return DS.Primary.accent.opacity(0.06)
        }
    }

    private var strokeColor: Color {
        switch style {
        case .outline:  return DS.Outline.soft.opacity(hovering ? 1.0 : 0.6)
        case .elevated: return DS.Outline.soft.opacity(0.8)
        case .tinted:   return DS.Primary.accent.opacity(hovering ? 0.6 : 0.35)
        }
    }
}

extension View {
    func dsCard(
        _ style: DSCardStyle = .outline,
        radius: CGFloat = DS.Radius.lg,
        padding: CGFloat = DS.Space.md,
        hovering: Bool = false
    ) -> some View {
        modifier(DSCardModifier(style: style, radius: radius, padding: padding, hovering: hovering))
    }
}

// MARK: - Buttons

/// Solid amber primary button — black text, maximum prominence.
struct DSPrimaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(DS.Primary.onAccent)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.base, style: .continuous)
                    .fill(hovering ? DS.Primary.accentPale : DS.Primary.accent)
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Ghost / secondary — 1px outline, no fill, off-white text.
struct DSGhostButtonStyle: ButtonStyle {
    @State private var hovering = false
    var highlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(highlighted ? DS.Primary.accent : DS.Text.primary)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.base, style: .continuous)
                    .fill(hovering ? DS.Surface.containerLow : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.base, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }

    private var borderColor: Color {
        if highlighted { return DS.Primary.accent.opacity(0.7) }
        return DS.Outline.soft.opacity(hovering ? 1.0 : 0.6)
    }
}

/// Square icon button (32pt) with the ghost treatment.
struct DSIconButtonStyle: ButtonStyle {
    @State private var hovering = false
    var size: CGFloat = 32
    var highlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(highlighted ? DS.Primary.accent : DS.Text.secondary)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.base, style: .continuous)
                    .fill(hovering ? DS.Surface.containerLow : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.base, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }

    private var borderColor: Color {
        if highlighted { return DS.Primary.accent.opacity(0.7) }
        return DS.Outline.soft.opacity(hovering ? 1.0 : 0.6)
    }
}

// MARK: - Tag / chip

struct DSChip: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case danger
    }

    var body: some View {
        Text(text)
            .dsType(.labelSm)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(background)
            )
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return DS.Text.muted
        case .accent:  return DS.Primary.accent
        case .success: return DS.Status.success
        case .warning: return DS.Status.warning
        case .danger:  return DS.Status.danger
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return DS.Text.primary.opacity(0.06)
        case .accent:  return DS.Primary.accent.opacity(0.12)
        case .success: return DS.Status.success.opacity(0.12)
        case .warning: return DS.Status.warning.opacity(0.12)
        case .danger:  return DS.Status.danger.opacity(0.15)
        }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
