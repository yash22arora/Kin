import AppIntents
import SwiftData
import WidgetKit

// Kin's Siri surface. Same voice as the app: warm, brief, never guilt.
// App Shortcuts register automatically; donations from in-app saves teach
// Siri (and Apple Intelligence) the user's patterns.

// MARK: - Person as an entity Siri can name

struct PersonEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Star"
    static var defaultQuery = PersonEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(person: Person) {
        self.id = person.id
        self.name = person.name
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

struct PersonEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    private func activePeople() throws -> [Person] {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.stateRaw != "released" },
            sortBy: [SortDescriptor(\.name)]
        )
        return try KinModelContainer.shared.mainContext.fetch(descriptor)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PersonEntity] {
        try activePeople().filter { identifiers.contains($0.id) }.map(PersonEntity.init(person:))
    }

    @MainActor
    func suggestedEntities() async throws -> [PersonEntity] {
        try activePeople().map(PersonEntity.init(person:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [PersonEntity] {
        try activePeople()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(PersonEntity.init(person:))
    }
}

// MARK: - Log a moment ("Log a moment with Mom in Kin")

struct LogMomentIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Moment"
    static var description = IntentDescription(
        "Add a shared moment with someone. Their star brightens.",
        categoryName: "Moments"
    )

    @Parameter(title: "With", requestValueDialog: "Who did you share a moment with?")
    var person: PersonEntity

    @Parameter(title: "Note", requestValueDialog: "Anything you want to remember about it?")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a moment with \(\.$person)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = KinModelContainer.shared.mainContext
        let personID = person.id
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let match = try context.fetch(descriptor).first else {
            return .result(dialog: "I couldn't find that star in your sky.")
        }

        let moment = Moment(
            timestamp: .now,
            note: (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            people: [match]
        )
        context.insert(moment)
        try context.save()
        publishSky(context: context)

        return .result(dialog: "A moment with \(match.name). Their star brightens.")
    }
}

// MARK: - How bright is a star ("How bright is Sarah's star?")

struct StarBrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "How Bright Is a Star"
    static var description = IntentDescription(
        "Check how someone's star is glowing.",
        categoryName: "Sky"
    )

    @Parameter(title: "Star", requestValueDialog: "Whose star?")
    var person: PersonEntity

    static var parameterSummary: some ParameterSummary {
        Summary("How bright is \(\.$person)'s star")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = KinModelContainer.shared.mainContext
        let personID = person.id
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let match = try context.fetch(descriptor).first else {
            return .result(dialog: "I couldn't find that star in your sky.")
        }

        if match.state == .remembered {
            return .result(dialog: "\(match.name)'s star is remembered — it holds steady, always.")
        }
        let lum = match.luminosity()
        let line: String
        switch lum {
        case 0.7...:    line = "\(match.name)'s star is burning bright."
        case 0.45..<0.7: line = "\(match.name)'s star is glowing softly."
        default:         line = "\(match.name)'s star feels a little distant. A small moment would warm it."
        }
        return .result(dialog: "\(line)")
    }
}

// MARK: - Open a star ("Show me Mom's star")

struct OpenStarIntent: AppIntent {
    static var title: LocalizedStringResource = "Show a Star"
    static var description = IntentDescription(
        "Open Kin zoomed in on someone's star.",
        categoryName: "Sky"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Star", requestValueDialog: "Whose star?")
    var person: PersonEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$person)'s star")
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // UUID strings are always URL-safe.
        let url = URL(string: "kin://star/\(person.id.uuidString)")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - App Shortcuts (zero-setup Siri phrases)

struct KinAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMomentIntent(),
            phrases: [
                "Log a moment in \(.applicationName)",
                "Add a moment in \(.applicationName)",
                "Log a moment with \(\.$person) in \(.applicationName)",
            ],
            shortTitle: "Log a Moment",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: StarBrightnessIntent(),
            phrases: [
                "How bright is \(\.$person) in \(.applicationName)",
                "Check a star in \(.applicationName)",
            ],
            shortTitle: "Check a Star",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: OpenStarIntent(),
            phrases: [
                "Show \(\.$person) in \(.applicationName)",
                "Open a star in \(.applicationName)",
            ],
            shortTitle: "Show a Star",
            systemImageName: "star"
        )
    }
}

// MARK: - Shared helpers

/// Call whenever the set of people changes (star added, renamed, released):
/// re-syncs Siri's vocabulary so "Log a moment with Mom" resolves. Without
/// this, parameterized phrases silently fail — Siri never learns the names.
func syncSiriVocabulary() {
    Task { KinAppShortcuts.updateAppShortcutParameters() }
}

/// Rebuild + publish the widget snapshot after Siri changes data,
/// so the home screen brightens without the app ever opening.
@MainActor
func publishSky(context: ModelContext) {
    let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.stateRaw != "released" })
    guard let people = try? context.fetch(descriptor) else { return }
    SkySnapshotStore.save(SnapshotBuilder.make(from: people))
    WidgetCenter.shared.reloadAllTimelines()
}
