import AppKit
import QuartzCore
import SceneKit
import SwiftUI

struct CinematicTab: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        GeometryReader { proxy in
            let caption = CinematicCaption(project: project)

            ZStack(alignment: .bottomLeading) {
                CinematicSceneView(
                    projectID: project.id,
                    lines: project.liveLog,
                    phase: project.phase,
                    isActive: project.isRunning || project.isAutoPlaying
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: max(160, proxy.size.height * 0.28))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                CinematicHUD(caption: caption)
                    .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.08))
            }
        }
        .frame(minHeight: 520)
    }
}

private struct CinematicHUD: View {
    var caption: CinematicCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: caption.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(caption.color)
                Text(caption.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(caption.phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule())
            }

            Text(caption.detail)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(caption.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct CinematicCaption {
    var title: String
    var detail: String
    var phase: String
    var systemImage: String
    var color: Color

    @MainActor
    init(project: CompassProject) {
        let latest = project.liveLog.last
        let currentPhase = project.isPaused ? LoopPhase.paused : project.phase
        phase = currentPhase.rawValue

        if (project.isRunning || project.isAutoPlaying) && Self.isThinking(project: project) {
            title = "The robot wizard is kiting the wave"
            detail = "Codex is thinking while pressure gathers around the arena."
            systemImage = "brain.head.profile"
            color = .blue
            return
        }

        guard let latest else {
            title = "The arena is quiet"
            detail = "Start a run to wake the dark expedition."
            systemImage = "moon.stars"
            color = .secondary
            return
        }

        let spell = SpellSchool(line: latest)
        color = spell.swiftUIColor
        systemImage = spell.systemImage

        switch latest.status {
        case .running:
            title = "\(spell.name) is being cast"
            detail = Self.detail(for: latest) ?? "An enemy is closing in."
        case .completed:
            title = "\(spell.name) landed"
            detail = Self.detail(for: latest) ?? "The wave breaks for a moment."
        case .failed:
            title = "The spell backfired"
            detail = Self.detail(for: latest) ?? "The arena flashes red."
        case .none:
            title = latest.text.isEmpty ? "The expedition advances" : latest.text
            detail = Self.detail(for: latest) ?? "The wizard watches the next gate."
        }
    }

    @MainActor
    private static func isThinking(project: CompassProject) -> Bool {
        !project.liveLog.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private static func detail(for line: LiveLine) -> String? {
        if let detail = line.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            return detail
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
        }
        return line.text.isEmpty ? nil : line.text
    }
}

struct CinematicSceneView: NSViewRepresentable {
    var projectID: UUID
    var lines: [LiveLine]
    var phase: LoopPhase
    var isActive: Bool

    func makeCoordinator() -> CinematicSceneCoordinator {
        CinematicSceneCache.shared.coordinator(for: projectID)
    }

    func makeNSView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.update(lines: lines, phase: phase, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: CinematicSceneCoordinator) {
        CinematicSceneCache.shared.release(coordinator.projectID)
    }
}

@MainActor
private final class CinematicSceneCache {
    static let shared = CinematicSceneCache()

    private struct Entry {
        var coordinator: CinematicSceneCoordinator
        var retainCount: Int
        var releaseTimer: Timer?
    }

    private let releaseDelay: TimeInterval = 5 * 60
    private var entries: [UUID: Entry] = [:]

    private init() {}

    func coordinator(for projectID: UUID) -> CinematicSceneCoordinator {
        if var entry = entries[projectID] {
            entry.releaseTimer?.invalidate()
            entry.releaseTimer = nil
            entry.retainCount += 1
            entries[projectID] = entry
            return entry.coordinator
        }

        let coordinator = CinematicSceneCoordinator(projectID: projectID)
        entries[projectID] = Entry(coordinator: coordinator, retainCount: 1)
        return coordinator
    }

    func release(_ projectID: UUID) {
        guard var entry = entries[projectID] else { return }
        entry.retainCount = max(0, entry.retainCount - 1)
        entry.releaseTimer?.invalidate()

        if entry.retainCount == 0 {
            entry.releaseTimer = Timer.scheduledTimer(withTimeInterval: releaseDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.expire(projectID)
                }
            }
        }

        entries[projectID] = entry
    }

    private func expire(_ projectID: UUID) {
        guard let entry = entries[projectID], entry.retainCount == 0 else { return }
        entry.coordinator.stop()
        entries[projectID] = nil
    }
}

private enum CinematicCameraShot {
    case home
    case wide
    case castPrep
    case impact
    case overhead
    case failure
    case victory

    var position: SCNVector3 {
        switch self {
        case .home:
            return SCNVector3(0, 5.5, 12)
        case .wide:
            return SCNVector3(-4.3, 6.2, 13.2)
        case .castPrep:
            return SCNVector3(-2.4, 3.1, 5.4)
        case .impact:
            return SCNVector3(2.7, 3.8, 6.2)
        case .overhead:
            return SCNVector3(0, 9.8, 5.6)
        case .failure:
            return SCNVector3(0.6, 2.4, 4.4)
        case .victory:
            return SCNVector3(0, 7.1, 15.4)
        }
    }

    var fieldOfView: CGFloat {
        switch self {
        case .castPrep, .failure:
            return 34
        case .impact:
            return 38
        case .overhead:
            return 48
        case .victory:
            return 52
        case .home, .wide:
            return 42
        }
    }

    var duration: TimeInterval {
        switch self {
        case .failure:
            return 0.22
        case .impact, .castPrep:
            return 0.48
        case .victory:
            return 1.2
        case .home, .wide, .overhead:
            return 0.82
        }
    }
}

final class CinematicSceneCoordinator: NSObject {
    let projectID: UUID
    private let scene = SCNScene()
    private let cameraRig = SCNNode()
    private let cameraNode = SCNNode()
    private let wizardNode = SCNNode()
    private let staffOrbNode = SCNNode()
    private let enemyRoot = SCNNode()
    private let effectsRoot = SCNNode()
    private let keyLightNode = SCNNode()
    private let rimLightNode = SCNNode()
    private let phaseLightNode = SCNNode()
    private var activeEnemies: [UUID: SCNNode] = [:]
    private var lineStatuses: [UUID: LiveLine.Status] = [:]
    private var hasBuiltScene = false
    private var hasBootstrapped = false
    private var lastPhase: LoopPhase = .idle
    private var thinkingTimer: Timer?
    private var skirmishTimer: Timer?
    private var isThinking = false
    private var ambientSpawnIndex = 0
    private var nextAmbientSpawnDate = Date.distantPast
    private var enemyHealth: [ObjectIdentifier: CGFloat] = [:]

    init(projectID: UUID) {
        self.projectID = projectID
        super.init()
    }

    deinit {
        stop()
    }

    func makeView() -> SCNView {
        if !hasBuiltScene {
            hasBuiltScene = true
            buildScene()
        }

        let view = SCNView(frame: .zero)
        view.scene = scene
        view.backgroundColor = .black
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.pointOfView = cameraNode
        return view
    }

    func update(lines: [LiveLine], phase: LoopPhase, isActive: Bool) {
        if !hasBootstrapped {
            hasBootstrapped = true
            lastPhase = phase
            lineStatuses = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.status) })
            syncRunningEnemies(with: lines)
            setThinking(isActive && isWaitingForCodex(lines: lines))
            return
        }

        if phase != lastPhase {
            lastPhase = phase
            applyPhaseChange(phase)
        }

        let currentIDs = Set(lines.map(\.id))
        lineStatuses = lineStatuses.filter { currentIDs.contains($0.key) }
        activeEnemies = activeEnemies.filter { currentIDs.contains($0.key) || $0.value.parent != nil }

        for line in lines {
            let previousStatus = lineStatuses[line.id]
            if previousStatus == nil || previousStatus != line.status {
                apply(line)
                lineStatuses[line.id] = line.status
            }
        }

        syncRunningEnemies(with: lines)
        setThinking(isActive && isWaitingForCodex(lines: lines))
    }

    func stop() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
        skirmishTimer?.invalidate()
        skirmishTimer = nil
    }

    private func resourceImage(_ name: String) -> NSImage? {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Cinematic"
        ) ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func applyPhaseChange(_ phase: LoopPhase) {
        switch phase {
        case .planning:
            phaseLightNode.light?.color = SpellSchool.scan.nsColor
            phaseLightNode.light?.intensity = 520
            chargeArena(color: SpellSchool.scan.nsColor)
            stageCamera(.wide)
        case .developing:
            phaseLightNode.light?.color = SpellSchool.shell.nsColor
            phaseLightNode.light?.intensity = 680
            chargeArena(color: SpellSchool.shell.nsColor)
            stageCamera(.castPrep)
        case .verifying:
            phaseLightNode.light?.color = SpellSchool.verify.nsColor
            phaseLightNode.light?.intensity = 760
            sealArena(color: SpellSchool.verify.nsColor)
            stageCamera(.overhead)
        case .succeeded:
            victorySurge()
        case .failed:
            stageCamera(.failure)
            phaseLightNode.light?.color = SpellSchool.failure.nsColor
            phaseLightNode.light?.intensity = 900
            shakeCamera()
            chargeArena(color: SpellSchool.failure.nsColor)
        case .paused, .cancelled, .idle:
            phaseLightNode.light?.intensity = 320
            stageCamera(.home)
        }
    }

    private func stageCamera(_ shot: CinematicCameraShot) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = shot.duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = shot.position
        cameraNode.camera?.fieldOfView = shot.fieldOfView
        SCNTransaction.commit()
    }

    private func buildScene() {
        scene.background.contents = resourceImage("void-arches")
            ?? NSColor(calibratedRed: 0.012, green: 0.013, blue: 0.018, alpha: 1)
        scene.fogStartDistance = 16
        scene.fogEndDistance = 38
        scene.fogColor = NSColor(calibratedRed: 0.018, green: 0.018, blue: 0.028, alpha: 1)

        let floor = SCNFloor()
        floor.reflectivity = 0.18
        floor.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.018, green: 0.018, blue: 0.024, alpha: 1),
            emission: NSColor(calibratedRed: 0.006, green: 0.006, blue: 0.014, alpha: 1)
        )
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)

        let arenaPlane = SCNPlane(width: 18.5, height: 18.5)
        let arenaMaterial = SCNMaterial()
        let arenaTexture = resourceImage("arena-runes")
        arenaMaterial.diffuse.contents = arenaTexture
            ?? NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.045, alpha: 1)
        arenaMaterial.emission.contents = arenaTexture
        arenaMaterial.transparency = arenaTexture == nil ? 0.0 : 0.58
        arenaMaterial.lightingModel = .physicallyBased
        arenaMaterial.roughness.contents = 0.68
        arenaMaterial.metalness.contents = 0.18
        arenaPlane.firstMaterial = arenaMaterial

        let arenaNode = SCNNode(geometry: arenaPlane)
        arenaNode.eulerAngles.x = -.pi / 2
        arenaNode.position.y = 0.018
        scene.rootNode.addChildNode(arenaNode)

        for radius in stride(from: 2.6, through: 10.4, by: 1.7) {
            let ring = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.008)
            ring.firstMaterial = material(
                diffuse: NSColor(calibratedWhite: 0.26, alpha: 0.32),
                emission: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.08, alpha: 0.45)
            )
            let ringNode = SCNNode(geometry: ring)
            ringNode.eulerAngles.x = .pi / 2
            ringNode.position.y = 0.012
            scene.rootNode.addChildNode(ringNode)
        }

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 150
        ambientLight.light?.color = NSColor(calibratedRed: 0.18, green: 0.2, blue: 0.28, alpha: 1)
        scene.rootNode.addChildNode(ambientLight)

        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .spot
        keyLightNode.light?.intensity = 2400
        keyLightNode.light?.spotInnerAngle = 30
        keyLightNode.light?.spotOuterAngle = 82
        keyLightNode.light?.castsShadow = true
        keyLightNode.position = SCNVector3(-6, 9, 7)
        keyLightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyLightNode)

        rimLightNode.light = SCNLight()
        rimLightNode.light?.type = .omni
        rimLightNode.light?.intensity = 760
        rimLightNode.light?.color = NSColor(calibratedRed: 0.22, green: 0.38, blue: 1, alpha: 1)
        rimLightNode.position = SCNVector3(3.4, 3.2, -4.6)
        scene.rootNode.addChildNode(rimLightNode)

        phaseLightNode.light = SCNLight()
        phaseLightNode.light?.type = .omni
        phaseLightNode.light?.intensity = 360
        phaseLightNode.light?.color = NSColor(calibratedRed: 0.42, green: 0.26, blue: 1, alpha: 1)
        phaseLightNode.position = SCNVector3(0, 2.4, 0)
        scene.rootNode.addChildNode(phaseLightNode)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 42
        cameraNode.camera?.zFar = 80
        cameraNode.position = SCNVector3(0, 5.5, 12)
        cameraNode.eulerAngles.x = -0.43
        cameraRig.addChildNode(cameraNode)
        cameraRig.runAction(
            .repeatForever(
                .sequence([
                    .moveBy(x: 0.25, y: 0.08, z: -0.18, duration: 4.2),
                    .moveBy(x: -0.25, y: -0.08, z: 0.18, duration: 4.2)
                ])
            )
        )
        scene.rootNode.addChildNode(cameraRig)
        scene.rootNode.addChildNode(enemyRoot)
        scene.rootNode.addChildNode(effectsRoot)

        buildWizard()
        scene.rootNode.addChildNode(wizardNode)
        let lookAt = SCNLookAtConstraint(target: wizardNode)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]
    }

    private func buildWizard() {
        wizardNode.position = SCNVector3(0, 0, 0)

        let robe = SCNCylinder(radius: 0.36, height: 0.92)
        robe.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
            emission: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.08, alpha: 1)
        )
        let robeNode = SCNNode(geometry: robe)
        robeNode.position.y = 0.54
        wizardNode.addChildNode(robeNode)

        let chest = SCNSphere(radius: 0.31)
        chest.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.47, green: 0.5, blue: 0.54, alpha: 1),
            emission: NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1)
        )
        let chestNode = SCNNode(geometry: chest)
        chestNode.scale = SCNVector3(1, 0.72, 0.78)
        chestNode.position.y = 1.05
        wizardNode.addChildNode(chestNode)

        let head = SCNSphere(radius: 0.22)
        head.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.7, alpha: 1),
            emission: NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.11, alpha: 1)
        )
        let headNode = SCNNode(geometry: head)
        headNode.position.y = 1.45
        wizardNode.addChildNode(headNode)

        let visor = SCNBox(width: 0.28, height: 0.055, length: 0.04, chamferRadius: 0.018)
        visor.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.25, green: 0.84, blue: 1, alpha: 1),
            emission: NSColor(calibratedRed: 0.1, green: 0.62, blue: 1, alpha: 1)
        )
        let visorNode = SCNNode(geometry: visor)
        visorNode.position = SCNVector3(0, 1.47, 0.195)
        wizardNode.addChildNode(visorNode)

        let hat = SCNCone(topRadius: 0.03, bottomRadius: 0.28, height: 0.55)
        hat.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.24, alpha: 1),
            emission: NSColor(calibratedRed: 0.05, green: 0.02, blue: 0.12, alpha: 1)
        )
        let hatNode = SCNNode(geometry: hat)
        hatNode.position.y = 1.78
        wizardNode.addChildNode(hatNode)

        let staff = SCNCylinder(radius: 0.035, height: 1.52)
        staff.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.44, green: 0.4, blue: 0.34, alpha: 1),
            emission: NSColor(calibratedRed: 0.04, green: 0.03, blue: 0.02, alpha: 1)
        )
        let staffNode = SCNNode(geometry: staff)
        staffNode.position = SCNVector3(0.56, 0.92, 0.05)
        staffNode.eulerAngles.z = 0.18
        wizardNode.addChildNode(staffNode)

        let orb = SCNSphere(radius: 0.13)
        orb.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.2, green: 0.68, blue: 1, alpha: 1),
            emission: NSColor(calibratedRed: 0.12, green: 0.48, blue: 1, alpha: 1)
        )
        staffOrbNode.geometry = orb
        staffOrbNode.position = SCNVector3(0.7, 1.68, 0.08)
        wizardNode.addChildNode(staffOrbNode)

        let idle = SCNAction.repeatForever(
            .sequence([
                .moveBy(x: 0, y: 0.08, z: 0, duration: 1.1),
                .moveBy(x: 0, y: -0.08, z: 0, duration: 1.1)
            ])
        )
        wizardNode.runAction(idle, forKey: "idle")

        let orbPulse = SCNAction.repeatForever(
            .sequence([
                .scale(to: 1.18, duration: 0.55),
                .scale(to: 0.92, duration: 0.55)
            ])
        )
        staffOrbNode.runAction(orbPulse, forKey: "pulse")
    }

    private func apply(_ line: LiveLine) {
        let spell = SpellSchool(line: line)

        if line.status == .running {
            if line.kind == .command || line.kind == .fileChange {
                stageCamera(.castPrep)
                chargeArena(color: spell.nsColor)
                spawnEnemy(for: line.id, spell: spell, persistent: true)
            } else if line.kind == .lifecycle {
                stageCamera(.wide)
                portalPulse(color: spell.nsColor)
            }
            return
        }

        if line.status == .completed || line.status == .failed {
            if line.kind == .command || line.kind == .fileChange || line.status == .failed {
                stageCamera(line.status == .failed ? .failure : .impact)
                castVolley(spell: spell, failed: line.status == .failed)
            } else if line.kind == .agentMessage {
                stageCamera(.overhead)
                insightPulse(color: spell.nsColor)
            } else if line.kind == .lifecycle {
                stageCamera(.wide)
                portalPulse(color: spell.nsColor)
            }
            return
        }

        if line.level == .error {
            stageCamera(.failure)
            shakeCamera()
            insightPulse(color: SpellSchool.failure.nsColor)
        }
    }

    private func syncRunningEnemies(with lines: [LiveLine]) {
        for line in lines where (line.kind == .command || line.kind == .fileChange) && line.status == .running {
            if activeEnemies[line.id] == nil {
                spawnEnemy(for: line.id, spell: SpellSchool(line: line), persistent: true)
            }
        }
    }

    private func isWaitingForCodex(lines: [LiveLine]) -> Bool {
        !lines.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private func setThinking(_ active: Bool) {
        guard active != isThinking else { return }
        isThinking = active

        if active {
            stageCamera(.wide)
            startKiting()
            thinkingTimer?.invalidate()
            thinkingTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
                self?.spawnAmbientEnemy()
            }
            spawnAmbientEnemy()
            startSkirmishCasting()
        } else {
            thinkingTimer?.invalidate()
            thinkingTimer = nil
            stopSkirmishCasting()
            stopKiting()
            stageCamera(.home)
        }
    }

    private func startSkirmishCasting() {
        skirmishTimer?.invalidate()
        skirmishTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.skirmishShot()
        }
        skirmishTimer?.tolerance = 0.04
        skirmishShot()
    }

    private func stopSkirmishCasting() {
        skirmishTimer?.invalidate()
        skirmishTimer = nil
    }

    private func startKiting() {
        guard wizardNode.action(forKey: "kite") == nil else { return }
        let path: [SCNVector3] = [
            SCNVector3(-1.4, 0, 0.6),
            SCNVector3(-0.2, 0, -1.0),
            SCNVector3(1.35, 0, -0.2),
            SCNVector3(0.45, 0, 1.1),
            SCNVector3(0, 0, 0)
        ]
        let moves = path.map { SCNAction.move(to: $0, duration: 1.05) }
        moves.forEach { $0.timingMode = .easeInEaseOut }
        wizardNode.runAction(.repeatForever(.sequence(moves)), forKey: "kite")
    }

    private func stopKiting() {
        wizardNode.removeAction(forKey: "kite")
        let settle = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 0.55)
        settle.timingMode = .easeInEaseOut
        wizardNode.runAction(settle, forKey: "settle")
    }

    private func chargeArena(color: NSColor) {
        arenaRing(radius: 1.1, color: color, duration: 0.55, scale: 5.8, opacity: 0.72)
        arenaRing(radius: 2.4, color: color.withAlphaComponent(0.8), duration: 0.85, scale: 2.7, opacity: 0.46)
        pulsePhaseLight(color: color, intensity: 880, duration: 0.42)
    }

    private func sealArena(color: NSColor) {
        for (index, radius) in [0.9, 1.8, 3.0, 4.4].enumerated() {
            let ringColor = color.withAlphaComponent(0.9 - CGFloat(index) * 0.12)
            arenaRing(
                radius: CGFloat(radius),
                color: ringColor,
                duration: 0.85 + Double(index) * 0.12,
                scale: 1.9,
                opacity: 0.7
            )
        }
        sparkBurst(at: SCNVector3(0, 0.5, 0), color: color, birthRate: 1200)
        pulsePhaseLight(color: color, intensity: 1200, duration: 0.8)
    }

    private func victorySurge() {
        stageCamera(.victory)
        nextAmbientSpawnDate = Date().addingTimeInterval(2.2)
        if !enemyRoot.childNodes.isEmpty {
            castVolley(spell: .verify, failed: false)
        }
        for radius in stride(from: 0.9, through: 7.6, by: 1.1) {
            arenaRing(
                radius: CGFloat(radius),
                color: SpellSchool.verify.nsColor.withAlphaComponent(0.7),
                duration: 1.1,
                scale: 1.35,
                opacity: 0.54
            )
        }
        portalPulse(color: SpellSchool.verify.nsColor)
        sparkBurst(at: SCNVector3(0, 1.3, -0.4), color: SpellSchool.verify.nsColor, birthRate: 1600)
        pulsePhaseLight(color: SpellSchool.verify.nsColor, intensity: 1500, duration: 1.0)
    }

    private func forgeSparks(color: NSColor) {
        for offset in [
            SCNVector3(-1.2, 0.45, 0.8),
            SCNVector3(1.15, 0.45, 0.55),
            SCNVector3(0.2, 0.45, -1.2)
        ] {
            sparkBurst(at: offset, color: color, birthRate: 620)
        }
    }

    private func historyChains(color: NSColor) {
        let points = [
            (SCNVector3(-3.8, 0.18, -1.8), SCNVector3(3.6, 0.18, 1.6)),
            (SCNVector3(-3.2, 0.24, 2.0), SCNVector3(3.3, 0.24, -1.6)),
            (SCNVector3(0, 0.26, -4.2), SCNVector3(0, 0.26, 4.2))
        ]
        for pair in points {
            spellTrail(from: pair.0, to: pair.1, spell: .git)
        }
        arenaRing(radius: 4.0, color: color, duration: 0.95, scale: 1.45, opacity: 0.58)
    }

    private func arenaRing(radius: CGFloat, color: NSColor, duration: TimeInterval, scale: CGFloat, opacity: CGFloat) {
        let ring = SCNTorus(ringRadius: radius, pipeRadius: 0.018)
        ring.firstMaterial = material(diffuse: color, emission: color)
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = 0.055
        ringNode.opacity = opacity
        ringNode.eulerAngles.x = .pi / 2
        effectsRoot.addChildNode(ringNode)
        ringNode.runAction(
            .sequence([
                .group([
                    .scale(to: scale, duration: duration),
                    .fadeOut(duration: duration)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func pulsePhaseLight(color: NSColor, intensity: CGFloat, duration: TimeInterval) {
        phaseLightNode.light?.color = color
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        phaseLightNode.light?.intensity = intensity
        SCNTransaction.completionBlock = { [weak self] in
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            self?.phaseLightNode.light?.intensity = 360
            SCNTransaction.commit()
        }
        SCNTransaction.commit()
    }

    private func spellTrail(from start: SCNVector3, to end: SCNVector3, spell: SpellSchool) {
        let steps = spell == .scan ? 11 : 7
        let baseRadius: CGFloat = spell == .verify ? 0.08 : 0.052
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(max(steps, 1))
            let point = interpolate(start, end, t: t)
            let geometry: SCNGeometry = spell == .verify
                ? SCNTorus(ringRadius: 0.12, pipeRadius: 0.012)
                : SCNSphere(radius: baseRadius)
            geometry.firstMaterial = material(diffuse: spell.nsColor, emission: spell.nsColor)
            let node = SCNNode(geometry: geometry)
            node.position = point
            node.opacity = 0.82
            effectsRoot.addChildNode(node)
            node.runAction(
                .sequence([
                    .wait(duration: Double(index) * 0.025),
                    .group([
                        .scale(to: spell == .scan ? 1.9 : 2.6, duration: 0.34),
                        .fadeOut(duration: 0.34)
                    ]),
                    .removeFromParentNode()
                ])
            )
        }
    }

    private func sparkBurst(at position: SCNVector3, color: NSColor, birthRate: CGFloat) {
        let particles = SCNParticleSystem()
        particles.loops = false
        particles.birthRate = birthRate
        particles.emissionDuration = 0.08
        particles.particleLifeSpan = 0.58
        particles.particleLifeSpanVariation = 0.22
        particles.particleVelocity = 2.2
        particles.particleVelocityVariation = 1.6
        particles.particleSize = 0.055
        particles.particleSizeVariation = 0.035
        particles.spreadingAngle = 180
        particles.isAffectedByGravity = false
        particles.blendMode = .additive
        particles.particleColor = color
        particles.emitterShape = SCNSphere(radius: 0.08)

        let node = SCNNode()
        node.position = position
        node.addParticleSystem(particles)
        effectsRoot.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 1.2), .removeFromParentNode()]))
    }

    private func interpolate(_ start: SCNVector3, _ end: SCNVector3, t: CGFloat) -> SCNVector3 {
        let x = start.x + (end.x - start.x) * t
        let y = start.y + (end.y - start.y) * t
        let z = start.z + (end.z - start.z) * t
        return SCNVector3(x, y, z)
    }

    private func skirmishShot() {
        var targets = livingEnemies()
        if targets.isEmpty {
            spawnAmbientEnemy()
            targets = livingEnemies()
        }
        guard let target = closestEnemy(in: targets) else { return }

        let spell = SpellSchool.pressure
        let startPosition = staffOrbNode.presentation.convertPosition(SCNVector3Zero, to: nil)
        let targetPosition = target.presentation.position

        let projectileGeometry = SCNSphere(radius: 0.055)
        projectileGeometry.firstMaterial = material(diffuse: spell.nsColor, emission: spell.nsColor)
        let projectile = SCNNode(geometry: projectileGeometry)
        projectile.position = startPosition
        effectsRoot.addChildNode(projectile)

        let move = SCNAction.move(to: targetPosition, duration: 0.18)
        move.timingMode = .easeOut
        projectile.runAction(.sequence([move, .removeFromParentNode()]))
        spellTrail(from: startPosition, to: targetPosition, spell: spell)

        target.runAction(
            .sequence([
                .wait(duration: 0.16),
                .run { [weak self, weak target] _ in
                    guard let self, let target else { return }
                    self.applySkirmishDamage(to: target, at: targetPosition)
                }
            ])
        )

        staffOrbNode.runAction(
            .sequence([
                .scale(to: 1.22, duration: 0.08),
                .scale(to: 1.0, duration: 0.12)
            ]),
            forKey: "skirmishPulse"
        )
    }

    private func applySkirmishDamage(to enemy: SCNNode, at position: SCNVector3) {
        let id = ObjectIdentifier(enemy)
        let remaining = max((enemyHealth[id] ?? 1.0) - 0.25, 0)
        enemyHealth[id] = remaining
        chipImpact(at: position, color: SpellSchool.pressure.nsColor)

        if remaining <= 0 {
            destroyEnemy(enemy, color: SpellSchool.pressure.nsColor, failed: false)
        } else {
            let scale = 0.78 + (remaining * 0.22)
            let recoil = SCNAction.sequence([
                .group([
                    .scale(to: scale, duration: 0.08),
                    .moveBy(x: 0, y: 0.08, z: 0, duration: 0.08)
                ]),
                .group([
                    .scale(to: max(scale, 0.82), duration: 0.16),
                    .moveBy(x: 0, y: -0.08, z: 0, duration: 0.16)
                ])
            ])
            enemy.runAction(recoil, forKey: "hit-react")
        }
    }

    private func destroyEnemy(_ enemy: SCNNode, color: NSColor, failed: Bool) {
        enemyHealth[ObjectIdentifier(enemy)] = nil
        enemy.name = "dyingEnemy"
        enemy.removeAllActions()
        enemy.runAction(
            .sequence([
                .run { [weak self] _ in
                    self?.impact(at: enemy.presentation.position, color: color, failed: failed)
                    if failed {
                        self?.shakeCamera()
                    }
                },
                .group([
                    .scale(to: failed ? 1.18 : 0.08, duration: failed ? 0.22 : 0.28),
                    .fadeOut(duration: failed ? 0.22 : 0.28)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func livingEnemies() -> [SCNNode] {
        let nodes = enemyRoot.childNodes.filter { node in
            node.parent != nil && node.name != "dyingEnemy"
        }
        let ids = Set(nodes.map { ObjectIdentifier($0) })
        enemyHealth = enemyHealth.filter { ids.contains($0.key) }
        for node in nodes where enemyHealth[ObjectIdentifier(node)] == nil {
            enemyHealth[ObjectIdentifier(node)] = 1.0
        }
        return nodes
    }

    private func closestEnemy(in enemies: [SCNNode]) -> SCNNode? {
        let wizardPosition = wizardNode.presentation.position
        return enemies.min {
            distanceSquared($0.presentation.position, wizardPosition) < distanceSquared($1.presentation.position, wizardPosition)
        }
    }

    private func distanceSquared(_ lhs: SCNVector3, _ rhs: SCNVector3) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        let dz = lhs.z - rhs.z
        return dx * dx + dy * dy + dz * dz
    }

    private func chipImpact(at position: SCNVector3, color: NSColor) {
        let flare = SCNSphere(radius: 0.11)
        flare.firstMaterial = material(diffuse: color, emission: color)
        let flareNode = SCNNode(geometry: flare)
        flareNode.position = position
        effectsRoot.addChildNode(flareNode)
        flareNode.runAction(
            .sequence([
                .group([
                    .scale(to: 1.8, duration: 0.18),
                    .fadeOut(duration: 0.18)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    @discardableResult
    private func spawnEnemy(for id: UUID?, spell: SpellSchool, persistent: Bool) -> SCNNode {
        if let id, let existing = activeEnemies[id] {
            enemyHealth[ObjectIdentifier(existing)] = enemyHealth[ObjectIdentifier(existing)] ?? 1.0
            return existing
        }

        ambientSpawnIndex += 1
        let angle = (Float(ambientSpawnIndex) * 1.77).truncatingRemainder(dividingBy: Float.pi * 2)
        let radius = Float.random(in: 7.0...10.5)
        let node = makeEnemy(spell: spell)
        node.position = SCNVector3(cos(angle) * radius, 0.45, sin(angle) * radius)
        node.name = persistent ? "activeEnemy" : "ambientEnemy"
        enemyRoot.addChildNode(node)
        enemyHealth[ObjectIdentifier(node)] = 1.0

        let destination = SCNVector3(Float.random(in: -1.7...1.7), 0.45, Float.random(in: -1.2...1.8))
        let approach = SCNAction.move(to: destination, duration: persistent ? 13.5 : 7.5)
        approach.timingMode = .easeInEaseOut
        node.runAction(approach, forKey: "approach")

        if let id {
            activeEnemies[id] = node
        }

        return node
    }

    private func spawnAmbientEnemy() {
        guard Date() >= nextAmbientSpawnDate else { return }
        let ambientEnemies = enemyRoot.childNodes.filter { $0.name == "ambientEnemy" }
        guard ambientEnemies.count < 8 else { return }
        _ = spawnEnemy(for: nil, spell: .pressure, persistent: false)
    }

    private func makeEnemy(spell: SpellSchool) -> SCNNode {
        let root = SCNNode()

        let body = SCNSphere(radius: 0.34)
        body.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.12, green: 0.105, blue: 0.12, alpha: 1),
            emission: spell.enemyGlow
        )
        let bodyNode = SCNNode(geometry: body)
        bodyNode.scale = SCNVector3(1, 1.25, 0.82)
        root.addChildNode(bodyNode)

        let eye = SCNBox(width: 0.24, height: 0.055, length: 0.045, chamferRadius: 0.015)
        eye.firstMaterial = material(diffuse: spell.nsColor, emission: spell.nsColor)
        let eyeNode = SCNNode(geometry: eye)
        eyeNode.position = SCNVector3(0, 0.08, 0.29)
        root.addChildNode(eyeNode)

        let crown = SCNCone(topRadius: 0, bottomRadius: 0.18, height: 0.28)
        crown.firstMaterial = material(
            diffuse: NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.18, alpha: 1),
            emission: spell.enemyGlow.withAlphaComponent(0.45)
        )
        let crownNode = SCNNode(geometry: crown)
        crownNode.position.y = 0.42
        root.addChildNode(crownNode)

        let aura = SCNTorus(ringRadius: 0.46, pipeRadius: 0.012)
        aura.firstMaterial = material(
            diffuse: spell.nsColor.withAlphaComponent(0.55),
            emission: spell.enemyGlow
        )
        let auraNode = SCNNode(geometry: aura)
        auraNode.position.y = -0.43
        auraNode.eulerAngles.x = .pi / 2
        root.addChildNode(auraNode)
        auraNode.runAction(
            .repeatForever(
                .sequence([
                    .scale(to: 1.18, duration: 0.75),
                    .scale(to: 0.92, duration: 0.75)
                ])
            )
        )

        root.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 3.2)))
        return root
    }

    private func castVolley(spell: SpellSchool, failed: Bool) {
        var targets = livingEnemies()
        if targets.isEmpty {
            targets = [spawnEnemy(for: nil, spell: spell, persistent: false)]
        }

        activeEnemies.removeAll()
        nextAmbientSpawnDate = Date().addingTimeInterval(1.4)
        targets.forEach { $0.removeAction(forKey: "approach") }

        for target in targets {
            cast(spell: spell, at: target, failed: failed)
        }

        if !failed {
            switch spell {
            case .verify:
                sealArena(color: spell.nsColor)
            case .edit:
                forgeSparks(color: spell.nsColor)
            case .git:
                historyChains(color: spell.nsColor)
            default:
                break
            }
        }
    }

    private func cast(spell: SpellSchool, at enemy: SCNNode, failed: Bool) {
        let targetPosition = enemy.presentation.position
        let startPosition = staffOrbNode.presentation.convertPosition(SCNVector3Zero, to: nil)
        enemyHealth[ObjectIdentifier(enemy)] = nil
        enemy.name = "dyingEnemy"

        let projectileGeometry = SCNSphere(radius: failed ? 0.11 : 0.085)
        projectileGeometry.firstMaterial = material(diffuse: spell.nsColor, emission: spell.nsColor)
        let projectile = SCNNode(geometry: projectileGeometry)
        projectile.position = startPosition
        effectsRoot.addChildNode(projectile)
        spellTrail(from: startPosition, to: targetPosition, spell: spell)

        let move = SCNAction.move(to: targetPosition, duration: 0.38)
        move.timingMode = .easeIn
        projectile.runAction(.sequence([move, .removeFromParentNode()]))

        enemy.removeAllActions()
        enemy.runAction(
            .sequence([
                .wait(duration: 0.34),
                .run { [weak self] _ in
                    self?.impact(at: targetPosition, color: spell.nsColor, failed: failed)
                    if failed {
                        self?.shakeCamera()
                    }
                },
                .group([
                    .scale(to: failed ? 1.18 : 0.08, duration: failed ? 0.22 : 0.32),
                    .fadeOut(duration: failed ? 0.22 : 0.32)
                ]),
                .removeFromParentNode()
            ])
        )

        staffOrbNode.runAction(
            .sequence([
                .scale(to: 1.42, duration: 0.14),
                .scale(to: 1.0, duration: 0.2)
            ]),
            forKey: "castPulse"
        )
    }

    private func impact(at position: SCNVector3, color: NSColor, failed: Bool) {
        let ring = SCNTorus(ringRadius: failed ? 0.18 : 0.12, pipeRadius: 0.018)
        ring.firstMaterial = material(diffuse: color, emission: color)
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = position
        ringNode.eulerAngles.x = .pi / 2
        effectsRoot.addChildNode(ringNode)
        ringNode.runAction(
            .sequence([
                .group([
                    .scale(to: failed ? 5.2 : 3.4, duration: failed ? 0.5 : 0.62),
                    .fadeOut(duration: failed ? 0.5 : 0.62)
                ]),
                .removeFromParentNode()
            ])
        )

        let flare = SCNSphere(radius: failed ? 0.28 : 0.2)
        flare.firstMaterial = material(diffuse: color, emission: color)
        let flareNode = SCNNode(geometry: flare)
        flareNode.position = position
        effectsRoot.addChildNode(flareNode)
        flareNode.runAction(
            .sequence([
                .group([
                    .scale(to: failed ? 2.2 : 1.55, duration: 0.34),
                    .fadeOut(duration: 0.34)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func insightPulse(color: NSColor) {
        let rune = SCNTorus(ringRadius: 0.8, pipeRadius: 0.018)
        rune.firstMaterial = material(diffuse: color, emission: color)
        let runeNode = SCNNode(geometry: rune)
        runeNode.position = SCNVector3(0, 1.9, 0)
        runeNode.eulerAngles.x = .pi / 2
        effectsRoot.addChildNode(runeNode)
        runeNode.runAction(
            .sequence([
                .group([
                    .rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 1.2),
                    .scale(to: 1.8, duration: 1.2),
                    .fadeOut(duration: 1.2)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func portalPulse(color: NSColor) {
        let portal = SCNTorus(ringRadius: 1.05, pipeRadius: 0.025)
        portal.firstMaterial = material(diffuse: color, emission: color)
        let portalNode = SCNNode(geometry: portal)
        portalNode.position = SCNVector3(0, 1.45, -3.2)
        effectsRoot.addChildNode(portalNode)
        portalNode.runAction(
            .sequence([
                .group([
                    .rotateBy(x: 0, y: 0, z: CGFloat.pi * 2, duration: 1.1),
                    .scale(to: 1.65, duration: 1.1),
                    .fadeOut(duration: 1.1)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func shakeCamera() {
        cameraRig.removeAction(forKey: "shake")
        cameraRig.runAction(
            .sequence([
                .moveBy(x: 0.18, y: 0.04, z: 0, duration: 0.06),
                .moveBy(x: -0.34, y: -0.07, z: 0, duration: 0.08),
                .moveBy(x: 0.16, y: 0.03, z: 0, duration: 0.06)
            ]),
            forKey: "shake"
        )
    }

    private func material(diffuse: NSColor, emission: NSColor? = nil) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = diffuse
        material.emission.contents = emission ?? NSColor.black
        material.specular.contents = NSColor.white.withAlphaComponent(0.18)
        material.shininess = 0.45
        return material
    }
}

private enum SpellSchool: Equatable {
    case scan
    case shell
    case edit
    case git
    case verify
    case insight
    case lifecycle
    case pressure
    case failure

    init(line: LiveLine) {
        if line.status == .failed || line.level == .error {
            self = .failure
            return
        }

        switch line.kind {
        case .command:
            self = SpellSchool.command(line.detail ?? line.text)
        case .fileChange:
            self = .edit
        case .agentMessage:
            self = .insight
        case .lifecycle:
            self = .lifecycle
        case .message:
            self = .shell
        }
    }

    var name: String {
        switch self {
        case .scan: return "Search spell"
        case .shell: return "Shell spell"
        case .edit: return "Forge spell"
        case .git: return "History spell"
        case .verify: return "Seal spell"
        case .insight: return "Insight spell"
        case .lifecycle: return "Gate spell"
        case .pressure: return "Pressure"
        case .failure: return "Backlash"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .shell: return "terminal"
        case .edit: return "hammer"
        case .git: return "point.3.connected.trianglepath.dotted"
        case .verify: return "checkmark.seal"
        case .insight: return "sparkles"
        case .lifecycle: return "circle.hexagongrid"
        case .pressure: return "flame"
        case .failure: return "exclamationmark.triangle"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .scan:
            return NSColor(calibratedRed: 0.18, green: 0.64, blue: 1.0, alpha: 1)
        case .shell:
            return NSColor(calibratedRed: 0.58, green: 0.44, blue: 1.0, alpha: 1)
        case .edit:
            return NSColor(calibratedRed: 0.15, green: 0.96, blue: 0.72, alpha: 1)
        case .git:
            return NSColor(calibratedRed: 0.46, green: 0.95, blue: 0.3, alpha: 1)
        case .verify:
            return NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.2, alpha: 1)
        case .insight:
            return NSColor(calibratedRed: 0.86, green: 0.52, blue: 1.0, alpha: 1)
        case .lifecycle:
            return NSColor(calibratedRed: 0.32, green: 0.84, blue: 1.0, alpha: 1)
        case .pressure:
            return NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.18, alpha: 1)
        case .failure:
            return NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.18, alpha: 1)
        }
    }

    var swiftUIColor: Color {
        Color(nsColor)
    }

    var enemyGlow: NSColor {
        nsColor.withAlphaComponent(0.38)
    }

    private static func command(_ detail: String) -> SpellSchool {
        let lowercased = detail.lowercased()
        if lowercased.contains("swift test")
            || lowercased.contains("swift build")
            || lowercased.contains("npm test")
            || lowercased.contains("pytest")
            || lowercased.contains("cargo test")
            || lowercased.contains("verify") {
            return .verify
        }
        if lowercased.contains("git ") {
            return .git
        }
        if lowercased.contains("rg ")
            || lowercased.contains("grep")
            || lowercased.contains("find ")
            || lowercased.contains("ls ")
            || lowercased.contains("sed ")
            || lowercased.contains("cat ") {
            return .scan
        }
        return .shell
    }
}
