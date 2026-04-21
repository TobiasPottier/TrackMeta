import Foundation

struct ClaudeSessionClient {
    private let url = URL(string: "http://localhost:7777")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        self.session = URLSession(configuration: config)
    }

    func fetchSummary() async throws -> SessionSummary {
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(SessionSummary.self, from: data)
    }

    func deleteSession(_ sessionId: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["event": "end", "session_id": sessionId]
        )
        _ = try await session.data(for: request)
    }
}
