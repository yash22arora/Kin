import WidgetKit
import SwiftUI

// The widget IS the product. Widgets can't run SpriteKit, so the sky is
// pre-rendered: the app writes a SkySnapshot (JSON) to the App Group container
// on every data change (see SkyView), and we render it with SwiftUI Canvas.

// MARK: - Timeline

struct SkyEntry: TimelineEntry {
    let date: Date
    let snapshot: SkySnapshot
}

struct SkyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkyEntry {
        SkyEntry(date: .now, snapshot: Self.demoSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (SkyEntry) -> Void) {
        // Demo stars only in the widget gallery; on the home screen, honesty:
        // real data or an explicit empty state — never fake stars.
        let fallback = context.isPreview ? Self.demoSnapshot : SkySnapshot(stars: [], lines: [])
        completion(SkyEntry(date: .now, snapshot: SkySnapshotStore.load() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyEntry>) -> Void) {
        // ~4 refreshes/day for the time-of-day tint; data changes trigger
        // WidgetCenter.shared.reloadAllTimelines() from the app.
        let snapshot = SkySnapshotStore.load() ?? SkySnapshot(stars: [], lines: [])
        let entries = (0..<4).map { i in
            SkyEntry(date: .now.addingTimeInterval(Double(i) * 6 * 3600), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static var demoSnapshot: SkySnapshot {
        let names = ["Mom", "Leo", "Ava", "Sam", "Mia"]
        let stars = (0..<5).map { i in
            let pos = SkyLayout.seededPosition(seed: i * 977, index: i, total: 5)
            return SkySnapshot.Star(
                id: UUID(), name: names[i], x: pos.x, y: pos.y,
                luminosity: [0.9, 0.7, 0.5, 0.8, 0.3][i],
                temperature: Double(i) / 5, isRemembered: false)
        }
        return SkySnapshot(stars: stars, lines: [])
    }
}

// MARK: - Shared drawing

enum WidgetSky {
    /// Same four-pointed sparkle the app uses, drawn in Canvas.
    static func starPath(at center: CGPoint, radius r: CGFloat, waist: CGFloat = 0.1) -> Path {
        let c = r * waist
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - r))
        p.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y),
                       control: CGPoint(x: center.x + c, y: center.y - c))
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r),
                       control: CGPoint(x: center.x + c, y: center.y + c))
        p.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y),
                       control: CGPoint(x: center.x - c, y: center.y + c))
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r),
                       control: CGPoint(x: center.x - c, y: center.y - c))
        p.closeSubpath()
        return p
    }

    /// Same warm-gold ↔ cool-blue ramp as SkyScene.color(temperature:).
    /// Keep these two in sync — they are the app/widget fidelity contract.
    static func color(temperature t: Double) -> Color {
        Color(red: 1.0 - 0.35 * t, green: 0.86 - 0.10 * t, blue: 0.55 + 0.45 * t)
    }

    static func draw(_ star: SkySnapshot.Star, in context: inout GraphicsContext, size: CGSize) {
        // Uniform square mapping, centered: preserves the *shape* of the sky
        // instead of stretching unit space to the widget's aspect ratio.
        let side = min(size.width, size.height)
        let center = mapped(star.x, star.y, in: size)
        let sizeScale = max(0.8, min(1.8, side / 160)) // small → large widgets
        let lum = star.luminosity
        let r = (2.6 + lum * 3.6) * sizeScale
        let tint = color(temperature: star.temperature)

        func circleRect(_ radius: CGFloat) -> CGRect {
            CGRect(x: center.x - radius, y: center.y - radius,
                   width: radius * 2, height: radius * 2)
        }

        // Wide tinted halo — atmosphere, barely there.
        context.fill(
            Circle().path(in: circleRect(r * 3.4)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: tint.opacity(0.28 * lum), location: 0),
                    .init(color: tint.opacity(0.08 * lum), location: 0.4),
                    .init(color: .clear, location: 1),
                ]),
                center: center, startRadius: 0, endRadius: r * 3.4
            )
        )

        // Diffraction cross — brightest stars only, under the core.
        // Sword-thin arms: hairline base, straight taper to a point at the
        // tip. Mirrors SkyScene.taperedCrossPath — keep in sync.
        if lum > 0.55 {
            let crossAlpha = (lum - 0.55) / 0.45 * 0.30
            let arm = r * 2.6
            let baseW = 0.8 * sizeScale
            var cross = Path()
            for k in 0..<4 {
                let angle = Double(k) * .pi / 2
                let dir = CGPoint(x: cos(angle), y: sin(angle))
                let perp = CGPoint(x: -sin(angle), y: cos(angle))
                cross.move(to: CGPoint(x: center.x + perp.x * baseW / 2,
                                       y: center.y + perp.y * baseW / 2))
                cross.addLine(to: CGPoint(x: center.x + dir.x * arm,
                                          y: center.y + dir.y * arm))
                cross.addLine(to: CGPoint(x: center.x - perp.x * baseW / 2,
                                          y: center.y - perp.y * baseW / 2))
                cross.closeSubpath()
            }
            context.fill(cross, with: .color(.white.opacity(crossAlpha)))
        }

        // The point of light: white-hot center → tinted falloff → nothing.
        // Mirrors SkyScene.pointImage — the app/widget fidelity contract.
        context.fill(
            Circle().path(in: circleRect(r * 1.5)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(1.0 * lum + 0.25), location: 0),
                    .init(color: .white.opacity(0.9 * lum), location: 0.10),
                    .init(color: tint.opacity(0.55 * lum), location: 0.28),
                    .init(color: tint.opacity(0.14 * lum), location: 0.55),
                    .init(color: .clear, location: 1),
                ]),
                center: center, startRadius: 0, endRadius: r * 1.5
            )
        )
    }

    /// Position mapping shared by stars and lines: centered square.
    static func mapped(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        let side = min(size.width, size.height)
        return CGPoint(x: (x - 0.5) * side + size.width / 2,
                       y: (y - 0.5) * side + size.height / 2)
    }

    static func drawLines(_ snapshot: SkySnapshot, in context: inout GraphicsContext, size: CGSize) {
        let starsByID = Dictionary(uniqueKeysWithValues: snapshot.stars.map { ($0.id, $0) })
        for line in snapshot.lines {
            guard let a = starsByID[line.a], let b = starsByID[line.b] else { continue }
            var path = Path()
            path.move(to: mapped(a.x, a.y, in: size))
            path.addLine(to: mapped(b.x, b.y, in: size))
            context.stroke(path, with: .color(.white.opacity(0.10 + 0.20 * line.strength)),
                           lineWidth: 0.6)
        }
    }

    static func background(at date: Date) -> LinearGradient {
        // Single source of truth in Core — same gradient as the app's scene.
        let colors = SkySnapshot.skyGradientColors(at: date)
        return LinearGradient(
            colors: [
                Color(red: colors.top.r, green: colors.top.g, blue: colors.top.b),
                Color(red: colors.bottom.r, green: colors.bottom.g, blue: colors.bottom.b),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - My Sky widget

struct SkyWidgetView: View {
    var entry: SkyEntry

    var body: some View {
        ZStack {
            Canvas { context, size in
                WidgetSky.drawLines(entry.snapshot, in: &context, size: size)
                for star in entry.snapshot.stars {
                    WidgetSky.draw(star, in: &context, size: size)
                }
            }
            if entry.snapshot.stars.isEmpty {
                Text("Open Kin to light your sky")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(for: .widget) { WidgetSky.background(at: entry.date) }
        .widgetURL(URL(string: "kin://log")) // one tap from home screen to logging
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let bright = entry.snapshot.stars.filter { $0.luminosity > 0.7 }.count
        return "Your sky. \(entry.snapshot.stars.count) stars, \(bright) bright tonight."
    }
}

struct SkyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MySky", provider: SkyProvider()) { entry in
            SkyWidgetView(entry: entry)
        }
        .configurationDisplayName("My Sky")
        .description("Your people, glowing at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - One Star widget

/// One person's star, pinned. Long-press → Edit Widget to choose who —
/// the "one widget per family member" grid moment from the plan.
/// Unconfigured, it shows the brightest star tonight.
struct OneStarEntry: TimelineEntry {
    let date: Date
    let snapshot: SkySnapshot
    let pinnedID: UUID?
}

struct OneStarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OneStarEntry {
        OneStarEntry(date: .now, snapshot: SkyProvider.demoSnapshot, pinnedID: nil)
    }

    func snapshot(for configuration: OneStarConfigIntent, in context: Context) async -> OneStarEntry {
        let fallback = context.isPreview ? SkyProvider.demoSnapshot : SkySnapshot(stars: [], lines: [])
        return OneStarEntry(date: .now,
                            snapshot: SkySnapshotStore.load() ?? fallback,
                            pinnedID: configuration.star?.id)
    }

    func timeline(for configuration: OneStarConfigIntent, in context: Context) async -> Timeline<OneStarEntry> {
        let snapshot = SkySnapshotStore.load() ?? SkySnapshot(stars: [], lines: [])
        let entries = (0..<4).map { i in
            OneStarEntry(date: .now.addingTimeInterval(Double(i) * 6 * 3600),
                         snapshot: snapshot,
                         pinnedID: configuration.star?.id)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct OneStarWidgetView: View {
    var entry: OneStarEntry

    private var star: SkySnapshot.Star? {
        if let pinned = entry.pinnedID,
           let match = entry.snapshot.stars.first(where: { $0.id == pinned }) {
            return match
        }
        return entry.snapshot.stars.max { $0.luminosity < $1.luminosity }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let star {
                Canvas { context, size in
                    var s = star
                    s = SkySnapshot.Star(id: star.id, name: star.name, x: 0.5, y: 0.45,
                                         luminosity: star.luminosity,
                                         temperature: star.temperature,
                                         isRemembered: star.isRemembered)
                    WidgetSky.draw(s, in: &context, size: size)
                }
                Text(star.name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            } else {
                Text("Your sky awaits")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .containerBackground(for: .widget) { WidgetSky.background(at: entry.date) }
        .widgetURL(star.flatMap { URL(string: "kin://star/\($0.id.uuidString)") })
        .accessibilityLabel(star.map { "\($0.name), bright tonight." } ?? "No stars yet.")
    }
}

struct OneStarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OneStar",
                               intent: OneStarConfigIntent.self,
                               provider: OneStarProvider()) { entry in
            OneStarWidgetView(entry: entry)
        }
        .configurationDisplayName("One Star")
        .description("Someone you love, at a glance. Edit the widget to choose who.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct KinWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkyWidget()
        OneStarWidget()
        // TODO v1.x: lock screen accessory + StandBy
    }
}
