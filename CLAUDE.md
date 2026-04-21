# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TrackMeta is a macOS menu bar (`MenuBarExtra`) SwiftUI app that shows Claude Max usage. It does **not** use the public Anthropic API's usage endpoints (those don't expose Max subscription usage). Instead, it sends a cheap 1-token `POST /v1/messages` request and reads the rate-limit utilization from the **response headers** (`anthropic-ratelimit-unified-5h-utilization` / `-7d-utilization` and their `-reset` counterparts).

Note: the README describes an older design that used a `claude.ai` session cookie pasted into Settings. The current implementation instead reads the Claude Code CLI's OAuth access token out of the macOS Keychain (service `Claude Code-credentials`, JSON value, `claudeAiOauth.accessToken`). If you see references to `sessionKey` / `SessionKeyStore` in docs, they're stale.

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

## Architecture

Layered, one-way data flow: Keychain → Client → ViewModel → Views. Everything is value-type / immutable per the user's coding rules.

```
Sources/
  App/TrackMetaApp.swift            @main; MenuBarExtra(.window) + Settings scene
  Models/
    UsageSnapshot.swift             UsageBucket, UsageSnapshot, UsageLoadState enum
    PeakHours.swift
  Services/
    ClaudeCredentialsStore.swift    SecItemCopyMatching → parses claudeAiOauth.accessToken
    ClaudeUsageClient.swift         POST /v1/messages; snapshot built from response headers
  ViewModels/UsageViewModel.swift   @Observable; 60s auto-refresh Task loop; owns UsageLoadState
  Views/
    MenuBarLabel.swift              icon + % shown in the menu bar
    UsagePopover.swift              click-to-open window content
    SettingsView.swift              Settings scene body
    TrackerLogo.swift
```

Key invariants to preserve when editing:

- `ClaudeUsageClient` never throws on missing headers — a missing header means 0% utilization. Don't turn that into an error.
- The request uses `anthropic-beta: oauth-2025-04-20` and `User-Agent: claude-code/<version>`. These are required for the OAuth token to be accepted; don't drop them when refactoring headers.
- `UsageViewModel.refreshTask` is a single long-lived `Task` that sleeps 60s between polls. If you add a manual refresh path, reuse `refreshOnce()` rather than starting a parallel loop.
- State flows through `UsageLoadState` (`idle | loading | loaded | failed`); views read `model.snapshot` which collapses non-loaded states to `.empty`. Keep that collapse in one place.
- `ClaudeUsageError.errorDescription` strings are shown verbatim in the UI — update them carefully.

## Things that are easy to get wrong

- The project has a doubly-nested layout: repo root contains `TrackMeta/` which contains both the `.xcodeproj` and the source `TrackMeta/` group. Paths in build commands must reflect this.
- `README.md` is out of date (cookie-based flow). Prefer code over README when they disagree.
- Do not add the App Sandbox's default restrictions back — outbound HTTPS to `api.anthropic.com` must work.
- The Keychain service string `"Claude Code-credentials"` is literal (with space and capital C) — it's what the Claude Code CLI writes. Don't "fix" the spacing.
