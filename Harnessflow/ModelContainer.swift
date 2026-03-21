import SwiftData

enum HarnessflowModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema([
            TicketEntity.self,
            PhaseStateEntity.self,
            PhaseRunEntity.self,
            SettingsEntity.self,
        ])
        let configuration = ModelConfiguration("Harnessflow")

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }
}

