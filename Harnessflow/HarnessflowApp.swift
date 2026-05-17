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
        .defaultSize(width: 1440, height: 900)
        .modelContainer(modelContainer)

        WindowGroup("Phase Output", id: "phase-output", for: PhaseOutputWindowRoute.self) { route in
            PhaseOutputWindowView(route: route.wrappedValue)
                .environmentObject(store)
        }
        .defaultSize(width: 960, height: 720)

        WindowGroup("Ticket Detail", id: "ticket-detail", for: TicketDetailWindowRoute.self) { route in
            TicketDetailWindowView(route: route.wrappedValue)
                .environmentObject(store)
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
