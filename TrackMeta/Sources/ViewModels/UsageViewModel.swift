import Foundation
import Observation

@Observable
final class UsageViewModel {
    private(set) var state: UsageLoadState = .idle
    private let client: ClaudeUsageClient
    private var refreshTask: Task<Void, Never>?

    init(client: ClaudeUsageClient = ClaudeUsageClient()) {
        self.client = client
        startAutoRefresh()
    }

    deinit { refreshTask?.cancel() }

    var snapshot: UsageSnapshot {
        if case .loaded(let snap) = state { return snap }
        return .empty
    }

    func refresh() {
        Task { await refreshOnce() }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refreshOnce() async {
        guard let token = ClaudeCredentialsStore.readAccessToken() else {
            state = .failed(ClaudeUsageError.missingCredentials.localizedDescription)
            return
        }
        state = .loading
        do {
            let snap = try await client.fetchSnapshot(accessToken: token)
            state = .loaded(snap)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
