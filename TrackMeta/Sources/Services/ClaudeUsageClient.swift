import Foundation

enum ClaudeUsageError: LocalizedError {
    case missingCredentials
    case unauthorized
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "No Claude Code credentials found. Run `claude` in Terminal and log in, then reopen this app."
        case .unauthorized:
            return "Credentials rejected (401). Run `claude /login` to refresh, then Reload here."
        case .http(let code):
            return "api.anthropic.com returned HTTP \(code)."
        case .badResponse:
            return "Unexpected response shape from api.anthropic.com."
        }
    }
}

// Fetches Claude Max usage by sending a cheap 1-token message to the Anthropic
// Messages API with the CLI's OAuth token. The response *headers* contain the
// 5-hour and 7-day rate-limit utilization — that's what we display.
struct ClaudeUsageClient {
    private let url = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20",      forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01",            forHTTPHeaderField: "anthropic-version")
        request.setValue("claude-code/2.1.5",     forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages":   [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeUsageError.badResponse }
        switch http.statusCode {
        case 200..<300: return snapshot(from: http)
        case 429:       return snapshot(from: http, usageCapReached: true)
        case 401, 403: throw ClaudeUsageError.unauthorized
        default:       throw ClaudeUsageError.http(http.statusCode)
        }
    }

    private func snapshot(from http: HTTPURLResponse, usageCapReached: Bool = false) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour:  bucket(utilHeader: "anthropic-ratelimit-unified-5h-utilization",
                              resetHeader: "anthropic-ratelimit-unified-5h-reset",
                              in: http,
                              usageCapReached: usageCapReached),
            sevenDay:  bucket(utilHeader: "anthropic-ratelimit-unified-7d-utilization",
                              resetHeader: "anthropic-ratelimit-unified-7d-reset",
                              in: http,
                              usageCapReached: usageCapReached),
            fetchedAt: Date(),
            isUsageCapReached: usageCapReached
        )
    }

    private func bucket(
        utilHeader: String,
        resetHeader: String,
        in http: HTTPURLResponse,
        usageCapReached: Bool
    ) -> UsageBucket {
        let rawUtil = (http.value(forHTTPHeaderField: utilHeader).flatMap(Double.init)) ?? 0
        let util = usageCapReached ? max(1, rawUtil) : rawUtil
        let pct = max(0, min(100, Int((util * 100).rounded())))
        let resetTs = http.value(forHTTPHeaderField: resetHeader).flatMap(Double.init) ?? 0
        let resetsAt = resetTs > 0 ? Date(timeIntervalSince1970: resetTs) : nil
        return UsageBucket(used: pct, limit: 100, resetsAt: resetsAt)
    }
}
