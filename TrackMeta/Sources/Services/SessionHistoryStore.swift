import Foundation

/// An event observed on a session — a tool change, summary change, or status
/// transition. Stored as part of the per-session history so the UI can show
/// a short activity log without the server needing to keep one.
struct SessionEvent: Equatable, Identifiable {
    enum Kind: Equatable {
        case toolChanged(String, String?)
        case summaryChanged(String)
        case statusChanged(ClaudeSession.Status)
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
}

/// Per-session local metadata accumulated across polls. Immutable — every
/// ingest produces a new value.
struct SessionHistory: Equatable {
    /// Wall-clock time TrackMeta first observed this session_id. Used as an
    /// approximation for "spawned at" since the server does not emit one.
    let firstSeenAt: Date
    /// Most recent events, newest last. Bounded by `maxEvents`.
    let events: [SessionEvent]
    /// Per-minute counts of events for the last `bucketCount` minutes. Index 0
    /// is the oldest bucket; index `bucketCount - 1` is "now".
    let activityBuckets: [Int]
    /// Bucket start (minute-aligned) of the last bucket. Used to roll the
    /// window when time advances.
    let bucketAnchor: Date
    /// Snapshot of last-observed fields, for change detection.
    let lastTool: String?
    let lastToolTarget: String?
    let lastSummary: String?
    let lastStatus: ClaudeSession.Status

    static let maxEvents = 8
    static let bucketCount = 30
    static let bucketSeconds: TimeInterval = 60

    /// How long since we first saw this session.
    func elapsed(now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(firstSeenAt))
    }
}

/// Pure functions that produce new `SessionHistory` values from observations.
/// Kept outside the view model so behavior is testable.
enum SessionHistoryIngestion {
    /// Creates the initial history for a newly observed session.
    static func initial(from session: ClaudeSession, at now: Date) -> SessionHistory {
        SessionHistory(
            firstSeenAt: now,
            events: [
                SessionEvent(id: UUID(), timestamp: now, kind: .statusChanged(session.status))
            ],
            activityBuckets: Array(repeating: 0, count: SessionHistory.bucketCount),
            bucketAnchor: minuteAnchor(of: now),
            lastTool: session.lastTool,
            lastToolTarget: session.lastToolTarget,
            lastSummary: session.summary,
            lastStatus: session.status
        )
    }

    /// Returns a new history reflecting any fields that changed between the
    /// prior observation and `session`. Activity buckets are rolled forward
    /// if wall-clock time has advanced into a new minute.
    static func update(_ history: SessionHistory,
                       with session: ClaudeSession,
                       at now: Date) -> SessionHistory {
        var newEvents: [SessionEvent] = []
        if (session.lastTool != history.lastTool || session.lastToolTarget != history.lastToolTarget),
           let tool = session.lastTool,
           !tool.isEmpty {
            newEvents.append(
                SessionEvent(
                    id: UUID(),
                    timestamp: now,
                    kind: .toolChanged(tool, session.lastToolTarget)
                )
            )
        }
        if session.summary != history.lastSummary, let summary = session.summary, !summary.isEmpty {
            newEvents.append(SessionEvent(id: UUID(), timestamp: now, kind: .summaryChanged(summary)))
        }
        if session.status != history.lastStatus {
            newEvents.append(SessionEvent(id: UUID(), timestamp: now, kind: .statusChanged(session.status)))
        }

        let mergedEvents = Array((history.events + newEvents).suffix(SessionHistory.maxEvents))

        let rolled = rolledBuckets(
            buckets: history.activityBuckets,
            anchor: history.bucketAnchor,
            at: now,
            incrementBy: newEvents.count
        )

        return SessionHistory(
            firstSeenAt: history.firstSeenAt,
            events: mergedEvents,
            activityBuckets: rolled.buckets,
            bucketAnchor: rolled.anchor,
            lastTool: session.lastTool,
            lastToolTarget: session.lastToolTarget,
            lastSummary: session.summary,
            lastStatus: session.status
        )
    }

    private static func rolledBuckets(buckets: [Int],
                                      anchor: Date,
                                      at now: Date,
                                      incrementBy delta: Int) -> (buckets: [Int], anchor: Date) {
        let currentAnchor = minuteAnchor(of: now)
        let minutesAdvanced = max(0, Int(currentAnchor.timeIntervalSince(anchor) / SessionHistory.bucketSeconds))
        var rolled = buckets
        if minutesAdvanced > 0 {
            if minutesAdvanced >= SessionHistory.bucketCount {
                rolled = Array(repeating: 0, count: SessionHistory.bucketCount)
            } else {
                rolled = Array(rolled.dropFirst(minutesAdvanced)) + Array(repeating: 0, count: minutesAdvanced)
            }
        }
        if delta > 0, let last = rolled.indices.last {
            rolled[last] += delta
        }
        return (rolled, currentAnchor)
    }

    private static func minuteAnchor(of date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / SessionHistory.bucketSeconds)
             * SessionHistory.bucketSeconds)
    }
}
