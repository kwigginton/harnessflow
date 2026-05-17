import Foundation

public enum TicketRunRequestError: LocalizedError, Equatable, Sendable {
    case missingPrompt(TicketPhase)
    case missingWorkingDirectory

    public var errorDescription: String? {
        switch self {
        case let .missingPrompt(phase):
            "Add a base prompt for \(phase.title) in Settings before running the agent."
        case .missingWorkingDirectory:
            "Configure a working directory in Settings before running the agent."
        }
    }
}

public struct TicketRunRequestBuilder: Sendable {
    public init() {}

    public func makeRequest(
        for ticket: Ticket,
        settings: AppSettings,
        workingDirectoryOverride: String? = nil
    ) throws -> AgentRunRequest {
        let phase = ticket.column
        let phaseState = ticket.phaseState(for: phase)
        let basePrompt = settings.phasePrompts.prompt(for: phase)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard basePrompt.isEmpty == false else {
            throw TicketRunRequestError.missingPrompt(phase)
        }

        let workingDirectory = (workingDirectoryOverride ?? settings.defaultWorkingDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard workingDirectory.isEmpty == false else {
            throw TicketRunRequestError.missingWorkingDirectory
        }

        return AgentRunRequest(
            ticketID: ticket.id,
            phase: phase,
            prompt: composePrompt(
                for: ticket,
                phase: phase,
                basePrompt: basePrompt,
                promptAddendum: phaseState.prompt,
                continuation: nil
            ),
            promptAddendum: phaseState.prompt,
            model: settings.phaseModels.model(for: phase),
            workingDirectory: workingDirectory
        )
    }

    public func makeContinuationRequest(
        for ticket: Ticket,
        settings: AppSettings,
        answers: [AgentAnswer],
        workingDirectoryOverride: String? = nil
    ) throws -> AgentRunRequest {
        let phase = ticket.column
        let phaseState = ticket.phaseState(for: phase)
        let basePrompt = settings.phasePrompts.prompt(for: phase)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard basePrompt.isEmpty == false else {
            throw TicketRunRequestError.missingPrompt(phase)
        }

        let workingDirectory = (workingDirectoryOverride ?? settings.defaultWorkingDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard workingDirectory.isEmpty == false else {
            throw TicketRunRequestError.missingWorkingDirectory
        }

        return AgentRunRequest(
            ticketID: ticket.id,
            phase: phase,
            prompt: composePrompt(
                for: ticket,
                phase: phase,
                basePrompt: basePrompt,
                promptAddendum: phaseState.prompt,
                continuation: continuationContext(for: phaseState, answers: answers)
            ),
            promptAddendum: phaseState.prompt,
            model: settings.phaseModels.model(for: phase),
            workingDirectory: workingDirectory
        )
    }

    private func composePrompt(
        for ticket: Ticket,
        phase: TicketPhase,
        basePrompt: String,
        promptAddendum: String,
        continuation: String?
    ) -> String {
        var sections = [basePrompt]

        sections.append(
            """
            Ticket Context
            Title: \(ticket.title)

            Details
            \(ticket.detailsText.isEmpty ? "(none provided)" : ticket.detailsText)
            """
        )

        let trimmedAddendum = promptAddendum.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAddendum.isEmpty == false {
            sections.append(
                """
                Phase-Specific Addendum
                \(trimmedAddendum)
                """
            )
        }

        let priorDeliverables = TicketPhase.allCases
            .filter { $0.rawValue < phase.rawValue }
            .compactMap { priorPhase -> String? in
                let state = ticket.phaseState(for: priorPhase)
                guard state.executionState == .completed, state.deliverableMarkdown.isEmpty == false else {
                    return nil
                }

                return """
                ## \(priorPhase.title)
                \(state.deliverableMarkdown)
                """
            }

        if priorDeliverables.isEmpty == false {
            sections.append(
                """
                Prior Completed Phase Deliverables
                \(priorDeliverables.joined(separator: "\n\n"))
                """
            )
        }

        if let finalAdjustmentContext = finalAdjustmentContext(for: ticket, phase: phase) {
            sections.append(finalAdjustmentContext)
        }

        if let continuation {
            sections.append(continuation)
        }

        sections.append(executionPolicy(for: phase))
        sections.append(AgentQuestionContract.instructions)
        if phase == .review {
            sections.append(ReviewFinalPassContract.instructions)
        }
        sections.append(PhaseDeliverableContract.instructions)
        return sections.joined(separator: "\n\n")
    }

    private func executionPolicy(for phase: TicketPhase) -> String {
        switch phase {
        case .research:
            return """
            Phase Execution Policy
            Do not run builds, tests, formatters, linters, package resolution, or other verification commands during Research unless the user explicitly asks for them. Prefer fast read-only inspection with targeted file searches and source reads.
            """
        case .plan:
            return """
            Phase Execution Policy
            Do not run builds, tests, formatters, linters, package resolution, or other verification commands during Plan unless the user explicitly asks for them. Specify the verification strategy for Implement or Review instead of executing it now.
            """
        case .implement:
            return """
            Phase Execution Policy
            Run only the focused builds, tests, or checks needed to validate the implementation. Prefer package or module-level checks over full app builds when they cover the change, and record exactly what was run.
            """
        case .review:
            return """
            Phase Execution Policy
            Start with code and diff inspection. Run focused builds, tests, or checks only when they materially reduce review risk, and avoid repeating successful verification already captured by Implement unless the change or risk justifies it.
            """
        }
    }

    private func finalAdjustmentContext(for ticket: Ticket, phase: TicketPhase) -> String? {
        guard phase == .review else {
            return nil
        }

        let reviewState = ticket.phaseState(for: .review)
        guard reviewState.needsFinalAdjustments else {
            return nil
        }

        return """
        Final Adjustment Pass
        The previous review deliverable requested final adjustments. This run is not a fresh review pass.

        Implement only the requested final adjustments in the current working directory, then inspect the final deliverable before deciding whether the ticket can move to Done. Keep the work in the Review state and preserve the existing phase history.

        Previous Review Deliverable
        \(reviewState.deliverableMarkdown)
        """
    }

    private func continuationContext(for phaseState: TicketPhaseState, answers: [AgentAnswer]) -> String {
        var sections = [
            """
            Continuation Context
            Continue the same \(phaseState.phase.title) phase. The previous run stopped to ask the user for input. Use the answers below, continue from the prior work, and return the normal Harnessflow deliverable when complete.
            """
        ]

        if phaseState.capturedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append(
                """
                Previous Agent Output
                \(phaseState.capturedOutput)
                """
            )
        }

        if let questionSet = phaseState.pendingQuestions {
            let answerLines = answers.map { answer in
                let question = questionSet.questions.first(where: { $0.id == answer.questionID })
                let choiceLabel = question?.choices.first(where: { $0.id == answer.choiceID })?.label
                let selected = choiceLabel ?? answer.choiceID ?? "(no choice)"
                let freeform = answer.freeformText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if freeform.isEmpty {
                    return "- \(answer.questionID): \(selected)"
                }
                return "- \(answer.questionID): \(selected)\n  Answer: \(freeform)"
            }

            sections.append(
                """
                User Answers
                \(answerLines.isEmpty ? "(none provided)" : answerLines.joined(separator: "\n"))
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }
}
