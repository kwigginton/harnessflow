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

public struct PhasePromptSelection: Codable, Equatable, Sendable {
    public var research: String
    public var plan: String
    public var implement: String
    public var review: String

    init(rawResearch: String, rawPlan: String, rawImplement: String, rawReview: String) {
        self.research = rawResearch
        self.plan = rawPlan
        self.implement = rawImplement
        self.review = rawReview
    }

    public init(
        research: String? = nil,
        plan: String? = nil,
        implement: String? = nil,
        review: String? = nil
    ) {
        let defaults = Self.bundledDefaults
        self.init(
            rawResearch: research ?? defaults.research,
            rawPlan: plan ?? defaults.plan,
            rawImplement: implement ?? defaults.implement,
            rawReview: review ?? defaults.review
        )
    }

    public static var bundledDefaults: Self {
        PhasePromptTemplateLoader.bundledDefaults()
    }

    public func prompt(for phase: TicketPhase) -> String {
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

    public mutating func setPrompt(_ prompt: String, for phase: TicketPhase) {
        switch phase {
        case .research:
            research = prompt
        case .plan:
            plan = prompt
        case .implement:
            implement = prompt
        case .review:
            review = prompt
        }
    }

    public func mergedWithBundledDefaults() -> Self {
        let defaults = Self.bundledDefaults
        return Self(
            rawResearch: research.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaults.research : research,
            rawPlan: plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaults.plan : plan,
            rawImplement: implement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaults.implement : implement,
            rawReview: review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaults.review : review
        )
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var codexExecutablePath: String
    public var defaultWorkingDirectory: String
    public var codexAuthStrategy: CodexAuthStrategy
    public var phaseModels: PhaseModelSelection
    public var phasePrompts: PhasePromptSelection

    public init(
        codexExecutablePath: String = "/opt/homebrew/bin/codex",
        defaultWorkingDirectory: String,
        codexAuthStrategy: CodexAuthStrategy = .preferSubscriptionFallbackToAPI,
        phaseModels: PhaseModelSelection = PhaseModelSelection(),
        phasePrompts: PhasePromptSelection = PhasePromptSelection()
    ) {
        self.codexExecutablePath = codexExecutablePath
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.codexAuthStrategy = codexAuthStrategy
        self.phaseModels = phaseModels
        self.phasePrompts = phasePrompts
    }
}
