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

    struct BoardTicketSummary: Identifiable, Equatable {
        private static let detailsPreviewLimit = 240

        let id: UUID
        let projectID: UUID
        let title: String
        let detailsPreview: String
        let column: TicketPhase
        let isDone: Bool
        let completedAt: Date?
        let updatedAt: Date
        let currentExecutionState: PhaseExecutionState
        let needsFinalAdjustments: Bool

        init(ticket: Ticket, projectID: UUID) {
            let currentState = ticket.phaseState(for: ticket.column)
            self.id = ticket.id
            self.projectID = projectID
            self.title = ticket.title
            self.detailsPreview = Self.makeDetailsPreview(from: ticket.detailsText)
            self.column = ticket.column
            self.isDone = ticket.isDone
            self.completedAt = ticket.completedAt
            self.updatedAt = ticket.updatedAt
            self.currentExecutionState = currentState.executionState
            self.needsFinalAdjustments = currentState.needsFinalAdjustments
        }

        private static func makeDetailsPreview(from detailsText: String) -> String {
            let collapsed = detailsText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")

            guard collapsed.count > detailsPreviewLimit else {
                return collapsed
            }

            return String(collapsed.prefix(detailsPreviewLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
    }

    struct DirectoryBoardRow: Identifiable, Equatable {
        let project: ProjectRecord
        let activeTicketsByPhase: [TicketPhase: [BoardTicketSummary]]
        let doneTickets: [BoardTicketSummary]
        let ticketCount: Int

        var id: UUID { project.id }

        func tickets(for phase: TicketPhase) -> [BoardTicketSummary] {
            activeTicketsByPhase[phase] ?? []
        }
    }

    struct ArchivedDirectorySummary: Identifiable, Equatable {
        let project: ProjectRecord
        let totalCount: Int
        let activeCount: Int
        let doneCount: Int
        let runningCount: Int
        let researchCount: Int
        let planCount: Int
        let implementCount: Int
        let reviewCount: Int

        var id: UUID { project.id }
    }

    @MainActor
    final class TicketSelectionState: ObservableObject {
        @Published private(set) var selectedTicketID: UUID?
        @Published private(set) var selectedTicketSummary: BoardTicketSummary?
        @Published private(set) var selectedTicketDetail: Ticket?

        func select(id: UUID?, summary: BoardTicketSummary?) {
            selectedTicketID = id
            selectedTicketSummary = summary
            selectedTicketDetail = nil
        }

        func setDetail(_ ticket: Ticket?) {
            guard selectedTicketID == ticket?.id else {
                return
            }

            selectedTicketDetail = ticket
        }

        func clear() {
            selectedTicketID = nil
            selectedTicketSummary = nil
            selectedTicketDetail = nil
        }
    }

    private struct LivePhaseOutputKey: Hashable {
        let ticketID: UUID
        let phase: TicketPhase
    }

    private struct PendingLiveOutput {
        var standardOutput = ""
        var standardError = ""
        var combinedText = ""
    }

    private static let liveOutputFlushInterval: Duration = .milliseconds(125)
    private static let liveOutputCharacterLimit = 80_000

    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var directoryBoardRows: [DirectoryBoardRow] = []
    @Published private(set) var archivedDirectorySummaries: [ArchivedDirectorySummary] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var selectedProjectID: UUID?
    let selection = TicketSelectionState()
    @Published var errorMessage: String?
    @Published private(set) var errorRecoveryAction: ErrorRecoveryAction?
    @Published private(set) var hasOpenAIAPIToken = false
    @Published private(set) var hasAnthropicAPIToken = false
    @Published private(set) var hasLinearAPIToken = false
    @Published private(set) var linearValidationMessage = "Linear token has not been checked yet."
    @Published private(set) var codexLoginStatus: CodexLoginStatus = .unknown("Codex login status has not been checked yet.")
    @Published private var livePhaseOutputs: [LivePhaseOutputKey: LivePhaseOutput] = [:]
    private var pendingLiveOutputChunks: [LivePhaseOutputKey: PendingLiveOutput] = [:]
    private var liveOutputFlushTasks: [LivePhaseOutputKey: Task<Void, Never>] = [:]
    private var ticketProjectIDs: [UUID: UUID] = [:]
    private var selectedDetailLoadTask: Task<Void, Never>?

    private let persistenceStore: PersistenceStore
    private let credentialsStore: KeychainTokenStore
    private let anthropicCredentialsStore: KeychainTokenStore
    private let linearCredentialsStore: KeychainTokenStore
    private let linearIssueImporter: any LinearIssueImporting
    private let workflow = TicketWorkflow()
    private let executionService = TicketExecutionService()
    private let processSupervisor = OwnedProcessSupervisor()

    init(modelContainer: ModelContainer, defaultWorkingDirectory: String) {
        self.persistenceStore = PersistenceStore(
            modelContainer: modelContainer,
            defaultWorkingDirectory: defaultWorkingDirectory
        )
        let keychainService = Bundle.main.bundleIdentifier ?? "com.kenw.harnessflow"
        self.credentialsStore = KeychainTokenStore(
            service: keychainService,
            account: "openai.api-token",
            tokenDescription: "OpenAI API token"
        )
        self.anthropicCredentialsStore = KeychainTokenStore(
            service: keychainService,
            account: "anthropic.api-token",
            tokenDescription: "Anthropic API token"
        )
        self.linearCredentialsStore = KeychainTokenStore(
            service: keychainService,
            account: "linear.api-token",
            tokenDescription: "Linear API token"
        )
        self.linearIssueImporter = LinearGraphQLClient()
        self.settings = AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
        reload()
        refreshCodexLoginStatus()
    }

    var selectedTicketID: UUID? {
        selection.selectedTicketID
    }

    var selectedTicket: Ticket? {
        selection.selectedTicketDetail
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
        selectedDetailLoadTask?.cancel()

        guard let id else {
            selection.clear()
            return
        }

        selection.select(id: id, summary: boardTicketSummary(withID: id))
        selectedDetailLoadTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false, self.selection.selectedTicketID == id else {
                return
            }

            self.selection.setDetail(self.ticket(withID: id))
        }
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
            let archivedProjects = try persistenceStore.loadArchivedProjects()
            selectedProjectID = try persistenceStore.loadSelectedProjectID()

            var loadedTickets: [Ticket] = []
            var loadedTicketProjectIDs: [UUID: UUID] = [:]
            for project in projects {
                let projectTickets = try persistenceStore.loadTickets(projectID: project.id)
                loadedTickets.append(contentsOf: projectTickets)
                for ticket in projectTickets {
                    loadedTicketProjectIDs[ticket.id] = project.id
                }
            }
            tickets = loadedTickets.sorted { $0.updatedAt > $1.updatedAt }
            ticketProjectIDs = loadedTicketProjectIDs
            directoryBoardRows = makeDirectoryBoardRows(
                projects: projects,
                tickets: tickets,
                ticketProjectIDs: ticketProjectIDs
            )
            archivedDirectorySummaries = try archivedProjects.map { project in
                makeArchivedDirectorySummary(
                    project: project,
                    tickets: try persistenceStore.loadTickets(projectID: project.id)
                )
            }

            if let selectedTicketID {
                if tickets.contains(where: { $0.id == selectedTicketID }) {
                    selectTicket(selectedTicketID)
                } else {
                    selectTicket(nil)
                }
            }
            hasOpenAIAPIToken = try credentialsStore.loadToken()?.isEmpty == false
            hasAnthropicAPIToken = try anthropicCredentialsStore.loadToken()?.isEmpty == false
            hasLinearAPIToken = try linearCredentialsStore.loadToken()?.isEmpty == false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCodexLoginStatus() {
        let executablePath = settings.codexExecutablePath
        codexLoginStatus = .unknown("Checking Codex login status...")

        Task { [weak self] in
            let status = await Task.detached {
                CodexCLIProvider(executablePath: executablePath).readLoginStatus()
            }.value
            self?.codexLoginStatus = status
        }
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

    func loadAnthropicAPIToken() -> String {
        do {
            return try anthropicCredentialsStore.loadToken() ?? ""
        } catch {
            errorMessage = error.localizedDescription
            return ""
        }
    }

    func saveAnthropicAPIToken(_ token: String) {
        do {
            try anthropicCredentialsStore.saveToken(token)
            hasAnthropicAPIToken = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAnthropicAPIToken() {
        do {
            try anthropicCredentialsStore.deleteToken()
            hasAnthropicAPIToken = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadLinearAPIToken() -> String {
        do {
            return try linearCredentialsStore.loadToken() ?? ""
        } catch {
            errorMessage = error.localizedDescription
            return ""
        }
    }

    func saveLinearAPIToken(_ token: String) {
        do {
            try linearCredentialsStore.saveToken(token)
            hasLinearAPIToken = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            linearValidationMessage = hasLinearAPIToken
                ? "Linear token saved in Keychain."
                : "No Linear token saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteLinearAPIToken() {
        do {
            try linearCredentialsStore.deleteToken()
            hasLinearAPIToken = false
            linearValidationMessage = "No Linear token saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func validateLinearAPIToken() async {
        errorMessage = nil

        do {
            let token = try linearCredentialsStore.loadToken() ?? ""
            let viewer = try await linearIssueImporter.validateToken(token)
            linearValidationMessage = "Connected to Linear as \(viewer.name)."
            hasLinearAPIToken = true
        } catch {
            linearValidationMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func importLinearIssue(identifier: String) async throws -> LinearIssueImport {
        errorMessage = nil
        do {
            let token = try linearCredentialsStore.loadToken() ?? ""
            let issue = try await linearIssueImporter.importIssue(identifier: identifier, apiToken: token)
            hasLinearAPIToken = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            return issue
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createTicket(
        title: String,
        detailsText: String,
        projectID: UUID,
        initialPhase: TicketPhase = .research,
        autoShiftOnSuccess: Bool = false
    ) {
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            errorMessage = "Ticket title cannot be empty."
            return
        }

        guard projects.contains(where: { $0.id == projectID }) else {
            errorMessage = "Choose a working directory before creating a ticket."
            return
        }

        do {
            let ticket = try persistenceStore.createTicket(
                title: trimmedTitle,
                detailsText: detailsText,
                projectID: projectID,
                initialPhase: initialPhase,
                autoShiftOnSuccess: autoShiftOnSuccess
            )
            reload()
            selectTicket(ticket.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(name: String, workingDirectory: String) {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false else {
            errorMessage = "Working directory name cannot be empty."
            return
        }
        guard trimmedDirectory.isEmpty == false else {
            errorMessage = "Working directory path cannot be empty."
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

    func removeDirectoryRow(projectID: UUID) {
        errorMessage = nil

        let projectTickets = tickets.filter { ticketProjectIDs[$0.id] == projectID }
        let hasRunningPhase = projectTickets.contains { ticket in
            ticket.phaseStates.contains { $0.executionState == .running }
        }
        guard hasRunningPhase == false else {
            errorMessage = "Stop running phases before removing this working directory row."
            return
        }

        do {
            _ = try persistenceStore.archiveProject(projectID: projectID)
            if let selectedTicketID, ticketProjectIDs[selectedTicketID] == projectID {
                selectTicket(nil)
            }
            if selectedProjectID == projectID {
                try persistenceStore.saveSelectedProjectID(nil)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreDirectoryRow(projectID: UUID) {
        errorMessage = nil

        do {
            let project = try persistenceStore.unarchiveProject(projectID: projectID)
            try persistenceStore.saveSelectedProjectID(project.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedProjectDirectory(_ workingDirectory: String) {
        errorMessage = nil
        guard let selectedProjectID else {
            errorMessage = "Select a working directory before choosing a folder."
            return
        }

        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDirectory.isEmpty == false else {
            errorMessage = "Working directory path cannot be empty."
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
    func moveTicket(id: UUID, to phase: TicketPhase, projectID: UUID) -> Bool {
        guard let ticket = tickets.first(where: { $0.id == id }) else {
            return false
        }
        guard ticketProjectIDs[id] == projectID else {
            errorMessage = "Tickets can only move within their working directory row."
            return false
        }

        do {
            let updated = try workflow.move(ticket, to: phase)
            try persistenceStore.upsert(ticket: updated, projectID: projectID)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func shiftTicketForward(id: UUID, projectID: UUID) -> Bool {
        guard let ticket = tickets.first(where: { $0.id == id }) else {
            return false
        }
        guard ticketProjectIDs[id] == projectID else {
            errorMessage = "Tickets can only move within their working directory row."
            return false
        }

        do {
            let shifted = try shiftCompletedTicket(ticket)
            try persistenceStore.upsert(ticket: shifted, projectID: projectID)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func completeTicket(id: UUID, projectID: UUID) -> Bool {
        guard let ticket = tickets.first(where: { $0.id == id }) else {
            return false
        }
        guard ticketProjectIDs[id] == projectID else {
            errorMessage = "Tickets can only be completed within their working directory row."
            return false
        }
        guard ticket.phaseStates.contains(where: { $0.executionState == .running }) == false else {
            errorMessage = "Stop running phases before marking this ticket completed."
            return false
        }

        do {
            let completed = workflow.complete(ticket)
            try persistenceStore.upsert(ticket: completed, projectID: projectID)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveSettings(
        selectedProviderKind: AgentProviderKind,
        codexExecutablePath: String,
        claudeExecutablePath: String,
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
            selectedProviderKind: selectedProviderKind,
            codexExecutablePath: codexExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
            claudeExecutablePath: claudeExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
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
            let project = project(forTicketID: ticketID)
        else {
            return
        }

        let projectID = project.id
        var request: AgentRunRequest?

        do {
            let preparedRequest = try executionService.makeRequest(
                for: ticket,
                settings: settings,
                workingDirectoryOverride: project.workingDirectory
            )
            request = preparedRequest
            let executionPlan = try await makeExecutionPlan(for: preparedRequest)
            let runningTicket = executionService.markRunning(ticket: ticket, request: preparedRequest)
            try persistenceStore.upsert(ticket: runningTicket, projectID: projectID)
            beginLiveOutput(for: preparedRequest, startedAt: runningTicket.phaseState(for: preparedRequest.phase).lastStartedAt ?? .now)
            reload()

            let execution = try await executeRequest(
                preparedRequest,
                plan: executionPlan
            )
            let completedTicket = executionService.applyResult(
                ticket: runningTicket,
                request: preparedRequest,
                result: execution.result,
                providerKind: execution.providerKind,
                authMethod: execution.codexAuthMethod,
                authMethodDescription: execution.authMethodDescription,
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
                        providerKind: executionError?.providerKind ?? settings.selectedProviderKind,
                        authMethod: executionError?.codexAuthMethod ?? .unknown,
                        authMethodDescription: executionError?.authMethodDescription ?? "Unknown",
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

    func submitAnswersAndContinue(ticketID: UUID, answers: [AgentAnswer]) async {
        guard
            var ticket = tickets.first(where: { $0.id == ticketID }),
            let project = project(forTicketID: ticketID)
        else {
            return
        }

        let phase = ticket.column
        var phaseState = ticket.phaseState(for: phase)
        guard phaseState.pendingQuestions != nil else {
            return
        }

        phaseState.pendingAnswers = answers
        ticket.updatePhaseState(phaseState)

        let projectID = project.id
        var request: AgentRunRequest?

        do {
            let preparedRequest = try executionService.makeContinuationRequest(
                for: ticket,
                settings: settings,
                answers: answers,
                workingDirectoryOverride: project.workingDirectory
            )
            request = preparedRequest
            let executionPlan = try await makeExecutionPlan(for: preparedRequest)
            let runningTicket = executionService.markRunning(ticket: ticket, request: preparedRequest)
            try persistenceStore.upsert(ticket: runningTicket, projectID: projectID)
            beginLiveOutput(for: preparedRequest, startedAt: runningTicket.phaseState(for: preparedRequest.phase).lastStartedAt ?? .now)
            reload()

            let execution = try await executeRequest(
                preparedRequest,
                plan: executionPlan
            )
            let completedTicket = executionService.applyResult(
                ticket: runningTicket,
                request: preparedRequest,
                result: execution.result,
                providerKind: execution.providerKind,
                authMethod: execution.codexAuthMethod,
                authMethodDescription: execution.authMethodDescription,
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
                        providerKind: executionError?.providerKind ?? settings.selectedProviderKind,
                        authMethod: executionError?.codexAuthMethod ?? .unknown,
                        authMethodDescription: executionError?.authMethodDescription ?? "Unknown",
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

    private func resolveCodexLoginStatus() async -> CodexLoginStatus {
        let executablePath = settings.codexExecutablePath
        return await Task.detached {
            CodexCLIProvider(executablePath: executablePath).readLoginStatus()
        }.value
    }

    private func makeExecutionPlan(for request: AgentRunRequest) async throws -> AgentExecutionPlan {
        switch settings.selectedProviderKind {
        case .codex:
            let token = try credentialsStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let loginStatus = await resolveCodexLoginStatus()
            codexLoginStatus = loginStatus
            let resolution = try CodexAuthResolver().resolve(
                strategy: settings.codexAuthStrategy,
                loginStatus: loginStatus,
                hasAPIKey: token?.isEmpty == false,
                model: request.model
            )
            return AgentExecutionPlan(
                providerKind: .codex,
                apiToken: token,
                codexResolution: resolution
            )
        case .claude:
            let token = try anthropicCredentialsStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgentExecutionPlan(
                providerKind: .claude,
                apiToken: token,
                codexResolution: nil
            )
        }
    }

    private func executeRequest(
        _ request: AgentRunRequest,
        plan: AgentExecutionPlan
    ) async throws -> AgentExecutionOutcome {
        switch plan.providerKind {
        case .codex:
            guard let resolution = plan.codexResolution else {
                throw CodexExecutionAttemptError(
                    message: "Codex authentication was not resolved.",
                    providerKind: .codex,
                    codexAuthMethod: .unknown,
                    authMethodDescription: "Unknown",
                    didFallbackFromSubscription: false
                )
            }
            return try await executeCodexRequest(request, apiToken: plan.apiToken, resolution: resolution)
        case .claude:
            return try await executeClaudeRequest(request, apiToken: plan.apiToken)
        }
    }

    private func executeCodexRequest(
        _ request: AgentRunRequest,
        apiToken: String?,
        resolution: CodexAuthResolution
    ) async throws -> AgentExecutionOutcome {
        let trimmedToken = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAPIKey = trimmedToken?.isEmpty == false
        let authResolver = CodexAuthResolver()
        let primaryProvider = makeCodexProvider(
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
                let fallbackProvider = makeCodexProvider(authMethod: .apiKey, apiToken: trimmedToken)
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
                return AgentExecutionOutcome(
                    result: fallbackResult,
                    providerKind: .codex,
                    codexAuthMethod: .apiKey,
                    authMethodDescription: CodexAuthMethod.apiKey.title,
                    didFallbackFromSubscription: true
                )
            }

            return AgentExecutionOutcome(
                result: primaryResult,
                providerKind: .codex,
                codexAuthMethod: resolution.authMethod,
                authMethodDescription: resolution.authMethod.title,
                didFallbackFromSubscription: false
            )
        } catch {
            if authResolver.shouldRetryWithAPIKey(
                after: error.localizedDescription,
                previousResolution: resolution,
                hasAPIKey: hasAPIKey
            ) {
                let fallbackProvider = makeCodexProvider(authMethod: .apiKey, apiToken: trimmedToken)
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
                    return AgentExecutionOutcome(
                        result: fallbackResult,
                        providerKind: .codex,
                        codexAuthMethod: .apiKey,
                        authMethodDescription: CodexAuthMethod.apiKey.title,
                        didFallbackFromSubscription: true
                    )
                } catch {
                    throw CodexExecutionAttemptError(
                        message: error.localizedDescription,
                        providerKind: .codex,
                        codexAuthMethod: .apiKey,
                        authMethodDescription: CodexAuthMethod.apiKey.title,
                        didFallbackFromSubscription: true
                    )
                }
            }

            throw CodexExecutionAttemptError(
                message: error.localizedDescription,
                providerKind: .codex,
                codexAuthMethod: resolution.authMethod,
                authMethodDescription: resolution.authMethod.title,
                didFallbackFromSubscription: false
            )
        }
    }

    private func executeClaudeRequest(
        _ request: AgentRunRequest,
        apiToken: String?
    ) async throws -> AgentExecutionOutcome {
        let provider = makeClaudeProvider(apiToken: apiToken?.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            let result = try await provider.run(
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
            let hasToken = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            return AgentExecutionOutcome(
                result: result,
                providerKind: .claude,
                codexAuthMethod: .unknown,
                authMethodDescription: hasToken ? "Anthropic API Key" : "Claude CLI Session",
                didFallbackFromSubscription: false
            )
        } catch {
            let hasToken = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            throw CodexExecutionAttemptError(
                message: error.localizedDescription,
                providerKind: .claude,
                codexAuthMethod: .unknown,
                authMethodDescription: hasToken ? "Anthropic API Key" : "Claude CLI Session",
                didFallbackFromSubscription: false
            )
        }
    }

    private func makeCodexProvider(
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

    private func makeClaudeProvider(apiToken: String?) -> ClaudeCLIProvider {
        let environmentOverrides: [String: String]
        if let apiToken, apiToken.isEmpty == false {
            environmentOverrides = ["ANTHROPIC_API_KEY": apiToken]
        } else {
            environmentOverrides = [:]
        }

        return ClaudeCLIProvider(
            executablePath: settings.claudeExecutablePath,
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

        return try workflow.completeAfterReview(ticket, completedAt: movedAt)
    }

    private func beginLiveOutput(for request: AgentRunRequest, startedAt: Date) {
        let key = liveOutputKey(for: request)
        pendingLiveOutputChunks.removeValue(forKey: key)
        liveOutputFlushTasks[key]?.cancel()
        liveOutputFlushTasks.removeValue(forKey: key)
        livePhaseOutputs[key] = LivePhaseOutput(
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
        guard livePhaseOutputs[key] != nil else {
            return
        }

        var pending = pendingLiveOutputChunks[key] ?? PendingLiveOutput()
        switch chunk.channel {
        case .standardOutput:
            pending.standardOutput.append(chunk.text)
            pending.combinedText.append(chunk.text)
        case .standardError:
            pending.standardError.append(chunk.text)
            pending.combinedText.append(formatStandardError(chunk.text))
        }
        pendingLiveOutputChunks[key] = pending

        scheduleLiveOutputFlush(for: key)
    }

    private func completeLiveOutput(for request: AgentRunRequest, result: AgentRunResult) {
        let key = liveOutputKey(for: request)
        flushPendingLiveOutput(for: key)
        guard var liveOutput = livePhaseOutputs[key] else {
            return
        }

        liveOutput.standardOutput = result.output.trimmingLeadingCharacters(
            overLimit: Self.liveOutputCharacterLimit
        )
        liveOutput.standardError = result.errorOutput.trimmingLeadingCharacters(
            overLimit: Self.liveOutputCharacterLimit
        )
        liveOutput.combinedText = makeCombinedOutput(
            standardOutput: result.output,
            standardError: result.errorOutput
        ).trimmingLeadingCharacters(
            overLimit: Self.liveOutputCharacterLimit
        )
        liveOutput.isRunning = false
        liveOutput.lastUpdatedAt = result.completedAt
        livePhaseOutputs[key] = liveOutput
    }

    private func failLiveOutput(for request: AgentRunRequest, message: String) {
        let key = liveOutputKey(for: request)
        flushPendingLiveOutput(for: key)
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
        pendingLiveOutputChunks.removeValue(forKey: key)
        liveOutputFlushTasks[key]?.cancel()
        liveOutputFlushTasks.removeValue(forKey: key)
        livePhaseOutputs[key] = LivePhaseOutput(
            ticketID: request.ticketID,
            phase: request.phase,
            startedAt: livePhaseOutputs[key]?.startedAt ?? .now
        )
    }

    private func scheduleLiveOutputFlush(for key: LivePhaseOutputKey) {
        guard liveOutputFlushTasks[key] == nil else {
            return
        }

        liveOutputFlushTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.liveOutputFlushInterval)
            self?.flushScheduledLiveOutput(for: key)
        }
    }

    private func flushScheduledLiveOutput(for key: LivePhaseOutputKey) {
        liveOutputFlushTasks.removeValue(forKey: key)
        flushPendingLiveOutput(for: key)
    }

    private func flushPendingLiveOutput(for key: LivePhaseOutputKey) {
        guard
            let pending = pendingLiveOutputChunks.removeValue(forKey: key),
            var liveOutput = livePhaseOutputs[key]
        else {
            return
        }

        liveOutput.standardOutput.append(pending.standardOutput)
        liveOutput.standardOutput = liveOutput.standardOutput.trimmingLeadingCharacters(
            overLimit: Self.liveOutputCharacterLimit
        )
        liveOutput.standardError.append(pending.standardError)
        liveOutput.standardError = liveOutput.standardError.trimmingLeadingCharacters(
            overLimit: Self.liveOutputCharacterLimit
        )
        liveOutput.combinedText.append(pending.combinedText)
        liveOutput.combinedText = liveOutput.combinedText.trimmingLeadingCharacters(
            overLimit: Self.liveOutputCharacterLimit
        )
        liveOutput.lastUpdatedAt = .now
        livePhaseOutputs[key] = liveOutput
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
                    executablePath: executablePath(for: settings.selectedProviderKind),
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
            directoryBoardRows = makeDirectoryBoardRows(
                projects: projects,
                tickets: tickets,
                ticketProjectIDs: ticketProjectIDs
            )
            if selection.selectedTicketID == updatedTicket.id {
                selectTicket(updatedTicket.id)
            }
        }
    }

    private func boardTicketSummary(withID id: UUID) -> BoardTicketSummary? {
        for row in directoryBoardRows {
            if let summary = TicketPhase.allCases.lazy.compactMap({ row.tickets(for: $0).first(where: { $0.id == id }) }).first {
                return summary
            }

            if let summary = row.doneTickets.first(where: { $0.id == id }) {
                return summary
            }
        }

        guard let ticket = ticket(withID: id), let projectID = ticketProjectIDs[id] else {
            return nil
        }

        return BoardTicketSummary(ticket: ticket, projectID: projectID)
    }

    private func project(forTicketID ticketID: UUID) -> ProjectRecord? {
        guard let projectID = ticketProjectIDs[ticketID] else {
            return nil
        }
        return projects.first(where: { $0.id == projectID })
    }

    private func executablePath(for providerKind: AgentProviderKind) -> String {
        switch providerKind {
        case .codex:
            settings.codexExecutablePath
        case .claude:
            settings.claudeExecutablePath
        }
    }

    private func makeArchivedDirectorySummary(
        project: ProjectRecord,
        tickets: [Ticket]
    ) -> ArchivedDirectorySummary {
        let doneCount = tickets.filter(\.isDone).count
        let activeTickets = tickets.filter { $0.isDone == false }
        return ArchivedDirectorySummary(
            project: project,
            totalCount: tickets.count,
            activeCount: activeTickets.count,
            doneCount: doneCount,
            runningCount: tickets.filter { ticket in
                ticket.phaseStates.contains { $0.executionState == .running }
            }.count,
            researchCount: activeTickets.filter { $0.column == .research }.count,
            planCount: activeTickets.filter { $0.column == .plan }.count,
            implementCount: activeTickets.filter { $0.column == .implement }.count,
            reviewCount: activeTickets.filter { $0.column == .review }.count
        )
    }

    private func makeDirectoryBoardRows(
        projects: [ProjectRecord],
        tickets: [Ticket],
        ticketProjectIDs: [UUID: UUID]
    ) -> [DirectoryBoardRow] {
        let summariesByProject = Dictionary(grouping: tickets.compactMap { ticket -> BoardTicketSummary? in
            guard let projectID = ticketProjectIDs[ticket.id] else {
                return nil
            }
            return BoardTicketSummary(ticket: ticket, projectID: projectID)
        }, by: \.projectID)

        return projects.map { project in
            let projectTickets = summariesByProject[project.id] ?? []
            let activeTickets = projectTickets
                .filter { $0.isDone == false }
                .sorted { $0.updatedAt > $1.updatedAt }
            let doneTickets = projectTickets
                .filter(\.isDone)
                .sorted { lhs, rhs in
                    let lhsDate = lhs.completedAt ?? lhs.updatedAt
                    let rhsDate = rhs.completedAt ?? rhs.updatedAt
                    return lhsDate > rhsDate
                }

            return DirectoryBoardRow(
                project: project,
                activeTicketsByPhase: Dictionary(grouping: activeTickets, by: \.column),
                doneTickets: doneTickets,
                ticketCount: projectTickets.count
            )
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

private struct AgentExecutionPlan {
    let providerKind: AgentProviderKind
    let apiToken: String?
    let codexResolution: CodexAuthResolution?
}

private struct AgentExecutionOutcome {
    let result: AgentRunResult
    let providerKind: AgentProviderKind
    let codexAuthMethod: CodexAuthMethod
    let authMethodDescription: String
    let didFallbackFromSubscription: Bool
}

private struct CodexExecutionAttemptError: LocalizedError {
    let message: String
    let providerKind: AgentProviderKind
    let codexAuthMethod: CodexAuthMethod
    let authMethodDescription: String
    let didFallbackFromSubscription: Bool

    var errorDescription: String? {
        message
    }
}

private struct KeychainTokenStore {
    let service: String
    let account: String
    let tokenDescription: String

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
                throw KeychainTokenStoreError.invalidStoredToken(tokenDescription)
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenStoreError.keychainFailure(status)
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
                throw KeychainTokenStoreError.keychainFailure(addStatus)
            }
        default:
            throw KeychainTokenStoreError.keychainFailure(updateStatus)
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.keychainFailure(status)
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

private enum KeychainTokenStoreError: LocalizedError {
    case invalidStoredToken(String)
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .invalidStoredToken(tokenDescription):
            return "Stored \(tokenDescription) could not be read from Keychain."
        case let .keychainFailure(status):
            let fallback = "Keychain operation failed with status \(status)."
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "\(fallback) \(message)"
            }
            return fallback
        }
    }
}

private extension String {
    func trimmingLeadingCharacters(overLimit limit: Int) -> String {
        guard count > limit else {
            return self
        }

        let startIndex = index(endIndex, offsetBy: -limit)
        return String(self[startIndex...])
    }
}
