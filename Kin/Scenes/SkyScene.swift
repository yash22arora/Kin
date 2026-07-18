import SpriteKit
import SwiftUI
import CoreMotion

/// The starfield. Consumes SkySnapshot; knows nothing about SwiftData.
///
/// Layer stack (back → front): gradient background (camera-fixed), dust
/// (far parallax), constellation lines + stars + ghost + comets (near).
/// A camera node powers the focus zoom: tap a star and the sky glides
/// toward it while everything else dims.
final class SkyScene: SKScene, UIGestureRecognizerDelegate {

    private var starNodes: [UUID: StarNode] = [:]
    private var currentSnapshot: SkySnapshot?
    private var pendingSnapshot: SkySnapshot?
    /// False until the first apply() has run. Stars added on that first pass
    /// are the *saved* sky returning — they appear quietly. Only stars that
    /// join after it are genuinely born, and earn the ignition.
    private var hasPopulated = false
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var onStarTap: ((UUID) -> Void)?
    /// Long-press on empty sky → (unitX, unitY) where a new star should be born.
    var onLongPress: ((Double, Double) -> Void)?
    /// A star was dragged to a new home → persist it.
    var onStarMoved: ((UUID, Double, Double) -> Void)?

    private static let starDisplaySize = CGSize(width: 28, height: 28)

    // Layers
    private let cameraNode = SKCameraNode()
    private let backgroundNode = SKSpriteNode()
    private let dustLayer = SKNode()
    private let ambientLayer = SKNode()
    private let lineLayer = SKNode()
    private let starLayer = SKNode()
    private var ghostNode: StarNode?

    // Ambient starfield (onboarding backdrop): faint distant stars, gently
    // twinkling, kept as unit coords so they survive resize.
    private var ambientUnits: [(node: SKSpriteNode, x: CGFloat, y: CGFloat)] = []

    // Parallax
    private let motionManager = CMMotionManager()
    private var parallaxTarget = CGPoint.zero

    // Touch-driven drag (gesture recognizers fought each other; the scene's
    // own touch pipeline arbitrates tap vs drag with a simple 10pt threshold)
    private var dragCandidateID: UUID?
    private var draggedStarID: UUID?
    private var touchStartPoint: CGPoint?

    // Focus zoom
    private(set) var focusedStarID: UUID?

    // MARK: Lifecycle & sizing

    override init() {
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        // Camera; background rides on it so zooming never reveals edges.
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
        backgroundNode.zPosition = -10
        cameraNode.addChild(backgroundNode)

        dustLayer.zPosition = -5
        addChild(dustLayer)
        ambientLayer.zPosition = -4
        addChild(ambientLayer)
        lineLayer.zPosition = -1
        starLayer.addChild(lineLayer)
        starLayer.zPosition = 0
        addChild(starLayer)

        layoutBackground()
        rebuildDustField()
        rebuildAmbientStarfield()

        // Live drift: the sky keeps pace with the real one while open.
        run(.repeatForever(.sequence([
            .wait(forDuration: 60),
            .run { [weak self] in self?.layoutBackground() },
        ])), withKey: "skyDrift")

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.delegate = self // never receives touches that start on a star
        view.addGestureRecognizer(longPress)

        startParallax()

        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            apply(snapshot)
        }
    }

    override func willMove(from view: SKView) {
        motionManager.stopDeviceMotionUpdates()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, size.height > 0 else { return }
        layoutBackground()
        rebuildDustField()
        repositionAmbientStarfield()
        if focusedStarID == nil {
            cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        }
        guard let snapshot = currentSnapshot else { return }
        for star in snapshot.stars {
            if let node = starNodes[star.id] { position(node, star: star) }
        }
        rebuildLines(snapshot)
    }

    // MARK: Focus zoom — tap a star, the sky leans in

    /// Glide the camera toward a star so it hangs in the upper third,
    /// above a half-height sheet. Everything else dims out of respect.
    func focus(on id: UUID) {
        guard let node = starNodes[id], focusedStarID != id else { return }
        focusedStarID = id

        let zoom: CGFloat = 0.55
        // Screen point where the star should sit: horizontally centered,
        // 72% up the screen (SpriteKit y-up), clear of a medium sheet.
        let anchor = CGPoint(x: 0, y: size.height * 0.22)
        let target = CGPoint(x: node.position.x - anchor.x * zoom,
                             y: node.position.y - anchor.y * zoom)
        let duration = reduceMotion ? 0.01 : 0.55

        let move = SKAction.move(to: clampCamera(target, zoom: zoom), duration: duration)
        move.timingMode = .easeInEaseOut
        let scale = SKAction.scale(to: zoom, duration: duration)
        scale.timingMode = .easeInEaseOut
        cameraNode.run(.group([move, scale]), withKey: "focus")

        // The chosen star swells; the rest of the sky holds its breath.
        node.removeAction(forKey: "shimmer")
        node.run(.scale(to: node.xScale * 1.35, duration: duration), withKey: "focusScale")
        for (otherID, other) in starNodes where otherID != id {
            other.removeAction(forKey: "alpha")
            other.run(.fadeAlpha(to: 0.15, duration: duration))
        }
        lineLayer.run(.fadeAlpha(to: 0.25, duration: duration))
        if currentSnapshot?.stars.first(where: { $0.id == id })?.isRemembered == true {
            Haptics.shared.remembered() // steady presence, not sparkle
        } else {
            Haptics.shared.ignition(luminosity: 0.9)
        }
    }

    /// Reverse the zoom and wake the sky back up.
    func unfocus() {
        guard focusedStarID != nil else { return }
        focusedStarID = nil
        let duration = reduceMotion ? 0.01 : 0.5

        let move = SKAction.move(to: CGPoint(x: size.width / 2, y: size.height / 2), duration: duration)
        move.timingMode = .easeInEaseOut
        let scale = SKAction.scale(to: 1.0, duration: duration)
        scale.timingMode = .easeInEaseOut
        cameraNode.run(.group([move, scale]), withKey: "focus")

        lineLayer.run(.fadeAlpha(to: 1.0, duration: duration))
        // Restore twinkle/scale for everyone from the source of truth.
        if let snapshot = currentSnapshot {
            for star in snapshot.stars {
                if let node = starNodes[star.id] { style(node, star: star, ignite: false) }
            }
        }
    }

    /// Onboarding's orbit step: the camera dives past the sky into a quieter
    /// space — push in, drift right, dim the stars to a whisper so the one
    /// star on stage (drawn by SwiftUI above) holds the room alone.
    /// `zoomedIn: false` reverses it, and *that* is the sky reveal: the
    /// heavens brightening back to meet you.
    func setOnboardingCamera(zoomedIn: Bool, duration: TimeInterval = 1.0) {
        let d = reduceMotion ? 0.01 : duration

        let scale: CGFloat = zoomedIn ? 0.7 : 1.0
        let target = CGPoint(x: size.width * (zoomedIn ? 0.64 : 0.5), y: size.height / 2)
        let move = SKAction.move(to: target, duration: d)
        move.timingMode = .easeInEaseOut
        let zoom = SKAction.scale(to: scale, duration: d)
        zoom.timingMode = .easeInEaseOut
        cameraNode.removeAction(forKey: "focus")
        cameraNode.run(.group([move, zoom]), withKey: "focus")

        // Layer-level dim multiplies under each star's own scintillation,
        // so nothing fights: the sky just recedes into atmosphere.
        starLayer.run(.fadeAlpha(to: zoomedIn ? 0.10 : 1.0, duration: d))
        dustLayer.run(.fadeAlpha(to: zoomedIn ? 0.45 : 1.0, duration: d))
    }

    /// Keep the zoomed viewport inside the world so the dust never runs out.
    private func clampCamera(_ p: CGPoint, zoom: CGFloat) -> CGPoint {
        let halfW = size.width * zoom / 2
        let halfH = size.height * zoom / 2
        return CGPoint(
            x: min(max(p.x, halfW - size.width * 0.15), size.width * 1.15 - halfW),
            y: min(max(p.y, halfH - size.height * 0.15), size.height * 1.15 - halfH)
        )
    }

    // MARK: Background & dust

    /// The Living Sky (LIVING_SKY.md, Phase A): three OkLCh-authored stops —
    /// zenith, mid, horizon warmth band — following the sun, or pinned to the
    /// user's chosen mood from Settings.
    private func layoutBackground() {
        let stops = SkyPalette.stops(variant: SkyPalette.currentVariant())
        guard stops.count == 3 else { return }
        let colors = stops.map {
            UIColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1).cgColor
        } as CFArray
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 256))
        let image = renderer.image { ctx in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.5, 1]
            )!
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 256),
                                             end: CGPoint(x: 0, y: 0), options: [])
        }
        backgroundNode.texture = SKTexture(image: image)
        backgroundNode.size = size
        backgroundNode.position = .zero // centered on camera
    }

    /// Settings changed the sky mood — repaint immediately.
    func refreshBackground() {
        layoutBackground()
    }

    /// Settings-controlled dust multiplier (1.0 floor = original look).
    /// Live-updates existing particles — no re-scatter while sliding.
    var dustBrightness: CGFloat = CGFloat(KinShared.dustBrightness) {
        didSet {
            guard dustBrightness != oldValue else { return }
            for dust in dustLayer.children {
                if let base = dust.userData?["baseAlpha"] as? CGFloat {
                    dust.alpha = min(0.5, base * dustBrightness)
                }
            }
        }
    }

    private func rebuildDustField() {
        dustLayer.removeAllChildren()
        // Spawn beyond the edges so the focus zoom never finds empty sky.
        for _ in 0..<160 {
            let dust = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.4...1.0))
            dust.fillColor = .white
            dust.lineWidth = 0
            let base = CGFloat.random(in: 0.05...0.15)
            dust.alpha = min(0.5, base * dustBrightness)
            dust.userData = ["baseAlpha": base]
            dust.position = CGPoint(
                x: .random(in: -size.width * 0.2...size.width * 1.2),
                y: .random(in: -size.height * 0.2...size.height * 1.2)
            )
            dustLayer.addChild(dust)
        }
    }

    // MARK: Ambient starfield (onboarding backdrop)

    /// A faint field of distant, gently twinkling stars — quiet atmosphere
    /// behind the user's own. Off by default; onboarding turns it on so the
    /// sky feels alive even before a single name is given.
    var showsAmbientStarfield = false {
        didSet {
            guard showsAmbientStarfield != oldValue else { return }
            rebuildAmbientStarfield()
        }
    }

    private func rebuildAmbientStarfield() {
        ambientLayer.removeAllChildren()
        ambientUnits.removeAll()
        guard showsAmbientStarfield, size.width > 0, size.height > 0 else { return }
        for _ in 0..<55 {
            let ux = CGFloat.random(in: 0.02...0.98)
            let uy = CGFloat.random(in: 0.04...0.98)
            let node = SKSpriteNode(texture: Self.starTexture(temperature: .random(in: 0.35...0.9)))
            let s = CGFloat.random(in: 3...8)
            node.size = CGSize(width: s, height: s)
            let base = CGFloat.random(in: 0.10...0.32)
            node.alpha = base
            node.position = CGPoint(x: ux * size.width, y: uy * size.height)
            ambientLayer.addChild(node)
            ambientUnits.append((node, ux, uy))

            guard !reduceMotion else { continue }
            // Slow, out-of-sync scintillation so the field breathes, never pulses.
            let dip = base * CGFloat.random(in: 0.55...0.8)
            let down = SKAction.fadeAlpha(to: dip, duration: .random(in: 1.6...3.2))
            down.timingMode = .easeInEaseOut
            let up = SKAction.fadeAlpha(to: base, duration: .random(in: 1.6...3.2))
            up.timingMode = .easeInEaseOut
            node.run(.sequence([
                .wait(forDuration: .random(in: 0...2.5)),
                .repeatForever(.sequence([down, up])),
            ]))
        }
    }

    private func repositionAmbientStarfield() {
        guard showsAmbientStarfield else { return }
        if ambientUnits.isEmpty { rebuildAmbientStarfield(); return }
        for entry in ambientUnits {
            entry.node.position = CGPoint(x: entry.x * size.width, y: entry.y * size.height)
        }
    }

    // MARK: Parallax

    private func startParallax() {
        guard !reduceMotion, motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates()
    }

    override func update(_ currentTime: TimeInterval) {
        guard focusedStarID == nil, // the camera owns motion while focused
              let attitude = motionManager.deviceMotion?.attitude else { return }
        parallaxTarget = CGPoint(
            x: CGFloat(max(-1, min(1, attitude.roll))) * 10,
            y: CGFloat(max(-1, min(1, attitude.pitch - 0.7))) * 10
        )
        starLayer.position = starLayer.position.lerp(to: parallaxTarget, t: 0.05)
        dustLayer.position = dustLayer.position.lerp(to: CGPoint(x: parallaxTarget.x * 0.4,
                                                                 y: parallaxTarget.y * 0.4), t: 0.05)
    }

    // MARK: Long-press (empty sky only — delegate filters star touches)

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let view, focusedStarID == nil else { return false }
        let scenePoint = convertPoint(fromView: touch.location(in: view))
        let point = starLayer.convert(scenePoint, from: self)
        return !starNodes.values.contains { $0.position.distance(to: point) < 44 }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let view else { return }
        let scenePoint = convertPoint(fromView: recognizer.location(in: view))
        let point = starLayer.convert(scenePoint, from: self)
        guard size.width > 0, size.height > 0 else { return }
        let unitX = min(max(Double(point.x / size.width), 0.05), 0.95)
        let unitY = min(max(1 - Double(point.y / size.height), 0.05), 0.95)
        Haptics.shared.ignition(luminosity: 0.6)
        showGhostStar(atUnit: unitX, unitY)
        onLongPress?(unitX, unitY)
    }

    // MARK: Touch pipeline — tap vs drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard focusedStarID == nil, let point = touches.first?.location(in: starLayer) else { return }
        touchStartPoint = point
        if let (id, node) = starNodes.min(by: {
            $0.value.position.distance(to: point) < $1.value.position.distance(to: point)
        }), node.position.distance(to: point) < 30 {
            dragCandidateID = id
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: starLayer) else { return }

        // Promote candidate → drag once the finger commits to moving.
        if draggedStarID == nil,
           let candidate = dragCandidateID,
           let start = touchStartPoint,
           point.distance(to: start) > 10,
           let node = starNodes[candidate] {
            draggedStarID = candidate
            node.removeAction(forKey: "shimmer")
            node.run(.scale(to: node.xScale * 1.25, duration: 0.15))
            Haptics.shared.ignition(luminosity: 0.5)
        }

        guard let id = draggedStarID, let node = starNodes[id] else { return }
        node.position = CGPoint(
            x: min(max(point.x, size.width * 0.05), size.width * 0.95),
            y: min(max(point.y, size.height * 0.08), size.height * 0.92)
        )
        if let snapshot = currentSnapshot { rebuildLines(snapshot) } // lines follow
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { dragCandidateID = nil; draggedStarID = nil; touchStartPoint = nil }

        if let id = draggedStarID, let node = starNodes[id] {
            // Drag finished: settle and persist.
            let unitX = Double(node.position.x / size.width)
            let unitY = Double(1 - node.position.y / size.height)
            Haptics.shared.ignition(luminosity: 0.8)
            onStarMoved?(id, unitX, unitY)
            if let snapshot = currentSnapshot,
               let star = snapshot.stars.first(where: { $0.id == id }) {
                style(node, star: star, ignite: false) // restores scale/shimmer
            }
            return
        }
        // No drag → a tap, if it started on a star.
        if focusedStarID == nil, let id = dragCandidateID {
            onStarTap?(id)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let id = draggedStarID, let node = starNodes[id],
           let snapshot = currentSnapshot,
           let star = snapshot.stars.first(where: { $0.id == id }) {
            let unitX = Double(node.position.x / size.width)
            let unitY = Double(1 - node.position.y / size.height)
            onStarMoved?(id, unitX, unitY)
            style(node, star: star, ignite: false)
        }
        dragCandidateID = nil
        draggedStarID = nil
        touchStartPoint = nil
    }

    // MARK: Snapshot → nodes

    func apply(_ snapshot: SkySnapshot) {
        guard view != nil, size.width > 0 else {
            pendingSnapshot = snapshot
            return
        }
        currentSnapshot = snapshot
        layoutBackground()

        let ids = Set(snapshot.stars.map(\.id))
        for (id, node) in starNodes where !ids.contains(id) {
            node.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
            starNodes[id] = nil
        }
        for star in snapshot.stars {
            let isNew = starNodes[star.id] == nil
            let node = starNodes[star.id] ?? makeStarNode(for: star)
            if draggedStarID != star.id { position(node, star: star) }
            if focusedStarID == nil {
                // Ignition is for births only — the first apply() is the
                // saved sky returning (`arrival`), without fanfare.
                style(node, star: star,
                      ignite: isNew && hasPopulated,
                      arrival: isNew && !hasPopulated)
            }
        }
        hasPopulated = true
        rebuildLines(snapshot)
        // NOTE: the ghost star is deliberately NOT removed here — apply()
        // runs on every snapshot refresh, which would sweep the ghost away
        // while the naming sheet is still up. Its one owner is SkyView's
        // sheet onDismiss. If a star was just born there, the ghost's
        // fade-out overlaps the newcomer's ignition — a soft morph, free.
    }

    private func makeStarNode(for star: SkySnapshot.Star) -> StarNode {
        let node = StarNode(temperature: star.temperature)
        node.name = star.id.uuidString
        node.alpha = 0
        starLayer.addChild(node)
        starNodes[star.id] = node
        return node
    }

    private func position(_ node: StarNode, star: SkySnapshot.Star) {
        node.position = CGPoint(x: star.x * size.width, y: (1 - star.y) * size.height)
    }

    private func style(_ node: StarNode, star: SkySnapshot.Star, ignite: Bool,
                       arrival: Bool = false) {
        let lum = star.luminosity
        // Narrower size spread than before — real skies vary brightness far
        // more than diameter. Brightness carries the meaning; size whispers it.
        let baseScale = 0.7 + lum * 0.7
        let base = CGFloat(0.5 + 0.5 * lum)
        node.removeAction(forKey: "focusScale")

        // style() runs on EVERY snapshot refresh, which is frequent. It must
        // be idempotent: entrances (arrival/ignite) always take the stage,
        // but steady-state passes may only rebuild the alpha/shimmer loops
        // when the star's brightness actually changed — never interrupting
        // an entrance in flight, never resetting a loop for no reason.
        if node.userData == nil { node.userData = NSMutableDictionary() }
        let storedBase = node.userData?["alphaBase"] as? CGFloat
        let baseChanged = storedBase == nil || abs((storedBase ?? 0) - base) > 0.01
        node.userData?["alphaBase"] = base
        let alphaIdle = node.action(forKey: "alpha") == nil
        let shimmerIdle = node.action(forKey: "shimmer") == nil

        node.halo.alpha = 0.10 + 0.28 * lum
        // Diffraction cross: only the brightest stars earn one, and faintly —
        // the detail you notice on the second week, not the first minute.
        node.cross.alpha = lum > 0.55 ? CGFloat((lum - 0.55) / 0.45) * 0.22 : 0

        guard !reduceMotion else {
            node.removeAction(forKey: "alpha")
            node.removeAction(forKey: "shimmer")
            node.alpha = base
            node.setScale(baseScale)
            return
        }

        if star.isRemembered {
            if arrival {
                // The remembered arrive last, after the living sky has
                // settled — a beat of stillness, then a slow, sure fade.
                node.removeAction(forKey: "alpha")
                node.alpha = 0
                node.run(.sequence([
                    .wait(forDuration: 0.7),
                    .fadeAlpha(to: base, duration: 1.0),
                ]), withKey: "alpha")
            } else if alphaIdle || baseChanged {
                node.removeAction(forKey: "alpha")
                node.alpha = base
            }
            // else: an arrival fade is mid-flight — it ends at base; let it.
            node.setScale(baseScale)
            node.removeAction(forKey: "shimmer")
            // Steady light, breathing once per ~16s — presence, not performance.
            let inhale = SKAction.scale(to: baseScale * 1.015, duration: 8.0)
            inhale.timingMode = .easeInEaseOut
            let exhale = SKAction.scale(to: baseScale * 0.99, duration: 8.0)
            exhale.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([inhale, exhale])), withKey: "shimmer")
            return
        }

        // Micro-scintillation: ±5–8% alpha over ~1–1.6s, randomized per star
        // so the field never pulses in sync. Felt, not watched.
        let dip = base * CGFloat(Double.random(in: 0.92...0.95))
        let down = SKAction.fadeAlpha(to: dip, duration: .random(in: 0.9...1.6))
        down.timingMode = .easeInEaseOut
        let up = SKAction.fadeAlpha(to: base, duration: .random(in: 0.9...1.6))
        up.timingMode = .easeInEaseOut
        let scintillate = SKAction.repeatForever(.sequence([down, up]))

        // Slow breath: ±2% scale over ~7s. The sky is alive, barely.
        let breath = Double.random(in: 6.0...9.0)
        let grow = SKAction.scale(to: baseScale * 1.02, duration: breath)
        grow.timingMode = .easeInEaseOut
        let shrink = SKAction.scale(to: baseScale * 0.985, duration: breath)
        shrink.timingMode = .easeInEaseOut
        let breathe = SKAction.repeatForever(.sequence([grow, shrink]))

        if ignite {
            // Born, not faded in: a spark that blooms past its size, then
            // settles into its place and starts breathing.
            node.removeAction(forKey: "alpha")
            node.removeAction(forKey: "shimmer")
            node.alpha = 0
            node.setScale(baseScale * 0.2)
            node.run(.sequence([.fadeAlpha(to: base, duration: 0.3), scintillate]),
                     withKey: "alpha")
            let spark = SKAction.scale(to: baseScale * 1.3, duration: 0.3)
            spark.timingMode = .easeOut
            let settle = SKAction.scale(to: baseScale, duration: 0.6)
            settle.timingMode = .easeInEaseOut
            node.run(.sequence([spark, settle, breathe]), withKey: "shimmer")

            // Birth sparkle: the tapered hairline cross flashes once —
            // appears, reaches past the bloom, and collapses to nothing —
            // then hands the cross back to its luminosity-earned steady state.
            // Choreography: two phases, summing to exactly `flashTotal`.
            // Phase A (40%): grow 0.3→2.0×, easing out; alpha arrives fast
            //   (half the phase) so the line is bright while still reaching.
            // Phase B (60%): collapse to zero, easing in; alpha dies with it.
            // A group's length = its longest member, so each phase's scale
            // action defines the phase; alpha just rides inside it.
            let flashTotal = 1.4
            let growDuration = flashTotal * 0.4
            let closeDuration = flashTotal * 0.6

            let steadyCross = node.cross.alpha // set above by the lum gate
            node.cross.removeAllActions()
            node.cross.alpha = 0
            node.cross.setScale(0.3)

            let reach = SKAction.scale(to: 1.0, duration: growDuration)
            reach.timingMode = .easeOut
            let flashIn = SKAction.group([
                .fadeAlpha(to: 0.85, duration: growDuration * 0.5),
                reach,
            ])

            let close = SKAction.scale(to: 0.001, duration: closeDuration)
            close.timingMode = .easeIn
            let collapse = SKAction.group([
                .fadeAlpha(to: 0, duration: closeDuration),
                close,
            ])

            let handBack = SKAction.run { [weak node] in
                node?.cross.setScale(1.0)
                node?.cross.alpha = steadyCross
            }
            node.cross.run(.sequence([flashIn, collapse, handBack]))
        } else if arrival {
            // The saved sky returning: a brisk, quiet fade-up (much faster
            // than the scintillation's lazy first ramp), then normal life.
            node.removeAction(forKey: "alpha")
            node.removeAction(forKey: "shimmer")
            node.alpha = 0
            let fadeUp = SKAction.fadeAlpha(to: base, duration: 0.4)
            fadeUp.timingMode = .easeOut
            node.run(.sequence([fadeUp, scintillate]), withKey: "alpha")
            node.setScale(baseScale)
            node.run(breathe, withKey: "shimmer")
        } else {
            // Steady state: touch nothing that's already living correctly.
            if alphaIdle || baseChanged {
                node.removeAction(forKey: "alpha")
                node.run(scintillate, withKey: "alpha")
            }
            if shimmerIdle || baseChanged {
                node.removeAction(forKey: "shimmer")
                node.setScale(baseScale)
                node.run(breathe, withKey: "shimmer")
            }
        }
    }

    // MARK: Constellation lines

    private func rebuildLines(_ snapshot: SkySnapshot) {
        lineLayer.removeAllChildren()
        for line in snapshot.lines {
            guard let a = starNodes[line.a], let b = starNodes[line.b] else { continue }
            let path = CGMutablePath()
            path.move(to: a.position)
            path.addLine(to: b.position)
            let node = SKShapeNode(path: path)
            node.strokeColor = SKColor(white: 1, alpha: 0.10 + 0.20 * line.strength)
            node.lineWidth = 0.8
            node.lineCap = .round
            lineLayer.addChild(node)
        }
    }

    // MARK: Ghost star

    private func showGhostStar(atUnit x: Double, _ y: Double) {
        removeGhostStar()
        let ghost = StarNode(temperature: 0.5)
        ghost.position = CGPoint(x: x * size.width, y: (1 - y) * size.height)
        ghost.alpha = 0
        ghost.setScale(0.7)
        starLayer.addChild(ghost)
        ghostNode = ghost
        guard !reduceMotion else { ghost.alpha = 0.3; return }
        ghost.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.9),
            .fadeAlpha(to: 0.15, duration: 0.9),
        ])))
    }

    func removeGhostStar() {
        ghostNode?.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
        ghostNode = nil
    }

    // MARK: Star texture baking

    private static var textureCache: [Int: SKTexture] = [:]
    private static let temperatureBuckets = 8

    static func starTexture(temperature: Double) -> SKTexture {
        let bucket = min(temperatureBuckets - 1, max(0, Int(temperature * Double(temperatureBuckets))))
        if let cached = textureCache[bucket] { return cached }
        let texture = SKTexture(image: pointImage(temperature: temperature))
        textureCache[bucket] = texture
        return texture
    }

    /// The luminous point — a hand-tuned point-spread falloff, the way a
    /// star actually renders through a lens: white-hot center, a tinted
    /// mid-falloff carrying the star's temperature, and a long transparent
    /// tail. No geometry. This is the star.
    static func pointImage(temperature: Double, px: CGFloat = 76) -> UIImage {
        let bucket = min(temperatureBuckets - 1, max(0, Int(temperature * Double(temperatureBuckets))))
        let tint = color(temperature: (Double(bucket) + 0.5) / Double(temperatureBuckets))
        let mid = UIColor.white.blended(with: tint, fraction: 0.55)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        return renderer.image { ctx in
            let c = ctx.cgContext
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.95).cgColor,
                mid.withAlphaComponent(0.55).cgColor,
                tint.withAlphaComponent(0.16).cgColor,
                tint.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.10, 0.24, 0.52, 1]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: locations)!
            c.drawRadialGradient(gradient,
                                 startCenter: CGPoint(x: px / 2, y: px / 2), startRadius: 0,
                                 endCenter: CGPoint(x: px / 2, y: px / 2), endRadius: px / 2,
                                 options: [])
        }
    }

    /// Hero rendering for onboarding and SwiftUI surfaces: the point at full
    /// brightness with its earned diffraction cross.
    static func starImage(temperature: Double) -> UIImage {
        let px: CGFloat = 84
        let center = px / 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        return renderer.image { ctx in
            let c = ctx.cgContext
            // Faint crosshair beneath…
            c.saveGState()
            c.translateBy(x: center, y: center)
            c.setShadow(offset: .zero, blur: 1.5,
                        color: UIColor.white.withAlphaComponent(0.4).cgColor)
            c.addPath(taperedCrossPath(arm: 38, baseWidth: 1.8))
            c.setFillColor(UIColor.white.withAlphaComponent(0.4).cgColor)
            c.fillPath()
            c.restoreGState()
            // …the point of light on top.
            pointImage(temperature: temperature, px: px)
                .draw(in: CGRect(x: 0, y: 0, width: px, height: px))
        }
    }

    static func starPath(radius r: CGFloat, waist: CGFloat = 0.1) -> CGPath {
        let c = r * waist
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: c, y: c))
        p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: c, y: -c))
        p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -c, y: -c))
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: -c, y: c))
        p.closeSubpath()
        return p
    }

    /// Warm gold ↔ cool blue by temperature. Widget's WidgetSky.color mirrors this.
    static func color(temperature t: Double) -> UIColor {
        UIColor(red: 1.0 - 0.35 * t, green: 0.86 - 0.10 * t, blue: 0.55 + 0.45 * t, alpha: 1)
    }

    // MARK: Ambient sky (flags: "random_comet", "meteor_shower")

    enum AmbientSkyMode {
        case none
        case comets       // a lone streak every 20–25s
        case meteorShower // burst events every few minutes; supersedes comets
    }

    /// Pure atmosphere, tied to nothing. Flag-gated so we can measure
    /// whether ambience helps retention or just burns battery.
    var ambientMode: AmbientSkyMode = .none {
        didSet {
            guard ambientMode != oldValue else { return }
            restartAmbient()
        }
    }

    private func restartAmbient() {
        removeAction(forKey: "ambient")
        guard !reduceMotion else { return }
        switch ambientMode {
        case .none:
            break
        case .comets:
            let loop = SKAction.repeatForever(.sequence([
                .wait(forDuration: 22.5, withRange: 5), // 20–25s
                .run { [weak self] in self?.spawnStreak() },
            ]))
            // First one arrives quickly so enabling the flag is verifiable.
            run(.sequence([
                .wait(forDuration: 4),
                .run { [weak self] in self?.spawnStreak() },
                loop,
            ]), withKey: "ambient")
        case .meteorShower:
            let burst = SKAction.run { [weak self] in self?.runMeteorShowerBurst() }
            run(.sequence([
                .wait(forDuration: 5), // first shower well inside the opening glance
                burst,
                .repeatForever(.sequence([
                    .wait(forDuration: 60, withRange: 30), // then every 45–75s
                    burst,
                ])),
            ]), withKey: "ambient")
        }
    }

    /// A shower: 6–10 streaks over ~8 seconds, all radiating from the same
    /// side of the sky — real showers share a radiant, and that coherence
    /// is what makes it read as an event rather than noise.
    private func runMeteorShowerBurst() {
        guard view != nil, size.width > 0, focusedStarID == nil else { return }
        let fromLeft = Bool.random()
        let count = Int.random(in: 6...10)
        for i in 0..<count {
            run(.sequence([
                .wait(forDuration: Double(i) * 0.9, withRange: 0.6),
                .run { [weak self] in self?.spawnStreak(fromLeft: fromLeft, shower: true) },
            ]))
        }
    }

    /// A faint streak on a straight line, gone in about a second — the way
    /// real meteors look: a scratch of light, not a traveling object.
    private func spawnStreak(fromLeft: Bool = Bool.random(), shower: Bool = false) {
        guard view != nil, size.width > 0, focusedStarID == nil else { return }

        // Showers rain across more of the sky; lone comets stay high.
        let yRange = shower
            ? size.height * 0.45...size.height * 0.98
            : size.height * 0.60...size.height * 0.98
        let startY = CGFloat.random(in: yRange)
        let drop = CGFloat.random(in: size.height * 0.15...size.height * 0.35)
        let start = CGPoint(x: fromLeft ? -60 : size.width + 60, y: startY)
        let end = CGPoint(x: fromLeft ? size.width + 60 : -60, y: startY - drop)
        let angle = atan2(end.y - start.y, end.x - start.x)

        let streak = SKSpriteNode(texture: Self.streakTexture(),
                                  size: CGSize(width: shower ? 52 : 64, height: 3))
        streak.anchorPoint = CGPoint(x: 1.0, y: 0.5) // bright head leads
        streak.position = start
        streak.zRotation = angle
        streak.alpha = 0
        starLayer.addChild(streak)

        // Shower members are quicker and fainter than a lone visitor.
        let duration = shower ? Double.random(in: 0.8...1.2)
                              : Double.random(in: 1.1...1.6)
        let peak: CGFloat = shower ? 0.55 : 0.7
        let move = SKAction.move(to: end, duration: duration) // linear — no easing
        let fade = SKAction.sequence([
            .fadeAlpha(to: peak, duration: 0.15),
            .wait(forDuration: max(0.1, duration - 0.55)),
            .fadeOut(withDuration: 0.4),
        ])
        streak.run(.sequence([.group([move, fade]), .removeFromParent()]))
    }

    private static var streakTextureCache: SKTexture?

    /// Horizontal gradient line: transparent tail → bright head (right edge).
    private static func streakTexture() -> SKTexture {
        if let cached = streakTextureCache { return cached }
        let size = CGSize(width: 128, height: 6)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            c.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                   cornerRadius: 3).cgPath)
            c.clip()
            let colors = [UIColor.white.withAlphaComponent(0.0).cgColor,
                          UIColor.white.withAlphaComponent(0.35).cgColor,
                          UIColor.white.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 0.6, 1])!
            c.drawLinearGradient(gradient,
                                 start: CGPoint(x: 0, y: size.height / 2),
                                 end: CGPoint(x: size.width, y: size.height / 2),
                                 options: [])
        }
        let texture = SKTexture(image: image)
        streakTextureCache = texture
        return texture
    }

    // MARK: The payoff — invest disproportionate polish here

    func runShootingStar(toward id: UUID) {
        guard let target = starNodes[id] else { return }
        let comet = SKShapeNode(circleOfRadius: 2.5)
        comet.fillColor = .white
        comet.lineWidth = 0
        comet.position = CGPoint(x: -20, y: size.height + 20)
        starLayer.addChild(comet)

        if let trail = SKEmitterNode(fileNamed: "CometTrail") {
            trail.targetNode = starLayer
            comet.addChild(trail)
        }

        let path = CGMutablePath()
        path.move(to: comet.position)
        path.addQuadCurve(
            to: target.position,
            control: CGPoint(x: size.width * 0.7, y: size.height * 0.9)
        )
        let duration = reduceMotion ? 0.01 : 1.4
        let flight = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
        flight.timingMode = .easeOut

        comet.run(.sequence([
            flight,
            .run { [weak self] in
                self?.pulse(target)
                Haptics.shared.ignition(luminosity: 1.0)
            },
            .group([.fadeOut(withDuration: 0.15), .scale(to: 0.1, duration: 0.15)]),
            .removeFromParent(),
        ]))
    }

    private func pulse(_ node: StarNode) {
        node.removeAction(forKey: "shimmer")
        let current = node.xScale
        let up = SKAction.scale(to: current * 1.6, duration: 0.25)
        up.timingMode = .easeOut
        let down = SKAction.scale(to: current, duration: 0.5)
        down.timingMode = .easeInEaseOut
        node.run(.sequence([up, down]))
    }
}

// MARK: - StarNode: a point of light

/// Three layers, back to front: a wide tinted halo, a faint static
/// diffraction cross (brightest stars only — style() gates it), and the
/// luminous core: a hand-tuned point-spread falloff, the way a real star
/// renders through a lens. No geometry, no ornament — just light.
/// Container-level alpha/scale drive scintillation/breath, so all scene
/// choreography works unchanged.
final class StarNode: SKNode {
    let halo: SKSpriteNode
    let cross: SKSpriteNode
    let core: SKSpriteNode

    init(temperature: Double) {
        halo = SKSpriteNode(texture: SkyScene.haloTexture(temperature: temperature),
                            size: CGSize(width: 58, height: 58))
        cross = SKSpriteNode(texture: SkyScene.crossTexture(),
                             size: CGSize(width: 44, height: 44))
        core = SKSpriteNode(texture: SkyScene.starTexture(temperature: temperature),
                            size: CGSize(width: 30, height: 30))
        super.init()
        halo.zPosition = 0
        cross.zPosition = 1
        core.zPosition = 2
        cross.alpha = 0 // earned by luminosity, granted in style()
        addChild(halo)
        addChild(cross)
        addChild(core)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

extension SkyScene {

    private static var haloCache: [Int: SKTexture] = [:]
    private static var crossCache: SKTexture?

    /// Wide, quiet tinted glow. Barely there; felt as atmosphere.
    static func haloTexture(temperature: Double) -> SKTexture {
        let bucket = min(7, max(0, Int(temperature * 8)))
        if let cached = haloCache[bucket] { return cached }
        let px: CGFloat = 92
        let tint = color(temperature: (Double(bucket) + 0.5) / 8.0)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            let colors = [tint.withAlphaComponent(0.30).cgColor,
                          tint.withAlphaComponent(0.10).cgColor,
                          tint.withAlphaComponent(0.0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 0.4, 1])!
            c.drawRadialGradient(gradient,
                                 startCenter: CGPoint(x: px / 2, y: px / 2), startRadius: 0,
                                 endCenter: CGPoint(x: px / 2, y: px / 2), endRadius: px / 2,
                                 options: [])
        }
        let texture = SKTexture(image: image)
        haloCache[bucket] = texture
        return texture
    }

    /// A single hairline four-point cross, white, heavily softened.
    /// Shared by all stars (displayed at ≤0.22 alpha, color reads from the
    /// core beneath). Never rotates. Present only on the brightest.
    static func crossTexture() -> SKTexture {
        if let cached = crossCache { return cached }
        let px: CGFloat = 132
        let center = px / 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: center, y: center)
            // Sword-thin arms: constant hairline at the base (2.2px ≈ 0.73pt
            // at display size), tapering to a point at each tip.
            c.setShadow(offset: .zero, blur: 1.5,
                        color: UIColor.white.withAlphaComponent(0.5).cgColor)
            c.addPath(taperedCrossPath(arm: 60, baseWidth: 2.2))
            c.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            c.fillPath()
        }
        let texture = SKTexture(image: image)
        crossCache = texture
        return texture
    }

    /// Four arms like very thin swords: full width at the star, a straight
    /// taper to a point at the tip. Never broader than the base.
    static func taperedCrossPath(arm: CGFloat, baseWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for k in 0..<4 {
            let angle = CGFloat(k) * .pi / 2
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let perp = CGPoint(x: -sin(angle), y: cos(angle))
            path.move(to: CGPoint(x: perp.x * baseWidth / 2, y: perp.y * baseWidth / 2))
            path.addLine(to: CGPoint(x: dir.x * arm, y: dir.y * arm))
            path.addLine(to: CGPoint(x: -perp.x * baseWidth / 2, y: -perp.y * baseWidth / 2))
            path.closeSubpath()
        }
        return path
    }
}

private extension UIColor {
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f,
                       blue: b1 + (b2 - b1) * f, alpha: a1 + (a2 - a1) * f)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
    func lerp(to target: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: x + (target.x - x) * t, y: y + (target.y - y) * t)
    }
}
