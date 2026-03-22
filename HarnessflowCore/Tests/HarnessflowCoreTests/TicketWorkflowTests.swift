import Foundation
import Testing
@testable import HarnessflowCore

struct TicketWorkflowTests {
    @Test
    func forwardMoveRequiresCompletedCurrentPhase() throws {
        let ticket = Ticket(title: "Blocked")
        let workflow = TicketWorkflow()

        #expect(throws: TicketWorkflowError.currentPhaseIncomplete(.research)) {
            _ = try workflow.move(ticket, to: .plan)
        }
    }

    @Test
    func adjacentForwardMoveSucceedsAfterCompletion() throws {
        var ticket = Ticket(title: "Ready")
        var research = ticket.phaseState(for: .research)
        research.executionState = .completed
        ticket.updatePhaseState(research)

        let moved = try TicketWorkflow().move(ticket, to: .plan)

        #expect(moved.column == .plan)
    }

    @Test
    func backwardMoveResetsLaterPhaseSnapshotsButKeepsHistory() throws {
        let run = PhaseRun(
            phase: .implement,
            model: "codex",
            prompt: "Implement it",
            output: "done",
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            success: true
        )
        var ticket = Ticket(title: "Backtrack", column: .implement)
        var implement = ticket.phaseState(for: .implement)
        implement.executionState = .completed
        implement.lastModel = "codex"
        implement.lastStartedAt = .distantPast
        implement.lastCompletedAt = .now
        implement.capturedOutput = "done"
        implement.deliverableMarkdown = "## Implemented"
        implement.deliverableGeneratedAt = .now
        implement.runs = [run]
        ticket.updatePhaseState(implement)

        let moved = try TicketWorkflow().move(ticket, to: .plan)
        let reset = moved.phaseState(for: .implement)

        #expect(moved.column == .plan)
        #expect(reset.executionState == .idle)
        #expect(reset.capturedOutput.isEmpty)
        #expect(reset.deliverableMarkdown.isEmpty)
        #expect(reset.runs.count == 1)
    }

    @Test
    func reviewCompletedTicketStaysTerminalInReviewColumn() throws {
        var ticket = Ticket(title: "Reviewed", column: .review)
        var review = ticket.phaseState(for: .review)
        review.executionState = .completed
        ticket.updatePhaseState(review)

        let unchanged = try TicketWorkflow().move(ticket, to: .review)

        #expect(unchanged.column == .review)
        #expect(unchanged.phaseState(for: .review).executionState == .completed)
    }
}
