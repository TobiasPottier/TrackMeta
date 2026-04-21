import Foundation

struct UsageBucket: Equatable {
    let used: Int
    let limit: Int
    let resetsAt: Date?

    var percent: Double {
        guard limit > 0 else { return 0 }
        return min(100, Double(used) / Double(limit) * 100)
    }

    /// Fraction (0…1) of the session window elapsed at `now`.
    /// Returns nil if there's no reset timestamp to anchor the window.
    func sessionProgress(at now: Date, windowLength: TimeInterval) -> Double? {
        guard let resetsAt, windowLength > 0 else { return nil }
        let start = resetsAt.addingTimeInterval(-windowLength)
        let elapsed = now.timeIntervalSince(start)
        return min(1, max(0, elapsed / windowLength))
    }
}

enum SessionWindow {
    static let fiveHourSeconds: TimeInterval = 5 * 60 * 60
    static let sevenDaySeconds: TimeInterval = 7 * 24 * 60 * 60
}

struct UsageSample: Equatable, Codable {
    let timestamp: Date
    let fiveHourPercent: Double
}

struct UsageSnapshot: Equatable {
    let fiveHour: UsageBucket
    let sevenDay: UsageBucket
    let fetchedAt: Date

    static let empty = UsageSnapshot(
        fiveHour: UsageBucket(used: 0, limit: 0, resetsAt: nil),
        sevenDay: UsageBucket(used: 0, limit: 0, resetsAt: nil),
        fetchedAt: .distantPast
    )
}

enum UsageLoadState: Equatable {
    case idle
    case loading
    case loaded(UsageSnapshot)
    case failed(String)
}
