# TrackMeta

macOS menu bar app that shows your Claude Max usage (5-hour session + 7-day) right next to the clock. It reuses the OAuth token that the Claude Code CLI already stores in the macOS Keychain, sends a cheap 1-token request to `api.anthropic.com`, and reads the rate-limit utilization out of the response headers.

It also shows a live **Sessions panel** for any Claude Code sessions running locally, charts your 5h-window usage history, registers a ⌃⌥Space global hotkey that toggles a notch-attached popover from anywhere, and ships a full dashboard window with a **Launch agent** button that opens a folder picker and starts a new Claude Code session in iTerm (as a new tab or split pane in the existing window for that folder).

## Requirements

- macOS 14+
- Xcode 15+
- The Claude Code CLI installed and logged in on this Mac (`claude` in Terminal). TrackMeta reads its OAuth token from the Keychain item `Claude Code-credentials` — it does not store credentials of its own.
- iTerm2 is required for the **Launch agent** button. macOS will prompt once for permission to control iTerm via Apple Events; click **OK**. Splitting a window left or up additionally requires Accessibility permission (TrackMeta synthesizes ⌘⌥⇧← / ⌘⌥⇧↑ via System Events to move the new pane).

## Build & run

```sh
open TrackMeta.xcodeproj
# ⌘R
```

Or from the command line:

```sh
xcodebuild -project TrackMeta.xcodeproj -scheme TrackMeta -configuration Debug build
```

On first launch:

1. The TrackMeta icon appears next to the clock.
2. macOS will prompt once for Keychain access to `Claude Code-credentials`. Click **Always Allow** so subsequent refreshes are silent; "Allow Once" will re-prompt every minute.
3. The label updates to show your current 5-hour utilization. Click it — or press **⌃⌥Space** from anywhere — to open the notch-attached popover with both 5h and 7d buckets, reset times, a usage history chart, and the live Sessions panel.
4. If a Claude Code sessions server is running on `http://localhost:7777`, the Sessions panel lists each session (status / last tool / cwd / summary). If it isn't, the Sessions section stays empty and the usage readout still works.

The usage history chart builds up samples over the current 5h window and rolls over when the window resets.

If requests start failing with 401, your OAuth token expired — run `claude /login` in a terminal, then hit Reload in TrackMeta.

If Anthropic returns 429, TrackMeta treats it as a Claude Max usage cap rather than a load failure. The full popover stays available, usage shows as capped, and live sessions continue to render.

## Why not the public Anthropic API?

Claude **Max** subscription usage isn't exposed by the public Messages / admin APIs. The only way to see it programmatically is to make a real Messages request and read the `anthropic-ratelimit-unified-5h-*` / `anthropic-ratelimit-unified-7d-*` headers. That's what TrackMeta does — one `max_tokens: 1` request per minute. The 1-second session poll is a separate call to `http://localhost:7777`, not an Anthropic API hit.

## Project layout

```
TrackMeta.xcodeproj
TrackMeta/
  TrackMeta.entitlements             sandbox + network.client
  Assets.xcassets/                   app icon
  Sources/
    App/TrackMetaApp.swift           @main, MenuBarExtra + Settings scene; wires hotkey + popover
    Models/
      UsageSnapshot.swift            UsageBucket / UsageSnapshot / UsageLoadState / sessionProgress
      ClaudeSession.swift            live Claude Code session model
      PeakHours.swift
    Services/
      ClaudeCredentialsStore.swift   reads Keychain → claudeAiOauth.accessToken
      ClaudeUsageClient.swift        POST /v1/messages; snapshot from headers
      ClaudeSessionClient.swift      GET http://localhost:7777; polled every 1s
      GlobalHotkey.swift             Carbon ⌃⌥Space → toggle popover
      UsageHistoryStore.swift        UserDefaults-backed sample buffer ("usageHistory.v1")
      SessionHistoryStore.swift      per-session events / activity buckets / first-seen time (pure ingestion)
      ITermLauncher.swift            AppleScript launcher; per-folder window cache; tabs or split panes
    ViewModels/
      UsageViewModel.swift           @Observable; 60s usage refresh + 1s session poll; owns session histories + expansion state
    Views/
      MenuBarLabel.swift             % indicator, session-elapsed stripe, time-until-reset
      UsagePopover.swift             notch-attached popover with Swift Charts history
      DashboardView.swift            two-pane dashboard: navigation rail + cards; "Launch agent" button
      SessionGrid.swift              aggregate header + tile grid (standard / compact); groups by folder
      SessionTile.swift              per-agent tile, collapsed and expanded layouts, ActivitySparkline
      SessionVisuals.swift           shared SessionStatusPalette + PulsingDot
      SettingsView.swift             Settings scene body; FloatingWindowConfigurator
      TrackerLogo.swift              brand mark + BrandPalette tokens
TrackMetaTests/                      unit tests
TrackMetaUITests/                    UI tests
```

Data flow is one-way: Keychain → `ClaudeUsageClient` → `UsageViewModel` (`UsageLoadState`) → SwiftUI views.

## Tests

```sh
xcodebuild -project TrackMeta.xcodeproj -scheme TrackMeta \
  -destination 'platform=macOS' test
```

Single test:

```sh
xcodebuild ... test -only-testing:TrackMetaTests/TrackMetaTests/<methodName>
```

## Notes

- The app is an `LSUIElement` agent — no Dock icon, only the menu bar extra.
- Sandbox stays on; entitlements granted are: `com.apple.security.network.client` (reaches `api.anthropic.com` and `localhost:7777`), `com.apple.security.automation.apple-events` plus a temporary-exception for `com.googlecode.iterm2` (the iTerm launcher), and `com.apple.security.files.user-selected.read-only` (the Launch-agent folder picker).
- Auth state is never stored by TrackMeta — it lives in the Claude Code CLI's Keychain item. TrackMeta does persist two small UserDefaults keys for UX state: `usageHistory.v1` (rolling 5h sample buffer) and `TrackMeta.sessionsPinned` (Sessions panel pin toggle).
- ⌃⌥Space is registered process-wide via Carbon; it toggles the popover whether or not TrackMeta is frontmost.
