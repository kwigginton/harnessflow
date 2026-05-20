import Foundation

public enum PhaseDeliverableContract {
    public static let startMarker = "<<<HARNESSFLOW_DELIVERABLE_START>>>"
    public static let endMarker = "<<<HARNESSFLOW_DELIVERABLE_END>>>"

    public static var instructions: String {
        """
        Output Contract
        Return the final phase deliverable as markdown wrapped exactly between these markers:

        \(startMarker)
        [markdown deliverable]
        \(endMarker)

        Do not omit either marker. The wrapped markdown is what Harnessflow persists and passes to later phases.
        """
    }

    public static func extractDeliverable(from output: String) -> String? {
        guard let startRange = output.range(of: startMarker) else {
            return nil
        }

        let contentStart = startRange.upperBound
        guard let endRange = output.range(of: endMarker, range: contentStart..<output.endIndex) else {
            return nil
        }

        let deliverable = output[contentStart..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return deliverable.isEmpty ? nil : deliverable
    }

    public static func recoverUnwrappedDeliverable(from output: String, phase: TicketPhase) -> String? {
        guard
            output.range(of: startMarker) == nil,
            output.range(of: endMarker) == nil
        else {
            return nil
        }

        let deliverable = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard deliverable.count >= 80, hasMarkdownStructure(deliverable) else {
            return nil
        }

        if phase == .review, ReviewFinalPassContract.requiresFinalPass(in: deliverable) == nil {
            return nil
        }

        return deliverable
    }

    private static func hasMarkdownStructure(_ markdown: String) -> Bool {
        let lines = markdown.components(separatedBy: .newlines)
        var signalCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                signalCount += 2
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                signalCount += 1
            } else if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                signalCount += 1
            } else if trimmed.hasPrefix("```") {
                signalCount += 1
            }
        }

        return signalCount >= 2
    }
}

public enum ReviewFinalPassContract {
    public static let requiredPrefix = "Final Pass Required:"

    public static var instructions: String {
        """
        Review Exit Check
        The review deliverable must include exactly one final-pass decision line:

        \(requiredPrefix) Yes
        or
        \(requiredPrefix) No

        Use "Yes" when the ticket needs final adjustments before it can move to Done. Use "No" only when the final deliverable is ready to move to Done. If the answer is "Yes", include a "Final Adjustments" section with the concrete remaining work.
        """
    }

    public static func requiresFinalPass(in markdown: String) -> Bool? {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.range(
                of: requiredPrefix,
                options: [.anchored, .caseInsensitive]
            ) != nil else {
                continue
            }

            let decision = trimmed
                .dropFirst(requiredPrefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let normalizedDecision = decision
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

            if normalizedDecision == "yes"
                || normalizedDecision == "y"
                || normalizedDecision == "true"
                || decision.hasPrefix("yes ") {
                return true
            }
            if normalizedDecision == "no"
                || normalizedDecision == "n"
                || normalizedDecision == "false"
                || normalizedDecision == "not required"
                || normalizedDecision == "none"
                || decision.hasPrefix("no ") {
                return false
            }
        }

        return nil
    }
}

public enum PhasePromptTemplateLoader {
    public static func bundledDefaults() -> PhasePromptSelection {
        PhasePromptSelection(
            rawResearch: defaultResearch,
            rawPlan: defaultPlan,
            rawImplement: defaultImplement,
            rawReview: defaultReview
        )
    }

    private static let defaultResearch = """
    # Research Phase

    Your job is to produce a high-signal research corpus that gives the next planning agent the best possible starting point.

    Produce a markdown deliverable that:
    - Summarizes the ticket objective in concrete engineering terms.
    - Identifies the most relevant code paths, types, views, persistence models, workflows, and provider boundaries.
    - Captures constraints, architectural rules, and repo conventions that materially affect the solution.
    - Distinguishes confirmed facts from assumptions or open questions.
    - Recommends the most likely implementation direction for the plan phase.

    Prefer repository-grounded evidence over speculation. Keep the result concise but information-dense.
    Do not run builds, tests, formatters, linters, package resolution, or other verification commands unless the user explicitly asks for them.

    Follow the shared output contract exactly.
    """

    private static let defaultPlan = """
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
    """

    private static let defaultImplement = """
    # Implement Phase

    Your job is to execute the plan and leave behind a precise implementation handoff for review.

    Produce a markdown deliverable that:
    - Summarizes the actual code and behavior changes made.
    - Names the most important files, modules, or workflows touched.
    - Explains any deviations from the plan and why they were necessary.
    - Lists tests, builds, or verification steps that were run and their outcomes.
    - Calls out remaining limitations, follow-ups, or risks the reviewer should inspect.

    Be concrete and factual. Reflect the implemented state, not the intended state.
    Run only the focused builds, tests, or checks needed to validate the implementation, and prefer package or module-level checks over full app builds when they cover the change.

    Follow the shared output contract exactly.
    """

    private static let defaultReview = """
    # Review Phase

    Your job is to evaluate the implementation rigorously and produce a reviewer-grade assessment.

    Produce a markdown deliverable that:
    - Lists findings first, ordered by severity, with clear reasoning.
    - Notes the validation performed and what was inspected.
    - Identifies residual risks, regressions, or test gaps.
    - Includes the required final-pass decision line.
    - States whether the ticket is ready to consider complete or needs rework.

    Prefer concrete evidence and actionable conclusions over general commentary.
    Start with code and diff inspection. Run focused builds, tests, or checks only when they materially reduce review risk, and avoid repeating successful verification already captured by Implement unless justified.

    Follow the shared output contract exactly.
    """
}
