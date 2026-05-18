import Foundation
import Testing
@testable import HarnessflowCore

struct TicketReducerTests {
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
        #expect(invocation.environment["PATH"] == "/usr/bin:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin")
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
        #expect(invocation.environment["PATH"] == "/usr/bin:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin")
        #expect(invocation.environment["ANTHROPIC_API_KEY"] == "sk-ant-test")
    }

    @Test
    func forwardMoveRequiresCompletedCurrentPhase() {
        let result = reduce(Ticket(title: "Blocked"), event: .moveRequested(destination: .plan))

        #expect(result.ticket.column == .research)
        #expect(result.commands == [.presentError("Research must complete successfully before moving forward.")])
    }

    @Test
    func adjacentForwardMovePersistsAfterCompletion() {
        var ticket = Ticket(title: "Ready")
        var research = ticket.phaseState(for: .research)
        research.executionState = .completed
        ticket.updatePhaseState(research)

        let result = reduce(ticket, event: .moveRequested(destination: .plan))

        #expect(result.ticket.column == .plan)
        #expect(result.commands == [.persistTicket(result.ticket)])
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
        implement.capturedOutput = "done"
        implement.deliverableMarkdown = "## Implemented"
        implement.ownedProcess = OwnedProcessReference(
            processIdentifier: 123,
            executablePath: "/opt/homebrew/bin/codex",
            launchedAt: .distantPast
        )
        implement.pendingQuestions = AgentQuestionSet(questions: [
            AgentQuestion(id: "decision", prompt: "Choose")
        ])
        implement.pendingAnswers = [AgentAnswer(questionID: "decision", choiceID: "a")]
        implement.runs = [run]
        ticket.updatePhaseState(implement)

        let result = reduce(ticket, event: .moveRequested(destination: .plan))
        let reset = result.ticket.phaseState(for: .implement)

        #expect(result.ticket.column == .plan)
        #expect(reset.executionState == .idle)
        #expect(reset.capturedOutput.isEmpty)
        #expect(reset.deliverableMarkdown.isEmpty)
        #expect(reset.ownedProcess == nil)
        #expect(reset.pendingQuestions == nil)
        #expect(reset.pendingAnswers.isEmpty)
        #expect(reset.runs == [run])
    }

    @Test
    func reviewCompletionMovesToDoneWhenFinalPassIsNotRequired() {
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
        let result = reduce(ticket, event: .shiftForwardRequested, now: completedAt)

        #expect(result.ticket.completedAt == completedAt)
        #expect(result.ticket.column == .review)
        #expect(result.commands == [.persistTicket(result.ticket)])
    }

    @Test
    func reviewCompletionRequiresStandardFinalPassDecision() {
        var ticket = Ticket(title: "Old review", column: .review)
        var review = ticket.phaseState(for: .review)
        review.executionState = .completed
        review.deliverableMarkdown = "## Findings\nNone."
        ticket.updatePhaseState(review)

        let result = reduce(ticket, event: .shiftForwardRequested)

        #expect(result.commands == [.presentError("Review must include a final-pass decision before the ticket can move to Done.")])
    }

    @Test
    func manualCompletionBlocksWhenAnyPhaseIsRunning() {
        var ticket = Ticket(title: "Archive", column: .plan)
        var research = ticket.phaseState(for: .research)
        research.executionState = .running
        ticket.updatePhaseState(research)

        let result = reduce(ticket, event: .completeRequested)

        #expect(result.ticket.completedAt == nil)
        #expect(result.commands == [.presentError("Stop running phases before marking this ticket completed.")])
    }

    @Test
    func runRequestedEmitsPersistenceLiveOutputAndRunCommand() throws {
        var ticket = Ticket(title: "Execution", detailsText: "Update persistence flow", column: .plan)
        var researchState = ticket.phaseState(for: .research)
        researchState.executionState = .completed
        researchState.deliverableMarkdown = "## Findings\n- Persist the handoff"
        ticket.updatePhaseState(researchState)

        var phaseState = ticket.phaseState(for: .plan)
        phaseState.prompt = "Focus on migration safety."
        ticket.updatePhaseState(phaseState)

        let startedAt = Date(timeIntervalSince1970: 2_000)
        let result = reduce(ticket, event: .runRequested, settings: phaseSettings, now: startedAt)
        let runningState = result.ticket.phaseState(for: .plan)
        let request = try runRequest(from: result.commands)

        #expect(runningState.executionState == .running)
        #expect(runningState.lastStartedAt == startedAt)
        #expect(runningState.ownedProcess == nil)
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
        #expect(result.commands == [
            .persistTicket(result.ticket),
            .beginLiveOutput(request: request, startedAt: startedAt),
            .runAgent(request),
        ])
    }

    @Test
    func requestBuilderPreservesPhasePromptPolicies() throws {
        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phaseModels: PhaseModelSelection(
                research: "codex-research",
                plan: "codex-plan",
                implement: "codex-implement",
                review: "codex-review"
            ),
            phasePrompts: PhasePromptTemplateLoader.bundledDefaults()
        )

        let planRequest = try TicketRunRequestBuilder().makeRequest(
            for: Ticket(title: "Ambiguous plan", column: .plan),
            settings: settings
        )
        let implementRequest = try TicketRunRequestBuilder().makeRequest(
            for: Ticket(title: "Implement narrowly", column: .implement),
            settings: settings
        )
        let reviewRequest = try TicketRunRequestBuilder().makeRequest(
            for: Ticket(title: "Review narrowly", column: .review),
            settings: settings
        )

        #expect(planRequest.prompt.contains("If a material decision is unresolved, do not guess"))
        #expect(planRequest.prompt.contains(AgentQuestionContract.startMarker))
        #expect(planRequest.prompt.contains("Do not run builds, tests"))
        #expect(implementRequest.prompt.contains("Run only the focused builds, tests, or checks"))
        #expect(reviewRequest.prompt.contains("Review Exit Check"))
        #expect(reviewRequest.prompt.contains("Final Pass Required: Yes"))
        #expect(reviewRequest.prompt.contains("Final Pass Required: No"))
    }

    @Test
    func continuationRequestIncludesPreviousOutputAndAnswers() throws {
        var ticket = Ticket(title: "Continue", detailsText: "Need a choice", column: .plan)
        var phaseState = ticket.phaseState(for: .plan)
        phaseState.executionState = .awaitingInput
        phaseState.capturedOutput = "Previous output with questions"
        phaseState.pendingQuestions = AgentQuestionSet(questions: [
            AgentQuestion(
                id: "direction",
                prompt: "Choose direction",
                choices: [AgentQuestionChoice(id: "fast", label: "Fast path")]
            )
        ])
        ticket.updatePhaseState(phaseState)

        let result = reduce(
            ticket,
            event: .continuationRequested(answers: [
                AgentAnswer(questionID: "direction", choiceID: "fast", freeformText: "Use the fast path.")
            ]),
            settings: AppSettings(
                defaultWorkingDirectory: "/tmp/workdir",
                phaseModels: PhaseModelSelection(plan: "codex-plan"),
                phasePrompts: PhasePromptSelection(plan: "Plan base prompt")
            )
        )
        let request = try runRequest(from: result.commands)

        #expect(request.prompt.contains("Continuation Context"))
        #expect(request.prompt.contains("Previous output with questions"))
        #expect(request.prompt.contains("direction: Fast path"))
        #expect(request.prompt.contains("Use the fast path."))
        #expect(request.prompt.contains(PhaseDeliverableContract.startMarker))
        #expect(result.ticket.phaseState(for: .plan).executionState == .running)
    }

    @Test
    func agentResultMapsExitStatusToCompletedAndPersistsMetadata() {
        let ticket = Ticket(title: "Success", column: .research)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .research,
            prompt: "Gather context",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let agentResult = AgentRunResult(
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

        let result = reduce(
            ticket,
            event: .agentResultReceived(
                request: request,
                result: agentResult,
                providerKind: .codex,
                authMethod: .subscription,
                authMethodDescription: "Subscription",
                didFallbackFromSubscription: true
            )
        )
        let state = result.ticket.phaseState(for: .research)

        #expect(state.executionState == .completed)
        #expect(state.deliverableMarkdown.contains("Research Corpus"))
        #expect(state.runs.count == 1)
        #expect(state.runs.last?.authMethod == .subscription)
        #expect(state.runs.last?.didFallbackFromSubscription == true)
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
        ])
    }

    @Test
    func agentResultMapsQuestionBlockToAwaitingInput() {
        let ticket = Ticket(title: "Needs decision", column: .plan)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .plan,
            prompt: "Plan",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let agentResult = AgentRunResult(
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

        let result = reduce(ticket, event: .agentResultReceived(
            request: request,
            result: agentResult,
            providerKind: .codex,
            authMethod: .unknown,
            authMethodDescription: "Unknown",
            didFallbackFromSubscription: false
        ))
        let state = result.ticket.phaseState(for: .plan)

        #expect(state.executionState == .awaitingInput)
        #expect(state.pendingQuestions?.questions.first?.id == "storage")
        #expect(state.capturedOutput.contains(AgentQuestionContract.startMarker))
        #expect(state.capturedError.isEmpty)
        #expect(state.runs.last?.success == false)
    }

    @Test
    func agentResultMarksWrappedDeliverableMissingAsFailed() {
        let ticket = Ticket(title: "Missing Deliverable", column: .implement)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Write the code",
            promptAddendum: "Write the code",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let agentResult = AgentRunResult(
            output: "implemented without markers",
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: .now,
            exitCode: 0
        )

        let result = reduce(ticket, event: .agentResultReceived(
            request: request,
            result: agentResult,
            providerKind: .codex,
            authMethod: .unknown,
            authMethodDescription: "Unknown",
            didFallbackFromSubscription: false
        ))
        let state = result.ticket.phaseState(for: .implement)

        #expect(state.executionState == .failed)
        #expect(state.capturedOutput == "implemented without markers")
        #expect(state.capturedError.contains("wrapped implement deliverable"))
        #expect(state.deliverableMarkdown.isEmpty)
        #expect(state.runs.last?.success == false)
    }

    @Test
    func agentFailurePersistsRunAndFailsLiveOutput() {
        let ticket = Ticket(title: "Failure", column: .review)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .review,
            prompt: "Validate the change",
            model: "gpt-5.3-codex",
            workingDirectory: "/tmp"
        )

        let result = reduce(ticket, event: .agentFailureReceived(
            request: request,
            message: "rate limited",
            providerKind: .codex,
            authMethod: .apiKey,
            authMethodDescription: "API Key",
            didFallbackFromSubscription: true
        ))
        let state = result.ticket.phaseState(for: .review)

        #expect(state.executionState == .failed)
        #expect(state.runs.last?.authMethod == .apiKey)
        #expect(state.runs.last?.didFallbackFromSubscription == true)
        #expect(result.commands == [
            .persistTicket(result.ticket),
            .failLiveOutput(request: request, message: "rate limited"),
        ])
    }

    @Test
    func processAttachedPersistsOwnedProcessReference() {
        let ticket = Ticket(title: "Running", column: .implement)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .implement,
            prompt: "Implement",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let attachedAt = Date(timeIntervalSince1970: 3_000)

        let result = reduce(ticket, event: .processAttached(
            request: request,
            processIdentifier: 123,
            executablePath: "/opt/homebrew/bin/codex"
        ), now: attachedAt)

        #expect(result.ticket.phaseState(for: .implement).ownedProcess == OwnedProcessReference(
            processIdentifier: 123,
            executablePath: "/opt/homebrew/bin/codex",
            launchedAt: attachedAt
        ))
        #expect(result.commands == [.persistTicket(result.ticket)])
    }

    @Test
    func phaseRecoveredMarksFailedAndClearsLiveOutput() {
        var ticket = Ticket(title: "Recovered", column: .implement)
        var implement = ticket.phaseState(for: .implement)
        implement.executionState = .running
        implement.capturedError = "previous"
        implement.ownedProcess = OwnedProcessReference(
            processIdentifier: 123,
            executablePath: "/opt/homebrew/bin/codex",
            launchedAt: .distantPast
        )
        ticket.updatePhaseState(implement)

        let result = reduce(ticket, event: .phaseRecovered(phase: .implement, message: "terminated"))
        let state = result.ticket.phaseState(for: .implement)

        #expect(state.executionState == .failed)
        #expect(state.ownedProcess == nil)
        #expect(state.capturedError == "previous\n\nterminated")
        #expect(result.commands == [
            .persistTicket(result.ticket),
            .clearLiveOutput(ticketID: ticket.id, phase: .implement),
        ])
    }

    @Test
    func autoShiftStartsNextPhaseAfterSuccessfulDeliverable() throws {
        var ticket = Ticket(title: "Auto", autoShiftOnSuccess: true)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .research,
            prompt: "Research",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let completedAt = Date(timeIntervalSince1970: 4_000)
        let agentResult = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Done
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: completedAt,
            exitCode: 0
        )
        var research = ticket.phaseState(for: .research)
        research.executionState = .running
        ticket.updatePhaseState(research)

        let result = reduce(
            ticket,
            event: .agentResultReceived(
                request: request,
                result: agentResult,
                providerKind: .codex,
                authMethod: .unknown,
                authMethodDescription: "Unknown",
                didFallbackFromSubscription: false
            ),
            settings: phaseSettings,
            now: completedAt
        )
        let planRequest = try runRequest(from: result.commands)

        #expect(result.ticket.column == .plan)
        #expect(result.ticket.phaseState(for: .research).executionState == .completed)
        #expect(result.ticket.phaseState(for: .research).deliverableMarkdown == "## Done")
        #expect(result.ticket.phaseState(for: .research).runs.count == 1)
        #expect(result.ticket.phaseState(for: .plan).executionState == .running)
        #expect(planRequest.phase == .plan)
        #expect(planRequest.prompt.contains("Plan base prompt"))
        #expect(planRequest.prompt.contains("## Research"))
        #expect(planRequest.prompt.contains("## Done"))
        #expect(planRequest.model == "codex-plan")
        #expect(planRequest.workingDirectory == "/tmp/workdir")
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
            .beginLiveOutput(request: planRequest, startedAt: completedAt),
            .runAgent(planRequest),
        ])
    }

    @Test
    func autoShiftStopsWhenPlanRequestsInput() {
        var ticket = Ticket(title: "Auto plan", column: .plan, autoShiftOnSuccess: true)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .plan,
            prompt: "Plan",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let agentResult = AgentRunResult(
            output: """
            I need a decision.
            \(AgentQuestionContract.startMarker)
            {"id":"00000000-0000-0000-0000-000000000000","questions":[{"id":"storage","prompt":"How should Q&A be stored?","choices":[{"id":"json","label":"JSON"}],"allowsFreeform":false,"defaultChoiceID":"json"}]}
            \(AgentQuestionContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: Date(timeIntervalSince1970: 4_100),
            exitCode: 0
        )
        var plan = ticket.phaseState(for: .plan)
        plan.executionState = .running
        ticket.updatePhaseState(plan)

        let result = reduce(ticket, event: .agentResultReceived(
            request: request,
            result: agentResult,
            providerKind: .codex,
            authMethod: .unknown,
            authMethodDescription: "Unknown",
            didFallbackFromSubscription: false
        ))
        let planState = result.ticket.phaseState(for: .plan)

        #expect(result.ticket.column == .plan)
        #expect(planState.executionState == .awaitingInput)
        #expect(planState.pendingQuestions?.questions.first?.id == "storage")
        #expect(planState.runs.last?.success == false)
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
        ])
    }

    @Test
    func autoShiftCompletesReviewWithoutStartingAnotherRun() {
        var ticket = Ticket(title: "Auto review", column: .review, autoShiftOnSuccess: true)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .review,
            prompt: "Review",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let completedAt = Date(timeIntervalSince1970: 5_000)
        let agentResult = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Findings
            None.

            Final Pass Required: No
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: completedAt,
            exitCode: 0
        )
        var review = ticket.phaseState(for: .review)
        review.executionState = .running
        ticket.updatePhaseState(review)

        let result = reduce(
            ticket,
            event: .agentResultReceived(
                request: request,
                result: agentResult,
                providerKind: .codex,
                authMethod: .unknown,
                authMethodDescription: "Unknown",
                didFallbackFromSubscription: false
            ),
            settings: phaseSettings,
            now: completedAt
        )
        let reviewState = result.ticket.phaseState(for: .review)

        #expect(result.ticket.column == .review)
        #expect(result.ticket.completedAt == completedAt)
        #expect(reviewState.executionState == .completed)
        #expect(reviewState.needsFinalAdjustments == false)
        #expect(reviewState.runs.count == 1)
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
        ])
    }

    @Test
    func autoShiftPersistsShiftedTicketWhenNextPhasePromptIsMissing() {
        var ticket = Ticket(title: "Missing prompt", autoShiftOnSuccess: true)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .research,
            prompt: "Research",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let completedAt = Date(timeIntervalSince1970: 4_200)
        let agentResult = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Done
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: completedAt,
            exitCode: 0
        )
        var research = ticket.phaseState(for: .research)
        research.executionState = .running
        ticket.updatePhaseState(research)

        var settings = phaseSettings
        settings.phasePrompts.plan = ""

        let result = reduce(
            ticket,
            event: .agentResultReceived(
                request: request,
                result: agentResult,
                providerKind: .codex,
                authMethod: .unknown,
                authMethodDescription: "Unknown",
                didFallbackFromSubscription: false
            ),
            settings: settings,
            now: completedAt
        )

        #expect(result.ticket.column == .plan)
        #expect(result.ticket.completedAt == nil)
        #expect(result.ticket.phaseState(for: .research).executionState == .completed)
        #expect(result.ticket.phaseState(for: .research).deliverableMarkdown == "## Done")
        #expect(result.ticket.phaseState(for: .research).runs.count == 1)
        #expect(result.ticket.phaseState(for: .plan).executionState == .idle)
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
            .presentError("Add a base prompt for Plan in Settings before running the agent."),
        ])
    }

    @Test
    func autoShiftPersistsShiftedTicketWhenWorkingDirectoryIsMissing() {
        var ticket = Ticket(title: "Missing working directory", autoShiftOnSuccess: true)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .research,
            prompt: "Research",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let completedAt = Date(timeIntervalSince1970: 4_300)
        let agentResult = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Done
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: completedAt,
            exitCode: 0
        )
        var research = ticket.phaseState(for: .research)
        research.executionState = .running
        ticket.updatePhaseState(research)

        var settings = phaseSettings
        settings.defaultWorkingDirectory = ""

        let result = reduce(
            ticket,
            event: .agentResultReceived(
                request: request,
                result: agentResult,
                providerKind: .codex,
                authMethod: .unknown,
                authMethodDescription: "Unknown",
                didFallbackFromSubscription: false
            ),
            settings: settings,
            workingDirectoryOverride: nil,
            now: completedAt
        )

        #expect(result.ticket.column == .plan)
        #expect(result.ticket.completedAt == nil)
        #expect(result.ticket.phaseState(for: .research).executionState == .completed)
        #expect(result.ticket.phaseState(for: .research).deliverableMarkdown == "## Done")
        #expect(result.ticket.phaseState(for: .research).runs.count == 1)
        #expect(result.ticket.phaseState(for: .plan).executionState == .idle)
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
            .presentError("Configure a working directory in Settings before running the agent."),
        ])
    }

    @Test
    func autoShiftKeepsReviewOpenWhenFinalAdjustmentsAreRequired() {
        var ticket = Ticket(title: "Auto review", column: .review, autoShiftOnSuccess: true)
        let request = AgentRunRequest(
            ticketID: ticket.id,
            phase: .review,
            prompt: "Review",
            model: "codex",
            workingDirectory: "/tmp"
        )
        let agentResult = AgentRunResult(
            output: """
            \(PhaseDeliverableContract.startMarker)
            ## Findings
            Needs one more change.

            Final Pass Required: Yes

            ## Final Adjustments
            - Apply the requested fix.
            \(PhaseDeliverableContract.endMarker)
            """,
            errorOutput: "",
            startedAt: .distantPast,
            completedAt: Date(timeIntervalSince1970: 5_000),
            exitCode: 0
        )
        var review = ticket.phaseState(for: .review)
        review.executionState = .running
        ticket.updatePhaseState(review)

        let result = reduce(ticket, event: .agentResultReceived(
            request: request,
            result: agentResult,
            providerKind: .codex,
            authMethod: .unknown,
            authMethodDescription: "Unknown",
            didFallbackFromSubscription: false
        ))
        let reviewState = result.ticket.phaseState(for: .review)

        #expect(result.ticket.column == .review)
        #expect(result.ticket.completedAt == nil)
        #expect(reviewState.executionState == .completed)
        #expect(reviewState.needsFinalAdjustments)
        #expect(reviewState.runs.count == 1)
        #expect(result.commands == [
            .completeLiveOutput(request: request, result: agentResult),
            .persistTicket(result.ticket),
        ])
    }

    private var phaseSettings: AppSettings {
        AppSettings(
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
    }

    private func reduce(
        _ ticket: Ticket,
        event: TicketEvent,
        settings: AppSettings? = nil,
        workingDirectoryOverride: String? = "/tmp/workdir",
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) -> TicketReducerResult {
        TicketReducer().reduce(
            ticket: ticket,
            event: event,
            context: TicketReducerContext(
                settings: settings ?? AppSettings(
                    defaultWorkingDirectory: "/tmp/workdir",
                    phasePrompts: PhasePromptSelection(
                        research: "Research base prompt",
                        plan: "Plan base prompt",
                        implement: "Implement base prompt",
                        review: "Review base prompt"
                    )
                ),
                workingDirectoryOverride: workingDirectoryOverride,
                now: now
            )
        )
    }

    private func runRequest(from commands: [TicketCommand]) throws -> AgentRunRequest {
        for command in commands {
            if case let .runAgent(request) = command {
                return request
            }
        }
        Issue.record("Expected runAgent command.")
        throw MissingCommandError()
    }

    private struct MissingCommandError: Error {}
}
