import SwiftUI

/// A single agent tile for the session overview. Has two layouts:
/// - Collapsed (68pt) for glanceable per-agent status.
/// - Expanded (~200pt) for the full prompt / recent events / actions.
/// A compact variant is used in the pinned notch drawer so more agents fit
/// in limited vertical space.
struct SessionTile: View {
    let session: ClaudeSession
    let history: SessionHistory?
    let isExpanded: Bool
    var variant: Variant = .standard
    var onToggleExpand: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var now: Date = Date()
    @State private var displayedAction: String = ""
    @State private var actionVersion: Int = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Variant {
        case standard   // dashboard grid
        case compact    // pinned notch drawer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: variant == .compact ? 4 : 6) {
            headerRow
            if variant != .compact || isExpanded {
                eventLine
            }
            if variant == .standard {
                activityRow
            }
            if isExpanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, variant == .compact ? 10 : 12)
        .padding(.vertical, variant == .compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: variant == .compact ? 10 : 12, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: variant == .compact ? 10 : 12, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onToggleExpand?()
        }
        .onAppear { displayedAction = currentAction }
        .onChange(of: currentAction) { _, newValue in
            withAnimation(.easeOut(duration: 0.28)) {
                displayedAction = newValue
                actionVersion += 1
            }
        }
        .onReceive(ticker) { now = $0 }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 8) {
            statusDot
            Text(titleText)
                .font(.system(size: variant == .compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(elapsedLabel)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(BrandPalette.muted)
            actionIcon
            if isExpanded, onToggleExpand != nil {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BrandPalette.muted)
            }
        }
    }

    private var rollingActionLabel: some View {
        HStack(spacing: 3) {
            Text("·")
                .font(.system(size: 9))
                .foregroundStyle(BrandPalette.muted.opacity(0.4))
            ZStack {
                actionText(displayedAction, target: session.lastToolTarget)
                    .font(.system(size: 10))
                    .foregroundStyle(BrandPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(actionVersion)
                    .transition(.asymmetric(
                        insertion: .push(from: .bottom),
                        removal: .push(from: .top)
                    ))
            }
            .frame(maxWidth: 120, alignment: .leading)
            .clipped()
        }
    }

    private var eventLine: some View {
        eventLineContent
            .font(.system(size: 10))
            .foregroundStyle(BrandPalette.muted)
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
                return Text(action) + Text(" ") + Text(file).bold().foregroundColor(.white)
            }
        }
        if let file = parsed.fileName {
            return Text(parsed.action) + Text(" ") + Text(file).bold().foregroundColor(.white)
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
        HStack(spacing: 6) {
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
        let color: Color = clamped >= 90 ? .red
                         : clamped >= 70 ? .orange
                         : BrandPalette.muted
        return HStack(spacing: 3) {
            Image(systemName: "doc.text")
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text("\(Int(clamped))%")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    @ViewBuilder private var expandedDetail: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
            .padding(.vertical, 2)

        if let cwd = session.cwd {
            Label {
                Text(cwd)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(BrandPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(BrandPalette.muted)
            }
        }

        if let events = history?.events, !events.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recent")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.muted.opacity(0.8))
                    .padding(.top, 4)
                ForEach(events.reversed().prefix(4)) { event in
                    eventRow(event)
                }
            }
        }

        HStack(spacing: 6) {
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private func eventRow(_ event: SessionEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: eventIcon(event.kind))
                .font(.system(size: 9))
                .foregroundStyle(BrandPalette.muted)
                .frame(width: 12)
            eventText(event.kind)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(relative(event.timestamp))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(BrandPalette.muted.opacity(0.7))
        }
    }

    // MARK: - Bits

    @ViewBuilder private var statusDot: some View {
        switch session.status {
        case .working, .awaitingInput:
            PulsingDot(color: statusColor, size: variant == .compact ? 6 : 7)
        case .idle:
            Circle()
                .fill(statusColor)
                .frame(width: variant == .compact ? 6 : 7,
                       height: variant == .compact ? 6 : 7)
                .frame(width: 13, height: 13)
        }
    }

    @ViewBuilder private var actionIcon: some View {
        Image(systemName: actionSymbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(statusColor)
            .frame(width: 14)
    }

    private var statusTag: some View {
        Text(statusTagLabel)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(statusColor)
    }

    // MARK: - Derived

    private var currentAction: String {
        session.lastTool ?? ""
    }

    private var titleText: String {
        if let summary = session.summary, !summary.isEmpty { return summary }
        if let name = session.cwdDisplayName { return name }
        return String(session.sessionId.prefix(8))
    }

    private var elapsedLabel: String {
        guard let history else { return "—" }
        return formatElapsed(history.elapsed(now: now))
    }

    private var actionSymbol: String {
        switch session.status {
        case .working:        return "arrow.triangle.2.circlepath"
        case .awaitingInput:  return "keyboard"
        case .idle:           return "pause.circle"
        }
    }

    private var statusTagLabel: String {
        switch session.status {
        case .working:        return "WORKING"
        case .awaitingInput:  return "NEEDS INPUT"
        case .idle:           return "IDLE"
        }
    }

    private var statusColor: Color { SessionStatusPalette.color(for: session.status) }

    private var background: Color {
        switch session.status {
        case .working:       return statusColor.opacity(0.07)
        case .awaitingInput: return statusColor.opacity(0.10)
        case .idle:          return Color.white.opacity(0.04)
        }
    }

    private var border: Color {
        switch session.status {
        case .working:       return statusColor.opacity(0.25)
        case .awaitingInput: return statusColor.opacity(0.36)
        case .idle:          return BrandPalette.border
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

/// Thin bar chart of per-minute event counts. Flat line when a session has
/// been idle; tall bars when it's been firing off tool calls.
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
                        .fill(value > 0 ? color.opacity(0.85) : Color.white.opacity(0.10))
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
