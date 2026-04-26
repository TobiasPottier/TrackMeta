import SwiftUI

/// Status colors are intentionally restrained — only the amber "needs input"
/// state is allowed to use the full primary accent. Working uses a calm green
/// so the pulsing indicator doesn't compete with primary CTAs.
enum SessionStatusPalette {
    static let working    = DS.Status.success
    static let idle       = DS.Text.muted
    static let awaiting   = DS.Primary.accent

    static func color(for status: ClaudeSession.Status) -> Color {
        switch status {
        case .working:       return working
        case .idle:          return idle
        case .awaitingInput: return awaiting
        }
    }
}

struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 7
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: size * 2.0, height: size * 2.0)
                .scaleEffect(pulse ? 1.35 : 1.0)
                .opacity(pulse ? 0.0 : 0.55)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.0, height: size * 2.0)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
