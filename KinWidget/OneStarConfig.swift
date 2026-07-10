import AppIntents
import WidgetKit

// The widget process can't reach SwiftData (app-only), but it already reads
// the SkySnapshot JSON from the App Group — so the picker's entities come
// from the snapshot. One source of truth, no duplicate persistence.

struct StarEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Star"
    static var defaultQuery = StarEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct StarEntityQuery: EntityQuery {
    private func allStars() -> [StarEntity] {
        (SkySnapshotStore.load()?.stars ?? [])
            .map { StarEntity(id: $0.id, name: $0.name) }
            .sorted { $0.name < $1.name }
    }

    func entities(for identifiers: [UUID]) async throws -> [StarEntity] {
        allStars().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StarEntity] {
        allStars()
    }
}

/// Configuration: long-press the widget → Edit Widget → pick a person.
struct OneStarConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a Star"
    static var description = IntentDescription("Pick whose star this widget shows.")

    @Parameter(title: "Star")
    var star: StarEntity?
}
