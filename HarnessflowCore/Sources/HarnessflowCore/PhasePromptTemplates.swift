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
            rawResearch: loadTemplate(named: "Research") ?? fallbackResearch,
            rawPlan: loadTemplate(named: "Plan") ?? fallbackPlan,
            rawImplement: loadTemplate(named: "Implement") ?? fallbackImplement,
            rawReview: loadTemplate(named: "Review") ?? fallbackReview
        )
    }

    private static func loadTemplate(named phaseName: String) -> String? {
        guard let url = Bundle.module.url(
            forResource: phaseName,
            withExtension: "md",
            subdirectory: "PhasePrompts"
        ) else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static let fallbackResearch = """
    # Research Phase

    Investigate the ticket and assemble a high-signal corpus for the planner.

    Produce a concise markdown deliverable with:
    - Problem summary
    - Relevant code paths, files, and systems
    - Constraints, risks, and unknowns
    - Evidence and observations from the repository
    - Recommended direction for the plan phase

    Do not run builds, tests, formatters, linters, package resolution, or other verification commands unless the user explicitly asks for them.

    Follow the shared output contract exactly.
    """

    private static let fallbackPlan = """
    # Plan Phase

    Turn the ticket and research corpus into a decision-complete implementation plan.

    Produce a concise markdown deliverable with:
    - Goal and success criteria
    - Implementation approach
    - Public interface or data model changes
    - Test and verification scenarios
    - Assumptions and unresolved risks

    Do not run builds, tests, formatters, linters, package resolution, or other verification commands unless the user explicitly asks for them.

    Follow the shared output contract exactly.
    """

    private static let fallbackImplement = """
    # Implement Phase

    Execute the approved plan and summarize the actual changes for reviewers.

    Produce a concise markdown deliverable with:
    - What changed
    - Important files or subsystems touched
    - Behavior changes and user-visible outcomes
    - Tests or checks run
    - Known gaps or follow-up items

    Run only the focused builds, tests, or checks needed to validate the implementation, and prefer package or module-level checks over full app builds when they cover the change.

    Follow the shared output contract exactly.
    """

    private static let fallbackReview = """
    # Review Phase

    Validate the implementation against the plan and identify regressions or residual risk.

    Produce a concise markdown deliverable with:
    - Findings, ordered by severity
    - Validation performed
    - Residual risks or test gaps
    - Final pass decision using the required review exit check
    - Final recommendation

    Start with code and diff inspection. Run focused builds, tests, or checks only when they materially reduce review risk, and avoid repeating successful verification already captured by Implement unless justified.

    Follow the shared output contract exactly.
    """
}
