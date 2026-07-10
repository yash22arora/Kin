import SwiftData

/// One container, shared by the app and App Intents (Siri runs intents
/// in-process; both must see the same store).
enum KinModelContainer {
    static let shared: ModelContainer = {
        // ⏸ iCloud sync PARKED: requires a paid Apple Developer account.
        // To re-enable: add iCloud→CloudKit capability + UIBackgroundModes
        // (see git history / POLISH.md), then flip .none → .automatic with
        // a local-only fallback. Models are CloudKit-compatible (defaults,
        // optional relationships, no unique constraints) — keep it that way.
        let schema = Schema([Person.self, Moment.self, StarGroup.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}
