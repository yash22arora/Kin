import SwiftUI
import SwiftData
import SpriteKit
import WidgetKit

/// The home canvas. No tab bar — one spatial view with sheets.
struct SkyView: View {
    @Query(filter: #Predicate<Person> { $0.stateRaw != "released" })
    private var people: [Person]
    @Environment(\.analytics) private var analytics

    @State private var scene = SkyScene()
    @State private var selectedPersonID: UUID?
    @State private var showLogSheet = false
    @State private var showSettings = false
    @State private var starBirth: StarBirth?
    @State private var detailPersonID: UUID?

    /// Carries an add-star request (and its optional long-press birth point)
    /// through `.sheet(item:)`, so the sheet always reads the right position —
    /// `.sheet(isPresented:)` could capture a stale `birthPosition`.
    private struct StarBirth: Identifiable {
        let id = UUID()
        let position: (x: Double, y: Double)?
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.allowsTransparency])
                .ignoresSafeArea()
                .onAppear { configureScene() }
                .onChange(of: snapshot) { _, new in
                    scene.apply(new)
                    publishToWidget(new)
                }
                // VoiceOver: the scene pixels are unreadable; this replaces
                // them with a swipeable list of stars, each a button with a
                // custom "Log a moment" action. The sky, spoken.
                .accessibilityRepresentation { accessibleSky }

            VStack(alignment: .trailing) {
                header
                Spacer()
                logButton
            }
            .padding()
        }
        .sheet(isPresented: $showLogSheet) {
            LogMomentSheet(preselectedPersonID: selectedPersonID) { involvedIDs in
                // The payoff: shooting star toward the (first) involved star.
                if let id = involvedIDs.first { scene.runShootingStar(toward: id) }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(item: $starBirth, onDismiss: {
            scene.removeGhostStar() // cancelled births leave no ghost behind
        }) { birth in
            StarFormSheet(editing: nil, birthPosition: birth.position)
        }
        .sheet(item: selectedDetailPerson, onDismiss: { scene.unfocus() }) { person in
            StarDetailView(person: person) {
                selectedPersonID = person.id
                showLogSheet = true
            }
            // Half-height frosted glass: the real star, zoomed by the camera,
            // hangs above the sheet. Large detent available for long histories.
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        // The one reliable dismissal signal: sheet(item:) always nils the
        // binding, even when another sheet replaces it in the same beat
        // (onDismiss is skipped during that handoff — learned the hard way).
        .onChange(of: detailPersonID) { _, new in
            if new == nil { scene.unfocus() }
        }
        .onOpenURL(perform: handleDeepLink)
        .onAppear {
            analytics.track(.skyOpened(
                hourBucket: Calendar.current.component(.hour, from: .now),
                starCountBucket: people.count <= 3 ? "1-3" : people.count <= 7 ? "4-7" : "8+"
            ))
        }
    }

    // MARK: Accessibility

    /// The spoken sky: a header summary, then one button per star.
    private var accessibleSky: some View {
        VStack {
            Text(accessibilitySummary)
                .accessibilityAddTraits(.isHeader)
            ForEach(people.sorted { $0.createdAt < $1.createdAt }) { person in
                Button {
                    scene.focus(on: person.id)
                    selectedPersonID = person.id
                    detailPersonID = person.id
                } label: {
                    Text("\(person.name). \(brightness(of: person)).")
                }
                .accessibilityHint("Opens their star.")
                .accessibilityAction(named: "Log a moment") {
                    selectedPersonID = person.id
                    showLogSheet = true
                }
            }
        }
    }

    private func brightness(of person: Person) -> String {
        if person.state == .remembered { return "Remembered, holding steady" }
        let lum = person.luminosity()
        if lum > 0.7 { return "Burning bright" }
        if lum > 0.45 { return "Glowing softly" }
        return "A little distant"
    }

    // MARK: Deep links (kin://log, kin://star/<uuid>)

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "kin" else { return }
        switch url.host {
        case "log":
            selectedPersonID = nil
            showLogSheet = true
            analytics.track(.widgetTap(kind: "sky"))
        case "star":
            let idString = url.pathComponents.dropFirst().first ?? ""
            if let id = UUID(uuidString: idString), people.contains(where: { $0.id == id }) {
                detailPersonID = id
                analytics.track(.widgetTap(kind: "onestar"))
            }
        default:
            break
        }
    }

    // MARK: Widget pipeline

    private func publishToWidget(_ snapshot: SkySnapshot) {
        SkySnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.footnote.smallCaps())
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            HStack(alignment: .center, spacing: 0) {
                Button { starBirth = StarBirth(position: nil) } label: {
                    Image(systemName: "plus.viewfinder")
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 44, height: 44) // Apple-minimum hit target
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("New star")
                Button { showSettings = true } label: {
                    Image(systemName: "moon.stars")
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var logButton: some View {
        Button {
            selectedPersonID = nil
            showLogSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
        }
        .accessibilityLabel("Log a moment")
    }

    // MARK: Data → snapshot

    private var snapshot: SkySnapshot {
        SnapshotBuilder.make(from: people) // shared with App Intents
    }

    private func configureScene() {
        scene.apply(snapshot)
        publishToWidget(snapshot)
        // Flag-gated ambience. Evaluated on appear from PostHog's cache, so a
        // remote change takes effect on the next launch — good enough for vibes.
        // Shower supersedes lone comets. Debug defaults live on FeatureFlag.
        scene.ambientMode = FeatureFlags.isEnabled(.meteorShower) ? .meteorShower
                          : FeatureFlags.isEnabled(.randomComet) ? .comets
                          : .none
        scene.onStarTap = { id in
            scene.focus(on: id) // the sky leans in…
            selectedPersonID = id
            detailPersonID = id // …as the sheet rises
        }
        scene.onLongPress = { x, y in
            starBirth = StarBirth(position: (x, y))
        }
        scene.onStarMoved = { id, x, y in
            if let person = people.first(where: { $0.id == id }) {
                person.positionX = x
                person.positionY = y
            }
        }
    }

    // Sheet plumbing for star detail
    private var selectedDetailPerson: Binding<Person?> {
        Binding(
            get: { people.first { $0.id == detailPersonID } },
            set: { detailPersonID = $0?.id }
        )
    }

    private var accessibilitySummary: String {
        let bright = people.filter { $0.luminosity() > 0.7 }.count
        return "Your sky. \(people.count) stars, \(bright) bright tonight."
    }
}
