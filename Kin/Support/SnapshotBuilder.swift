import Foundation

/// Builds the SkySnapshot from model objects. Used by SkyView on every
/// change and by App Intents after Siri logs a moment — one definition
/// of what the sky looks like.
enum SnapshotBuilder {

    static func make(from people: [Person]) -> SkySnapshot {
        let active = people
            .filter { $0.state != .released && !$0.isDormant } // resting stars stay unseen
            .sorted { $0.createdAt < $1.createdAt }

        let stars = active.enumerated().map { index, person -> SkySnapshot.Star in
            // A star without a home gets one NOW, and it's written down —
            // seeded positions depend on (index, total), which drift as the
            // sky changes, so deriving twice gives two different skies.
            // Materializing makes position a stored fact: stable across
            // launches, star additions, and export/import round-trips.
            if person.positionX < 0 {
                let seeded = SkyLayout.seededPosition(
                    seed: person.colorSeed, index: index, total: active.count)
                person.positionX = seeded.x
                person.positionY = seeded.y
            }
            let pos = (x: person.positionX, y: person.positionY)
            return SkySnapshot.Star(
                id: person.id,
                name: person.name,
                x: pos.x, y: pos.y,
                luminosity: person.luminosity(),
                temperature: SkyLayout.temperature(colorSeed: person.colorSeed),
                isRemembered: person.state == .remembered
            )
        }
        return SkySnapshot(stars: stars, lines: constellationLines(among: active))
    }

    /// Lines between people who share moments; strength grows with repetition.
    /// Five shared moments = a fully formed bond.
    private static func constellationLines(among active: [Person]) -> [SkySnapshot.ConstellationLine] {
        let activeIDs = Set(active.map(\.id))
        var counts: [String: (a: UUID, b: UUID, count: Int)] = [:]
        var seen = Set<UUID>()
        for person in active {
            for moment in person.moments ?? [] where !seen.contains(moment.id) {
                seen.insert(moment.id)
                let ids = (moment.people ?? [])
                    .map(\.id)
                    .filter { activeIDs.contains($0) }
                    .sorted { $0.uuidString < $1.uuidString }
                guard ids.count >= 2 else { continue }
                for i in 0..<ids.count {
                    for j in (i + 1)..<ids.count {
                        let key = ids[i].uuidString + "+" + ids[j].uuidString
                        var entry = counts[key] ?? (ids[i], ids[j], 0)
                        entry.count += 1
                        counts[key] = entry
                    }
                }
            }
        }
        return counts.values.map {
            SkySnapshot.ConstellationLine(a: $0.a, b: $0.b, strength: min(1, Double($0.count) / 5))
        }
    }
}
