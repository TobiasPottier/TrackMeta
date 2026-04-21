import SwiftUI

struct SettingsView: View {
    let model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            card(title: "Status", icon: "dot.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 10) {
                    statusText
                    Button {
                        model.refresh()
                    } label: {
                        Label("Reload now", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(BrandPalette.accent)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }

            card(title: "How it works", icon: "questionmark.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TrackMeta reads the OAuth token saved by the Claude Code CLI (Keychain item “Claude Code-credentials”) and asks Anthropic for your current rate-limit usage.")
                    Text("If credentials are missing: open Terminal, run `claude`, and log in. Then click Reload.")
                }
                .font(.system(size: 11))
                .foregroundStyle(BrandPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 480, height: 360)
        .background(
            LinearGradient(
                colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 12) {
            TrackerLogo(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("TrackMeta")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                Text("Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandPalette.muted)
            }
            Spacer()
        }
    }

    @ViewBuilder private var statusText: some View {
        switch model.state {
        case .idle, .loading:
            Label("Loading…", systemImage: "clock")
                .font(.system(size: 12))
                .foregroundStyle(BrandPalette.muted)
        case .loaded(let snap):
            Label("Last updated \(snap.fetchedAt.formatted(date: .omitted, time: .standard))",
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.34, green: 0.78, blue: 0.47))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func card<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(BrandPalette.muted)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BrandPalette.border, lineWidth: 1)
        )
    }
}
