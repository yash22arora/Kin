import SwiftUI
import SwiftData
import WidgetKit
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @AppStorage("stargazingHour") private var stargazingHour = 21
    @AppStorage("stargazingEnabled") private var stargazingEnabled = false
    @AppStorage("faceIDLock") private var faceIDLock = false
    // App Group store, so widgets read the same value.
    @AppStorage(KinShared.dustBrightnessKey,
                store: UserDefaults(suiteName: KinShared.appGroupID))
    private var dustBrightness = 1.75
    @AppStorage(SkyPalette.variantKey,
                store: UserDefaults(suiteName: KinShared.appGroupID))
    private var skyMoodRaw = SkyPhaseVariant.auto.rawValue

    #if DEBUG
    /// Debug sky clock: hours 0–24, -1 = follow the real clock.
    @AppStorage("debugSkyHour") private var debugSkyHour: Double = -1

    private var debugTimeLabel: String {
        let h = Int(debugSkyHour)
        let m = Int((debugSkyHour - Double(h)) * 60)
        return String(format: "%02d:%02d", min(h, 23), m)
    }
    #endif

    /// LOW / MIDDLE / HIGH detents. The slider rests anywhere; these only
    /// speak through the haptics (and the brightening labels) when crossed.
    private let dustDetents: [Double] = [1.0, 1.75, 2.5]
    @State private var activeDustDetent: Double?

    /// Tiny tracked caption under the slider; lights up while the thumb
    /// sits in its detent's zone.
    private func detentLabel(_ text: String, detent: Double) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium)).tracking(1.2)
            .foregroundStyle(.white.opacity(
                abs(dustBrightness - detent) < 0.06 ? 0.85 : 0.3))
            .animation(.easeOut(duration: 0.2), value: dustBrightness)
    }

    @Query(filter: #Predicate<Person> { $0.isDormant })
    private var restingStars: [Person]

    @Environment(\.modelContext) private var context
    @State private var showImportWarning = false
    @State private var showImporter = false
    @State private var importResult: String?

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
                Section("Sky") {
                    Picker("Sky mood", selection: $skyMoodRaw) {
                        ForEach(SkyPhaseVariant.allCases, id: \.rawValue) { variant in
                            Text(variant.displayName).tag(variant.rawValue)
                        }
                    }
                    .onChange(of: skyMoodRaw) { _, _ in
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Star dust")
                        Slider(
                            value: $dustBrightness,
                            in: 1.0...2.5,
                            onEditingChanged: { editing in
                                // Widgets re-render once, when the finger lifts.
                                if !editing { WidgetCenter.shared.reloadAllTimelines() }
                            }
                        )
                        .onChange(of: dustBrightness) { _, new in
                            // A tick when the thumb passes a detent — the tick
                            // itself brightens with the detent, like the dust.
                            let zone = dustDetents.first { abs($0 - new) < 0.06 }
                            if let zone, zone != activeDustDetent {
                                Haptics.shared.ignition(
                                    luminosity: 0.25 + (zone - 1.0) / 1.5 * 0.5)
                            }
                            activeDustDetent = zone
                        }
                        HStack {
                            detentLabel("LOW", detent: dustDetents[0])
                            Spacer()
                            detentLabel("MEDIUM", detent: dustDetents[1])
                            Spacer()
                            detentLabel("HIGH", detent: dustDetents[2])
                        }
                        Text("The faint grain of distant stars, in the app and your widgets.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 2)
                    }
                }
                #if DEBUG
                Section("Debug — sky clock") {
                    if debugSkyHour >= 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Slider(value: $debugSkyHour, in: 0...24)
                            HStack {
                                Text(debugTimeLabel)
                                Spacer()
                                Text(String(format: "sun %+.1f°",
                                            SkyPalette.solarAltitude(hour: debugSkyHour, at: .now)))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                        }
                        Button("Follow the real clock") { debugSkyHour = -1 }
                    } else {
                        Button("Override time of day") { debugSkyHour = 18.5 }
                    }
                }
                #endif
                Section("Privacy") {
                    Toggle("Lock with Face ID", isOn: $faceIDLock)
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
                    NavigationLink("Export my sky") { ExportView() }
                    Button("Import a sky…") { showImportWarning = true }
                }
                Section("About") {
                    NavigationLink("How glow works") { HowGlowWorksView() }
                    Link("Support", destination: URL(string: "mailto:you@example.com")!)
                }
                Section("Legal") {
                    Link("Privacy Policy",
                         destination: URL(string: "https://kin.servatom.com/privacy")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Replace your sky?", isPresented: $showImportWarning) {
                Button("Import and replace", role: .destructive) { showImporter = true }
                Button("Keep my sky", role: .cancel) {}
            } message: {
                Text("Importing overwrites everything here now — every star and every moment. This can't be undone. Export your current sky first if you want to keep it.")
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): importSky(from: url)
                case .failure: importResult = "Couldn't open that file."
                }
            }
            .alert("Import", isPresented: .init(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )) {
                Button("OK") { importResult = nil }
            } message: {
                Text(importResult ?? "")
            }
        }
    }

    // MARK: Import

    /// Mirrors ExportView's JSON shape exactly. Photos aren't part of the
    /// export format, so imported moments arrive photoless.
    private struct SkyFile: Codable {
        struct FilePerson: Codable {
            let name: String; let orbit: String; let state: String; let since: Date
            let seed: Int; let x: Double; let y: Double
        }
        struct FileMoment: Codable {
            let date: Date; let note: String; let feeling: String?
            let people: [String]; let hasPhoto: Bool
        }
        let exportedAt: Date
        let people: [FilePerson]
        let moments: [FileMoment]
    }

    private func importSky(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(SkyFile.self, from: data) else {
            importResult = "That file doesn't look like a Kin sky export."
            return
        }

        // Wipe the current sky — people, moments, and photo files.
        // (Person→Moment delete rule is .nullify, so moments go explicitly.)
        if let moments = try? context.fetch(FetchDescriptor<Moment>()) {
            for moment in moments {
                if let photoID = moment.photoID { PhotoStore.delete(id: photoID) }
                context.delete(moment)
            }
        }
        if let people = try? context.fetch(FetchDescriptor<Person>()) {
            for person in people { context.delete(person) }
        }

        // Rebuild from the file. Names link moments to people, as exported.
        var byName: [String: Person] = [:]
        for entry in file.people {
            let person = Person(name: entry.name,
                                orbit: OrbitCadence(rawValue: entry.orbit) ?? .weekly)
            person.state = StarState(rawValue: entry.state) ?? .active
            person.createdAt = entry.since
            person.colorSeed = entry.seed // same color…
            // …same place — but hand-edited files don't get to put stars
            // off-screen. Out-of-range coords fall back to reseeding.
            if (0.0...1.0).contains(entry.x) && (0.0...1.0).contains(entry.y) {
                person.positionX = entry.x
                person.positionY = entry.y
            }
            context.insert(person)
            byName[entry.name.lowercased()] = person
        }
        for entry in file.moments {
            let involved = entry.people.compactMap { byName[$0.lowercased()] }
            guard !involved.isEmpty else { continue }
            let moment = Moment(timestamp: entry.date, note: entry.note,
                                people: involved,
                                feeling: entry.feeling.flatMap(Feeling.init(rawValue:)))
            context.insert(moment)
        }
        try? context.save()

        // Entitlement guard: if this import trips the trial gate (locked +
        // more lit stars than the free sky allows), widgets and Siri must NOT
        // learn the oversized sky — the keep-3 choice republishes both after
        // the user resolves the gate. Without this, import-then-force-quit
        // would leave a >3-star sky on the home screen forever, unpaid.
        let lit = byName.values.filter { $0.state != .released && !$0.isDormant }.count
        if store.hasFullAccess || lit <= Store.freeStarLimit {
            publishSky(context: context)
            syncSiriVocabulary()
        }
        Haptics.shared.ignition(luminosity: 0.9)
        importResult = "Sky imported — \(file.people.count) star\(file.people.count == 1 ? "" : "s"), \(file.moments.count) moment\(file.moments.count == 1 ? "" : "s"). Photos aren't carried by exports, so those start fresh."
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
            let seed: Int; let x: Double; let y: Double // full sky fidelity
        }
        struct Export: Codable {
            let exportedAt: Date; let people: [ExportPerson]; let moments: [ExportMoment]
        }

        let export = Export(
            exportedAt: .now,
            people: people.map {
                ExportPerson(name: $0.name, orbit: $0.orbit.rawValue,
                             state: $0.state.rawValue, since: $0.createdAt,
                             seed: $0.colorSeed, x: $0.positionX, y: $0.positionY)
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
