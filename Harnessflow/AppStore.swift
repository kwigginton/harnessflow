import Combine
import Foundation
import Security
import SwiftData
import HarnessflowCore

@MainActor
final class AppStore: ObservableObject {
    enum ErrorRecoveryAction: Equatable {
        case clearRunningState(ticketID: UUID, phase: TicketPhase)

        var title: String {
            switch self {
            case .clearRunningState:
                "Clear Running State"
            }
        }
    }

    struct LivePhaseOutput: Equatable, Sendable {
        let ticketID: UUID
        let phase: TicketPhase
        var processIdentifier: Int32?
        var startedAt: Date
        var lastUpdatedAt: Date
        var standardOutput: String
        var standardError: String
        var combinedText: String
        var isRunning: Bool

        init(ticketID: UUID, phase: TicketPhase, startedAt: Date) {
            self.ticketID = ticketID
            self.phase = phase
            self.processIdentifier = nil
            self.startedAt = startedAt
            self.lastUpdatedAt = startedAt
            self.standardOutput = ""
            self.standardError = ""
            self.combinedText = ""
            self.isRunning = true
        }
    }

    private struct LivePhaseOutputKey: Hashable {
        let ticketID: UUID
        let phase: TicketPhase
    }

    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var selectedProjectID: UUID?
    @Published var selectedTicketID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var errorRecoveryAction: ErrorRecoveryAction?
    @Published private(set) var hasOpenAIAPIToken = false
    @Published private(set) var codexLoginStatus: CodexLoginStatus = .unknown("Codex login status has not been checked yet.")
    @Published private var livePhaseOutputs: [LivePhaseOutputKey: LivePhaseOutput] = [:]

    private let persistenceStore: PersistenceStore
    private let credentialsStore: OpenAICredentialsStore
    private let workflow = TicketWorkflow()
    private let executionService = TicketExecutionService()
    private let processSupervisor = OwnedProcessSupervisor()

    init(modelContainer: ModelContainer, defaultWorkingDirectory: String) {
        self.persistenceStore = PersistenceStore(
            modelContainer: modelContainer,
            defaultWorkingDirectory: defaultWorkingDirectory
        )
        self.credentialsStore = OpenAICredentialsStore(
            service: Bundle.main.bundleIdentifier ?? "com.kenw.harnessflow",
            account: "openai.api-token"
        )
        self.settings = AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
        reload()
    }

    var selectedTicket: Ticket? {
        tickets.first(where: { $0.id == selectedTicketID })
    }

    var selectedProject: ProjectRecord? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    var hasSelectedProject: Bool {
        selectedProject != nil
    }

    func ticket(withID id: UUID) -> Ticket? {
        tickets.first(where: { $0.id == id })
    }

    func liveOutput(for ticketID: UUID, phase: TicketPhase) -> LivePhaseOutput? {
        livePhaseOutputs[LivePhaseOutputKey(ticketID: ticketID, phase: phase)]
    }

    func selectTicket(_ id: UUID?) {
        selectedTicketID = id
    }

    func selectProject(_ id: UUID) {
        do {
            try persistenceStore.saveSelectedProjectID(id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
        errorRecoveryAction = nil
    }

    func reload() {
        do {
            settings = try persistenceStore.loadSettings()
            projects = try persistenceStore.loadProjects()
            selectedProjectID = try persistenceStore.loadSelectedProjectID()
            if let selectedProjectID {
                tickets = try persistenceStore.loadTickets(projectID: selectedProjectID)
            } else {
                tickets = []
            }
            if let selectedTicketID, tickets.contains(where: { $0.id == selectedTicketID }) == false {
                self.selectedTicketID = nil
            }
            hasOpenAIAPIToken = try credentialsStore.loadToken()?.isEmpty == false
            codexLoginStatus = readCodexLoginStatus(executablePath: settings.codexExecutablePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCodexLoginStatus() {
        codexLoginStatus = readCodexLoginStatus(executablePath: settings.codexExecutablePath)
    }

    func loadOpenAIAPIToken() -> String {
        do {
            return try credentialsStore.loadToken() ?? ""
        } catch {
            errorMessage = error.localizedDescription
            return ""
        }
    }

    func saveOpenAIAPIToken(_ token: String) {
        do {
            try credentialsStore.saveToken(token)
            hasOpenAIAPIToken = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteOpenAIAPIToken() {
        do {
            try credentialsStore.deleteToken()
            hasOpenAIAPIToken = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTicket(
        title: String,
        detailsText: String,
        initialPhase: TicketPhase = .research,
        autoShiftOnSuccess: Bool = false
    ) {
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            errorMessage = "Ticket title cannot be empty."
            return
        }
        guard let selectedProjectID else {
            errorMessage = "Select a project before creating a ticket."
            return
        }

        do {
            let ticket = try persistenceStore.createTicket(
                title: trimmedTitle,
                detailsText: detailsText,
                projectID: selectedProjectID,
                initialPhase: initialPhase,
                autoShiftOnSuccess: autoShiftOnSuccess
            )
            reload()
            selectedTicketID = ticket.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(name: String, workingDirectory: String) {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false else {
            errorMessage = "Project name cannot be empty."
            return
        }
        guard trimmedDirectory.isEmpty == false else {
            errorMessage = "Project working directory cannot be empty."
            return
        }

        do {
            let project = try persistenceStore.createProject(
                name: trimmedName,
                workingDirectory: trimmedDirectory
            )
            try persistenceStore.saveSelectedProjectID(project.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedProjectDirectory(_ workingDirectory: String) {
        errorMessage = nil
        guard let selectedProjectID else {
            errorMessage = "Select a project before choosing a directory."
            return
        }

        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDirectory.isEmpty == false else {
            errorMessage = "Project working directory cannot be empty."
            return
        }

        do {
            _ = try persistenceStore.updateProjectDirectory(
                projectID: selectedProjectID,
                workingDirectory: trimmedDirectory
            )
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePrompt(for ticketID: UUID, prompt: String) {
        guard let ticket = tickets.first(where: { $0.id == ticketID }) else {
            return
        }

        do {
            try persistenceStore.savePrompt(ticketID: ticketID, phase: ticket.column, prompt: prompt)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func moveTicket(id: UUID, to phase: TicketPhase) -> Bool {
        guard let ticket = tickets.first(where: { $0.id == id }) else {
            return false
        }
        guard let selectedProjectID else {
            errorMessage = "Select a project before moving tickets."
            return false
        }

        do {
            let updated = try workflow.move(ticket, to: phase)
            try persistenceStore.upsert(ticket: updated, projectID: selectedProjectID)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func shiftTicketForward(id: UUID) -> Bool {
        guard let ticket = tickets.first(where: { $0.id == id }) else {
            return false
        }
        guard let selectedProjectID else {
            errorMessage = "Select a project before moving tickets."
            return false
        }

        do {
            let shifted = try shiftCompletedTicket(ticket)
            try persistenceStore.upsert(ticket: shifted, projectID: selectedProjectID)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveSettings(
        codexExecutablePath: String,
        defaultWorkingDirectory: String,
        codexAuthStrategy: CodexAuthStrategy,
        researchModel: String,
        planModel: String,
        implementModel: String,
        reviewModel: String,
        researchPrompt: String,
        planPrompt: String,
        implementPrompt: String,
        reviewPrompt: String
    ) {
        let draft = AppSettings(
            codexExecutablePath: codexExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultWorkingDirectory: defaultWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
            codexAuthStrategy: codexAuthStrategy,
            phaseModels: PhaseModelSelection(
                research: researchModel.trimmingCharacters(in: .whitespacesAndNewlines),
                plan: planModel.trimmingCharacters(in: .whitespacesAndNewlines),
                implement: implementModel.trimmingCharacters(in: .whitespacesAndNewlines),
                review: reviewModel.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            phasePrompts: PhasePromptSelection(
                research: researchPrompt,
                plan: planPrompt,
                implement: implementPrompt,
                review: reviewPrompt
            )
        )

        do {
            try persistenceStore.saveSettings(draft)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runCurrentPhase(for ticketID: UUID) async {
        guard
            let ticket = tickets.first(where: { $0.id == ticketID }),
            let project = selectedProject
        else {
            return
        }

        let projectID = project.id
        var request: AgentRunRequest?

        do {
            let token = try credentialsStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preparedRequest = try executionService.makeRequest(
                for: ticket,
                settings: settings,
                workingDirectoryOverride: project.workingDirectory
            )
            request = preparedRequest
            let loginStatus = readCodexLoginStatus(executablePath: settings.codexExecutablePath)
            codexLoginStatus = loginStatus
            let authResolver = CodexAuthResolver()
            let resolution = try authResolver.resolve(
                strategy: settings.codexAuthStrategy,
                loginStatus: loginStatus,
                hasAPIKey: token?.isEmpty == false,
                model: preparedRequest.model
            )
            let runningTicket = executionService.markRunning(ticket: ticket, request: preparedRequest)
            try persistenceStore.upsert(ticket: runningTicket, projectID: projectID)
            beginLiveOutput(for: preparedRequest, startedAt: runningTicket.phaseState(for: preparedRequest.phase).lastStartedAt ?? .now)
            reload()

            let execution = try await executeRequest(
                preparedRequest,
                apiToken: token,
                resolution: resolution
            )
            let completedTicket = executionService.applyResult(
                ticket: runningTicket,
                request: preparedRequest,
                result: execution.result,
                authMethod: execution.authMethod,
                didFallbackFromSubscription: execution.didFallbackFromSubscription
            )
            let finalTicket = try maybeAutoShift(
                completedTicket,
                completedAt: execution.result.completedAt
            )
            try persistenceStore.upsert(ticket: finalTicket, projectID: projectID)
            completeLiveOutput(for: preparedRequest, result: execution.result)
            reload()
        } catch {
            if let request {
                do {
                    let currentTicket = try persistenceStore.ticket(withID: ticketID) ?? ticket
                    let executionError = error as? CodexExecutionAttemptError
                    let failedTicket = executionService.applyFailure(
                        ticket: currentTicket,
                        request: request,
                        errorMessage: executionError?.message ?? error.localizedDescription,
                        authMethod: executionError?.authMethod ?? .unknown,
                        didFallbackFromSubscription: executionError?.didFallbackFromSubscription ?? false
                    )
                    try persistenceStore.upsert(ticket: failedTicket, projectID: projectID)
                    failLiveOutput(for: request, message: executionError?.message ?? error.localizedDescription)
                    reload()
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func terminateOwnedProcess(ticketID: UUID, phase: TicketPhase, force: Bool = false) {
        guard let ticket = ticket(withID: ticketID) else {
            return
        }
        let phaseState = ticket.phaseState(for: phase)
        guard let ownedProcess = phaseState.ownedProcess else {
            errorMessage = "There is no recorded process for this phase."
            return
        }

        let priorStatus = processSupervisor.status(
            for: ownedProcess,
            attachedPID: liveOutput(for: ticketID, phase: phase)?.processIdentifier
        )
        let status = processSupervisor.terminate(reference: ownedProcess, force: force)
        if priorStatus.kind == .runningDetached {
            markPhaseRecovered(
                ticketID: ticketID,
                phase: phase,
                recoveryMessage: status.summary
            )
        } else if status.canTerminate {
            reload()
        } else {
            presentError(
                status.summary,
                recoveryAction: status.kind == .exited
                    ? .clearRunningState(ticketID: ticketID, phase: phase)
                    : nil
            )
        }
    }

    func clearStuckRunningState(ticketID: UUID, phase: TicketPhase) {
        guard let ticket = ticket(withID: ticketID) else {
            return
        }

        let phaseState = ticket.phaseState(for: phase)
        guard phaseState.executionState == .running else {
            return
        }

        let status = phaseState.ownedProcess.map { ownedProcess in
            processSupervisor.status(
                for: ownedProcess,
                attachedPID: liveOutput(for: ticketID, phase: phase)?.processIdentifier
            )
        }

        if status?.canTerminate == true {
            errorMessage = "PID \(phaseState.ownedProcess?.processIdentifier ?? 0) still appears to be running. Terminate it before clearing the running state."
            return
        }

        markPhaseRecovered(
            ticketID: ticketID,
            phase: phase,
            recoveryMessage: status?.summary ?? "The phase was manually cleared from a stuck running state."
        )
    }

    private func readCodexLoginStatus(executablePath: String) -> CodexLoginStatus {
        CodexCLIProvider(executablePath: executablePath).readLoginStatus()
    }

    private func executeRequest(
        _ request: AgentRunRequest,
        apiToken: String?,
        resolution: CodexAuthResolution
    ) async throws -> CodexExecutionOutcome {
        let trimmedToken = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAPIKey = trimmedToken?.isEmpty == false
        let authResolver = CodexAuthResolver()
        let primaryProvider = makeProvider(
            authMethod: resolution.authMethod,
            apiToken: trimmedToken
        )

        do {
            let primaryResult = try await primaryProvider.run(
                request: request,
                onStart: { [weak self] processIdentifier in
                    Task { @MainActor in
                        self?.attachProcess(processIdentifier, to: request)
                    }
                },
                onOutput: { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendLiveOutput(chunk, to: request)
                    }
                }
            )
            if authResolver.shouldRetryWithAPIKey(
                after: combinedFailureText(output: primaryResult.output, errorOutput: primaryResult.errorOutput),
                previousResolution: resolution,
                hasAPIKey: hasAPIKey
            ) {
                let fallbackProvider = makeProvider(authMethod: .apiKey, apiToken: trimmedToken)
                resetLiveOutput(for: request)
                let fallbackResult = try await fallbackProvider.run(
                    request: request,
                    onStart: { [weak self] processIdentifier in
                        Task { @MainActor in
                            self?.attachProcess(processIdentifier, to: request)
                        }
                    },
                    onOutput: { [weak self] chunk in
                        Task { @MainActor in
                            self?.appendLiveOutput(chunk, to: request)
                        }
                    }
                )
                return CodexExecutionOutcome(
                    result: fallbackResult,
                    authMethod: .apiKey,
                    didFallbackFromSubscription: true
                )
            }

            return CodexExecutionOutcome(
                result: primaryResult,
                authMethod: resolution.authMethod,
                didFallbackFromSubscription: false
            )
        } catch {
            if authResolver.shouldRetryWithAPIKey(
                after: error.localizedDescription,
                previousResolution: resolution,
                hasAPIKey: hasAPIKey
            ) {
                let fallbackProvider = makeProvider(authMethod: .apiKey, apiToken: trimmedToken)
                resetLiveOutput(for: request)

                do {
                    let fallbackResult = try await fallbackProvider.run(
                        request: request,
                        onStart: { [weak self] processIdentifier in
                            Task { @MainActor in
                                self?.attachProcess(processIdentifier, to: request)
                            }
                        },
                        onOutput: { [weak self] chunk in
                            Task { @MainActor in
                                self?.appendLiveOutput(chunk, to: request)
                            }
                        }
                    )
                    return CodexExecutionOutcome(
                        result: fallbackResult,
                        authMethod: .apiKey,
                        didFallbackFromSubscription: true
                    )
                } catch {
                    throw CodexExecutionAttemptError(
                        message: error.localizedDescription,
                        authMethod: .apiKey,
                        didFallbackFromSubscription: true
                    )
                }
            }

            throw CodexExecutionAttemptError(
                message: error.localizedDescription,
                authMethod: resolution.authMethod,
                didFallbackFromSubscription: false
            )
        }
    }

    private func makeProvider(
        authMethod: CodexAuthMethod,
        apiToken: String?
    ) -> CodexCLIProvider {
        let environmentOverrides: [String: String]

        switch authMethod {
        case .apiKey:
            if let apiToken, apiToken.isEmpty == false {
                environmentOverrides = ["OPENAI_API_KEY": apiToken]
            } else {
                environmentOverrides = [:]
            }
        case .subscription, .unknown:
            environmentOverrides = [:]
        }

        return CodexCLIProvider(
            executablePath: settings.codexExecutablePath,
            environmentOverrides: environmentOverrides
        )
    }

    private func combinedFailureText(output: String, errorOutput: String) -> String {
        [errorOutput, output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n")
    }

    private func maybeAutoShift(_ ticket: Ticket, completedAt: Date) throws -> Ticket {
        guard ticket.autoShiftOnSuccess else {
            return ticket
        }

        let state = ticket.phaseState(for: ticket.column)
        guard state.executionState == .completed else {
            return ticket
        }

        return try shiftCompletedTicket(ticket, movedAt: completedAt)
    }

    private func shiftCompletedTicket(
        _ ticket: Ticket,
        movedAt: Date = .now
    ) throws -> Ticket {
        let state = ticket.phaseState(for: ticket.column)
        guard state.executionState == .completed else {
            throw TicketWorkflowError.currentPhaseIncomplete(ticket.column)
        }

        if let nextPhase = ticket.column.next {
            return try workflow.move(ticket, to: nextPhase, movedAt: movedAt)
        }

        var completedTicket = ticket
        completedTicket.completedAt = movedAt
        completedTicket.updatedAt = movedAt
        return completedTicket
    }

    private func beginLiveOutput(for request: AgentRunRequest, startedAt: Date) {
        livePhaseOutputs[liveOutputKey(for: request)] = LivePhaseOutput(
            ticketID: request.ticketID,
            phase: request.phase,
            startedAt: startedAt
        )
    }

    private func attachProcess(_ processIdentifier: Int32, to request: AgentRunRequest) {
        let key = liveOutputKey(for: request)
        guard var liveOutput = livePhaseOutputs[key] else {
            return
        }

        liveOutput.processIdentifier = processIdentifier
        liveOutput.lastUpdatedAt = .now
        livePhaseOutputs[key] = liveOutput
        persistOwnedProcess(for: request, processIdentifier: processIdentifier)
    }

    private func appendLiveOutput(_ chunk: AgentOutputChunk, to request: AgentRunRequest) {
        let key = liveOutputKey(for: request)
        guard var liveOutput = livePhaseOutputs[key] else {
            return
        }

        switch chunk.channel {
        case .standardOutput:
            liveOutput.standardOutput.append(chunk.text)
            liveOutput.combinedText.append(chunk.text)
        case .standardError:
            liveOutput.standardError.append(chunk.text)
            liveOutput.combinedText.append(formatStandardError(chunk.text))
        }

        liveOutput.lastUpdatedAt = .now
        livePhaseOutputs[key] = liveOutput
    }

    private func completeLiveOutput(for request: AgentRunRequest, result: AgentRunResult) {
        let key = liveOutputKey(for: request)
        guard var liveOutput = livePhaseOutputs[key] else {
            return
        }

        liveOutput.standardOutput = result.output
        liveOutput.standardError = result.errorOutput
        liveOutput.combinedText = makeCombinedOutput(
            standardOutput: result.output,
            standardError: result.errorOutput
        )
        liveOutput.isRunning = false
        liveOutput.lastUpdatedAt = result.completedAt
        livePhaseOutputs[key] = liveOutput
    }

    private func failLiveOutput(for request: AgentRunRequest, message: String) {
        let key = liveOutputKey(for: request)
        guard var liveOutput = livePhaseOutputs[key] else {
            return
        }

        let formattedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if formattedMessage.isEmpty == false {
            liveOutput.standardError = formattedMessage
            liveOutput.combinedText = makeCombinedOutput(
                standardOutput: liveOutput.standardOutput,
                standardError: formattedMessage
            )
        }
        liveOutput.isRunning = false
        liveOutput.lastUpdatedAt = .now
        livePhaseOutputs[key] = liveOutput
    }

    private func resetLiveOutput(for request: AgentRunRequest) {
        let key = liveOutputKey(for: request)
        livePhaseOutputs[key] = LivePhaseOutput(
            ticketID: request.ticketID,
            phase: request.phase,
            startedAt: livePhaseOutputs[key]?.startedAt ?? .now
        )
    }

    private func liveOutputKey(for request: AgentRunRequest) -> LivePhaseOutputKey {
        LivePhaseOutputKey(ticketID: request.ticketID, phase: request.phase)
    }

    private func makeCombinedOutput(standardOutput: String, standardError: String) -> String {
        let stdout = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = standardError.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (stdout.isEmpty, stderr.isEmpty) {
        case (false, true):
            return standardOutput
        case (true, false):
            return formatStandardError(standardError)
        case (false, false):
            return standardOutput + (standardOutput.hasSuffix("\n") ? "" : "\n") + formatStandardError(standardError)
        case (true, true):
            return ""
        }
    }

    private func formatStandardError(_ text: String) -> String {
        let trailingNewline = text.hasSuffix("\n")
        let formatted = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "[stderr] \($0)" }
            .joined(separator: "\n")

        if trailingNewline {
            return formatted + "\n"
        }
        return formatted
    }

    private func persistOwnedProcess(for request: AgentRunRequest, processIdentifier: Int32) {
        do {
            let updatedTicket = try persistenceStore.updatePhaseState(ticketID: request.ticketID, phase: request.phase) { phaseState in
                phaseState.ownedProcess = OwnedProcessReference(
                    processIdentifier: processIdentifier,
                    executablePath: settings.codexExecutablePath,
                    launchedAt: phaseState.lastStartedAt ?? .now
                )
            }
            if let updatedTicket {
                replaceTicketInMemory(updatedTicket)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markPhaseRecovered(ticketID: UUID, phase: TicketPhase, recoveryMessage: String) {
        do {
            let recoveredTicket = try persistenceStore.updatePhaseState(ticketID: ticketID, phase: phase) { phaseState in
                let existing = phaseState.capturedError.trimmingCharacters(in: .whitespacesAndNewlines)
                let addition = recoveryMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                phaseState.executionState = .failed
                phaseState.lastCompletedAt = .now
                phaseState.ownedProcess = nil
                phaseState.capturedError = [existing, addition]
                    .filter { $0.isEmpty == false }
                    .joined(separator: existing.isEmpty ? "" : "\n\n")
            }

            livePhaseOutputs.removeValue(forKey: LivePhaseOutputKey(ticketID: ticketID, phase: phase))
            if recoveredTicket == nil {
                errorMessage = "Ticket not found."
            } else {
                reload()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceTicketInMemory(_ updatedTicket: Ticket) {
        if let index = tickets.firstIndex(where: { $0.id == updatedTicket.id }) {
            tickets[index] = updatedTicket
            tickets.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    func performErrorRecoveryAction() {
        guard let errorRecoveryAction else {
            return
        }

        clearError()

        switch errorRecoveryAction {
        case let .clearRunningState(ticketID, phase):
            clearStuckRunningState(ticketID: ticketID, phase: phase)
        }
    }

    private func presentError(_ message: String, recoveryAction: ErrorRecoveryAction? = nil) {
        errorMessage = message
        errorRecoveryAction = recoveryAction
    }
}

private struct CodexExecutionOutcome {
    let result: AgentRunResult
    let authMethod: CodexAuthMethod
    let didFallbackFromSubscription: Bool
}

private struct CodexExecutionAttemptError: LocalizedError {
    let message: String
    let authMethod: CodexAuthMethod
    let didFallbackFromSubscription: Bool

    var errorDescription: String? {
        message
    }
}

private struct OpenAICredentialsStore {
    let service: String
    let account: String

    func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let token = String(data: data, encoding: .utf8)
            else {
                throw OpenAICredentialsStoreError.invalidStoredToken
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAICredentialsStoreError.keychainFailure(status)
        }
    }

    func saveToken(_ token: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.isEmpty == false else {
            try deleteToken()
            return
        }

        let data = Data(trimmedToken.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenAICredentialsStoreError.keychainFailure(addStatus)
            }
        default:
            throw OpenAICredentialsStoreError.keychainFailure(updateStatus)
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAICredentialsStoreError.keychainFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

private enum OpenAICredentialsStoreError: LocalizedError {
    case invalidStoredToken
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredToken:
            return "Stored OpenAI API token could not be read from Keychain."
        case let .keychainFailure(status):
            let fallback = "Keychain operation failed with status \(status)."
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "\(fallback) \(message)"
            }
            return fallback
        }
    }
}
