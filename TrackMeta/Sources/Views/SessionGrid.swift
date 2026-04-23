import SwiftUI

/// Session overview: an aggregate header plus tiles laid out in a 2-column
/// grid (dashboard) or a single compact column (pinned notch drawer).
/// Tiles are sorted errors → awaitingInput → working → idle, then grouped
/// by project folder so multi-project swarms stay visually separated.
struct SessionGrid: View {
    @Bindable var model: UsageViewModel
    var variant: SessionTile.Variant = .standard
    var isPinned: Bool = false
    var onTogglePin: (() -> Void)? = nil
    var onLaunchAgent: ((URL, ITermSplit?) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: variant == .compact ? 8 : 12) {
            aggregateHeader
            if model.sessions.isEmpty {
                emptyState
            } else {
                ForEach(groupedSessions, id: \.key) { group in
                    VStack(alignment: .leading, spacing: variant == .compact ? 6 : 8) {
                        if variant == .standard && groupedSessions.count > 1 {
                            groupHeader(group)
                        }
                        tileLayout(for: group.sessions)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var aggregateHeader: some View {
        HStack(spacing: 8) {
            aggregateStatusDot
            VStack(alignment: .leading, spacing: 1) {
                Text(aggregateTitle)
                    .font(.system(size: variant == .compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(aggregateSubtitle)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(BrandPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if variant == .standard,
               onLaunchAgent != nil,
               let folder = singleGroupFolder {
                launchAgentButton(folder: folder)
            }
            if let onTogglePin {
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPinned ? BrandPalette.accent : BrandPalette.muted)
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin sessions" : "Pin sessions to notch")
            }
        }
    }

    @ViewBuilder private var aggregateStatusDot: some View {
        if awaitingCount > 0 {
            PulsingDot(color: SessionStatusPalette.awaiting, size: 8)
        } else if workingCount > 0 {
            PulsingDot(color: SessionStatusPalette.working, size: 8)
        } else {
            Circle()
                .fill(BrandPalette.muted.opacity(0.6))
                .frame(width: 8, height: 8)
                .frame(width: 15, height: 15)
        }
    }

    private var aggregateTitle: String {
        if let only = singleGroupName { return only }
        return model.sessions.isEmpty ? "Sessions" : "\(groupedSessions.count) projects"
    }

    private var aggregateSubtitle: String {
        let parts = [
            "\(workingCount)/\(model.sessions.count) running",
            awaitingCount > 0 ? "\(awaitingCount) awaiting" : nil,
            totalElapsedLabel
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundStyle(BrandPalette.muted)
            Text(group.key)
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(BrandPalette.muted)
                .tracking(0.3)
            Text("(\(group.sessions.count))")
                .font(.system(size: 10))
                .foregroundStyle(BrandPalette.muted.opacity(0.6))
            if onLaunchAgent != nil, let folder = folder(for: group) {
                launchAgentButton(folder: folder)
            }
        }
    }

    private func launchAgentButton(folder: URL) -> some View {
        HStack(spacing: 3) {
            Button {
                onLaunchAgent?(folder, nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BrandPalette.accent)
                    .padding(4)
                    .background(Circle().fill(BrandPalette.accent.opacity(0.18)))
                    .overlay(Circle().stroke(BrandPalette.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Launch new agent in \(folder.lastPathComponent) as a new tab")

            Menu {
                Button {
                    onLaunchAgent?(folder, .right)
                } label: {
                    Label("Split right", systemImage: "rectangle.righthalf.inset.filled")
                }
                Button {
                    onLaunchAgent?(folder, .left)
                } label: {
                    Label("Split left", systemImage: "rectangle.lefthalf.inset.filled")
                }
                Button {
                    onLaunchAgent?(folder, .down)
                } label: {
                    Label("Split down", systemImage: "rectangle.bottomhalf.inset.filled")
                }
                Button {
                    onLaunchAgent?(folder, .up)
                } label: {
                    Label("Split up", systemImage: "rectangle.tophalf.inset.filled")
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(BrandPalette.accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BrandPalette.accent.opacity(0.12)))
                    .overlay(Capsule().stroke(BrandPalette.accent.opacity(0.3), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Split existing iTerm window with a new agent")
        }
    }

    private func folder(for group: SessionGroup) -> URL? {
        guard let cwd = group.sessions.first?.cwd else { return nil }
        return URL(fileURLWithPath: cwd)
    }

    private var singleGroupFolder: URL? {
        let groups = groupedSessions
        guard groups.count == 1, let group = groups.first else { return nil }
        return folder(for: group)
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tileLayout(for sessions: [ClaudeSession]) -> some View {
        let columns: [GridItem] = {
            if variant == .compact { return [GridItem(.flexible(), spacing: 6)] }
            return [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]
        }()

        LazyVGrid(columns: columns, alignment: .leading, spacing: variant == .compact ? 6 : 10) {
            ForEach(sessions) { session in
                SessionTile(
                    session: session,
                    history: model.sessionHistories[session.sessionId],
                    isExpanded: model.isExpanded(session.sessionId),
                    variant: variant,
                    onToggleExpand: { model.toggleExpanded(session.sessionId) },
                    onDismiss: { model.dismissSession(session.sessionId) }
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 11))
                .foregroundStyle(BrandPalette.muted)
            Text("No active sessions")
                .font(.system(size: 11))
                .foregroundStyle(BrandPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }

    // MARK: - Grouping + sorting

    struct SessionGroup {
        let key: String
        let sessions: [ClaudeSession]
    }

    private var groupedSessions: [SessionGroup] {
        var order: [String] = []
        var buckets: [String: [ClaudeSession]] = [:]
        for session in sortedSessions {
            let key = session.cwdDisplayName ?? "Unknown folder"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(session)
        }
        return order.map { SessionGroup(key: $0, sessions: buckets[$0] ?? []) }
    }

    /// Sort tiles so attention-grabbing ones float up. Stable within buckets
    /// by sessionId so tiles don't swap places on every poll.
    private var sortedSessions: [ClaudeSession] {
        model.sessions.sorted { lhs, rhs in
            let lRank = statusRank(lhs.status)
            let rRank = statusRank(rhs.status)
            if lRank != rRank { return lRank < rRank }
            return lhs.sessionId < rhs.sessionId
        }
    }

    private func statusRank(_ status: ClaudeSession.Status) -> Int {
        switch status {
        case .awaitingInput: return 0
        case .working:       return 1
        case .idle:          return 2
        }
    }

    // MARK: - Aggregates

    private var workingCount: Int { model.sessions.filter { $0.status == .working }.count }
    private var awaitingCount: Int { model.sessions.filter { $0.status == .awaitingInput }.count }

    private var singleGroupName: String? {
        let unique = Set(model.sessions.compactMap { $0.cwdDisplayName })
        return unique.count == 1 ? unique.first : nil
    }

    private var totalElapsedLabel: String? {
        guard !model.sessions.isEmpty else { return nil }
        let now = Date()
        let earliest = model.sessions
            .compactMap { model.sessionHistories[$0.sessionId]?.firstSeenAt }
            .min()
        guard let earliest else { return nil }
        return formatElapsed(now.timeIntervalSince(earliest))
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rm = m % 60
        return "\(h)h \(rm)m"
    }
}
