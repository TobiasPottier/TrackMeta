# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TrackMeta is a macOS menu bar (`MenuBarExtra`) SwiftUI app that surfaces Claude Max usage next to the clock. It does **not** use the public Anthropic API's usage endpoints (those don't expose Max subscription usage). Instead, it sends a cheap 1-token `POST /v1/messages` request and reads the rate-limit utilization from the **response headers** (`anthropic-ratelimit-unified-5h-utilization` / `-7d-utilization` and their `-reset` counterparts).

Beyond the core usage readout, the app also:

- Polls `http://localhost:7777` once per second for live Claude Code sessions (status / last tool / cwd / summary) and renders a Sessions panel. A connection failure is not an error — empty sessions is a valid state.
- Persists a rolling buffer of 5h-window usage samples and plots them as a Swift Charts history in the popover.
- Registers a process-wide ⌃⌥Space global hotkey (Carbon API) that toggles a notch-attached popover.
- Raises the Settings window above the status bar via a FloatingWindowConfigurator.

Credentials come from the Claude Code CLI's OAuth access token, read out of the macOS Keychain (service `Claude Code-credentials`, JSON value, `claudeAiOauth.accessToken`). The app does not store credentials of its own, but it **does** persist two UserDefaults keys: `usageHistory.v1` (sample buffer) and `TrackMeta.sessionsPinned` (pin toggle).

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
- The Sessions panel depends on a local sessions server reachable at `http://localhost:7777`. If it isn't running, the Sessions section stays empty but the usage readout still works.
- ⌃⌥Space is registered as a process-wide hotkey that toggles the popover from anywhere.

## Architecture

Layered, one-way data flow: Keychain → Client → ViewModel → Views. Everything is value-type / immutable per the user's coding rules.

```
Sources/
  App/TrackMetaApp.swift            @main; MenuBarExtra(.window) + Settings scene; wires hotkey + popover
  Models/
    UsageSnapshot.swift             UsageBucket, UsageSnapshot, UsageLoadState, sessionProgress(...)
    ClaudeSession.swift             ClaudeSession model (status / lastTool / cwd / summary)
    PeakHours.swift
  Services/
    ClaudeCredentialsStore.swift    SecItemCopyMatching → parses claudeAiOauth.accessToken
    ClaudeUsageClient.swift         POST /v1/messages; snapshot built from response headers
    ClaudeSessionClient.swift       GET http://localhost:7777 → [ClaudeSession]; polled every 1s
    GlobalHotkey.swift              Carbon process-wide ⌃⌥Space → toggle popover
    UsageHistoryStore.swift         UserDefaults-backed 5h sample buffer (key "usageHistory.v1")
  ViewModels/UsageViewModel.swift   @Observable; runs 60s usage loop AND 1s session loop; owns sessions/history/sessionsPinned
  Views/
    MenuBarLabel.swift              110pt indicator: % + session-elapsed stripe + center dot + time-until-reset
    UsagePopover.swift              notch-attached popover (NotchIslandShape), 560pt wide, Swift Charts usage history
    SessionsSection.swift           per-session rows + aggregate header; pin persisted to "TrackMeta.sessionsPinned"
    SettingsView.swift              Settings scene body; FloatingWindowConfigurator raises above .statusBar
    TrackerLogo.swift
```

Key invariants to preserve when editing:

- `ClaudeUsageClient` never throws on missing headers — a missing header means 0% utilization. Don't turn that into an error.
- The request uses `anthropic-beta: oauth-2025-04-20` and `User-Agent: claude-code/<version>`. These are required for the OAuth token to be accepted; don't drop them when refactoring headers.
- `UsageViewModel` runs **two** long-lived `Task`s: a 60s usage-refresh loop and a 1s session-poll loop. If you add a manual refresh path, reuse the existing `refreshOnce()` entry points rather than starting a third parallel loop. When warning about parallel loops, specify which one.
- State flows through `UsageLoadState` (`idle | loading | loaded | failed`); views read `model.snapshot` which collapses non-loaded states to `.empty`. Keep that collapse in one place.
- `ClaudeUsageError.errorDescription` strings are shown verbatim in the UI — update them carefully.
- `ClaudeSessionClient` hits `http://localhost:7777` unauthenticated. Connection failure is not a hard error — an empty sessions list is valid state. Do not surface transport errors to the user.
- `UsageHistoryStore` rolls its buffer when a new `reset` timestamp is observed. That is intentional — don't treat the drop as state loss.
- `GlobalHotkey` must unregister its Carbon handler on deinit; Carbon event handlers leak otherwise.

## Things that are easy to get wrong

- The project has a doubly-nested layout: repo root contains `TrackMeta/` which contains both the `.xcodeproj` and the source `TrackMeta/` group. Paths in build commands must reflect this.
- Do not add the App Sandbox's default restrictions back — outbound HTTPS to `api.anthropic.com` must work.
- The Keychain service string `"Claude Code-credentials"` is literal (with space and capital C) — it's what the Claude Code CLI writes. Don't "fix" the spacing.
- UserDefaults keys `usageHistory.v1` and `TrackMeta.sessionsPinned` are persistence contracts. Renaming them wipes user state on upgrade.
