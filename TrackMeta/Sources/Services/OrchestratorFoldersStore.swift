import Foundation

/// UserDefaults-backed store for orchestrator project destinations.
/// Paths are stored as absolute filesystem strings; this intentionally does
/// not use security-scoped bookmarks because iTerm launches run out-of-process.
struct OrchestratorFoldersStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "TrackMeta.orchestratorFolders") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [URL] {
        guard let paths = defaults.array(forKey: key) as? [String] else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    func save(_ folders: [URL]) {
        let paths = folders.map { $0.path }
        defaults.set(paths, forKey: key)
    }
}
