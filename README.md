# Harnessflow

Harnessflow is a native macOS app for managing AI/agent tickets through a linear workflow: Research, Plan, Implement, and Review.

## MVP Scope

- Single board with four fixed columns
- Ticket creation and selection
- Phase-specific prompt editing and execution
- Local persistence with SwiftData backed by SQLite
- Configurable per-phase model selection
- Provider abstraction with an initial Codex CLI implementation

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

## Notes

- The Codex provider runs the local `codex` CLI non-interactively.
- The default working directory and per-phase models are configurable in Settings.
- Review completion is terminal for the v1 board.

