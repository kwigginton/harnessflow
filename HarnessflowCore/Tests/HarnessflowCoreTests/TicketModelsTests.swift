import Testing
@testable import HarnessflowCore

struct TicketModelsTests {
    @Test
    func ticketCanStartInLaterPhaseAndKeepsNormalizedStates() {
        let implementState = TicketPhaseState(phase: .implement, prompt: "Ship it")
        let ticket = Ticket(
            title: "Direct to Implement",
            column: .implement,
            phaseStates: [implementState]
        )

        #expect(ticket.column == .implement)
        #expect(ticket.phaseStates.count == TicketPhase.allCases.count)
        #expect(ticket.phaseStates.map(\.phase) == TicketPhase.allCases)
        #expect(ticket.phaseState(for: .implement).prompt == "Ship it")
        #expect(ticket.phaseState(for: .research).executionState == .idle)
        #expect(ticket.phaseState(for: .research).deliverableMarkdown.isEmpty)
    }

    @Test
    func resetForReworkClearsOwnedProcessReference() {
        var state = TicketPhaseState(phase: .plan)
        state.ownedProcess = OwnedProcessReference(
            processIdentifier: 456,
            executablePath: "/opt/homebrew/bin/codex",
            launchedAt: .now
        )

        state.resetForRework()

        #expect(state.ownedProcess == nil)
    }
}
