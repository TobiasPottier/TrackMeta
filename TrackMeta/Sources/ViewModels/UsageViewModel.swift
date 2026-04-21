import Foundation
import Observation

@Observable
final class UsageViewModel {
    private(set) var state: UsageLoadState = .idle
    private(set) var history: [UsageSample] = []
    private(set) var sessions: [ClaudeSession] = []
    private var dismissedSessionIds: Set<String> = []
    var sessionsPinned: Bool {
        didSet { UserDefaults.standard.set(sessionsPinned, forKey: Self.pinnedKey) }
    }
    var sessionsPinnedCollapsed: Bool {
        didSet { UserDefaults.standard.set(sessionsPinnedCollapsed, forKey: Self.pinnedCollapsedKey) }
    }
    private static let pinnedKey = "TrackMeta.sessionsPinned"
    private static let pinnedCollapsedKey = "TrackMeta.sessionsPinnedCollapsed"
    private let client: ClaudeUsageClient
    private let sessionClient = ClaudeSessionClient()
    private let store: UsageHistoryStore
    private var refreshTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var lastSessionResetsAt: Date?

    init(client: ClaudeUsageClient = ClaudeUsageClient(),
         store: UsageHistoryStore = UsageHistoryStore()) {
        self.client = client
        self.store = store
        self.history = store.load(asOf: Date())
        self.sessionsPinned = UserDefaults.standard.bool(forKey: Self.pinnedKey)
        self.sessionsPinnedCollapsed = UserDefaults.standard.bool(forKey: Self.pinnedCollapsedKey)
        startAutoRefresh()
        startSessionPolling()
    }

    deinit {
        refreshTask?.cancel()
        sessionTask?.cancel()
    }

    var snapshot: UsageSnapshot {
        if case .loaded(let snap) = state { return snap }
        return .empty
    }

    func refresh() {
        Task { await refreshOnce() }
        Task { await refreshSessions() }
    }

    private func startSessionPolling() {
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSessions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshSessions() async {
        let fetched: [ClaudeSession]
        do {
            fetched = try await sessionClient.fetchSummary().sessions
        } catch {
            fetched = []
        }
        let fetchedIds = Set(fetched.map(\.sessionId))
        dismissedSessionIds = dismissedSessionIds.intersection(fetchedIds)
        sessions = fetched.filter { !dismissedSessionIds.contains($0.sessionId) }
    }

    func dismissSession(_ sessionId: String) {
        dismissedSessionIds.insert(sessionId)
        sessions = sessions.filter { $0.sessionId != sessionId }
        Task { [sessionClient] in
            try? await sessionClient.deleteSession(sessionId)
        }
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
            recordSample(from: snap)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func recordSample(from snap: UsageSnapshot) {
        let resetsAt = snap.fiveHour.resetsAt
        let rolledOver: Bool = {
            guard let prev = lastSessionResetsAt, let now = resetsAt else { return false }
            return now > prev
        }()
        let base: [UsageSample] = rolledOver ? [] : history
        let sample = UsageSample(timestamp: snap.fetchedAt, fiveHourPercent: snap.fiveHour.percent)
        let cutoff: Date = {
            if let resetsAt {
                return resetsAt.addingTimeInterval(-SessionWindow.fiveHourSeconds)
            }
            return snap.fetchedAt.addingTimeInterval(-SessionWindow.fiveHourSeconds)
        }()
        history = (base + [sample]).filter { $0.timestamp >= cutoff }
        lastSessionResetsAt = resetsAt
        store.save(history)
    }
}
