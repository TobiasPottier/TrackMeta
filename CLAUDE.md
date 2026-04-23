# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TrackMeta is a macOS menu bar (`MenuBarExtra`) SwiftUI app that surfaces Claude Max usage next to the clock. It does **not** use the public Anthropic API's usage endpoints (those don't expose Max subscription usage). Instead, it sends a cheap 1-token `POST /v1/messages` request and reads the rate-limit utilization from the **response headers** (`anthropic-ratelimit-unified-5h-utilization` / `-7d-utilization` and their `-reset` counterparts).

Beyond the core usage readout, the app also:

- Polls `http://localhost:7777` once per second for live Claude Code sessions (status / last tool / last-tool-target / cwd / summary / context_percentage) and groups them by their working directory in a read-only **Sessions** panel. A connection failure is not an error — empty sessions is a valid state. TrackMeta does **not** start sessions or control iTerm; session lifecycle is owned by the user's IDE / CLI.
- Buffers per-session metadata locally (first-seen time, recent events, per-minute activity buckets) so each tile can show an elapsed timer, an activity sparkline, and a short event log even though the server itself is stateless.
- Persists a rolling buffer of 5h-window usage samples and plots them as a Swift Charts history in the popover.
- Registers a process-wide ⌃⌥Space global hotkey (Carbon API) that toggles the dashboard window.
- Opens a single dashboard window (1120x720, midnight-blue redesign) that shows peak hours, 5-hour usage, the usage chart, weekly usage, and the Sessions panel. A **Pin** button in the header toggles the dashboard's window level to `.floating` so it stays above other apps — this is the only floating UI (there is no separate floating panel).
- Raises the Settings window above the status bar via a FloatingWindowConfigurator.

Credentials come from the Claude Code CLI's OAuth access token, read out of the macOS Keychain (service `Claude Code-credentials`, JSON value, `claudeAiOauth.accessToken`). The app does not store credentials of its own, but it **does** persist three UserDefaults keys: `usageHistory.v1` (sample buffer), `TrackMeta.sessionsPinned` (pin toggle), and `TrackMeta.orchestratorFolders` (saved project folder paths).

## Build / run / test

This is an Xcode project — there's no Swift Package Manager or Makefile.

```sh
# Project is at TrackMeta/TrackMeta.xcodeproj (note the nested TrackMeta/TrackMeta/ layout)
open TrackMeta/TrackMeta.xcodeproj            # then ⌘R in Xcode

# Command-line build
xcodebuild -project TrackMeta/TrackMeta.xcodeproj -scheme TrackMeta -configuration Debug build

# Run tests (unit + UI)
xcodebuild -project TrackMeta/TrackMeta.xcodeproj -scheme TrackMeta \
  -destination 'platform=macOS' test

# Run a single test
xcodebuild ... test -only-testing:TrackMetaTests/TrackMetaTests/<methodName>
```

Target: macOS 14+. App is an `LSUIElement` agent (no Dock icon). Needs outbound HTTPS to `api.anthropic.com` — the entitlements file keeps sandbox on with `com.apple.security.network.client`.

## First-run requirements

- The Claude Code CLI (`claude`) must already be logged in on this Mac so the Keychain item `Claude Code-credentials` exists. Without it the UI shows "No Claude Code credentials found."
- First Keychain read triggers a macOS prompt — the user must click **Always Allow** for silent subsequent reads. If they pick "Allow Once", every refresh re-prompts.
- When the token expires, requests return 401 → user runs `claude /login` and hits Reload.
- When Anthropic returns 429 or 439, treat it as Claude Max usage-cap reached, not a hard load error. The UI should render the normal app, mark the cap as reached, preserve the last known usage percentages if the capped response omits utilization headers, and continue showing sessions.
- The Sessions panel depends on a local sessions server reachable at `http://localhost:7777`. If it isn't running, the Sessions section stays empty but the usage readout still works.
- ⌃⌥Space is registered as a process-wide hotkey that toggles the dashboard window from anywhere.

## Architecture

Layered, one-way data flow: Keychain → Client → ViewModel → Views. Everything is value-type / immutable per the user's coding rules.

```
Sources/
  App/TrackMetaApp.swift            @main; MenuBarExtra(.window) + Settings scene; wires hotkey + notch pill + dashboard window; owns the dashboard "pin to floating" toggle
  Models/
    UsageSnapshot.swift             UsageBucket, UsageSnapshot, UsageLoadState, sessionProgress(...)
    ClaudeSession.swift             ClaudeSession model (status / lastTool / lastToolTarget / cwd / summary / contextPercentage)
    PeakHours.swift
  Services/
    ClaudeCredentialsStore.swift    SecItemCopyMatching → parses claudeAiOauth.accessToken
    ClaudeUsageClient.swift         POST /v1/messages; snapshot built from response headers; 429/439 treated as capped; preserves prior utilization when headers absent
    ClaudeSessionClient.swift       GET http://localhost:7777 → [ClaudeSession]; polled every 1s
    GlobalHotkey.swift              Carbon process-wide ⌃⌥Space → toggle dashboard
    UsageHistoryStore.swift         UserDefaults-backed 5h sample buffer (key "usageHistory.v1")
    SessionHistoryStore.swift       SessionHistory + SessionHistoryIngestion (pure); per-session events / activity buckets / firstSeenAt
  ViewModels/UsageViewModel.swift   @Observable; 60s usage loop + 1s session loop; owns sessions, sessionHistories, expandedSessionIds, autoExpand window, sessionsPinned, unifiedFolderGroups (live sessions grouped by cwd)
  Views/
    MenuBarLabel.swift              110pt indicator: % + session-elapsed stripe + center dot + time-until-reset
    UsagePopover.swift              notch-attached popover (NotchIslandShape), 560pt wide, Swift Charts usage history
    DashboardView.swift             single-pane dashboard: peak + 5h + chart + weekly + Sessions card; header has Pin / Refresh buttons
    ProjectFoldersPanel.swift       read-only Sessions panel: groups live sessions by cwd, indents SessionTiles under each folder row
    SessionTile.swift               per-agent tile w/ collapsed and expanded layouts; ActivitySparkline of per-minute event counts
    SessionVisuals.swift            shared SessionStatusPalette + PulsingDot
    SettingsView.swift              Settings scene body; FloatingWindowConfigurator raises above .statusBar
    TrackerLogo.swift               brand mark + BrandPalette (midnight-blue: sidebar / cardFill / borderSoft / mutedStrong)
```

Key invariants to preserve when editing:

- `ClaudeUsageClient` never throws on missing headers — a missing header means 0% utilization. Don't turn that into an error.
- `ClaudeUsageClient` treats HTTP 429/439 as a successful capped snapshot so the app does not get stuck behind an error message. Do not synthesize usage as 100% for capped responses; keep utilization headers when present, or preserve the last loaded snapshot when they are absent.
- The request uses `anthropic-beta: oauth-2025-04-20` and `User-Agent: claude-code/<version>`. These are required for the OAuth token to be accepted; don't drop them when refactoring headers.
- `UsageViewModel` runs **two** long-lived `Task`s: a 60s usage-refresh loop and a 1s session-poll loop. If you add a manual refresh path, reuse the existing `refreshOnce()` entry points rather than starting a third parallel loop. When warning about parallel loops, specify which one.
- State flows through `UsageLoadState` (`idle | loading | loaded | failed`); views read `model.snapshot` which collapses non-loaded states to `.empty`. Keep that collapse in one place.
- `ClaudeUsageError.errorDescription` strings are shown verbatim in the UI — update them carefully.
- `ClaudeSessionClient` hits `http://localhost:7777` unauthenticated. Connection failure is not a hard error — an empty sessions list is valid state. Do not surface transport errors to the user.
- `UsageHistoryStore` rolls its buffer when a new `reset` timestamp is observed. That is intentional — don't treat the drop as state loss.
- `GlobalHotkey` must unregister its Carbon handler on deinit; Carbon event handlers leak otherwise.
- `SessionHistoryIngestion` is pure — every poll produces a brand-new `SessionHistory` value via `update(_:with:at:)`. Do not mutate the stored value in place. Activity buckets roll forward minute-by-minute; if more than `bucketCount` minutes elapse the buffer is reset to zeros (intentional, not data loss).
- `UsageViewModel` auto-expands a tile for `Self.autoExpandDuration` (8s) the first time it sees a session transition into `awaitingInput`. The user clicking the tile clears that auto-expand window. Don't extend the duration without thinking about it — the point is to surface the new "needs input" state without permanently expanding it.
- `UsageViewModel.refreshOnce` passes `lastLoadedSnapshot` to `ClaudeUsageClient.fetchSnapshot(preservingUsageFrom:)` so a 429/439 response with missing utilization headers preserves the last known percentage instead of flickering to 0. It also no longer drops to `.loading` once a snapshot has loaded — the view keeps rendering the last value while a refresh is in flight.
- The dashboard's **Pin** button flips the hosting window between `.normal` and `.floating` level via `AppDelegate.applyPinnedBehavior(to:)`. The pinned state persists to UserDefaults (`TrackMeta.dashboardPinned`). There is no separate floating panel — the dashboard itself is the float target.
- `AppDelegate.updateActivationPolicy()` drops back to `.accessory` whenever the dashboard window is not visible. It is the single place that decision lives.
- TrackMeta is strictly a read-only session viewer. Do not reintroduce iTerm launching, orchestration, or session-spawning flows — session lifecycle belongs to the user's IDE.

## Things that are easy to get wrong

- The project has a doubly-nested layout: repo root contains `TrackMeta/` which contains both the `.xcodeproj` and the source `TrackMeta/` group. Paths in build commands must reflect this.
- Do not add the App Sandbox's default restrictions back — outbound HTTPS to `api.anthropic.com` must work.
- The Keychain service string `"Claude Code-credentials"` is literal (with space and capital C) — it's what the Claude Code CLI writes. Don't "fix" the spacing.
- UserDefaults keys `usageHistory.v1`, `TrackMeta.sessionsPinned`, `TrackMeta.sessionsPinnedCollapsed`, and `TrackMeta.dashboardPinned` are persistence contracts. Renaming any of them wipes user state on upgrade.
- `TrackMeta.entitlements` only needs `com.apple.security.app-sandbox` + `com.apple.security.network.client`. Do not re-add Apple Events / iTerm / user-selected-files entitlements — they were dropped when the iTerm launcher was removed.
- The notch-pill tap action calls `openDashboard()` (always show), not `toggleDashboard()` — toggling caused the dashboard to close on the same click that re-focused it. The status-bar icon click still toggles.
