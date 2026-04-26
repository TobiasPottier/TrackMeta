import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header

            section(label: "Status") {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    statusText
                    Button {
                        model.refresh()
                    } label: {
                        Label("Reload now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }

            section(label: "How it works") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TrackMeta reads the OAuth token saved by the Claude Code CLI (Keychain item “Claude Code-credentials”) and asks Anthropic for your current rate-limit usage.")
                    Text("If credentials are missing: open Terminal, run `claude`, and log in. Then click Reload.")
                }
                .dsType(.bodySm)
                .foregroundStyle(DS.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Space.lg)
        .frame(width: 480, height: 360)
        .background(DS.Surface.base.ignoresSafeArea())
        .background(FloatingWindowConfigurator())
        .foregroundStyle(DS.Text.primary)
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            TrackerLogo(size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .dsType(.labelSm)
                    .foregroundStyle(DS.Text.muted)
                Text("TrackMeta")
                    .dsType(.headlineMd)
                    .foregroundStyle(DS.Text.primary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var statusText: some View {
        switch model.state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .dsType(.bodyMd)
                    .foregroundStyle(DS.Text.muted)
            }
        case .loaded(let snap):
            HStack(spacing: 8) {
                Circle()
                    .fill(snap.isUsageCapReached ? DS.Status.danger : DS.Status.success)
                    .frame(width: 6, height: 6)
                Text(statusMessage(for: snap))
                    .dsType(.bodyMd)
                    .foregroundStyle(DS.Text.primary)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DS.Status.danger)
                Text(message)
                    .dsType(.bodyMd)
                    .foregroundStyle(DS.Text.primary)
            }
        }
    }

    private func statusMessage(for snap: UsageSnapshot) -> String {
        let updated = snap.fetchedAt.formatted(date: .omitted, time: .standard)
        if snap.isUsageCapReached {
            return "Usage cap reached · updated \(updated)"
        }
        return "Last updated \(updated)"
    }

    @ViewBuilder
    private func section<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(label)
                .dsType(.labelSm)
                .foregroundStyle(DS.Text.muted)
            content()
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Outline.soft.opacity(0.5), lineWidth: 1)
        )
    }
}

/// Pins the hosting window above all other app windows so Settings stays on top.
private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.hidesOnDeactivate = false
            window.orderFrontRegardless()
        }
    }
}
