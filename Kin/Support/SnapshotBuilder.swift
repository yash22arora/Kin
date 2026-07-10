import Foundation

/// Builds the SkySnapshot from model objects. Used by SkyView on every
/// change and by App Intents after Siri logs a moment — one definition
/// of what the sky looks like.
enum SnapshotBuilder {

    static func make(from people: [Person]) -> SkySnapshot {
        let active = people
            .filter { $0.state != .released }
            .sorted { $0.createdAt < $1.createdAt }

        let stars = active.enumerated().map { index, person -> SkySnapshot.Star in
            let pos: (x: Double, y: Double) = person.positionX >= 0
                ? (person.positionX, person.positionY)
                : SkyLayout.seededPosition(seed: person.colorSeed, index: index, total: active.count)
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
