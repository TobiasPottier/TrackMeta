# TrackMeta

macOS menu bar app that shows your Claude Max usage (5-hour session + 7-day) right next to the clock. It reuses the OAuth token that the Claude Code CLI already stores in the macOS Keychain, sends a cheap 1-token request to `api.anthropic.com`, and reads the rate-limit utilization out of the response headers.

## Requirements

- macOS 14+
- Xcode 15+
- The Claude Code CLI installed and logged in on this Mac (`claude` in Terminal). TrackMeta reads its OAuth token from the Keychain item `Claude Code-credentials` — it does not store credentials of its own.

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
3. The label updates to show your current 5-hour utilization. Click it for the full popover with both 5h and 7d buckets and reset times.

If requests start failing with 401, your OAuth token expired — run `claude /login` in a terminal, then hit Reload in TrackMeta.

## Why not the public Anthropic API?

Claude **Max** subscription usage isn't exposed by the public Messages / admin APIs. The only way to see it programmatically is to make a real Messages request and read the `anthropic-ratelimit-unified-5h-*` / `anthropic-ratelimit-unified-7d-*` headers. That's what TrackMeta does — one `max_tokens: 1` request per minute.

## Project layout

```
TrackMeta.xcodeproj
TrackMeta/
  TrackMeta.entitlements             sandbox + network.client
  Assets.xcassets/                   app icon
  Sources/
    App/TrackMetaApp.swift           @main, MenuBarExtra + Settings scene
    Models/
      UsageSnapshot.swift            UsageBucket / UsageSnapshot / UsageLoadState
      PeakHours.swift
    Services/
      ClaudeCredentialsStore.swift   reads Keychain → claudeAiOauth.accessToken
      ClaudeUsageClient.swift        POST /v1/messages; snapshot from headers
    ViewModels/
      UsageViewModel.swift           @Observable; 60s auto-refresh loop
    Views/
      MenuBarLabel.swift             icon + % in the menu bar
      UsagePopover.swift             click-to-open panel
      SettingsView.swift             Settings scene body
      TrackerLogo.swift
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
- Sandbox stays on; the `com.apple.security.network.client` entitlement is what lets it reach `api.anthropic.com`.
- Nothing is persisted by TrackMeta itself. All auth state lives in the Claude Code CLI's Keychain item.
