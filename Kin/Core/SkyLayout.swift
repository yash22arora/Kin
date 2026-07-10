import Foundation

/// Deterministic star placement: the same person always lands in the same
/// spot, so the sky becomes spatially memorable ("mom is upper left").
/// Users can drag to rearrange; explicit positions override the seed.
public struct SkyLayout {

    /// Position in unit space (0...1, 0...1), derived from a stable seed.
    /// Uses a golden-angle spiral jittered by the seed hash, keeping stars
    /// away from screen edges and roughly evenly distributed.
    public static func seededPosition(seed: Int, index: Int, total: Int) -> (x: Double, y: Double) {
        let golden = 2.399963229728653 // golden angle in radians
        let hash = Double(abs(seed % 1000)) / 1000.0
        let i = Double(index) + hash
        let n = Double(max(total, 1))

        let r = 0.12 + 0.34 * sqrt(i / n)        // radius 0.12...0.46 of min dimension
        let theta = i * golden + hash * .pi * 2

        let x = 0.5 + r * cos(theta)
        let y = 0.5 + r * sin(theta) * 0.85       // slightly flattened, sky-like
        return (min(max(x, 0.08), 0.92), min(max(y, 0.10), 0.88))
    }

    /// Stable per-person hue seed → star temperature.
    /// Maps to a warm-gold ↔ cool-blue range; never garish.
    public static func temperature(colorSeed: Int) -> Double {
        Double(abs(colorSeed % 100)) / 100.0 // 0 = warmest gold, 1 = coolest blue
    }
}
