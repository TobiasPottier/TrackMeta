import SwiftUI

/// One agent tile. Outline-only by default; the only fill is a 6% amber wash
/// when a session is awaiting input, so the eye lands on it without the rest
/// of the grid lighting up. Idle / working tiles read as quiet metadata.
struct SessionTile: View {
    let session: ClaudeSession
    let history: SessionHistory?
    let isExpanded: Bool
    var variant: Variant = .standard
    var onToggleExpand: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var now: Date = Date()
    @State private var hovering: Bool = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Variant {
        case standard
        case compact
    }

    private var isCompact: Bool { variant == .compact }
    private var radius: CGFloat { isCompact ? DS.Radius.md : DS.Radius.lg }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : DS.Space.xs) {
            headerRow
            if !isCompact || isExpanded {
                eventLine
            }
            if !isCompact {
                activityRow
            }
            if isExpanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, isCompact ? DS.Space.sm : DS.Space.sm)
        .padding(.vertical, isCompact ? DS.Space.xs : DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { onToggleExpand?() }
        .onReceive(ticker) { now = $0 }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: DS.Space.xs) {
            statusDot
            Text(titleText)
                .font(.system(size: isCompact ? 11 : 13, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(DS.Text.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(elapsedLabel)
                .dsType(.bodySm)
                .monospacedDigit()
                .foregroundStyle(DS.Text.muted)
            if isExpanded, onToggleExpand != nil {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Text.muted)
            }
        }
    }

    private var eventLine: some View {
        eventLineContent
            .dsType(.bodySm)
            .foregroundStyle(DS.Text.muted)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventLineContent: Text {
        if let tool = session.lastTool, !tool.isEmpty {
            return actionText(tool, target: session.lastToolTarget)
        }
        if let name = session.cwdDisplayName { return Text(name) }
        return Text("—")
    }

    private func actionText(_ raw: String, target: String? = nil) -> Text {
        let parsed = Self.parseAction(raw)
        let action = parsed.action.isEmpty ? raw : parsed.action
        if let target,
           !target.isEmpty,
           Self.fileTools.contains(action) {
            let file = URL(fileURLWithPath: target).lastPathComponent
            if !file.isEmpty {
                return Text(action) + Text(" ")
                    + Text(file).bold().foregroundColor(DS.Text.primary)
            }
        }
        if let file = parsed.fileName {
            return Text(parsed.action) + Text(" ")
                + Text(file).bold().foregroundColor(DS.Text.primary)
        }
        return Text(action)
    }

    private static let fileTools: Set<String> = [
        "Read", "Write", "Edit", "MultiEdit", "NotebookEdit", "NotebookRead",
        "Glob", "Grep", "LS", "Open"
    ]

    private struct ParsedAction {
        let action: String
        let fileName: String?
    }

    private static func parseAction(_ raw: String) -> ParsedAction {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.firstIndex(of: "("),
              let close = trimmed.lastIndex(of: ")"),
              open < close else {
            return ParsedAction(action: trimmed, fileName: nil)
        }
        let name = String(trimmed[trimmed.startIndex..<open])
            .trimmingCharacters(in: .whitespaces)
        guard fileTools.contains(name) else {
            return ParsedAction(action: trimmed, fileName: nil)
        }
        let inside = String(trimmed[trimmed.index(after: open)..<close])
        guard let path = extractPath(from: inside) else {
            return ParsedAction(action: name, fileName: nil)
        }
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return ParsedAction(action: name, fileName: fileName.isEmpty ? nil : fileName)
    }

    private static func extractPath(from inside: String) -> String? {
        let stripped = inside.trimmingCharacters(in: .whitespaces)
        let candidate: String
        if let eq = stripped.firstIndex(of: "=") {
            candidate = String(stripped[stripped.index(after: eq)...])
        } else {
            candidate = stripped
        }
        let unquoted = candidate
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let first = unquoted.split(whereSeparator: { $0 == "," || $0 == " " }).first.map(String.init) ?? unquoted
        let value = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !value.isEmpty else { return nil }
        if value.contains("/") || value.contains(".") { return value }
        return nil
    }

    private var activityRow: some View {
        HStack(spacing: DS.Space.xs) {
            ActivitySparkline(buckets: history?.activityBuckets ?? [], color: statusColor)
                .frame(height: 10)
            Spacer(minLength: 0)
            if let pct = session.contextPercentage {
                contextBadge(pct)
            }
            statusTag
        }
    }

    private func contextBadge(_ pct: Double) -> some View {
        let clamped = min(max(pct, 0), 100)
        let tone: DSChip.Tone = clamped >= 90 ? .danger
                              : clamped >= 70 ? .warning
                              : .neutral
        return DSChip(text: "\(Int(clamped))% ctx", tone: tone)
    }

    @ViewBuilder private var expandedDetail: some View {
        Divider()
            .overlay(DS.Outline.soft.opacity(0.5))
            .padding(.vertical, 2)

        if let cwd = session.cwd {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Text.muted)
                Text(cwd)
                    .dsType(.mono)
                    .foregroundStyle(DS.Text.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }

        if let events = history?.events, !events.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .dsType(.labelSm)
                    .foregroundStyle(DS.Text.muted)
                    .padding(.top, 4)
                ForEach(events.reversed().prefix(4)) { event in
                    eventRow(event)
                }
            }
        }

        HStack(spacing: 6) {
            Spacer()
            if let onDismiss {
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(DSGhostButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    private func eventRow(_ event: SessionEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: eventIcon(event.kind))
                .font(.system(size: 9))
                .foregroundStyle(DS.Text.muted)
                .frame(width: 12)
            eventText(event.kind)
                .dsType(.bodySm)
                .foregroundStyle(DS.Text.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(relative(event.timestamp))
                .font(.system(size: 9, weight: .regular).monospacedDigit())
                .foregroundStyle(DS.Text.muted.opacity(0.8))
        }
    }

    // MARK: - Bits

    @ViewBuilder private var statusDot: some View {
        switch session.status {
        case .working, .awaitingInput:
            PulsingDot(color: statusColor, size: isCompact ? 6 : 7)
        case .idle:
            Circle()
                .stroke(statusColor.opacity(0.6), lineWidth: 1)
                .frame(width: isCompact ? 6 : 7, height: isCompact ? 6 : 7)
                .frame(width: 14, height: 14)
        }
    }

    private var statusTag: some View {
        DSChip(text: statusTagLabel, tone: statusTagTone)
    }

    private var statusTagTone: DSChip.Tone {
        switch session.status {
        case .working:        return .success
        case .awaitingInput:  return .accent
        case .idle:           return .neutral
        }
    }

    // MARK: - Derived

    private var titleText: String {
        if let summary = session.summary, !summary.isEmpty { return summary }
        if let name = session.cwdDisplayName { return name }
        return String(session.sessionId.prefix(8))
    }

    private var elapsedLabel: String {
        guard let history else { return "—" }
        return formatElapsed(history.elapsed(now: now))
    }

    private var statusTagLabel: String {
        switch session.status {
        case .working:        return "Working"
        case .awaitingInput:  return "Needs input"
        case .idle:           return "Idle"
        }
    }

    private var statusColor: Color { SessionStatusPalette.color(for: session.status) }

    /// Backgrounds are tonal-only — no chromatic fills except the amber wash
    /// for "needs input", which is the single state we actively want the eye
    /// to find.
    private var background: Color {
        switch session.status {
        case .working:       return Color.clear
        case .awaitingInput: return DS.Primary.accent.opacity(0.06)
        case .idle:          return Color.clear
        }
    }

    private var border: Color {
        let hoverBoost = hovering ? 0.4 : 0.0
        switch session.status {
        case .working:
            return DS.Outline.soft.opacity(0.55 + hoverBoost)
        case .awaitingInput:
            return DS.Primary.accent.opacity(0.45 + hoverBoost * 0.5)
        case .idle:
            return DS.Outline.soft.opacity(0.4 + hoverBoost)
        }
    }

    private func eventIcon(_ kind: SessionEvent.Kind) -> String {
        switch kind {
        case .toolChanged:       return "wrench.and.screwdriver"
        case .summaryChanged:    return "text.alignleft"
        case .statusChanged(let s):
            switch s {
            case .working:       return "play.fill"
            case .awaitingInput: return "keyboard"
            case .idle:          return "pause"
            }
        }
    }

    private func eventText(_ kind: SessionEvent.Kind) -> Text {
        switch kind {
        case .toolChanged(let tool, let target):
            return actionText(tool, target: target)
        case .summaryChanged(let summary):
            return Text(summary)
        case .statusChanged(let status):
            switch status {
            case .working:        return Text("Started working")
            case .awaitingInput:  return Text("Awaiting input")
            case .idle:           return Text("Went idle")
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        if m < 60 { return String(format: "%d:%02d", m, r) }
        let h = m / 60
        let rm = m % 60
        return String(format: "%dh %02dm", h, rm)
    }
}

/// Per-minute event sparkline — capsule bars to match the "soft" shape
/// language. Empty buckets render as faint outline marks rather than filled
/// stubs so the line stays quiet.
struct ActivitySparkline: View {
    let buckets: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(buckets.max() ?? 0, 1)
            let count = max(buckets.count, 1)
            let spacing: CGFloat = 1
            let barWidth = max(1, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, value in
                    Capsule(style: .continuous)
                        .fill(value > 0 ? color.opacity(0.85) : DS.Outline.soft.opacity(0.4))
                        .frame(
                            width: barWidth,
                            height: max(1, geo.size.height * CGFloat(value) / CGFloat(maxValue))
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }
}
