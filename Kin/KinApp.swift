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

/// Routes: onboarding → (lock) → sky.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("faceIDLock") private var faceIDLock = false
    @State private var unlockedThisSession = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView { hasCompletedOnboarding = true }
            } else if faceIDLock && !unlockedThisSession {
                LockView { unlockedThisSession = true }
            } else {
                SkyView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-lock when the app goes to background.
            if phase == .background { unlockedThisSession = false }
        }
    }
}
