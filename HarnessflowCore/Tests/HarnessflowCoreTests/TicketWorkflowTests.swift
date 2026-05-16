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
    func forwardMoveIsBlockedWhileAwaitingInput() throws {
        var ticket = Ticket(title: "Needs answers")
        var research = ticket.phaseState(for: .research)
        research.executionState = .awaitingInput
        research.pendingQuestions = AgentQuestionSet(questions: [
            AgentQuestion(id: "decision", prompt: "Choose")
        ])
        ticket.updatePhaseState(research)

        #expect(throws: TicketWorkflowError.currentPhaseIncomplete(.research)) {
            _ = try TicketWorkflow().move(ticket, to: .plan)
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
        implement.pendingQuestions = AgentQuestionSet(questions: [
            AgentQuestion(id: "decision", prompt: "Choose")
        ])
        implement.pendingAnswers = [AgentAnswer(questionID: "decision", choiceID: "a")]
        implement.runs = [run]
        ticket.updatePhaseState(implement)

        let moved = try TicketWorkflow().move(ticket, to: .plan)
        let reset = moved.phaseState(for: .implement)

        #expect(moved.column == .plan)
        #expect(reset.executionState == .idle)
        #expect(reset.capturedOutput.isEmpty)
        #expect(reset.deliverableMarkdown.isEmpty)
        #expect(reset.pendingQuestions == nil)
        #expect(reset.pendingAnswers.isEmpty)
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

    @Test
    func reviewCompletionMovesToDoneWhenFinalPassIsNotRequired() throws {
        var ticket = Ticket(title: "Reviewed", column: .review)
        var review = ticket.phaseState(for: .review)
        review.executionState = .completed
        review.deliverableMarkdown = """
        ## Findings
        None.

        Final Pass Required: No
        """
        ticket.updatePhaseState(review)

        let completedAt = Date(timeIntervalSince1970: 1_000)
        let completed = try TicketWorkflow().completeAfterReview(ticket, completedAt: completedAt)

        #expect(completed.completedAt == completedAt)
        #expect(completed.column == .review)
    }

    @Test
    func reviewCompletionStaysInReviewWhenFinalPassIsRequired() throws {
        var ticket = Ticket(title: "Needs final pass", column: .review)
        var review = ticket.phaseState(for: .review)
        review.executionState = .completed
        review.deliverableMarkdown = """
        ## Findings
        Final adjustments remain.

        Final Pass Required: Yes
        """
        ticket.updatePhaseState(review)

        #expect(throws: TicketWorkflowError.reviewFinalPassRequired) {
            _ = try TicketWorkflow().completeAfterReview(ticket)
        }
        #expect(ticket.phaseState(for: .review).needsFinalAdjustments)
    }

    @Test
    func reviewCompletionRequiresStandardFinalPassDecision() throws {
        var ticket = Ticket(title: "Old review", column: .review)
        var review = ticket.phaseState(for: .review)
        review.executionState = .completed
        review.deliverableMarkdown = "## Findings\nNone."
        ticket.updatePhaseState(review)

        #expect(throws: TicketWorkflowError.reviewFinalPassUndetermined) {
            _ = try TicketWorkflow().completeAfterReview(ticket)
        }
    }

    @Test
    func moveClearsDoneTimestamp() throws {
        var ticket = Ticket(title: "Reopened", column: .plan, completedAt: .now)
        var plan = ticket.phaseState(for: .plan)
        plan.executionState = .completed
        ticket.updatePhaseState(plan)

        let moved = try TicketWorkflow().move(ticket, to: .implement)

        #expect(moved.completedAt == nil)
    }
}
