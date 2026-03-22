import SwiftUI
import HarnessflowCore

private enum SettingsPage: Hashable {
    case general
    case openAI
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

private struct GeneralSettingsPage: View {
    @EnvironmentObject private var store: AppStore
    @State private var codexExecutablePath = ""
    @State private var researchModel = ""
    @State private var planModel = ""
    @State private var implementModel = ""
    @State private var reviewModel = ""
    @State private var researchPrompt = ""
    @State private var planPrompt = ""
    @State private var implementPrompt = ""
    @State private var reviewPrompt = ""
    @State private var editingPhase: TicketPhase?

    private let bundledDefaults = PhasePromptSelection.bundledDefaults

    var body: some View {
        Form {
            Section("Provider") {
                TextField("Codex executable path", text: $codexExecutablePath)

                Text("Working directory is now controlled per project from the top toolbar. The legacy default directory remains only for migration/bootstrap behavior.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Per-Phase Models") {
                TextField("Research model", text: $researchModel)
                TextField("Plan model", text: $planModel)
                TextField("Implement model", text: $implementModel)
                TextField("Review model", text: $reviewModel)
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
                            codexExecutablePath: codexExecutablePath,
                            defaultWorkingDirectory: store.settings.defaultWorkingDirectory,
                            codexAuthStrategy: store.settings.codexAuthStrategy,
                            researchModel: researchModel,
                            planModel: planModel,
                            implementModel: implementModel,
                            reviewModel: reviewModel,
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
        codexExecutablePath = store.settings.codexExecutablePath
        researchModel = store.settings.phaseModels.research
        planModel = store.settings.phaseModels.plan
        implementModel = store.settings.phaseModels.implement
        reviewModel = store.settings.phaseModels.review
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

                    Text("CLI login is managed outside Harnessflow. Use `codex login` in Terminal to sign in with your ChatGPT subscription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                            codexExecutablePath: store.settings.codexExecutablePath,
                            defaultWorkingDirectory: store.settings.defaultWorkingDirectory,
                            codexAuthStrategy: selectedStrategy,
                            researchModel: store.settings.phaseModels.research,
                            planModel: store.settings.phaseModels.plan,
                            implementModel: store.settings.phaseModels.implement,
                            reviewModel: store.settings.phaseModels.review,
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
