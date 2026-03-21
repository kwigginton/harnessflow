import Foundation
import SwiftData
import HarnessflowCore

@MainActor
final class PersistenceStore {
    private let modelContainer: ModelContainer
    private let defaultWorkingDirectory: String

    init(modelContainer: ModelContainer, defaultWorkingDirectory: String) {
        self.modelContainer = modelContainer
        self.defaultWorkingDirectory = defaultWorkingDirectory
        try? bootstrapSettingsIfNeeded()
    }

    var context: ModelContext {
        modelContainer.mainContext
    }

    func loadTickets() throws -> [Ticket] {
        let descriptor = FetchDescriptor<TicketEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func loadSettings() throws -> AppSettings {
        try bootstrapSettingsIfNeeded()
        return try fetchSettingsEntity()?.toDomain()
            ?? AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
    }

    func ticket(withID id: UUID) throws -> Ticket? {
        try fetchTicketEntity(id: id)?.toDomain()
    }

    func createTicket(title: String, detailsText: String) throws -> Ticket {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ticket = Ticket(
            title: trimmedTitle,
            detailsText: detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let entity = TicketEntity(ticket: ticket)
        context.insert(entity)
        try context.save()
        return ticket
    }

    func savePrompt(ticketID: UUID, phase: TicketPhase, prompt: String) throws {
        guard let entity = try fetchTicketEntity(id: ticketID) else {
            return
        }

        if let phaseEntity = entity.phaseStates.first(where: { $0.phaseValue == phase.rawValue }) {
            phaseEntity.prompt = prompt
        }
        entity.updatedAt = .now
        try context.save()
    }

    func upsert(ticket: Ticket) throws {
        if let entity = try fetchTicketEntity(id: ticket.id) {
            entity.update(from: ticket)
        } else {
            context.insert(TicketEntity(ticket: ticket))
        }
        try context.save()
    }

    func saveSettings(_ settings: AppSettings) throws {
        if let entity = try fetchSettingsEntity() {
            entity.update(from: settings)
        } else {
            context.insert(SettingsEntity(settings: settings))
        }
        try context.save()
    }

    private func fetchTicketEntity(id: UUID) throws -> TicketEntity? {
        let descriptor = FetchDescriptor<TicketEntity>(
            predicate: #Predicate<TicketEntity> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchSettingsEntity() throws -> SettingsEntity? {
        let descriptor = FetchDescriptor<SettingsEntity>(
            predicate: #Predicate<SettingsEntity> { $0.key == "default" }
        )
        return try context.fetch(descriptor).first
    }

    private func bootstrapSettingsIfNeeded() throws {
        guard try fetchSettingsEntity() == nil else {
            return
        }

        let settings = AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
        context.insert(SettingsEntity(settings: settings))
        try context.save()
    }
}
