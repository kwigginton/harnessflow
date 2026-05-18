import AppKit
import SwiftUI
import HarnessflowCore

private enum SettingsPage: Hashable {
    case general
    case openAI
    case anthropic
    case linear
}

struct SettingsView: View {
    @State private var selection: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("General") {
                    Label("Workflow", systemImage: "slider.horizontal.3")
                        .tag(SettingsPage.general)
                }

                Section("Providers") {
                    Label("OpenAI", systemImage: "key.horizontal")
                        .tag(SettingsPage.openAI)

                    Label("Anthropic", systemImage: "sparkles")
                        .tag(SettingsPage.anthropic)

                    Label("Linear", systemImage: "link")
                        .tag(SettingsPage.linear)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralSettingsPage()
                case .openAI:
                    OpenAISettingsPage()
                case .anthropic:
                    AnthropicSettingsPage()
                case .linear:
                    LinearSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

private struct GeneralSettingsPage: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProviderKind: AgentProviderKind = .codex
    @State private var codexExecutablePath = ""
    @State private var claudeExecutablePath = ""
    @State private var codexPhaseModels = PhaseModelSelection()
    @State private var claudePhaseModels = PhaseModelSelection.claudeDefaults
    @State private var researchPrompt = ""
    @State private var planPrompt = ""
    @State private var implementPrompt = ""
    @State private var reviewPrompt = ""
    @State private var editingPhase: TicketPhase?

    private let bundledDefaults = PhasePromptSelection.bundledDefaults

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Active provider", selection: $selectedProviderKind) {
                    ForEach(AgentProviderKind.allCases) { providerKind in
                        Text(providerKind.title)
                            .tag(providerKind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Codex executable path", text: $codexExecutablePath)
                TextField("Claude executable path", text: $claudeExecutablePath)

                Text("Working directories are managed as board rows from the top toolbar. The legacy default directory remains only for migration/bootstrap behavior.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Per-Phase Models") {
                TextField("Research model", text: modelBinding(for: .research))
                TextField("Plan model", text: modelBinding(for: .plan))
                TextField("Implement model", text: modelBinding(for: .implement))
                TextField("Review model", text: modelBinding(for: .review))

                Text(modelSelectionHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Per-Phase Base Prompts") {
                ForEach(TicketPhase.allCases) { phase in
                    PhasePromptRow(
                        phase: phase,
                        text: promptBinding(for: phase),
                        onEdit: {
                            editingPhase = phase
                        }
                    )
                }

                HStack {
                    Spacer()
                    Button("Restore Bundled Defaults") {
                        restoreBundledDefaults()
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save Settings") {
                        store.saveSettings(
                            selectedProviderKind: selectedProviderKind,
                            codexExecutablePath: codexExecutablePath,
                            claudeExecutablePath: claudeExecutablePath,
                            defaultWorkingDirectory: store.settings.defaultWorkingDirectory,
                            codexAuthStrategy: store.settings.codexAuthStrategy,
                            claudeAuthMode: store.settings.claudeAuthMode,
                            claudePermissionMode: store.settings.claudePermissionMode,
                            codexPhaseModels: codexPhaseModels,
                            claudePhaseModels: claudePhaseModels,
                            researchPrompt: researchPrompt,
                            planPrompt: planPrompt,
                            implementPrompt: implementPrompt,
                            reviewPrompt: reviewPrompt
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear(perform: loadFromStore)
        .sheet(item: $editingPhase) { phase in
            PhasePromptSheet(
                phase: phase,
                text: promptBinding(for: phase),
                bundledDefault: bundledDefaults.prompt(for: phase)
            )
        }
    }

    private func loadFromStore() {
        selectedProviderKind = store.settings.selectedProviderKind
        codexExecutablePath = store.settings.codexExecutablePath
        claudeExecutablePath = store.settings.claudeExecutablePath
        codexPhaseModels = store.settings.codexPhaseModels
        claudePhaseModels = store.settings.claudePhaseModels
        researchPrompt = store.settings.phasePrompts.research
        planPrompt = store.settings.phasePrompts.plan
        implementPrompt = store.settings.phasePrompts.implement
        reviewPrompt = store.settings.phasePrompts.review
    }

    private func restoreBundledDefaults() {
        researchPrompt = bundledDefaults.research
        planPrompt = bundledDefaults.plan
        implementPrompt = bundledDefaults.implement
        reviewPrompt = bundledDefaults.review
    }

    private func modelBinding(for phase: TicketPhase) -> Binding<String> {
        Binding(
            get: {
                switch selectedProviderKind {
                case .codex:
                    codexPhaseModels.model(for: phase)
                case .claude:
                    claudePhaseModels.model(for: phase)
                }
            },
            set: { newValue in
                switch selectedProviderKind {
                case .codex:
                    var updated = codexPhaseModels
                    updated.setModel(newValue, for: phase)
                    codexPhaseModels = updated
                case .claude:
                    var updated = claudePhaseModels
                    updated.setModel(newValue, for: phase)
                    claudePhaseModels = updated
                }
            }
        )
    }

    private var modelSelectionHelpText: String {
        switch selectedProviderKind {
        case .codex:
            "Codex and Claude model selections are stored separately, so switching providers does not overwrite your Codex defaults."
        case .claude:
            "Claude model selections are stored separately from Codex. Blank or legacy Codex defaults normalize to `sonnet` when you save Claude settings."
        }
    }

    private func promptBinding(for phase: TicketPhase) -> Binding<String> {
        switch phase {
        case .research:
            $researchPrompt
        case .plan:
            $planPrompt
        case .implement:
            $implementPrompt
        case .review:
            $reviewPrompt
        }
    }
}

private struct OpenAISettingsPage: View {
    @EnvironmentObject private var store: AppStore
    @State private var apiToken = ""
    @State private var selectedStrategy: CodexAuthStrategy = .preferSubscriptionFallbackToAPI
    @State private var didCopyLoginCommand = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Codex Authentication")
                        .font(.title3.weight(.semibold))

                    Text("Harnessflow can either reuse the Codex CLI ChatGPT subscription session or fall back to an OpenAI API key.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Picker("Auth Strategy", selection: $selectedStrategy) {
                    ForEach(CodexAuthStrategy.allCases) { strategy in
                        Text(strategy.title)
                            .tag(strategy)
                    }
                }

                Text(selectedStrategy.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Codex CLI Login")
                            .font(.headline)

                        Spacer()

                        Button("Refresh Status") {
                            store.refreshCodexLoginStatus()
                        }
                    }

                    Label(store.codexLoginStatus.title, systemImage: subscriptionStatusSymbolName)
                        .foregroundStyle(subscriptionStatusColor)

                    Text(store.codexLoginStatus.detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("CLI login is managed outside Harnessflow. Run the command below in Terminal to sign in with your ChatGPT subscription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(codexLoginCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                        Button {
                            copyCodexLoginCommand()
                        } label: {
                            Label("Copy Command", systemImage: "doc.on.doc")
                        }

                        if didCopyLoginCommand {
                            Label("Copied", systemImage: "checkmark")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.top, 8)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.headline)

                    Text("Harnessflow passes this token to Codex as `OPENAI_API_KEY` when the selected auth strategy uses the API key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SecureField("sk-...", text: $apiToken)
                    .textFieldStyle(.roundedBorder)

                Label(
                    store.hasOpenAIAPIToken ? "Token saved in Keychain." : "No token saved.",
                    systemImage: store.hasOpenAIAPIToken ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(store.hasOpenAIAPIToken ? .green : .secondary)

                Text("The token is stored in the macOS Keychain, not in the Harnessflow database.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Remove Token", role: .destructive) {
                        apiToken = ""
                        store.deleteOpenAIAPIToken()
                    }
                    .disabled(store.hasOpenAIAPIToken == false && apiToken.isEmpty)

                    Spacer()

                    Button("Save Provider Settings") {
                        store.saveSettings(
                            selectedProviderKind: store.settings.selectedProviderKind,
                            codexExecutablePath: store.settings.codexExecutablePath,
                            claudeExecutablePath: store.settings.claudeExecutablePath,
                            defaultWorkingDirectory: store.settings.defaultWorkingDirectory,
                            codexAuthStrategy: selectedStrategy,
                            claudeAuthMode: store.settings.claudeAuthMode,
                            claudePermissionMode: store.settings.claudePermissionMode,
                            codexPhaseModels: store.settings.codexPhaseModels,
                            claudePhaseModels: store.settings.claudePhaseModels,
                            researchPrompt: store.settings.phasePrompts.research,
                            planPrompt: store.settings.phasePrompts.plan,
                            implementPrompt: store.settings.phasePrompts.implement,
                            reviewPrompt: store.settings.phasePrompts.review
                        )
                        store.refreshCodexLoginStatus()
                    }

                    Button("Save API Key") {
                        store.saveOpenAIAPIToken(apiToken)
                        apiToken = store.loadOpenAIAPIToken()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            apiToken = store.loadOpenAIAPIToken()
            selectedStrategy = store.settings.codexAuthStrategy
            store.refreshCodexLoginStatus()
        }
    }

    private var subscriptionStatusSymbolName: String {
        switch store.codexLoginStatus {
        case .loggedInChatGPT:
            "checkmark.circle.fill"
        case .loggedInAPIKey:
            "person.crop.circle.badge.exclamationmark"
        case .loggedOut:
            "xmark.circle"
        case .unavailable, .unknown:
            "questionmark.circle"
        }
    }

    private var subscriptionStatusColor: Color {
        switch store.codexLoginStatus {
        case .loggedInChatGPT:
            .green
        case .loggedInAPIKey:
            .orange
        case .loggedOut:
            .secondary
        case .unavailable, .unknown:
            .secondary
        }
    }

    private var codexLoginCommand: String {
        let executablePath = store.settings.codexExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = executablePath.isEmpty ? "codex" : shellEscaped(executablePath)
        return "\(executable) login"
    }

    private func copyCodexLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codexLoginCommand, forType: .string)
        didCopyLoginCommand = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            didCopyLoginCommand = false
        }
    }

    private func shellEscaped(_ value: String) -> String {
        let charactersRequiringQuotes = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: #"'"`$\"#))

        guard value.rangeOfCharacter(from: charactersRequiringQuotes) != nil else {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct AnthropicSettingsPage: View {
    @EnvironmentObject private var store: AppStore
    @State private var apiToken = ""
    @State private var selectedAuthMode: ClaudeAuthMode = .subscription
    @State private var selectedPermissionMode: ClaudePermissionMode = .bypassPermissions

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude Authentication")
                        .font(.title3.weight(.semibold))

                    Text("Use `claude auth login` with the Claude.ai account your Team Premium seat was invited with. Switch to API key mode only if you intentionally want Anthropic API auth.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Picker("Auth Mode", selection: $selectedAuthMode) {
                    ForEach(ClaudeAuthMode.allCases) { authMode in
                        Text(authMode.title)
                            .tag(authMode)
                    }
                }

                Text(selectedAuthMode.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label(apiKeyStatusText, systemImage: apiKeyStatusSymbolName)
                    .foregroundStyle(apiKeyStatusColor)

                Text("The Claude login and any saved API key are stored outside the Harnessflow database. Subscription mode ignores the saved key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permission Mode") {
                Picker("Permission Mode", selection: $selectedPermissionMode) {
                    ForEach(ClaudePermissionMode.allCases) { permissionMode in
                        Text(permissionMode.title)
                            .tag(permissionMode)
                    }
                }

                Text(selectedPermissionMode.summary)
                    .font(.footnote)
                    .foregroundStyle(selectedPermissionMode.isRisky ? .orange : .secondary)
            }

            Section("Anthropic API Key") {
                SecureField("sk-ant-...", text: $apiToken)
                    .textFieldStyle(.roundedBorder)

                Text("Save an Anthropic key only if you want Harnessflow to use API key mode. Otherwise, leave this empty and use the Claude subscription login.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("The token is stored in the macOS Keychain, not in the Harnessflow database.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Remove Token", role: .destructive) {
                        apiToken = ""
                        store.deleteAnthropicAPIToken()
                    }
                    .disabled(store.hasAnthropicAPIToken == false && apiToken.isEmpty)

                    Spacer()

                    Button("Save Claude Settings") {
                        store.saveSettings(
                            selectedProviderKind: store.settings.selectedProviderKind,
                            codexExecutablePath: store.settings.codexExecutablePath,
                            claudeExecutablePath: store.settings.claudeExecutablePath,
                            defaultWorkingDirectory: store.settings.defaultWorkingDirectory,
                            codexAuthStrategy: store.settings.codexAuthStrategy,
                            claudeAuthMode: selectedAuthMode,
                            claudePermissionMode: selectedPermissionMode,
                            codexPhaseModels: store.settings.codexPhaseModels,
                            claudePhaseModels: store.settings.claudePhaseModels,
                            researchPrompt: store.settings.phasePrompts.research,
                            planPrompt: store.settings.phasePrompts.plan,
                            implementPrompt: store.settings.phasePrompts.implement,
                            reviewPrompt: store.settings.phasePrompts.review
                        )
                    }

                    Button("Save API Key") {
                        store.saveAnthropicAPIToken(apiToken)
                        apiToken = store.loadAnthropicAPIToken()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear(perform: loadFromStore)
    }

    private func loadFromStore() {
        apiToken = store.loadAnthropicAPIToken()
        selectedAuthMode = store.settings.claudeAuthMode
        selectedPermissionMode = store.settings.claudePermissionMode
    }

    private var apiKeyStatusText: String {
        switch (selectedAuthMode, store.hasAnthropicAPIToken) {
        case (.subscription, true):
            "API key saved in Keychain, but subscription mode ignores it."
        case (.subscription, false):
            "Subscription mode is active. No API key is required."
        case (.apiKey, true):
            "Anthropic API key saved in Keychain."
        case (.apiKey, false):
            "No Anthropic API key saved. Save one to use API-key mode."
        }
    }

    private var apiKeyStatusSymbolName: String {
        switch (selectedAuthMode, store.hasAnthropicAPIToken) {
        case (.subscription, true):
            "key.fill"
        case (.subscription, false):
            "checkmark.circle.fill"
        case (.apiKey, true):
            "checkmark.circle.fill"
        case (.apiKey, false):
            "exclamationmark.circle"
        }
    }

    private var apiKeyStatusColor: Color {
        switch (selectedAuthMode, store.hasAnthropicAPIToken) {
        case (.subscription, _):
            .secondary
        case (.apiKey, true):
            .green
        case (.apiKey, false):
            .orange
        }
    }
}

private struct LinearSettingsPage: View {
    @EnvironmentObject private var store: AppStore
    @State private var apiToken = ""
    @State private var isValidating = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linear Authentication")
                        .font(.title3.weight(.semibold))

                    Text("Harnessflow uses this API key to import issue titles, descriptions, comments, and file references into new tickets.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                SecureField("lin_api_...", text: $apiToken)
                    .textFieldStyle(.roundedBorder)

                Label(
                    store.hasLinearAPIToken ? "Token saved in Keychain." : "No token saved.",
                    systemImage: store.hasLinearAPIToken ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(store.hasLinearAPIToken ? .green : .secondary)

                Text(store.linearValidationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("The token is stored in the macOS Keychain, not in the Harnessflow database.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Remove Token", role: .destructive) {
                        apiToken = ""
                        store.deleteLinearAPIToken()
                    }
                    .disabled(store.hasLinearAPIToken == false && apiToken.isEmpty)

                    Spacer()

                    Button("Validate") {
                        isValidating = true
                        Task {
                            await store.validateLinearAPIToken()
                            isValidating = false
                        }
                    }
                    .disabled(isValidating || store.hasLinearAPIToken == false)

                    Button("Save API Key") {
                        store.saveLinearAPIToken(apiToken)
                        apiToken = store.loadLinearAPIToken()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            apiToken = store.loadLinearAPIToken()
        }
    }
}

private struct PhasePromptRow: View {
    let phase: TicketPhase
    @Binding var text: String
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(phase.title)
                    .font(.headline)

                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Edit Prompt") {
                onEdit()
            }
        }
        .padding(.vertical, 4)
    }

    private var summaryText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "No prompt configured."
        }

        let singleLine = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.isEmpty == false })
            ?? trimmed

        return singleLine
    }
}

private struct PhasePromptSheet: View {
    let phase: TicketPhase
    @Binding var text: String
    let bundledDefault: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(phase.title) Prompt")
                    .font(.title3.weight(.semibold))

                Text("Edit the base markdown prompt for the \(phase.title.lowercased()) phase.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 360)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

            HStack {
                Button("Restore Default") {
                    text = bundledDefault
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 520)
    }
}
