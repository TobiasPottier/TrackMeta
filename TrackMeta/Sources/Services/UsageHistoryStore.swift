import Foundation

// Persists the in-session usage chart history across app launches.
// Backed by UserDefaults — the payload is small (one sample per minute, capped
// to a 5h session window ≈ 300 samples).
struct UsageHistoryStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "usageHistory.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load(asOf now: Date) -> [UsageSample] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let decoded = try? JSONDecoder().decode([UsageSample].self, from: data) else { return [] }
        let cutoff = now.addingTimeInterval(-SessionWindow.fiveHourSeconds)
        return decoded.filter { $0.timestamp >= cutoff }
    }

    func save(_ history: [UsageSample]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }
}
