import AppKit
import Metal
import RealityKit
import SwiftUI

struct CinematicSceneView: View {
    var projectID: UUID
    var lines: [LiveLine]
    var phase: LoopPhase
    var isActive: Bool
    var languageProfile: RepositoryLanguageProfile
    var activityProfile: RepositoryActivityProfile
    var influenceSettings: CinematicInfluenceSettings

    @StateObject private var host: CinematicRealitySceneHost

    init(
        projectID: UUID,
        lines: [LiveLine],
        phase: LoopPhase,
        isActive: Bool,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) {
        self.projectID = projectID
        self.lines = lines
        self.phase = phase
        self.isActive = isActive
        self.languageProfile = languageProfile
        self.activityProfile = activityProfile
        self.influenceSettings = influenceSettings
        _host = StateObject(wrappedValue: CinematicRealitySceneHost(projectID: projectID))
    }

    var body: some View {
        RealityView { content in
            host.install(in: &content)
            host.update(
                lines: lines,
                phase: phase,
                isActive: isActive,
                languageProfile: languageProfile,
                activityProfile: activityProfile,
                influenceSettings: influenceSettings
            )
        } update: { content in
            host.install(in: &content)
            host.update(
                lines: lines,
                phase: phase,
                isActive: isActive,
                languageProfile: languageProfile,
                activityProfile: activityProfile,
                influenceSettings: influenceSettings
            )
        } placeholder: {
            Color.black
        }
        .background(Color.black)
        .onDisappear {
            host.release()
        }
    }
}

@MainActor
private final class CinematicRealitySceneHost: ObservableObject {
    private let projectID: UUID
    private let coordinator: CinematicSceneCoordinator
    private var retained = true

    init(projectID: UUID) {
        self.projectID = projectID
        coordinator = CinematicSceneCache.shared.coordinator(for: projectID)
    }

    deinit {
        if retained {
            let projectID = projectID
            Task { @MainActor in
                CinematicSceneCache.shared.release(projectID)
            }
        }
    }

    func install(in content: inout RealityViewCameraContent) {
        coordinator.install(in: &content)
    }

    func update(
        lines: [LiveLine],
        phase: LoopPhase,
        isActive: Bool,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) {
        coordinator.update(
            lines: lines,
            phase: phase,
            isActive: isActive,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
    }

    func release() {
        guard retained else { return }
        retained = false
        CinematicSceneCache.shared.release(projectID)
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

private enum DefensiveSpell {
    case slow
    case stun
    case wall

    var school: SpellSchool {
        switch self {
        case .slow:
            return .scan
        case .stun:
            return .verify
        case .wall:
            return .lifecycle
        }
    }

    var color: NSColor {
        school.nsColor
    }
}

@MainActor
private final class CinematicSceneCoordinator {
    let projectID: UUID

    private let root = Entity()
    private let cameraEntity = Entity()
    private let wizardNode = Entity()
    private let headNode = Entity()
    private let hatNode = Entity()
    private let leftArmNode = Entity()
    private let rightArmNode = Entity()
    private let staffPivotNode = Entity()
    private let staffOrbNode = Entity()
    private let enemyRoot = Entity()
    private let effectsRoot = Entity()
    private let setDressingRoot = Entity()
    private let languageSigilRoot = Entity()
    private let activitySigilRoot = Entity()
    private let keyLightNode = Entity()
    private let rimLightNode = Entity()
    private let phaseLightNode = Entity()

    private var activeEnemies: [UUID: Entity] = [:]
    private var lineStatuses: [UUID: LiveLine.Status] = [:]
    private var hasBuiltScene = false
    private var hasBootstrapped = false
    private var isInstalled = false
    private var languageProfile = RepositoryLanguageProfile.empty
    private var languageMotif = CinematicMotif.language(for: RepositoryLanguageProfile.empty)
    private var activityProfile = RepositoryActivityProfile.empty
    private var activityMotif = CinematicMotif.activity(for: RepositoryActivityProfile.empty)
    private var influenceSettings = CinematicInfluenceSettings()
    private var lastPhase: LoopPhase = .idle
    private var thinkingTimer: Timer?
    private var defenseTimer: Timer?
    private var displayTimer: Timer?
    private var lastTickDate = Date()
    private var elapsedTime: TimeInterval = 0
    private var isThinking = false
    private var ambientSpawnIndex = 0
    private var defensiveCastIndex = 0
    private var nextAmbientSpawnDate = Date.distantPast
    private var enemyHealth: [ObjectIdentifier: Float] = [:]
    private var slowedEnemies: [ObjectIdentifier: Date] = [:]
    private var stunnedEnemies: [ObjectIdentifier: Date] = [:]
    private var setDressingBaseHeights: [ObjectIdentifier: Float] = [:]
    private var animations: [EntityAnimation] = []
    private var cameraAnimation: CameraAnimation?
    private var currentCameraShot = CinematicCameraShot.home
    private var cameraPosition = CinematicCameraShot.home.position
    private var cameraFieldOfView = CinematicCameraShot.home.fieldOfView
    private var wizardFacingTarget: SIMD3<Float>?
    private var wizardFacingUntil = Date.distantPast
    private var followCameraTarget: SIMD3<Float>?
    private var followCameraUntil = Date.distantPast
    private var shakeUntil = Date.distantPast
    private var staffOrbBoost: Float = 0
    private let staffIdleOrientation = simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 0, 1))
    private let leftArmIdleOrientation = simd_quatf(angle: 0.44, axis: SIMD3<Float>(0, 0, 1))
    private let rightArmIdleOrientation = simd_quatf(angle: -0.34, axis: SIMD3<Float>(0, 0, 1))

    init(projectID: UUID) {
        self.projectID = projectID
    }

    func install(in content: inout RealityViewCameraContent) {
        if !hasBuiltScene {
            hasBuiltScene = true
            buildScene()
        }

        var entities = content.entities
        entities.removeAll()
        entities.append(contentsOf: [root, cameraEntity])
        content.entities = entities
        content.camera = .virtual
        content.cameraTarget = wizardNode

        var effects = content.renderingEffects
        effects.antialiasing = .multisample4X
        effects.depthOfField = .enabled
        effects.cameraGrain = .disabled
        content.renderingEffects = effects

        isInstalled = true
        startDisplayTimer()
    }

    func update(
        lines: [LiveLine],
        phase: LoopPhase,
        isActive: Bool,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) {
        let languageProfileChanged = languageProfile != self.languageProfile
        if languageProfileChanged {
            self.languageProfile = languageProfile
            languageMotif = CinematicMotif.language(for: languageProfile)
        }
        let activityProfileChanged = activityProfile != self.activityProfile
        if activityProfileChanged {
            self.activityProfile = activityProfile
            activityMotif = CinematicMotif.activity(for: activityProfile)
        }
        let influenceChanged = influenceSettings != self.influenceSettings
        if influenceChanged {
            self.influenceSettings = influenceSettings
        }

        if !hasBootstrapped {
            hasBootstrapped = true
            lastPhase = phase
            lineStatuses = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.status) })
            syncRunningEnemies(with: lines)
            setThinking(isActive && isWaitingForCodex(lines: lines))
            if languageProfileChanged {
                applyLanguageTheme(animated: hasBuiltScene)
            }
            if activityProfileChanged {
                applyActivityTraits(animated: false)
            }
            if influenceChanged {
                applyCinematicInfluenceChange()
            }
            return
        }

        if languageProfileChanged {
            applyLanguageTheme(animated: hasBuiltScene)
        }
        if activityProfileChanged {
            applyActivityTraits(animated: hasBuiltScene)
            if isThinking {
                startThinkingTimer(spawnImmediately: false)
            }
        }
        if influenceChanged {
            applyCinematicInfluenceChange()
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
        defenseTimer?.invalidate()
        defenseTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func buildScene() {
        root.name = "cinematic-root"
        enemyRoot.name = "enemy-root"
        effectsRoot.name = "effects-root"
        setDressingRoot.name = "set-dressing-root"

        buildBackdrop()
        buildArena()
        buildSetDressing()
        buildLights()
        buildCamera()
        buildWizard()

        root.addChild(wizardNode)
        root.addChild(enemyRoot)
        root.addChild(effectsRoot)
        root.addChild(setDressingRoot)
        stageCamera(.home, animated: false)
    }

    private func buildBackdrop() {
        let fallback = glowMaterial(NSColor(calibratedRed: 0.006, green: 0.006, blue: 0.01, alpha: 1))
        let backdrop = ModelEntity(
            mesh: curvedWallMesh(radius: 31, height: 21, arc: 2.55),
            materials: [
                textureMaterial(
                    "void-arches-v2",
                    tint: NSColor(calibratedWhite: 0.52, alpha: 1)
                ) ?? fallback
            ]
        )
        backdrop.name = "void-cyclorama"
        root.addChild(backdrop)

        let horizonHaze = ModelEntity(
            mesh: curvedWallMesh(radius: 30.5, height: 6.2, arc: 2.62, bottomY: -0.08),
            materials: [
                glowMaterial(
                    NSColor(calibratedRed: 0.002, green: 0.002, blue: 0.006, alpha: 1),
                    opacity: 0.68
                )
            ]
        )
        horizonHaze.name = "horizon-haze"
        root.addChild(horizonHaze)
    }

    private func buildArena() {
        let floor = ModelEntity(
            mesh: .generatePlane(width: 128, depth: 128),
            materials: [obsidianFloorMaterial()]
        )
        floor.name = "void-floor"
        floor.position.y = -0.012
        root.addChild(floor)

        let arenaFallback = glowMaterial(
            NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.052, alpha: 1),
            opacity: 0.48
        )
        let arena = ModelEntity(
            mesh: circularPlaneMesh(radius: 9.55),
            materials: [
                textureMaterial(
                    "arena-runes-v3",
                    tint: NSColor(calibratedWhite: 0.82, alpha: 1),
                    opacity: 0.9
                ) ?? arenaFallback
            ]
        )
        arena.name = "arena-runes-v3"
        arena.position.y = 0.032
        root.addChild(arena)

        let falloffBands: [(inner: Float, outer: Float, opacity: Float)] = [
            (10.6, 18, 0.12),
            (18, 34, 0.25),
            (34, 62, 0.42)
        ]
        for (index, band) in falloffBands.enumerated() {
            let falloff = ModelEntity(
                mesh: annulusMesh(innerRadius: band.inner, outerRadius: band.outer),
                materials: [
                    glowMaterial(
                        NSColor(calibratedRed: 0.001, green: 0.001, blue: 0.004, alpha: 1),
                        opacity: band.opacity
                    )
                ]
            )
            falloff.name = "floor-falloff-\(index)"
            falloff.position.y = 0.018 + Float(index) * 0.002
            root.addChild(falloff)
        }

        for radius in stride(from: Float(2.6), through: Float(10.4), by: Float(1.7)) {
            let ring = ModelEntity(
                mesh: torusMesh(ringRadius: radius, pipeRadius: 0.008),
                materials: [
                    material(
                        diffuse: NSColor(calibratedWhite: 0.26, alpha: 0.32),
                        emission: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.08, alpha: 0.45),
                        opacity: 0.42
                    )
                ]
            )
            ring.position.y = 0.052
            ring.components.set(OpacityComponent(opacity: 0.42))
            root.addChild(ring)
        }

        let distantRings: [(Float, Float)] = [
            (14.2, 0.16),
            (21.8, 0.1),
            (31.5, 0.06)
        ]
        for (radius, opacity) in distantRings {
            let ring = ModelEntity(
                mesh: torusMesh(ringRadius: radius, pipeRadius: 0.01),
                materials: [
                    glowMaterial(
                        NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.42, alpha: 1),
                        opacity: opacity
                    )
                ]
            )
            ring.name = "distant-arena-ring"
            ring.position.y = 0.055
            root.addChild(ring)
        }
    }

    private func buildSetDressing() {
        let pedestalPositions: [SIMD3<Float>] = [
            [-7.7, 0, -6.3],
            [7.7, 0, -6.3],
            [-8.5, 0, 2.8],
            [8.5, 0, 2.8]
        ]

        for (index, position) in pedestalPositions.enumerated() {
            let pedestal = Entity()
            pedestal.name = "set-pedestal"
            pedestal.position = position

            let base = ModelEntity(
                mesh: .generateCylinder(height: 0.28, radius: 0.38),
                materials: [material(diffuse: NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.07, alpha: 1))]
            )
            base.position.y = 0.14
            pedestal.addChild(base)

            let column = ModelEntity(
                mesh: .generateCylinder(height: 1.05, radius: 0.2),
                materials: [material(diffuse: NSColor(calibratedRed: 0.036, green: 0.038, blue: 0.052, alpha: 1))]
            )
            column.position.y = 0.78
            pedestal.addChild(column)

            let rim = ModelEntity(
                mesh: torusMesh(ringRadius: 0.28, pipeRadius: 0.026),
                materials: [glowMaterial(NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.92, alpha: 1), opacity: 0.58)]
            )
            rim.name = "set-flame-rim"
            rim.position.y = 1.36
            pedestal.addChild(rim)

            let flame = ModelEntity(
                mesh: .generateSphere(radius: 0.18),
                materials: [glowMaterial(NSColor(calibratedRed: 0.28, green: 0.58, blue: 1, alpha: 1), opacity: 0.86)]
            )
            flame.name = "set-flame-\(index)"
            flame.scale = [0.72, 1.35, 0.72]
            flame.position.y = 1.58
            pedestal.addChild(flame)

            let flameLight = Entity()
            flameLight.name = "set-flame-light-\(index)"
            flameLight.components.set(
                PointLightComponent(
                    color: NSColor(calibratedRed: 0.2, green: 0.42, blue: 1, alpha: 1),
                    intensity: 160,
                    attenuationRadius: 3.6
                )
            )
            flameLight.position.y = 1.56
            pedestal.addChild(flameLight)

            setDressingRoot.addChild(pedestal)
        }

        let shardPositions: [SIMD3<Float>] = [
            [-5.2, 1.9, -9.8],
            [-2.7, 2.8, -10.4],
            [2.8, 2.3, -9.4],
            [5.4, 1.75, -8.6],
            [-6.2, 1.3, -2.4],
            [6.1, 1.5, -2.1]
        ]

        for (index, position) in shardPositions.enumerated() {
            let shard = ModelEntity(
                mesh: .generateBox(width: 0.22, height: 0.62, depth: 0.08, cornerRadius: 0.015),
                materials: [
                    material(
                        diffuse: NSColor(calibratedRed: 0.055, green: 0.052, blue: 0.074, alpha: 1),
                        emission: NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.1, alpha: 1)
                    )
                ]
            )
            shard.name = "floating-shard-\(index)"
            shard.position = position
            shard.orientation = simd_quatf(angle: Float(index) * 0.83, axis: [0.2, 1, 0.12])
            setDressingBaseHeights[ObjectIdentifier(shard)] = position.y
            setDressingRoot.addChild(shard)
        }

        languageSigilRoot.name = "language-sigil-root"
        activitySigilRoot.name = "activity-sigil-root"
        setDressingRoot.addChild(languageSigilRoot)
        setDressingRoot.addChild(activitySigilRoot)
        rebuildLanguageSigil()
        rebuildActivitySigil()
    }

    private func buildLights() {
        keyLightNode.components.set(
            SpotLightComponent(
                color: .white,
                intensity: 1900,
                innerAngleInDegrees: 24,
                outerAngleInDegrees: 68,
                attenuationRadius: 22
            )
        )
        keyLightNode.position = [-5.5, 7.6, 6.3]
        keyLightNode.look(at: .zero, from: keyLightNode.position, relativeTo: root)
        root.addChild(keyLightNode)

        rimLightNode.components.set(
            PointLightComponent(
                color: NSColor(calibratedRed: 0.22, green: 0.38, blue: 1, alpha: 1),
                intensity: 1180,
                attenuationRadius: 12
            )
        )
        rimLightNode.position = [3.6, 3.8, -5.4]
        root.addChild(rimLightNode)

        phaseLightNode.components.set(
            PointLightComponent(
                color: NSColor(calibratedRed: 0.42, green: 0.26, blue: 1, alpha: 1),
                intensity: 420,
                attenuationRadius: 9
            )
        )
        phaseLightNode.position = [0, 2.4, 0]
        root.addChild(phaseLightNode)
    }

    private func buildCamera() {
        var camera = PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = CinematicCameraShot.home.fieldOfView
        camera.near = 0.01
        camera.far = 140
        cameraEntity.components.set(camera)
        cameraEntity.name = "cinematic-camera"
    }

    private func buildWizard() {
        wizardNode.name = "robot-wizard"
        wizardNode.position = .zero

        let robe = ModelEntity(
            mesh: .generateCylinder(height: 0.92, radius: 0.36),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
                    emission: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.08, alpha: 1)
                )
            ]
        )
        robe.position.y = 0.54
        wizardNode.addChild(robe)

        let chest = ModelEntity(
            mesh: .generateSphere(radius: 0.31),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.47, green: 0.5, blue: 0.54, alpha: 1),
                    emission: NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1)
                )
            ]
        )
        chest.scale = [1, 0.72, 0.78]
        chest.position.y = 1.05
        wizardNode.addChild(chest)

        headNode.name = "wizard-head"
        headNode.components.set(
            ModelComponent(
                mesh: .generateSphere(radius: 0.22),
                materials: [
                    material(
                        diffuse: NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.7, alpha: 1),
                        emission: NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.11, alpha: 1)
                    )
                ]
            )
        )
        headNode.position.y = 1.45
        wizardNode.addChild(headNode)

        let collar = ModelEntity(
            mesh: torusMesh(ringRadius: 0.31, pipeRadius: 0.028),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1),
                    emission: NSColor(calibratedRed: 0.02, green: 0.035, blue: 0.08, alpha: 1)
                )
            ]
        )
        collar.position.y = 1.23
        wizardNode.addChild(collar)

        let visor = ModelEntity(
            mesh: .generateBox(width: 0.28, height: 0.055, depth: 0.04, cornerRadius: 0.018),
            materials: [
                glowMaterial(NSColor(calibratedRed: 0.25, green: 0.84, blue: 1, alpha: 1))
            ]
        )
        visor.position = [0, 0.02, 0.195]
        headNode.addChild(visor)

        hatNode.name = "wizard-hat"
        hatNode.components.set(
            ModelComponent(
                mesh: .generateCone(height: 0.55, radius: 0.28),
                materials: [
                    material(
                        diffuse: NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.24, alpha: 1),
                        emission: NSColor(calibratedRed: 0.05, green: 0.02, blue: 0.12, alpha: 1)
                    )
                ]
            )
        )
        hatNode.position.y = 1.78
        wizardNode.addChild(hatNode)

        let hatBrim = ModelEntity(
            mesh: torusMesh(ringRadius: 0.32, pipeRadius: 0.025),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.24, alpha: 1),
                    emission: NSColor(calibratedRed: 0.05, green: 0.02, blue: 0.12, alpha: 1)
                )
            ]
        )
        hatBrim.position.y = 1.54
        wizardNode.addChild(hatBrim)

        leftArmNode.name = "wizard-left-arm"
        leftArmNode.position = [-0.36, 1.08, 0.03]
        leftArmNode.orientation = leftArmIdleOrientation
        let leftSleeve = ModelEntity(
            mesh: .generateCylinder(height: 0.64, radius: 0.06),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.2, alpha: 1),
                    emission: NSColor(calibratedRed: 0.02, green: 0.035, blue: 0.08, alpha: 1)
                )
            ]
        )
        leftSleeve.position.y = -0.28
        leftArmNode.addChild(leftSleeve)
        wizardNode.addChild(leftArmNode)

        rightArmNode.name = "wizard-right-arm"
        rightArmNode.position = [0.36, 1.07, 0.03]
        rightArmNode.orientation = rightArmIdleOrientation
        let rightSleeve = ModelEntity(
            mesh: .generateCylinder(height: 0.54, radius: 0.055),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.2, alpha: 1),
                    emission: NSColor(calibratedRed: 0.02, green: 0.035, blue: 0.08, alpha: 1)
                )
            ]
        )
        rightSleeve.position.y = -0.24
        rightArmNode.addChild(rightSleeve)
        wizardNode.addChild(rightArmNode)

        staffPivotNode.name = "wizard-staff-pivot"
        staffPivotNode.position = [0.56, 0.2, 0.05]
        staffPivotNode.orientation = staffIdleOrientation
        let staff = ModelEntity(
            mesh: .generateCylinder(height: 1.52, radius: 0.035),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.44, green: 0.4, blue: 0.34, alpha: 1),
                    emission: NSColor(calibratedRed: 0.04, green: 0.03, blue: 0.02, alpha: 1)
                )
            ]
        )
        staff.position.y = 0.76
        staffPivotNode.addChild(staff)

        staffOrbNode.components.set(
            ModelComponent(
                mesh: .generateSphere(radius: 0.13),
                materials: [
                    glowMaterial(NSColor(calibratedRed: 0.2, green: 0.68, blue: 1, alpha: 1))
                ]
            )
        )
        staffOrbNode.name = "staff-orb"
        staffOrbNode.position = [0.02, 1.52, 0]
        staffPivotNode.addChild(staffOrbNode)
        wizardNode.addChild(staffPivotNode)
    }

    private func applyPhaseChange(_ phase: LoopPhase) {
        switch phase {
        case .planning:
            setPhaseLight(color: themedColor(SpellSchool.scan.nsColor), intensity: 520)
            chargeArena(color: themedColor(SpellSchool.scan.nsColor))
            stageCamera(.wide)
        case .developing:
            setPhaseLight(color: themedColor(SpellSchool.shell.nsColor), intensity: 680)
            chargeArena(color: themedColor(SpellSchool.shell.nsColor))
            stageCamera(.castPrep)
        case .verifying:
            setPhaseLight(color: themedColor(SpellSchool.verify.nsColor), intensity: 760)
            sealArena(color: themedColor(SpellSchool.verify.nsColor))
            stageCamera(.overhead)
        case .succeeded:
            victorySurge()
        case .failed:
            stageCamera(.failure)
            setPhaseLight(color: themedColor(SpellSchool.failure.nsColor), intensity: 900)
            shakeCamera()
            chargeArena(color: themedColor(SpellSchool.failure.nsColor))
        case .paused, .cancelled, .idle:
            setPhaseLight(color: themedColor(SpellSchool.lifecycle.nsColor), intensity: 320)
            stageCamera(.home)
        }
    }

    private func apply(_ line: LiveLine) {
        let spell = SpellSchool(line: line)

        if line.status == .running {
            if line.kind == .command || line.kind == .fileChange {
                stageCamera(.overShoulder)
                chargeArena(color: spell.nsColor)
                let enemy = spawnEnemy(for: line.id, spell: spell, persistent: true)
                trackTarget(enemy.position(relativeTo: nil), duration: 1.8)
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
                castVolley(spell: spell, failed: false)
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
            startThinkingTimer(spawnImmediately: true)
            startDefensiveCasting()
        } else {
            thinkingTimer?.invalidate()
            thinkingTimer = nil
            stopDefensiveCasting()
            animate(wizardNode, toPosition: .zero, duration: 0.55, timing: .easeInOut)
            stageCamera(.home)
        }
    }

    private func startThinkingTimer(spawnImmediately: Bool) {
        thinkingTimer?.invalidate()
        let cadence = ambientSpawnCadence()
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.spawnAmbientEnemy()
            }
        }
        thinkingTimer?.tolerance = min(0.18, cadence * 0.12)
        if spawnImmediately {
            spawnAmbientEnemy()
        }
    }

    private func startDefensiveCasting() {
        defenseTimer?.invalidate()
        defenseTimer = Timer.scheduledTimer(withTimeInterval: 1.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.defensiveCast()
            }
        }
        defenseTimer?.tolerance = 0.08
        defensiveCast()
    }

    private func stopDefensiveCasting() {
        defenseTimer?.invalidate()
        defenseTimer = nil
    }

    private func chargeArena(color: NSColor) {
        arenaRing(radius: 1.1, color: color, duration: 0.55, scale: 5.8, opacity: 0.72)
        arenaRing(radius: 2.4, color: color.withAlphaComponent(0.8), duration: 0.85, scale: 2.7, opacity: 0.46)
        pulsePhaseLight(color: color, intensity: 880, duration: 0.42)
    }

    private func sealArena(color: NSColor) {
        for (index, radius) in [Float(0.9), 1.8, 3.0, 4.4].enumerated() {
            let opacity = 0.9 - Float(index) * 0.12
            let ringColor = color.withAlphaComponent(CGFloat(opacity))
            arenaRing(
                radius: radius,
                color: ringColor,
                duration: 0.85 + Double(index) * 0.12,
                scale: 1.9,
                opacity: 0.7
            )
        }
        sparkBurst(at: [0, 0.5, 0], color: color, birthRate: 1200)
        pulsePhaseLight(color: color, intensity: 1200, duration: 0.8)
    }

    private func victorySurge() {
        stageCamera(.victory)
        nextAmbientSpawnDate = Date().addingTimeInterval(2.2)
        if !Array(enemyRoot.children).isEmpty {
            castVolley(spell: .verify, failed: false)
        }
        let victoryColor = themedColor(SpellSchool.verify.nsColor)
        for radius in stride(from: Float(0.9), through: Float(7.6), by: Float(1.1)) {
            arenaRing(
                radius: radius,
                color: victoryColor.withAlphaComponent(0.7),
                duration: 1.1,
                scale: 1.35,
                opacity: 0.54
            )
        }
        portalPulse(color: victoryColor)
        sparkBurst(at: [0, 1.3, -0.4], color: victoryColor, birthRate: 1600)
        pulsePhaseLight(color: victoryColor, intensity: 1500, duration: 1.0)
    }

    private func forgeSparks(color: NSColor) {
        for offset in [
            SIMD3<Float>(-1.2, 0.45, 0.8),
            SIMD3<Float>(1.15, 0.45, 0.55),
            SIMD3<Float>(0.2, 0.45, -1.2)
        ] {
            sparkBurst(at: offset, color: color, birthRate: 620)
        }
    }

    private func historyChains(color: NSColor) {
        let points = [
            (SIMD3<Float>(-3.8, 0.18, -1.8), SIMD3<Float>(3.6, 0.18, 1.6)),
            (SIMD3<Float>(-3.2, 0.24, 2.0), SIMD3<Float>(3.3, 0.24, -1.6)),
            (SIMD3<Float>(0, 0.26, -4.2), SIMD3<Float>(0, 0.26, 4.2))
        ]
        for pair in points {
            spellTrail(from: pair.0, to: pair.1, spell: .git)
        }
        arenaRing(radius: 4.0, color: color, duration: 0.95, scale: 1.45, opacity: 0.58)
    }

    private func arenaRing(radius: Float, color: NSColor, duration: TimeInterval, scale: Float, opacity: Float) {
        let ring = ModelEntity(
            mesh: torusMesh(ringRadius: radius, pipeRadius: 0.018),
            materials: [glowMaterial(color, opacity: opacity)]
        )
        ring.position.y = 0.055
        ring.components.set(OpacityComponent(opacity: opacity))
        effectsRoot.addChild(ring)
        animate(ring, toScale: SIMD3<Float>(repeating: scale), toOpacity: 0, duration: duration, removeOnCompletion: true)
    }

    private func pulsePhaseLight(color: NSColor, intensity: Float, duration: TimeInterval) {
        setPhaseLight(color: color, intensity: intensity)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.setPhaseLight(color: color, intensity: 360)
        }
    }

    private func spellTrail(from start: SIMD3<Float>, to end: SIMD3<Float>, spell: SpellSchool) {
        let beam = beamEntity(
            from: start,
            to: end,
            radius: spell == .verify ? 0.026 : 0.016,
            color: spell.nsColor.withAlphaComponent(0.72),
            opacity: 0.58
        )
        effectsRoot.addChild(beam)
        animate(
            beam,
            toScale: [1, 1.02, 1],
            toOpacity: 0,
            duration: spell == .pressure ? 0.18 : 0.28,
            timing: .easeOut,
            removeOnCompletion: true
        )

        let steps = spell == .scan ? 11 : 7
        let baseRadius: Float = spell == .verify ? 0.08 : 0.052
        for index in 0...steps {
            let t = Float(index) / Float(max(steps, 1))
            let point = interpolate(start, end, t: t)
            let mesh = spell == .verify
                ? torusMesh(ringRadius: 0.12, pipeRadius: 0.012)
                : MeshResource.generateSphere(radius: baseRadius)
            let node = ModelEntity(mesh: mesh, materials: [glowMaterial(spell.nsColor, opacity: 0.82)])
            node.position = point
            node.components.set(OpacityComponent(opacity: 0.82))
            effectsRoot.addChild(node)
            animate(
                node,
                toScale: SIMD3<Float>(repeating: spell == .scan ? 1.9 : 2.6),
                toOpacity: 0,
                duration: 0.34,
                delay: Double(index) * 0.025,
                removeOnCompletion: true
            )
        }
    }

    private func castCharge(at position: SIMD3<Float>, spell: SpellSchool, duration: TimeInterval) {
        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.16),
            materials: [glowMaterial(spell.nsColor, opacity: 0.85)]
        )
        core.position = position
        core.components.set(OpacityComponent(opacity: 0.85))
        effectsRoot.addChild(core)
        animate(
            core,
            toScale: SIMD3<Float>(repeating: 2.6),
            toOpacity: 0,
            duration: duration,
            timing: .easeOut,
            removeOnCompletion: true
        )

        for (index, axis) in [
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 0, 1)
        ].enumerated() {
            let ring = ModelEntity(
                mesh: torusMesh(ringRadius: 0.26 + Float(index) * 0.06, pipeRadius: 0.01),
                materials: [glowMaterial(spell.nsColor.withAlphaComponent(0.78), opacity: 0.68)]
            )
            ring.position = position
            ring.orientation = simd_quatf(angle: Float(index) * .pi / 3, axis: axis)
            ring.components.set(OpacityComponent(opacity: 0.68))
            effectsRoot.addChild(ring)
            animate(
                ring,
                toScale: SIMD3<Float>(repeating: 2.2 + Float(index) * 0.28),
                toOpacity: 0,
                duration: duration + Double(index) * 0.04,
                timing: .easeOut,
                removeOnCompletion: true
            )
        }

        for index in 0..<14 {
            let angle = Float(index) / 14 * .pi * 2
            let offset = SIMD3<Float>(
                cos(angle) * Float.random(in: 0.35...0.85),
                Float.random(in: -0.18...0.32),
                sin(angle) * Float.random(in: 0.35...0.85)
            )
            let mote = ModelEntity(
                mesh: .generateSphere(radius: Float.random(in: 0.018...0.04)),
                materials: [glowMaterial(spell.nsColor, opacity: 0.72)]
            )
            mote.position = position + offset
            mote.components.set(OpacityComponent(opacity: 0.72))
            effectsRoot.addChild(mote)
            animate(
                mote,
                toPosition: position,
                toScale: SIMD3<Float>(repeating: 0.12),
                toOpacity: 0,
                duration: duration * Double.random(in: 0.72...1.05),
                timing: .easeIn,
                removeOnCompletion: true
            )
        }
    }

    private func beamEntity(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        color: NSColor,
        opacity: Float
    ) -> ModelEntity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let beam = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [glowMaterial(color, opacity: opacity)]
        )
        beam.name = "spell-beam"
        beam.position = start + delta * 0.5
        let direction = simd_length(delta) > 0.001 ? simd_normalize(delta) : SIMD3<Float>(0, 1, 0)
        beam.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        beam.components.set(OpacityComponent(opacity: opacity))
        return beam
    }

    private func sparkBurst(at position: SIMD3<Float>, color: NSColor, birthRate: Float) {
        let count = max(16, min(42, Int(birthRate / 45)))
        for _ in 0..<count {
            let spark = ModelEntity(
                mesh: .generateSphere(radius: Float.random(in: 0.018...0.05)),
                materials: [glowMaterial(color, opacity: 0.9)]
            )
            spark.position = position
            spark.components.set(OpacityComponent(opacity: 0.9))
            effectsRoot.addChild(spark)

            var direction = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -0.15...1),
                Float.random(in: -1...1)
            )
            if simd_length(direction) < 0.001 {
                direction = [0, 1, 0]
            }
            direction = simd_normalize(direction)
            let distance = Float.random(in: 0.65...1.9)
            animate(
                spark,
                toPosition: position + direction * distance,
                toScale: SIMD3<Float>(repeating: 0.12),
                toOpacity: 0,
                duration: Double.random(in: 0.42...0.78),
                removeOnCompletion: true
            )
        }
    }

    private func interpolate(_ start: SIMD3<Float>, _ end: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        start + (end - start) * t
    }

    private func defensiveCast() {
        var targets = livingEnemies()
        if targets.isEmpty {
            spawnAmbientEnemy()
            targets = livingEnemies()
        }
        guard let target = closestEnemy(in: targets) else { return }

        let defensiveSpell = nextDefensiveSpell()
        let spell = defensiveSpell.school
        let startPosition = staffOrbNode.convert(position: .zero, to: nil)
        let targetPosition = target.position(relativeTo: nil)
        trackTarget(targetPosition, duration: defensiveSpell == .wall ? 1.9 : 1.45)
        performCastPose(spell: spell, duration: 0.34)
        castCharge(at: startPosition, spell: spell, duration: 0.18)
        spellTrail(from: startPosition, to: targetPosition, spell: spell)

        switch defensiveSpell {
        case .slow:
            applySlow(to: target, at: targetPosition, color: defensiveSpell.color)
        case .stun:
            applyStun(to: target, at: targetPosition, color: defensiveSpell.color)
        case .wall:
            buildMagicWall(blocking: target, color: defensiveSpell.color)
        }

        staffOrbBoost = max(staffOrbBoost, 0.28)
    }

    private func nextDefensiveSpell() -> DefensiveSpell {
        let sequence: [DefensiveSpell] = [.wall, .slow, .stun, .slow]
        let spell = sequence[defensiveCastIndex % sequence.count]
        defensiveCastIndex += 1
        return spell
    }

    private func applySlow(to enemy: Entity, at position: SIMD3<Float>, color: NSColor) {
        cancelMotion(for: enemy)
        slowedEnemies[ObjectIdentifier(enemy)] = Date().addingTimeInterval(4.2)
        slowField(at: position, color: color)

        animate(
            enemy,
            toPosition: guardedAdvancePosition(for: enemy, step: 0.75),
            duration: 8.8,
            timing: .easeOut
        )
    }

    private func applyStun(to enemy: Entity, at position: SIMD3<Float>, color: NSColor) {
        cancelMotion(for: enemy)
        stunnedEnemies[ObjectIdentifier(enemy)] = Date().addingTimeInterval(3.1)
        stunField(at: position, color: color)

        animate(enemy, toPosition: enemy.position + [0, 0.18, 0], duration: 0.12, timing: .easeOut) { [weak self, weak enemy] in
            guard let self, let enemy else { return }
            self.animate(enemy, toPosition: enemy.position - [0, 0.18, 0], duration: 0.32, timing: .easeInOut)
        }
    }

    private func buildMagicWall(blocking enemy: Entity, color: NSColor) {
        cancelMotion(for: enemy)
        let id = ObjectIdentifier(enemy)
        stunnedEnemies[id] = Date().addingTimeInterval(1.8)

        let wizardPosition = wizardNode.position(relativeTo: nil)
        let enemyPosition = enemy.position(relativeTo: nil)
        let direction = horizontalDirection(from: wizardPosition, to: enemyPosition) ?? [0, 0, 1]
        let side = SIMD3<Float>(-direction.z, 0, direction.x)
        let wallPosition = mix(wizardPosition, enemyPosition, 0.58)

        let wall = Entity()
        wall.name = "magic-wall"
        wall.position = [wallPosition.x, 0.82, wallPosition.z]
        wall.look(at: wall.position + direction, from: wall.position, relativeTo: nil, forward: .positiveZ)
        wall.components.set(OpacityComponent(opacity: 0.86))

        let panel = ModelEntity(
            mesh: .generateBox(width: 2.45, height: 1.34, depth: 0.055, cornerRadius: 0.025),
            materials: [glowMaterial(color.withAlphaComponent(0.48), opacity: 0.42)]
        )
        panel.components.set(OpacityComponent(opacity: 0.42))
        wall.addChild(panel)

        for offsetY in [Float(-0.66), 0.66] {
            let edge = ModelEntity(
                mesh: .generateBox(width: 2.62, height: 0.045, depth: 0.075, cornerRadius: 0.02),
                materials: [glowMaterial(color, opacity: 0.78)]
            )
            edge.position.y = offsetY
            edge.components.set(OpacityComponent(opacity: 0.78))
            wall.addChild(edge)
        }

        for offsetX in [Float(-1.22), 1.22] {
            let pillar = ModelEntity(
                mesh: .generateBox(width: 0.055, height: 1.42, depth: 0.08, cornerRadius: 0.02),
                materials: [glowMaterial(color, opacity: 0.72)]
            )
            pillar.position.x = offsetX
            pillar.components.set(OpacityComponent(opacity: 0.72))
            wall.addChild(pillar)
        }

        effectsRoot.addChild(wall)
        animate(wall, toScale: [1.08, 1.03, 1], toOpacity: 0, duration: 2.25, timing: .easeOut, removeOnCompletion: true)

        let pushPosition = enemyPosition + direction * 0.82 + side * Float.random(in: -0.28...0.28)
        animate(enemy, toPosition: [pushPosition.x, 0.45, pushPosition.z], duration: 0.42, timing: .easeOut)
        arenaRing(radius: simd_length(SIMD2<Float>(wallPosition.x, wallPosition.z)), color: color, duration: 0.85, scale: 1.04, opacity: 0.36)
    }

    private func destroyEnemy(_ enemy: Entity, color: NSColor, failed: Bool) {
        let id = ObjectIdentifier(enemy)
        enemyHealth[id] = nil
        slowedEnemies[id] = nil
        stunnedEnemies[id] = nil
        enemy.name = "dyingEnemy"
        animations.removeAll { $0.entity === enemy }
        impact(at: enemy.position(relativeTo: nil), color: color, failed: failed)
        if failed {
            shakeCamera()
        }
        animate(
            enemy,
            toScale: SIMD3<Float>(repeating: failed ? 1.18 : 0.08),
            toOpacity: 0,
            duration: failed ? 0.22 : 0.28,
            removeOnCompletion: true
        )
    }

    private func livingEnemies() -> [Entity] {
        let nodes = Array(enemyRoot.children).filter { node in
            node.parent != nil && node.name != "dyingEnemy"
        }
        let ids = Set(nodes.map { ObjectIdentifier($0) })
        enemyHealth = enemyHealth.filter { ids.contains($0.key) }
        let now = Date()
        slowedEnemies = slowedEnemies.filter { ids.contains($0.key) && $0.value > now }
        stunnedEnemies = stunnedEnemies.filter { ids.contains($0.key) && $0.value > now }
        for node in nodes where enemyHealth[ObjectIdentifier(node)] == nil {
            enemyHealth[ObjectIdentifier(node)] = 1.0
        }
        return nodes
    }

    private func closestEnemy(in enemies: [Entity]) -> Entity? {
        let wizardPosition = wizardNode.position(relativeTo: nil)
        return enemies.min {
            distanceSquared($0.position(relativeTo: nil), wizardPosition) < distanceSquared($1.position(relativeTo: nil), wizardPosition)
        }
    }

    private func distanceSquared(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
        let delta = lhs - rhs
        return simd_dot(delta, delta)
    }

    private func chipImpact(at position: SIMD3<Float>, color: NSColor) {
        let flare = ModelEntity(
            mesh: .generateSphere(radius: 0.11),
            materials: [glowMaterial(color)]
        )
        flare.position = position
        effectsRoot.addChild(flare)
        animate(
            flare,
            toScale: SIMD3<Float>(repeating: 1.8),
            toOpacity: 0,
            duration: 0.18,
            removeOnCompletion: true
        )
    }

    private func slowField(at position: SIMD3<Float>, color: NSColor) {
        for (index, radius) in [Float(0.42), 0.68, 0.94].enumerated() {
            let ring = ModelEntity(
                mesh: torusMesh(ringRadius: radius, pipeRadius: 0.012),
                materials: [glowMaterial(color.withAlphaComponent(0.74), opacity: 0.62)]
            )
            ring.position = [position.x, 0.12 + Float(index) * 0.045, position.z]
            ring.components.set(OpacityComponent(opacity: 0.62))
            effectsRoot.addChild(ring)
            animate(
                ring,
                toScale: SIMD3<Float>(repeating: 1.55),
                toOpacity: 0,
                duration: 1.15 + Double(index) * 0.12,
                delay: Double(index) * 0.06,
                timing: .easeOut,
                removeOnCompletion: true
            )
        }
    }

    private func stunField(at position: SIMD3<Float>, color: NSColor) {
        let flare = ModelEntity(
            mesh: torusMesh(ringRadius: 0.36, pipeRadius: 0.016),
            materials: [glowMaterial(color, opacity: 0.82)]
        )
        flare.position = [position.x, position.y + 0.18, position.z]
        flare.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        flare.components.set(OpacityComponent(opacity: 0.82))
        effectsRoot.addChild(flare)
        animate(flare, toScale: SIMD3<Float>(repeating: 2.2), toOpacity: 0, duration: 0.74, timing: .easeOut, removeOnCompletion: true)

        sparkBurst(at: position + [0, 0.32, 0], color: color, birthRate: 520)
    }

    private func guardedAdvancePosition(for enemy: Entity, step: Float) -> SIMD3<Float> {
        let wizardPosition = wizardNode.position(relativeTo: nil)
        let enemyPosition = enemy.position(relativeTo: nil)
        let direction = horizontalDirection(from: wizardPosition, to: enemyPosition) ?? [0, 0, 1]
        let distance = simd_length(SIMD2<Float>(enemyPosition.x - wizardPosition.x, enemyPosition.z - wizardPosition.z))
        let guardedDistance = max(3.9, distance - step)
        let destination = wizardPosition + direction * guardedDistance
        return [destination.x, 0.45, destination.z]
    }

    @discardableResult
    private func spawnEnemy(for id: UUID?, spell: SpellSchool, persistent: Bool) -> Entity {
        if let id, let existing = activeEnemies[id] {
            enemyHealth[ObjectIdentifier(existing)] = enemyHealth[ObjectIdentifier(existing)] ?? 1.0
            return existing
        }

        ambientSpawnIndex += 1
        let angle = (Float(ambientSpawnIndex) * 1.77).truncatingRemainder(dividingBy: .pi * 2)
        let radius = Float.random(in: 7.0...10.5)
        let node = makeEnemy(spell: spell)
        node.position = [cos(angle) * radius, 0.45, sin(angle) * radius]
        node.name = persistent ? "activeEnemy" : "ambientEnemy"
        enemyRoot.addChild(node)
        enemyHealth[ObjectIdentifier(node)] = 1.0

        let destination = SIMD3<Float>(
            Float.random(in: -1.7...1.7),
            0.45,
            Float.random(in: -1.2...1.8)
        )
        animate(
            node,
            toPosition: destination,
            duration: persistent ? 13.5 : 7.5,
            timing: .easeInOut
        )

        if let id {
            activeEnemies[id] = node
        }

        return node
    }

    private func spawnAmbientEnemy() {
        guard Date() >= nextAmbientSpawnDate else { return }
        let ambientEnemies = enemyRoot.children.filter { $0.name == "ambientEnemy" }
        guard ambientEnemies.count < ambientEnemyLimit() else { return }
        spawnEnemy(for: nil, spell: ambientSpellForActivity(), persistent: false)
    }

    private func ambientSpawnCadence() -> TimeInterval {
        CinematicTuning.ambientSpawnCadence(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
    }

    private func ambientEnemyLimit() -> Int {
        CinematicTuning.ambientEnemyLimit(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
    }

    private func ambientSpellForActivity() -> SpellSchool {
        activityMotif.ambientSpell(
            languageAmbient: languageMotif.ambientSpell,
            spawnIndex: ambientSpawnIndex
        )
    }

    private func makeEnemy(spell: SpellSchool) -> Entity {
        let root = Entity()

        let body = ModelEntity(
            mesh: .generateSphere(radius: 0.34),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.12, green: 0.105, blue: 0.12, alpha: 1),
                    emission: spell.enemyGlow
                )
            ]
        )
        body.scale = [1, 1.25, 0.82]
        root.addChild(body)

        let eye = ModelEntity(
            mesh: .generateBox(width: 0.24, height: 0.055, depth: 0.045, cornerRadius: 0.015),
            materials: [glowMaterial(spell.nsColor)]
        )
        eye.position = [0, 0.08, 0.29]
        root.addChild(eye)

        let crown = ModelEntity(
            mesh: .generateCone(height: 0.28, radius: 0.18),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.18, alpha: 1),
                    emission: spell.enemyGlow.withAlphaComponent(0.45)
                )
            ]
        )
        crown.position.y = 0.42
        root.addChild(crown)

        let aura = ModelEntity(
            mesh: torusMesh(ringRadius: 0.46, pipeRadius: 0.012),
            materials: [glowMaterial(spell.nsColor.withAlphaComponent(0.55), opacity: 0.65)]
        )
        aura.name = "enemyAura"
        aura.position.y = -0.43
        aura.components.set(OpacityComponent(opacity: 0.65))
        root.addChild(aura)

        return root
    }

    private func castVolley(spell: SpellSchool, failed: Bool) {
        var targets = livingEnemies()
        if targets.isEmpty {
            targets = [spawnEnemy(for: nil, spell: spell, persistent: false)]
        }

        activeEnemies.removeAll()
        nextAmbientSpawnDate = Date().addingTimeInterval(1.4)
        targets.forEach { target in
            animations.removeAll { $0.entity === target }
        }

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

    private func cast(spell: SpellSchool, at enemy: Entity, failed: Bool) {
        let targetPosition = enemy.position(relativeTo: nil)
        let startPosition = staffOrbNode.convert(position: .zero, to: nil)
        trackTarget(targetPosition, duration: 2.1)
        performCastPose(spell: spell, duration: failed ? 0.52 : 0.44)
        castCharge(at: startPosition, spell: spell, duration: failed ? 0.24 : 0.2)
        enemyHealth[ObjectIdentifier(enemy)] = nil
        enemy.name = "dyingEnemy"

        let releaseDelay: TimeInterval = failed ? 0.16 : 0.11
        Task { @MainActor [weak self, weak enemy] in
            try? await Task.sleep(for: .seconds(releaseDelay))
            guard let self, let enemy else { return }
            let projectile = ModelEntity(
                mesh: .generateSphere(radius: failed ? 0.11 : 0.085),
                materials: [self.glowMaterial(spell.nsColor)]
            )
            projectile.position = startPosition
            self.effectsRoot.addChild(projectile)
            self.spellTrail(from: startPosition, to: targetPosition, spell: spell)
            self.animate(projectile, toPosition: targetPosition, duration: 0.38, timing: .easeIn, removeOnCompletion: true)

            try? await Task.sleep(for: .seconds(0.34))
            self.impact(at: targetPosition, color: spell.nsColor, failed: failed)
            if failed {
                self.shakeCamera()
            }
            self.animate(
                enemy,
                toScale: SIMD3<Float>(repeating: failed ? 1.18 : 0.08),
                toOpacity: 0,
                duration: failed ? 0.22 : 0.32,
                removeOnCompletion: true
            )
        }

        staffOrbBoost = max(staffOrbBoost, 0.42)
    }

    private func impact(at position: SIMD3<Float>, color: NSColor, failed: Bool) {
        let flashColor = failed ? SpellSchool.failure.nsColor : color
        let ring = ModelEntity(
            mesh: torusMesh(ringRadius: failed ? 0.18 : 0.12, pipeRadius: 0.018),
            materials: [glowMaterial(flashColor)]
        )
        ring.position = position
        effectsRoot.addChild(ring)
        animate(
            ring,
            toScale: SIMD3<Float>(repeating: failed ? 5.2 : 3.4),
            toOpacity: 0,
            duration: failed ? 0.5 : 0.62,
            removeOnCompletion: true
        )

        let flare = ModelEntity(
            mesh: .generateSphere(radius: failed ? 0.28 : 0.2),
            materials: [glowMaterial(flashColor)]
        )
        flare.position = position
        effectsRoot.addChild(flare)
        animate(
            flare,
            toScale: SIMD3<Float>(repeating: failed ? 2.2 : 1.55),
            toOpacity: 0,
            duration: 0.34,
            removeOnCompletion: true
        )

        for index in 0..<2 {
            let shock = ModelEntity(
                mesh: torusMesh(ringRadius: 0.28 + Float(index) * 0.16, pipeRadius: 0.01),
                materials: [glowMaterial(flashColor.withAlphaComponent(0.7), opacity: 0.56)]
            )
            shock.position = [position.x, 0.08 + Float(index) * 0.02, position.z]
            shock.components.set(OpacityComponent(opacity: 0.56))
            effectsRoot.addChild(shock)
            animate(
                shock,
                toScale: SIMD3<Float>(repeating: failed ? 7.0 : 4.4),
                toOpacity: 0,
                duration: failed ? 0.72 : 0.58,
                delay: Double(index) * 0.04,
                timing: .easeOut,
                removeOnCompletion: true
            )
        }

        sparkBurst(at: position + [0, 0.1, 0], color: flashColor, birthRate: failed ? 1100 : 760)
    }

    private func insightPulse(color: NSColor) {
        let rune = ModelEntity(
            mesh: torusMesh(ringRadius: 0.8, pipeRadius: 0.018),
            materials: [glowMaterial(color)]
        )
        rune.position = [0, 1.9, 0]
        effectsRoot.addChild(rune)
        animate(
            rune,
            toScale: SIMD3<Float>(repeating: 1.8),
            toOpacity: 0,
            duration: 1.2,
            removeOnCompletion: true
        )
    }

    private func portalPulse(color: NSColor) {
        let portal = ModelEntity(
            mesh: torusMesh(ringRadius: 1.05, pipeRadius: 0.025),
            materials: [glowMaterial(color)]
        )
        portal.position = [0, 1.45, -3.2]
        portal.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        effectsRoot.addChild(portal)
        animate(
            portal,
            toScale: SIMD3<Float>(repeating: 1.65),
            toOpacity: 0,
            duration: 1.1,
            removeOnCompletion: true
        )
    }

    private func rebuildLanguageSigil() {
        clearChildren(of: languageSigilRoot)
        languageSigilRoot.name = "language-sigil-\(languageMotif.sigilIdentifier)"
        languageSigilRoot.position = [-5.8, 0.035, 5.55]

        addSigilBase(
            to: languageSigilRoot,
            color: languageMotif.accent,
            secondary: languageMotif.secondaryAccent,
            radius: 0.64
        )
        addSigilSegments(
            languageSigilSegments(for: languageMotif.style),
            to: languageSigilRoot,
            color: languageMotif.accent,
            secondary: languageMotif.secondaryAccent
        )
        addSigilCore(
            to: languageSigilRoot,
            color: languageMotif.secondaryAccent,
            scale: [1, 1.35, 1]
        )
    }

    private func rebuildActivitySigil() {
        clearChildren(of: activitySigilRoot)
        activitySigilRoot.name = "activity-sigil-\(activityMotif.sigilIdentifier)"
        activitySigilRoot.position = [5.8, 0.035, 5.55]

        let color = activityColor(for: activityMotif)
        let secondary = activityMotif.tintSource.map { themedColor($0.nsColor) } ?? languageMotif.secondaryAccent
        addSigilBase(
            to: activitySigilRoot,
            color: color,
            secondary: secondary,
            radius: 0.58
        )
        addSigilSegments(
            activitySigilSegments(for: activityMotif.style),
            to: activitySigilRoot,
            color: color,
            secondary: secondary
        )
        addSigilCore(
            to: activitySigilRoot,
            color: secondary,
            scale: activityMotif.eventKind == .unavailable ? [0.62, 0.62, 0.62] : [0.9, 1.1, 0.9]
        )
    }

    private func clearChildren(of entity: Entity) {
        for child in Array(entity.children) {
            child.removeFromParent()
        }
    }

    private func addSigilBase(
        to root: Entity,
        color: NSColor,
        secondary: NSColor,
        radius: Float
    ) {
        let plinth = ModelEntity(
            mesh: .generateCylinder(height: 0.1, radius: radius),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.028, green: 0.03, blue: 0.042, alpha: 1),
                    emission: color.withAlphaComponent(0.12)
                )
            ]
        )
        plinth.name = "sigil-plinth"
        plinth.position.y = 0.05
        root.addChild(plinth)

        let outerRing = ModelEntity(
            mesh: torusMesh(ringRadius: radius * 1.05, pipeRadius: 0.012),
            materials: [glowMaterial(color.withAlphaComponent(0.72), opacity: 0.58)]
        )
        outerRing.name = "sigil-outer-ring"
        outerRing.position.y = 0.12
        root.addChild(outerRing)

        let innerRing = ModelEntity(
            mesh: torusMesh(ringRadius: radius * 0.42, pipeRadius: 0.008),
            materials: [glowMaterial(secondary.withAlphaComponent(0.64), opacity: 0.46)]
        )
        innerRing.name = "sigil-inner-ring"
        innerRing.position.y = 0.145
        root.addChild(innerRing)
    }

    private func addSigilCore(
        to root: Entity,
        color: NSColor,
        scale: SIMD3<Float>
    ) {
        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.075),
            materials: [glowMaterial(color, opacity: 0.84)]
        )
        core.name = "sigil-core"
        core.scale = scale
        core.position.y = 0.24
        root.addChild(core)
    }

    private func addSigilSegments(
        _ segments: [SetDressingSigilSegment],
        to root: Entity,
        color: NSColor,
        secondary: NSColor
    ) {
        for segment in segments {
            let beam = beamEntity(
                from: segment.start,
                to: segment.end,
                radius: segment.radius,
                color: segment.usesSecondary ? secondary : color,
                opacity: segment.opacity
            )
            beam.name = "sigil-segment"
            root.addChild(beam)
        }
    }

    private func languageSigilSegments(for style: CinematicLanguageSigilStyle) -> [SetDressingSigilSegment] {
        let y: Float = 0.2
        switch style {
        case .swiftComet:
            return [
                SetDressingSigilSegment([-0.42, y, -0.34], [0.24, y, 0.16], radius: 0.018),
                SetDressingSigilSegment([-0.08, y, -0.48], [0.48, y, -0.04], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0.16, y, 0.16], [0.5, y, 0.42], radius: 0.014)
            ]
        case .scriptCircuit:
            return [
                SetDressingSigilSegment([-0.42, y, -0.34], [0.42, y, -0.34], radius: 0.012),
                SetDressingSigilSegment([0.42, y, -0.34], [0.42, y, 0.34], radius: 0.012),
                SetDressingSigilSegment([0.42, y, 0.34], [-0.42, y, 0.34], radius: 0.012),
                SetDressingSigilSegment([-0.42, y, 0.34], [-0.42, y, -0.34], radius: 0.012),
                SetDressingSigilSegment([-0.18, y, 0], [0.36, y, 0], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0.08, y, -0.28], [0.08, y, 0.28], radius: 0.01, usesSecondary: true)
            ]
        case .pythonCoil:
            return [
                SetDressingSigilSegment([-0.42, y, -0.18], [-0.08, y, -0.38], radius: 0.015),
                SetDressingSigilSegment([-0.08, y, -0.38], [0.28, y, -0.2], radius: 0.015, usesSecondary: true),
                SetDressingSigilSegment([0.28, y, -0.2], [-0.24, y, 0.2], radius: 0.015),
                SetDressingSigilSegment([-0.24, y, 0.2], [0.12, y, 0.4], radius: 0.015, usesSecondary: true),
                SetDressingSigilSegment([0.12, y, 0.4], [0.44, y, 0.18], radius: 0.015)
            ]
        case .goCurrent:
            return [
                SetDressingSigilSegment([-0.48, y, -0.22], [0.36, y, -0.22], radius: 0.014),
                SetDressingSigilSegment([-0.36, y, 0], [0.48, y, 0], radius: 0.018, usesSecondary: true),
                SetDressingSigilSegment([-0.48, y, 0.22], [0.28, y, 0.22], radius: 0.014),
                SetDressingSigilSegment([0.24, y, -0.38], [0.5, y, -0.16], radius: 0.012),
                SetDressingSigilSegment([0.5, y, 0.16], [0.24, y, 0.38], radius: 0.012)
            ]
        case .rustGear:
            return stride(from: 0, to: 8, by: 1).map { index in
                let angle = Float(index) / 8 * .pi * 2
                let inner = SIMD3<Float>(cos(angle) * 0.22, y, sin(angle) * 0.22)
                let outer = SIMD3<Float>(cos(angle) * 0.52, y, sin(angle) * 0.52)
                return SetDressingSigilSegment(inner, outer, radius: 0.012, usesSecondary: index % 2 == 0)
            }
        case .markdownRune:
            return [
                SetDressingSigilSegment([-0.42, y, 0.34], [-0.42, y, -0.34], radius: 0.014),
                SetDressingSigilSegment([-0.42, y, -0.34], [0, y, 0.05], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0, y, 0.05], [0.42, y, -0.34], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0.42, y, -0.34], [0.42, y, 0.34], radius: 0.014),
                SetDressingSigilSegment([-0.16, y, 0.28], [0.16, y, 0.28], radius: 0.012)
            ]
        case .polyglotPrism:
            return [
                SetDressingSigilSegment([0, y, -0.5], [0.44, y, 0.24], radius: 0.014),
                SetDressingSigilSegment([0.44, y, 0.24], [-0.44, y, 0.24], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([-0.44, y, 0.24], [0, y, -0.5], radius: 0.014),
                SetDressingSigilSegment([0, y, -0.5], [0, y, 0.24], radius: 0.01, usesSecondary: true)
            ]
        case .unknownGate:
            return [
                SetDressingSigilSegment([-0.38, y, 0.38], [-0.38, y, -0.18], radius: 0.014),
                SetDressingSigilSegment([-0.38, y, -0.18], [0, y, -0.42], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0, y, -0.42], [0.38, y, -0.18], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0.38, y, -0.18], [0.38, y, 0.38], radius: 0.014)
            ]
        }
    }

    private func activitySigilSegments(for style: CinematicActivitySigilStyle) -> [SetDressingSigilSegment] {
        let y: Float = 0.2
        switch style {
        case .dimGate:
            return [
                SetDressingSigilSegment([-0.26, y, 0.24], [0.26, y, 0.24], radius: 0.01),
                SetDressingSigilSegment([0, y, -0.3], [0, y, 0.1], radius: 0.01, usesSecondary: true)
            ]
        case .calmHalo:
            return [
                SetDressingSigilSegment([-0.34, y, 0], [0.34, y, 0], radius: 0.012),
                SetDressingSigilSegment([0, y, -0.34], [0, y, 0.34], radius: 0.012, usesSecondary: true)
            ]
        case .pressureShard:
            return [
                SetDressingSigilSegment([0, y, -0.48], [0.18, y, 0.18], radius: 0.016),
                SetDressingSigilSegment([0.18, y, 0.18], [-0.18, y, 0.46], radius: 0.013, usesSecondary: true),
                SetDressingSigilSegment([-0.22, y, -0.16], [0.46, y, -0.16], radius: 0.012)
            ]
        case .fractureCross:
            return [
                SetDressingSigilSegment([-0.46, y, -0.38], [0.46, y, 0.38], radius: 0.018),
                SetDressingSigilSegment([0.46, y, -0.38], [-0.46, y, 0.38], radius: 0.018, usesSecondary: true),
                SetDressingSigilSegment([-0.12, y, -0.48], [0.12, y, -0.12], radius: 0.011)
            ]
        case .historyBranch:
            return [
                SetDressingSigilSegment([-0.46, y, 0.24], [0.28, y, -0.24], radius: 0.014),
                SetDressingSigilSegment([-0.08, y, 0], [0.46, y, 0.26], radius: 0.012, usesSecondary: true),
                SetDressingSigilSegment([0.04, y, -0.08], [0.42, y, -0.42], radius: 0.012, usesSecondary: true)
            ]
        case .sealBurst:
            return [
                SetDressingSigilSegment([-0.42, y, 0.02], [-0.1, y, 0.34], radius: 0.018, usesSecondary: true),
                SetDressingSigilSegment([-0.1, y, 0.34], [0.46, y, -0.36], radius: 0.018),
                SetDressingSigilSegment([-0.08, y, -0.42], [0.08, y, -0.18], radius: 0.01)
            ]
        case .recoveryArc:
            return [
                SetDressingSigilSegment([-0.48, y, 0.3], [-0.18, y, 0.02], radius: 0.014),
                SetDressingSigilSegment([-0.18, y, 0.02], [0.1, y, -0.18], radius: 0.014, usesSecondary: true),
                SetDressingSigilSegment([0.1, y, -0.18], [0.42, y, -0.4], radius: 0.014),
                SetDressingSigilSegment([0.2, y, -0.42], [0.42, y, -0.4], radius: 0.012),
                SetDressingSigilSegment([0.42, y, -0.4], [0.36, y, -0.16], radius: 0.012)
            ]
        case .backlashSpike:
            return [
                SetDressingSigilSegment([0, y, -0.52], [0.4, y, 0.36], radius: 0.018),
                SetDressingSigilSegment([0.4, y, 0.36], [-0.4, y, 0.36], radius: 0.018, usesSecondary: true),
                SetDressingSigilSegment([-0.4, y, 0.36], [0, y, -0.52], radius: 0.018),
                SetDressingSigilSegment([0, y, -0.22], [0, y, 0.24], radius: 0.012, usesSecondary: true)
            ]
        }
    }

    private func activityColor(for motif: CinematicActivityMotif) -> NSColor {
        switch motif.eventKind {
        case .unavailable:
            return NSColor(calibratedRed: 0.24, green: 0.28, blue: 0.34, alpha: 1)
        case .clean:
            return themedColor(SpellSchool.lifecycle.nsColor)
        case .dirty:
            return themedColor(SpellSchool.pressure.nsColor)
        case .conflicted, .failure:
            return themedColor(SpellSchool.failure.nsColor)
        case .commit:
            return themedColor(SpellSchool.git.nsColor)
        case .success, .recovery:
            return themedColor(SpellSchool.verify.nsColor)
        }
    }

    private func applyLanguageTheme(animated: Bool) {
        let accent = languageMotif.accent
        let secondary = languageMotif.secondaryAccent

        setGlow(accent, on: staffOrbNode)
        for pedestal in setDressingRoot.children where pedestal.name == "set-pedestal" {
            for child in pedestal.children {
                if child.name == "set-flame-rim" {
                    setGlow(accent, opacity: 0.62, on: child)
                } else if child.name.hasPrefix("set-flame-light-") {
                    setPointLight(color: accent, intensity: 190, on: child)
                } else if child.name.hasPrefix("set-flame-") {
                    setGlow(secondary, opacity: 0.88, on: child)
                }
            }
        }

        for shard in setDressingRoot.children where shard.name.hasPrefix("floating-shard-") {
            if var model = shard.components[ModelComponent.self] {
                model.materials = [
                    material(
                        diffuse: NSColor(calibratedRed: 0.055, green: 0.052, blue: 0.074, alpha: 1),
                        emission: accent.withAlphaComponent(0.24)
                    )
                ]
                shard.components.set(model)
            }
        }

        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
        rebuildLanguageSigil()
        rebuildActivitySigil()
        if animated, languageMotif.language != .unknown {
            arenaRing(radius: 6.6, color: accent.withAlphaComponent(0.72), duration: 1.05, scale: 1.18, opacity: 0.34)
        }
    }

    private func applyActivityTraits(animated: Bool) {
        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
        rebuildActivitySigil()
        guard animated, activityMotif.eventKind != .unavailable else { return }

        switch activityMotif.eventKind {
        case .conflicted, .failure:
            let color = themedColor(activityMotif.transitionSpell?.nsColor ?? SpellSchool.failure.nsColor)
            arenaRing(radius: 5.4, color: color.withAlphaComponent(0.68), duration: 0.62, scale: 1.22, opacity: 0.5)
            if activityMotif.shouldShakeOnTransition {
                shakeCamera()
            }
        case .dirty:
            let color = themedColor(activityMotif.transitionSpell?.nsColor ?? SpellSchool.pressure.nsColor)
            arenaRing(radius: 4.4, color: color.withAlphaComponent(0.58), duration: 0.85, scale: 1.18, opacity: 0.4)
        case .success, .recovery:
            let color = themedColor(activityMotif.transitionSpell?.nsColor ?? SpellSchool.verify.nsColor)
            arenaRing(radius: 5.8, color: color.withAlphaComponent(0.58), duration: 1.0, scale: 1.14, opacity: 0.34)
        case .commit:
            historyChains(color: themedColor(activityMotif.transitionSpell?.nsColor ?? SpellSchool.git.nsColor))
        case .clean, .unavailable:
            break
        }
    }

    private func applyCinematicInfluenceChange() {
        stageCamera(currentCameraShot)
        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)

        if isThinking {
            startThinkingTimer(spawnImmediately: false)
        }
    }

    private func themedColor(_ color: NSColor) -> NSColor {
        languageMotif.phaseColor(color)
    }

    private func phaseLightBaseline(for phase: LoopPhase) -> (color: NSColor, intensity: Float) {
        switch phase {
        case .planning:
            return (SpellSchool.scan.nsColor, 520)
        case .developing:
            return (SpellSchool.shell.nsColor, 680)
        case .verifying:
            return (SpellSchool.verify.nsColor, 760)
        case .succeeded:
            return (SpellSchool.verify.nsColor, 760)
        case .failed:
            return (SpellSchool.failure.nsColor, 900)
        case .paused, .cancelled, .idle:
            return (SpellSchool.lifecycle.nsColor, 320)
        }
    }

    private func shakeCamera() {
        shakeUntil = Date().addingTimeInterval(0.22 * Double(cameraShakeScale()))
    }

    private func setPhaseLight(color: NSColor, intensity: Float) {
        guard var light = phaseLightNode.components[PointLightComponent.self] else { return }
        light.color = activityTint(for: color)
        light.intensity = intensity + activityLightBoost()
        phaseLightNode.components.set(light)
    }

    private func activityTint(for color: NSColor) -> NSColor {
        guard let tintSource = activityMotif.tintSource else { return color }
        return color.mixing(with: themedColor(tintSource.nsColor), fraction: CinematicMotif.activityTintBlend)
    }

    private func activityLightBoost() -> Float {
        CinematicTuning.activityLightBoost(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
    }

    private func cameraOrbitScale() -> Float {
        CinematicTuning.cameraOrbitScale(settings: influenceSettings)
    }

    private func cameraPullbackScale() -> Float {
        CinematicTuning.cameraPullbackScale(settings: influenceSettings)
    }

    private func cameraHeightOffset() -> Float {
        CinematicTuning.cameraHeightOffset(settings: influenceSettings)
    }

    private func cameraFollowResponsiveness() -> Float {
        CinematicTuning.cameraFollowResponsiveness(settings: influenceSettings)
    }

    private func cameraFollowFieldOfView() -> Float {
        CinematicTuning.cameraFollowFieldOfView(settings: influenceSettings)
    }

    private func cameraDriftScale() -> Float {
        CinematicTuning.cameraDriftScale(settings: influenceSettings)
    }

    private func cameraShakeScale() -> Float {
        CinematicTuning.cameraShakeScale(settings: influenceSettings)
    }

    private func setPointLight(color: NSColor, intensity: Float, on entity: Entity) {
        guard var light = entity.components[PointLightComponent.self] else { return }
        light.color = color
        light.intensity = intensity
        entity.components.set(light)
    }

    private func setGlow(_ color: NSColor, opacity: Float = 1, on entity: Entity) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = [glowMaterial(color, opacity: opacity)]
        entity.components.set(model)
    }

    private func stageCamera(_ shot: CinematicCameraShot, animated: Bool = true) {
        currentCameraShot = shot
        let position = cameraPosition(for: shot)
        let fieldOfView = cameraFieldOfView(for: shot)
        let duration = cameraTransitionDuration(for: shot)

        if animated {
            cameraAnimation = CameraAnimation(
                startPosition: cameraPosition,
                endPosition: position,
                startFieldOfView: cameraFieldOfView,
                endFieldOfView: fieldOfView,
                duration: duration
            )
        } else {
            cameraAnimation = nil
            cameraPosition = position
            cameraFieldOfView = fieldOfView
            updateCameraEntity()
        }
    }

    private func cameraPosition(for shot: CinematicCameraShot) -> SIMD3<Float> {
        CinematicTuning.cameraPosition(for: shot, settings: influenceSettings)
    }

    private func cameraFieldOfView(for shot: CinematicCameraShot) -> Float {
        CinematicTuning.cameraFieldOfView(for: shot, settings: influenceSettings)
    }

    private func cameraTransitionDuration(for shot: CinematicCameraShot) -> TimeInterval {
        CinematicTuning.cameraTransitionDuration(for: shot, settings: influenceSettings)
    }

    private func trackTarget(_ target: SIMD3<Float>, duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        wizardFacingTarget = target
        wizardFacingUntil = until
        followCameraTarget = target
        followCameraUntil = until
    }

    private func performCastPose(spell: SpellSchool, duration: TimeInterval) {
        let staffPitch: Float = spell == .failure ? -0.56 : -0.42
        let staffWindup = simd_quatf(angle: staffPitch, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: -0.38, axis: SIMD3<Float>(0, 0, 1))
        let rightArmWindup = simd_quatf(angle: -0.92, axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: -0.16, axis: SIMD3<Float>(1, 0, 0))
        let leftArmBrace = simd_quatf(angle: 0.82, axis: SIMD3<Float>(0, 0, 1))
        let headDip = simd_quatf(angle: -0.08, axis: SIMD3<Float>(1, 0, 0))

        animate(staffPivotNode, toOrientation: staffWindup, duration: 0.12, timing: .easeOut)
        animate(rightArmNode, toOrientation: rightArmWindup, duration: 0.12, timing: .easeOut)
        animate(leftArmNode, toOrientation: leftArmBrace, duration: 0.16, timing: .easeOut)
        animate(headNode, toOrientation: headDip, duration: 0.14, timing: .easeOut)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self else { return }
            self.animate(self.staffPivotNode, toOrientation: self.staffIdleOrientation, duration: 0.28, timing: .easeInOut)
            self.animate(self.rightArmNode, toOrientation: self.rightArmIdleOrientation, duration: 0.28, timing: .easeInOut)
            self.animate(self.leftArmNode, toOrientation: self.leftArmIdleOrientation, duration: 0.34, timing: .easeInOut)
            self.animate(self.headNode, toOrientation: simd_quatf(), duration: 0.24, timing: .easeInOut)
        }
    }

    private func startDisplayTimer() {
        guard displayTimer == nil else { return }
        lastTickDate = Date()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        let delta = min(now.timeIntervalSince(lastTickDate), 1.0 / 15.0)
        lastTickDate = now
        elapsedTime += delta

        updateCamera(delta: delta)
        updateWizard(delta: delta)
        updateEnemyLoops()
        updateSetDressing()
        updateAnimations(delta: delta)
    }

    private func updateCamera(delta: TimeInterval) {
        if let followTarget = activeFollowTarget() {
            cameraAnimation = nil
            let wizardPosition = wizardNode.position(relativeTo: nil)
            let direction = horizontalDirection(from: wizardPosition, to: followTarget) ?? [0, 0, 1]
            let side = SIMD3<Float>(-direction.z, 0, direction.x)
            let orbit = side * ((0.72 + sin(Float(elapsedTime) * 0.42) * 0.36) * cameraOrbitScale())
            let pullback: Float = (isThinking ? 5.9 : 5.35) * cameraPullbackScale()
            let desired = wizardPosition - direction * pullback + orbit + [0, 2.28 + cameraHeightOffset(), 0]
            let factor = min(1, Float(delta) * cameraFollowResponsiveness())
            cameraPosition = mix(cameraPosition, desired, factor)
            cameraFieldOfView += (cameraFollowFieldOfView() - cameraFieldOfView) * factor
        } else if var animation = cameraAnimation {
            animation.elapsed += delta
            let progress = animation.duration <= 0 ? 1 : min(Float(animation.elapsed / animation.duration), 1)
            let eased = ease(progress, timing: .easeInOut)
            cameraPosition = mix(animation.startPosition, animation.endPosition, eased)
            cameraFieldOfView = animation.startFieldOfView + (animation.endFieldOfView - animation.startFieldOfView) * eased
            cameraAnimation = progress >= 1 ? nil : animation
        }

        updateCameraEntity()
    }

    private func updateCameraEntity() {
        let driftScale = cameraDriftScale()
        var cameraOffset = SIMD3<Float>(
            sin(Float(elapsedTime) * 1.5) * 0.12 * driftScale,
            sin(Float(elapsedTime) * 1.1) * 0.05 * driftScale,
            cos(Float(elapsedTime) * 1.2) * 0.09 * driftScale
        )

        if Date() < shakeUntil {
            let shakeScale = cameraShakeScale()
            cameraOffset += SIMD3<Float>(
                Float.random(in: -0.16...0.16) * shakeScale,
                Float.random(in: -0.05...0.05) * shakeScale,
                0
            )
        }

        let finalPosition = cameraPosition + cameraOffset
        let lookTarget = cameraLookTarget()
        cameraEntity.look(at: lookTarget, from: finalPosition, relativeTo: nil)

        if var camera = cameraEntity.components[PerspectiveCameraComponent.self] {
            camera.fieldOfViewInDegrees = cameraFieldOfView
            cameraEntity.components.set(camera)
        }
    }

    private func updateWizard(delta: TimeInterval) {
        let idleY = sin(Float(elapsedTime) * 2.85) * 0.04
        if isThinking {
            let path: [SIMD3<Float>] = [
                [-1.4, 0, 0.6],
                [-0.2, 0, -1.0],
                [1.35, 0, -0.2],
                [0.45, 0, 1.1],
                [0, 0, 0]
            ]
            let segmentDuration: Float = 1.05
            let cycle = Float(elapsedTime).truncatingRemainder(dividingBy: segmentDuration * Float(path.count))
            let index = min(Int(cycle / segmentDuration), path.count - 1)
            let nextIndex = (index + 1) % path.count
            let localT = ease((cycle - Float(index) * segmentDuration) / segmentDuration, timing: .easeInOut)
            let base = mix(path[index], path[nextIndex], localT)
            wizardNode.position = base + [0, idleY, 0]
        } else if animations.contains(where: { $0.entity === wizardNode }) {
            wizardNode.position.y += idleY * 0.02
        } else {
            wizardNode.position.y = idleY
        }

        staffOrbBoost = max(0, staffOrbBoost - Float(delta) * 1.8)
        let orbPulse = 1 + sin(Float(elapsedTime) * 5.6) * 0.12 + staffOrbBoost
        staffOrbNode.scale = SIMD3<Float>(repeating: orbPulse)
        headNode.position.y = 1.45 + idleY * 0.18
        hatNode.position.y = 1.78 + idleY * 0.24

        if let target = activeWizardTarget() {
            faceWizard(toward: target)
        }
    }

    private func activeWizardTarget() -> SIMD3<Float>? {
        if Date() < wizardFacingUntil, let wizardFacingTarget {
            return wizardFacingTarget
        }
        if isThinking {
            return closestEnemy(in: Array(enemyRoot.children).filter { $0.name != "dyingEnemy" })?.position(relativeTo: nil)
        }
        return nil
    }

    private func activeFollowTarget() -> SIMD3<Float>? {
        if Date() < followCameraUntil, let followCameraTarget {
            return followCameraTarget
        }
        if isThinking && influenceSettings.cameraStyle != .steady {
            return activeWizardTarget()
        }
        return nil
    }

    private func cameraLookTarget() -> SIMD3<Float> {
        let wizardPosition = wizardNode.position(relativeTo: nil)
        guard let target = activeFollowTarget() else {
            return wizardPosition + [0, 0.9, 0]
        }
        return mix(wizardPosition, target, 0.56) + [0, 0.84, 0]
    }

    private func faceWizard(toward target: SIMD3<Float>) {
        let position = wizardNode.position(relativeTo: nil)
        guard let direction = horizontalDirection(from: position, to: target) else { return }
        let lookTarget = position + direction
        wizardNode.look(at: lookTarget, from: position, relativeTo: nil, forward: .positiveZ)
    }

    private func horizontalDirection(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SIMD3<Float>? {
        let delta = SIMD3<Float>(end.x - start.x, 0, end.z - start.z)
        let length = simd_length(delta)
        guard length > 0.001 else { return nil }
        return delta / length
    }

    private func updateEnemyLoops() {
        let enemies = Array(enemyRoot.children)
        let wizardPosition = wizardNode.position(relativeTo: nil)
        let now = Date()
        for (index, enemy) in enemies.enumerated() where enemy.name != "dyingEnemy" {
            let id = ObjectIdentifier(enemy)
            let isSlowed = slowedEnemies[id].map { $0 > now } ?? false
            let isStunned = stunnedEnemies[id].map { $0 > now } ?? false
            let bobSpeed: Float = isStunned ? 0.55 : (isSlowed ? 0.95 : 2.1)
            let bobHeight: Float = isStunned ? 0.016 : (isSlowed ? 0.028 : 0.045)
            let baseY = Float(0.45) + sin(Float(elapsedTime) * bobSpeed + Float(index)) * bobHeight
            enemy.position.y = baseY
            enemy.look(at: wizardPosition + [0, 0.65, 0], from: enemy.position(relativeTo: nil), relativeTo: nil, forward: .positiveZ)
            if let aura = enemy.children.first(where: { $0.name == "enemyAura" }) {
                let pulseSpeed: Float = isStunned ? 1.1 : (isSlowed ? 2.2 : 4.2)
                let pulse = 1.05 + sin(Float(elapsedTime) * pulseSpeed + Float(index)) * (isStunned ? 0.07 : 0.13)
                aura.scale = SIMD3<Float>(repeating: pulse)
                aura.orientation = simd_quatf(angle: Float(elapsedTime) * (isSlowed ? 1.1 : 2.6) + Float(index), axis: [0, 1, 0])
            }
        }
    }

    private func updateSetDressing() {
        for (index, pedestal) in setDressingRoot.children.enumerated() where pedestal.name == "set-pedestal" {
            if let flame = pedestal.children.first(where: { $0.name.hasPrefix("set-flame-") }) {
                let pulse = 1 + sin(Float(elapsedTime) * 4.4 + Float(index)) * 0.12
                flame.scale = [0.72 * pulse, 1.35 + pulse * 0.08, 0.72 * pulse]
            }
        }

        for (index, shard) in setDressingRoot.children.enumerated() where shard.name.hasPrefix("floating-shard-") {
            if let baseY = setDressingBaseHeights[ObjectIdentifier(shard)] {
                shard.position.y = baseY + sin(Float(elapsedTime) * 1.1 + Float(index)) * 0.08
            }
            shard.orientation = shard.orientation * simd_quatf(angle: 0.006 + Float(index) * 0.0007, axis: [0.22, 1, 0.12])
        }
    }

    private func updateAnimations(delta: TimeInterval) {
        guard !animations.isEmpty else { return }

        var pending: [EntityAnimation] = []
        var completions: [() -> Void] = []

        for var animation in animations {
            guard let entity = animation.entity else { continue }
            animation.elapsed += delta

            if animation.elapsed < animation.delay {
                pending.append(animation)
                continue
            }

            let activeElapsed = animation.elapsed - animation.delay
            let progress = animation.duration <= 0 ? 1 : min(Float(activeElapsed / animation.duration), 1)
            let eased = ease(progress, timing: animation.timing)

            if let endPosition = animation.endPosition {
                entity.position = mix(animation.startPosition, endPosition, eased)
            }
            if let endScale = animation.endScale {
                entity.scale = mix(animation.startScale, endScale, eased)
            }
            if let endOrientation = animation.endOrientation {
                entity.orientation = simd_slerp(animation.startOrientation, endOrientation, eased)
            }
            if let endOpacity = animation.endOpacity {
                setOpacity(animation.startOpacity + (endOpacity - animation.startOpacity) * eased, on: entity)
            }

            if progress >= 1 {
                if animation.removeOnCompletion {
                    enemyHealth[ObjectIdentifier(entity)] = nil
                    entity.removeFromParent()
                }
                if let completion = animation.completion {
                    completions.append(completion)
                }
            } else {
                pending.append(animation)
            }
        }

        animations = pending
        completions.forEach { $0() }
    }

    private func animate(
        _ entity: Entity,
        toPosition: SIMD3<Float>? = nil,
        toScale: SIMD3<Float>? = nil,
        toOrientation: simd_quatf? = nil,
        toOpacity: Float? = nil,
        duration: TimeInterval,
        delay: TimeInterval = 0,
        timing: EntityAnimation.Timing = .easeInOut,
        removeOnCompletion: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        animations.append(
            EntityAnimation(
                entity: entity,
                startPosition: entity.position,
                endPosition: toPosition,
                startScale: entity.scale,
                endScale: toScale,
                startOrientation: entity.orientation,
                endOrientation: toOrientation,
                startOpacity: opacity(of: entity),
                endOpacity: toOpacity,
                duration: duration,
                delay: delay,
                timing: timing,
                removeOnCompletion: removeOnCompletion,
                completion: completion
            )
        )
    }

    private func cancelMotion(for entity: Entity) {
        animations.removeAll { $0.entity === entity }
    }

    private func opacity(of entity: Entity) -> Float {
        entity.components[OpacityComponent.self]?.opacity ?? 1
    }

    private func setOpacity(_ opacity: Float, on entity: Entity) {
        entity.components.set(OpacityComponent(opacity: max(0, min(1, opacity))))
    }

    private func ease(_ value: Float, timing: EntityAnimation.Timing) -> Float {
        let clamped = max(0, min(1, value))
        switch timing {
        case .linear:
            return clamped
        case .easeIn:
            return clamped * clamped
        case .easeOut:
            let inverse = 1 - clamped
            return 1 - inverse * inverse
        case .easeInOut:
            return clamped * clamped * (3 - 2 * clamped)
        }
    }

    private func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * t
    }

    private func material(diffuse: NSColor, emission: NSColor? = nil, opacity: Float = 1) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: diffuse.withAlphaComponent(CGFloat(opacity)))
        material.roughness = 0.68
        material.metallic = 0.12
        material.specular = 0.35
        if let emission {
            material.emissiveColor = .init(color: emission)
            material.emissiveIntensity = 1.4
        }
        if opacity < 0.999 || diffuse.alphaComponent < 0.999 {
            material.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity))
        }
        return material
    }

    private func obsidianFloorMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: NSColor(calibratedRed: 0.004, green: 0.004, blue: 0.007, alpha: 1))
        material.roughness = 0.94
        material.metallic = 0.02
        material.specular = 0.08
        material.emissiveColor = .init(color: NSColor(calibratedRed: 0.001, green: 0.001, blue: 0.004, alpha: 1))
        material.emissiveIntensity = 0.65
        return material
    }

    private func glowMaterial(_ color: NSColor, opacity: Float = 1) -> UnlitMaterial {
        var material = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)), applyPostProcessToneMap: false)
        if opacity < 0.999 || color.alphaComponent < 0.999 {
            material.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity))
        }
        return material
    }

    private func textureMaterial(_ name: String, tint: NSColor, opacity: Float = 1) -> UnlitMaterial? {
        guard let image = resourceImage(name),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let texture = try? TextureResource(
                image: cgImage,
                withName: name,
                options: .init(semantic: .color)
              ) else {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear

        let sampler = MaterialParameters.Texture.Sampler(samplerDescriptor)
        let textureParameter = MaterialParameters.Texture(texture, sampler: sampler)
        var material = UnlitMaterial(color: tint.withAlphaComponent(CGFloat(opacity)), applyPostProcessToneMap: false)
        material.color = .init(tint: tint.withAlphaComponent(CGFloat(opacity)), texture: textureParameter)
        if opacity < 0.999 || tint.alphaComponent < 0.999 {
            material.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity))
        }
        material.faceCulling = .none
        return material
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

    private func curvedWallMesh(radius: Float, height: Float, arc: Float, segments: Int = 72, bottomY: Float = 0) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for segment in 0...segments {
            let t = Float(segment) / Float(segments)
            let theta = -arc * 0.5 + arc * t
            let x = sin(theta) * radius
            let z = -cos(theta) * radius
            let normal = simd_normalize(SIMD3<Float>(-sin(theta), 0, cos(theta)))

            positions.append([x, bottomY, z])
            normals.append(normal)
            uvs.append([t, 0])

            positions.append([x, bottomY + height, z])
            normals.append(normal)
            uvs.append([t, 1])
        }

        for segment in 0..<segments {
            let lower = UInt32(segment * 2)
            let upper = lower + 1
            let nextLower = UInt32((segment + 1) * 2)
            let nextUpper = nextLower + 1
            indices.append(contentsOf: [lower, upper, nextUpper, lower, nextUpper, nextLower])
        }

        var descriptor = MeshDescriptor(name: "curved-wall")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        return .generatePlane(width: radius * 1.6, height: height)
    }

    private func circularPlaneMesh(radius: Float, segments: Int = 128) -> MeshResource {
        var positions: [SIMD3<Float>] = [[0, 0, 0]]
        var normals: [SIMD3<Float>] = [[0, 1, 0]]
        var uvs: [SIMD2<Float>] = [[0.5, 0.5]]
        var indices: [UInt32] = []

        for segment in 0..<segments {
            let theta = Float(segment) / Float(segments) * .pi * 2
            let x = cos(theta) * radius
            let z = sin(theta) * radius
            positions.append([x, 0, z])
            normals.append([0, 1, 0])
            uvs.append([0.5 + cos(theta) * 0.5, 0.5 + sin(theta) * 0.5])
        }

        for segment in 0..<segments {
            let current = UInt32(segment + 1)
            let next = UInt32(((segment + 1) % segments) + 1)
            indices.append(contentsOf: [0, current, next])
        }

        var descriptor = MeshDescriptor(name: "circular-plane")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        return .generatePlane(width: radius * 2, depth: radius * 2)
    }

    private func annulusMesh(innerRadius: Float, outerRadius: Float, segments: Int = 128) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for segment in 0..<segments {
            let theta = Float(segment) / Float(segments) * .pi * 2
            let radial = SIMD3<Float>(cos(theta), 0, sin(theta))
            positions.append(radial * innerRadius)
            normals.append([0, 1, 0])
            uvs.append([0.5 + radial.x * innerRadius / (outerRadius * 2), 0.5 + radial.z * innerRadius / (outerRadius * 2)])

            positions.append(radial * outerRadius)
            normals.append([0, 1, 0])
            uvs.append([0.5 + radial.x * 0.5, 0.5 + radial.z * 0.5])
        }

        for segment in 0..<segments {
            let inner = UInt32(segment * 2)
            let outer = inner + 1
            let nextInner = UInt32(((segment + 1) % segments) * 2)
            let nextOuter = nextInner + 1
            indices.append(contentsOf: [inner, outer, nextOuter, inner, nextOuter, nextInner])
        }

        var descriptor = MeshDescriptor(name: "annulus")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        return .generatePlane(width: outerRadius * 2, depth: outerRadius * 2)
    }

    private func torusMesh(ringRadius: Float, pipeRadius: Float) -> MeshResource {
        let majorSegments = 72
        let minorSegments = 10
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for major in 0..<majorSegments {
            let theta = Float(major) / Float(majorSegments) * .pi * 2
            let radial = SIMD3<Float>(cos(theta), 0, sin(theta))
            for minor in 0..<minorSegments {
                let phi = Float(minor) / Float(minorSegments) * .pi * 2
                let normal = simd_normalize(radial * cos(phi) + SIMD3<Float>(0, sin(phi), 0))
                let position = radial * (ringRadius + pipeRadius * cos(phi)) + SIMD3<Float>(0, pipeRadius * sin(phi), 0)
                positions.append(position)
                normals.append(normal)
                uvs.append([Float(major) / Float(majorSegments), Float(minor) / Float(minorSegments)])
            }
        }

        for major in 0..<majorSegments {
            for minor in 0..<minorSegments {
                let nextMajor = (major + 1) % majorSegments
                let nextMinor = (minor + 1) % minorSegments
                let a = UInt32(major * minorSegments + minor)
                let b = UInt32(nextMajor * minorSegments + minor)
                let c = UInt32(nextMajor * minorSegments + nextMinor)
                let d = UInt32(major * minorSegments + nextMinor)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "torus")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        return .generateSphere(radius: max(pipeRadius, 0.01))
    }
}

private struct SetDressingSigilSegment {
    var start: SIMD3<Float>
    var end: SIMD3<Float>
    var radius: Float
    var usesSecondary: Bool
    var opacity: Float

    init(
        _ start: SIMD3<Float>,
        _ end: SIMD3<Float>,
        radius: Float,
        usesSecondary: Bool = false,
        opacity: Float = 0.72
    ) {
        self.start = start
        self.end = end
        self.radius = radius
        self.usesSecondary = usesSecondary
        self.opacity = opacity
    }
}

private struct CameraAnimation {
    var startPosition: SIMD3<Float>
    var endPosition: SIMD3<Float>
    var startFieldOfView: Float
    var endFieldOfView: Float
    var duration: TimeInterval
    var elapsed: TimeInterval = 0
}

private struct EntityAnimation {
    enum Timing {
        case linear
        case easeIn
        case easeOut
        case easeInOut
    }

    weak var entity: Entity?
    var startPosition: SIMD3<Float>
    var endPosition: SIMD3<Float>?
    var startScale: SIMD3<Float>
    var endScale: SIMD3<Float>?
    var startOrientation: simd_quatf
    var endOrientation: simd_quatf?
    var startOpacity: Float
    var endOpacity: Float?
    var duration: TimeInterval
    var delay: TimeInterval
    var elapsed: TimeInterval = 0
    var timing: Timing
    var removeOnCompletion: Bool
    var completion: (() -> Void)?
}

private extension NSColor {
    func mixing(with other: NSColor, fraction: CGFloat) -> NSColor {
        let amount = max(0, min(1, fraction))
        let lhs = usingColorSpace(.deviceRGB) ?? self
        let rhs = other.usingColorSpace(.deviceRGB) ?? other
        return NSColor(
            calibratedRed: lhs.redComponent + (rhs.redComponent - lhs.redComponent) * amount,
            green: lhs.greenComponent + (rhs.greenComponent - lhs.greenComponent) * amount,
            blue: lhs.blueComponent + (rhs.blueComponent - lhs.blueComponent) * amount,
            alpha: lhs.alphaComponent + (rhs.alphaComponent - lhs.alphaComponent) * amount
        )
    }
}
