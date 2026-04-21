import SwiftUI

struct SessionsSection: View {
    let sessions: [ClaudeSession]
    var isPinned: Bool = false
    var onTogglePin: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader
            if sessions.isEmpty {
                emptyState
            } else {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                }
            }
        }
    }

    private var workingCount: Int { sessions.filter { $0.status == .working }.count }
    private var awaitingCount: Int { sessions.filter { $0.status == .awaitingInput }.count }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text("Sessions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrandPalette.muted)
                .tracking(0.3)

            Text("(\(sessions.count))")
                .font(.system(size: 11))
                .foregroundStyle(BrandPalette.muted.opacity(0.5))

            Spacer()

            if awaitingCount > 0 {
                HStack(spacing: 4) {
                    PulsingDot(color: SessionStatusPalette.awaiting)
                    Text("\(awaitingCount) need input")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SessionStatusPalette.awaiting)
                }
            }

            if workingCount > 0 {
                HStack(spacing: 4) {
                    PulsingDot(color: SessionStatusPalette.working)
                    Text("\(workingCount) working")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SessionStatusPalette.working)
                }
            }

            if let onTogglePin {
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPinned ? BrandPalette.accent : BrandPalette.muted)
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin sessions from notch" : "Pin sessions under notch")
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 11))
                .foregroundStyle(BrandPalette.muted)
            Text("No sessions recorded yet")
                .font(.system(size: 11))
                .foregroundStyle(BrandPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }
}

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

private struct SessionRow: View {
    let session: ClaudeSession

    private var statusColor: Color { SessionStatusPalette.color(for: session.status) }

    var body: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayTool)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                    statusBadge
                }
                Text(timeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(BrandPalette.muted)
                    .monospacedDigit()
            }

            Spacer()

            Text(session.cwdDisplayName ?? String(session.sessionId.prefix(8)))
                .font(.system(size: 9).monospaced())
                .foregroundStyle(BrandPalette.muted.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rowBorder, lineWidth: 1)
        )
    }

    @ViewBuilder private var statusDot: some View {
        switch session.status {
        case .working, .awaitingInput:
            PulsingDot(color: statusColor)
        case .idle:
            Circle().fill(statusColor).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch session.status {
        case .working:
            badge("working", bg: statusColor, fg: .black.opacity(0.75))
        case .awaitingInput:
            badge("input needed", bg: statusColor, fg: .black.opacity(0.8))
        case .idle:
            badge("idle", bg: Color.white.opacity(0.12), fg: .white)
        }
    }

    private func badge(_ label: String, bg: Color, fg: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(bg))
    }

    private var rowBackground: Color {
        switch session.status {
        case .working:       return statusColor.opacity(0.06)
        case .awaitingInput: return statusColor.opacity(0.08)
        case .idle:          return Color.white.opacity(0.04)
        }
    }

    private var rowBorder: Color {
        switch session.status {
        case .working:       return statusColor.opacity(0.22)
        case .awaitingInput: return statusColor.opacity(0.30)
        case .idle:          return BrandPalette.border
        }
    }

    private var displayTool: String {
        session.summary ?? session.lastTool ?? "—"
    }

    private var timeLabel: String {
        let idle = "idle \(format(session.idleForSeconds))"
        if let tool = session.lastTool, session.summary != nil {
            return "\(tool) · \(idle)"
        }
        return idle
    }

    private func format(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 13, height: 13)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0 : 0.6)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
