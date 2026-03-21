import Foundation
import Testing
@testable import HarnessflowCore

struct TicketExecutionServiceTests {
    @Test
    func requestUsesPhaseModelAndPrompt() throws {
        var ticket = Ticket(title: "Execution", column: .plan)
        var phaseState = ticket.phaseState(for: .plan)
        phaseState.prompt = "Draft the implementation plan."
        ticket.updatePhaseState(phaseState)

        let settings = AppSettings(
            codexExecutablePath: "/opt/homebrew/bin/codex",
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(
                research: "codex-research",
                plan: "codex-plan",
                implement: "codex-implement",
                review: "codex-review"
            )
        )

        let request = try TicketExecutionService().makeRequest(for: ticket, settings: settings)

        #expect(request.phase == .plan)
        #expect(request.prompt == "Draft the implementation plan.")
        #expect(request.model == "codex-plan")
        #expect(request.workingDirectory == "/tmp/workdir")
    }

    @Test
    func applyResultMapsExitStatusToCompleted() {
        var ticket = Ticket(title: "Success", column: .research)
        var phaseState = ticket.phaseState(for: .research)
        phaseState.prompt = "Gather context"
        ticket.updatePhaseState(phaseState)

        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .research,
            prompt: "Gather context",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let result = AgentRunResult(
            output: "Context gathered",
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 0
        )

        let updated = TicketExecutionService().applyResult(ticket: ticket, request: request, result: result)

        #expect(updated.phaseState(for: .research).executionState == .completed)
        #expect(updated.phaseState(for: .research).runs.count == 1)
    }

    @Test
    func applyResultMapsNonZeroExitStatusToFailed() {
        var ticket = Ticket(title: "Failure", column: .implement)
        var phaseState = ticket.phaseState(for: .implement)
        phaseState.prompt = "Write the code"
        ticket.updatePhaseState(phaseState)

        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Write the code",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let result = AgentRunResult(
            output: "",
            errorOutput: "compile failed",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 1
        )

        let updated = TicketExecutionService().applyResult(ticket: ticket, request: request, result: result)

        #expect(updated.phaseState(for: .implement).executionState == .failed)
        #expect(updated.phaseState(for: .implement).capturedError == "compile failed")
    }
}
