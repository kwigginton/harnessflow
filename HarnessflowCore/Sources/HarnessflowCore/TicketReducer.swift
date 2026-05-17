import Foundation

public enum TicketReducerError: LocalizedError, Equatable, Sendable {
    case invalidTransition(from: TicketPhase, to: TicketPhase)
    case currentPhaseIncomplete(TicketPhase)
    case reviewFinalPassRequired
    case reviewFinalPassUndetermined
    case runningPhaseCannotComplete
    case noPendingQuestions(TicketPhase)

    public var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            "Cannot move a ticket from \(from.title) to \(to.title)."
        case let .currentPhaseIncomplete(phase):
            "\(phase.title) must complete successfully before moving forward."
        case .reviewFinalPassRequired:
            "Review requested final adjustments. Keep the ticket in Review until the final pass is complete."
        case .reviewFinalPassUndetermined:
            "Review must include a final-pass decision before the ticket can move to Done."
        case .runningPhaseCannotComplete:
            "Stop running phases before marking this ticket completed."
        case let .noPendingQuestions(phase):
            "\(phase.title) is not waiting for user input."
        }
    }
}

public enum TicketEvent: Equatable, Sendable {
    case moveRequested(destination: TicketPhase)
    case shiftForwardRequested
    case completeRequested
    case runRequested
    case continuationRequested(answers: [AgentAnswer])
    case agentResultReceived(
        request: AgentRunRequest,
        result: AgentRunResult,
        providerKind: AgentProviderKind,
        authMethod: CodexAuthMethod,
        authMethodDescription: String,
        didFallbackFromSubscription: Bool
    )
    case agentFailureReceived(
        request: AgentRunRequest,
        message: String,
        providerKind: AgentProviderKind,
        authMethod: CodexAuthMethod,
        authMethodDescription: String,
        didFallbackFromSubscription: Bool
    )
    case processAttached(
        request: AgentRunRequest,
        processIdentifier: Int32,
        executablePath: String
    )
    case phaseRecovered(phase: TicketPhase, message: String)
}

public enum TicketCommand: Equatable, Sendable {
    case persistTicket(Ticket)
    case runAgent(AgentRunRequest)
    case beginLiveOutput(request: AgentRunRequest, startedAt: Date)
    case completeLiveOutput(request: AgentRunRequest, result: AgentRunResult)
    case failLiveOutput(request: AgentRunRequest, message: String)
    case clearLiveOutput(ticketID: UUID, phase: TicketPhase)
    case presentError(String)
}

public struct TicketReducerContext: Equatable, Sendable {
    public var settings: AppSettings
    public var workingDirectoryOverride: String?
    public var now: Date

    public init(
        settings: AppSettings,
        workingDirectoryOverride: String? = nil,
        now: Date = .now
    ) {
        self.settings = settings
        self.workingDirectoryOverride = workingDirectoryOverride
        self.now = now
    }
}

public struct TicketReducerResult: Equatable, Sendable {
    public var ticket: Ticket
    public var commands: [TicketCommand]

    public init(ticket: Ticket, commands: [TicketCommand] = []) {
        self.ticket = ticket
        self.commands = commands
    }
}

public struct TicketReducer: Sendable {
    private let requestBuilder: TicketRunRequestBuilder

    public init(requestBuilder: TicketRunRequestBuilder = TicketRunRequestBuilder()) {
        self.requestBuilder = requestBuilder
    }

    public func reduce(
        ticket: Ticket,
        event: TicketEvent,
        context: TicketReducerContext
    ) -> TicketReducerResult {
        do {
            switch event {
            case let .moveRequested(destination):
                return try move(ticket, to: destination, movedAt: context.now)
            case .shiftForwardRequested:
                return try shiftCompletedTicket(ticket, movedAt: context.now)
            case .completeRequested:
                return try complete(ticket, completedAt: context.now)
            case .runRequested:
                return try startRun(ticket, context: context, answers: nil)
            case let .continuationRequested(answers):
                return try startRun(ticket, context: context, answers: answers)
            case let .agentResultReceived(request, result, providerKind, authMethod, authMethodDescription, didFallbackFromSubscription):
                return try applyResult(
                    ticket: ticket,
                    request: request,
                    result: result,
                    providerKind: providerKind,
                    authMethod: authMethod,
                    authMethodDescription: authMethodDescription,
                    didFallbackFromSubscription: didFallbackFromSubscription
                )
            case let .agentFailureReceived(request, message, providerKind, authMethod, authMethodDescription, didFallbackFromSubscription):
                return applyFailure(
                    ticket: ticket,
                    request: request,
                    message: message,
                    providerKind: providerKind,
                    authMethod: authMethod,
                    authMethodDescription: authMethodDescription,
                    didFallbackFromSubscription: didFallbackFromSubscription,
                    failedAt: context.now
                )
            case let .processAttached(request, processIdentifier, executablePath):
                return attachProcess(
                    ticket: ticket,
                    request: request,
                    processIdentifier: processIdentifier,
                    executablePath: executablePath,
                    attachedAt: context.now
                )
            case let .phaseRecovered(phase, message):
                return recoverPhase(ticket: ticket, phase: phase, message: message, recoveredAt: context.now)
            }
        } catch {
            return TicketReducerResult(ticket: ticket, commands: [.presentError(error.localizedDescription)])
        }
    }

    private func startRun(
        _ ticket: Ticket,
        context: TicketReducerContext,
        answers: [AgentAnswer]?
    ) throws -> TicketReducerResult {
        let request: AgentRunRequest
        if let answers {
            let phaseState = ticket.phaseState(for: ticket.column)
            guard phaseState.pendingQuestions != nil else {
                throw TicketReducerError.noPendingQuestions(ticket.column)
            }
            var answeredTicket = ticket
            var answeredState = phaseState
            answeredState.pendingAnswers = answers
            answeredTicket.updatePhaseState(answeredState)
            request = try requestBuilder.makeContinuationRequest(
                for: answeredTicket,
                settings: context.settings,
                answers: answers,
                workingDirectoryOverride: context.workingDirectoryOverride
            )
            return markRunning(answeredTicket, request: request, startedAt: context.now)
        }

        request = try requestBuilder.makeRequest(
            for: ticket,
            settings: context.settings,
            workingDirectoryOverride: context.workingDirectoryOverride
        )
        return markRunning(ticket, request: request, startedAt: context.now)
    }

    private func markRunning(
        _ ticket: Ticket,
        request: AgentRunRequest,
        startedAt: Date
    ) -> TicketReducerResult {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        phaseState.prompt = request.promptAddendum
        phaseState.executionState = .running
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = startedAt
        phaseState.lastCompletedAt = nil
        phaseState.capturedOutput = ""
        phaseState.capturedError = ""
        phaseState.ownedProcess = nil
        phaseState.pendingQuestions = nil
        phaseState.pendingAnswers = []
        updated.updatePhaseState(phaseState)
        updated.completedAt = nil
        updated.updatedAt = startedAt

        return TicketReducerResult(
            ticket: updated,
            commands: [
                .persistTicket(updated),
                .beginLiveOutput(request: request, startedAt: startedAt),
                .runAgent(request),
            ]
        )
    }

    private func move(_ ticket: Ticket, to destination: TicketPhase, movedAt: Date) throws -> TicketReducerResult {
        try validateMove(for: ticket, to: destination)

        var updated = ticket
        let current = ticket.column
        updated.column = destination
        updated.completedAt = nil
        updated.updatedAt = movedAt

        if destination.rawValue < current.rawValue {
            for phase in TicketPhase.allCases where phase.rawValue > destination.rawValue {
                var state = updated.phaseState(for: phase)
                state.resetForRework()
                updated.updatePhaseState(state)
            }
        }

        return TicketReducerResult(ticket: updated, commands: [.persistTicket(updated)])
    }

    private func validateMove(for ticket: Ticket, to destination: TicketPhase) throws {
        let current = ticket.column
        if current == destination {
            return
        }

        let delta = destination.rawValue - current.rawValue
        guard abs(delta) == 1 else {
            throw TicketReducerError.invalidTransition(from: current, to: destination)
        }

        if delta > 0 {
            let state = ticket.phaseState(for: current)
            guard state.executionState == .completed else {
                throw TicketReducerError.currentPhaseIncomplete(current)
            }
        }
    }

    private func shiftCompletedTicket(_ ticket: Ticket, movedAt: Date) throws -> TicketReducerResult {
        let state = ticket.phaseState(for: ticket.column)
        guard state.executionState == .completed else {
            throw TicketReducerError.currentPhaseIncomplete(ticket.column)
        }

        if let nextPhase = ticket.column.next {
            return try move(ticket, to: nextPhase, movedAt: movedAt)
        }

        return try completeAfterReview(ticket, completedAt: movedAt)
    }

    private func completeAfterReview(_ ticket: Ticket, completedAt: Date) throws -> TicketReducerResult {
        guard ticket.column == .review else {
            throw TicketReducerError.invalidTransition(from: ticket.column, to: .review)
        }

        let state = ticket.phaseState(for: .review)
        guard state.executionState == .completed else {
            throw TicketReducerError.currentPhaseIncomplete(.review)
        }

        switch ReviewFinalPassContract.requiresFinalPass(in: state.deliverableMarkdown) {
        case .some(true):
            throw TicketReducerError.reviewFinalPassRequired
        case .some(false):
            var completedTicket = ticket
            completedTicket.completedAt = completedAt
            completedTicket.updatedAt = completedAt
            return TicketReducerResult(ticket: completedTicket, commands: [.persistTicket(completedTicket)])
        case .none:
            throw TicketReducerError.reviewFinalPassUndetermined
        }
    }

    private func complete(_ ticket: Ticket, completedAt: Date) throws -> TicketReducerResult {
        guard ticket.phaseStates.contains(where: { $0.executionState == .running }) == false else {
            throw TicketReducerError.runningPhaseCannotComplete
        }

        var completedTicket = ticket
        completedTicket.completedAt = completedAt
        completedTicket.updatedAt = completedAt
        return TicketReducerResult(ticket: completedTicket, commands: [.persistTicket(completedTicket)])
    }

    private func applyResult(
        ticket: Ticket,
        request: AgentRunRequest,
        result: AgentRunResult,
        providerKind: AgentProviderKind,
        authMethod: CodexAuthMethod,
        authMethodDescription: String,
        didFallbackFromSubscription: Bool
    ) throws -> TicketReducerResult {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        let questionSet = result.success ? AgentQuestionContract.extractQuestionSet(from: result.output) : nil
        let deliverable = result.success ? PhaseDeliverableContract.extractDeliverable(from: result.output) : nil
        let deliverableError = result.success && deliverable == nil && questionSet == nil
            ? "Agent output did not include a wrapped \(request.phase.title.lowercased()) deliverable using the required Harnessflow markers."
            : nil
        let finalSuccess = result.success && deliverable != nil
        let isAwaitingInput = result.success && questionSet != nil && deliverable == nil
        let finalErrorOutput = combinedErrorOutput(result.errorOutput, additionalMessage: deliverableError)
        let runID = UUID()

        phaseState.prompt = request.promptAddendum
        phaseState.executionState = finalSuccess ? .completed : (isAwaitingInput ? .awaitingInput : .failed)
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
            phaseState.pendingQuestions = nil
            phaseState.pendingAnswers = []
        } else if let questionSet {
            phaseState.pendingQuestions = questionSet
            phaseState.pendingAnswers = []
        }
        phaseState.runs.append(
            PhaseRun(
                id: runID,
                phase: request.phase,
                providerKind: providerKind,
                model: request.model,
                authMethod: authMethod,
                authMethodDescription: authMethodDescription,
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

        var commands: [TicketCommand] = [.completeLiveOutput(request: request, result: result)]
        if finalSuccess, updated.autoShiftOnSuccess, shouldAutoShiftAfterSuccess(updated, phase: request.phase) {
            let shifted = try shiftCompletedTicket(updated, movedAt: result.completedAt)
            updated = shifted.ticket
            commands.append(contentsOf: shifted.commands)
        } else {
            commands.append(.persistTicket(updated))
        }
        return TicketReducerResult(ticket: updated, commands: commands)
    }

    private func shouldAutoShiftAfterSuccess(_ ticket: Ticket, phase: TicketPhase) -> Bool {
        guard phase == .review else {
            return true
        }

        return ReviewFinalPassContract.requiresFinalPass(in: ticket.phaseState(for: .review).deliverableMarkdown) == false
    }

    private func applyFailure(
        ticket: Ticket,
        request: AgentRunRequest,
        message: String,
        providerKind: AgentProviderKind,
        authMethod: CodexAuthMethod,
        authMethodDescription: String,
        didFallbackFromSubscription: Bool,
        failedAt: Date
    ) -> TicketReducerResult {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        let startedAt = phaseState.lastStartedAt ?? failedAt
        phaseState.prompt = request.promptAddendum
        phaseState.executionState = .failed
        phaseState.lastModel = request.model
        phaseState.lastStartedAt = startedAt
        phaseState.lastCompletedAt = failedAt
        phaseState.capturedOutput = ""
        phaseState.capturedError = message
        phaseState.ownedProcess = nil
        phaseState.runs.append(
            PhaseRun(
                phase: request.phase,
                providerKind: providerKind,
                model: request.model,
                authMethod: authMethod,
                authMethodDescription: authMethodDescription,
                didFallbackFromSubscription: didFallbackFromSubscription,
                prompt: request.prompt,
                output: "",
                errorOutput: message,
                startedAt: startedAt,
                completedAt: failedAt,
                success: false
            )
        )
        updated.updatePhaseState(phaseState)
        updated.updatedAt = failedAt

        return TicketReducerResult(
            ticket: updated,
            commands: [
                .persistTicket(updated),
                .failLiveOutput(request: request, message: message),
            ]
        )
    }

    private func attachProcess(
        ticket: Ticket,
        request: AgentRunRequest,
        processIdentifier: Int32,
        executablePath: String,
        attachedAt: Date
    ) -> TicketReducerResult {
        var updated = ticket
        var phaseState = updated.phaseState(for: request.phase)
        phaseState.ownedProcess = OwnedProcessReference(
            processIdentifier: processIdentifier,
            executablePath: executablePath,
            launchedAt: phaseState.lastStartedAt ?? attachedAt
        )
        updated.updatePhaseState(phaseState)
        updated.updatedAt = attachedAt
        return TicketReducerResult(ticket: updated, commands: [.persistTicket(updated)])
    }

    private func recoverPhase(
        ticket: Ticket,
        phase: TicketPhase,
        message: String,
        recoveredAt: Date
    ) -> TicketReducerResult {
        var updated = ticket
        var phaseState = updated.phaseState(for: phase)
        let existing = phaseState.capturedError.trimmingCharacters(in: .whitespacesAndNewlines)
        let addition = message.trimmingCharacters(in: .whitespacesAndNewlines)
        phaseState.executionState = .failed
        phaseState.lastCompletedAt = recoveredAt
        phaseState.ownedProcess = nil
        phaseState.capturedError = [existing, addition]
            .filter { $0.isEmpty == false }
            .joined(separator: existing.isEmpty ? "" : "\n\n")
        updated.updatePhaseState(phaseState)
        updated.updatedAt = recoveredAt

        return TicketReducerResult(
            ticket: updated,
            commands: [
                .persistTicket(updated),
                .clearLiveOutput(ticketID: ticket.id, phase: phase),
            ]
        )
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
