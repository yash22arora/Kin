import CoreHaptics
import UIKit

/// Bespoke haptics: bright stars feel warmer under your finger.
/// Falls back to UIImpactFeedbackGenerator if CoreHaptics is unavailable.
final class Haptics {
    static let shared = Haptics()
    private var engine: CHHapticEngine?

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    /// Remembered stars answer differently: no bright transient, just one
    /// deep, steady swell — presence under the finger, not sparkle.
    func remembered() {
        guard let engine else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.7)
            return
        }
        let swell = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08),
            ],
            relativeTime: 0, duration: 0.5)
        if let pattern = try? CHHapticPattern(events: [swell], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }

    /// The star-touch haptic. Intensity and warmth (sharpness inverse) scale
    /// with luminosity: bright star = fuller, softer thump; dim = faint tick.
    func ignition(luminosity: Double) {
        let l = Float(max(0, min(1, luminosity)))
        guard let engine else {
            UIImpactFeedbackGenerator(style: l > 0.6 ? .medium : .light).impactOccurred()
            return
        }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3 + 0.7 * l)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8 - 0.6 * l)
        let event = CHHapticEvent(eventType: .hapticTransient,
                                  parameters: [intensity, sharpness], relativeTime: 0)
        // Bright stars get a soft afterglow pulse
        var events = [event]
        if l > 0.6 {
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2 * l),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
                ],
                relativeTime: 0.05, duration: 0.25))
        }
        if let pattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
}
