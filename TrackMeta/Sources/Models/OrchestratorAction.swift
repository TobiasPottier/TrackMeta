import Foundation

struct OrchestratorAction: Decodable {
    let model: String
    let prompt: String
    let split: String?

    var iTermSplit: ITermSplit? {
        switch split {
        case "right": return .right
        case "left":  return .left
        case "up":    return .up
        case "down":  return .down
        default:      return nil
        }
    }

    var shellCommand: String {
        let modelFlag: String
        switch model.lowercased() {
        case "opus", "opus-4-7", "claude-opus-4-7":
            modelFlag = "claude-opus-4-7"
        case "haiku", "haiku-4-5", "claude-haiku-4-5":
            modelFlag = "claude-haiku-4-5-20251001"
        default:
            modelFlag = "claude-sonnet-4-6"
        }
        let escaped = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
        return "claude --dangerously-skip-permissions --model \(modelFlag) '\(escaped)'"
    }
}

struct OrchestratorResponse: Decodable {
    let actions: [OrchestratorAction]
}
