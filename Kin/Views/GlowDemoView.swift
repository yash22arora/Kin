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
    @State private var companion2Visible = false
    @State private var companionShift = false   // false = start position, true = dragged home
    @State private var lineOpacity: Double = 0
    @State private var touchHalo = false
    @State private var rememberedVisible = false
    @State private var rememberedBreath = false
    @State private var caption = "Every person you love is a star."
    /// The Continue button stays hidden until the loop has played through once.
    @State private var demoCompletedOnce = false

    private static let hero = SkyScene.starImage(temperature: 0.2)
    private static let companion = SkyScene.starImage(temperature: 0.7)
    private static let companion2 = SkyScene.starImage(temperature: 0.45)
    private static let remembered = SkyScene.starImage(temperature: 0.5)

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

            // Held back until the sky has shown what it does at least once.
            if demoCompletedOnce {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 1) // reserve nothing; keeps layout calm
            }
        }
        .animation(.easeInOut(duration: 0.5), value: demoCompletedOnce)
        .task { await runLoop() }
    }

    // MARK: The little sky

    private var demoSky: some View {
        GeometryReader { geo in
            let heroPoint = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.42)
            let companionPoint = companionShift
                ? CGPoint(x: geo.size.width * 0.72, y: geo.size.height * 0.68)
                : CGPoint(x: geo.size.width * 0.28, y: geo.size.height * 0.74)
            let companion2Point = CGPoint(x: geo.size.width * 0.70, y: geo.size.height * 0.20)
            let cometStart = CGPoint(x: -30, y: geo.size.height * 0.05)

            ZStack {
                // Constellation lines (animatable endpoints) — hero to each companion
                StarLink(from: heroPoint, to: companionPoint)
                    .stroke(.white.opacity(lineOpacity), style: .init(lineWidth: 0.8, lineCap: .round))
                StarLink(from: heroPoint, to: companion2Point)
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

                // A second companion — the constellation needs three points to feel like one
                Image(uiImage: Self.companion2)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .opacity(companion2Visible ? 0.75 : 0)
                    .position(companion2Point)

                // The hero star — glow drives size and brightness, like the real
                // engine. Fades fully out as the remembered star takes its place.
                Image(uiImage: Self.hero)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .opacity((0.35 + 0.65 * glow) * (rememberedVisible ? 0 : 1))
                    .scaleEffect(0.75 + 0.35 * glow)
                    .position(heroPoint)

                // Remembered star — softer, ringed as "kept", holding perfectly
                // steady where an active star would twinkle. Rendered at the
                // hero's exact point so it crossfades in place, no jump.
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(rememberedVisible ? 0.16 : 0), lineWidth: 1)
                        .frame(width: 60, height: 60)
                    Image(uiImage: Self.remembered)
                        .resizable()
                        .frame(width: 44, height: 44)
                        .opacity(rememberedVisible ? 0.72 : 0)
                        .scaleEffect(rememberedBreath ? 1.02 : 0.99)
                        .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true),
                                   value: rememberedBreath)
                }
                .position(heroPoint)

                // Comet — a bright head with a tapered, fading trail behind it
                comet(angle: atan2(heroPoint.y - cometStart.y, heroPoint.x - cometStart.x))
                    .opacity(cometVisible ? 1 : 0)
                    .position(cometAtStar ? heroPoint : cometStart)
            }
        }
    }

    /// A comet drawn head-at-center so it rotates cleanly around its point of
    /// travel: a hot white core, a soft glow, and a triangular tail that fades
    /// to nothing behind it. Head points along +x, then we rotate to the path.
    private func comet(angle: CGFloat) -> some View {
        Canvas { ctx, size in
            let head = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let tailTip = CGPoint(x: size.width * 0.04, y: size.height * 0.5)
            let halfWidth: CGFloat = 3.0

            var tail = Path()
            tail.move(to: CGPoint(x: head.x, y: head.y - halfWidth))
            tail.addLine(to: CGPoint(x: head.x, y: head.y + halfWidth))
            tail.addLine(to: tailTip)
            tail.closeSubpath()
            ctx.fill(tail, with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.85)]),
                startPoint: tailTip, endPoint: head))

            // Soft outer glow, then the hot core.
            ctx.fill(
                Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.85), .white.opacity(0)]),
                    center: head, startRadius: 0, endRadius: 7))
            ctx.fill(
                Path(ellipseIn: CGRect(x: head.x - 2.6, y: head.y - 2.6, width: 5.2, height: 5.2)),
                with: .color(.white))
        }
        .frame(width: 76, height: 22)
        .rotationEffect(.radians(Double(angle)))
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
            companion2Visible = true
            lineOpacity = 0.3
            withAnimation { demoCompletedOnce = true } // static composition — offer it now
            rememberedBreath = true
            let captions = [
                "Share a moment — their star brightens.",
                "Quiet weeks soften it. It never goes dark.",
                "Moments together draw constellations.",
                "Drag stars to arrange your sky.",
                "And those who are gone stay — remembered, always steady.",
            ]
            var i = 0
            while !Task.isCancelled {
                await sleep(3.5)
                let text = captions[i % captions.count]
                setCaption(text)
                // Spotlight the remembered star only on its own caption.
                withAnimation(.easeInOut(duration: 0.6)) {
                    rememberedVisible = text == captions[4]
                }
                i += 1
            }
            return
        }

        await sleep(1.2)
        var firstPass = true
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
            withAnimation(.easeOut(duration: 0.9).delay(0.4)) { companion2Visible = true }
            withAnimation(.easeOut(duration: 1.4).delay(0.6)) { lineOpacity = 0.3 }
            await sleep(3.2)

            // 4 — drag to arrange
            setCaption("Drag stars to arrange your sky.")
            withAnimation(.easeOut(duration: 0.4)) { touchHalo = true }
            await sleep(0.5)
            withAnimation(.easeInOut(duration: 1.7)) { companionShift = true }
            await sleep(1.8)
            withAnimation(.easeOut(duration: 0.5)) { touchHalo = false }
            await sleep(1.6)

            // 5 — remembered. First let the whole showcase fade away and settle
            // into darkness…
            withAnimation(.easeInOut(duration: 1.4)) {
                lineOpacity = 0
                companionVisible = false
                companion2Visible = false
                glow = 0
            }
            await sleep(1.8)
            companionShift = false

            // …then, gently and in the hero's place, one steady light that —
            // unlike the others — never fades: the star of someone who's gone.
            setCaption("And those who are gone stay — remembered, always steady.")
            rememberedBreath = true
            withAnimation(.easeInOut(duration: 1.8)) { rememberedVisible = true }
            await sleep(4.2)
            // As the remembered star fades, the hero crossfades back in its
            // place, ready for the next pass — no snap.
            withAnimation(.easeInOut(duration: 1.4)) {
                rememberedVisible = false
                glow = 0.5
            }
            await sleep(1.6)

            // One full pass shown — the way forward can appear now.
            if firstPass {
                firstPass = false
                withAnimation { demoCompletedOnce = true }
            }
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
