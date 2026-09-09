import Foundation

/// Immutable value bridging the data layer → renderers.
/// Both SkyScene (SpriteKit, in-app) and the widget's static renderer
/// consume this — one source of truth, two render paths.
public struct SkySnapshot: Equatable, Sendable, Codable {
    public struct Star: Equatable, Identifiable, Sendable, Codable {
        public let id: UUID
        public let name: String
        public let x: Double          // unit space 0...1
        public let y: Double
        public let luminosity: Double // floorGlow...1
        public let temperature: Double // 0 warm ... 1 cool
        public let isRemembered: Bool
        /// A moment from this exact date, some past year — the star
        /// breathes a little brighter today. (Decodes to false when absent,
        /// so older stored snapshots stay readable.)
        public let hasAnniversary: Bool

        public init(id: UUID, name: String, x: Double, y: Double,
                    luminosity: Double, temperature: Double, isRemembered: Bool,
                    hasAnniversary: Bool = false) {
            self.id = id; self.name = name; self.x = x; self.y = y
            self.luminosity = luminosity; self.temperature = temperature
            self.isRemembered = isRemembered
            self.hasAnniversary = hasAnniversary
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            x = try c.decode(Double.self, forKey: .x)
            y = try c.decode(Double.self, forKey: .y)
            luminosity = try c.decode(Double.self, forKey: .luminosity)
            temperature = try c.decode(Double.self, forKey: .temperature)
            isRemembered = try c.decode(Bool.self, forKey: .isRemembered)
            hasAnniversary = try c.decodeIfPresent(Bool.self, forKey: .hasAnniversary) ?? false
        }
    }

    /// A line between stars that share moments; strength grows with repetition.
    public struct ConstellationLine: Equatable, Sendable, Codable {
        public let a: UUID
        public let b: UUID
        public let strength: Double // 0...1

        public init(a: UUID, b: UUID, strength: Double) {
            self.a = a; self.b = b; self.strength = strength
        }
    }

    public let stars: [Star]
    public let lines: [ConstellationLine]
    public let generatedAt: Date

    public init(stars: [Star], lines: [ConstellationLine], generatedAt: Date = Date()) {
        self.stars = stars; self.lines = lines; self.generatedAt = generatedAt
    }

    /// Sky tint phase from real local time (0 = deep night, 1 = pre-dawn/dusk edge).
    /// Renderers map this to background gradient. Season handling comes later.
    public static func skyPhase(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        let hour = Double(calendar.component(.hour, from: date))
            + Double(calendar.component(.minute, from: date)) / 60.0
        // Deepest at 1am, lightest edges at 6am/8pm; simple placeholder curve.
        let distanceFromDeepNight = min(abs(hour - 1), 24 - abs(hour - 1)) // 0...12
        return min(1, distanceFromDeepNight / 12.0)
    }

    /// The one true sky gradient, shared by app (SpriteKit) and widget (SwiftUI).
    /// Change it here and both surfaces stay in step.
    public static func skyGradientColors(at date: Date = Date())
        -> (top: (r: Double, g: Double, b: Double), bottom: (r: Double, g: Double, b: Double)) {
        let phase = skyPhase(at: date)
        return (
            top: (0.02 + 0.035 * phase, 0.02 + 0.02 * phase, 0.08 + 0.07 * phase),
            bottom: (0.05 + 0.05 * phase, 0.04 + 0.035 * phase, 0.15 + 0.11 * phase)
        )
    }
}
