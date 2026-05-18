# Harnessflow

Harnessflow is a native macOS app for managing AI/agent tickets through a linear workflow: Research, Plan, Implement, and Review.

## MVP Scope

- Single board with four fixed columns
- Ticket creation and selection
- Phase-specific prompt editing and execution
- Local persistence with SwiftData backed by SQLite
- Configurable per-phase model selection
- Provider abstraction with Codex CLI and Claude CLI implementations

## Project Layout

- `Harnessflow.xcodeproj`: macOS app project
- `Harnessflow/`: SwiftUI app, SwiftData models, persistence, and UI
- `HarnessflowCore/`: shared domain, workflow, provider interfaces, and tests

## Development

Build the core package tests:

```bash
swift test --package-path HarnessflowCore
```

Build the macOS app target:

```bash
xcodebuild -project Harnessflow.xcodeproj -target Harnessflow -configuration Debug build
```

## Provider Setup

- Codex runs the local `codex` CLI non-interactively and can use either the Codex CLI ChatGPT login or an OpenAI API key from Keychain.
- Claude runs the local `claude` CLI non-interactively with `claude -p`. The default path uses the Claude.ai subscription login from `claude auth login` with the Team/Enterprise account your admin invited, and Harnessflow strips conflicting API/cloud auth variables in that mode.
- Harnessflow intentionally does not use `claude --bare` for subscription mode because `--bare` skips the Claude OAuth/keychain login path that Team and Enterprise subscriptions rely on.
- Claude API key mode is still available if you intentionally want Anthropic API auth. Saved keys live in the macOS Keychain and are only injected when API key mode is selected.
- Claude permission mode is explicit. `bypassPermissions` matches the current unattended behavior, but `acceptEdits` is the safer default for day-to-day code work. `plan` is read-only, and `dontAsk` is for locked-down scripts.
- The active provider, executable paths, default working directory, auth mode, permission mode, and per-phase models are configurable in Settings.
- Starting June 15, 2026, `claude -p` on subscription plans uses monthly Agent SDK credit separate from interactive usage limits.
- Review completion is terminal for the v1 board.
