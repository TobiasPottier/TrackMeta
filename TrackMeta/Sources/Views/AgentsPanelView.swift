import SwiftUI

/// Floating overlay that shows all agents content on top of other windows.
/// Opened via the "Float" button in the Agents section of DashboardView;
/// managed as a floating NSPanel in AppDelegate.
struct AgentsPanelView: View {
    @Bindable var model: UsageViewModel

    @State private var orchestratorFolder: URL?
    @State private var isOrchestrating = false
    @State private var orchestratorError: String?

    private let orchestratorClient = OrchestratorClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                compactChartCard
                projectsFoldersCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [BrandPalette.panelTop, BrandPalette.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .foregroundStyle(.white)
        .alert("Orchestration failed",
               isPresented: Binding(
                get: { orchestratorError != nil },
                set: { if !$0 { orchestratorError = nil } }
               ),
               presenting: orchestratorError) { _ in
            Button("OK", role: .cancel) { orchestratorError = nil }
        } message: { Text($0) }
        .sheet(isPresented: Binding(
            get: { orchestratorFolder != nil },
            set: { if !$0 { orchestratorFolder = nil } }
        )) {
            if let folder = orchestratorFolder {
                orchestratorSheetContent(folder: folder)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder private var compactChartCard: some View {
        if case .loaded(let snap) = model.state {
            ZStack(alignment: .topLeading) {
                SessionUsageChart(history: model.history, bucket: snap.fiveHour)
                    .frame(maxWidth: .infinity)
                RefreshIconButton(action: model.refresh)
                    .padding(10)
            }
        }
    }

    @ViewBuilder private var projectsFoldersCard: some View {
        DashCard {
            ProjectFoldersPanel(
                model: model,
                variant: .standard,
                isPinned: model.sessionsPinned,
                onOrchestrate: { folder in orchestratorFolder = folder },
                onLaunchAgent: { folder, split in launchAgent(folder: folder, split: split) }
            )
        }
    }

    // MARK: - Orchestrator sheet

    @ViewBuilder private func orchestratorSheetContent(folder: URL) -> some View {
        if isOrchestrating {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Asking Claude to plan your sessions…")
                    .font(.system(size: 13))
                    .foregroundStyle(BrandPalette.muted)
            }
            .frame(width: 520, height: 160)
            .background(BrandPalette.cardFill)
        } else {
            OrchestratorSheet(
                initialFolder: folder,
                onSubmit: { resolvedFolder, prompt in
                    orchestratorFolder = nil
                    Task { await runOrchestration(folder: resolvedFolder, prompt: prompt) }
                },
                onCancel: { orchestratorFolder = nil }
            )
        }
    }

    private func launchAgent(folder: URL, split: ITermSplit?) {
        do {
            try ITermLauncher.launch(folder: folder, command: "csp", split: split)
        } catch {
            orchestratorError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func runOrchestration(folder: URL, prompt: String) async {
        isOrchestrating = true
        defer { isOrchestrating = false }
        do {
            let actions = try await orchestratorClient.orchestrate(userPrompt: prompt, folder: folder)
            for action in actions {
                try ITermLauncher.launch(folder: folder, command: action.shellCommand, split: action.iTermSplit)
            }
        } catch {
            orchestratorError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct RefreshIconButton: View {
    let action: () -> Void

    @State private var rotation: Double = 0
    @State private var isSpinning = false

    var body: some View {
        Button {
            guard !isSpinning else { return }
            isSpinning = true
            withAnimation(.linear(duration: 0.5)) {
                rotation += 360
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSpinning = false
            }
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrandPalette.mutedStrong)
                .rotationEffect(.degrees(rotation))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.3)))
                .overlay(Circle().stroke(BrandPalette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Refresh usage")
    }
}
