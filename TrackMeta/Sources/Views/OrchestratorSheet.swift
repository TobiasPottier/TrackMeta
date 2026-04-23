import SwiftUI
import AppKit

/// Modal sheet for orchestrating new Claude Code sessions.
/// Pre-fills the folder from the session group's CWD; the user can change it
/// with the Finder picker and type a natural-language prompt.
struct OrchestratorSheet: View {
    let onSubmit: (URL, String) -> Void
    let onCancel: () -> Void

    @State private var folder: URL
    @State private var promptText = ""
    @FocusState private var promptFocused: Bool

    init(initialFolder: URL, onSubmit: @escaping (URL, String) -> Void, onCancel: @escaping () -> Void) {
        _folder = State(initialValue: initialFolder)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)

            Divider().overlay(BrandPalette.borderSoft)

            VStack(alignment: .leading, spacing: 16) {
                folderRow
                promptRow
            }
            .padding(20)

            Divider().overlay(BrandPalette.borderSoft)

            footerButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 520)
        .background(BrandPalette.cardFill)
        .onAppear { promptFocused = true }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrandPalette.accent.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Orchestrate agents")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Describe what you want — Claude will open the right terminals.")
                    .font(.system(size: 11))
                    .foregroundStyle(BrandPalette.muted)
            }
        }
    }

    private var folderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Working directory", systemImage: "folder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrandPalette.mutedStrong)
            HStack(spacing: 8) {
                Text(folder.path)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Change") { pickFolder() }
                    .buttonStyle(OrchestratorGhostStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BrandPalette.border, lineWidth: 1)
            )
        }
    }

    private var promptRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Prompt", systemImage: "text.cursor")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrandPalette.mutedStrong)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $promptText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .focused($promptFocused)
                    .frame(minHeight: 80, maxHeight: 140)
                    .padding(8)
                if promptText.isEmpty {
                    Text("e.g. \"Open Opus for the dashboard and Sonnet for settings\"")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandPalette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BrandPalette.border, lineWidth: 1)
            )
        }
    }

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(OrchestratorGhostStyle())
            Button("Orchestrate") {
                let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSubmit(folder, trimmed)
            }
            .buttonStyle(OrchestratorAccentStyle())
            .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose working directory"
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
        }
    }
}

// MARK: - Button styles (sheet-local to avoid name collisions)

struct OrchestratorGhostStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
            )
            .foregroundStyle(BrandPalette.mutedStrong)
    }
}

struct OrchestratorAccentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BrandPalette.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .foregroundStyle(.white)
    }
}
