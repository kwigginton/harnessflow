import Testing
@testable import HarnessflowCore

struct CodexAuthenticationTests {
    @Test
    func appSettingsDefaultToPreferSubscriptionFallback() {
        let settings = AppSettings(defaultWorkingDirectory: "/tmp")

        #expect(settings.codexAuthStrategy == .preferSubscriptionFallbackToAPI)
        #expect(settings.phaseModels.research == PhaseModelSelection.subscriptionCompatibleDefaultModel)
        #expect(settings.phaseModels.plan == PhaseModelSelection.subscriptionCompatibleDefaultModel)
    }

    @Test
    func loginStatusParserRecognizesChatGPTLogin() {
        let parser = CodexLoginStatusParser()

        let status = parser.parse("""
        WARNING: proceeding, even though we could not update PATH
        Logged in using ChatGPT
        """)

        #expect(status == .loggedInChatGPT)
    }

    @Test
    func loginStatusParserRecognizesLoggedOutState() {
        let parser = CodexLoginStatusParser()

        let status = parser.parse("Not logged in")

        #expect(status == .loggedOut)
    }

    @Test
    func authResolverUsesSubscriptionWhenAvailableAndCompatible() throws {
        let resolution = try CodexAuthResolver().resolve(
            strategy: .preferSubscriptionFallbackToAPI,
            loginStatus: .loggedInChatGPT,
            hasAPIKey: true,
            model: "gpt-5.3-codex"
        )

        #expect(resolution.authMethod == .subscription)
        #expect(resolution.allowRateLimitFallbackToAPI)
    }

    @Test
    func authResolverUsesAPIWhenSubscriptionUnavailable() throws {
        let resolution = try CodexAuthResolver().resolve(
            strategy: .preferSubscriptionFallbackToAPI,
            loginStatus: .loggedOut,
            hasAPIKey: true,
            model: "gpt-5.3-codex"
        )

        #expect(resolution.authMethod == .apiKey)
        #expect(resolution.allowRateLimitFallbackToAPI == false)
    }

    @Test
    func authResolverBlocksCodexModelForSubscriptionOnly() {
        #expect(throws: CodexAuthResolutionError.modelRequiresAPIKey("codex")) {
            _ = try CodexAuthResolver().resolve(
                strategy: .subscriptionOnly,
                loginStatus: .loggedInChatGPT,
                hasAPIKey: true,
                model: "codex"
            )
        }
    }

    @Test
    func authResolverUsesAPIForCodexModelWhenFallbackKeyExists() throws {
        let resolution = try CodexAuthResolver().resolve(
            strategy: .preferSubscriptionFallbackToAPI,
            loginStatus: .loggedInChatGPT,
            hasAPIKey: true,
            model: "codex"
        )

        #expect(resolution.authMethod == .apiKey)
    }

    @Test
    func authResolverBlocksCodexModelWithoutAPIKey() {
        #expect(throws: CodexAuthResolutionError.modelRequiresAPIKey("codex")) {
            _ = try CodexAuthResolver().resolve(
                strategy: .preferSubscriptionFallbackToAPI,
                loginStatus: .loggedInChatGPT,
                hasAPIKey: false,
                model: "codex"
            )
        }
    }

    @Test
    func rateLimitFailuresRetryWithAPIWhenAllowed() {
        let resolution = CodexAuthResolution(
            authMethod: .subscription,
            allowRateLimitFallbackToAPI: true
        )

        let shouldRetry = CodexAuthResolver().shouldRetryWithAPIKey(
            after: "429 rate limit exceeded for this account",
            previousResolution: resolution,
            hasAPIKey: true
        )

        #expect(shouldRetry)
    }

    @Test
    func nonRateLimitFailuresDoNotRetryWithAPI() {
        let resolution = CodexAuthResolution(
            authMethod: .subscription,
            allowRateLimitFallbackToAPI: true
        )

        let shouldRetry = CodexAuthResolver().shouldRetryWithAPIKey(
            after: "The 'codex' model is not supported when using Codex with a ChatGPT account.",
            previousResolution: resolution,
            hasAPIKey: true
        )

        #expect(shouldRetry == false)
    }
}
