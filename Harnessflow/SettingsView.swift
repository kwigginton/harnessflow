import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var codexExecutablePath = ""
    @State private var defaultWorkingDirectory = ""
    @State private var researchModel = ""
    @State private var planModel = ""
    @State private var implementModel = ""
    @State private var reviewModel = ""

    var body: some View {
        Form {
            Section("Provider") {
                TextField("Codex executable path", text: $codexExecutablePath)
                TextField("Default working directory", text: $defaultWorkingDirectory)
            }

            Section("Per-Phase Models") {
                TextField("Research model", text: $researchModel)
                TextField("Plan model", text: $planModel)
                TextField("Implement model", text: $implementModel)
                TextField("Review model", text: $reviewModel)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save Settings") {
                        store.saveSettings(
                            codexExecutablePath: codexExecutablePath,
                            defaultWorkingDirectory: defaultWorkingDirectory,
                            researchModel: researchModel,
                            planModel: planModel,
                            implementModel: implementModel,
                            reviewModel: reviewModel
                        )
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: loadFromStore)
    }

    private func loadFromStore() {
        codexExecutablePath = store.settings.codexExecutablePath
        defaultWorkingDirectory = store.settings.defaultWorkingDirectory
        researchModel = store.settings.phaseModels.research
        planModel = store.settings.phaseModels.plan
        implementModel = store.settings.phaseModels.implement
        reviewModel = store.settings.phaseModels.review
    }
}
