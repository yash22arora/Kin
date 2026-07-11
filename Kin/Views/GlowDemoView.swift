import SwiftUI
import SpriteKit

/// Onboarding interlude: how the sky works, shown rather than told.
/// One slow loop — comet brightens a star, quiet weeks soften it,
/// a companion draws a constellation, a touch drags it home.
/// Deliberately unhurried; nothing demands attention.
struct GlowDemoView: View {
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Demo state
    @State private var glow: Double = 0.5
    @State private var cometVisible = false
    @State private var cometAtStar = false
    @State private var companionVisible = false
    @State private var companionShift = false   // false = start position, true = dragged home
    @State private var lineOpacity: Double = 0
    @State private var touchHalo = false
    @State private var caption = "Every person you love is a star."

    private static let hero = SkyScene.starImage(temperature: 0.2)
    private static let companion = SkyScene.starImage(temperature: 0.7)

    var body: some View {
        VStack(spacing: 28) {
            demoSky
                .frame(height: 280)
                .accessibilityElement()
                .accessibilityLabel("How your sky works.")

            Text(caption)
                .font(KinType.whisper)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(minHeight: 44, alignment: .top)
                .padding(.horizontal, 40)
                .id(caption)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.6), value: caption)
                .accessibilityAddTraits(.updatesFrequently)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
        }
        .task { await runLoop() }
    }

    // MARK: The little sky

    private var demoSky: some View {
        GeometryReader { geo in
            let heroPoint = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.42)
            let companionPoint = companionShift
                ? CGPoint(x: geo.size.width * 0.72, y: geo.size.height * 0.68)
                : CGPoint(x: geo.size.width * 0.28, y: geo.size.height * 0.74)
            let cometStart = CGPoint(x: -30, y: geo.size.height * 0.05)

            ZStack {
                // Constellation line (animatable endpoints)
                StarLink(from: heroPoint, to: companionPoint)
                    .stroke(.white.opacity(lineOpacity), style: .init(lineWidth: 0.8, lineCap: .round))

                // Companion star + the touch that moves it
                Image(uiImage: Self.companion)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .opacity(companionVisible ? 0.8 : 0)
                    .position(companionPoint)
                Circle()
                    .strokeBorder(.white.opacity(touchHalo ? 0.35 : 0), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
                    .position(companionPoint)

                // The hero star — glow drives size and brightness, like the real engine
                Image(uiImage: Self.hero)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .opacity(0.35 + 0.65 * glow)
                    .scaleEffect(0.75 + 0.35 * glow)
                    .position(heroPoint)

                // Comet
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .shadow(color: .white.opacity(0.8), radius: 4)
                    .opacity(cometVisible ? 0.95 : 0)
                    .position(cometAtStar ? heroPoint : cometStart)
            }
        }
    }

    // MARK: The loop

    private func setCaption(_ text: String) {
        caption = text
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func runLoop() async {
        guard !reduceMotion else {
            // Motion-free: settle into the full composition, cycle captions only.
            glow = 0.9
            companionVisible = true
            lineOpacity = 0.3
            let captions = [
                "Share a moment — their star brightens.",
                "Quiet weeks soften it. It never goes dark.",
                "Moments together draw constellations.",
                "Drag stars to arrange your sky.",
            ]
            var i = 0
            while !Task.isCancelled {
                await sleep(3.5)
                setCaption(captions[i % captions.count])
                i += 1
            }
            return
        }

        await sleep(1.2)
        while !Task.isCancelled {
            // 1 — a moment arrives
            setCaption("Share a moment — their star brightens.")
            cometAtStar = false
            cometVisible = true
            withAnimation(.easeOut(duration: 1.3)) { cometAtStar = true }
            await sleep(1.3)
            cometVisible = false
            withAnimation(.easeOut(duration: 0.5)) { glow = 1.0 }
            Haptics.shared.ignition(luminosity: 0.7)
            await sleep(2.4)

            // 2 — quiet weeks
            setCaption("Quiet weeks soften it. It never goes dark.")
            withAnimation(.easeInOut(duration: 3.0)) { glow = 0.45 }
            await sleep(3.6)

            // 3 — constellation
            setCaption("Moments together draw constellations.")
            withAnimation(.easeOut(duration: 0.9)) { companionVisible = true }
            withAnimation(.easeOut(duration: 1.4).delay(0.6)) { lineOpacity = 0.3 }
            await sleep(3.2)

            // 4 — drag to arrange
            setCaption("Drag stars to arrange your sky.")
            withAnimation(.easeOut(duration: 0.4)) { touchHalo = true }
            await sleep(0.5)
            withAnimation(.easeInOut(duration: 1.7)) { companionShift = true }
            await sleep(1.8)
            withAnimation(.easeOut(duration: 0.5)) { touchHalo = false }
            await sleep(1.8)

            // reset, softly
            withAnimation(.easeInOut(duration: 1.2)) {
                lineOpacity = 0
                companionVisible = false
            }
            await sleep(1.3)
            companionShift = false
            await sleep(0.6)
        }
    }
}

/// A line whose endpoints animate.
private struct StarLink: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        return p
    }
}
