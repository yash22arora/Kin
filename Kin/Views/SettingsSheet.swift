import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @AppStorage("stargazingHour") private var stargazingHour = 21
    @AppStorage("stargazingEnabled") private var stargazingEnabled = false
    @AppStorage("faceIDLock") private var faceIDLock = false

    @Query(filter: #Predicate<Person> { $0.isDormant })
    private var restingStars: [Person]

    let store = Store.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Ritual") {
                    Toggle("Stargazing reminder", isOn: $stargazingEnabled)
                        .onChange(of: stargazingEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    if await NotificationScheduler.requestPermission() {
                                        NotificationScheduler.schedule(hour: stargazingHour)
                                    } else {
                                        stargazingEnabled = false
                                    }
                                }
                            } else {
                                NotificationScheduler.cancel()
                            }
                        }
                    if stargazingEnabled {
                        Picker("Stargazing hour", selection: $stargazingHour) {
                            ForEach(17..<24, id: \.self) { h in
                                Text("\(h % 12 == 0 ? 12 : h % 12) PM").tag(h)
                            }
                        }
                        .onChange(of: stargazingHour) { _, hour in
                            NotificationScheduler.schedule(hour: hour)
                        }
                    }
                }
                Section("Privacy") {
                    Toggle("Lock with Face ID", isOn: $faceIDLock)
                    NavigationLink("Export my sky") { ExportView() }
                }
                Section("Kin") {
                    if store.isUnlocked {
                        Label("Unlocked, forever", systemImage: "sparkles")
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        if !restingStars.isEmpty {
                            Text("\(restingStars.count) star\(restingStars.count == 1 ? " is" : "s are") resting — every moment kept. Unlock and they return.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        NavigationLink("Unlock Kin") { PaywallView() }
                        Button("Restore purchase") { Task { await store.restore() } }
                    }
                }
                Section("About") {
                    NavigationLink("How glow works") { HowGlowWorksView() }
                    Link("Support", destination: URL(string: "mailto:you@example.com")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Full export: everything the user ever put in, theirs to take anywhere.
struct ExportView: View {
    @Query private var people: [Person]
    @Query private var moments: [Moment]
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            if let url = exportURL {
                Text("Your sky, as a file. Photos stay in your library.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label("Share export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
            } else {
                ProgressView()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.03, green: 0.03, blue: 0.10))
        .navigationTitle("Export")
        .onAppear(perform: generate)
    }

    private func generate() {
        struct ExportMoment: Codable {
            let date: Date; let note: String; let feeling: String?
            let people: [String]; let hasPhoto: Bool
        }
        struct ExportPerson: Codable {
            let name: String; let orbit: String; let state: String; let since: Date
        }
        struct Export: Codable {
            let exportedAt: Date; let people: [ExportPerson]; let moments: [ExportMoment]
        }

        let export = Export(
            exportedAt: .now,
            people: people.map {
                ExportPerson(name: $0.name, orbit: $0.orbit.rawValue,
                             state: $0.state.rawValue, since: $0.createdAt)
            },
            moments: moments.map {
                ExportMoment(date: $0.timestamp, note: $0.note, feeling: $0.feelingRaw,
                             people: ($0.people ?? []).map(\.name), hasPhoto: $0.photoID != nil)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kin-export.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }
}

/// Transparency page — users deserve to know the rules of their own sky.
struct HowGlowWorksView: View {
    @State private var showTour = false

    var body: some View {
        ScrollView {
            Text("""
            Every moment you share adds warmth to a star. Warmth fades slowly — \
            over weeks, not days — and how fast depends on the orbit you chose \
            for each person. A friend you see twice a year keeps their glow for months.

            Stars never go dark. The softest a star can be is a quiet, distant \
            glow — because distance isn't failure, it's just distance.

            Nothing is scored. Nothing is a streak. Your sky just reflects, gently, \
            where the light has been lately.
            """)
            .foregroundStyle(.white.opacity(0.85))
            .padding()
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.10))
        .navigationTitle("How glow works")
        // Pinned to the bottom, alive: this is an invitation, not a setting.
        .safeAreaInset(edge: .bottom) {
            Button {
                showTour = true
            } label: {
                Label("Walk through Kin again", systemImage: "sparkles")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.10)],
                                       startPoint: .top, endPoint: .bottom),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
                    .shadow(color: .white.opacity(0.15), radius: 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .accessibilityHint("Replays the guided introduction. Your stars are untouched.")
        }
        .fullScreenCover(isPresented: $showTour) {
            OnboardingView(isReplay: true) { showTour = false }
        }
    }
}
