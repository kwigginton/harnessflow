import Combine
import Foundation
import SwiftData
import HarnessflowCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var settings: AppSettings
    @Published var selectedTicketID: UUID?
    @Published var errorMessage: String?

    private let persistenceStore: PersistenceStore
    private let workflow = TicketWorkflow()
    private let executionService = TicketExecutionService()

    init(modelContainer: ModelContainer, defaultWorkingDirectory: String) {
        self.persistenceStore = PersistenceStore(
            modelContainer: modelContainer,
            defaultWorkingDirectory: defaultWorkingDirectory
        )
        self.settings = AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
        reload()
    }

    var selectedTicket: Ticket? {
        tickets.first(where: { $0.id == selectedTicketID })
    }

    func selectTicket(_ id: UUID?) {
        selectedTicketID = id
    }

    func clearError() {
        errorMessage = nil
    }

    func reload() {
        do {
            settings = try persistenceStore.loadSettings()
            tickets = try persistenceStore.loadTickets()
            if let selectedTicketID, tickets.contains(where: { $0.id == selectedTicketID }) == false {
                self.selectedTicketID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTicket(title: String, detailsText: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            errorMessage = "Ticket title cannot be empty."
            return
        }

        do {
            let ticket = try persistenceStore.createTicket(title: trimmedTitle, detailsText: detailsText)
            reload()
            selectedTicketID = ticket.id
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

        do {
            let updated = try workflow.move(ticket, to: phase)
            try persistenceStore.upsert(ticket: updated)
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
        researchModel: String,
        planModel: String,
        implementModel: String,
        reviewModel: String
    ) {
        let draft = AppSettings(
            codexExecutablePath: codexExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultWorkingDirectory: defaultWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
            phaseModels: PhaseModelSelection(
                research: researchModel.trimmingCharacters(in: .whitespacesAndNewlines),
                plan: planModel.trimmingCharacters(in: .whitespacesAndNewlines),
                implement: implementModel.trimmingCharacters(in: .whitespacesAndNewlines),
                review: reviewModel.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let ticket = tickets.first(where: { $0.id == ticketID }) else {
            return
        }

        let provider = CodexCLIProvider(executablePath: settings.codexExecutablePath)
        var request: AgentRunRequest?

        do {
            let preparedRequest = try executionService.makeRequest(for: ticket, settings: settings)
            request = preparedRequest
            let runningTicket = executionService.markRunning(ticket: ticket, request: preparedRequest)
            try persistenceStore.upsert(ticket: runningTicket)
            reload()

            let result = try await provider.run(request: preparedRequest)
            let completedTicket = executionService.applyResult(
                ticket: runningTicket,
                request: preparedRequest,
                result: result
            )
            try persistenceStore.upsert(ticket: completedTicket)
            reload()
        } catch {
            if let request {
                do {
                    let currentTicket = try persistenceStore.ticket(withID: ticketID) ?? ticket
                    let failedTicket = executionService.applyFailure(
                        ticket: currentTicket,
                        request: request,
                        errorMessage: error.localizedDescription
                    )
                    try persistenceStore.upsert(ticket: failedTicket)
                    reload()
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
