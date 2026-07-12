import SwiftUI
import SwiftData
import SpriteKit
import StoreKit

/// The first 90 seconds. Full-screen, dark, skippable at every step.
/// Also serves as the replayable tour ("walk through Kin again" in settings):
/// with `isReplay`, existing stars are honored — no re-collection, no
/// duplicates, no pricing pitch — just the features, revisited.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @AppStorage("stargazingHour") private var stargazingHour = 21
    @AppStorage("stargazingEnabled") private var stargazingEnabled = false
    @Query(filter: #Predicate<Person> { $0.stateRaw != "released" })
    private var existingPeople: [Person]

    var isReplay: Bool = false
    let onComplete: () -> Void

    private enum Step: Int { case light, names, orbits, sky, demo, widget, ritual, deal }
    @State private var step: Step = .light

    /// A name given a stable seed the moment it's typed, so the star it ignites
    /// sits at the exact position (and wears the exact color) it will hold in
    /// the real sky — the seed is carried through to the created `Person`.
    private struct Light: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var seed: Int
    }
    @State private var lights: [Light] = []
    private var names: [String] { lights.map(\.name) }

    @State private var currentName = ""
    @State private var orbits: [String: OrbitCadence] = [:]
    @State private var heroBreathing = false

    /// One live SpriteKit sky behind every step: ambient dust + faint stars,
    /// with the user's own stars igniting into place as they're named.
    @State private var skyScene = SkyScene()
    /// Widget demo: which card is showing, and whether both have been seen.
    @State private var widgetCardIndex = 0
    @State private var widgetBothSeen = false

    /// The real star artwork — the same sparkle the sky renders.
    private static let heroStar = SkyScene.starImage(temperature: 0.2)

    var body: some View {
        ZStack {
            // The living sky, behind everything. Purely decorative here —
            // never steals a touch from the fields and buttons above it.
            SpriteView(scene: skyScene, options: [.allowsTransparency])
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            switch step {
            case .light:  lightStep
            case .names:  namesStep
            case .orbits: orbitsStep
            case .sky:    skyStep
            case .demo:   GlowDemoView { step = .widget }
            case .widget: widgetStep
            case .ritual: ritualStep
            case .deal:   dealStep
            }
        }
        .animation(.easeInOut(duration: 0.8), value: step)
        .onAppear(perform: configureSky)
        .onChange(of: step) { _, new in
            analytics.track(.onboardingStep(step: new.rawValue, completed: true))
        }
    }

    // MARK: The living backdrop

    /// Turn on the ambient starfield and reflect whatever sky already exists
    /// (empty on a fresh run; the user's stars on replay).
    private func configureSky() {
        skyScene.showsAmbientStarfield = true
        applySky()
    }

    /// Push the current onboarding sky into the scene. While names are being
    /// given, the backdrop is built from the seeded `lights` so each addition
    /// ignites in place; once there are none to show (replay), it falls back to
    /// the real saved sky.
    private func applySky() {
        skyScene.apply(onboardingSnapshot())
    }

    private func onboardingSnapshot() -> SkySnapshot {
        guard !lights.isEmpty else { return SnapshotBuilder.make(from: existingPeople) }
        let total = lights.count
        let stars = lights.enumerated().map { index, light -> SkySnapshot.Star in
            let pos = SkyLayout.seededPosition(seed: light.seed, index: index, total: total)
            return SkySnapshot.Star(
                id: light.id, name: light.name, x: pos.x, y: pos.y,
                luminosity: 0.72,
                temperature: SkyLayout.temperature(colorSeed: light.seed),
                isRemembered: false)
        }
        return SkySnapshot(stars: stars, lines: [])
    }

    // 1 — "Everyone you love is a light."
    private var lightStep: some View {
        VStack(spacing: 32) {
            Image(uiImage: Self.heroStar)
                .resizable()
                .frame(width: 48, height: 48)
                .scaleEffect(heroBreathing ? 1.08 : 0.92)
                .opacity(heroBreathing ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                           value: heroBreathing)
                .onAppear { heroBreathing = true }
            Text("Everyone you love is a light.")
                .font(KinType.heroLine).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // Replaying with a sky already full? Skip straight to the reveal.
            step = (isReplay && !existingPeople.isEmpty) ? .sky : .names
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to continue")
    }

    // 2 — name the lights. Each name ignites a star in the sky behind, at the
    // very spot it will occupy forever.
    private var namesStep: some View {
        VStack(spacing: 24) {
            Text("Who lights up your life?")
                .font(KinType.title).foregroundStyle(.white)
            Text(lights.isEmpty
                 ? "Name a few. Watch them take their place."
                 : "\(lights.count) up so far. Name as many as you like.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))
                .animation(.easeInOut, value: lights.count)

            TextField("A name", text: $currentName)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .submitLabel(lights.isEmpty ? .next : .done)
                .onSubmit(addName)
                .padding(.horizontal, 60)

            if !lights.isEmpty {
                Button("That's everyone, for now") { step = .orbits }
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding()
    }

    private func addName() {
        let trimmed = currentName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation { lights.append(Light(name: trimmed, seed: Int.random(in: 0..<1_000_000))) }
        applySky() // the new star ignites at its real, seeded position
        Haptics.shared.ignition(luminosity: min(1, 0.4 + Double(lights.count) * 0.1))
        currentName = ""
    }

    // 3 — orbits, one poetic question per person
    private var orbitsStep: some View {
        let unanswered = names.first { orbits[$0] == nil }
        return VStack(spacing: 24) {
            if let name = unanswered {
                Text("How often do your paths cross with \(name)?")
                    .font(KinType.title).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                ForEach(OrbitCadence.allCases, id: \.self) { orbit in
                    Button(orbit.label) {
                        orbits[name] = orbit
                        if names.allSatisfy({ orbits[$0] != nil }) {
                            createStars()
                            step = .sky
                        }
                    }
                    .buttonStyle(.bordered).tint(.white.opacity(0.4))
                }
            }
        }
        .padding()
    }

    private func createStars() {
        // Never duplicate an existing star (matters on replay, and protects
        // against "Mom" typed twice in a fresh run).
        let existing = Set(existingPeople.map { $0.name.lowercased() })
        var seen = Set<String>()
        for light in lights {
            let key = light.name.lowercased()
            guard !existing.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            let person = Person(name: light.name, orbit: orbits[light.name] ?? .weekly)
            person.colorSeed = light.seed // keep the seed → same spot, same color
            context.insert(person)
        }
        analytics.track(.starCreated(countBucket: lights.count <= 3 ? "1-3" : lights.count <= 7 ? "4-7" : "8+"))
        syncSiriVocabulary() // Siri learns the names as soon as they exist
    }

    // 4/5 — the reveal. No new scene: the sky they lit while naming *is* the
    // sky revealed here. Just settle a scrim over it and name the moment.
    private var skyStep: some View {
        ZStack {
            // A soft scrim so the copy stays legible over the stars.
            LinearGradient(
                colors: [.clear, Color(red: 0.01, green: 0.01, blue: 0.05).opacity(0.8)],
                startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Text("This is your sky on \(Date.now.formatted(.dateTime.month(.wide).day())).")
                    .font(KinType.title).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(isReplay && !existingPeople.isEmpty
                     ? "\(existingPeople.count) star\(existingPeople.count == 1 ? "" : "s"), still glowing."
                     : "Tend it, and it glows.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                Button("Continue") { step = .demo }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
                    .padding(.top, 4)
            }
            .padding()
            .padding(.bottom, 48)
        }
    }

    // 6 — stargazing hour (the only permission ask, and only if they opt in)
    private var ritualStep: some View {
        VStack(spacing: 24) {
            Text("A small evening ritual?")
                .font(KinType.title).foregroundStyle(.white)
            Text("One quiet reminder a day: “The sky is out.”\nNever more. Never about anyone.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Picker("Hour", selection: $stargazingHour) {
                ForEach(17..<24, id: \.self) { h in
                    Text("\(h % 12 == 0 ? 12 : h % 12) PM").tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
            Button("Set my stargazing hour") {
                Task {
                    if await NotificationScheduler.requestPermission() {
                        NotificationScheduler.schedule(hour: stargazingHour)
                        stargazingEnabled = true
                        analytics.track(.notificationOptIn)
                    }
                    advanceFromRitual()
                }
            }
            .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
            Button("Maybe later") { advanceFromRitual() }
                .font(.footnote).foregroundStyle(.white.opacity(0.4))
        }
        .padding()
    }

    /// Ritual is now the last stop before the pitch. Replays, which skip the
    /// pitch entirely, finish here.
    private func advanceFromRitual() {
        if isReplay { onComplete() } else { step = .deal }
    }

    // 7 — widget invite
    @State private var widgetBobbing = false

    /// A floating mock of the My Sky widget, rendering the user's actual
    /// stars — the same trick the home screen's widget gallery uses.
    private var widgetPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.03, green: 0.03, blue: 0.10),
                             Color(red: 0.07, green: 0.06, blue: 0.18)],
                    startPoint: .top, endPoint: .bottom))
            ForEach(Array(previewStars.enumerated()), id: \.offset) { _, star in
                Image(uiImage: SkyScene.pointImage(temperature: star.temperature))
                    .resizable()
                    .frame(width: 10 + star.luminosity * 14,
                           height: 10 + star.luminosity * 14)
                    .opacity(0.5 + 0.5 * star.luminosity)
                    .position(x: star.x * 158, y: star.y * 158)
            }
        }
        .frame(width: 158, height: 158)
        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
        .offset(y: widgetBobbing ? -7 : 7)
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                   value: widgetBobbing)
        .onAppear { widgetBobbing = true }
        .accessibilityHidden(true)
    }

    /// The user's real stars if they have any; a small demo sky otherwise.
    private var previewStars: [(x: Double, y: Double, luminosity: Double, temperature: Double)] {
        let people = existingPeople.sorted { $0.createdAt < $1.createdAt }.prefix(7)
        guard !people.isEmpty else {
            return [(0.30, 0.28, 0.9, 0.2), (0.68, 0.42, 0.6, 0.7),
                    (0.45, 0.66, 0.75, 0.45), (0.78, 0.75, 0.4, 0.9)]
        }
        return people.enumerated().map { index, person in
            let pos: (x: Double, y: Double) = person.positionX >= 0
                ? (person.positionX, person.positionY)
                : SkyLayout.seededPosition(seed: person.colorSeed, index: index, total: people.count)
            return (pos.x, pos.y, person.luminosity(),
                    SkyLayout.temperature(colorSeed: person.colorSeed))
        }
    }

    /// A single, larger star — the One Star widget — showing the brightest
    /// person the user just named (or a demo star), with their name beneath.
    private var oneStarPreview: some View {
        let star = previewStars.max { $0.luminosity < $1.luminosity }
            ?? (x: 0.5, y: 0.5, luminosity: 0.9, temperature: 0.2)
        return ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.03, green: 0.03, blue: 0.10),
                             Color(red: 0.07, green: 0.06, blue: 0.18)],
                    startPoint: .top, endPoint: .bottom))
            Image(uiImage: SkyScene.starImage(temperature: star.temperature))
                .resizable()
                .frame(width: 60, height: 60)
                .position(x: 79, y: 66)
            Text("MOM")
                .font(.system(size: 11, weight: .medium)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .position(x: 79, y: 120)
        }
        .frame(width: 158, height: 158)
        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
        .offset(y: widgetBobbing ? -7 : 7)
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                   value: widgetBobbing)
        .accessibilityHidden(true)
    }

    private var widgetStep: some View {
        VStack(spacing: 28) {
            // The two widget faces crossfade in place.
            ZStack {
                if widgetCardIndex == 0 {
                    widgetPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    oneStarPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(height: 176)
            .onAppear { widgetBobbing = true }

            Text(widgetCardIndex == 0
                 ? "Keep your whole sky on your home screen."
                 : "Or keep one star close.")
                .font(KinType.title).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .id("title\(widgetCardIndex)")
                .transition(.opacity)

            Text(widgetCardIndex == 0
                 ? "Touch and hold your home screen, tap +, and look for Kin. Every star, glowing at a glance."
                 : "Add the single-star widget for someone you're tending — one light, always in view.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .id("body\(widgetCardIndex)")
                .transition(.opacity)

            // Held back until both widget faces have been shown.
            if widgetBothSeen {
                Button("Continue") { step = .ritual }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
                    .transition(.opacity)
            }
        }
        .padding(32)
        .animation(.easeInOut(duration: 1.1), value: widgetCardIndex)
        .animation(.easeInOut(duration: 0.5), value: widgetBothSeen)
        .task {
            // Rotate the card every 5s; once the second face lands, the button
            // is allowed to appear.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                widgetCardIndex = (widgetCardIndex + 1) % 2
                if widgetCardIndex == 1 { widgetBothSeen = true }
            }
        }
    }

    // 8 — the deal, transparent
    private var dealStep: some View {
        VStack(spacing: 24) {
            Text("The deal, plainly.")
                .font(KinType.title).foregroundStyle(.white)
            Text("Kin is yours, fully, free for 7 days.\nThen \(Store.shared.lifetimeProduct?.displayPrice ?? "$4.99"), once, forever — or keep a free sky of 3 stars.\n\nNo subscription. No account.\nYour sky never leaves your device.")
                .font(.callout).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Begin") {
                analytics.track(.onboardingStep(step: Step.deal.rawValue + 1, completed: true))
                onComplete()
            }
            .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
        }
        .padding(32)
    }
}
