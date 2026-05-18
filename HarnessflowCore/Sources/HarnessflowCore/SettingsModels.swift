import Foundation

public struct PhaseModelSelection: Codable, Equatable, Sendable {
    public static let subscriptionCompatibleDefaultModel = "gpt-5.3-codex"
    public static let claudeSubscriptionDefaultModel = "sonnet"

    public static var claudeDefaults: Self {
        Self(
            research: claudeSubscriptionDefaultModel,
            plan: claudeSubscriptionDefaultModel,
            implement: claudeSubscriptionDefaultModel,
            review: claudeSubscriptionDefaultModel
        )
    }

    public var research: String
    public var plan: String
    public var implement: String
    public var review: String

    public init(
        research: String = PhaseModelSelection.subscriptionCompatibleDefaultModel,
        plan: String = PhaseModelSelection.subscriptionCompatibleDefaultModel,
        implement: String = PhaseModelSelection.subscriptionCompatibleDefaultModel,
        review: String = PhaseModelSelection.subscriptionCompatibleDefaultModel
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

    public func normalized(for providerKind: AgentProviderKind) -> Self {
        guard providerKind == .claude else {
            return self
        }

        return Self(
            research: normalizedClaudeModel(research),
            plan: normalizedClaudeModel(plan),
            implement: normalizedClaudeModel(implement),
            review: normalizedClaudeModel(review)
        )
    }

    private func normalizedClaudeModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        guard trimmed.isEmpty
            || normalized == "codex"
            || trimmed.caseInsensitiveCompare(Self.subscriptionCompatibleDefaultModel) == .orderedSame
        else {
            return trimmed
        }

        return Self.claudeSubscriptionDefaultModel
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
    public var selectedProviderKind: AgentProviderKind
    public var codexExecutablePath: String
    public var claudeExecutablePath: String
    public var defaultWorkingDirectory: String
    public var codexAuthStrategy: CodexAuthStrategy
    public var claudeAuthMode: ClaudeAuthMode
    public var claudePermissionMode: ClaudePermissionMode
    public var codexPhaseModels: PhaseModelSelection
    public var claudePhaseModels: PhaseModelSelection
    public var phasePrompts: PhasePromptSelection

    public var phaseModels: PhaseModelSelection {
        get { phaseModels(for: selectedProviderKind) }
        set { setPhaseModels(newValue, for: selectedProviderKind) }
    }

    public init(
        selectedProviderKind: AgentProviderKind = .codex,
        codexExecutablePath: String = "/opt/homebrew/bin/codex",
        claudeExecutablePath: String = "/opt/homebrew/bin/claude",
        defaultWorkingDirectory: String,
        codexAuthStrategy: CodexAuthStrategy = .preferSubscriptionFallbackToAPI,
        claudeAuthMode: ClaudeAuthMode = .subscription,
        claudePermissionMode: ClaudePermissionMode = .bypassPermissions,
        phaseModels: PhaseModelSelection = PhaseModelSelection(),
        phasePrompts: PhasePromptSelection = PhasePromptSelection()
    ) {
        self.init(
            selectedProviderKind: selectedProviderKind,
            codexExecutablePath: codexExecutablePath,
            claudeExecutablePath: claudeExecutablePath,
            defaultWorkingDirectory: defaultWorkingDirectory,
            codexAuthStrategy: codexAuthStrategy,
            claudeAuthMode: claudeAuthMode,
            claudePermissionMode: claudePermissionMode,
            codexPhaseModels: selectedProviderKind == .codex ? phaseModels : PhaseModelSelection(),
            claudePhaseModels: selectedProviderKind == .claude ? phaseModels : PhaseModelSelection.claudeDefaults,
            phasePrompts: phasePrompts
        )
    }

    public init(
        selectedProviderKind: AgentProviderKind = .codex,
        codexExecutablePath: String = "/opt/homebrew/bin/codex",
        claudeExecutablePath: String = "/opt/homebrew/bin/claude",
        defaultWorkingDirectory: String,
        codexAuthStrategy: CodexAuthStrategy = .preferSubscriptionFallbackToAPI,
        claudeAuthMode: ClaudeAuthMode = .subscription,
        claudePermissionMode: ClaudePermissionMode = .bypassPermissions,
        codexPhaseModels: PhaseModelSelection = PhaseModelSelection(),
        claudePhaseModels: PhaseModelSelection = PhaseModelSelection.claudeDefaults,
        phasePrompts: PhasePromptSelection = PhasePromptSelection()
    ) {
        self.selectedProviderKind = selectedProviderKind
        self.codexExecutablePath = codexExecutablePath
        self.claudeExecutablePath = claudeExecutablePath
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.codexAuthStrategy = codexAuthStrategy
        self.claudeAuthMode = claudeAuthMode
        self.claudePermissionMode = claudePermissionMode
        self.codexPhaseModels = codexPhaseModels
        self.claudePhaseModels = claudePhaseModels.normalized(for: .claude)
        self.phasePrompts = phasePrompts
    }

    public func resolvedModel(for phase: TicketPhase) -> String {
        phaseModels(for: selectedProviderKind).model(for: phase)
    }

    public func normalizedPhaseModels() -> PhaseModelSelection {
        phaseModels(for: selectedProviderKind)
    }

    public func phaseModels(for providerKind: AgentProviderKind) -> PhaseModelSelection {
        switch providerKind {
        case .codex:
            codexPhaseModels
        case .claude:
            claudePhaseModels.normalized(for: .claude)
        }
    }

    public mutating func setPhaseModels(_ phaseModels: PhaseModelSelection, for providerKind: AgentProviderKind) {
        switch providerKind {
        case .codex:
            codexPhaseModels = phaseModels
        case .claude:
            claudePhaseModels = phaseModels.normalized(for: .claude)
        }
    }

    public func normalizedForPersistence() -> Self {
        Self(
            selectedProviderKind: selectedProviderKind,
            codexExecutablePath: codexExecutablePath,
            claudeExecutablePath: claudeExecutablePath,
            defaultWorkingDirectory: defaultWorkingDirectory,
            codexAuthStrategy: codexAuthStrategy,
            claudeAuthMode: claudeAuthMode,
            claudePermissionMode: claudePermissionMode,
            codexPhaseModels: codexPhaseModels,
            claudePhaseModels: claudePhaseModels,
            phasePrompts: phasePrompts
        )
    }
}

public enum ClaudeAuthMode: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case subscription
    case apiKey

    public var id: Self { self }

    public var title: String {
        switch self {
        case .subscription:
            "Subscription"
        case .apiKey:
            "API Key"
        }
    }

    public var runHistoryDescription: String {
        switch self {
        case .subscription:
            "Claude Subscription"
        case .apiKey:
            "Anthropic API Key"
        }
    }

    public var summary: String {
        switch self {
        case .subscription:
            "Use your Claude.ai Team or Enterprise login from `claude auth login`. Any saved Anthropic API key is ignored."
        case .apiKey:
            "Use the saved Anthropic API key instead of the Claude subscription login."
        }
    }

    public var environmentRemovals: Set<String> {
        switch self {
        case .subscription:
            [
                "CLAUDE_CODE_USE_BEDROCK",
                "CLAUDE_CODE_USE_VERTEX",
                "CLAUDE_CODE_USE_FOUNDRY",
                "ANTHROPIC_AUTH_TOKEN",
                "ANTHROPIC_API_KEY",
            ]
        case .apiKey:
            [
                "CLAUDE_CODE_USE_BEDROCK",
                "CLAUDE_CODE_USE_VERTEX",
                "CLAUDE_CODE_USE_FOUNDRY",
                "ANTHROPIC_AUTH_TOKEN",
                "CLAUDE_CODE_OAUTH_TOKEN",
                "ANTHROPIC_API_KEY",
            ]
        }
    }
}

public enum ClaudePermissionMode: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case plan
    case acceptEdits
    case dontAsk
    case bypassPermissions

    public var id: Self { self }

    public var title: String {
        switch self {
        case .plan:
            "Plan"
        case .acceptEdits:
            "Accept Edits"
        case .dontAsk:
            "Don't Ask"
        case .bypassPermissions:
            "Bypass Permissions"
        }
    }

    public var summary: String {
        switch self {
        case .plan:
            "Read-only exploration mode. Good for scoping work before edits."
        case .acceptEdits:
            "Allows file edits and common filesystem operations without prompting."
        case .dontAsk:
            "Denies anything that is not already pre-approved."
        case .bypassPermissions:
            "Approves everything and should only be used in isolated environments."
        }
    }

    public var isRisky: Bool {
        self == .bypassPermissions
    }
}
