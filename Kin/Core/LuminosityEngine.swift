import Foundation

// ============================================================================
// The heart of Kin. Pure Foundation — no UI, no SwiftData.
// Luminosity is ALWAYS computed, never stored, and never shown as a number.
// ============================================================================

/// How often you and this person naturally cross paths.
/// Scales decay so a twice-a-year friend stays bright between meetings.
public enum OrbitCadence: String, Codable, CaseIterable, Sendable {
    case mostDays
    case weekly
    case everyFewMonths
    case rarely

    /// Expected interval between moments, in seconds.
    public var expectedInterval: TimeInterval {
        switch self {
        case .mostDays:       return 1 * 86_400
        case .weekly:         return 7 * 86_400
        case .everyFewMonths: return 90 * 86_400
        case .rarely:         return 365 * 86_400
        }
    }

    /// Onboarding copy — poetic, never clinical.
    public var label: String {
        switch self {
        case .mostDays:       return "Most days"
        case .weekly:         return "Every week or so"
        case .everyFewMonths: return "Every few months"
        case .rarely:         return "Rarely, and that's okay"
        }
    }
}

public enum StarState: String, Codable, Sendable {
    case active
    case released    // person removed; data deleted after ritual
    case remembered  // deceased/permanent: fixed glow, never dims
}

public struct LuminosityEngine {

    /// Stars never go dark. Dimming reads as "distant," never "dying."
    public static let floorGlow: Double = 0.25

    /// Fixed glow for remembered stars.
    public static let rememberedGlow: Double = 0.80

    /// Glow of a brand-new star with no moments yet.
    public static let newbornGlow: Double = 0.45

    /// Decay time constant: how long a moment's warmth lingers.
    /// τ = 3 × expected interval, clamped to [1 week, 6 months].
    /// For a weekly orbit this makes a star noticeably soften after ~3 weeks
    /// and approach its floor around ~3 months — the plan's emotional contract.
    static func timeConstant(for orbit: OrbitCadence) -> TimeInterval {
        let raw = orbit.expectedInterval * 3
        return min(max(raw, 7 * 86_400), 180 * 86_400)
    }

    /// Compute a star's luminosity in [floorGlow, 1].
    ///
    /// Each moment contributes energy that decays exponentially with the
    /// person's orbit-scaled time constant. Total energy saturates via
    /// 1 − e^(−E) so many moments approach (but never game past) full glow.
    public static func luminosity(
        momentDates: [Date],
        orbit: OrbitCadence,
        state: StarState = .active,
        now: Date = Date()
    ) -> Double {
        switch state {
        case .remembered: return rememberedGlow
        case .released:   return 0
        case .active:     break
        }

        guard !momentDates.isEmpty else { return newbornGlow }

        let tau = timeConstant(for: orbit)
        let energy = momentDates.reduce(0.0) { sum, date in
            let dt = now.timeIntervalSince(date)
            guard dt >= 0 else { return sum } // ignore future-dated entries
            return sum + exp(-dt / tau)
        }

        let saturated = 1 - exp(-energy) // 0..1, concave
        return floorGlow + (1 - floorGlow) * saturated
    }

    /// Twinkle rate for the sky scene: recent warmth twinkles faster.
    /// Returns cycles per second in [0.1, 0.6].
    public static func twinkleRate(luminosity: Double) -> Double {
        0.1 + 0.5 * max(0, min(1, (luminosity - floorGlow) / (1 - floorGlow)))
    }
}
