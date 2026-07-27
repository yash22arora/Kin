import Foundation

// ============================================================================
// The Living Sky, Phase A (see LIVING_SKY.md): a solar hue arc.
// Six phase anchors authored in OkLCh, interpolated continuously along the
// sun's altitude. Morning legs lean violet so dawn never reruns dusk.
// Pure Foundation — shared by SkyScene and the widget. One sky, everywhere.
// ============================================================================

/// User-selectable sky mood. `.auto` follows the sun; the rest pin a phase.
public enum SkyPhaseVariant: String, CaseIterable, Sendable {
    case auto
    case day
    case goldenHour
    case dusk
    case blueHour
    case deepNight
    case dawn

    public var displayName: String {
        switch self {
        case .auto:       return "Auto — follows the sun"
        case .day:        return "Day"
        case .goldenHour: return "Golden hour"
        case .dusk:       return "Dusk"
        case .blueHour:   return "Blue hour"
        case .deepNight:  return "Deep night"
        case .dawn:       return "Dawn"
        }
    }

    /// The solar altitude (and side of the day) this variant pins.
    var pinned: (altitude: Double, morning: Bool)? {
        switch self {
        case .auto:       return nil
        case .day:        return (12, false)
        case .goldenHour: return (3, false)
        case .dusk:       return (-7, false)
        case .blueHour:   return (-12, false)
        case .deepNight:  return (-25, false)
        case .dawn:       return (-7, true)
        }
    }
}

public enum SkyPalette {

    public struct RGB: Sendable {
        public let r: Double
        public let g: Double
        public let b: Double
    }

    // MARK: Settings (App Group — widgets read the same choice)

    public static let variantKey = "skyHueVariant"

    public static func currentVariant() -> SkyPhaseVariant {
        let raw = UserDefaults(suiteName: KinShared.appGroupID)?
            .string(forKey: variantKey) ?? ""
        return SkyPhaseVariant(rawValue: raw) ?? .auto
    }

    // MARK: Public API

    #if DEBUG
    /// Settings' debug clock ("debugSkyHour" in standard defaults, hours
    /// 0–24; -1 = off). Lets the hues be auditioned without waiting for the
    /// planet. Debug builds only; applies to Auto mood, in-app only.
    static var debugHour: Double? {
        let value = UserDefaults.standard.double(forKey: "debugSkyHour")
        return value >= 0 ? min(value, 24) : nil
    }
    #endif

    /// Three vertical stops — [zenith, mid, horizon] — for the given moment
    /// and mood. This is the single source of truth for the sky's color.
    public static func stops(at date: Date = Date(),
                             variant: SkyPhaseVariant = .auto) -> [RGB] {
        var altitude: Double
        var morning: Bool
        if let pinned = variant.pinned {
            (altitude, morning) = pinned
        } else {
            altitude = solarAltitude(at: date)
            morning = isMorning(at: date)
            #if DEBUG
            if let hour = Self.debugHour {
                altitude = solarAltitude(hour: hour, at: date)
                morning = hour < 12.5
            }
            #endif
        }
        let stops = interpolatedStops(altitude: altitude)
        let adjusted = morning ? stops.map(morningShift) : stops
        return adjusted.map(oklchToSRGB)
    }

    // MARK: Solar model (approximate; no location permission needed)

    /// Sun altitude in degrees from local clock time + seasonal declination,
    /// assuming mid-latitude (37°). Wrong by a few degrees, right in feel —
    /// LIVING_SKY.md's graceful-degradation rule.
    static func solarAltitude(at date: Date, calendar: Calendar = .current) -> Double {
        let hour = Double(calendar.component(.hour, from: date))
            + Double(calendar.component(.minute, from: date)) / 60
        return solarAltitude(hour: hour, at: date, calendar: calendar)
    }

    /// Same model with the clock decoupled — powers the debug time slider.
    static func solarAltitude(hour: Double, at date: Date,
                              calendar: Calendar = .current) -> Double {
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
        let declination = -23.44 * cos(2 * .pi * (day + 10) / 365) * .pi / 180
        let hourAngle = (hour - 12.5) * 15 * .pi / 180 // solar noon ≈ 12:30
        let latitude = 37.0 * .pi / 180
        let sinAlt = sin(latitude) * sin(declination)
            + cos(latitude) * cos(declination) * cos(hourAngle)
        return asin(max(-1, min(1, sinAlt))) * 180 / .pi
    }

    static func isMorning(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = Double(calendar.component(.hour, from: date))
            + Double(calendar.component(.minute, from: date)) / 60
        return hour < 12.5
    }

    // MARK: Phase anchors (evening side; from LIVING_SKY.md tables)

    struct OkLCh { let l: Double; let c: Double; let h: Double }
    private struct Anchor { let altitude: Double; let stops: [OkLCh] }

    private static let anchors: [Anchor] = [
        // Day — pale, desaturated; rarely seen
        Anchor(altitude: 10, stops: [OkLCh(l: 0.55, c: 0.050, h: 240),
                                     OkLCh(l: 0.62, c: 0.045, h: 235),
                                     OkLCh(l: 0.70, c: 0.040, h: 230)]),
        // Golden hour — amber pooling at the horizon
        Anchor(altitude: 3, stops: [OkLCh(l: 0.45, c: 0.060, h: 250),
                                    OkLCh(l: 0.55, c: 0.100, h: 60),
                                    OkLCh(l: 0.70, c: 0.140, h: 70)]),
        // Civil twilight — rose into magenta; first stars
        Anchor(altitude: -3, stops: [OkLCh(l: 0.30, c: 0.070, h: 285),
                                     OkLCh(l: 0.42, c: 0.100, h: 320),
                                     OkLCh(l: 0.55, c: 0.130, h: 25)]),
        // Blue hour — THE HERO
        Anchor(altitude: -9, stops: [OkLCh(l: 0.20, c: 0.080, h: 265),
                                     OkLCh(l: 0.28, c: 0.110, h: 275),
                                     OkLCh(l: 0.40, c: 0.100, h: 300)]),
        // Astronomical twilight — settling
        Anchor(altitude: -15, stops: [OkLCh(l: 0.14, c: 0.050, h: 268),
                                      OkLCh(l: 0.19, c: 0.060, h: 272),
                                      OkLCh(l: 0.28, c: 0.070, h: 285)]),
        // Deep night — never true black
        Anchor(altitude: -25, stops: [OkLCh(l: 0.10, c: 0.030, h: 265),
                                      OkLCh(l: 0.13, c: 0.040, h: 268),
                                      OkLCh(l: 0.17, c: 0.050, h: 275)]),
    ]

    private static func interpolatedStops(altitude: Double) -> [OkLCh] {
        let clamped = max(anchors.last!.altitude, min(anchors.first!.altitude, altitude))
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i], b = anchors[i + 1]
            if clamped <= a.altitude && clamped >= b.altitude {
                let t = (a.altitude - clamped) / (a.altitude - b.altitude)
                return zip(a.stops, b.stops).map { lerp($0, $1, t) }
            }
        }
        return clamped > 0 ? anchors.first!.stops : anchors.last!.stops
    }

    private static func lerp(_ a: OkLCh, _ b: OkLCh, _ t: Double) -> OkLCh {
        // Hue takes the shortest way around the wheel — so golden-hour amber
        // melts through rose into indigo instead of detouring through green.
        let dh = ((b.h - a.h + 540).truncatingRemainder(dividingBy: 360)) - 180
        return OkLCh(l: a.l + (b.l - a.l) * t,
                     c: a.c + (b.c - a.c) * t,
                     h: a.h + dh * t)
    }

    /// Dawn is dusk's cooler sibling: zenith/mid lean violet and lose a
    /// little chroma; the horizon warmth swings from rose toward sunrise gold.
    private static func morningShift(_ stop: OkLCh) -> OkLCh {
        OkLCh(l: min(1, stop.l + 0.02),
              c: stop.c * 0.9,
              h: stop.h + ((262 - stop.h + 540).truncatingRemainder(dividingBy: 360) - 180) * 0.3)
    }

    // MARK: OkLCh → sRGB (standard Oklab transform, gamma-encoded, clamped)

    static func oklchToSRGB(_ stop: OkLCh) -> RGB {
        let hRad = stop.h * .pi / 180
        let a = stop.c * cos(hRad)
        let b = stop.c * sin(hRad)

        let l_ = stop.l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = stop.l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = stop.l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_

        let rLin =  4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

        func encode(_ x: Double) -> Double {
            let v = max(0, min(1, x))
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return RGB(r: encode(rLin), g: encode(gLin), b: encode(bLin))
    }
}
