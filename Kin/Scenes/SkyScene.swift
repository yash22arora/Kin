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

    private var starNodes: [UUID: SKSpriteNode] = [:]
    private var currentSnapshot: SkySnapshot?
    private var pendingSnapshot: SkySnapshot?
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
    private let lineLayer = SKNode()
    private let starLayer = SKNode()
    private var ghostNode: SKSpriteNode?

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
        lineLayer.zPosition = -1
        starLayer.addChild(lineLayer)
        starLayer.zPosition = 0
        addChild(starLayer)

        layoutBackground()
        rebuildDustField()

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
        Haptics.shared.ignition(luminosity: 0.9)
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

    private func layoutBackground() {
        let colors = SkySnapshot.skyGradientColors()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 256))
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: colors.top.r, green: colors.top.g, blue: colors.top.b, alpha: 1).cgColor,
                    UIColor(red: colors.bottom.r, green: colors.bottom.g, blue: colors.bottom.b, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 256),
                                  end: CGPoint(x: 0, y: 0), options: [])
        }
        backgroundNode.texture = SKTexture(image: image)
        backgroundNode.size = size
        backgroundNode.position = .zero // centered on camera
    }

    private func rebuildDustField() {
        dustLayer.removeAllChildren()
        // Spawn beyond the edges so the focus zoom never finds empty sky.
        for _ in 0..<160 {
            let dust = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.4...1.0))
            dust.fillColor = .white
            dust.lineWidth = 0
            dust.alpha = CGFloat.random(in: 0.05...0.15)
            dust.position = CGPoint(
                x: .random(in: -size.width * 0.2...size.width * 1.2),
                y: .random(in: -size.height * 0.2...size.height * 1.2)
            )
            dustLayer.addChild(dust)
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
            if focusedStarID == nil { style(node, star: star, ignite: isNew) }
        }
        rebuildLines(snapshot)
        removeGhostStar()
    }

    private func makeStarNode(for star: SkySnapshot.Star) -> SKSpriteNode {
        let node = SKSpriteNode(
            texture: Self.starTexture(temperature: star.temperature),
            size: Self.starDisplaySize
        )
        node.name = star.id.uuidString
        node.alpha = 0
        starLayer.addChild(node)
        starNodes[star.id] = node
        return node
    }

    private func position(_ node: SKSpriteNode, star: SkySnapshot.Star) {
        node.position = CGPoint(x: star.x * size.width, y: (1 - star.y) * size.height)
    }

    private func style(_ node: SKSpriteNode, star: SkySnapshot.Star, ignite: Bool) {
        let baseScale = 0.6 + star.luminosity * 0.9
        let base = CGFloat(0.45 + 0.55 * star.luminosity)
        node.removeAction(forKey: "alpha")
        node.removeAction(forKey: "shimmer")
        node.removeAction(forKey: "focusScale")

        guard !reduceMotion else {
            node.alpha = base
            node.setScale(baseScale)
            return
        }

        if star.isRemembered {
            node.alpha = base
            node.setScale(baseScale)
            let inhale = SKAction.scale(to: baseScale * 1.05, duration: 3.0)
            inhale.timingMode = .easeInEaseOut
            let exhale = SKAction.scale(to: baseScale * 0.98, duration: 3.0)
            exhale.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([inhale, exhale])), withKey: "shimmer")
            return
        }

        let rate = LuminosityEngine.twinkleRate(luminosity: star.luminosity)
        let half = 0.5 / rate
        let twinkle = SKAction.repeatForever(.sequence([
            .fadeAlpha(to: base * 0.75, duration: half),
            .fadeAlpha(to: base, duration: half),
        ]))
        node.run(ignite ? .sequence([.fadeAlpha(to: base, duration: 1.2), twinkle]) : twinkle,
                 withKey: "alpha")

        node.setScale(baseScale)
        let grow = SKAction.scale(to: baseScale * 1.08, duration: half * 1.4)
        grow.timingMode = .easeInEaseOut
        let shrink = SKAction.scale(to: baseScale * 0.95, duration: half * 1.4)
        shrink.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([grow, shrink])), withKey: "shimmer")
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
        let ghost = SKSpriteNode(texture: Self.starTexture(temperature: 0.5),
                                 size: Self.starDisplaySize)
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
        let texture = SKTexture(image: starImage(temperature: temperature))
        textureCache[bucket] = texture
        return texture
    }

    /// The star artwork as a plain image — onboarding and any SwiftUI surface
    /// can show the exact same sparkle the scene renders.
    static func starImage(temperature: Double) -> UIImage {
        let bucket = min(temperatureBuckets - 1, max(0, Int(temperature * Double(temperatureBuckets))))
        let px: CGFloat = 84
        let center = px / 2
        let color = color(temperature: (Double(bucket) + 0.5) / Double(temperatureBuckets))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: center, y: center)
            c.saveGState()
            c.setShadow(offset: .zero, blur: 16, color: color.withAlphaComponent(0.9).cgColor)
            c.addPath(starPath(radius: 24, waist: 0.1))
            c.setFillColor(color.cgColor)
            c.fillPath()
            c.restoreGState()
            c.addPath(starPath(radius: 24, waist: 0.1))
            c.setFillColor(color.cgColor)
            c.fillPath()
            c.addPath(starPath(radius: 13, waist: 0.1))
            c.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            c.fillPath()
        }
        return image
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

    private func pulse(_ node: SKSpriteNode) {
        node.removeAction(forKey: "shimmer")
        let current = node.xScale
        let up = SKAction.scale(to: current * 1.6, duration: 0.25)
        up.timingMode = .easeOut
        let down = SKAction.scale(to: current, duration: 0.5)
        down.timingMode = .easeInEaseOut
        node.run(.sequence([up, down]))
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
