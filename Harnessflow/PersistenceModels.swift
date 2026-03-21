import Foundation
import SwiftData
import HarnessflowCore

@Model
final class TicketEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var detailsText: String
    var columnValue: Int
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

    init(
        id: UUID,
        title: String,
        detailsText: String,
        columnValue: Int,
        createdAt: Date,
        updatedAt: Date,
        phaseStates: [PhaseStateEntity] = []
    ) {
        self.id = id
        self.title = title
        self.detailsText = detailsText
        self.columnValue = columnValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phaseStates = phaseStates
    }

    convenience init(ticket: Ticket) {
        self.init(
            id: ticket.id,
            title: ticket.title,
            detailsText: ticket.detailsText,
            columnValue: ticket.column.rawValue,
            createdAt: ticket.createdAt,
            updatedAt: ticket.updatedAt
        )
        phaseStates = ticket.phaseStates.map { PhaseStateEntity(state: $0, ticket: self) }
    }

    func update(from ticket: Ticket) {
        title = ticket.title
        detailsText = ticket.detailsText
        columnValue = ticket.column.rawValue
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt

        let existing = Dictionary(uniqueKeysWithValues: phaseStates.map { ($0.phaseValue, $0) })
        phaseStates = ticket.phaseStates.map { state in
            if let entity = existing[state.phase.rawValue] {
                entity.update(from: state)
                entity.ticket = self
                return entity
            }

            return PhaseStateEntity(state: state, ticket: self)
        }
        .sorted(by: { $0.phaseValue < $1.phaseValue })
    }

    func toDomain() -> Ticket {
        Ticket(
            id: id,
            title: title,
            detailsText: detailsText,
            column: TicketPhase(rawValue: columnValue) ?? .research,
            createdAt: createdAt,
            updatedAt: updatedAt,
            phaseStates: phaseStates
                .sorted(by: { $0.phaseValue < $1.phaseValue })
                .map { $0.toDomain() }
        )
    }
}

@Model
final class PhaseStateEntity {
    @Attribute(.unique) var id: UUID
    var phaseValue: Int
    var executionStateRawValue: String
    var prompt: String
    var lastModel: String
    var lastStartedAt: Date?
    var lastCompletedAt: Date?
    var capturedOutput: String
    var capturedError: String
    var ticket: TicketEntity?
    @Relationship(deleteRule: .cascade, inverse: \PhaseRunEntity.phaseState) var runs: [PhaseRunEntity]

    init(
        id: UUID = UUID(),
        phaseValue: Int,
        executionStateRawValue: String,
        prompt: String,
        lastModel: String,
        lastStartedAt: Date?,
        lastCompletedAt: Date?,
        capturedOutput: String,
        capturedError: String,
        ticket: TicketEntity? = nil,
        runs: [PhaseRunEntity] = []
    ) {
        self.id = id
        self.phaseValue = phaseValue
        self.executionStateRawValue = executionStateRawValue
        self.prompt = prompt
        self.lastModel = lastModel
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
        self.capturedOutput = capturedOutput
        self.capturedError = capturedError
        self.ticket = ticket
        self.runs = runs
    }

    convenience init(state: TicketPhaseState, ticket: TicketEntity? = nil) {
        self.init(
            phaseValue: state.phase.rawValue,
            executionStateRawValue: state.executionState.rawValue,
            prompt: state.prompt,
            lastModel: state.lastModel ?? "",
            lastStartedAt: state.lastStartedAt,
            lastCompletedAt: state.lastCompletedAt,
            capturedOutput: state.capturedOutput,
            capturedError: state.capturedError,
            ticket: ticket
        )
        runs = state.runs.map { PhaseRunEntity(run: $0, phaseState: self) }
    }

    func update(from state: TicketPhaseState) {
        phaseValue = state.phase.rawValue
        executionStateRawValue = state.executionState.rawValue
        prompt = state.prompt
        lastModel = state.lastModel ?? ""
        lastStartedAt = state.lastStartedAt
        lastCompletedAt = state.lastCompletedAt
        capturedOutput = state.capturedOutput
        capturedError = state.capturedError

        let existing = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        runs = state.runs.map { run in
            if let entity = existing[run.id] {
                entity.update(from: run)
                entity.phaseState = self
                return entity
            }

            return PhaseRunEntity(run: run, phaseState: self)
        }
        .sorted(by: { $0.startedAt < $1.startedAt })
    }

    func toDomain() -> TicketPhaseState {
        TicketPhaseState(
            phase: TicketPhase(rawValue: phaseValue) ?? .research,
            executionState: PhaseExecutionState(rawValue: executionStateRawValue) ?? .idle,
            prompt: prompt,
            lastModel: lastModel.isEmpty ? nil : lastModel,
            lastStartedAt: lastStartedAt,
            lastCompletedAt: lastCompletedAt,
            capturedOutput: capturedOutput,
            capturedError: capturedError,
            runs: runs.sorted(by: { $0.startedAt < $1.startedAt }).map { $0.toDomain() }
        )
    }
}

@Model
final class PhaseRunEntity {
    @Attribute(.unique) var id: UUID
    var phaseValue: Int
    var model: String
    var prompt: String
    var outputText: String
    var errorOutputText: String
    var startedAt: Date
    var completedAt: Date
    var success: Bool
    var phaseState: PhaseStateEntity?

    init(
        id: UUID,
        phaseValue: Int,
        model: String,
        prompt: String,
        outputText: String,
        errorOutputText: String,
        startedAt: Date,
        completedAt: Date,
        success: Bool,
        phaseState: PhaseStateEntity? = nil
    ) {
        self.id = id
        self.phaseValue = phaseValue
        self.model = model
        self.prompt = prompt
        self.outputText = outputText
        self.errorOutputText = errorOutputText
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.success = success
        self.phaseState = phaseState
    }

    convenience init(run: PhaseRun, phaseState: PhaseStateEntity? = nil) {
        self.init(
            id: run.id,
            phaseValue: run.phase.rawValue,
            model: run.model,
            prompt: run.prompt,
            outputText: run.output,
            errorOutputText: run.errorOutput,
            startedAt: run.startedAt,
            completedAt: run.completedAt,
            success: run.success,
            phaseState: phaseState
        )
    }

    func update(from run: PhaseRun) {
        phaseValue = run.phase.rawValue
        model = run.model
        prompt = run.prompt
        outputText = run.output
        errorOutputText = run.errorOutput
        startedAt = run.startedAt
        completedAt = run.completedAt
        success = run.success
    }

    func toDomain() -> PhaseRun {
        PhaseRun(
            id: id,
            phase: TicketPhase(rawValue: phaseValue) ?? .research,
            model: model,
            prompt: prompt,
            output: outputText,
            errorOutput: errorOutputText,
            startedAt: startedAt,
            completedAt: completedAt,
            success: success
        )
    }
}

@Model
final class SettingsEntity {
    @Attribute(.unique) var key: String
    var codexExecutablePath: String
    var defaultWorkingDirectory: String
    var researchModel: String
    var planModel: String
    var implementModel: String
    var reviewModel: String

    init(
        key: String = "default",
        codexExecutablePath: String,
        defaultWorkingDirectory: String,
        researchModel: String,
        planModel: String,
        implementModel: String,
        reviewModel: String
    ) {
        self.key = key
        self.codexExecutablePath = codexExecutablePath
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.researchModel = researchModel
        self.planModel = planModel
        self.implementModel = implementModel
        self.reviewModel = reviewModel
    }

    convenience init(settings: AppSettings) {
        self.init(
            codexExecutablePath: settings.codexExecutablePath,
            defaultWorkingDirectory: settings.defaultWorkingDirectory,
            researchModel: settings.phaseModels.research,
            planModel: settings.phaseModels.plan,
            implementModel: settings.phaseModels.implement,
            reviewModel: settings.phaseModels.review
        )
    }

    func update(from settings: AppSettings) {
        codexExecutablePath = settings.codexExecutablePath
        defaultWorkingDirectory = settings.defaultWorkingDirectory
        researchModel = settings.phaseModels.research
        planModel = settings.phaseModels.plan
        implementModel = settings.phaseModels.implement
        reviewModel = settings.phaseModels.review
    }

    func toDomain() -> AppSettings {
        AppSettings(
            codexExecutablePath: codexExecutablePath,
            defaultWorkingDirectory: defaultWorkingDirectory,
            phaseModels: PhaseModelSelection(
                research: researchModel,
                plan: planModel,
                implement: implementModel,
                review: reviewModel
            )
        )
    }
}
