import SwiftUI

// Privacy-first analytics: measure the product, never the people in it.
// No note contents, no names, no photos, no identifiers.
// Swap NoopAnalytics for a TelemetryDeck-backed client without touching call sites.

enum AnalyticsEvent {
    case onboardingStep(step: Int, completed: Bool)
    case starCreated(countBucket: String)
    case momentLogged(source: String, hasNote: Bool, hasPhoto: Bool, peopleCount: Int, backdated: Bool)
    case skyOpened(hourBucket: Int, starCountBucket: String)
    case widgetTap(kind: String)
    case paywallViewed(daySinceInstall: Int)
    case purchase
    case starReleased
    case starRemembered
    case notificationOptIn
    case momentEdited
    case momentDeleted
    case starsRested(count: Int)
    case starsRestored(count: Int)

    var name: String {
        switch self {
        case .onboardingStep: "onboarding_step"
        case .starCreated: "star_created"
        case .momentLogged: "moment_logged"
        case .skyOpened: "sky_opened"
        case .widgetTap: "widget_tap"
        case .paywallViewed: "paywall_viewed"
        case .purchase: "purchase"
        case .starReleased: "star_released"
        case .starRemembered: "star_remembered"
        case .notificationOptIn: "notification_opt_in"
        case .momentEdited: "moment_edited"
        case .momentDeleted: "moment_deleted"
        case .starsRested: "stars_rested"
        case .starsRestored: "stars_restored"
        }
    }
}

extension AnalyticsEvent {
    /// Non-PII payloads only — buckets and booleans, never content or names.
    var parameters: [String: String] {
        switch self {
        case .onboardingStep(let step, let completed):
            return ["step": "\(step)", "completed": "\(completed)"]
        case .starCreated(let countBucket):
            return ["countBucket": countBucket]
        case .momentLogged(let source, let hasNote, let hasPhoto, let peopleCount, let backdated):
            return ["source": source, "hasNote": "\(hasNote)", "hasPhoto": "\(hasPhoto)",
                    "peopleCount": "\(peopleCount)", "backdated": "\(backdated)"]
        case .skyOpened(let hourBucket, let starCountBucket):
            return ["hourBucket": "\(hourBucket)", "starCountBucket": starCountBucket]
        case .widgetTap(let kind):
            return ["kind": kind]
        case .paywallViewed(let daySinceInstall):
            return ["daySinceInstall": "\(daySinceInstall)"]
        case .starsRested(let count), .starsRestored(let count):
            return ["count": "\(count)"]
        default:
            return [:]
        }
    }
}

protocol AnalyticsClient {
    func track(_ event: AnalyticsEvent)
}

struct NoopAnalytics: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        #if DEBUG
        print("[analytics] \(event.name)")
        #endif
    }
}

// MARK: - TelemetryDeck (privacy-first, no PII, no IDFA)
// To activate:
//   1. Xcode → File → Add Package Dependencies →
//      https://github.com/TelemetryDeck/SwiftSDK  (add to Kin target)
//   2. Create an app at dashboard.telemetrydeck.com, paste its ID below.
//   3. Update the App Store privacy label: "Usage Data — not linked to you."
// Until both are done, this compiles out and Noop stays active.

enum AnalyticsFactory {
    static let postHogAPIKey = "phc_CqezDHhg42W8CMX8zWHhw7RWRkQHGLeyR86DDQFBaJZK"
    static let postHogHost = "https://us.i.posthog.com" // or eu.i.posthog.com

    /// Legacy option — TelemetryDeck, if you ever prefer it.
    static let telemetryDeckAppID = ""

    /// Memoized — SwiftUI body re-evaluations must not re-run PostHog setup.
    static let shared: AnalyticsClient = makeClient()

    private static func makeClient() -> AnalyticsClient {
        #if canImport(PostHog)
        if !postHogAPIKey.isEmpty {
            return PostHogAnalytics(apiKey: postHogAPIKey, host: postHogHost)
        }
        #endif
        #if canImport(TelemetryDeck)
        if !telemetryDeckAppID.isEmpty {
            return TelemetryDeckAnalytics(appID: telemetryDeckAppID)
        }
        #endif
        return NoopAnalytics()
    }
}

// MARK: - PostHog (events + feature flags)
// Resolves via SPM (github.com/PostHog/posthog-ios, 3.56.0+). Configured
// privacy-first: no screen autocapture, no session replay, anonymous —
// we never call identify(), so no person profiles are created.

#if canImport(PostHog)
import PostHog

struct PostHogAnalytics: AnalyticsClient {
    init(apiKey: String, host: String) {
        let config = PostHogConfig(projectToken: apiKey, host: host)
        config.captureScreenViews = false          // we track meaning, not screens
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
    }

    func track(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.parameters)
    }
}
#endif

/// Every feature flag in the app, in one place. Add a case here, create the
/// flag in PostHog with the same raw value, and gate code with
/// `FeatureFlags.isEnabled(.myFlag)`. Never use string literals at call sites.
enum FeatureFlag: String, CaseIterable {
    case randomComet = "random_comet"     // lone meteor streak every 20–25s
    case meteorShower = "meteor_shower"   // burst events; overrides randomComet

    /// What debug builds see before PostHog is keyed in / flags load.
    /// Release builds always default to false — dark until the flag speaks.
    var debugDefault: Bool {
        switch self {
        case .randomComet: return true
        case .meteorShower: return true // flip off to watch lone comets in dev
        }
    }
}

/// Feature flags, PostHog-backed. Works offline (last-known values are
/// cached by the SDK) and degrades to defaults when analytics is off —
/// the app must never behave differently just because flags can't load.
enum FeatureFlags {
    static func isEnabled(_ flag: FeatureFlag) -> Bool {
        #if DEBUG
        isEnabled(flag.rawValue, default: flag.debugDefault)
        #else
        isEnabled(flag.rawValue, default: false)
        #endif
    }

    static func isEnabled(_ key: String, default defaultValue: Bool = false) -> Bool {
        #if canImport(PostHog)
        guard !AnalyticsFactory.postHogAPIKey.isEmpty else { return defaultValue }
        return PostHogSDK.shared.isFeatureEnabled(key)
        #else
        return defaultValue
        #endif
    }

    /// Call at launch (Store.start-time) so flags are fresh for the session.
    static func refresh() {
        #if canImport(PostHog)
        guard !AnalyticsFactory.postHogAPIKey.isEmpty else { return }
        PostHogSDK.shared.reloadFeatureFlags()
        #endif
    }
}

#if canImport(TelemetryDeck)
import TelemetryDeck

struct TelemetryDeckAnalytics: AnalyticsClient {
    init(appID: String) {
        TelemetryDeck.initialize(config: .init(appID: appID))
    }

    func track(_ event: AnalyticsEvent) {
        TelemetryDeck.signal(event.name, parameters: event.parameters)
    }
}
#endif

private struct AnalyticsKey: EnvironmentKey {
    static let defaultValue: AnalyticsClient = NoopAnalytics()
}

extension EnvironmentValues {
    var analytics: AnalyticsClient {
        get { self[AnalyticsKey.self] }
        set { self[AnalyticsKey.self] = newValue }
    }
}
