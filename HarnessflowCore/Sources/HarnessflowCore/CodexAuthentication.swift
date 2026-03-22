import Foundation

public enum CodexAuthStrategy: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case preferSubscriptionFallbackToAPI
    case subscriptionOnly
    case apiOnly

    public var id: Self { self }

    public var title: String {
        switch self {
        case .preferSubscriptionFallbackToAPI:
            "Prefer Subscription, Fallback to API"
        case .subscriptionOnly:
            "Subscription Only"
        case .apiOnly:
            "API Key Only"
        }
    }

    public var summary: String {
        switch self {
        case .preferSubscriptionFallbackToAPI:
            "Use Codex CLI ChatGPT login first, then retry with the API key on rate limits."
        case .subscriptionOnly:
            "Only use the Codex CLI ChatGPT subscription login."
        case .apiOnly:
            "Always use the OpenAI API key from Settings."
        }
    }
}

public enum CodexAuthMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case subscription
    case apiKey

    public var title: String {
        switch self {
        case .unknown:
            "Unknown"
        case .subscription:
            "Subscription"
        case .apiKey:
            "API Key"
        }
    }
}

public enum CodexLoginStatus: Equatable, Sendable {
    case loggedOut
    case loggedInChatGPT
    case loggedInAPIKey
    case unavailable(String)
    case unknown(String)

    public var supportsSubscription: Bool {
        if case .loggedInChatGPT = self {
            return true
        }
        return false
    }

    public var title: String {
        switch self {
        case .loggedOut:
            "Logged Out"
        case .loggedInChatGPT:
            "Logged In With ChatGPT"
        case .loggedInAPIKey:
            "Logged In With API Key"
        case .unavailable:
            "Status Unavailable"
        case .unknown:
            "Unknown Status"
        }
    }

    public var detailText: String {
        switch self {
        case .loggedOut:
            "Codex CLI is not logged in."
        case .loggedInChatGPT:
            "Codex CLI can use the ChatGPT subscription session."
        case .loggedInAPIKey:
            "Codex CLI is logged in with an API key, not a ChatGPT subscription."
        case let .unavailable(message), let .unknown(message):
            message
        }
    }
}

public struct CodexLoginStatusParser {
    public init() {}

    public func parse(_ text: String) -> CodexLoginStatus {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        if normalized.contains("logged in using chatgpt") {
            return .loggedInChatGPT
        }
        if normalized.contains("logged in using api key") {
            return .loggedInAPIKey
        }
        if normalized.contains("not logged in") || normalized.contains("logged out") {
            return .loggedOut
        }

        return .unknown(trimmed.isEmpty ? "Codex login status returned no output." : trimmed)
    }
}

public struct CodexAuthResolution: Equatable, Sendable {
    public var authMethod: CodexAuthMethod
    public var allowRateLimitFallbackToAPI: Bool

    public init(
        authMethod: CodexAuthMethod,
        allowRateLimitFallbackToAPI: Bool
    ) {
        self.authMethod = authMethod
        self.allowRateLimitFallbackToAPI = allowRateLimitFallbackToAPI
    }
}

public enum CodexAuthResolutionError: LocalizedError, Equatable, Sendable {
    case subscriptionLoginRequired
    case apiKeyRequired
    case modelRequiresAPIKey(String)
    case noAvailableAuthentication

    public var errorDescription: String? {
        switch self {
        case .subscriptionLoginRequired:
            "Subscription auth requires Codex CLI to be logged in with ChatGPT. Run `codex login` outside Harnessflow or choose a different auth strategy."
        case .apiKeyRequired:
            "This auth strategy requires an OpenAI API key in Settings."
        case let .modelRequiresAPIKey(model):
            "The `\(model)` model cannot run with ChatGPT subscription auth. Add an OpenAI API key or choose a subscription-compatible model."
        case .noAvailableAuthentication:
            "No usable Codex authentication is configured. Log in to Codex with ChatGPT or add an OpenAI API key in Settings."
        }
    }
}

public struct CodexAuthResolver: Sendable {
    public init() {}

    public func resolve(
        strategy: CodexAuthStrategy,
        loginStatus: CodexLoginStatus,
        hasAPIKey: Bool,
        model: String
    ) throws -> CodexAuthResolution {
        let requiresAPIKey = modelRequiresAPIKey(model)
        let hasSubscription = loginStatus.supportsSubscription

        switch strategy {
        case .subscriptionOnly:
            guard hasSubscription else {
                throw CodexAuthResolutionError.subscriptionLoginRequired
            }
            guard requiresAPIKey == false else {
                throw CodexAuthResolutionError.modelRequiresAPIKey(model)
            }
            return CodexAuthResolution(
                authMethod: .subscription,
                allowRateLimitFallbackToAPI: false
            )

        case .apiOnly:
            guard hasAPIKey else {
                throw CodexAuthResolutionError.apiKeyRequired
            }
            return CodexAuthResolution(
                authMethod: .apiKey,
                allowRateLimitFallbackToAPI: false
            )

        case .preferSubscriptionFallbackToAPI:
            if requiresAPIKey {
                guard hasAPIKey else {
                    throw CodexAuthResolutionError.modelRequiresAPIKey(model)
                }
                return CodexAuthResolution(
                    authMethod: .apiKey,
                    allowRateLimitFallbackToAPI: false
                )
            }

            if hasSubscription {
                return CodexAuthResolution(
                    authMethod: .subscription,
                    allowRateLimitFallbackToAPI: hasAPIKey
                )
            }

            if hasAPIKey {
                return CodexAuthResolution(
                    authMethod: .apiKey,
                    allowRateLimitFallbackToAPI: false
                )
            }

            throw CodexAuthResolutionError.noAvailableAuthentication
        }
    }

    public func shouldRetryWithAPIKey(
        after message: String,
        previousResolution: CodexAuthResolution,
        hasAPIKey: Bool
    ) -> Bool {
        guard previousResolution.authMethod == .subscription else {
            return false
        }
        guard previousResolution.allowRateLimitFallbackToAPI else {
            return false
        }
        guard hasAPIKey else {
            return false
        }

        return isRateLimitLikeFailure(message)
    }

    private func modelRequiresAPIKey(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("codex") == .orderedSame
    }

    private func isRateLimitLikeFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let indicators = [
            "rate limit",
            "rate-limit",
            "too many requests",
            "429",
            "quota",
            "capacity",
            "capacity reached",
            "usage limit",
            "request limit",
            "exceeded your current quota",
        ]

        return indicators.contains { normalized.contains($0) }
    }
}
