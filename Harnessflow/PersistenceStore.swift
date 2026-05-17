import Foundation
import SwiftData
import HarnessflowCore

enum PersistenceStoreError: LocalizedError {
    case missingProject(UUID)
    case duplicateActiveProject(String)

    var errorDescription: String? {
        switch self {
        case let .missingProject(id):
            "Project not found: \(id.uuidString)"
        case let .duplicateActiveProject(path):
            "A working directory row already exists for \(path)."
        }
    }
}

@MainActor
final class PersistenceStore {
    private let modelContainer: ModelContainer
    private let defaultWorkingDirectory: String

    init(modelContainer: ModelContainer, defaultWorkingDirectory: String) {
        self.modelContainer = modelContainer
        self.defaultWorkingDirectory = defaultWorkingDirectory
        try? bootstrapIfNeeded()
    }

    var context: ModelContext {
        modelContainer.mainContext
    }

    func loadProjects() throws -> [ProjectRecord] {
        try bootstrapIfNeeded()
        let descriptor = FetchDescriptor<ProjectEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
            .filter { $0.isArchived == false }
            .map { $0.toRecord() }
    }

    func loadArchivedProjects() throws -> [ProjectRecord] {
        try bootstrapIfNeeded()
        let descriptor = FetchDescriptor<ProjectEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
            .filter(\.isArchived)
            .map { $0.toRecord() }
    }

    func loadTickets(projectID: UUID) throws -> [Ticket] {
        try bootstrapIfNeeded()
        let descriptor = FetchDescriptor<TicketEntity>(
            predicate: #Predicate<TicketEntity> { ticket in
                ticket.project?.id == projectID
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func loadSettings() throws -> AppSettings {
        try bootstrapIfNeeded()
        return try fetchSettingsEntity()?.toDomain()
            ?? AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
    }

    func loadSelectedProjectID() throws -> UUID? {
        try bootstrapIfNeeded()
        return try fetchSettingsEntity()?.selectedProjectID
    }

    func ticket(withID id: UUID) throws -> Ticket? {
        try bootstrapIfNeeded()
        return try fetchTicketEntity(id: id)?.toDomain()
    }

    func createProject(name: String, workingDirectory: String) throws -> ProjectRecord {
        try bootstrapIfNeeded()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDirectory = normalizedPath(trimmedDirectory)

        if let existing = try fetchProjectEntity(workingDirectory: normalizedDirectory) {
            if existing.isArchived {
                existing.update(
                    name: trimmedName,
                    workingDirectory: trimmedDirectory,
                    isArchived: false
                )
                try context.save()
                return existing.toRecord()
            }

            throw PersistenceStoreError.duplicateActiveProject(existing.workingDirectory)
        }

        let now = Date()
        let entity = ProjectEntity(
            name: trimmedName,
            workingDirectory: trimmedDirectory,
            createdAt: now,
            updatedAt: now
        )
        context.insert(entity)
        try context.save()
        return entity.toRecord()
    }

    func archiveProject(projectID: UUID) throws -> ProjectRecord {
        try bootstrapIfNeeded()
        guard let entity = try fetchProjectEntity(id: projectID) else {
            throw PersistenceStoreError.missingProject(projectID)
        }

        entity.isArchived = true
        entity.updatedAt = .now
        try context.save()
        return entity.toRecord()
    }

    func unarchiveProject(projectID: UUID) throws -> ProjectRecord {
        try bootstrapIfNeeded()
        guard let entity = try fetchProjectEntity(id: projectID) else {
            throw PersistenceStoreError.missingProject(projectID)
        }

        entity.isArchived = false
        entity.updatedAt = .now
        try context.save()
        return entity.toRecord()
    }

    func updateProjectDirectory(projectID: UUID, workingDirectory: String) throws -> ProjectRecord {
        try bootstrapIfNeeded()
        guard let entity = try fetchProjectEntity(id: projectID) else {
            throw PersistenceStoreError.missingProject(projectID)
        }

        entity.update(
            name: entity.name,
            workingDirectory: workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try context.save()
        return entity.toRecord()
    }

    func saveSelectedProjectID(_ id: UUID?) throws {
        try bootstrapIfNeeded()
        if let entity = try fetchSettingsEntity() {
            entity.selectedProjectID = id
            try context.save()
        }
    }

    func createTicket(
        title: String,
        detailsText: String,
        projectID: UUID,
        initialPhase: TicketPhase = .research,
        autoShiftOnSuccess: Bool = false
    ) throws -> Ticket {
        try bootstrapIfNeeded()
        guard let project = try fetchProjectEntity(id: projectID) else {
            throw PersistenceStoreError.missingProject(projectID)
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ticket = Ticket(
            title: trimmedTitle,
            detailsText: detailsText.trimmingCharacters(in: .whitespacesAndNewlines),
            column: initialPhase,
            autoShiftOnSuccess: autoShiftOnSuccess
        )
        let entity = TicketEntity(ticket: ticket, project: project)
        context.insert(entity)
        try context.save()
        return ticket
    }

    func savePrompt(ticketID: UUID, phase: TicketPhase, prompt: String) throws {
        try bootstrapIfNeeded()
        guard let entity = try fetchTicketEntity(id: ticketID) else {
            return
        }

        if let phaseEntity = entity.phaseStates.first(where: { $0.phaseValue == phase.rawValue }) {
            phaseEntity.prompt = prompt
        }
        entity.updatedAt = .now
        try context.save()
    }

    func updatePhaseState(
        ticketID: UUID,
        phase: TicketPhase,
        mutate: (inout TicketPhaseState) -> Void
    ) throws -> Ticket? {
        try bootstrapIfNeeded()
        guard let entity = try fetchTicketEntity(id: ticketID) else {
            return nil
        }

        var ticket = entity.toDomain()
        var phaseState = ticket.phaseState(for: phase)
        mutate(&phaseState)
        ticket.updatePhaseState(phaseState)
        ticket.updatedAt = .now
        entity.update(from: ticket)
        try context.save()
        return ticket
    }

    func upsert(ticket: Ticket, projectID: UUID) throws {
        try bootstrapIfNeeded()
        let project = try fetchProjectEntity(id: projectID)
        guard let project else {
            throw PersistenceStoreError.missingProject(projectID)
        }

        if let entity = try fetchTicketEntity(id: ticket.id) {
            entity.update(from: ticket)
            entity.project = project
        } else {
            context.insert(TicketEntity(ticket: ticket, project: project))
        }
        try context.save()
    }

    func saveSettings(_ settings: AppSettings) throws {
        try bootstrapIfNeeded()
        if let entity = try fetchSettingsEntity() {
            entity.update(from: settings)
        } else {
            context.insert(SettingsEntity(settings: settings))
        }
        try context.save()
    }

    private func fetchProjectEntity(id: UUID) throws -> ProjectEntity? {
        let descriptor = FetchDescriptor<ProjectEntity>(
            predicate: #Predicate<ProjectEntity> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchProjectEntity(workingDirectory normalizedWorkingDirectory: String) throws -> ProjectEntity? {
        let descriptor = FetchDescriptor<ProjectEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).first { project in
            normalizedPath(project.workingDirectory) == normalizedWorkingDirectory
        }
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

    private func bootstrapIfNeeded() throws {
        var didChange = false
        let settingsEntity: SettingsEntity

        if let existingSettings = try fetchSettingsEntity() {
            settingsEntity = existingSettings
        } else {
            let settings = AppSettings(defaultWorkingDirectory: defaultWorkingDirectory)
            let entity = SettingsEntity(settings: settings)
            context.insert(entity)
            settingsEntity = entity
            didChange = true
        }

        let projectDescriptor = FetchDescriptor<ProjectEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        var projects = try context.fetch(projectDescriptor)

        let orphanDescriptor = FetchDescriptor<TicketEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let orphanTickets = try context.fetch(orphanDescriptor).filter { $0.project == nil }

        if projects.isEmpty {
            let fallbackDirectory = resolvedDefaultProjectDirectory(from: settingsEntity.defaultWorkingDirectory)
            let project = ProjectEntity(
                name: defaultProjectName(for: fallbackDirectory),
                workingDirectory: fallbackDirectory
            )
            context.insert(project)
            projects = [project]
            didChange = true
        }

        if let migrationProject = projects.first, orphanTickets.isEmpty == false {
            for ticket in orphanTickets {
                ticket.project = migrationProject
            }
            didChange = true
        }

        let activeProjects = projects.filter { $0.isArchived == false }
        let projectIDs = Set(activeProjects.map(\.id))
        if let selectedProjectID = settingsEntity.selectedProjectID, projectIDs.contains(selectedProjectID) {
            // Keep the persisted selection.
        } else {
            settingsEntity.selectedProjectID = activeProjects.first?.id
            didChange = true
        }

        if settingsEntity.fillMissingPhasePromptsFromDefaults() {
            didChange = true
        }
        if settingsEntity.normalizeAuthStrategy() {
            didChange = true
        }
        if settingsEntity.normalizeProviderSelection() {
            didChange = true
        }
        if settingsEntity.migrateLegacyCodexModelDefaultsIfNeeded() {
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }

    private func resolvedDefaultProjectDirectory(from settingsDirectory: String) -> String {
        let trimmed = settingsDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        return defaultWorkingDirectory
    }

    private func defaultProjectName(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "Default Project"
        }

        let lastPathComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        return lastPathComponent.isEmpty ? "Default Project" : lastPathComponent
    }

    private func normalizedPath(_ path: String) -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return NSString(string: expandedPath).standardizingPath
    }
}
