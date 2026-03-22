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

    Follow the shared output contract exactly.
    """

    private static let fallbackReview = """
    # Review Phase

    Validate the implementation against the plan and identify regressions or residual risk.

    Produce a concise markdown deliverable with:
    - Findings, ordered by severity
    - Validation performed
    - Residual risks or test gaps
    - Final recommendation

    Follow the shared output contract exactly.
    """
}
