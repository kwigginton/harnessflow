import Foundation

public enum TicketPhase: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case research
    case plan
    case implement
    case review

    public var id: Self { self }

    public var title: String {
        switch self {
        case .research:
            "Research"
        case .plan:
            "Plan"
        case .implement:
            "Implement"
        case .review:
            "Review"
        }
    }

    public var symbolName: String {
        switch self {
        case .research:
            "magnifyingglass"
        case .plan:
            "list.bullet.rectangle"
        case .implement:
            "hammer"
        case .review:
            "checkmark.shield"
        }
    }
}

public enum PhaseExecutionState: String, Codable, CaseIterable, Equatable, Sendable {
    case idle
    case running
    case completed
    case failed

    public var displayTitle: String {
        rawValue.capitalized
    }
}

public struct PhaseRun: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var phase: TicketPhase
    public var model: String
    public var prompt: String
    public var output: String
    public var errorOutput: String
    public var startedAt: Date
    public var completedAt: Date
    public var success: Bool

    public init(
        id: UUID = UUID(),
        phase: TicketPhase,
        model: String,
        prompt: String,
        output: String,
        errorOutput: String,
        startedAt: Date,
        completedAt: Date,
        success: Bool
    ) {
        self.id = id
        self.phase = phase
        self.model = model
        self.prompt = prompt
        self.output = output
        self.errorOutput = errorOutput
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.success = success
    }
}

public struct TicketPhaseState: Identifiable, Codable, Equatable, Sendable {
    public var phase: TicketPhase
    public var executionState: PhaseExecutionState
    public var prompt: String
    public var lastModel: String?
    public var lastStartedAt: Date?
    public var lastCompletedAt: Date?
    public var capturedOutput: String
    public var capturedError: String
    public var runs: [PhaseRun]

    public var id: TicketPhase { phase }

    public init(
        phase: TicketPhase,
        executionState: PhaseExecutionState = .idle,
        prompt: String = "",
        lastModel: String? = nil,
        lastStartedAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        capturedOutput: String = "",
        capturedError: String = "",
        runs: [PhaseRun] = []
    ) {
        self.phase = phase
        self.executionState = executionState
        self.prompt = prompt
        self.lastModel = lastModel
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
        self.capturedOutput = capturedOutput
        self.capturedError = capturedError
        self.runs = runs
    }

    public static func empty(for phase: TicketPhase) -> Self {
        TicketPhaseState(phase: phase)
    }

    public mutating func resetForRework() {
        executionState = .idle
        lastModel = nil
        lastStartedAt = nil
        lastCompletedAt = nil
        capturedOutput = ""
        capturedError = ""
    }
}

public struct Ticket: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var detailsText: String
    public var column: TicketPhase
    public var createdAt: Date
    public var updatedAt: Date
    public var phaseStates: [TicketPhaseState]

    public init(
        id: UUID = UUID(),
        title: String,
        detailsText: String = "",
        column: TicketPhase = .research,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        phaseStates: [TicketPhaseState] = TicketPhase.allCases.map(TicketPhaseState.empty(for:))
    ) {
        self.id = id
        self.title = title
        self.detailsText = detailsText
        self.column = column
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phaseStates = Ticket.normalizedStates(from: phaseStates)
    }

    public func phaseState(for phase: TicketPhase) -> TicketPhaseState {
        phaseStates.first(where: { $0.phase == phase }) ?? .empty(for: phase)
    }

    public mutating func updatePhaseState(_ newState: TicketPhaseState) {
        if let index = phaseStates.firstIndex(where: { $0.phase == newState.phase }) {
            phaseStates[index] = newState
        } else {
            phaseStates.append(newState)
            phaseStates.sort { $0.phase.rawValue < $1.phase.rawValue }
        }
    }

    private static func normalizedStates(from states: [TicketPhaseState]) -> [TicketPhaseState] {
        TicketPhase.allCases.map { phase in
            states.first(where: { $0.phase == phase }) ?? .empty(for: phase)
        }
    }
}

