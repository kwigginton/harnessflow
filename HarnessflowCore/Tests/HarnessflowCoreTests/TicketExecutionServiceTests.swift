import Foundation
import Testing
@testable import HarnessflowCore

struct TicketExecutionServiceTests {
    @Test
    func codexProviderInvocationMergesEnvironmentOverrides() {
        let provider = CodexCLIProvider(
            executablePath: "/opt/homebrew/bin/codex",
            environmentOverrides: ["OPENAI_API_KEY": "sk-test"]
        )
        let request = AgentRunRequest(
            ticketID: UUID(),
            phase: .research,
            prompt: "Research prompt",
            model: "codex",
            workingDirectory: "/tmp/workdir"
        )

        let invocation = provider.makeInvocation(
            for: request,
            baseEnvironment: [
                "PATH": "/usr/bin",
                "OPENAI_API_KEY": "stale-token",
            ]
        )

        #expect(invocation.arguments == [
            "exec",
            "-m", "codex",
            "-C", "/tmp/workdir",
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
            "-",
        ])
        #expect(invocation.environment["PATH"] == "/usr/bin")
        #expect(invocation.environment["OPENAI_API_KEY"] == "sk-test")
    }

    @Test
    func requestUsesPhaseModelBasePromptAndPriorDeliverables() throws {
        var ticket = Ticket(title: "Execution", detailsText: "Update persistence flow", column: .plan)
        var researchState = ticket.phaseState(for: .research)
        researchState.executionState = .completed
        researchState.deliverableMarkdown = "## Findings\n- Persist the handoff"
        ticket.updatePhaseState(researchState)

        var phaseState = ticket.phaseState(for: .plan)
        phaseState.prompt = "Focus on migration safety."
        ticket.updatePhaseState(phaseState)

        let settings = AppSettings(
            codexExecutablePath: "/opt/homebrew/bin/codex",
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(
                research: "codex-research",
                plan: "codex-plan",
                implement: "codex-implement",
                review: "codex-review"
            ),
            phasePrompts: PhasePromptSelection(
                research: "Research base prompt",
                plan: "Plan base prompt",
                implement: "Implement base prompt",
                review: "Review base prompt"
            )
        )

        let request = try TicketExecutionService().makeRequest(for: ticket, settings: settings)

        #expect(request.phase == .plan)
        #expect(request.prompt.contains("Plan base prompt"))
        #expect(request.prompt.contains("Title: Execution"))
        #expect(request.prompt.contains("Update persistence flow"))
        #expect(request.prompt.contains("Focus on migration safety."))
        #expect(request.prompt.contains("## Research"))
        #expect(request.prompt.contains(PhaseDeliverableContract.startMarker))
        #expect(request.promptAddendum == "Focus on migration safety.")
        #expect(request.model == "codex-plan")
        #expect(request.workingDirectory == "/tmp/workdir")
    }

    @Test
    func requestPrefersExplicitWorkingDirectoryOverride() throws {
        var ticket = Ticket(title: "Execution", column: .plan)
        var phaseState = ticket.phaseState(for: .plan)
        phaseState.prompt = "Draft the implementation plan."
        ticket.updatePhaseState(phaseState)

        let settings = AppSettings(
            codexExecutablePath: "/opt/homebrew/bin/codex",
            defaultWorkingDirectory: "/tmp/default",
            phaseModels: PhaseModelSelection(plan: "codex-plan"),
            phasePrompts: PhasePromptSelection(plan: "Plan base prompt")
        )

        let request = try TicketExecutionService().makeRequest(
            for: ticket,
            settings: settings,
            workingDirectoryOverride: "/tmp/project"
        )

        #expect(request.workingDirectory == "/tmp/project")
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
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Research Corpus
            - Context gathered
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 0
        )

        let updated = TicketExecutionService().applyResult(
            ticket: ticket,
            request: request,
            result: result,
            authMethod: .subscription,
            didFallbackFromSubscription: true
        )

        #expect(updated.phaseState(for: .research).executionState == .completed)
        #expect(updated.phaseState(for: .research).deliverableMarkdown.contains("Research Corpus"))
        #expect(updated.phaseState(for: .research).runs.count == 1)
        #expect(updated.phaseState(for: .research).runs.last?.authMethod == .subscription)
        #expect(updated.phaseState(for: .research).runs.last?.didFallbackFromSubscription == true)
    }

    @Test
    func applyResultMarksWrappedDeliverableMissingAsFailed() {
        var ticket = Ticket(title: "Missing Deliverable", column: .implement)
        var phaseState = ticket.phaseState(for: .implement)
        phaseState.prompt = "Write the code"
        ticket.updatePhaseState(phaseState)

        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Write the code",
            promptAddendum: "Write the code",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let result = AgentRunResult(
            output: "implemented without markers",
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 0
        )

        let updated = TicketExecutionService().applyResult(ticket: ticket, request: request, result: result)

        #expect(updated.phaseState(for: .implement).executionState == .failed)
        #expect(updated.phaseState(for: .implement).capturedOutput == "implemented without markers")
        #expect(updated.phaseState(for: .implement).capturedError.contains("wrapped implement deliverable"))
        #expect(updated.phaseState(for: .implement).deliverableMarkdown.isEmpty)
        #expect(updated.phaseState(for: .implement).runs.last?.success == false)
    }

    @Test
    func applyResultMapsNonZeroExitStatusToFailedWithoutOverwritingPreviousDeliverable() {
        var ticket = Ticket(title: "Failure", column: .implement)
        var phaseState = ticket.phaseState(for: .implement)
        phaseState.prompt = "Write the code"
        phaseState.deliverableMarkdown = "## Previous Deliverable"
        phaseState.deliverableGeneratedAt = .distantPast
        ticket.updatePhaseState(phaseState)

        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Write the code",
            promptAddendum: "Write the code",
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
        #expect(updated.phaseState(for: .implement).deliverableMarkdown == "## Previous Deliverable")
    }

    @Test
    func applyFailurePersistsAuthMetadata() {
        let ticket = Ticket(title: "Failure", column: .review)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .review,
            prompt: "Validate the change",
            model: "gpt-5.3-codex",
            workingDirectory: "/tmp"
        )

        let updated = TicketExecutionService().applyFailure(
            ticket: ticket,
            request: request,
            errorMessage: "rate limited",
            authMethod: .apiKey,
            didFallbackFromSubscription: true
        )

        #expect(updated.phaseState(for: .review).runs.last?.authMethod == .apiKey)
        #expect(updated.phaseState(for: .review).runs.last?.didFallbackFromSubscription == true)
    }
}
