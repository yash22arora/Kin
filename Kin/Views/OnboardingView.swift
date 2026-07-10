import SwiftUI
import SwiftData
import StoreKit

/// The first 90 seconds. Full-screen, dark, skippable at every step.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @AppStorage("stargazingHour") private var stargazingHour = 21
    @AppStorage("stargazingEnabled") private var stargazingEnabled = false
    let onComplete: () -> Void

    private enum Step: Int { case light, names, orbits, sky, demo, ritual, widget, deal }
    @State private var step: Step = .light
    @State private var names: [String] = []
    @State private var currentName = ""
    @State private var orbits: [String: OrbitCadence] = [:]
    @State private var heroBreathing = false

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
            case .demo:   GlowDemoView { step = .ritual }
            case .ritual: ritualStep
            case .widget: widgetStep
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
                .font(.title3).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { step = .names }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to continue")
    }

    // 2 — name the lights
    private var namesStep: some View {
        VStack(spacing: 24) {
            Text("Who lights up your life?")
                .font(.title2).foregroundStyle(.white)
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
                    .font(.title3).foregroundStyle(.white)
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
        for name in names {
            context.insert(Person(name: name, orbit: orbits[name] ?? .weekly))
        }
        analytics.track(.starCreated(countBucket: names.count <= 3 ? "1-3" : names.count <= 7 ? "4-7" : "8+"))
        syncSiriVocabulary() // Siri learns the names as soon as they exist
    }

    // 4/5 — the reveal
    private var skyStep: some View {
        VStack(spacing: 24) {
            Text("This is your sky on \(Date.now.formatted(.dateTime.month(.wide).day())).")
                .font(.title3).foregroundStyle(.white)
            Text("Tend it, and it glows.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))
            Button("Continue") { step = .demo }
                .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
        }
    }

    // 6 — stargazing hour (the only permission ask, and only if they opt in)
    private var ritualStep: some View {
        VStack(spacing: 24) {
            Text("A small evening ritual?")
                .font(.title3).foregroundStyle(.white)
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
                    step = .widget
                }
            }
            .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
            Button("Maybe later") { step = .widget }
                .font(.footnote).foregroundStyle(.white.opacity(0.4))
        }
        .padding()
    }

    // 7 — widget invite
    private var widgetStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            Text("Keep your sky on your home screen.")
                .font(.title3).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Touch and hold your home screen, tap +, and look for Kin. Your stars, glowing at a glance.")
                .font(.footnote).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Continue") { step = .deal }
                .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
        }
        .padding(32)
    }

    // 8 — the deal, transparent
    private var dealStep: some View {
        VStack(spacing: 24) {
            Text("The deal, plainly.")
                .font(.title3).foregroundStyle(.white)
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
