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
}
