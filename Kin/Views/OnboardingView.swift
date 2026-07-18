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
        .onChange(of: step) { old, new in
            // Haptic crescendo: each step lands a touch warmer than the last,
            // peaking at the moment the sky is revealed.
            Haptics.shared.ignition(
                luminosity: new == .sky ? 1.0 : min(0.85, 0.3 + Double(new.rawValue) * 0.09))
            analytics.track(.onboardingStep(step: new.rawValue, completed: true))
            // Entering orbits: the backdrop sky dives away so the star on
            // stage holds the room alone. (The return trip happens in
            // orbitsStep's onFinished, timed with the carousel's pull-back.)
            if new == .orbits {
                skyScene.setOnboardingCamera(zoomedIn: true, duration: 1.0)
            } else if old == .orbits && new != .sky {
                skyScene.setOnboardingCamera(zoomedIn: false, duration: 0.6) // safety net
            }
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
                .poeticReveal()
            Text("Everyone you love is a light.")
                .font(KinType.heroLine).foregroundStyle(.white.opacity(0.9))
                .poeticReveal(delay: 0.4)
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

    // 3 — orbits. The camera glides in; each person's star waits at the left
    // edge with its orbits sweeping the full width of the screen. Choosing
    // one turns the great unseen plate, and the next star swings into place.
    private var orbitsStep: some View {
        OrbitCarousel(
            stars: lights.map {
                OrbitCarousel.StarInfo(
                    name: $0.name,
                    temperature: SkyLayout.temperature(colorSeed: $0.seed))
            },
            onSelect: { name, cadence in orbits[name] = cadence },
            onWillFinish: {
                // Begin the camera's return while the carousel recedes —
                // both motions read as one pull-back.
                skyScene.setOnboardingCamera(zoomedIn: false, duration: 1.1)
            },
            onFinished: {
                createStars()
                step = .sky // the sky has brightened back; just name the moment
            }
        )
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
                    .poeticReveal(delay: 0.15)
                Text(isReplay && !existingPeople.isEmpty
                     ? "\(existingPeople.count) star\(existingPeople.count == 1 ? "" : "s"), still glowing."
                     : "Tend it, and it glows.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .poeticReveal(delay: 0.6)
                Button("Continue") { step = .demo }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
                    .padding(.top, 4)
                    .poeticReveal(delay: 1.1)
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

    /// The first star the user created — name and color both real, so the
    /// widget pitch is personally theirs from the first second.
    private var firstStar: (name: String, temperature: Double) {
        if let light = lights.first {
            return (light.name, SkyLayout.temperature(colorSeed: light.seed))
        }
        if let person = existingPeople.min(by: { $0.createdAt < $1.createdAt }) {
            return (person.name, SkyLayout.temperature(colorSeed: person.colorSeed))
        }
        return ("Mom", 0.2)
    }

    /// A single, larger star — the One Star widget — showing the first
    /// person the user named, with their name beneath.
    private var oneStarPreview: some View {
        let star = firstStar
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
            Text(star.name.uppercased())
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
                .poeticReveal(delay: 0.1)
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

// MARK: - Orbit carousel

/// The orbit step as a place, not a form.
///
/// Every star waits on the rim of a great unseen plate whose center lies far
/// off-screen to the left. One star at a time rests at the screen's left
/// edge, vertically centered, its four orbits sweeping the full width of the
/// display — the farther the ring, the rarer the crossing. Choosing an orbit
/// turns the plate: the current star swings away along the rim while the
/// next swings in. When the last is answered, the camera pulls back and the
/// sky they lit is simply *there*.
private struct OrbitCarousel: View {
    struct StarInfo {
        let name: String
        let temperature: Double
    }

    let stars: [StarInfo]
    let onSelect: (String, OrbitCadence) -> Void
    /// Fired the moment the pull-back begins — lets the host reverse the
    /// backdrop camera in the same breath.
    var onWillFinish: () -> Void = {}
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var plateRotation: Double = 0
    @State private var selected: OrbitCadence?
    @State private var chromeVisible = false   // rings, labels, question
    @State private var transitioning = false
    @State private var cameraScale: CGFloat = 1.24
    @State private var cameraOffsetX: CGFloat = 70
    @State private var cameraOpacity: Double = 0

    /// Plate geometry: center far off-screen left; ~62° between neighbors is
    /// enough that only one star is ever meaningfully on screen.
    private let plateRadius: CGFloat = 400
    private let stepAngle: Double = .pi * 62 / 180
    private let cadences = OrbitCadence.allCases

    var body: some View {
        GeometryReader { geo in
            let anchor = CGPoint(x: 28, y: geo.size.height / 2)
            let plateCenter = CGPoint(x: anchor.x - plateRadius, y: anchor.y)
            let maxR = geo.size.width - anchor.x - 18 // outermost ring stays on screen
            let radii = [0.32, 0.55, 0.78, 1.0].map { maxR * CGFloat($0) }

            ZStack {
                // ── The space itself (camera-transformed) ──────────────────
                ZStack {
                    ringsAndLabels(anchor: anchor, radii: radii)
                        .opacity(chromeVisible && !transitioning ? 1 : 0)
                        .animation(.easeInOut(duration: 0.35), value: chromeVisible)
                        .animation(.easeInOut(duration: 0.35), value: transitioning)

                    // Stars riding the plate rim. Position is pure geometry of
                    // (index, plateRotation), so one spring on plateRotation
                    // moves the whole heaven.
                    ForEach(Array(stars.enumerated()), id: \.offset) { i, star in
                        let angle = Double(i) * stepAngle - plateRotation
                        Image(uiImage: SkyScene.starImage(temperature: star.temperature))
                            .resizable()
                            .frame(width: 46, height: 46)
                            .position(x: plateCenter.x + plateRadius * cos(angle),
                                      y: plateCenter.y + plateRadius * sin(angle))
                            .opacity(max(0, 1 - abs(angle) / (stepAngle * 0.75)))
                    }
                }
                .scaleEffect(cameraScale, anchor: UnitPoint(x: 0.12, y: 0.5))
                .offset(x: cameraOffsetX)
                .opacity(cameraOpacity)

                // ── The question (screen-fixed, above the camera) ──────────
                VStack(spacing: 10) {
                    if index < stars.count {
                        Text("How often do your paths cross with \(stars[index].name)?")
                            .font(KinType.title).foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .id(index)
                            .transition(.opacity)
                    }
                    // One line beneath: the hint, replaced by the chosen
                    // cadence's full poetic name the moment a ring is tapped.
                    Text(selected?.label ?? "Tap an orbit — the closer, the more often.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(selected == nil ? 0.45 : 0.85))
                        .id(selected?.rawValue ?? "hint")
                        .transition(.opacity)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(chromeVisible && !transitioning ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: transitioning)
                .animation(.easeInOut(duration: 0.25), value: selected)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, anchor: anchor, radii: radii)
            }
            .onAppear { enter() }
        }
        .accessibilityRepresentation { accessibleOrbits }
    }

    // MARK: Rings

    private func ringsAndLabels(anchor: CGPoint, radii: [CGFloat]) -> some View {
        ZStack {
            ForEach(Array(cadences.enumerated()), id: \.offset) { i, cadence in
                let r = radii[i]
                let isChosen = selected == cadence

                Circle()
                    .strokeBorder(.white.opacity(isChosen ? 0.85 : 0.20),
                                  lineWidth: isChosen ? 1.6 : 0.8)
                    .frame(width: r * 2, height: r * 2)
                    .position(anchor)

                // Short label riding its ring, staggered above/below the
                // horizontal so four capsules never crowd one axis.
                let labelAngle = Double(i % 2 == 0 ? -34 : 34) * .pi / 180
                Text(cadence.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(isChosen ? 0.95 : (selected == nil ? 0.65 : 0.3)))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.3), in: Capsule())
                    .position(x: anchor.x + r * CGFloat(cos(labelAngle)),
                              y: anchor.y + r * CGFloat(sin(labelAngle)))
            }

            // The moon settles onto the chosen ring.
            if let selected, let i = cadences.firstIndex(of: selected) {
                Circle().fill(.white).frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.8), radius: 5)
                    .position(x: anchor.x + radii[i], y: anchor.y)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Interaction

    private func handleTap(at location: CGPoint, anchor: CGPoint, radii: [CGFloat]) {
        guard chromeVisible, !transitioning, selected == nil, index < stars.count else { return }
        // Distance from the star = which orbit. Forgiving by construction:
        // anywhere on screen resolves to the nearest ring, within a band.
        let d = hypot(location.x - anchor.x, location.y - anchor.y)
        guard let nearest = radii.enumerated().min(by: { abs($0.1 - d) < abs($1.1 - d) }),
              abs(nearest.1 - d) < 48 else { return }
        choose(cadences[nearest.0])
    }

    private func choose(_ cadence: OrbitCadence) {
        withAnimation(.easeOut(duration: 0.3)) { selected = cadence }
        Haptics.shared.ignition(luminosity: 0.7)
        onSelect(stars[index].name, cadence)
        Task {
            try? await Task.sleep(nanoseconds: 850_000_000) // let the choice land
            if index >= stars.count - 1 {
                exitAndFinish()
            } else {
                advance()
            }
        }
    }

    /// Turn the plate: chrome fades, the rim rotates one notch, the next
    /// star swings up into the anchor, chrome returns.
    private func advance() {
        transitioning = true
        if reduceMotion {
            plateRotation += stepAngle
            index += 1
            selected = nil
            transitioning = false
            return
        }
        withAnimation(.spring(response: 0.95, dampingFraction: 0.86)) {
            plateRotation += stepAngle
        }
        Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            index += 1
            selected = nil
            transitioning = false
        }
    }

    // MARK: Camera

    /// The glide in: space scales down from 1.24 while panning left, and the
    /// first star sweeps up the rim into its place — arriving, not appearing.
    private func enter() {
        if reduceMotion {
            cameraScale = 1; cameraOffsetX = 0; cameraOpacity = 1
            plateRotation = 0; chromeVisible = true
            return
        }
        plateRotation = -stepAngle * 0.45
        withAnimation(.easeOut(duration: 1.0)) {
            cameraOpacity = 1; cameraScale = 1; cameraOffsetX = 0
        }
        withAnimation(.spring(response: 1.05, dampingFraction: 0.85).delay(0.15)) {
            plateRotation = 0
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            chromeVisible = true
        }
    }

    /// The pull back: rings dissolve, space recedes, and what's left when we
    /// let go is the sky itself (the living backdrop behind this view).
    private func exitAndFinish() {
        if reduceMotion {
            onWillFinish()
            onFinished()
            return
        }
        // Two beats, strictly in sequence: the orbit scene leaves the stage
        // completely… then the sky returns to an empty room. No overlap —
        // the beat of darkness between them is what makes the reveal land.
        chromeVisible = false
        withAnimation(.easeInOut(duration: 0.8).delay(0.05)) {
            cameraScale = 0.5
            cameraOpacity = 0
        }
        Task {
            try? await Task.sleep(nanoseconds: 950_000_000)  // scene fully gone
            onWillFinish()                                    // now the sky brightens back
            try? await Task.sleep(nanoseconds: 1_000_000_000) // let it mostly land
            onFinished()
        }
    }

    // MARK: Accessibility

    /// VoiceOver skips the theater: one question, four buttons.
    private var accessibleOrbits: some View {
        VStack {
            if index < stars.count {
                Text("How often do your paths cross with \(stars[index].name)?")
                ForEach(cadences, id: \.self) { cadence in
                    Button(cadence.label) { choose(cadence) }
                }
            }
        }
    }
}

// MARK: - Poetic reveal

/// Lines are spoken, not shown: rise, un-blur, fade in — staggered by delay
/// so a screen reads like a breath, not a layout. Reduce Motion keeps the
/// fade, drops the motion.
struct PoeticReveal: ViewModifier {
    let delay: Double
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 10)
            .blur(radius: revealed || reduceMotion ? 0 : 4)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9).delay(delay)) { revealed = true }
            }
    }
}

extension View {
    func poeticReveal(delay: Double = 0) -> some View {
        modifier(PoeticReveal(delay: delay))
    }
}

private extension OrbitCadence {
    /// Compact ring labels; the full poetic label confirms under the question.
    var shortLabel: String {
        switch self {
        case .mostDays:       return "Most days"
        case .weekly:         return "Most weeks"
        case .everyFewMonths: return "Some seasons"
        case .rarely:         return "Rarely"
        }
    }
}
