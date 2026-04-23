import Foundation

enum OrchestratorError: LocalizedError {
    case missingCredentials
    case unauthorized
    case apiError(Int, String)
    case noActions
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "No Claude Code credentials found. Run `claude` and log in."
        case .unauthorized:
            return "Credentials rejected (401). Run `claude /login` to refresh."
        case .apiError(_, let message):
            return message
        case .noActions:
            return "Claude returned no actions for that prompt."
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        }
    }
}

struct OrchestratorClient {
    private static let url = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func orchestrate(userPrompt: String, folder: URL) async throws -> [OrchestratorAction] {
        guard let token = ClaudeCredentialsStore.readAccessToken() else {
            throw OrchestratorError.missingCredentials
        }

        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)",       forHTTPHeaderField: "Authorization")
        request.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20",      forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01",            forHTTPHeaderField: "anthropic-version")
        request.setValue("claude-code/2.1.5",     forHTTPHeaderField: "User-Agent")

        let systemPrompt = """
        You are an orchestrator for Claude Code terminal sessions. \
        The user describes what they want. \
        Respond ONLY with a JSON object — no markdown, no prose, nothing else.

        Schema:
        {
          "actions": [
            {
              "model": "opus | sonnet | haiku",
              "prompt": "<the exact prompt to pass as a command-line argument to `claude`>",
              "split": "right | left | up | down | null"
            }
          ]
        }

        Rules:
        - model: use "opus" for complex reasoning/architecture, "sonnet" for standard dev work, "haiku" for lightweight tasks.
        - prompt: be specific and include the relevant file paths relative to the working directory.
        - split: null opens a new tab; right/left/up/down opens a split pane in the existing window.
        - The working directory is: \(folder.path)
        - Derive relative paths from the user's description; don't invent paths that don't make sense.
        """

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system":     systemPrompt,
            "messages":   [["role": "user", "content": userPrompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrchestratorError.badResponse("not an HTTP response")
        }

        switch http.statusCode {
        case 401, 403: throw OrchestratorError.unauthorized
        case 200..<300: break
        default: throw apiError(statusCode: http.statusCode, body: data)
        }

        return try parseActions(from: data)
    }

    private func apiError(statusCode: Int, body: Data) -> OrchestratorError {
        let message: String
        if let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let msg = error["message"] as? String {
            message = msg
        } else {
            message = "api.anthropic.com returned HTTP \(statusCode)."
        }
        return .apiError(statusCode, message)
    }

    private func parseActions(from data: Data) throws -> [OrchestratorAction] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let contentArray = root["content"] as? [[String: Any]],
              let text = contentArray.first?["text"] as? String
        else {
            throw OrchestratorError.badResponse("missing content[0].text")
        }

        // Strip any accidental markdown fences
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw OrchestratorError.badResponse("could not encode response text as UTF-8")
        }

        do {
            let decoded = try JSONDecoder().decode(OrchestratorResponse.self, from: jsonData)
            if decoded.actions.isEmpty { throw OrchestratorError.noActions }
            return decoded.actions
        } catch let error as OrchestratorError {
            throw error
        } catch {
            throw OrchestratorError.badResponse("JSON decode failed: \(error.localizedDescription)\n\nRaw: \(cleaned.prefix(300))")
        }
    }
}
