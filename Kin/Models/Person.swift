import Foundation
import SwiftData

@Model
public final class Person {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorSeed: Int = 0
    /// Unit-space position; -1 means "not yet placed" → SkyLayout seeds it.
    public var positionX: Double = -1
    public var positionY: Double = -1
    public var orbitRaw: String = OrbitCadence.weekly.rawValue
    public var stateRaw: String = StarState.active.rawValue
    public var createdAt: Date = Date()

    /// Free tier after the trial: stars beyond the limit *rest* — hidden
    /// from every surface (sky, widgets, Siri, logging) but never deleted.
    /// Unlocking wakes them all. Moments, positions, everything survives.
    public var isDormant: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Moment.people)
    public var moments: [Moment]? = []

    public init(name: String, orbit: OrbitCadence = .weekly) {
        self.id = UUID()
        self.name = name
        self.colorSeed = Int.random(in: 0..<1_000_000)
        self.orbitRaw = orbit.rawValue
        self.createdAt = Date()
    }

    // Enum bridges (SwiftData + CloudKit prefer primitive storage)
    public var orbit: OrbitCadence {
        get { OrbitCadence(rawValue: orbitRaw) ?? .weekly }
        set { orbitRaw = newValue.rawValue }
    }

    public var state: StarState {
        get { StarState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    /// Computed, never stored.
    public func luminosity(now: Date = Date()) -> Double {
        LuminosityEngine.luminosity(
            momentDates: (moments ?? []).map(\.timestamp),
            orbit: orbit,
            state: state,
            now: now
        )
    }
}
