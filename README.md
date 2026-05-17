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
- Claude runs the local `claude` CLI non-interactively with `claude -p`; when saved, Harnessflow passes the Anthropic key as `ANTHROPIC_API_KEY`.
- The active provider, executable paths, default working directory, and per-phase models are configurable in Settings.
- Review completion is terminal for the v1 board.
