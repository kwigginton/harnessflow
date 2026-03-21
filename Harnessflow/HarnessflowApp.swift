import SwiftUI
import SwiftData

@main
struct HarnessflowApp: App {
    @StateObject private var store: AppStore
    private let modelContainer: ModelContainer

    init() {
        let container = HarnessflowModelContainer.make()
        self.modelContainer = container
        _store = StateObject(
            wrappedValue: AppStore(
                modelContainer: container,
                defaultWorkingDirectory: FileManager.default.currentDirectoryPath
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

