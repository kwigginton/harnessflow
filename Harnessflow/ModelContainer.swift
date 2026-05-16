import Foundation
import SwiftData

enum HarnessflowModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema(versionedSchema: HarnessflowSchemaV6.self)
        let configuration = ModelConfiguration("Harnessflow", schema: schema)

        do {
            return try makeContainer(
                for: schema,
                configuration: configuration,
                migrationPlan: HarnessflowMigrationPlan.self
            )
        } catch let error as NSError where shouldRetryWithoutMigrationPlan(error) {
            do {
                return try makeContainer(
                    for: schema,
                    configuration: configuration,
                    migrationPlan: nil
                )
            } catch {
                fatalError("Failed to create model container after retry: \(describe(error))")
            }
        } catch {
            fatalError("Failed to create model container: \(describe(error))")
        }
    }

    private static func makeContainer(
        for schema: Schema,
        configuration: ModelConfiguration,
        migrationPlan: (any SchemaMigrationPlan.Type)?
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: [configuration]
        )
    }

    private static func shouldRetryWithoutMigrationPlan(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && error.code == 134504
            && (error.localizedDescription.localizedCaseInsensitiveContains("unknown model version")
                || (error.userInfo[NSLocalizedDescriptionKey] as? String)?
                    .localizedCaseInsensitiveContains("unknown model version") == true)
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let details = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)",
        ]
        return details.joined(separator: ", ")
    }
}
