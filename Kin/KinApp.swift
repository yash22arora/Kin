import SwiftUI
import SwiftData

@main
struct KinApp: App {
    let container: ModelContainer

    init() {
        // Shared with App Intents — Siri and the app must see the same store.
        // (iCloud parked; see KinModelContainer for the re-enable recipe.)
        container = KinModelContainer.shared
        Store.shared.start()
        FeatureFlags.refresh()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark) // the sky is always night
                .environment(\.analytics, AnalyticsFactory.shared)
        }
        .modelContainer(container)
    }
}

/// Routes: onboarding → (lock) → (trial gate) → sky.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("faceIDLock") private var faceIDLock = false
    @State private var unlockedThisSession = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundTick = false // re-evaluates the trial gate on return

    /// Stars currently lit — the trial gate cares only about these.
    @Query(filter: #Predicate<Person> { $0.stateRaw != "released" && !$0.isDormant })
    private var litStars: [Person]
    private let store = Store.shared

    /// Trial over, not unlocked, and more stars lit than the free sky allows:
    /// the user chooses — unlock, or pick three. Clears itself either way.
    private var trialGateNeeded: Bool {
        _ = foregroundTick
        return !store.hasFullAccess && litStars.count > Store.freeStarLimit
    }

    var body: some View {
        ZStack {
            // The night, always underneath. Kills the white flash during
            // view swaps (SpriteView takes a frame to draw its first sky)
            // and seams perfectly with the launch screen's background.
            Color(red: 0.031, green: 0.031, blue: 0.102)
                .ignoresSafeArea()

            if !hasCompletedOnboarding {
                OnboardingView { hasCompletedOnboarding = true }
            } else if faceIDLock && !unlockedThisSession {
                LockView { unlockedThisSession = true }
            } else if trialGateNeeded {
                TrialEndedView()
            } else {
                SkyView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-lock when the app goes to background.
            if phase == .background { unlockedThisSession = false }
            // Trial may have lapsed while the app slept.
            if phase == .active { foregroundTick.toggle() }
        }
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { restoreDormantStars() } // the promise, kept instantly
        }
        .onAppear {
            if store.isUnlocked { restoreDormantStars() } // safety net (e.g. restore on another device)
        }
    }
}
