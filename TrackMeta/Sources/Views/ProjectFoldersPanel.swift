import SwiftUI
import AppKit

/// Read-only overview of live Claude Code sessions, grouped by their working
/// directory. Each group shows a folder header plus indented SessionTiles.
struct ProjectFoldersPanel: View {
    @Bindable var model: UsageViewModel
    var variant: SessionTile.Variant = .standard
    var isPinned: Bool = false
    var onTogglePin: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: variant == .compact ? 8 : 10) {
            panelHeader
            let groups = model.unifiedFolderGroups
            if groups.isEmpty {
                emptyState
            } else {
                ForEach(groups) { group in
                    folderSection(group)
                }
            }
        }
    }

    // MARK: - Panel header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: variant == .compact ? 10 : 12))
                .foregroundStyle(BrandPalette.accent)
            Text("Sessions")
                .font(.system(size: variant == .compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(.white)
            if !model.sessions.isEmpty {
                Text("\(model.sessions.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(BrandPalette.accent.opacity(0.18)))
            }
            Spacer()
            if let onTogglePin {
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPinned ? BrandPalette.accent : BrandPalette.muted)
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin sessions from notch" : "Pin sessions to notch")
            }
        }
    }

    // MARK: - Folder section

    private func folderSection(_ group: UsageViewModel.UnifiedFolderGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            folderRow(group)
            if !group.sessions.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(BrandPalette.borderSoft)
                        .frame(width: 1)
                        .padding(.leading, variant == .compact ? 12 : 16)

                    tileLayout(for: group.sessions)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .padding(.trailing, 2)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }

    private func folderRow(_ group: UsageViewModel.UnifiedFolderGroup) -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: group.sessions.isEmpty ? "folder" : "folder.fill")
                    .font(.system(size: variant == .compact ? 12 : 14))
                    .foregroundStyle(group.sessions.isEmpty ? BrandPalette.muted : BrandPalette.accent)
                if !group.sessions.isEmpty {
                    statusBadge(for: group)
                        .offset(x: 3, y: 2)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(.system(size: variant == .compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !group.sessions.isEmpty {
                        Text("\(group.sessions.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(sessionCountColor(for: group))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(sessionCountColor(for: group).opacity(0.18)))
                    }
                }
                if variant == .standard {
                    Text(group.folderURL.path)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(BrandPalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, variant == .compact ? 7 : 9)
    }

    @ViewBuilder
    private func statusBadge(for group: UsageViewModel.UnifiedFolderGroup) -> some View {
        if group.sessions.contains(where: { $0.status == .awaitingInput }) {
            PulsingDot(color: SessionStatusPalette.awaiting, size: 6)
        } else if group.sessions.contains(where: { $0.status == .working }) {
            PulsingDot(color: SessionStatusPalette.working, size: 6)
        } else {
            Circle()
                .fill(BrandPalette.muted.opacity(0.45))
                .frame(width: 6, height: 6)
        }
    }

    private func sessionCountColor(for group: UsageViewModel.UnifiedFolderGroup) -> Color {
        if group.sessions.contains(where: { $0.status == .awaitingInput }) { return SessionStatusPalette.awaiting }
        if group.sessions.contains(where: { $0.status == .working }) { return SessionStatusPalette.working }
        return BrandPalette.muted
    }

    // MARK: - Session tiles

    @ViewBuilder
    private func tileLayout(for sessions: [ClaudeSession]) -> some View {
        let columns: [GridItem] = variant == .compact
            ? [GridItem(.flexible(), spacing: 6)]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack.badge.xmark")
                .font(.system(size: 20))
                .foregroundStyle(BrandPalette.muted.opacity(0.5))
            Text("No active sessions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BrandPalette.muted)
            Text("Start a Claude Code session in your IDE to see it here")
                .font(.system(size: 10))
                .foregroundStyle(BrandPalette.muted.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }
}
