import SwiftUI

enum SessionStatusPalette {
    static let working    = Color(red: 0.34, green: 0.78, blue: 0.47)
    static let idle       = Color(white: 0.65)
    static let awaiting   = Color(red: 0.98, green: 0.80, blue: 0.22)

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
                .fill(color.opacity(0.25))
                .frame(width: size * 1.85, height: size * 1.85)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 0.15 : 0.6)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.85, height: size * 1.85)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
