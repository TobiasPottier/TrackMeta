import Foundation
import Observation

@Observable
final class UsageViewModel {
    private(set) var state: UsageLoadState = .idle
    private(set) var history: [UsageSample] = []
    private(set) var sessions: [ClaudeSession] = []
    private(set) var sessionHistories: [String: SessionHistory] = [:]
    private(set) var expandedSessionIds: Set<String> = []
    private var autoExpandExpiry: [String: Date] = [:]
    private var dismissedSessionIds: Set<String> = []
    private static let autoExpandDuration: TimeInterval = 8
    var sessionsPinned: Bool {
        didSet { UserDefaults.standard.set(sessionsPinned, forKey: Self.pinnedKey) }
    }
    var sessionsPinnedCollapsed: Bool {
        didSet { UserDefaults.standard.set(sessionsPinnedCollapsed, forKey: Self.pinnedCollapsedKey) }
    }
    private static let pinnedKey = "TrackMeta.sessionsPinned"
    private static let pinnedCollapsedKey = "TrackMeta.sessionsPinnedCollapsed"

    struct UnifiedFolderGroup: Identifiable {
        let id: String          // absolute folder path
        let folderURL: URL
        let sessions: [ClaudeSession]
        var displayName: String { folderURL.lastPathComponent }
    }
    private let client: ClaudeUsageClient
    private let sessionClient = ClaudeSessionClient()
    private let store: UsageHistoryStore
    private var refreshTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var lastWeeklyResetsAt: Date?
    private var lastLoadedSnapshot: UsageSnapshot?

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

    /// Groups live sessions by their working directory. A session without a cwd
    /// is dropped from the grouped view.
    var unifiedFolderGroups: [UnifiedFolderGroup] {
        let sorted = sessions.sorted {
            let lr = sessionStatusRank($0.status), rr = sessionStatusRank($1.status)
            return lr != rr ? lr < rr : $0.sessionId < $1.sessionId
        }
        var order: [String] = []
        var buckets: [String: [ClaudeSession]] = [:]
        for session in sorted {
            guard let cwd = session.cwd else { continue }
            let key = URL(fileURLWithPath: cwd).standardizedFileURL.path
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(session)
        }
        return order.map { path in
            UnifiedFolderGroup(
                id: path,
                folderURL: URL(fileURLWithPath: path),
                sessions: buckets[path] ?? []
            )
        }
    }

    private func sessionStatusRank(_ status: ClaudeSession.Status) -> Int {
        switch status {
        case .awaitingInput: return 0
        case .working:       return 1
        case .idle:          return 2
        }
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
        let visible = fetched.filter { !dismissedSessionIds.contains($0.sessionId) }
        ingest(sessions: visible, at: Date())
        sessions = visible
    }

    /// Folds new session observations into the per-session history store and
    /// flips auto-expand on for sessions that just became `awaitingInput`.
    private func ingest(sessions next: [ClaudeSession], at now: Date) {
        var updated: [String: SessionHistory] = [:]
        for session in next {
            if let prior = sessionHistories[session.sessionId] {
                let newHistory = SessionHistoryIngestion.update(prior, with: session, at: now)
                updated[session.sessionId] = newHistory
                if prior.lastStatus != .awaitingInput, session.status == .awaitingInput {
                    autoExpandExpiry[session.sessionId] = now.addingTimeInterval(Self.autoExpandDuration)
                }
            } else {
                updated[session.sessionId] = SessionHistoryIngestion.initial(from: session, at: now)
                if session.status == .awaitingInput {
                    autoExpandExpiry[session.sessionId] = now.addingTimeInterval(Self.autoExpandDuration)
                }
            }
        }
        sessionHistories = updated
        pruneAutoExpand(at: now, validIds: Set(next.map(\.sessionId)))
    }

    private func pruneAutoExpand(at now: Date, validIds: Set<String>) {
        autoExpandExpiry = autoExpandExpiry.filter { id, expiry in
            validIds.contains(id) && expiry > now
        }
    }

    /// True when a session should render in its expanded form — either the
    /// user clicked to expand, or an auto-expand window is still active.
    func isExpanded(_ sessionId: String, at now: Date = Date()) -> Bool {
        if expandedSessionIds.contains(sessionId) { return true }
        if let expiry = autoExpandExpiry[sessionId], expiry > now { return true }
        return false
    }

    func toggleExpanded(_ sessionId: String) {
        if expandedSessionIds.contains(sessionId) {
            expandedSessionIds.remove(sessionId)
        } else {
            expandedSessionIds.insert(sessionId)
        }
        autoExpandExpiry.removeValue(forKey: sessionId)
    }

    func dismissSession(_ sessionId: String) {
        dismissedSessionIds.insert(sessionId)
        sessions = sessions.filter { $0.sessionId != sessionId }
        sessionHistories.removeValue(forKey: sessionId)
        expandedSessionIds.remove(sessionId)
        autoExpandExpiry.removeValue(forKey: sessionId)
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
        if case .loaded = state { } else { state = .loading }
        do {
            let snap = try await client.fetchSnapshot(accessToken: token, preservingUsageFrom: lastLoadedSnapshot)
            state = .loaded(snap)
            lastLoadedSnapshot = snap
            recordSample(from: snap)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func recordSample(from snap: UsageSnapshot) {
        let resetsAt = snap.sevenDay.resetsAt
        let rolledOver: Bool = {
            guard let prev = lastWeeklyResetsAt, let now = resetsAt else { return false }
            return now > prev
        }()
        let base: [UsageSample] = rolledOver ? [] : history
        let sample = UsageSample(
            timestamp: snap.fetchedAt,
            fiveHourPercent: snap.fiveHour.percent,
            sevenDayPercent: snap.sevenDay.percent
        )
        let cutoff: Date = {
            if let resetsAt {
                return resetsAt.addingTimeInterval(-SessionWindow.sevenDaySeconds)
            }
            return snap.fetchedAt.addingTimeInterval(-SessionWindow.sevenDaySeconds)
        }()
        history = (base + [sample]).filter { $0.timestamp >= cutoff }
        lastWeeklyResetsAt = resetsAt
        store.save(history)
    }
}
