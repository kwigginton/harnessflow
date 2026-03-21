# Harnessflow Agent Guide

## Purpose

Harnessflow is a macOS AI/agent harness for moving tickets through four phases:

1. Research
2. Plan
3. Implement
4. Review

Each phase has a user-authored prompt, a configured model, execution state, and run history. The board is intentionally linear and optimized for agent-driven work rather than general-purpose task tracking.

## Phase Expectations

- `Research`: gather context, references, and constraints before solutioning.
- `Plan`: produce a concrete implementation spec with assumptions and tests.
- `Implement`: execute the plan and capture concrete changes or output.
- `Review`: validate the result, identify defects or regressions, and summarize residual risk.

## Engineering Rules

- Keep workflow and provider logic in `HarnessflowCore`.
- Keep SwiftData persistence and view orchestration in the app target.
- Provider integrations must live behind interfaces and service boundaries, never directly inside SwiftUI views.
- Preserve phase run history even when tickets move backward for rework.
- Forward ticket movement is adjacent-only and gated on successful completion of the current phase.

## Repository Conventions

- Use Swift 6.
- Prefer small, behavior-oriented types over large view files with embedded logic.
- Keep domain mapping outside SwiftUI views.
- Add tests for workflow rules and provider request construction in `HarnessflowCore/Tests`.

