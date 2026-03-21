import Foundation

public struct PhaseModelSelection: Codable, Equatable, Sendable {
    public var research: String
    public var plan: String
    public var implement: String
    public var review: String

    public init(
        research: String = "codex",
        plan: String = "codex",
        implement: String = "codex",
        review: String = "codex"
    ) {
        self.research = research
        self.plan = plan
        self.implement = implement
        self.review = review
    }

    public func model(for phase: TicketPhase) -> String {
        switch phase {
        case .research:
            research
        case .plan:
            plan
        case .implement:
            implement
        case .review:
            review
        }
    }

    public mutating func setModel(_ model: String, for phase: TicketPhase) {
        switch phase {
        case .research:
            research = model
        case .plan:
            plan = model
        case .implement:
            implement = model
        case .review:
            review = model
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var codexExecutablePath: String
    public var defaultWorkingDirectory: String
    public var phaseModels: PhaseModelSelection

    public init(
        codexExecutablePath: String = "/opt/homebrew/bin/codex",
        defaultWorkingDirectory: String,
        phaseModels: PhaseModelSelection = PhaseModelSelection()
    ) {
        self.codexExecutablePath = codexExecutablePath
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.phaseModels = phaseModels
    }
}

