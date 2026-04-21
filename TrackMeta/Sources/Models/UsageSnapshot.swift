import Foundation

struct UsageBucket: Equatable {
    let used: Int
    let limit: Int
    let resetsAt: Date?

    var percent: Double {
        guard limit > 0 else { return 0 }
        return min(100, Double(used) / Double(limit) * 100)
    }
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
