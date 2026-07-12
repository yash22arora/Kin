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
    @State private var names: [String] = []
    @State private var currentName = ""
    @State private var orbits: [String: OrbitCadence] = [:]
    @State private var heroBreathing = false

    /// Live SpriteKit sky rendered behind the reveal step.
    @State private var revealScene = SkyScene()
    /// Widget demo: which card is showing, and whether both have been seen.
    @State private var widgetCardIndex = 0
    @State private var widgetBothSeen = false

    /// The real star artwork — the same sparkle the sky renders.
    private static let heroStar = SkyScene.starImage(temperature: 0.2)

    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.01, blue: 0.05).ignoresSafeArea()
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
        .onChange(of: step) { _, new in
            analytics.track(.onboardingStep(step: new.rawValue, completed: true))
        }
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

    // 2 — name the lights
    private var namesStep: some View {
        VStack(spacing: 24) {
            Text("Who lights up your life?")
                .font(KinType.title).foregroundStyle(.white)
            Text("Name a few. You can always add more.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 12) {
                ForEach(Array(names.enumerated()), id: \.element) { index, _ in
                    Image(uiImage: SkyScene.starImage(temperature: Double(index % 5) / 5))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 22)

            TextField("A name", text: $currentName)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .submitLabel(names.isEmpty ? .next : .done)
                .onSubmit(addName)
                .padding(.horizontal, 60)

            if !names.isEmpty {
                Button("That's everyone, for now") { step = .orbits }
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding()
    }

    private func addName() {
        let trimmed = currentName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation { names.append(trimmed) }
        Haptics.shared.ignition(luminosity: min(1, 0.4 + Double(names.count) * 0.1))
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
        for name in names {
            let key = name.lowercased()
            guard !existing.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            context.insert(Person(name: name, orbit: orbits[name] ?? .weekly))
        }
        analytics.track(.starCreated(countBucket: names.count <= 3 ? "1-3" : names.count <= 7 ? "4-7" : "8+"))
        syncSiriVocabulary() // Siri learns the names as soon as they exist
    }

    // 4/5 — the reveal. The real starfield, rendered behind the words.
    private var skyStep: some View {
        ZStack {
            SpriteView(scene: revealScene, options: [.allowsTransparency])
                .ignoresSafeArea()
                .onAppear { revealScene.apply(SnapshotBuilder.make(from: existingPeople)) }
                .accessibilityHidden(true)

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
