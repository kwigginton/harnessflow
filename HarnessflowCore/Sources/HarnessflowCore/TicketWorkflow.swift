import Foundation

public enum TicketWorkflowError: LocalizedError, Equatable, Sendable {
    case invalidTransition(from: TicketPhase, to: TicketPhase)
    case currentPhaseIncomplete(TicketPhase)

    public var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            "Cannot move a ticket from \(from.title) to \(to.title)."
        case let .currentPhaseIncomplete(phase):
            "\(phase.title) must complete successfully before moving forward."
        }
    }
}

public struct TicketWorkflow: Sendable {
    public init() {}

    public func validateMove(for ticket: Ticket, to destination: TicketPhase) throws {
        let current = ticket.column
        if current == destination {
            return
        }

        let delta = destination.rawValue - current.rawValue
        guard abs(delta) == 1 else {
            throw TicketWorkflowError.invalidTransition(from: current, to: destination)
        }

        if delta > 0 {
            let state = ticket.phaseState(for: current)
            guard state.executionState == .completed else {
                throw TicketWorkflowError.currentPhaseIncomplete(current)
            }
        }
    }

    public func move(_ ticket: Ticket, to destination: TicketPhase, movedAt: Date = .now) throws -> Ticket {
        try validateMove(for: ticket, to: destination)

        var updated = ticket
        let current = ticket.column
        updated.column = destination
        updated.updatedAt = movedAt

        if destination.rawValue < current.rawValue {
            for phase in TicketPhase.allCases where phase.rawValue > destination.rawValue {
                var state = updated.phaseState(for: phase)
                state.resetForRework()
                updated.updatePhaseState(state)
            }
        }

        return updated
    }
}

