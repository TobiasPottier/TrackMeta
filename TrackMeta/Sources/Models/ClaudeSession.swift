import Foundation

struct ClaudeSession: Identifiable, Decodable, Equatable {
    let sessionId: String
    let status: Status
    let lastTool: String?
    let lastToolTarget: String?
    let cwd: String?
    let summary: String?
    let idleForSeconds: Int
    /// 0–100 context window utilisation reported by the sessions server, if available.
    let contextPercentage: Double?

    var id: String { sessionId }

    var cwdDisplayName: String? {
        guard let cwd else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    enum Status: String, Decodable {
        case working
        case idle
        case awaitingInput = "awaiting_input"

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            if raw == "generating" {
                self = .working
            } else {
                self = Status(rawValue: raw) ?? .idle
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case sessionId         = "session_id"
        case status
        case lastTool          = "last_tool"
        case lastToolTarget    = "last_tool_target"
        case cwd
        case summary
        case idleForSeconds    = "idle_for_seconds"
        case contextPercentage = "context_percentage"
    }
}

struct SessionSummary: Decodable, Equatable {
    let total: Int
    let working: Int
    let idle: Int
    let sessions: [ClaudeSession]

    enum CodingKeys: String, CodingKey {
        case total
        case working
        case generating
        case idle
        case sessions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try c.decode(Int.self, forKey: .total)
        self.idle = try c.decode(Int.self, forKey: .idle)
        self.sessions = try c.decode([ClaudeSession].self, forKey: .sessions)
        if let working = try c.decodeIfPresent(Int.self, forKey: .working) {
            self.working = working
        } else {
            self.working = try c.decodeIfPresent(Int.self, forKey: .generating) ?? 0
        }
    }
}
