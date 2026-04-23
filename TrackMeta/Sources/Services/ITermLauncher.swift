import Foundation
import AppKit

enum ITermLauncherError: LocalizedError {
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): return message
        }
    }
}

/// Direction in which to place the new split pane relative to the existing
/// session for a folder. `right`/`down` map to iTerm's native `split
/// vertically`/`split horizontally`. `left`/`up` split then invoke iTerm's
/// default ⌘⌥⇧‹arrow› shortcut ("Move Active Session") to reposition the
/// new pane.
enum ITermSplit {
    case right, left, up, down
}

/// Launches Claude Code agent sessions in iTerm. Keeps a per-folder cache of
/// iTerm window IDs so that a second agent for the same folder opens as a new
/// tab — or split pane — in the existing window rather than spawning a fresh
/// one.
enum ITermLauncher {
    private static let cacheQueue = DispatchQueue(label: "ITermLauncher.cache")
    private static var windowIdsByFolder: [String: Int] = [:]

    /// Opens a shell session running `command` in `folder`.
    /// - If `split` is non-nil and a cached iTerm window still exists, the
    ///   new agent opens as a split pane in that window.
    /// - If `split` is nil and a cached window exists, the new agent opens
    ///   as a new tab in that window.
    /// - Otherwise a fresh full-screen iTerm window is spawned.
    static func launch(folder: URL, command: String, split: ITermSplit? = nil) throws {
        let path = folder.path
        let shellCommand = "cd \(shellQuoted(path)) && \(command)"

        if let cached = cachedWindowId(for: path) {
            let didReuse: Bool
            if let split {
                didReuse = try openSplit(inWindowId: cached, shellCommand: shellCommand, direction: split)
            } else {
                didReuse = try openTab(inWindowId: cached, shellCommand: shellCommand)
            }
            if didReuse { return }
            setCachedWindowId(nil, for: path)
        }

        let newId = try openNewWindow(shellCommand: shellCommand)
        setCachedWindowId(newId, for: path)
    }

    // MARK: - AppleScript paths

    /// Creates a new tab in the given window and runs the command. Returns
    /// `false` when the window no longer exists so the caller can fall back
    /// to creating a fresh window.
    private static func openTab(inWindowId windowId: Int, shellCommand: String) throws -> Bool {
        let source = """
        tell application "iTerm"
            if not (exists window id \(windowId)) then return false
            activate
            tell window id \(windowId)
                create tab with default profile
                tell current session
                    write text "\(appleScriptQuoted(shellCommand))"
                end tell
            end tell
            return true
        end tell
        """
        return try runScript(source).booleanValue
    }

    /// Splits the current session of the cached window in the requested
    /// direction and runs the command in the new pane. Returns `false` when
    /// the window no longer exists.
    private static func openSplit(inWindowId windowId: Int, shellCommand: String, direction: ITermSplit) throws -> Bool {
        let splitVerb: String
        switch direction {
        case .right, .left: splitVerb = "split vertically with default profile"
        case .up, .down:    splitVerb = "split horizontally with default profile"
        }

        let moveBlock: String
        switch direction {
        case .right, .down:
            moveBlock = ""
        case .left, .up:
            // iTerm2 default shortcut for "Move Active Session Left/Up"
            // is ⌘⌥⇧←/↑. Requires Accessibility permission; on the first
            // use macOS will prompt the user.
            let keyCode = (direction == .left) ? 123 : 126
            moveBlock = """

            delay 0.15
            tell application "System Events"
                key code \(keyCode) using {command down, option down, shift down}
            end tell
            """
        }

        let source = """
        tell application "iTerm"
            if not (exists window id \(windowId)) then return false
            activate
            tell window id \(windowId)
                tell current session of current tab
                    set newSession to (\(splitVerb))
                end tell
                tell newSession
                    write text "\(appleScriptQuoted(shellCommand))"
                end tell
            end tell
        end tell\(moveBlock)
        return true
        """
        return try runScript(source).booleanValue
    }

    /// Creates a new full-screen iTerm window and returns its integer id.
    private static func openNewWindow(shellCommand: String) throws -> Int {
        let bounds = fullScreenBounds()
        let source = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            set bounds of newWindow to {\(bounds.left), \(bounds.top), \(bounds.right), \(bounds.bottom)}
            tell current session of newWindow
                write text "\(appleScriptQuoted(shellCommand))"
            end tell
            return id of newWindow
        end tell
        """
        return Int(try runScript(source).int32Value)
    }

    private static func runScript(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw ITermLauncherError.scriptFailed("Could not compile AppleScript.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? "Failed to launch iTerm."
            throw ITermLauncherError.scriptFailed(message)
        }
        return result
    }

    // MARK: - Cache

    private static func cachedWindowId(for path: String) -> Int? {
        cacheQueue.sync { windowIdsByFolder[path] }
    }

    private static func setCachedWindowId(_ id: Int?, for path: String) {
        cacheQueue.sync {
            if let id {
                windowIdsByFolder[path] = id
            } else {
                windowIdsByFolder.removeValue(forKey: path)
            }
        }
    }

    // MARK: - Helpers

    private static func fullScreenBounds() -> (left: Int, top: Int, right: Int, bottom: Int) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let size = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        return (0, 0, Int(size.width), Int(size.height))
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuoted(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
