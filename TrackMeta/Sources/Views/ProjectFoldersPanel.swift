import SwiftUI
import AppKit

/// Read-only overview of live Claude Code sessions, grouped by working
/// directory. The whole panel is rendered in the editorial-monochrome style:
/// section header with uppercase tracked label, hairline outline groups, and
/// the amber accent reserved for the count badge / pin toggle in active
/// states.
struct ProjectFoldersPanel: View {
    @Bindable var model: UsageViewModel
    var variant: SessionTile.Variant = .standard
    var isPinned: Bool = false
    var onTogglePin: (() -> Void)? = nil

    private var isCompact: Bool { variant == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? DS.Space.xs : DS.Space.md) {
            panelHeader
            let groups = model.unifiedFolderGroups
            if groups.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: isCompact ? DS.Space.xs : DS.Space.sm) {
                    ForEach(groups) { group in
                        folderSection(group)
                    }
                }
            }
        }
    }

    // MARK: - Panel header

    private var panelHeader: some View {
        HStack(spacing: DS.Space.xs) {
            Text("Sessions")
                .dsType(.labelSm)
                .foregroundStyle(DS.Text.muted)
            if !model.sessions.isEmpty {
                DSChip(text: "\(model.sessions.count)", tone: .accent)
            }
            Spacer()
            if let onTogglePin {
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                }
                .buttonStyle(DSIconButtonStyle(size: 28, highlighted: isPinned))
                .help(isPinned ? "Unpin sessions from notch" : "Pin sessions to notch")
            }
        }
    }

    // MARK: - Folder section

    private func folderSection(_ group: UsageViewModel.UnifiedFolderGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            folderRow(group)
            if !group.sessions.isEmpty {
                HStack(alignment: .top, spacing: DS.Space.xs) {
                    Rectangle()
                        .fill(DS.Outline.soft.opacity(0.45))
                        .frame(width: 1)
                        .padding(.leading, isCompact ? 14 : 18)

                    tileLayout(for: group.sessions)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .padding(.trailing, 2)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Outline.soft.opacity(0.45), lineWidth: 1)
        )
    }

    private func folderRow(_ group: UsageViewModel.UnifiedFolderGroup) -> some View {
        HStack(spacing: DS.Space.sm) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: group.sessions.isEmpty ? "folder" : "folder.fill")
                    .font(.system(size: isCompact ? 12 : 14))
                    .foregroundStyle(group.sessions.isEmpty ? DS.Text.muted : DS.Primary.accent)
                if !group.sessions.isEmpty {
                    statusBadge(for: group)
                        .offset(x: 3, y: 2)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Text.primary)
                        .lineLimit(1)
                    if !group.sessions.isEmpty {
                        DSChip(text: "\(group.sessions.count)",
                               tone: countTone(for: group))
                    }
                }
                if !isCompact {
                    Text(group.folderURL.path)
                        .dsType(.mono)
                        .foregroundStyle(DS.Text.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, isCompact ? 8 : 10)
    }

    @ViewBuilder
    private func statusBadge(for group: UsageViewModel.UnifiedFolderGroup) -> some View {
        if group.sessions.contains(where: { $0.status == .awaitingInput }) {
            PulsingDot(color: SessionStatusPalette.awaiting, size: 6)
        } else if group.sessions.contains(where: { $0.status == .working }) {
            PulsingDot(color: SessionStatusPalette.working, size: 6)
        } else {
            Circle()
                .fill(DS.Text.muted.opacity(0.45))
                .frame(width: 6, height: 6)
        }
    }

    private func countTone(for group: UsageViewModel.UnifiedFolderGroup) -> DSChip.Tone {
        if group.sessions.contains(where: { $0.status == .awaitingInput }) { return .accent }
        if group.sessions.contains(where: { $0.status == .working }) { return .success }
        return .neutral
    }

    // MARK: - Session tiles

    @ViewBuilder
    private func tileLayout(for sessions: [ClaudeSession]) -> some View {
        let columns: [GridItem] = isCompact
            ? [GridItem(.flexible(), spacing: 6)]
            : [GridItem(.flexible(), spacing: DS.Space.sm),
               GridItem(.flexible(), spacing: DS.Space.sm)]

        LazyVGrid(columns: columns, alignment: .leading, spacing: isCompact ? 6 : DS.Space.sm) {
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
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Text.muted.opacity(0.55))
            Text("No active sessions")
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(DS.Text.secondary)
            Text("Start a Claude Code session in your IDE to see it here")
                .dsType(.bodySm)
                .foregroundStyle(DS.Text.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Outline.soft.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}
