import Foundation

public enum TicketExecutionError: LocalizedError, Equatable, Sendable {
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

public struct TicketExecutionService: Sendable {
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
        guard !basePrompt.isEmpty else {
            throw TicketExecutionError.missingPrompt(phase)
        }
        let promptAddendum = phaseState.prompt

        let workingDirectory = (workingDirectoryOverride ?? settings.defaultWorkingDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingDirectory.isEmpty else {
            throw TicketExecutionError.missingWorkingDirectory
        }

        return AgentRunRequest(
            ticketID: ticket.id,
            phase: phase,
            prompt: composePrompt(
                for: ticket,
                phase: phase,
                basePrompt: basePrompt,
                promptAddendum: promptAddendum
            ),
            promptAddendum: promptAddendum,
            model: settings.phaseModels.model(for: phase),
            workingDirectory: workingDirectory
        )
    }

    public func markRunning(ticket: Ticket, request: AgentRunRequest, at: Date = .now) -> Ticket {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        phaseState.prompt = request.promptAddendum
        phaseState.executionState = .running
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = at
        phaseState.lastCompletedAt = nil
        phaseState.capturedOutput = ""
        phaseState.capturedError = ""
        phaseState.ownedProcess = nil
        updated.updatePhaseState(phaseState)
        updated.updatedAt = at
        return updated
    }

    public func applyResult(ticket: Ticket, request: AgentRunRequest, result: AgentRunResult) -> Ticket {
        applyResult(
            ticket: ticket,
            request: request,
            result: result,
            authMethod: .unknown,
            didFallbackFromSubscription: false
        )
    }

    public func applyResult(
        ticket: Ticket,
        request: AgentRunRequest,
        result: AgentRunResult,
        authMethod: CodexAuthMethod,
        didFallbackFromSubscription: Bool
    ) -> Ticket {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        let deliverable = result.success ? PhaseDeliverableContract.extractDeliverable(from: result.output) : nil
        let deliverableError = result.success && deliverable == nil
            ? "Agent output did not include a wrapped \(request.phase.title.lowercased()) deliverable using the required Harnessflow markers."
            : nil
        let finalSuccess = result.success && deliverable != nil
        let finalErrorOutput = combinedErrorOutput(
            result.errorOutput,
            additionalMessage: deliverableError
        )
        let runID = UUID()

        phaseState.prompt = request.promptAddendum
        phaseState.executionState = finalSuccess ? .completed : .failed
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = result.startedAt
        phaseState.lastCompletedAt = result.completedAt
        phaseState.capturedOutput = result.output
        phaseState.capturedError = finalErrorOutput
        phaseState.ownedProcess = nil
        if let deliverable {
            phaseState.deliverableMarkdown = deliverable
            phaseState.deliverableGeneratedAt = result.completedAt
            phaseState.deliverableSourceRunID = runID
        }
        phaseState.runs.append(
            PhaseRun(
                id: runID,
                phase: request.phase,
                model: request.model,
                authMethod: authMethod,
                didFallbackFromSubscription: didFallbackFromSubscription,
                prompt: request.prompt,
                output: result.output,
                errorOutput: finalErrorOutput,
                startedAt: result.startedAt,
                completedAt: result.completedAt,
                success: finalSuccess
            )
        )
        updated.updatePhaseState(phaseState)
        updated.updatedAt = result.completedAt
        return updated
    }

    public func applyFailure(
        ticket: Ticket,
        request: AgentRunRequest,
        errorMessage: String,
        failedAt: Date = .now
    ) -> Ticket {
        applyFailure(
            ticket: ticket,
            request: request,
            errorMessage: errorMessage,
            authMethod: .unknown,
            didFallbackFromSubscription: false,
            failedAt: failedAt
        )
    }

    public func applyFailure(
        ticket: Ticket,
        request: AgentRunRequest,
        errorMessage: String,
        authMethod: CodexAuthMethod,
        didFallbackFromSubscription: Bool,
        failedAt: Date = .now
    ) -> Ticket {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        let startedAt = phaseState.lastStartedAt ?? failedAt
        phaseState.prompt = request.promptAddendum
        phaseState.executionState = .failed
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = startedAt
        phaseState.lastCompletedAt = failedAt
        phaseState.capturedOutput = ""
        phaseState.capturedError = errorMessage
        phaseState.ownedProcess = nil
        phaseState.runs.append(
            PhaseRun(
                phase: request.phase,
                model: request.model,
                authMethod: authMethod,
                didFallbackFromSubscription: didFallbackFromSubscription,
                prompt: request.prompt,
                output: "",
                errorOutput: errorMessage,
                startedAt: startedAt,
                completedAt: failedAt,
                success: false
            )
        )
        updated.updatePhaseState(phaseState)
        updated.updatedAt = failedAt
        return updated
    }

    private func composePrompt(
        for ticket: Ticket,
        phase: TicketPhase,
        basePrompt: String,
        promptAddendum: String
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

        sections.append(PhaseDeliverableContract.instructions)
        return sections.joined(separator: "\n\n")
    }

    private func combinedErrorOutput(_ errorOutput: String, additionalMessage: String?) -> String {
        let trimmedErrorOutput = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAdditional = additionalMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch (trimmedErrorOutput.isEmpty, trimmedAdditional.isEmpty) {
        case (false, false):
            return "\(trimmedErrorOutput)\n\n\(trimmedAdditional)"
        case (false, true):
            return trimmedErrorOutput
        case (true, false):
            return trimmedAdditional
        case (true, true):
            return ""
        }
    }
}
