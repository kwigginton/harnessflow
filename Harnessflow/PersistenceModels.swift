import Foundation
import SwiftData
import HarnessflowCore

struct ProjectRecord: Identifiable, Equatable {
    let id: UUID
    let name: String
    let workingDirectory: String
    let createdAt: Date
    let updatedAt: Date
}

enum HarnessflowSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

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
    }
}

enum HarnessflowSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ticket = ticket
            self.runs = runs
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
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var codexExecutablePath: String
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            codexExecutablePath: String,
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.codexExecutablePath = codexExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}

enum HarnessflowSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var didFallbackFromSubscription: Bool = false
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
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            didFallbackFromSubscription: Bool = false,
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
            self.authMethodRawValue = authMethodRawValue
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var codexExecutablePath: String
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            codexExecutablePath: String,
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.codexExecutablePath = codexExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}

enum HarnessflowSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
        var ownedProcessIdentifier: Int?
        var ownedProcessExecutablePath: String?
        var ownedProcessLaunchedAt: Date?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
            ownedProcessIdentifier: Int? = nil,
            ownedProcessExecutablePath: String? = nil,
            ownedProcessLaunchedAt: Date? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ownedProcessIdentifier = ownedProcessIdentifier
            self.ownedProcessExecutablePath = ownedProcessExecutablePath
            self.ownedProcessLaunchedAt = ownedProcessLaunchedAt
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var didFallbackFromSubscription: Bool = false
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
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            didFallbackFromSubscription: Bool = false,
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
            self.authMethodRawValue = authMethodRawValue
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var codexExecutablePath: String
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            codexExecutablePath: String,
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.codexExecutablePath = codexExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}

enum HarnessflowSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var autoShiftOnSuccess: Bool = false
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            autoShiftOnSuccess: Bool,
            completedAt: Date?,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.autoShiftOnSuccess = autoShiftOnSuccess
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
        var ownedProcessIdentifier: Int?
        var ownedProcessExecutablePath: String?
        var ownedProcessLaunchedAt: Date?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
            ownedProcessIdentifier: Int? = nil,
            ownedProcessExecutablePath: String? = nil,
            ownedProcessLaunchedAt: Date? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ownedProcessIdentifier = ownedProcessIdentifier
            self.ownedProcessExecutablePath = ownedProcessExecutablePath
            self.ownedProcessLaunchedAt = ownedProcessLaunchedAt
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var didFallbackFromSubscription: Bool = false
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
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            didFallbackFromSubscription: Bool = false,
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
            self.authMethodRawValue = authMethodRawValue
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var codexExecutablePath: String
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            codexExecutablePath: String,
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.codexExecutablePath = codexExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}

enum HarnessflowSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var isArchived: Bool = false
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var autoShiftOnSuccess: Bool = false
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            autoShiftOnSuccess: Bool,
            completedAt: Date?,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.autoShiftOnSuccess = autoShiftOnSuccess
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
        var ownedProcessIdentifier: Int?
        var ownedProcessExecutablePath: String?
        var ownedProcessLaunchedAt: Date?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
            ownedProcessIdentifier: Int? = nil,
            ownedProcessExecutablePath: String? = nil,
            ownedProcessLaunchedAt: Date? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ownedProcessIdentifier = ownedProcessIdentifier
            self.ownedProcessExecutablePath = ownedProcessExecutablePath
            self.ownedProcessLaunchedAt = ownedProcessLaunchedAt
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var didFallbackFromSubscription: Bool = false
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
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            didFallbackFromSubscription: Bool = false,
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
            self.authMethodRawValue = authMethodRawValue
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var codexExecutablePath: String
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            codexExecutablePath: String,
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.codexExecutablePath = codexExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}


enum HarnessflowSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var isArchived: Bool = false
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var autoShiftOnSuccess: Bool = false
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            autoShiftOnSuccess: Bool,
            completedAt: Date?,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.autoShiftOnSuccess = autoShiftOnSuccess
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
        var ownedProcessIdentifier: Int?
        var ownedProcessExecutablePath: String?
        var ownedProcessLaunchedAt: Date?
        var pendingQuestionsJSON: String?
        var pendingAnswersJSON: String?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
            ownedProcessIdentifier: Int? = nil,
            ownedProcessExecutablePath: String? = nil,
            ownedProcessLaunchedAt: Date? = nil,
            pendingQuestionsJSON: String? = nil,
            pendingAnswersJSON: String? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ownedProcessIdentifier = ownedProcessIdentifier
            self.ownedProcessExecutablePath = ownedProcessExecutablePath
            self.ownedProcessLaunchedAt = ownedProcessLaunchedAt
            self.pendingQuestionsJSON = pendingQuestionsJSON
            self.pendingAnswersJSON = pendingAnswersJSON
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var didFallbackFromSubscription: Bool = false
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
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            didFallbackFromSubscription: Bool = false,
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
            self.authMethodRawValue = authMethodRawValue
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var codexExecutablePath: String
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            codexExecutablePath: String,
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.codexExecutablePath = codexExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}

enum HarnessflowSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var isArchived: Bool = false
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var autoShiftOnSuccess: Bool = false
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            autoShiftOnSuccess: Bool,
            completedAt: Date?,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.autoShiftOnSuccess = autoShiftOnSuccess
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
        var ownedProcessIdentifier: Int?
        var ownedProcessExecutablePath: String?
        var ownedProcessLaunchedAt: Date?
        var pendingQuestionsJSON: String?
        var pendingAnswersJSON: String?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
            ownedProcessIdentifier: Int? = nil,
            ownedProcessExecutablePath: String? = nil,
            ownedProcessLaunchedAt: Date? = nil,
            pendingQuestionsJSON: String? = nil,
            pendingAnswersJSON: String? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ownedProcessIdentifier = ownedProcessIdentifier
            self.ownedProcessExecutablePath = ownedProcessExecutablePath
            self.ownedProcessLaunchedAt = ownedProcessLaunchedAt
            self.pendingQuestionsJSON = pendingQuestionsJSON
            self.pendingAnswersJSON = pendingAnswersJSON
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var providerKindRawValue: String = AgentProviderKind.codex.rawValue
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var authMethodDescription: String = CodexAuthMethod.unknown.title
        var didFallbackFromSubscription: Bool = false
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
            providerKindRawValue: String = AgentProviderKind.codex.rawValue,
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            authMethodDescription: String = CodexAuthMethod.unknown.title,
            didFallbackFromSubscription: Bool = false,
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
            self.providerKindRawValue = providerKindRawValue
            self.authMethodRawValue = authMethodRawValue
            self.authMethodDescription = authMethodDescription
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue
        var codexExecutablePath: String
        var claudeExecutablePath: String = "/opt/homebrew/bin/claude"
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue,
            codexExecutablePath: String,
            claudeExecutablePath: String = "/opt/homebrew/bin/claude",
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.selectedProviderKindRawValue = selectedProviderKindRawValue
            self.codexExecutablePath = codexExecutablePath
            self.claudeExecutablePath = claudeExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}


enum HarnessflowSchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var name: String
        var workingDirectory: String
        var isArchived: Bool = false
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \TicketEntity.project) var tickets: [TicketEntity]

        init(
            id: UUID = UUID(),
            name: String,
            workingDirectory: String,
            isArchived: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tickets: [TicketEntity] = []
        ) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tickets = tickets
        }
    }

    @Model
    final class TicketEntity {
        @Attribute(.unique) var id: UUID
        var title: String
        var detailsText: String
        var columnValue: Int
        var autoShiftOnSuccess: Bool = false
        var completedAt: Date?
        var archivedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var project: ProjectEntity?
        @Relationship(deleteRule: .cascade, inverse: \PhaseStateEntity.ticket) var phaseStates: [PhaseStateEntity]

        init(
            id: UUID,
            title: String,
            detailsText: String,
            columnValue: Int,
            autoShiftOnSuccess: Bool,
            completedAt: Date?,
            archivedAt: Date? = nil,
            createdAt: Date,
            updatedAt: Date,
            project: ProjectEntity? = nil,
            phaseStates: [PhaseStateEntity] = []
        ) {
            self.id = id
            self.title = title
            self.detailsText = detailsText
            self.columnValue = columnValue
            self.autoShiftOnSuccess = autoShiftOnSuccess
            self.completedAt = completedAt
            self.archivedAt = archivedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            self.phaseStates = phaseStates
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
        var deliverableMarkdown: String = ""
        var deliverableGeneratedAt: Date?
        var deliverableSourceRunID: UUID?
        var ownedProcessIdentifier: Int?
        var ownedProcessExecutablePath: String?
        var ownedProcessLaunchedAt: Date?
        var pendingQuestionsJSON: String?
        var pendingAnswersJSON: String?
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
            deliverableMarkdown: String = "",
            deliverableGeneratedAt: Date? = nil,
            deliverableSourceRunID: UUID? = nil,
            ownedProcessIdentifier: Int? = nil,
            ownedProcessExecutablePath: String? = nil,
            ownedProcessLaunchedAt: Date? = nil,
            pendingQuestionsJSON: String? = nil,
            pendingAnswersJSON: String? = nil,
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
            self.deliverableMarkdown = deliverableMarkdown
            self.deliverableGeneratedAt = deliverableGeneratedAt
            self.deliverableSourceRunID = deliverableSourceRunID
            self.ownedProcessIdentifier = ownedProcessIdentifier
            self.ownedProcessExecutablePath = ownedProcessExecutablePath
            self.ownedProcessLaunchedAt = ownedProcessLaunchedAt
            self.pendingQuestionsJSON = pendingQuestionsJSON
            self.pendingAnswersJSON = pendingAnswersJSON
            self.ticket = ticket
            self.runs = runs
        }
    }

    @Model
    final class PhaseRunEntity {
        @Attribute(.unique) var id: UUID
        var phaseValue: Int
        var model: String
        var providerKindRawValue: String = AgentProviderKind.codex.rawValue
        var authMethodRawValue: String = CodexAuthMethod.unknown.rawValue
        var authMethodDescription: String = CodexAuthMethod.unknown.title
        var didFallbackFromSubscription: Bool = false
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
            providerKindRawValue: String = AgentProviderKind.codex.rawValue,
            authMethodRawValue: String = CodexAuthMethod.unknown.rawValue,
            authMethodDescription: String = CodexAuthMethod.unknown.title,
            didFallbackFromSubscription: Bool = false,
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
            self.providerKindRawValue = providerKindRawValue
            self.authMethodRawValue = authMethodRawValue
            self.authMethodDescription = authMethodDescription
            self.didFallbackFromSubscription = didFallbackFromSubscription
            self.prompt = prompt
            self.outputText = outputText
            self.errorOutputText = errorOutputText
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.success = success
            self.phaseState = phaseState
        }
    }

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue
        var codexExecutablePath: String
        var claudeExecutablePath: String = "/opt/homebrew/bin/claude"
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue,
            codexExecutablePath: String,
            claudeExecutablePath: String = "/opt/homebrew/bin/claude",
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.selectedProviderKindRawValue = selectedProviderKindRawValue
            self.codexExecutablePath = codexExecutablePath
            self.claudeExecutablePath = claudeExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}


enum HarnessflowSchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    typealias ProjectEntity = HarnessflowSchemaV9.ProjectEntity
    typealias TicketEntity = HarnessflowSchemaV9.TicketEntity
    typealias PhaseStateEntity = HarnessflowSchemaV9.PhaseStateEntity
    typealias PhaseRunEntity = HarnessflowSchemaV9.PhaseRunEntity

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue
        var codexExecutablePath: String
        var claudeExecutablePath: String = "/opt/homebrew/bin/claude"
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var claudeAuthModeRawValue: String = ClaudeAuthMode.subscription.rawValue
        var claudePermissionModeRawValue: String = ClaudePermissionMode.bypassPermissions.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue,
            codexExecutablePath: String,
            claudeExecutablePath: String = "/opt/homebrew/bin/claude",
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            claudeAuthModeRawValue: String = ClaudeAuthMode.subscription.rawValue,
            claudePermissionModeRawValue: String = ClaudePermissionMode.bypassPermissions.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.selectedProviderKindRawValue = selectedProviderKindRawValue
            self.codexExecutablePath = codexExecutablePath
            self.claudeExecutablePath = claudeExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.claudeAuthModeRawValue = claudeAuthModeRawValue
            self.claudePermissionModeRawValue = claudePermissionModeRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}


enum HarnessflowSchemaV11: VersionedSchema {
    static let versionIdentifier = Schema.Version(11, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectEntity.self,
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ]
    }

    typealias ProjectEntity = HarnessflowSchemaV10.ProjectEntity
    typealias TicketEntity = HarnessflowSchemaV10.TicketEntity
    typealias PhaseStateEntity = HarnessflowSchemaV10.PhaseStateEntity
    typealias PhaseRunEntity = HarnessflowSchemaV10.PhaseRunEntity

    @Model
    final class SettingsEntity {
        @Attribute(.unique) var key: String
        var selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue
        var codexExecutablePath: String
        var claudeExecutablePath: String = "/opt/homebrew/bin/claude"
        var defaultWorkingDirectory: String
        var selectedProjectID: UUID?
        var codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        var claudeAuthModeRawValue: String = ClaudeAuthMode.subscription.rawValue
        var claudePermissionModeRawValue: String = ClaudePermissionMode.bypassPermissions.rawValue
        var researchModel: String
        var planModel: String
        var implementModel: String
        var reviewModel: String
        var claudeResearchModel: String = ""
        var claudePlanModel: String = ""
        var claudeImplementModel: String = ""
        var claudeReviewModel: String = ""
        var researchPrompt: String = ""
        var planPrompt: String = ""
        var implementPrompt: String = ""
        var reviewPrompt: String = ""

        init(
            key: String = "default",
            selectedProviderKindRawValue: String = AgentProviderKind.codex.rawValue,
            codexExecutablePath: String,
            claudeExecutablePath: String = "/opt/homebrew/bin/claude",
            defaultWorkingDirectory: String,
            selectedProjectID: UUID? = nil,
            codexAuthStrategyRawValue: String = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue,
            claudeAuthModeRawValue: String = ClaudeAuthMode.subscription.rawValue,
            claudePermissionModeRawValue: String = ClaudePermissionMode.bypassPermissions.rawValue,
            researchModel: String,
            planModel: String,
            implementModel: String,
            reviewModel: String,
            claudeResearchModel: String = "",
            claudePlanModel: String = "",
            claudeImplementModel: String = "",
            claudeReviewModel: String = "",
            researchPrompt: String,
            planPrompt: String,
            implementPrompt: String,
            reviewPrompt: String
        ) {
            self.key = key
            self.selectedProviderKindRawValue = selectedProviderKindRawValue
            self.codexExecutablePath = codexExecutablePath
            self.claudeExecutablePath = claudeExecutablePath
            self.defaultWorkingDirectory = defaultWorkingDirectory
            self.selectedProjectID = selectedProjectID
            self.codexAuthStrategyRawValue = codexAuthStrategyRawValue
            self.claudeAuthModeRawValue = claudeAuthModeRawValue
            self.claudePermissionModeRawValue = claudePermissionModeRawValue
            self.researchModel = researchModel
            self.planModel = planModel
            self.implementModel = implementModel
            self.reviewModel = reviewModel
            self.claudeResearchModel = claudeResearchModel
            self.claudePlanModel = claudePlanModel
            self.claudeImplementModel = claudeImplementModel
            self.claudeReviewModel = claudeReviewModel
            self.researchPrompt = researchPrompt
            self.planPrompt = planPrompt
            self.implementPrompt = implementPrompt
            self.reviewPrompt = reviewPrompt
        }
    }
}


enum HarnessflowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            HarnessflowSchemaV1.self,
            HarnessflowSchemaV2.self,
            HarnessflowSchemaV3.self,
            HarnessflowSchemaV4.self,
            HarnessflowSchemaV5.self,
            HarnessflowSchemaV6.self,
            HarnessflowSchemaV7.self,
            HarnessflowSchemaV8.self,
            HarnessflowSchemaV9.self,
            HarnessflowSchemaV10.self,
            HarnessflowSchemaV11.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: HarnessflowSchemaV1.self, toVersion: HarnessflowSchemaV2.self),
            .lightweight(fromVersion: HarnessflowSchemaV2.self, toVersion: HarnessflowSchemaV3.self),
            .lightweight(fromVersion: HarnessflowSchemaV3.self, toVersion: HarnessflowSchemaV4.self),
            .lightweight(fromVersion: HarnessflowSchemaV4.self, toVersion: HarnessflowSchemaV5.self),
            .lightweight(fromVersion: HarnessflowSchemaV5.self, toVersion: HarnessflowSchemaV6.self),
            .lightweight(fromVersion: HarnessflowSchemaV6.self, toVersion: HarnessflowSchemaV7.self),
            .lightweight(fromVersion: HarnessflowSchemaV7.self, toVersion: HarnessflowSchemaV8.self),
            .lightweight(fromVersion: HarnessflowSchemaV8.self, toVersion: HarnessflowSchemaV9.self),
            .lightweight(fromVersion: HarnessflowSchemaV9.self, toVersion: HarnessflowSchemaV10.self),
            .lightweight(fromVersion: HarnessflowSchemaV10.self, toVersion: HarnessflowSchemaV11.self),
        ]
    }
}

private enum PhaseQACoder {
    static func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func encodeAnswers(_ value: [AgentAnswer]) -> String? {
        guard value.isEmpty == false, let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decodeQuestionSet(_ json: String?) -> AgentQuestionSet? {
        guard
            let json,
            json.isEmpty == false,
            let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(AgentQuestionSet.self, from: data)
    }

    static func decodeAnswers(_ json: String?) -> [AgentAnswer] {
        guard
            let json,
            json.isEmpty == false,
            let data = json.data(using: .utf8)
        else {
            return []
        }
        return (try? JSONDecoder().decode([AgentAnswer].self, from: data)) ?? []
    }
}

typealias ProjectEntity = HarnessflowSchemaV11.ProjectEntity
typealias TicketEntity = HarnessflowSchemaV11.TicketEntity
typealias PhaseStateEntity = HarnessflowSchemaV11.PhaseStateEntity
typealias PhaseRunEntity = HarnessflowSchemaV11.PhaseRunEntity
typealias SettingsEntity = HarnessflowSchemaV11.SettingsEntity

extension ProjectEntity {
    func update(
        name: String,
        workingDirectory: String,
        isArchived: Bool? = nil,
        updatedAt: Date = .now
    ) {
        self.name = name
        self.workingDirectory = workingDirectory
        if let isArchived {
            self.isArchived = isArchived
        }
        self.updatedAt = updatedAt
    }

    func toRecord() -> ProjectRecord {
        ProjectRecord(
            id: id,
            name: name,
            workingDirectory: workingDirectory,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension TicketEntity {
    convenience init(ticket: Ticket, project: ProjectEntity? = nil) {
        self.init(
            id: ticket.id,
            title: ticket.title,
            detailsText: ticket.detailsText,
            columnValue: ticket.column.rawValue,
            autoShiftOnSuccess: ticket.autoShiftOnSuccess,
            completedAt: ticket.completedAt,
            archivedAt: ticket.archivedAt,
            createdAt: ticket.createdAt,
            updatedAt: ticket.updatedAt,
            project: project
        )
        phaseStates = ticket.phaseStates.map { PhaseStateEntity(state: $0, ticket: self) }
    }

    func update(from ticket: Ticket) {
        title = ticket.title
        detailsText = ticket.detailsText
        columnValue = ticket.column.rawValue
        autoShiftOnSuccess = ticket.autoShiftOnSuccess
        completedAt = ticket.completedAt
        archivedAt = ticket.archivedAt
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
            autoShiftOnSuccess: autoShiftOnSuccess,
            completedAt: completedAt,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            phaseStates: phaseStates
                .sorted(by: { $0.phaseValue < $1.phaseValue })
                .map { $0.toDomain() }
        )
    }
}

extension PhaseStateEntity {
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
            deliverableMarkdown: state.deliverableMarkdown,
            deliverableGeneratedAt: state.deliverableGeneratedAt,
            deliverableSourceRunID: state.deliverableSourceRunID,
            ownedProcessIdentifier: state.ownedProcess.map { Int($0.processIdentifier) },
            ownedProcessExecutablePath: state.ownedProcess?.executablePath ?? "",
            ownedProcessLaunchedAt: state.ownedProcess?.launchedAt,
            pendingQuestionsJSON: PhaseQACoder.encode(state.pendingQuestions),
            pendingAnswersJSON: PhaseQACoder.encodeAnswers(state.pendingAnswers),
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
        deliverableMarkdown = state.deliverableMarkdown
        deliverableGeneratedAt = state.deliverableGeneratedAt
        deliverableSourceRunID = state.deliverableSourceRunID
        ownedProcessIdentifier = state.ownedProcess.map { Int($0.processIdentifier) }
        ownedProcessExecutablePath = state.ownedProcess?.executablePath
        ownedProcessLaunchedAt = state.ownedProcess?.launchedAt
        pendingQuestionsJSON = PhaseQACoder.encode(state.pendingQuestions)
        pendingAnswersJSON = PhaseQACoder.encodeAnswers(state.pendingAnswers)

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
            deliverableMarkdown: deliverableMarkdown,
            deliverableGeneratedAt: deliverableGeneratedAt,
            deliverableSourceRunID: deliverableSourceRunID,
            ownedProcess: ownedProcessReference(),
            pendingQuestions: PhaseQACoder.decodeQuestionSet(pendingQuestionsJSON),
            pendingAnswers: PhaseQACoder.decodeAnswers(pendingAnswersJSON),
            runs: runs.sorted(by: { $0.startedAt < $1.startedAt }).map { $0.toDomain() }
        )
    }

    private func ownedProcessReference() -> OwnedProcessReference? {
        guard
            let ownedProcessIdentifier,
            let ownedProcessExecutablePath,
            ownedProcessExecutablePath.isEmpty == false
        else {
            return nil
        }

        return OwnedProcessReference(
            processIdentifier: Int32(ownedProcessIdentifier),
            executablePath: ownedProcessExecutablePath,
            launchedAt: ownedProcessLaunchedAt ?? lastStartedAt ?? .distantPast
        )
    }
}

extension PhaseRunEntity {
    convenience init(run: PhaseRun, phaseState: PhaseStateEntity? = nil) {
        self.init(
            id: run.id,
            phaseValue: run.phase.rawValue,
            model: run.model,
            providerKindRawValue: run.providerKind.rawValue,
            authMethodRawValue: run.authMethod.rawValue,
            authMethodDescription: run.authMethodDescription,
            didFallbackFromSubscription: run.didFallbackFromSubscription,
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
        providerKindRawValue = run.providerKind.rawValue
        authMethodRawValue = run.authMethod.rawValue
        authMethodDescription = run.authMethodDescription
        didFallbackFromSubscription = run.didFallbackFromSubscription
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
            providerKind: AgentProviderKind(rawValue: providerKindRawValue) ?? .codex,
            model: model,
            authMethod: CodexAuthMethod(rawValue: authMethodRawValue) ?? .unknown,
            authMethodDescription: authMethodDescription,
            didFallbackFromSubscription: didFallbackFromSubscription,
            prompt: prompt,
            output: outputText,
            errorOutput: errorOutputText,
            startedAt: startedAt,
            completedAt: completedAt,
            success: success
        )
    }
}

extension SettingsEntity {
    convenience init(settings: AppSettings) {
        let prompts = settings.phasePrompts.mergedWithBundledDefaults()
        self.init(
            selectedProviderKindRawValue: settings.selectedProviderKind.rawValue,
            codexExecutablePath: settings.codexExecutablePath,
            claudeExecutablePath: settings.claudeExecutablePath,
            defaultWorkingDirectory: settings.defaultWorkingDirectory,
            codexAuthStrategyRawValue: settings.codexAuthStrategy.rawValue,
            claudeAuthModeRawValue: settings.claudeAuthMode.rawValue,
            claudePermissionModeRawValue: settings.claudePermissionMode.rawValue,
            researchModel: settings.codexPhaseModels.research,
            planModel: settings.codexPhaseModels.plan,
            implementModel: settings.codexPhaseModels.implement,
            reviewModel: settings.codexPhaseModels.review,
            claudeResearchModel: settings.claudePhaseModels.research,
            claudePlanModel: settings.claudePhaseModels.plan,
            claudeImplementModel: settings.claudePhaseModels.implement,
            claudeReviewModel: settings.claudePhaseModels.review,
            researchPrompt: prompts.research,
            planPrompt: prompts.plan,
            implementPrompt: prompts.implement,
            reviewPrompt: prompts.review
        )
    }

    func update(from settings: AppSettings) {
        let prompts = settings.phasePrompts.mergedWithBundledDefaults()
        selectedProviderKindRawValue = settings.selectedProviderKind.rawValue
        codexExecutablePath = settings.codexExecutablePath
        claudeExecutablePath = settings.claudeExecutablePath
        defaultWorkingDirectory = settings.defaultWorkingDirectory
        codexAuthStrategyRawValue = settings.codexAuthStrategy.rawValue
        claudeAuthModeRawValue = settings.claudeAuthMode.rawValue
        claudePermissionModeRawValue = settings.claudePermissionMode.rawValue
        researchModel = settings.codexPhaseModels.research
        planModel = settings.codexPhaseModels.plan
        implementModel = settings.codexPhaseModels.implement
        reviewModel = settings.codexPhaseModels.review
        claudeResearchModel = settings.claudePhaseModels.research
        claudePlanModel = settings.claudePhaseModels.plan
        claudeImplementModel = settings.claudePhaseModels.implement
        claudeReviewModel = settings.claudePhaseModels.review
        researchPrompt = prompts.research
        planPrompt = prompts.plan
        implementPrompt = prompts.implement
        reviewPrompt = prompts.review
    }

    func fillMissingPhasePromptsFromDefaults() -> Bool {
        let defaults = PhasePromptSelection.bundledDefaults
        var didChange = false

        if researchPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            researchPrompt = defaults.research
            didChange = true
        }
        if planPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            planPrompt = defaults.plan
            didChange = true
        }
        if implementPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            implementPrompt = defaults.implement
            didChange = true
        }
        if reviewPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reviewPrompt = defaults.review
            didChange = true
        }

        return didChange
    }

    func normalizeAuthStrategy() -> Bool {
        let trimmed = codexAuthStrategyRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if CodexAuthStrategy(rawValue: trimmed) != nil {
            return false
        }

        codexAuthStrategyRawValue = CodexAuthStrategy.preferSubscriptionFallbackToAPI.rawValue
        return true
    }

    func normalizeProviderSelection() -> Bool {
        let trimmed = selectedProviderKindRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if AgentProviderKind(rawValue: trimmed) != nil {
            return false
        }

        selectedProviderKindRawValue = AgentProviderKind.codex.rawValue
        return true
    }

    func normalizeClaudeAuthMode() -> Bool {
        let trimmed = claudeAuthModeRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if ClaudeAuthMode(rawValue: trimmed) != nil {
            return false
        }

        claudeAuthModeRawValue = ClaudeAuthMode.subscription.rawValue
        return true
    }

    func normalizeClaudePermissionMode() -> Bool {
        let trimmed = claudePermissionModeRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if ClaudePermissionMode(rawValue: trimmed) != nil {
            return false
        }

        claudePermissionModeRawValue = ClaudePermissionMode.bypassPermissions.rawValue
        return true
    }

    func migrateLegacyCodexModelDefaultsIfNeeded() -> Bool {
        guard CodexAuthStrategy(rawValue: codexAuthStrategyRawValue) != .apiOnly else {
            return false
        }

        let models = [researchModel, planModel, implementModel, reviewModel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard models.allSatisfy({ $0 == "codex" }) else {
            return false
        }

        researchModel = PhaseModelSelection.subscriptionCompatibleDefaultModel
        planModel = PhaseModelSelection.subscriptionCompatibleDefaultModel
        implementModel = PhaseModelSelection.subscriptionCompatibleDefaultModel
        reviewModel = PhaseModelSelection.subscriptionCompatibleDefaultModel
        return true
    }

    func fillMissingClaudePhaseModelsIfNeeded() -> Bool {
        let storedClaudeModels = [
            claudeResearchModel,
            claudePlanModel,
            claudeImplementModel,
            claudeReviewModel,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard storedClaudeModels.allSatisfy(\.isEmpty) else {
            return false
        }

        let normalized = PhaseModelSelection(
            research: researchModel,
            plan: planModel,
            implement: implementModel,
            review: reviewModel
        ).normalized(for: .claude)

        claudeResearchModel = normalized.research
        claudePlanModel = normalized.plan
        claudeImplementModel = normalized.implement
        claudeReviewModel = normalized.review
        return true
    }

    func normalizeStoredClaudeModelDefaultsIfNeeded() -> Bool {
        let current = PhaseModelSelection(
            research: claudeResearchModel,
            plan: claudePlanModel,
            implement: claudeImplementModel,
            review: claudeReviewModel
        )
        let normalized = current.normalized(for: .claude)

        guard normalized != current else {
            return false
        }

        claudeResearchModel = normalized.research
        claudePlanModel = normalized.plan
        claudeImplementModel = normalized.implement
        claudeReviewModel = normalized.review
        return true
    }

    func toDomain() -> AppSettings {
        AppSettings(
            selectedProviderKind: AgentProviderKind(rawValue: selectedProviderKindRawValue) ?? .codex,
            codexExecutablePath: codexExecutablePath,
            claudeExecutablePath: claudeExecutablePath,
            defaultWorkingDirectory: defaultWorkingDirectory,
            codexAuthStrategy: CodexAuthStrategy(rawValue: codexAuthStrategyRawValue)
                ?? .preferSubscriptionFallbackToAPI,
            claudeAuthMode: ClaudeAuthMode(rawValue: claudeAuthModeRawValue) ?? .subscription,
            claudePermissionMode: ClaudePermissionMode(rawValue: claudePermissionModeRawValue)
                ?? .bypassPermissions,
            codexPhaseModels: PhaseModelSelection(
                research: researchModel,
                plan: planModel,
                implement: implementModel,
                review: reviewModel
            ),
            claudePhaseModels: PhaseModelSelection(
                research: claudeResearchModel,
                plan: claudePlanModel,
                implement: claudeImplementModel,
                review: claudeReviewModel
            ),
            phasePrompts: PhasePromptSelection(
                research: researchPrompt,
                plan: planPrompt,
                implement: implementPrompt,
                review: reviewPrompt
            )
        )
    }
}
