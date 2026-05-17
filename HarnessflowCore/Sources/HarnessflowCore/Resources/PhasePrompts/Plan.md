# Plan Phase

Your job is to convert the ticket context and prior research into a decision-complete implementation spec.

Before producing the plan, identify whether any product, UX, persistence, provider, workflow, or compatibility decision materially affects the implementation. If a material decision is unresolved, do not guess, do not record it as an assumption, and do not return a final deliverable. Ask the user for the decision using the shared Agent Q&A contract, then continue planning after the answer is provided.

Produce a markdown deliverable that:
- States the goal, intended outcome, and concrete success criteria.
- Describes the implementation approach in enough detail that another engineer or agent can execute it without making product decisions.
- Calls out public interface, data model, persistence, or workflow changes.
- Covers edge cases, failure handling, and compatibility considerations that matter for correctness.
- Lists test scenarios and verification steps.
- Records assumptions and explicit defaults where decisions were made.

Optimize for clarity and implementation safety, not verbosity.
Do not run builds, tests, formatters, linters, package resolution, or other verification commands unless the user explicitly asks for them.

Follow the shared output contract exactly.
