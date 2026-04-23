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
/// one. Also records the `unique id` of every iTerm session we launch so
/// `focus(cwd:)` can bring that exact tab to the front later.
enum ITermLauncher {
    private static let cacheQueue = DispatchQueue(label: "ITermLauncher.cache")
    private static var windowIdsByFolder: [String: Int] = [:]
    private static var sessionUidsByFolder: [String: [String]] = [:]
    private static let sessionUidCap = 8

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
            let outcome: LaunchOutcome
            if let split {
                outcome = try openSplit(inWindowId: cached, shellCommand: shellCommand, direction: split)
            } else {
                outcome = try openTab(inWindowId: cached, shellCommand: shellCommand)
            }
            if outcome.didReuse {
                if let uid = outcome.sessionUid { rememberSessionUid(uid, for: path) }
                return
            }
            setCachedWindowId(nil, for: path)
        }

        let fresh = try openNewWindow(shellCommand: shellCommand)
        setCachedWindowId(fresh.windowId, for: path)
        rememberSessionUid(fresh.sessionUid, for: path)
    }

    // MARK: - AppleScript paths

    private struct LaunchOutcome {
        let didReuse: Bool
        let sessionUid: String?
    }

    /// Creates a new tab in the given window and runs the command. Returns
    /// `didReuse = false` when the window no longer exists so the caller can
    /// fall back to creating a fresh window. On success, `sessionUid` is the
    /// new session's iTerm `unique id`.
    private static func openTab(inWindowId windowId: Int, shellCommand: String) throws -> LaunchOutcome {
        let source = """
        tell application "iTerm"
            if not (exists window id \(windowId)) then return {false, ""}
            activate
            set sid to ""
            tell window id \(windowId)
                create tab with default profile
                tell current session
                    set sid to unique id
                    write text "\(appleScriptQuoted(shellCommand))"
                end tell
            end tell
            return {true, sid}
        end tell
        """
        return try decodeLaunchOutcome(runScript(source))
    }

    /// Splits the current session of the cached window in the requested
    /// direction and runs the command in the new pane. Returns
    /// `didReuse = false` when the window no longer exists.
    private static func openSplit(inWindowId windowId: Int, shellCommand: String, direction: ITermSplit) throws -> LaunchOutcome {
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
            if not (exists window id \(windowId)) then return {false, ""}
            activate
            set sid to ""
            tell window id \(windowId)
                tell current session of current tab
                    set newSession to (\(splitVerb))
                end tell
                tell newSession
                    set sid to unique id
                    write text "\(appleScriptQuoted(shellCommand))"
                end tell
            end tell\(moveBlock)
            return {true, sid}
        end tell
        """
        return try decodeLaunchOutcome(runScript(source))
    }

    /// Creates a new full-screen iTerm window. Returns the window's integer
    /// id and the new session's iTerm `unique id`.
    ///
    /// When iTerm wasn't already running, `tell application "iTerm"` launches
    /// it and iTerm auto-creates a startup window. In that case we reuse the
    /// startup window instead of calling `create window` — otherwise we'd end
    /// up with an empty ghost window alongside the real one.
    private static func openNewWindow(shellCommand: String) throws -> (windowId: Int, sessionUid: String) {
        let bounds = fullScreenBounds()
        let iTermBundleId = "com.googlecode.iterm2"
        let wasRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: iTermBundleId)
            .isEmpty

        let windowExpr = wasRunning
            ? "(create window with default profile)"
            : "current window"

        let source = """
        tell application "iTerm"
            activate
            set newWindow to \(windowExpr)
            set bounds of newWindow to {\(bounds.left), \(bounds.top), \(bounds.right), \(bounds.bottom)}
            set sid to ""
            tell current session of newWindow
                set sid to unique id
                write text "\(appleScriptQuoted(shellCommand))"
            end tell
            return {id of newWindow, sid}
        end tell
        """
        let desc = try runScript(source)
        let wid = Int(desc.atIndex(1)?.int32Value ?? 0)
        let uid = desc.atIndex(2)?.stringValue ?? ""
        return (wid, uid)
    }

    private static func decodeLaunchOutcome(_ desc: NSAppleEventDescriptor) -> LaunchOutcome {
        let didReuse = desc.atIndex(1)?.booleanValue ?? false
        let uid = desc.atIndex(2)?.stringValue ?? ""
        return LaunchOutcome(didReuse: didReuse, sessionUid: uid.isEmpty ? nil : uid)
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

    private static func rememberSessionUid(_ uid: String, for path: String) {
        guard !uid.isEmpty else { return }
        cacheQueue.sync {
            var list = sessionUidsByFolder[path] ?? []
            if let existing = list.firstIndex(of: uid) {
                list.remove(at: existing)
            }
            list.append(uid)
            if list.count > sessionUidCap {
                list.removeFirst(list.count - sessionUidCap)
            }
            sessionUidsByFolder[path] = list
        }
    }

    private static func cachedSessionUids(for path: String) -> [String] {
        cacheQueue.sync { sessionUidsByFolder[path] ?? [] }
    }

    private static func removeSessionUids(_ uids: Set<String>, for path: String) {
        guard !uids.isEmpty else { return }
        cacheQueue.sync {
            guard var list = sessionUidsByFolder[path] else { return }
            list.removeAll { uids.contains($0) }
            if list.isEmpty {
                sessionUidsByFolder.removeValue(forKey: path)
            } else {
                sessionUidsByFolder[path] = list
            }
        }
    }

    // MARK: - Focus

    /// Brings an iTerm tab previously launched in `cwd` to the front by
    /// matching against cached session `unique id`s. This is the only method
    /// that works reliably under the macOS app sandbox — every approach that
    /// requires reading another process's cwd (lsof, proc_pidinfo) is
    /// sandbox-restricted, and iTerm's `session.path` variable throws -1723
    /// for sessions that haven't populated it. Returns `true` if a cached
    /// session was found live and focused.
    @discardableResult
    static func focus(cwd: String) throws -> Bool {
        let uids = cachedSessionUids(for: cwd)
        guard !uids.isEmpty else {
            _ = try? runScript(#"tell application "iTerm" to activate"#)
            return false
        }

        let uidListLiteral = uids
            .map { "\"\(appleScriptQuoted($0))\"" }
            .joined(separator: ", ")

        let source = """
        tell application "iTerm"
            activate
            set targetUids to {\(uidListLiteral)}
            set foundUid to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set uid to unique id of s
                        if uid is in targetUids then
                            set current tab of w to t
                            select s
                            set foundUid to uid
                            exit repeat
                        end if
                    end repeat
                    if foundUid is not "" then exit repeat
                end repeat
                if foundUid is not "" then exit repeat
            end repeat
            return foundUid
        end tell
        """
        let desc = try runScript(source)
        let foundUid = desc.stringValue ?? ""

        if foundUid.isEmpty {
            // None of our cached sessions are live anymore — purge so the
            // cache doesn't grow with zombie UIDs.
            removeSessionUids(Set(uids), for: cwd)
            return false
        }
        return true
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
