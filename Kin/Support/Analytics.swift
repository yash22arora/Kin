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
    /// Paste your TelemetryDeck app ID here to go live.
    static let telemetryDeckAppID = ""

    static func makeClient() -> AnalyticsClient {
        #if canImport(TelemetryDeck)
        if !telemetryDeckAppID.isEmpty {
            return TelemetryDeckAnalytics(appID: telemetryDeckAppID)
        }
        #endif
        return NoopAnalytics()
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
