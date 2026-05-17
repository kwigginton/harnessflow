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
    func claudeProviderInvocationUsesPrintModeWorkingDirectoryAndEnvironmentOverrides() {
        let provider = ClaudeCLIProvider(
            executablePath: "/opt/homebrew/bin/claude",
            environmentOverrides: ["ANTHROPIC_API_KEY": "sk-ant-test"]
        )
        let request = AgentRunRequest(
            ticketID: UUID(),
            phase: .implement,
            prompt: "Implement prompt",
            model: "claude-sonnet-4-5",
            workingDirectory: "/tmp/project"
        )

        let invocation = provider.makeInvocation(
            for: request,
            baseEnvironment: [
                "PATH": "/usr/bin",
                "ANTHROPIC_API_KEY": "stale-token",
            ]
        )

        #expect(invocation.arguments == [
            "-p",
            "--model", "claude-sonnet-4-5",
            "--permission-mode", "bypassPermissions",
        ])
        #expect(invocation.currentDirectory == "/tmp/project")
        #expect(invocation.environment["PATH"] == "/usr/bin")
        #expect(invocation.environment["ANTHROPIC_API_KEY"] == "sk-ant-test")
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
    func planRequestInstructsAgentToAskQuestionsForMaterialDecisions() throws {
        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(plan: "codex-plan"),
            phasePrompts: PhasePromptTemplateLoader.bundledDefaults()
        )
        let ticket = Ticket(title: "Ambiguous plan", column: .plan)

        let request = try TicketExecutionService().makeRequest(for: ticket, settings: settings)

        #expect(request.prompt.contains("If a material decision is unresolved, do not guess"))
        #expect(request.prompt.contains("shared Agent Q&A contract"))
        #expect(request.prompt.contains(AgentQuestionContract.startMarker))
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
    func reviewRequestIncludesFinalPassContract() throws {
        let ticket = Ticket(title: "Review exit", column: .review)
        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(review: "codex-review"),
            phasePrompts: PhasePromptSelection(review: "Review base prompt")
        )

        let request = try TicketExecutionService().makeRequest(for: ticket, settings: settings)

        #expect(request.phase == .review)
        #expect(request.prompt.contains("Review Exit Check"))
        #expect(request.prompt.contains("Final Pass Required: Yes"))
        #expect(request.prompt.contains("Final Pass Required: No"))
    }

    @Test
    func researchAndPlanRequestsForbidVerificationCommandsByDefault() throws {
        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(
                research: "codex-research",
                plan: "codex-plan"
            ),
            phasePrompts: PhasePromptSelection(
                research: "Research base prompt",
                plan: "Plan base prompt"
            )
        )

        for phase in [TicketPhase.research, .plan] {
            let ticket = Ticket(title: "Avoid slow checks", column: phase)
            let request = try TicketExecutionService().makeRequest(for: ticket, settings: settings)

            #expect(request.prompt.contains("Phase Execution Policy"))
            #expect(request.prompt.contains("Do not run builds, tests"))
            #expect(request.prompt.contains("unless the user explicitly asks"))
        }
    }

    @Test
    func implementAndReviewRequestsPreferFocusedVerification() throws {
        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(
                implement: "codex-implement",
                review: "codex-review"
            ),
            phasePrompts: PhasePromptSelection(
                implement: "Implement base prompt",
                review: "Review base prompt"
            )
        )

        let implementRequest = try TicketExecutionService().makeRequest(
            for: Ticket(title: "Implement narrowly", column: .implement),
            settings: settings
        )
        let reviewRequest = try TicketExecutionService().makeRequest(
            for: Ticket(title: "Review narrowly", column: .review),
            settings: settings
        )

        #expect(implementRequest.prompt.contains("Run only the focused builds, tests, or checks"))
        #expect(reviewRequest.prompt.contains("Start with code and diff inspection"))
        #expect(reviewRequest.prompt.contains("avoid repeating successful verification"))
    }

    @Test
    func reviewRequestSwitchesToFinalAdjustmentPassWhenPreviousReviewRequiresIt() throws {
        var ticket = Ticket(title: "Final pass", column: .review)
        var reviewState = ticket.phaseState(for: .review)
        reviewState.executionState = .completed
        reviewState.deliverableMarkdown = """
        ## Findings
        Fix the remaining validation copy.

        Final Pass Required: Yes

        ## Final Adjustments
        - Update the final delivery wording.
        """
        ticket.updatePhaseState(reviewState)

        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(review: "codex-review"),
            phasePrompts: PhasePromptSelection(review: "Review base prompt")
        )

        let request = try TicketExecutionService().makeRequest(for: ticket, settings: settings)

        #expect(request.prompt.contains("Final Adjustment Pass"))
        #expect(request.prompt.contains("This run is not a fresh review pass."))
        #expect(request.prompt.contains("Implement only the requested final adjustments"))
        #expect(request.prompt.contains("Fix the remaining validation copy."))
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
    func questionContractExtractsValidQuestionSet() throws {
        let output = """
        \(AgentQuestionContract.startMarker)
        {"id":"00000000-0000-0000-0000-000000000000","questions":[{"id":"decision","prompt":"Choose an approach.","choices":[{"id":"a","label":"A","description":"Use A."}],"allowsFreeform":false,"defaultChoiceID":"a"}]}
        \(AgentQuestionContract.endMarker)
        """

        let questionSet = try #require(AgentQuestionContract.extractQuestionSet(from: output))

        #expect(questionSet.questions.count == 1)
        #expect(questionSet.questions[0].id == "decision")
        #expect(questionSet.questions[0].choices[0].label == "A")
    }

    @Test
    func applyResultMapsQuestionBlockToAwaitingInput() throws {
        let ticket = Ticket(title: "Needs decision", column: .plan)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .plan,
            prompt: "Plan",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let result = AgentRunResult(
            output: """
            I need a decision.
            \(AgentQuestionContract.startMarker)
            {"id":"00000000-0000-0000-0000-000000000000","questions":[{"id":"storage","prompt":"How should Q&A be stored?","choices":[{"id":"json","label":"JSON"}],"allowsFreeform":false,"defaultChoiceID":"json"}]}
            \(AgentQuestionContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 0
        )

        let updated = TicketExecutionService().applyResult(ticket: ticket, request: request, result: result)
        let state = updated.phaseState(for: .plan)

        #expect(state.executionState == .awaitingInput)
        #expect(state.pendingQuestions?.questions.first?.id == "storage")
        #expect(state.capturedOutput.contains(AgentQuestionContract.startMarker))
        #expect(state.capturedError.isEmpty)
        #expect(state.runs.last?.success == false)
    }

    @Test
    func completedDeliverableClearsPendingQuestionsAndAnswers() {
        var ticket = Ticket(title: "Complete", column: .implement)
        var phaseState = ticket.phaseState(for: .implement)
        phaseState.executionState = .awaitingInput
        phaseState.pendingQuestions = AgentQuestionSet(questions: [
            AgentQuestion(id: "decision", prompt: "Choose", choices: [AgentQuestionChoice(id: "a", label: "A")])
        ])
        phaseState.pendingAnswers = [AgentAnswer(questionID: "decision", choiceID: "a")]
        ticket.updatePhaseState(phaseState)

        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Implement",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let result = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Done
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 0
        )

        let updated = TicketExecutionService().applyResult(ticket: ticket, request: request, result: result)

        #expect(updated.phaseState(for: .implement).executionState == .completed)
        #expect(updated.phaseState(for: .implement).pendingQuestions == nil)
        #expect(updated.phaseState(for: .implement).pendingAnswers.isEmpty)
    }

    @Test
    func continuationRequestIncludesPreviousOutputAndAnswers() throws {
        var ticket = Ticket(title: "Continue", detailsText: "Need a choice", column: .plan)
        var phaseState = ticket.phaseState(for: .plan)
        phaseState.capturedOutput = "Previous output with questions"
        phaseState.pendingQuestions = AgentQuestionSet(questions: [
            AgentQuestion(
                id: "direction",
                prompt: "Choose direction",
                choices: [AgentQuestionChoice(id: "fast", label: "Fast path")]
            )
        ])
        ticket.updatePhaseState(phaseState)

        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(plan: "codex-plan"),
            phasePrompts: PhasePromptSelection(plan: "Plan base prompt")
        )

        let request = try TicketExecutionService().makeContinuationRequest(
            for: ticket,
            settings: settings,
            answers: [AgentAnswer(questionID: "direction", choiceID: "fast", freeformText: "Use the fast path.")]
        )

        #expect(request.prompt.contains("Continuation Context"))
        #expect(request.prompt.contains("Previous output with questions"))
        #expect(request.prompt.contains("direction: Fast path"))
        #expect(request.prompt.contains("Use the fast path."))
        #expect(request.prompt.contains(PhaseDeliverableContract.startMarker))
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
    func markRunningClearsPreviouslyOwnedProcess() {
        var ticket = Ticket(title: "Running", column: .implement)
        var phaseState = ticket.phaseState(for: .implement)
        phaseState.ownedProcess = OwnedProcessReference(
            processIdentifier: 123,
            executablePath: "/opt/homebrew/bin/codex",
            launchedAt: .distantPast
        )
        ticket.updatePhaseState(phaseState)

        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Implement",
            model: "codex",
            workingDirectory: "/tmp"
        )

        let updated = TicketExecutionService().markRunning(ticket: ticket, request: request)

        #expect(updated.phaseState(for: .implement).executionState == .running)
        #expect(updated.phaseState(for: .implement).ownedProcess == nil)
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

    @Test
    func applyResultPersistsClaudeProviderMetadata() {
        let ticket = Ticket(title: "Claude run", column: .implement)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Implement",
            model: "claude-sonnet-4-5",
            workingDirectory: "/tmp"
        )
        let result = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Done
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
            providerKind: .claude,
            authMethodDescription: "Anthropic API Key"
        )

        #expect(updated.phaseState(for: .implement).runs.last?.providerKind == .claude)
        #expect(updated.phaseState(for: .implement).runs.last?.authMethodDescription == "Anthropic API Key")
    }
}
