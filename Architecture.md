# Harnessflow Architecture

## Overview
Harnessflow is a native macOS app for moving tickets through a fixed, linear agent workflow:

`Research -> Plan -> Implement -> Review`

The workflow is intentionally constrained. It is not a general-purpose kanban system; it is an agent harness optimized for phase-based execution, handoff, and review.

## Architectural Principles
- Keep domain, workflow, prompt composition, provider interfaces, and auth resolution in `HarnessflowCore`.
- Keep SwiftData persistence, schema migration, process supervision, and SwiftUI view orchestration in the app target (`Harnessflow/`).
- Keep provider integrations behind `AgentProvider`; SwiftUI views do not call provider implementations directly.
- Preserve phase run history across rework when tickets move backward.
- Allow only adjacent phase movement; require successful completion before forward movement.

## System Boundaries
### `HarnessflowCore` responsibilities
- Domain model (`Ticket`, `TicketPhase`, `TicketPhaseState`, `PhaseRun`, `OwnedProcessReference`).
- Workflow rules (`TicketWorkflow`) for adjacent-only movement, forward gating, and rework reset semantics.
- Execution lifecycle (`TicketExecutionService`) including prompt assembly and result application.
- Deliverable marker contract (`PhaseDeliverableContract`) and bundled phase prompt templates.
- Provider protocol boundary (`AgentProvider`) and Codex CLI implementation (`CodexCLIProvider`).
- Authentication strategy and fallback policy (`CodexAuthResolver`, login status parsing).

### App target responsibilities (`Harnessflow/`)
- SwiftData schema/versioning and domain mapping (`PersistenceModels`, `PersistenceStore`).
- App orchestration (`AppStore`) for loading state, executing phases, handling retries/fallbacks, and persisting outcomes.
- Process ownership inspection and termination (`OwnedProcessSupervisor`).
- UI composition (`ContentView`, `BoardView`, `TicketDetailView`, `PhaseOutputWindowView`, `SettingsView`, `HarnessflowApp`).
- Secret storage for OpenAI API key via Keychain (`OpenAICredentialsStore` in app layer).

## Core Domain Model
- `TicketPhase` is a fixed enum with four phases: research, plan, implement, review.
- `Ticket` stores current column, completion metadata, and per-phase state snapshots.
- `TicketPhaseState` stores prompt addendum, execution state, captured output/error, deliverable markdown, owned process reference, and run history.
- `PhaseRun` stores immutable execution records (model, auth method, prompt, outputs, timestamps, success).
- `OwnedProcessReference` stores PID, executable path, and launch time for detached-process ownership checks.

## Workflow Semantics
`TicketWorkflow` enforces:
- Adjacent-only transitions (no skipping phases).
- Forward transitions only when the current phase state is `.completed`.
- Backward transitions reset later phase snapshots to idle and clear deliverable/output snapshots.
- Backward transitions preserve `runs` history for auditability and rework traceability.

Review is terminal in v1 board behavior.

## Execution Lifecycle
1. `AppStore` requests an `AgentRunRequest` from `TicketExecutionService` for the ticket's current phase.
2. `TicketExecutionService` composes prompt from:
   - phase base prompt from settings,
   - ticket title/details,
   - phase-specific addendum,
   - prior completed phase deliverables,
   - shared output contract markers.
3. `AppStore` resolves auth method using `CodexAuthResolver` (subscription/API strategy + login status + API key availability + model constraints).
4. `AppStore` marks phase as running, persists it, and starts live output capture.
5. `CodexCLIProvider` runs `codex exec` in the selected project working directory.
6. On completion, `TicketExecutionService`:
   - extracts deliverable markdown between required markers,
   - treats missing markers as failure even if process exit code is 0,
   - appends a `PhaseRun` record,
   - updates phase status and snapshots.
7. `AppStore` persists updates and optionally auto-shifts to the next adjacent phase when enabled.

Key distinction: raw run output is always captured, but only marker-wrapped deliverable markdown is persisted for phase handoff.

## Provider And Auth Model
- Provider boundary: `AgentProvider` protocol.
- Current implementation: `CodexCLIProvider` only.
- Current invocation shape includes model selection, working-directory override, stdin prompt piping, and non-interactive CLI execution.
- Auth strategies:
  - prefer subscription, fallback to API on rate-limit-like failures,
  - subscription only,
  - API key only.
- API key is stored in Keychain, not SwiftData.
- Subscription/API resolution is model-aware (some models require API key).

## Persistence Architecture
- SwiftData schema is versioned (`HarnessflowSchemaV1` -> `V4`) with migration stages.
- Persisted state includes:
  - projects and selected project,
  - tickets and per-phase state,
  - phase run history,
  - deliverables and run linkage,
  - owned process references,
  - settings (models, prompts, auth strategy, executable path, default directory).
- `PersistenceStore.bootstrapIfNeeded` performs startup normalization and migration-safe defaults:
  - creates a default project when missing,
  - associates orphan tickets,
  - ensures selected project validity,
  - fills missing bundled prompts,
  - normalizes auth strategy,
  - migrates legacy model defaults.

Project working directory is execution-scoped: runs use the selected project's directory, with settings default used for bootstrap/defaulting.

## Runtime Process Ownership And Recovery
- While running, `AppStore` holds in-memory live output streams keyed by ticket+phase.
- PID ownership is persisted via `OwnedProcessReference`.
- `OwnedProcessSupervisor` verifies liveness, executable identity, and launch time to avoid PID-reuse false positives.
- Recovery controls include graceful terminate, force kill, and manual clear of stuck running state when process is no longer terminable.

## UI Architecture
- Main layout is board + detail split view (`ContentView`).
- Board surface shows fixed phase columns and supports movement rules (`BoardView`).
- Detail surface edits prompts and executes phases (`TicketDetailView`).
- A separate output window shows streaming/persisted logs (`PhaseOutputWindowView`).
- Settings manages executable path, working directories, auth strategy, per-phase models, and per-phase prompts (`SettingsView`).

Views are intentionally thin; orchestration and domain mutation live in `AppStore` and core services.

## Test Coverage
`HarnessflowCore` tests cover critical architecture invariants:
- Workflow transition and rework semantics (`TicketWorkflowTests`).
- Request composition, prompt contract behavior, and deliverable extraction requirements (`TicketExecutionServiceTests`).
- Auth resolution and fallback logic (`CodexAuthenticationTests`).

Current gap: app-target persistence/orchestration/runtime recovery has limited direct automated test coverage.

## Current Limitations And Near-Term Evolution
- macOS-only target.
- Single implemented provider (`CodexCLIProvider`).
- Fixed four-phase linear workflow by design.
- Process supervision and recovery are local-session/system-process based.
- Architecture doc should be updated when provider behavior, auth policy, or schema versions change to avoid documentation drift.
