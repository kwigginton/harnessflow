import Foundation

public enum TicketExecutionError: LocalizedError, Equatable, Sendable {
    case missingPrompt(TicketPhase)
    case missingWorkingDirectory

    public var errorDescription: String? {
        switch self {
        case let .missingPrompt(phase):
            "Add a prompt for \(phase.title) before running the agent."
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
        let prompt = phaseState.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw TicketExecutionError.missingPrompt(phase)
        }

        let workingDirectory = (workingDirectoryOverride ?? settings.defaultWorkingDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingDirectory.isEmpty else {
            throw TicketExecutionError.missingWorkingDirectory
        }

        return AgentRunRequest(
            ticketID: ticket.id,
            phase: phase,
            prompt: prompt,
            model: settings.phaseModels.model(for: phase),
            workingDirectory: workingDirectory
        )
    }

    public func markRunning(ticket: Ticket, request: AgentRunRequest, at: Date = .now) -> Ticket {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        phaseState.prompt = request.prompt
        phaseState.executionState = .running
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = at
        phaseState.lastCompletedAt = nil
        phaseState.capturedOutput = ""
        phaseState.capturedError = ""
        updated.updatePhaseState(phaseState)
        updated.updatedAt = at
        return updated
    }

    public func applyResult(ticket: Ticket, request: AgentRunRequest, result: AgentRunResult) -> Ticket {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        phaseState.prompt = request.prompt
        phaseState.executionState = result.success ? .completed : .failed
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = result.startedAt
        phaseState.lastCompletedAt = result.completedAt
        phaseState.capturedOutput = result.output
        phaseState.capturedError = result.errorOutput
        phaseState.runs.append(
            PhaseRun(
                phase: request.phase,
                model: request.model,
                prompt: request.prompt,
                output: result.output,
                errorOutput: result.errorOutput,
                startedAt: result.startedAt,
                completedAt: result.completedAt,
                success: result.success
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
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        let startedAt = phaseState.lastStartedAt ?? failedAt
        phaseState.prompt = request.prompt
        phaseState.executionState = .failed
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = startedAt
        phaseState.lastCompletedAt = failedAt
        phaseState.capturedOutput = ""
        phaseState.capturedError = errorMessage
        phaseState.runs.append(
            PhaseRun(
                phase: request.phase,
                model: request.model,
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
}

