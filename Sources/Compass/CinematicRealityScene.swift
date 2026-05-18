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
    var worldText: CinematicWorldText
    var briefing: CinematicBriefing
    var commitConstellationPlan: CinematicCommitConstellationPlan
    var recoveryCuePlan: CinematicRecoveryCuePlan
    var idleStoryCyclePlan: CinematicIdleStoryCyclePlan
    var timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan
    var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan
    var runRecapEndCardPlan: CinematicRunRecapEndCardPlan
    var nativeFeedbackCue: CinematicNativeFeedbackCuePlan?

    @StateObject private var host: CinematicRealitySceneHost

    init(
        projectID: UUID,
        lines: [LiveLine],
        phase: LoopPhase,
        isActive: Bool,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        recoveryCuePlan: CinematicRecoveryCuePlan = .none,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan = .none,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan = .none,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil
    ) {
        self.projectID = projectID
        self.lines = lines
        self.phase = phase
        self.isActive = isActive
        self.languageProfile = languageProfile
        self.activityProfile = activityProfile
        self.influenceSettings = influenceSettings
        self.worldText = worldText
        self.briefing = briefing
        self.commitConstellationPlan = commitConstellationPlan
        self.recoveryCuePlan = recoveryCuePlan
        self.idleStoryCyclePlan = idleStoryCyclePlan
        self.timelineSceneFocusPlan = timelineSceneFocusPlan
        self.runRecapSceneFocusPlan = runRecapSceneFocusPlan
        self.runRecapEndCardPlan = runRecapEndCardPlan
        self.nativeFeedbackCue = nativeFeedbackCue
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
                influenceSettings: influenceSettings,
                worldText: worldText,
                briefing: briefing,
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan,
                idleStoryCyclePlan: idleStoryCyclePlan,
                timelineSceneFocusPlan: timelineSceneFocusPlan,
                runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                runRecapEndCardPlan: runRecapEndCardPlan,
                nativeFeedbackCue: nativeFeedbackCue
            )
        } update: { content in
            host.install(in: &content)
            host.update(
                lines: lines,
                phase: phase,
                isActive: isActive,
                languageProfile: languageProfile,
                activityProfile: activityProfile,
                influenceSettings: influenceSettings,
                worldText: worldText,
                briefing: briefing,
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan,
                idleStoryCyclePlan: idleStoryCyclePlan,
                timelineSceneFocusPlan: timelineSceneFocusPlan,
                runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                runRecapEndCardPlan: runRecapEndCardPlan,
                nativeFeedbackCue: nativeFeedbackCue
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
        influenceSettings: CinematicInfluenceSettings,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        recoveryCuePlan: CinematicRecoveryCuePlan,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
    ) {
        coordinator.update(
            lines: lines,
            phase: phase,
            isActive: isActive,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            worldText: worldText,
            briefing: briefing,
            commitConstellationPlan: commitConstellationPlan,
            recoveryCuePlan: recoveryCuePlan,
            idleStoryCyclePlan: idleStoryCyclePlan,
            timelineSceneFocusPlan: timelineSceneFocusPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan,
            nativeFeedbackCue: nativeFeedbackCue
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

    private enum CameraFollowSource {
        case liveCommandOrFile
        case stageAction
    }

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
    private let atmosphereRoot = Entity()
    private let pressureHaloNode = Entity()
    private let atmospherePulseNode = Entity()
    private let backdropTintNode = Entity()
    private let floorTintNode = Entity()
    private let phasePolishRoot = Entity()
    private let commitConstellationRoot = Entity()
    private let portalApertureNode = Entity()
    private let portalFillNode = Entity()
    private let healingAccentNode = Entity()
    private let narrativeCueRoot = Entity()
    private let narrativeQuestPlaqueNode = Entity()
    private let narrativeArenaInscriptionNode = Entity()
    private let narrativeActivityBannerNode = Entity()
    private let runRecapEndCardNode = Entity()
    private let savedRecapArtifactTourNode = Entity()
    private let keyLightNode = Entity()
    private let rimLightNode = Entity()
    private let phaseLightNode = Entity()
    private let rimLightBaseIntensity: Float = 1180

    private var backdropCycloramaNode: ModelEntity?
    private var arenaDiscNode: ModelEntity?
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
    private var worldText = CinematicWorldText.placeholder
    private var briefing = CinematicBriefing.placeholder
    private var recoveryCuePlan = CinematicRecoveryCuePlan.none
    private var nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
    private var setDressingPlan = CinematicSetDressingPlanner.plan(
        languageProfile: .empty,
        activityProfile: .empty,
        influenceSettings: CinematicInfluenceSettings()
    )
    private var appliedTextureRouteState: CinematicSetDressingTextureRouteState?
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
    private var activeCameraShakeScale: Float = 0
    private var staffOrbBoost: Float = 0
    private var currentAtmospherePlan: CinematicStageAtmospherePlan?
    private var currentPhasePolishPlan: CinematicStagePhasePolishPlan?
    private var currentNarrativeCuePlan: CinematicSceneNarrativeCuePlan?
    private var currentCommitConstellationPlan = CinematicCommitConstellationPlan.empty
    private var pendingCommitConstellationFocusPlan: CinematicCommitConstellationPlan.FocusPlan?
    private var activeCommitConstellationFocusPlan: CinematicCommitConstellationPlan.FocusPlan?
    private var commitConstellationFocusUntil = Date.distantPast
    private var currentIdleStoryCyclePlan = CinematicIdleStoryCyclePlan.none
    private var activeIdleStoryCycleDescriptor: CinematicIdleStoryCyclePlan.Descriptor?
    private var activeIdleStoryCycleEndCardDescriptor: CinematicRunRecapEndCardPlan.Descriptor?
    private var activeIdleStoryCycleArtifactTourPlan: CinematicRunRecapShareArtifactTourPlan?
    private var currentTimelineSceneFocusPlan = CinematicTimelineSceneFocusPlan.none
    private var activeTimelineSceneFocusDescriptor: CinematicTimelineSceneFocusPlan.Descriptor?
    private var currentRunRecapSceneFocusPlan = CinematicRunRecapSceneFocusPlan.none
    private var activeRunRecapSceneFocusDescriptor: CinematicRunRecapSceneFocusPlan.Descriptor?
    private var currentRunRecapEndCardPlan = CinematicRunRecapEndCardPlan.none
    private var followCameraSource: CameraFollowSource?
    private var fractureAccentNodes: [Entity] = []
    private var phaseStaffOrientation = simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 0, 1))
    private var phaseLeftArmOrientation = simd_quatf(angle: 0.44, axis: SIMD3<Float>(0, 0, 1))
    private var phaseRightArmOrientation = simd_quatf(angle: -0.34, axis: SIMD3<Float>(0, 0, 1))
    private var phaseHeadOrientation = simd_quatf()
    private var phaseOrbScale: Float = 1
    private var phaseOrbPulseAmplitude: Float = 0.12
    private var phaseOrbPulseCadence: TimeInterval = 4.8
    private let staffIdleOrientation = simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 0, 1))
    private let leftArmIdleOrientation = simd_quatf(angle: 0.44, axis: SIMD3<Float>(0, 0, 1))
    private let rightArmIdleOrientation = simd_quatf(angle: -0.34, axis: SIMD3<Float>(0, 0, 1))
    private let languageSigilBasePosition = SIMD3<Float>(-5.8, 0.035, 5.55)
    private let activitySigilBasePosition = SIMD3<Float>(5.8, 0.035, 5.55)

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
        influenceSettings: CinematicInfluenceSettings,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        recoveryCuePlan: CinematicRecoveryCuePlan,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
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
        let worldTextChanged = worldText != self.worldText
        if worldTextChanged {
            self.worldText = worldText
        }
        let briefingChanged = briefing != self.briefing
        if briefingChanged {
            self.briefing = briefing
        }
        let recoveryCueChanged = recoveryCuePlan != self.recoveryCuePlan
        if recoveryCueChanged {
            self.recoveryCuePlan = recoveryCuePlan
        }
        let nativeFeedbackCueChanged = nativeFeedbackCue?.identifier != self.nativeFeedbackCue?.identifier
        if nativeFeedbackCueChanged {
            self.nativeFeedbackCue = nativeFeedbackCue
        }
        let commitConstellationChanged = commitConstellationPlan != currentCommitConstellationPlan
        let idleStoryCycleChanged = idleStoryCyclePlan != currentIdleStoryCyclePlan
        let timelineFocusChanged = timelineSceneFocusPlan != currentTimelineSceneFocusPlan
        let runRecapFocusChanged = runRecapSceneFocusPlan != currentRunRecapSceneFocusPlan
        let runRecapEndCardChanged = runRecapEndCardPlan != currentRunRecapEndCardPlan
        if languageProfileChanged || activityProfileChanged || influenceChanged {
            setDressingPlan = CinematicSetDressingPlanner.plan(
                languageMotif: languageMotif,
                activityMotif: activityMotif,
                languageProfile: self.languageProfile,
                activityProfile: self.activityProfile,
                influenceSettings: self.influenceSettings
            )
            refreshSetDressingTextureMaterialsIfNeeded()
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
            refreshAtmosphere(animated: false)
            if recoveryCuePlan.hasActionableCue {
                applyRecoveryCueTraits(animated: false)
            }
            applyCommitConstellationPlan(commitConstellationPlan, animated: false)
            stagePendingCommitConstellationFocusIfPossible(lines: lines, animated: false)
            let baseline = phaseLightBaseline(for: phase)
            setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
            applyTimelineSceneFocusPlan(timelineSceneFocusPlan, lines: lines, animated: false)
            applyRunRecapSceneFocusPlan(runRecapSceneFocusPlan, lines: lines, animated: false)
            applyRunRecapEndCardPlan(runRecapEndCardPlan, lines: lines, animated: false)
            applyIdleStoryCyclePlan(idleStoryCyclePlan, lines: lines, animated: false)
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
        if recoveryCueChanged {
            applyRecoveryCueTraits(animated: hasBuiltScene)
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
        if worldTextChanged || briefingChanged || nativeFeedbackCueChanged {
            refreshNarrativeCues(animated: hasBuiltScene)
        }
        if commitConstellationChanged {
            applyCommitConstellationPlan(commitConstellationPlan, animated: hasBuiltScene)
        }
        stagePendingCommitConstellationFocusIfPossible(lines: lines, animated: hasBuiltScene)
        if timelineFocusChanged || commitConstellationChanged {
            applyTimelineSceneFocusPlan(timelineSceneFocusPlan, lines: lines, animated: hasBuiltScene)
        }
        if runRecapFocusChanged || commitConstellationChanged {
            applyRunRecapSceneFocusPlan(runRecapSceneFocusPlan, lines: lines, animated: hasBuiltScene)
        }
        if runRecapEndCardChanged {
            applyRunRecapEndCardPlan(runRecapEndCardPlan, lines: lines, animated: hasBuiltScene)
        }
        if idleStoryCycleChanged || commitConstellationChanged {
            applyIdleStoryCyclePlan(idleStoryCyclePlan, lines: lines, animated: hasBuiltScene)
        }
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
        atmosphereRoot.name = "atmosphere-root"
        narrativeCueRoot.name = "narrative-cue-root"
        commitConstellationRoot.name = "commit-constellation-root"

        buildBackdrop()
        buildArena()
        appliedTextureRouteState = CinematicSetDressingTextureRouteState(
            materialTextureVariants: setDressingPlan.materialTextureVariants
        )
        buildAtmosphere()
        buildNarrativeCueNodes()
        buildSetDressing()
        buildLights()
        buildCamera()
        buildWizard()

        root.addChild(wizardNode)
        root.addChild(enemyRoot)
        root.addChild(atmosphereRoot)
        root.addChild(effectsRoot)
        root.addChild(setDressingRoot)
        root.addChild(narrativeCueRoot)
        root.addChild(commitConstellationRoot)
        refreshAtmosphere(animated: false)
        stageCamera(.home, animated: false)
    }

    private func buildBackdrop() {
        let backdropAsset = setDressingPlan.materialTextureVariants.backdropTextureAsset
        let backdrop = ModelEntity(
            mesh: curvedWallMesh(radius: 31, height: 21, arc: 2.55),
            materials: [
                backdropMaterial(for: backdropAsset)
            ]
        )
        backdrop.name = backdropCycloramaName(for: backdropAsset)
        backdropCycloramaNode = backdrop
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

        let arenaAsset = setDressingPlan.materialTextureVariants.arenaTextureAsset
        let arena = ModelEntity(
            mesh: circularPlaneMesh(radius: 9.55),
            materials: [
                arenaMaterial(for: arenaAsset)
            ]
        )
        arena.name = arenaDiscName(for: arenaAsset)
        arena.position.y = 0.032
        arenaDiscNode = arena
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

    private func refreshSetDressingTextureMaterialsIfNeeded() {
        let refreshPlan = CinematicSetDressingTextureRefreshPlanner.plan(
            appliedState: appliedTextureRouteState,
            setDressingPlan: setDressingPlan
        )

        if refreshPlan.refreshesBackdrop {
            refreshBackdropTextureMaterial(setDressingPlan.materialTextureVariants.backdropTextureAsset)
        }
        if refreshPlan.refreshesArena {
            refreshArenaTextureMaterial(setDressingPlan.materialTextureVariants.arenaTextureAsset)
        }
        appliedTextureRouteState = refreshPlan.nextState
    }

    private func refreshBackdropTextureMaterial(_ asset: CinematicTextureAsset) {
        guard let backdropCycloramaNode else { return }
        backdropCycloramaNode.name = backdropCycloramaName(for: asset)
        setUnlitMaterial(backdropMaterial(for: asset), on: backdropCycloramaNode)
    }

    private func refreshArenaTextureMaterial(_ asset: CinematicTextureAsset) {
        guard let arenaDiscNode else { return }
        arenaDiscNode.name = arenaDiscName(for: asset)
        setUnlitMaterial(arenaMaterial(for: asset), on: arenaDiscNode)
    }

    private func backdropMaterial(for asset: CinematicTextureAsset) -> UnlitMaterial {
        textureMaterial(
            asset.textureName,
            tint: NSColor(calibratedWhite: 0.52, alpha: 1)
        ) ?? backdropFallbackMaterial()
    }

    private func arenaMaterial(for asset: CinematicTextureAsset) -> UnlitMaterial {
        textureMaterial(
            asset.textureName,
            tint: NSColor(calibratedWhite: 0.82, alpha: 1),
            opacity: 0.9
        ) ?? arenaFallbackMaterial()
    }

    private func backdropFallbackMaterial() -> UnlitMaterial {
        glowMaterial(NSColor(calibratedRed: 0.006, green: 0.006, blue: 0.01, alpha: 1))
    }

    private func arenaFallbackMaterial() -> UnlitMaterial {
        glowMaterial(
            NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.052, alpha: 1),
            opacity: 0.48
        )
    }

    private func backdropCycloramaName(for asset: CinematicTextureAsset) -> String {
        "void-cyclorama-\(asset.textureName)"
    }

    private func arenaDiscName(for asset: CinematicTextureAsset) -> String {
        "arena-\(asset.textureName)"
    }

    private func buildAtmosphere() {
        let clear = glowMaterial(NSColor(calibratedWhite: 0, alpha: 0), opacity: 0)

        pressureHaloNode.name = "pressure-atmosphere-halo"
        pressureHaloNode.components.set(
            ModelComponent(
                mesh: torusMesh(ringRadius: 1, pipeRadius: 0.011),
                materials: [clear]
            )
        )
        pressureHaloNode.position.y = 0.09
        pressureHaloNode.components.set(OpacityComponent(opacity: 0))
        atmosphereRoot.addChild(pressureHaloNode)

        atmospherePulseNode.name = "pressure-atmosphere-pulse"
        atmospherePulseNode.components.set(
            ModelComponent(
                mesh: torusMesh(ringRadius: 1, pipeRadius: 0.006),
                materials: [clear]
            )
        )
        atmospherePulseNode.position.y = 0.115
        atmospherePulseNode.components.set(OpacityComponent(opacity: 0))
        atmosphereRoot.addChild(atmospherePulseNode)

        floorTintNode.name = "pressure-atmosphere-floor"
        floorTintNode.components.set(
            ModelComponent(
                mesh: circularPlaneMesh(radius: 13.8),
                materials: [clear]
            )
        )
        floorTintNode.position.y = 0.04
        floorTintNode.components.set(OpacityComponent(opacity: 0))
        atmosphereRoot.addChild(floorTintNode)

        backdropTintNode.name = "pressure-atmosphere-backdrop"
        backdropTintNode.components.set(
            ModelComponent(
                mesh: curvedWallMesh(radius: 30.35, height: 16.8, arc: 2.58, bottomY: 0),
                materials: [clear]
            )
        )
        backdropTintNode.components.set(OpacityComponent(opacity: 0))
        atmosphereRoot.addChild(backdropTintNode)

        buildPhasePolishNodes(clearMaterial: clear)
    }

    private func buildPhasePolishNodes(clearMaterial: UnlitMaterial) {
        phasePolishRoot.name = "phase-polish-root"

        portalApertureNode.name = "phase-polish-portal-aperture"
        portalApertureNode.components.set(
            ModelComponent(
                mesh: torusMesh(ringRadius: 1, pipeRadius: 0.028),
                materials: [clearMaterial]
            )
        )
        portalApertureNode.position = [0, 1.48, -3.2]
        portalApertureNode.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        portalApertureNode.components.set(OpacityComponent(opacity: 0))
        phasePolishRoot.addChild(portalApertureNode)

        portalFillNode.name = "phase-polish-portal-fill"
        portalFillNode.components.set(
            ModelComponent(
                mesh: circularPlaneMesh(radius: 1),
                materials: [clearMaterial]
            )
        )
        portalFillNode.position = [0, 1.48, -3.22]
        portalFillNode.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        portalFillNode.components.set(OpacityComponent(opacity: 0))
        phasePolishRoot.addChild(portalFillNode)

        healingAccentNode.name = "phase-polish-healing-ring"
        healingAccentNode.components.set(
            ModelComponent(
                mesh: torusMesh(ringRadius: 2.25, pipeRadius: 0.018),
                materials: [clearMaterial]
            )
        )
        healingAccentNode.position.y = 0.13
        healingAccentNode.components.set(OpacityComponent(opacity: 0))
        phasePolishRoot.addChild(healingAccentNode)

        let fractureSegments: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([-0.45, 0.075, -0.2], [-3.2, 0.075, -1.35]),
            ([0.32, 0.078, -0.28], [3.1, 0.078, -1.65]),
            ([-0.2, 0.081, 0.32], [-2.35, 0.081, 2.6]),
            ([0.4, 0.084, 0.18], [2.85, 0.084, 2.35]),
            ([0.0, 0.087, -0.5], [0.32, 0.087, -3.55]),
            ([-0.18, 0.09, 0.48], [0.22, 0.09, 3.4])
        ]
        fractureAccentNodes = fractureSegments.enumerated().map { index, segment in
            let node = beamEntity(
                from: segment.0,
                to: segment.1,
                radius: 0.018,
                color: SpellSchool.failure.nsColor,
                opacity: 0
            )
            node.name = "phase-polish-fracture-\(index)"
            phasePolishRoot.addChild(node)
            return node
        }

        atmosphereRoot.addChild(phasePolishRoot)
    }

    private func buildNarrativeCueNodes() {
        narrativeQuestPlaqueNode.name = "narrative-quest-plaque"
        narrativeArenaInscriptionNode.name = "narrative-arena-inscription"
        narrativeActivityBannerNode.name = "narrative-activity-banner"
        runRecapEndCardNode.name = "run-recap-end-card"
        savedRecapArtifactTourNode.name = "saved-recap-artifact-tour"

        for node in [
            narrativeQuestPlaqueNode,
            narrativeArenaInscriptionNode,
            narrativeActivityBannerNode,
            runRecapEndCardNode,
            savedRecapArtifactTourNode
        ] {
            node.components.set(OpacityComponent(opacity: 0))
            narrativeCueRoot.addChild(node)
        }
    }

    private func buildSetDressing() {
        let pedestalSlots = setDressingPlan.languageArchitecture.pedestalSlots

        for index in 0..<CinematicSetDressingPlan.pedestalCountRange.upperBound {
            let position = pedestalSlots.indices.contains(index)
                ? pedestalSlots[index].position
                : .zero
            let pedestal = Entity()
            pedestal.name = "set-pedestal-\(index)"
            pedestal.position = position

            let base = ModelEntity(
                mesh: .generateCylinder(height: 0.28, radius: 0.38),
                materials: [material(diffuse: NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.07, alpha: 1))]
            )
            base.name = "set-pedestal-base"
            base.position.y = 0.14
            pedestal.addChild(base)

            let column = ModelEntity(
                mesh: .generateCylinder(height: 1.05, radius: 0.2),
                materials: [material(diffuse: NSColor(calibratedRed: 0.036, green: 0.038, blue: 0.052, alpha: 1))]
            )
            column.name = "set-pedestal-column"
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
            flame.name = "set-flame-core-\(index)"
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

        let shardSlots = setDressingPlan.languageArchitecture.shardSlots

        for index in 0..<CinematicSetDressingPlan.shardCountRange.upperBound {
            let position = shardSlots.indices.contains(index)
                ? shardSlots[index].position
                : .zero
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
            if shardSlots.indices.contains(index) {
                shard.orientation = shardOrientation(for: shardSlots[index])
            } else {
                shard.orientation = simd_quatf(angle: Float(index) * 0.83, axis: [0.2, 1, 0.12])
            }
            setDressingBaseHeights[ObjectIdentifier(shard)] = position.y
            setDressingRoot.addChild(shard)
        }

        languageSigilRoot.name = "language-sigil-root"
        activitySigilRoot.name = "activity-sigil-root"
        setDressingRoot.addChild(languageSigilRoot)
        setDressingRoot.addChild(activitySigilRoot)
        applySetDressingPlan(animated: false)
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
                intensity: rimLightBaseIntensity,
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
        applyPhaseBeat(stageBeat(for: phase))
    }

    private func stageBeat(for phase: LoopPhase? = nil) -> CinematicStageBeat {
        CinematicStageBeatPlanner.plan(
            phase: phase ?? lastPhase,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
    }

    private func stageEffectPlan(for beat: CinematicStageBeat) -> CinematicStageEffectPlan {
        CinematicStageEffectPlanner.plan(
            beat: beat,
            setDressingPlan: setDressingPlan,
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
        )
    }

    private func stageAtmospherePlan(
        for beat: CinematicStageBeat,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageAtmospherePlan {
        CinematicStageAtmospherePlanner.plan(
            beat: beat,
            setDressingPlan: setDressingPlan,
            stageEffectTuning: tuningMetadata,
            influenceSettings: influenceSettings
        )
    }

    private func stagePhasePolishPlan(
        for beat: CinematicStageBeat,
        effectPlan: CinematicStageEffectPlan,
        atmospherePlan: CinematicStageAtmospherePlan
    ) -> CinematicStagePhasePolishPlan {
        CinematicStagePhasePolishPlanner.plan(
            beat: beat,
            stageEffectTuning: effectPlan.tuningMetadata,
            atmospherePlan: atmospherePlan,
            activityMotif: activityMotif,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
        )
    }

    private func narrativeCuePlan(
        for beat: CinematicStageBeat,
        phasePolishPlan: CinematicStagePhasePolishPlan
    ) -> CinematicSceneNarrativeCuePlan {
        CinematicSceneNarrativeCuePlanner.plan(
            worldText: worldText,
            briefing: briefing,
            stageBeat: beat,
            stagePhasePolishPlan: phasePolishPlan,
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nativeFeedbackCue
        )
    }

    private func refreshAtmosphere(animated: Bool) {
        let beat = stageBeat()
        let effectPlan = stageEffectPlan(for: beat)
        let atmospherePlan = stageAtmospherePlan(for: beat, tuningMetadata: effectPlan.tuningMetadata)
        applyAtmospherePlan(atmospherePlan, animated: animated)
        let phasePolishPlan = stagePhasePolishPlan(for: beat, effectPlan: effectPlan, atmospherePlan: atmospherePlan)
        applyPhasePolishPlan(phasePolishPlan, animated: animated)
        applyNarrativeCuePlan(
            narrativeCuePlan(for: beat, phasePolishPlan: phasePolishPlan),
            animated: animated
        )
    }

    private func applyPhaseBeat(_ beat: CinematicStageBeat) {
        let effectPlan = stageEffectPlan(for: beat)
        let atmospherePlan = stageAtmospherePlan(for: beat, tuningMetadata: effectPlan.tuningMetadata)
        applyAtmospherePlan(atmospherePlan, animated: true)
        let phasePolishPlan = stagePhasePolishPlan(for: beat, effectPlan: effectPlan, atmospherePlan: atmospherePlan)
        applyPhasePolishPlan(phasePolishPlan, animated: true)
        applyNarrativeCuePlan(
            narrativeCuePlan(for: beat, phasePolishPlan: phasePolishPlan),
            animated: true
        )
        if beat.shouldRunVictorySurge {
            victorySurge(using: effectPlan)
            if let recoveryEffect = effectPlan.recoveryEffect {
                applyRecoveryCueEffect(recoveryEffect)
            }
            return
        }

        if beat.kind == .failed {
            stageCamera(beat.cameraShot)
            let baseline = phaseLightBaseline(for: beat.phase)
            setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
            if let cameraShake = effectPlan.phaseEffect.cameraShake {
                shakeCamera(cameraShake)
            }
            applyArenaEffect(effectPlan.phaseEffect)
            if let recoveryEffect = effectPlan.recoveryEffect {
                applyRecoveryCueEffect(recoveryEffect)
            }
            return
        }

        let baseline = phaseLightBaseline(for: beat.phase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
        applyArenaEffect(effectPlan.phaseEffect)
        if let recoveryEffect = effectPlan.recoveryEffect {
            applyRecoveryCueEffect(recoveryEffect)
        }
        stageCamera(beat.cameraShot)
    }

    private func applyArenaEffect(_ effect: CinematicStageEffectPlan.EffectChoreography) {
        let color = themedColor(effect.lightFamily.spell.nsColor)
        if !effect.historyTrails.isEmpty {
            historyChains(effect, color: color)
        } else {
            applyArenaRings(effect.arenaRings, color: color)
        }
        applySparkBursts(effect.sparkBursts, color: color)
        if let pulse = effect.phaseLightPulse {
            pulsePhaseLight(color: color, pulse: pulse)
        }
    }

    private func apply(_ line: LiveLine) {
        let spell = SpellSchool(line: line)

        if line.status == .running {
            if line.kind == .command || line.kind == .fileChange {
                stageCamera(.overShoulder)
                chargeArena(color: spell.nsColor)
                let enemy = spawnEnemy(for: line.id, spell: spell, persistent: true)
                trackTarget(
                    enemy.position(relativeTo: nil),
                    duration: 1.8,
                    source: .liveCommandOrFile
                )
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

    private func victorySurge(using plan: CinematicStageEffectPlan) {
        guard let cadence = plan.phaseEffect.victoryCadence else { return }
        stageCamera(cadence.cameraShot)
        nextAmbientSpawnDate = Date().addingTimeInterval(cadence.ambientSpawnDelay)
        if cadence.shouldVolleyActiveEnemies, !Array(enemyRoot.children).isEmpty {
            castVolley(spell: .verify, failed: false)
        }
        let victoryColor = themedColor(cadence.portalLightFamily.spell.nsColor)
        applyArenaEffect(plan.phaseEffect)
        if cadence.shouldRunPortalPulse {
            portalPulse(color: victoryColor)
        }
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

    private func historyChains(_ effect: CinematicStageEffectPlan.EffectChoreography, color: NSColor) {
        for trail in effect.historyTrails {
            spellTrail(from: trail.start, to: trail.end, spell: trail.lightFamily.spell)
        }
        applyArenaRings(effect.arenaRings, color: color)
    }

    private func applyArenaRings(_ rings: [CinematicStageEffectPlan.ArenaRing], color: NSColor) {
        for ring in rings {
            arenaRing(
                radius: ring.radius,
                color: color.withAlphaComponent(CGFloat(ring.colorAlpha)),
                duration: ring.duration,
                scale: ring.scale,
                opacity: ring.opacity
            )
        }
    }

    private func applySparkBursts(_ sparkBursts: [CinematicStageEffectPlan.SparkBurst], color: NSColor) {
        for spark in sparkBursts {
            sparkBurst(
                at: spark.position,
                color: color.withAlphaComponent(CGFloat(spark.colorAlpha)),
                birthRate: spark.birthRate
            )
        }
    }

    private func arenaRing(radius: Float, color: NSColor, duration: TimeInterval, scale: Float, opacity: Float) {
        let treatment = setDressingPlan.materialTextureVariants.runeMaterialTreatment
        let treatedOpacity = clamped(opacity * treatment.arenaAccentOpacityScale, to: 0...1)
        let treatedScale = max(0.001, scale * treatment.arenaAccentScale)
        let ring = ModelEntity(
            mesh: torusMesh(ringRadius: radius, pipeRadius: 0.018),
            materials: [glowMaterial(color, opacity: treatedOpacity)]
        )
        ring.position.y = 0.055
        ring.components.set(OpacityComponent(opacity: treatedOpacity))
        effectsRoot.addChild(ring)
        animate(ring, toScale: SIMD3<Float>(repeating: treatedScale), toOpacity: 0, duration: duration, removeOnCompletion: true)
    }

    private func pulsePhaseLight(color: NSColor, intensity: Float, duration: TimeInterval) {
        setPhaseLight(color: color, intensity: intensity)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.setPhaseLight(color: color, intensity: 360)
        }
    }

    private func pulsePhaseLight(
        color: NSColor,
        pulse: CinematicStageEffectPlan.PhaseLightPulse
    ) {
        setPhaseLight(color: color, intensity: pulse.intensity)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(pulse.duration))
            self?.setPhaseLight(color: color, intensity: pulse.resetIntensity)
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
        setDressingPlan.ambientSpawnCadence
    }

    private func ambientEnemyLimit() -> Int {
        setDressingPlan.ambientEnemyLimit
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
                historyChains(
                    CinematicStageEffectPlanner.historyChainsEffect(),
                    color: spell.nsColor
                )
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
        languageSigilRoot.name = "language-sigil-\(setDressingPlan.languageArchitecture.identifier)"
        languageSigilRoot.position = languageSigilBasePosition
        languageSigilRoot.scale = SIMD3<Float>(repeating: 1)

        let color = setDressingTint(
            languageMotif.accent,
            fraction: setDressingPlan.pedestalFlames.activityTintFraction
        )
        let secondary = setDressingTint(
            languageMotif.secondaryAccent,
            fraction: setDressingPlan.pedestalFlames.activityTintFraction
        )
        addSigilBase(
            to: languageSigilRoot,
            color: color,
            secondary: secondary,
            radius: setDressingPlan.runeIntensity.languageBaseRadius
        )
        addSigilSegments(
            languageSigilSegments(for: languageMotif.style),
            to: languageSigilRoot,
            color: color,
            secondary: secondary,
            radiusScale: setDressingPlan.runeIntensity.segmentRadiusScale,
            opacityScale: setDressingPlan.runeIntensity.segmentOpacityScale
        )
        addSigilCore(
            to: languageSigilRoot,
            color: secondary,
            scale: SIMD3<Float>(1, 1.35, 1) * setDressingPlan.runeIntensity.coreScale
        )
    }

    private func rebuildActivitySigil() {
        clearChildren(of: activitySigilRoot)
        activitySigilRoot.name = "activity-sigil-\(setDressingPlan.activityMarker.identifier)"
        activitySigilRoot.position = activitySigilBasePosition
        activitySigilRoot.scale = SIMD3<Float>(repeating: 1)

        let color = activityColor(for: activityMotif)
        let secondary = activityMotif.tintSource.map { themedColor($0.nsColor) } ?? languageMotif.secondaryAccent
        let treatment = setDressingPlan.materialTextureVariants.runeMaterialTreatment
        addSigilBase(
            to: activitySigilRoot,
            color: color,
            secondary: secondary,
            radius: setDressingPlan.runeIntensity.activityBaseRadius,
            treatment: treatment
        )
        addSigilSegments(
            activitySigilSegments(for: activityMotif.style),
            to: activitySigilRoot,
            color: color,
            secondary: secondary,
            radiusScale: setDressingPlan.runeIntensity.segmentRadiusScale * treatment.segmentRadiusScale,
            opacityScale: setDressingPlan.runeIntensity.segmentOpacityScale * treatment.segmentOpacityScale
        )
        let activityCoreBaseScale: SIMD3<Float> = activityMotif.eventKind == .unavailable
            ? [0.62, 0.62, 0.62]
            : [0.9, 1.1, 0.9]
        addSigilCore(
            to: activitySigilRoot,
            color: secondary,
            scale: activityCoreBaseScale * setDressingPlan.runeIntensity.coreScale,
            opacity: treatment.coreOpacity
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
        radius: Float,
        treatment: CinematicSetDressingPlan.RuneMaterialTreatment? = nil
    ) {
        let floorEmissionOpacity = treatment?.floorEmissionOpacity ?? 0.12
        let plinthOpacity = treatment?.plinthOpacity ?? 1
        let ringOpacityScale = treatment?.ringOpacityScale ?? 1
        let plinth = ModelEntity(
            mesh: .generateCylinder(height: 0.1, radius: radius),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.028, green: 0.03, blue: 0.042, alpha: 1),
                    emission: color.withAlphaComponent(CGFloat(floorEmissionOpacity)),
                    opacity: plinthOpacity
                )
            ]
        )
        plinth.name = "sigil-plinth"
        plinth.position.y = 0.05
        root.addChild(plinth)

        let outerRing = ModelEntity(
            mesh: torusMesh(ringRadius: radius * 1.05, pipeRadius: 0.012),
            materials: [
                glowMaterial(
                    color.withAlphaComponent(0.72),
                    opacity: clamped(0.58 * ringOpacityScale, to: 0...1)
                )
            ]
        )
        outerRing.name = "sigil-outer-ring"
        outerRing.position.y = 0.12
        root.addChild(outerRing)

        let innerRing = ModelEntity(
            mesh: torusMesh(ringRadius: radius * 0.42, pipeRadius: 0.008),
            materials: [
                glowMaterial(
                    secondary.withAlphaComponent(0.64),
                    opacity: clamped(0.46 * ringOpacityScale, to: 0...1)
                )
            ]
        )
        innerRing.name = "sigil-inner-ring"
        innerRing.position.y = 0.145
        root.addChild(innerRing)
    }

    private func addSigilCore(
        to root: Entity,
        color: NSColor,
        scale: SIMD3<Float>,
        opacity: Float = 0.84
    ) {
        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.075),
            materials: [glowMaterial(color, opacity: opacity)]
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
        secondary: NSColor,
        radiusScale: Float,
        opacityScale: Float
    ) {
        for segment in segments {
            let beam = beamEntity(
                from: segment.start,
                to: segment.end,
                radius: segment.radius * radiusScale,
                color: segment.usesSecondary ? secondary : color,
                opacity: max(0, min(1, segment.opacity * opacityScale))
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

    private func applySetDressingPlan(animated: Bool) {
        applyPedestalFlames()
        applyFloatingShards()
        rebuildLanguageSigil()
        rebuildActivitySigil()

        if animated, activityMotif.eventKind != .unavailable {
            let color = activityMotif.transitionSpell.map { themedColor($0.nsColor) }
                ?? setDressingTint(languageMotif.accent, fraction: setDressingPlan.pedestalFlames.activityTintFraction)
            arenaRing(
                radius: 7.2,
                color: color.withAlphaComponent(0.44),
                duration: max(0.58, setDressingPlan.animationCadence.activityPulseDuration * 0.9),
                scale: 1.08 * setDressingPlan.runeIntensity.activityPulseScale,
                opacity: 0.26
            )
        }
    }

    private func applyPedestalFlames() {
        let plan = setDressingPlan.pedestalFlames
        let slots = setDressingPlan.languageArchitecture.pedestalSlots
        let rimColor = setDressingTint(languageMotif.accent, fraction: plan.activityTintFraction)
        let flameColor = setDressingTint(languageMotif.secondaryAccent, fraction: plan.activityTintFraction)
        let stone = pedestalStoneColors()

        for pedestal in setDressingRoot.children where pedestal.name.hasPrefix("set-pedestal-") {
            let index = setDressingIndex(in: pedestal.name, prefix: "set-pedestal-") ?? 0
            if slots.indices.contains(index) {
                let slot = slots[index]
                pedestal.position = slot.position
                pedestal.orientation = simd_quatf(angle: slot.yawRadians, axis: [0, 1, 0])
            }
            let isActive = index < plan.pedestalCount && slots.indices.contains(index)
            setOpacity(isActive ? 1 : 0, on: pedestal)

            for child in pedestal.children {
                if child.name == "set-pedestal-base" {
                    setMaterial(
                        material(diffuse: stone.base, emission: stone.emission),
                        on: child
                    )
                } else if child.name == "set-pedestal-column" {
                    setMaterial(
                        material(diffuse: stone.column, emission: stone.emission.withAlphaComponent(0.7)),
                        on: child
                    )
                } else if child.name == "set-flame-rim" {
                    setGlow(rimColor, opacity: isActive ? plan.rimOpacity : 0, on: child)
                } else if child.name.hasPrefix("set-flame-light-") {
                    setPointLight(color: rimColor, intensity: isActive ? plan.flameLightIntensity : 0, on: child)
                } else if child.name.hasPrefix("set-flame-core-") {
                    setGlow(flameColor, opacity: isActive ? plan.flameOpacity : 0, on: child)
                    child.scale = [
                        plan.flameXZScale,
                        plan.flameHeightScale,
                        plan.flameXZScale
                    ]
                }
            }
        }
    }

    private func applyFloatingShards() {
        let plan = setDressingPlan.floatingShards
        let slots = setDressingPlan.languageArchitecture.shardSlots
        let shardColor = setDressingTint(languageMotif.accent, fraction: plan.activityTintFraction)
        let shardDiffuse = shardStoneColor()

        for shard in setDressingRoot.children where shard.name.hasPrefix("floating-shard-") {
            let index = setDressingIndex(in: shard.name, prefix: "floating-shard-") ?? 0
            if slots.indices.contains(index) {
                let slot = slots[index]
                shard.position = slot.position
                shard.orientation = shardOrientation(for: slot)
                setDressingBaseHeights[ObjectIdentifier(shard)] = slot.position.y
            }
            let isActive = index < plan.shardCount && slots.indices.contains(index)
            setOpacity(isActive ? plan.opacity : 0, on: shard)
            shard.scale = SIMD3<Float>(repeating: isActive ? plan.scale : 0.001)
            setMaterial(
                material(
                    diffuse: shardDiffuse,
                    emission: shardColor.withAlphaComponent(CGFloat(plan.emissionOpacity))
                ),
                on: shard
            )
        }
    }

    private func applyLanguageTheme(animated: Bool) {
        let accent = setDressingTint(
            languageMotif.accent,
            fraction: setDressingPlan.pedestalFlames.activityTintFraction
        )
        setGlow(accent, on: staffOrbNode)
        applySetDressingPlan(animated: animated)
        refreshAtmosphere(animated: animated)

        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
        if animated, languageMotif.language != .unknown {
            arenaRing(radius: 6.6, color: accent.withAlphaComponent(0.72), duration: 1.05, scale: 1.18, opacity: 0.34)
        }
    }

    private func applyActivityTraits(animated: Bool) {
        applySetDressingPlan(animated: animated)
        let beat = stageBeat()
        let effectPlan = stageEffectPlan(for: beat)
        let atmospherePlan = stageAtmospherePlan(for: beat, tuningMetadata: effectPlan.tuningMetadata)
        applyAtmospherePlan(atmospherePlan, animated: animated)
        let phasePolishPlan = stagePhasePolishPlan(for: beat, effectPlan: effectPlan, atmospherePlan: atmospherePlan)
        applyPhasePolishPlan(phasePolishPlan, animated: animated)
        applyNarrativeCuePlan(
            narrativeCuePlan(for: beat, phasePolishPlan: phasePolishPlan),
            animated: animated
        )
        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
        guard animated else { return }
        if let activityEffect = effectPlan.activityEffect {
            applyActivityAccent(activityEffect)
        }
        if let recoveryEffect = effectPlan.recoveryEffect {
            applyRecoveryCueEffect(recoveryEffect)
        }
    }

    private func applyRecoveryCueTraits(animated: Bool) {
        let beat = stageBeat()
        let effectPlan = stageEffectPlan(for: beat)
        let atmospherePlan = stageAtmospherePlan(for: beat, tuningMetadata: effectPlan.tuningMetadata)
        applyAtmospherePlan(atmospherePlan, animated: animated)
        let phasePolishPlan = stagePhasePolishPlan(for: beat, effectPlan: effectPlan, atmospherePlan: atmospherePlan)
        applyPhasePolishPlan(phasePolishPlan, animated: animated)
        applyNarrativeCuePlan(
            narrativeCuePlan(for: beat, phasePolishPlan: phasePolishPlan),
            animated: animated
        )
        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)
        guard animated, let recoveryEffect = effectPlan.recoveryEffect else { return }
        applyRecoveryCueEffect(recoveryEffect)
    }

    private func applyActivityAccent(_ effect: CinematicStageEffectPlan.EffectChoreography) {
        let color = themedColor(effect.lightFamily.spell.nsColor)
        if !effect.historyTrails.isEmpty {
            historyChains(effect, color: color)
        } else {
            applyArenaRings(effect.arenaRings, color: color)
        }
        applySparkBursts(effect.sparkBursts, color: color)
        if let pulse = effect.phaseLightPulse {
            pulsePhaseLight(color: color, pulse: pulse)
        }
        if let cameraShake = effect.cameraShake {
            shakeCamera(cameraShake)
        }
    }

    private func applyRecoveryCueEffect(_ effect: CinematicStageEffectPlan.EffectChoreography) {
        applyArenaEffect(effect)
        if let cameraShake = effect.cameraShake {
            shakeCamera(cameraShake)
        }
    }

    private func applyAtmospherePlan(_ plan: CinematicStageAtmospherePlan, animated: Bool) {
        currentAtmospherePlan = plan

        let haloColor = atmosphereColor(plan.floorTint)
            .withAlphaComponent(CGFloat(plan.pressureHalo.colorAlpha))
        setGlow(haloColor, opacity: plan.pressureHalo.opacity, on: pressureHaloNode)
        pressureHaloNode.scale = atmosphereScale(
            radius: plan.pressureHalo.radius,
            scale: plan.pressureHalo.scale
        )
        setOpacity(plan.pressureHalo.opacity, on: pressureHaloNode)

        let pulseColor = atmosphereColor(plan.floorTint)
            .withAlphaComponent(CGFloat(plan.pressureLighting.colorAlpha))
        setGlow(pulseColor, opacity: plan.atmosphericPulse.opacity, on: atmospherePulseNode)
        atmospherePulseNode.scale = atmosphereScale(
            radius: plan.pressureHalo.radius * 0.76,
            scale: plan.pressureHalo.scale
        )
        setOpacity(plan.atmosphericPulse.opacity, on: atmospherePulseNode)

        setGlow(atmosphereColor(plan.backdropTint), opacity: plan.backdropTint.opacity, on: backdropTintNode)
        setOpacity(plan.backdropTint.opacity, on: backdropTintNode)
        let runeTreatment = setDressingPlan.materialTextureVariants.runeMaterialTreatment
        let floorOpacity = clamped(plan.floorTint.opacity * runeTreatment.ringOpacityScale, to: 0...1)
        let floorColor = atmosphereColor(plan.floorTint)
            .withAlphaComponent(CGFloat(runeTreatment.floorEmissionOpacity))
        setGlow(floorColor, opacity: floorOpacity, on: floorTintNode)
        setOpacity(floorOpacity, on: floorTintNode)

        let rimColor = themedColor(stageBeat().lightFamily.spell.nsColor)
            .mixing(with: atmosphereColor(plan.floorTint), fraction: CGFloat(plan.floorTint.blendFraction))
        setPointLight(
            color: rimColor,
            intensity: rimLightBaseIntensity + plan.pressureLighting.rimLightPressureBoost,
            on: rimLightNode
        )

        if animated, plan.pressureHalo.opacity > 0 {
            animate(
                pressureHaloNode,
                toScale: atmosphereScale(
                    radius: plan.pressureHalo.radius,
                    scale: plan.pressureHalo.scale + plan.atmosphericPulse.amplitude
                ),
                duration: min(0.65, plan.atmosphericPulse.cadence * 0.32),
                timing: .easeOut
            )
        }
    }

    private func applyPhasePolishPlan(_ plan: CinematicStagePhasePolishPlan, animated: Bool) {
        currentPhasePolishPlan = plan
        phaseStaffOrientation = staffOrientation(for: plan.wizardPose)
        phaseLeftArmOrientation = armOrientation(plan.wizardPose.leftArmLift)
        phaseRightArmOrientation = armOrientation(plan.wizardPose.rightArmLift)
        phaseHeadOrientation = simd_quatf(angle: plan.wizardPose.headTilt, axis: [1, 0, 0])
        phaseOrbScale = plan.staffOrb.scale
        phaseOrbPulseAmplitude = plan.staffOrb.pulseAmplitude
        phaseOrbPulseCadence = plan.cadence.orbPulseCadence

        let poseDuration = min(0.78, max(0.18, plan.cadence.poseCadence * 0.18))
        if animated {
            animate(staffPivotNode, toOrientation: phaseStaffOrientation, duration: poseDuration, timing: .easeInOut)
            animate(leftArmNode, toOrientation: phaseLeftArmOrientation, duration: poseDuration, timing: .easeInOut)
            animate(rightArmNode, toOrientation: phaseRightArmOrientation, duration: poseDuration, timing: .easeInOut)
            animate(headNode, toOrientation: phaseHeadOrientation, duration: min(0.46, poseDuration), timing: .easeInOut)
        } else {
            staffPivotNode.orientation = phaseStaffOrientation
            leftArmNode.orientation = phaseLeftArmOrientation
            rightArmNode.orientation = phaseRightArmOrientation
            headNode.orientation = phaseHeadOrientation
        }

        let orbColor = themedColor(plan.staffOrb.lightFamily.spell.nsColor)
            .withAlphaComponent(CGFloat(plan.staffOrb.emission))
        setGlow(orbColor, opacity: max(0.001, plan.staffOrb.emission), on: staffOrbNode)

        let portalColor = themedColor(plan.portalBackdrop.lightFamily.spell.nsColor)
        setGlow(
            portalColor.withAlphaComponent(CGFloat(plan.portalBackdrop.portalOpacity)),
            opacity: plan.portalBackdrop.portalOpacity,
            on: portalApertureNode
        )
        setGlow(
            portalColor.withAlphaComponent(CGFloat(plan.portalBackdrop.portalOpacity * 0.42)),
            opacity: plan.portalBackdrop.portalOpacity * 0.42,
            on: portalFillNode
        )

        let fractureColor = themedColor(plan.fractureRecovery.lightFamily.spell.nsColor)
        for node in fractureAccentNodes {
            setGlow(
                fractureColor.withAlphaComponent(CGFloat(plan.fractureRecovery.fractureOpacity)),
                opacity: plan.fractureRecovery.fractureOpacity,
                on: node
            )
        }
        setGlow(
            themedColor(SpellSchool.verify.nsColor).withAlphaComponent(CGFloat(plan.fractureRecovery.healingOpacity)),
            opacity: plan.fractureRecovery.healingOpacity,
            on: healingAccentNode
        )

        updatePhasePolish()
    }

    private func refreshNarrativeCues(animated: Bool) {
        let beat = stageBeat()
        let effectPlan = stageEffectPlan(for: beat)
        let atmospherePlan = currentAtmospherePlan
            ?? stageAtmospherePlan(for: beat, tuningMetadata: effectPlan.tuningMetadata)
        let phasePolishPlan = currentPhasePolishPlan
            ?? stagePhasePolishPlan(for: beat, effectPlan: effectPlan, atmospherePlan: atmospherePlan)
        applyNarrativeCuePlan(
            narrativeCuePlan(for: beat, phasePolishPlan: phasePolishPlan),
            animated: animated
        )
    }

    private func applyNarrativeCuePlan(_ plan: CinematicSceneNarrativeCuePlan, animated: Bool) {
        guard currentNarrativeCuePlan?.identifier != plan.identifier else { return }
        let previousPlan = currentNarrativeCuePlan
        currentNarrativeCuePlan = plan

        applyNarrativeCueDescriptor(
            plan.questPlaque,
            to: narrativeQuestPlaqueNode,
            animated: animated && previousPlan?.questPlaque.identifier != plan.questPlaque.identifier
        )
        applyNarrativeCueDescriptor(
            plan.arenaInscription,
            to: narrativeArenaInscriptionNode,
            animated: animated && previousPlan?.arenaInscription.identifier != plan.arenaInscription.identifier
        )
        applyNarrativeCueDescriptor(
            plan.activityBanner,
            to: narrativeActivityBannerNode,
            animated: animated && previousPlan?.activityBanner.identifier != plan.activityBanner.identifier
        )
    }

    private func applyNarrativeCueDescriptor(
        _ descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor,
        to node: Entity,
        animated: Bool
    ) {
        clearChildren(of: node)
        node.name = descriptor.stableID

        let layout = descriptor.layout
        node.position = layout.anchorPosition
        node.orientation = narrativeOrientation(for: layout)
        node.scale = SIMD3<Float>(repeating: descriptor.scale)
        setOpacity(descriptor.opacity, on: node)

        let color = narrativeColor(for: descriptor)
        let treatment = descriptor.plaqueTreatment
        let plateEmissionAlpha = min(0.42, 0.14 + treatment.emissionBoost)
        let plateOpacity = min(
            CinematicSceneNarrativeCuePlan.cueBackingOpacityRange.upperBound,
            layout.backingOpacity + treatment.emissionBoost * 0.18
        )
        let plate = ModelEntity(
            mesh: .generateBox(
                width: layout.plateSize.x,
                height: layout.plateSize.y,
                depth: layout.plateDepth,
                cornerRadius: max(0.014, min(0.04, layout.plateDepth * 0.95))
            ),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.018, green: 0.02, blue: 0.032, alpha: 1),
                    emission: color.withAlphaComponent(CGFloat(plateEmissionAlpha)),
                    opacity: plateOpacity
                )
            ]
        )
        plate.name = "\(descriptor.stableID).placard"
        plate.position.z = layout.plateZOffset
        plate.components.set(OpacityComponent(opacity: plateOpacity))
        node.addChild(plate)

        addNarrativePlaqueTreatment(
            treatment,
            to: node,
            name: "\(descriptor.stableID).treatment",
            layout: layout,
            color: color
        )

        addNarrativeText(
            descriptor.text,
            to: node,
            name: "\(descriptor.stableID).text.primary",
            width: layout.primaryTextWidth,
            offset: layout.primaryTextOffset,
            fontSize: CGFloat(layout.primaryFontSize),
            weight: .semibold,
            color: color,
            opacity: min(0.96, descriptor.opacity + 0.12)
        )

        let hasSecondary = descriptor.secondaryText?.isEmpty == false
        if let secondaryText = descriptor.secondaryText, hasSecondary {
            addNarrativeText(
                secondaryText,
                to: node,
                name: "\(descriptor.stableID).text.secondary",
                width: layout.secondaryTextWidth,
                offset: layout.secondaryTextOffset,
                fontSize: CGFloat(layout.secondaryFontSize),
                weight: .medium,
                color: color.withAlphaComponent(0.78),
                opacity: min(0.72, descriptor.opacity)
            )
        }

        if descriptor.glyphIdentifier != nil, layout.glyphSide != .none {
            addNarrativeGlyph(
                to: node,
                name: "\(descriptor.stableID).glyph",
                layout: layout,
                color: color,
                opacity: min(0.82, descriptor.opacity + 0.08)
            )
        }

        if animated {
            node.scale = SIMD3<Float>(repeating: max(0.001, descriptor.scale * 0.92))
            animate(
                node,
                toScale: SIMD3<Float>(repeating: descriptor.scale),
                duration: min(0.5, descriptor.cadence * 0.16),
                timing: .easeOut
            )
        }
    }

    private func addNarrativePlaqueTreatment(
        _ treatment: CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor,
        to node: Entity,
        name: String,
        layout: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor,
        color: NSColor
    ) {
        typealias PlaqueTreatmentDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor
        typealias RenderPrimitive = PlaqueTreatmentDescriptor.RenderPrimitive
        let recipe = treatment.renderRecipe
        guard recipe.primitiveCount > 0 else { return }

        let accentRoot = Entity()
        accentRoot.name = name
        accentRoot.scale = SIMD3<Float>(repeating: treatment.pulseScale)

        let halfWidth = layout.plateSize.x * 0.5
        let halfHeight = layout.plateSize.y * 0.5
        let inset = max(0.1, min(0.18, layout.plateSize.y * 0.28))
        let sideInset = max(0.05, min(0.1, layout.plateSize.y * 0.16))
        let z = max(0.022, layout.plateZOffset + layout.plateDepth * 0.66 + 0.018)
        let railRadius = max(0.0045, min(0.0085, layout.plateDepth * 0.18))
        let braceRadius = max(0.005, min(0.01, layout.plateDepth * 0.22))

        func addBeam(
            _ primitive: RenderPrimitive,
            from start: SIMD3<Float>,
            to end: SIMD3<Float>,
            radius: Float,
            opacity: Float,
            beamColor: NSColor? = nil
        ) {
            guard opacity > 0.001 else { return }
            let beam = beamEntity(
                from: start,
                to: end,
                radius: radius,
                color: beamColor ?? color,
                opacity: opacity
            )
            beam.name = "\(name).\(primitive.identifier)"
            accentRoot.addChild(beam)
        }

        for primitive in recipe.primitives {
            switch primitive {
            case .railTop:
                addBeam(
                    primitive,
                    from: [-halfWidth + inset, halfHeight - sideInset, z],
                    to: [halfWidth - inset, halfHeight - sideInset, z],
                    radius: railRadius,
                    opacity: treatment.edgeRailOpacity
                )
            case .railBottom:
                addBeam(
                    primitive,
                    from: [-halfWidth + inset, -halfHeight + sideInset, z],
                    to: [halfWidth - inset, -halfHeight + sideInset, z],
                    radius: railRadius,
                    opacity: treatment.edgeRailOpacity * 0.82
                )
            case .sealLeft:
                addBeam(
                    primitive,
                    from: [-halfWidth + inset, -halfHeight + sideInset, z],
                    to: [-halfWidth + inset, halfHeight - sideInset, z],
                    radius: railRadius,
                    opacity: treatment.edgeRailOpacity * 0.72
                )
            case .sealRight:
                addBeam(
                    primitive,
                    from: [halfWidth - inset, -halfHeight + sideInset, z],
                    to: [halfWidth - inset, halfHeight - sideInset, z],
                    radius: railRadius,
                    opacity: treatment.edgeRailOpacity * 0.72
                )
            case .warningLeft:
                addBeam(
                    primitive,
                    from: [-halfWidth + sideInset, -halfHeight + sideInset, z],
                    to: [-halfWidth + sideInset, halfHeight - sideInset, z],
                    radius: braceRadius,
                    opacity: treatment.braceOpacity
                )
            case .warningRight:
                addBeam(
                    primitive,
                    from: [halfWidth - sideInset, -halfHeight + sideInset, z],
                    to: [halfWidth - sideInset, halfHeight - sideInset, z],
                    radius: braceRadius,
                    opacity: treatment.braceOpacity
                )
            case .fractureDiagonalA:
                addBeam(
                    primitive,
                    from: [-halfWidth + inset, halfHeight - sideInset, z],
                    to: [halfWidth - inset, -halfHeight + sideInset, z],
                    radius: braceRadius,
                    opacity: treatment.fractureOpacity,
                    beamColor: color.withAlphaComponent(0.9)
                )
            case .fractureDiagonalB:
                addBeam(
                    primitive,
                    from: [-halfWidth * 0.28, -halfHeight + sideInset, z + 0.002],
                    to: [halfWidth * 0.34, halfHeight - sideInset, z + 0.002],
                    radius: railRadius,
                    opacity: treatment.braceOpacity,
                    beamColor: color.withAlphaComponent(0.9)
                )
            case .retryBraceLeft:
                addBeam(
                    primitive,
                    from: [-halfWidth + inset, -halfHeight + sideInset, z],
                    to: [-halfWidth + inset * 1.45, halfHeight - sideInset, z],
                    radius: braceRadius,
                    opacity: treatment.braceOpacity
                )
            case .retryBraceRight:
                addBeam(
                    primitive,
                    from: [halfWidth - inset * 1.45, -halfHeight + sideInset, z],
                    to: [halfWidth - inset, halfHeight - sideInset, z],
                    radius: braceRadius,
                    opacity: treatment.braceOpacity
                )
            case .retryCross:
                addBeam(
                    primitive,
                    from: [-halfWidth * 0.18, halfHeight - sideInset, z + 0.002],
                    to: [halfWidth * 0.18, -halfHeight + sideInset, z + 0.002],
                    radius: railRadius,
                    opacity: treatment.fractureOpacity
                )
            }
        }

        node.addChild(accentRoot)
    }

    private func addNarrativeText(
        _ value: String,
        to node: Entity,
        name: String,
        width: Float,
        offset: SIMD3<Float>,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        opacity: Float
    ) {
        let frame = CGRect(
            x: CGFloat(-width / 2),
            y: CGFloat(-fontSize * 0.52),
            width: CGFloat(width),
            height: CGFloat(fontSize * 1.55)
        )
        let text = ModelEntity(
            mesh: MeshResource.generateText(
                value,
                extrusionDepth: 0.0035,
                font: .systemFont(ofSize: fontSize, weight: weight),
                containerFrame: frame,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            ),
            materials: [glowMaterial(color, opacity: opacity)]
        )
        text.name = name
        text.position = offset
        text.components.set(OpacityComponent(opacity: opacity))
        node.addChild(text)
    }

    private func addNarrativeGlyph(
        to node: Entity,
        name: String,
        layout: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor,
        color: NSColor,
        opacity: Float
    ) {
        let glyph = Entity()
        glyph.name = name
        glyph.position = layout.glyphOffset
        let ringRadius = max(0.115, min(0.18, layout.plateSize.y * 0.34))
        let segmentReach = ringRadius * 0.82

        let ring = ModelEntity(
            mesh: torusMesh(ringRadius: ringRadius, pipeRadius: 0.006),
            materials: [glowMaterial(color, opacity: opacity)]
        )
        ring.name = "\(name).ring"
        ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        ring.components.set(OpacityComponent(opacity: opacity))
        glyph.addChild(ring)

        let horizontal = beamEntity(
            from: [-segmentReach, 0, 0],
            to: [segmentReach, 0, 0],
            radius: 0.006,
            color: color,
            opacity: opacity
        )
        horizontal.name = "\(name).segment.horizontal"
        glyph.addChild(horizontal)

        let vertical = beamEntity(
            from: [0, -segmentReach * 0.86, 0],
            to: [0, segmentReach * 0.86, 0],
            radius: 0.006,
            color: color.withAlphaComponent(0.76),
            opacity: opacity * 0.82
        )
        vertical.name = "\(name).segment.vertical"
        glyph.addChild(vertical)

        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.034),
            materials: [glowMaterial(color, opacity: opacity)]
        )
        core.name = "\(name).core"
        glyph.addChild(core)
        node.addChild(glyph)
    }

    private func applyCommitConstellationPlan(_ plan: CinematicCommitConstellationPlan, animated: Bool) {
        guard currentCommitConstellationPlan != plan else { return }
        currentCommitConstellationPlan = plan
        clearChildren(of: commitConstellationRoot)

        guard !plan.isEmpty else {
            pendingCommitConstellationFocusPlan = nil
            activeCommitConstellationFocusPlan = nil
            commitConstellationFocusUntil = .distantPast
            setOpacity(0, on: commitConstellationRoot)
            return
        }

        pendingCommitConstellationFocusPlan = plan.focusPlan
        commitConstellationRoot.position = .zero
        commitConstellationRoot.orientation = simd_quatf()
        setOpacity(0.94, on: commitConstellationRoot)

        let branchColor = themedColor(SpellSchool.git.nsColor).withAlphaComponent(0.52)
        for branch in plan.branchSegments {
            let trail = beamEntity(
                from: branch.startPosition,
                to: branch.endPosition,
                radius: 0.014,
                color: branchColor,
                opacity: 0.46
            )
            trail.name = branch.stableID
            commitConstellationRoot.addChild(trail)
        }

        for node in plan.nodes {
            addCommitConstellationNode(node, animated: animated)
        }

        if animated {
            commitConstellationRoot.scale = SIMD3<Float>(repeating: 0.96)
            animate(
                commitConstellationRoot,
                toScale: SIMD3<Float>(repeating: 1),
                duration: 0.42,
                timing: .easeOut
            )
        } else {
            commitConstellationRoot.scale = SIMD3<Float>(repeating: 1)
        }
    }

    private func stagePendingCommitConstellationFocusIfPossible(
        lines: [LiveLine],
        animated: Bool
    ) {
        guard let focusPlan = pendingCommitConstellationFocusPlan else { return }
        guard !focusPlan.isFallback else {
            pendingCommitConstellationFocusPlan = nil
            return
        }
        guard !hasActiveLiveFollowTarget(lines: lines) else { return }

        pendingCommitConstellationFocusPlan = nil
        activeCommitConstellationFocusPlan = focusPlan
        commitConstellationFocusUntil = Date().addingTimeInterval(1.75)
        stageCamera(focusPlan.shot, animated: animated)
    }

    private func applyTimelineSceneFocusPlan(
        _ plan: CinematicTimelineSceneFocusPlan,
        lines: [LiveLine],
        animated: Bool
    ) {
        guard plan != currentTimelineSceneFocusPlan else { return }
        currentTimelineSceneFocusPlan = plan
        activeTimelineSceneFocusDescriptor = plan.descriptor

        guard let descriptor = plan.descriptor else { return }
        if !hasActiveLiveFollowTarget(lines: lines) {
            stageCamera(descriptor.cameraShot, animated: animated)
        }

        let color = themedColor(descriptor.lightFamily.spell.nsColor)
        setPhaseLight(color: color, intensity: descriptor.phaseLightIntensity)

        switch descriptor.kind {
        case .recovery:
            applyRecoveryCueTraits(animated: animated)
        case .failedVerify:
            applyTimelineSceneFocusArenaEffect(descriptor, color: color)
            shakeCamera()
        case .commit, .plan, .develop, .verify, .outcome:
            applyTimelineSceneFocusArenaEffect(descriptor, color: color)
        }
    }

    private func applyRunRecapSceneFocusPlan(
        _ plan: CinematicRunRecapSceneFocusPlan,
        lines: [LiveLine],
        animated: Bool
    ) {
        guard plan != currentRunRecapSceneFocusPlan else { return }
        currentRunRecapSceneFocusPlan = plan
        activeRunRecapSceneFocusDescriptor = plan.descriptor

        guard let descriptor = plan.descriptor else { return }
        if !hasActiveLiveFollowTarget(lines: lines) {
            stageCamera(descriptor.cameraShot, animated: animated)
        }

        let color = themedColor(descriptor.lightFamily.spell.nsColor)
        setPhaseLight(color: color, intensity: descriptor.phaseLightIntensity)
        applyRunRecapSceneFocusArenaEffect(descriptor, color: color)
        if descriptor.terminalStyleIdentifier == CinematicRunRecapPlan.Style.failure.rawValue {
            shakeCamera()
        }
    }

    private func applyRunRecapEndCardPlan(
        _ plan: CinematicRunRecapEndCardPlan,
        lines: [LiveLine],
        animated: Bool
    ) {
        guard plan != currentRunRecapEndCardPlan else { return }
        currentRunRecapEndCardPlan = plan

        guard let descriptor = plan.descriptor else {
            if activeIdleStoryCycleDescriptor?.phase != .runRecapEndCard {
                clearRunRecapEndCardNode()
            }
            return
        }

        applyRunRecapEndCardDescriptor(descriptor, animated: animated)
        if !hasActiveLiveFollowTarget(lines: lines) {
            faceWizard(toward: descriptor.layout.anchorPosition)
        }
    }

    private func applyIdleStoryCyclePlan(
        _ plan: CinematicIdleStoryCyclePlan,
        lines: [LiveLine],
        animated: Bool
    ) {
        guard plan != currentIdleStoryCyclePlan else { return }
        let previousDescriptor = activeIdleStoryCycleDescriptor
        currentIdleStoryCyclePlan = plan
        activeIdleStoryCycleDescriptor = plan.descriptor
        activeIdleStoryCycleEndCardDescriptor = nil
        activeIdleStoryCycleArtifactTourPlan = nil

        if previousDescriptor?.phase == .runRecapEndCard,
           plan.descriptor?.phase != .runRecapEndCard,
           currentRunRecapEndCardPlan.descriptor == nil {
            clearRunRecapEndCardNode()
        }
        if previousDescriptor?.phase == .savedRecapArtifactTour,
           plan.descriptor?.phase != .savedRecapArtifactTour {
            clearSavedRecapArtifactTourNode()
        }

        guard let descriptor = plan.descriptor else { return }
        guard !hasActiveLiveFollowTarget(lines: lines) else { return }

        let color = themedColor(descriptor.lightFamily.spell.nsColor)
        stageCamera(
            descriptor.cameraShot,
            animated: animated,
            transitionDurationScale: descriptor.choreography.transitionDurationScale
        )
        setPhaseLight(color: color, intensity: descriptor.phaseLightIntensity)
        applyIdleStoryCycleArenaEffect(
            descriptor.arenaEffect,
            color: color,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            choreography: descriptor.choreography
        )
        let lookTarget = idleStoryCycleLookTarget(for: descriptor)
        faceWizard(toward: lookTarget)
        trackTarget(lookTarget, duration: descriptor.choreography.dwellDuration)
        applyIdleStoryCycleChoreographyCues(
            descriptor.choreography,
            color: color,
            phaseLightIntensity: descriptor.phaseLightIntensity
        )

        switch descriptor.phase {
        case .nativeFeedbackPlaque:
            if let plaqueDescriptor = descriptor.nativeFeedbackPlaqueDescriptor {
                applyNarrativeCueDescriptor(
                    plaqueDescriptor,
                    to: narrativeQuestPlaqueNode,
                    animated: animated
                )
            }
        case .runRecapEndCard:
            if let endCardDescriptor = descriptor.runRecapEndCardPlan?.descriptor {
                activeIdleStoryCycleEndCardDescriptor = endCardDescriptor
                applyRunRecapEndCardDescriptor(endCardDescriptor, animated: animated)
            }
        case .savedRecapArtifactTour:
            if let tourPlan = descriptor.runRecapShareArtifactTourPlan {
                activeIdleStoryCycleArtifactTourPlan = tourPlan
                applySavedRecapArtifactTourPlan(tourPlan, animated: animated)
            }
        case .timelineFocus:
            break
        case .runRecapFocus:
            break
        case .commitConstellation:
            break
        }
    }

    private func clearRunRecapEndCardNode() {
        clearChildren(of: runRecapEndCardNode)
        runRecapEndCardNode.name = "run-recap-end-card.none"
        setOpacity(0, on: runRecapEndCardNode)
    }

    private func clearSavedRecapArtifactTourNode() {
        clearChildren(of: savedRecapArtifactTourNode)
        savedRecapArtifactTourNode.name = "saved-recap-artifact-tour.none"
        setOpacity(0, on: savedRecapArtifactTourNode)
    }

    private func applySavedRecapArtifactTourPlan(
        _ tourPlan: CinematicRunRecapShareArtifactTourPlan,
        animated: Bool
    ) {
        clearChildren(of: savedRecapArtifactTourNode)
        savedRecapArtifactTourNode.name = "saved-recap-artifact-tour.\(tourPlan.stateIdentifier).\(tourPlan.savedTourHoldStateIdentifier)"
        savedRecapArtifactTourNode.position = savedRecapArtifactTourPosition(for: tourPlan)
        savedRecapArtifactTourNode.orientation = narrativeBillboardOrientation(
            from: savedRecapArtifactTourNode.position(relativeTo: nil),
            to: cameraPosition
        )
        savedRecapArtifactTourNode.scale = SIMD3<Float>(repeating: 1)
        setOpacity(0.9, on: savedRecapArtifactTourNode)

        let color = savedRecapArtifactTourColor(for: tourPlan)
        let plateWidth: Float = 2.62
        let plateHeight: Float = 0.94
        let plateDepth: Float = 0.034
        let plate = ModelEntity(
            mesh: .generateBox(
                width: plateWidth,
                height: plateHeight,
                depth: plateDepth,
                cornerRadius: 0.026
            ),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.012, green: 0.017, blue: 0.028, alpha: 1),
                    emission: color.withAlphaComponent(0.22),
                    opacity: 0.84
                )
            ]
        )
        plate.name = "saved-recap-artifact-tour.card"
        plate.position.z = 0
        plate.components.set(OpacityComponent(opacity: 0.84))
        savedRecapArtifactTourNode.addChild(plate)

        let topRail = beamEntity(
            from: [-plateWidth * 0.43, plateHeight * 0.36, 0.032],
            to: [plateWidth * 0.43, plateHeight * 0.36, 0.032],
            radius: 0.005,
            color: color,
            opacity: 0.48
        )
        topRail.name = "saved-recap-artifact-tour.rail.top"
        savedRecapArtifactTourNode.addChild(topRail)

        let sideRail = beamEntity(
            from: [-plateWidth * 0.43, -plateHeight * 0.3, 0.034],
            to: [-plateWidth * 0.43, plateHeight * 0.3, 0.034],
            radius: 0.0045,
            color: color.withAlphaComponent(0.82),
            opacity: tourPlan.selectionSourceIdentifier == "held"
                ? 0.62
                : (tourPlan.selectionSourceIdentifier == "pinned" ? 0.54 : 0.34)
        )
        sideRail.name = "saved-recap-artifact-tour.rail.\(tourPlan.selectionSourceIdentifier).\(tourPlan.savedTourHoldStateIdentifier)"
        savedRecapArtifactTourNode.addChild(sideRail)

        let orb = ModelEntity(
            mesh: .generateSphere(radius: 0.046),
            materials: [glowMaterial(color, opacity: tourPlan.hasWarnings ? 0.78 : 0.62)]
        )
        orb.name = "saved-recap-artifact-tour.orb.\(tourPlan.stateIdentifier).\(tourPlan.savedTourHoldStateIdentifier)"
        orb.position = [-plateWidth * 0.43, plateHeight * 0.36, 0.058]
        orb.components.set(OpacityComponent(opacity: tourPlan.hasWarnings ? 0.78 : 0.62))
        savedRecapArtifactTourNode.addChild(orb)

        addNarrativeText(
            tourPlan.titleSnippet,
            to: savedRecapArtifactTourNode,
            name: "saved-recap-artifact-tour.text.title",
            width: 2.2,
            offset: [0.08, 0.24, 0.048],
            fontSize: 0.075,
            weight: .semibold,
            color: color,
            opacity: 0.94
        )
        addNarrativeText(
            tourPlan.statusSnippet,
            to: savedRecapArtifactTourNode,
            name: "saved-recap-artifact-tour.text.status",
            width: 2.26,
            offset: [0.08, 0.08, 0.05],
            fontSize: 0.052,
            weight: .medium,
            color: color.withAlphaComponent(0.76),
            opacity: 0.72
        )
        addNarrativeText(
            tourPlan.bodyPreviewText,
            to: savedRecapArtifactTourNode,
            name: "saved-recap-artifact-tour.text.body",
            width: 2.32,
            offset: [0.08, -0.08, 0.05],
            fontSize: 0.047,
            weight: .regular,
            color: color.withAlphaComponent(0.66),
            opacity: 0.58
        )
        addNarrativeText(
            tourPlan.sessionText,
            to: savedRecapArtifactTourNode,
            name: "saved-recap-artifact-tour.text.session",
            width: 1.72,
            offset: [0.08, -0.3, 0.052],
            fontSize: 0.049,
            weight: .semibold,
            color: color.withAlphaComponent(0.84),
            opacity: 0.68
        )

        if animated {
            savedRecapArtifactTourNode.scale = SIMD3<Float>(repeating: 0.92)
            animate(
                savedRecapArtifactTourNode,
                toScale: SIMD3<Float>(repeating: 1),
                duration: 0.44,
                timing: .easeOut
            )
        }
    }

    private func applyRunRecapEndCardDescriptor(
        _ descriptor: CinematicRunRecapEndCardPlan.Descriptor,
        animated: Bool
    ) {
        clearChildren(of: runRecapEndCardNode)
        runRecapEndCardNode.name = descriptor.identifier

        let layout = descriptor.layout
        runRecapEndCardNode.position = layout.anchorPosition
        runRecapEndCardNode.orientation = narrativeOrientation(for: layout)
        runRecapEndCardNode.scale = SIMD3<Float>(repeating: descriptor.scale)
        setOpacity(0.9, on: runRecapEndCardNode)

        let color = recapEndCardColor(for: descriptor)
        let treatment = descriptor.plaqueTreatment
        let plateEmissionAlpha = min(0.46, 0.16 + treatment.emissionBoost)
        let plateOpacity = min(
            CinematicSceneNarrativeCuePlan.cueBackingOpacityRange.upperBound,
            layout.backingOpacity + treatment.emissionBoost * 0.16
        )
        let plate = ModelEntity(
            mesh: .generateBox(
                width: layout.plateSize.x,
                height: layout.plateSize.y,
                depth: layout.plateDepth,
                cornerRadius: max(0.016, min(0.04, layout.plateDepth * 0.95))
            ),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.014, green: 0.018, blue: 0.028, alpha: 1),
                    emission: color.withAlphaComponent(CGFloat(plateEmissionAlpha)),
                    opacity: plateOpacity
                )
            ]
        )
        plate.name = "\(descriptor.identifier).placard"
        plate.position.z = layout.plateZOffset
        plate.components.set(OpacityComponent(opacity: plateOpacity))
        runRecapEndCardNode.addChild(plate)

        addNarrativePlaqueTreatment(
            treatment,
            to: runRecapEndCardNode,
            name: "\(descriptor.identifier).treatment",
            layout: layout,
            color: color
        )

        addNarrativeText(
            descriptor.title,
            to: runRecapEndCardNode,
            name: "\(descriptor.identifier).text.title",
            width: layout.primaryTextWidth,
            offset: layout.primaryTextOffset,
            fontSize: CGFloat(layout.primaryFontSize),
            weight: .semibold,
            color: color,
            opacity: 0.96
        )
        addNarrativeText(
            descriptor.detail,
            to: runRecapEndCardNode,
            name: "\(descriptor.identifier).text.detail",
            width: layout.secondaryTextWidth,
            offset: layout.secondaryTextOffset,
            fontSize: CGFloat(layout.secondaryFontSize),
            weight: .medium,
            color: color.withAlphaComponent(0.8),
            opacity: 0.78
        )
        addNarrativeText(
            descriptor.status,
            to: runRecapEndCardNode,
            name: "\(descriptor.identifier).text.status",
            width: layout.secondaryTextWidth,
            offset: layout.secondaryTextOffset + [0, -0.13, 0.004],
            fontSize: CGFloat(max(0.058, layout.secondaryFontSize * 0.88)),
            weight: .medium,
            color: color.withAlphaComponent(0.64),
            opacity: 0.68
        )

        if !descriptor.glyphIdentifier.isEmpty, layout.glyphSide != .none {
            addNarrativeGlyph(
                to: runRecapEndCardNode,
                name: "\(descriptor.identifier).glyph.\(descriptor.glyphIdentifier)",
                layout: layout,
                color: color,
                opacity: 0.86
            )
        }

        if let cue = descriptor.pinnedComparisonCue {
            addRunRecapPinnedComparisonCue(
                cue,
                to: runRecapEndCardNode,
                layout: layout,
                color: color
            )
        }

        if animated {
            runRecapEndCardNode.scale = SIMD3<Float>(repeating: max(0.001, descriptor.scale * 0.9))
            animate(
                runRecapEndCardNode,
                toScale: SIMD3<Float>(repeating: descriptor.scale),
                duration: min(0.56, descriptor.cadence * 0.18),
                timing: .easeOut
            )
        }
    }

    private func addRunRecapPinnedComparisonCue(
        _ cue: CinematicRunRecapEndCardPlan.PinnedComparisonCue,
        to node: Entity,
        layout: CinematicRunRecapEndCardPlan.LayoutDescriptor,
        color: NSColor
    ) {
        let cueRoot = Entity()
        cueRoot.name = "\(cue.identifier).pin-bridge"
        cueRoot.position = [
            0,
            -layout.plateSize.y * 0.5 - 0.18,
            layout.plateZOffset + layout.plateDepth * 0.8 + 0.036
        ]

        let bridgeColor = pinnedComparisonCueColor(for: cue, base: color)
        let bridgeWidth = min(layout.plateSize.x * 0.72, 2.64)
        let railOpacity: Float = cue.stateIdentifier == "filtered-pinned-target" ? 0.5 : 0.42
        let rail = beamEntity(
            from: [-bridgeWidth * 0.5, 0.055, 0],
            to: [bridgeWidth * 0.5, 0.055, 0],
            radius: 0.0055,
            color: bridgeColor,
            opacity: railOpacity
        )
        rail.name = "\(cue.identifier).rail.\(cue.railTreatmentIdentifier)"
        cueRoot.addChild(rail)

        let selectedPin = ModelEntity(
            mesh: .generateSphere(radius: 0.032),
            materials: [glowMaterial(color, opacity: 0.56)]
        )
        selectedPin.name = "\(cue.identifier).pin.selected"
        selectedPin.position = [-bridgeWidth * 0.5, 0.055, 0.004]
        selectedPin.components.set(OpacityComponent(opacity: 0.56))
        cueRoot.addChild(selectedPin)

        let targetPin = ModelEntity(
            mesh: .generateSphere(radius: 0.038),
            materials: [glowMaterial(bridgeColor, opacity: 0.68)]
        )
        targetPin.name = "\(cue.identifier).pin.target"
        targetPin.position = [bridgeWidth * 0.5, 0.055, 0.004]
        targetPin.components.set(OpacityComponent(opacity: 0.68))
        cueRoot.addChild(targetPin)

        let glyph = ModelEntity(
            mesh: torusMesh(ringRadius: 0.058, pipeRadius: 0.0045),
            materials: [glowMaterial(bridgeColor, opacity: 0.46)]
        )
        glyph.name = "\(cue.identifier).glyph.\(cue.glyphIdentifier)"
        glyph.position = [0, 0.055, 0.008]
        glyph.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        glyph.components.set(OpacityComponent(opacity: 0.46))
        cueRoot.addChild(glyph)

        addNarrativeText(
            cue.label,
            to: cueRoot,
            name: "\(cue.identifier).text.label",
            width: min(layout.secondaryTextWidth, 2.54),
            offset: [0, -0.028, 0.012],
            fontSize: CGFloat(max(0.044, layout.secondaryFontSize * 0.68)),
            weight: .semibold,
            color: bridgeColor.withAlphaComponent(0.78),
            opacity: 0.62
        )
        addNarrativeText(
            cue.detail,
            to: cueRoot,
            name: "\(cue.identifier).text.detail",
            width: min(layout.secondaryTextWidth, 2.7),
            offset: [0, -0.102, 0.014],
            fontSize: CGFloat(max(0.038, layout.secondaryFontSize * 0.56)),
            weight: .medium,
            color: bridgeColor.withAlphaComponent(0.64),
            opacity: 0.5
        )

        node.addChild(cueRoot)
    }

    private func pinnedComparisonCueColor(
        for cue: CinematicRunRecapEndCardPlan.PinnedComparisonCue,
        base: NSColor
    ) -> NSColor {
        let accent: NSColor
        switch cue.railTreatmentIdentifier {
        case "promoted-hold-rail", "warning-promoted-hold-rail":
            accent = themedColor(SpellSchool.verify.nsColor)
        case "filtered-promoted-hold-rail":
            accent = themedColor(SpellSchool.scan.nsColor).mixing(
                with: themedColor(SpellSchool.verify.nsColor),
                fraction: 0.36
            )
        case "filtered-pin-rail":
            accent = themedColor(SpellSchool.scan.nsColor)
        case "warning-pin-rail":
            accent = themedColor(SpellSchool.pressure.nsColor)
        case "stale-pin-rail":
            accent = themedColor(SpellSchool.failure.nsColor)
        default:
            accent = themedColor(SpellSchool.git.nsColor)
        }
        return accent.mixing(with: base, fraction: 0.34)
    }

    private func recapEndCardColor(
        for descriptor: CinematicRunRecapEndCardPlan.Descriptor
    ) -> NSColor {
        themedColor(descriptor.lightFamily.spell.nsColor)
            .mixing(with: themedColor(descriptor.tintFamily.spell.nsColor), fraction: 0.28)
    }

    private func savedRecapArtifactTourPosition(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> SIMD3<Float> {
        let sessionOffset = Float((tourPlan.sessionNumber ?? 0) % 5) * 0.035
        let pinOffset: Float
        switch tourPlan.selectionSourceIdentifier {
        case "held":
            pinOffset = -0.02
        case "pinned":
            pinOffset = -0.08
        default:
            pinOffset = 0.08
        }
        return [-1.68 + pinOffset, 1.18 + sessionOffset, 1.58]
    }

    private func savedRecapArtifactTourColor(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> NSColor {
        if tourPlan.stateIdentifier.contains("missing-pin")
            || tourPlan.stateIdentifier.contains("missing-hold") {
            return themedColor(SpellSchool.failure.nsColor)
        }
        if tourPlan.stateIdentifier.contains("filtered-pin")
            || tourPlan.stateIdentifier.contains("filtered-hold")
            || tourPlan.stateIdentifier.contains("no-match") {
            return themedColor(SpellSchool.scan.nsColor)
        }
        if tourPlan.hasWarnings {
            return themedColor(SpellSchool.pressure.nsColor)
        }
        if tourPlan.selectionSourceIdentifier == "held" {
            return themedColor(SpellSchool.verify.nsColor)
        }
        if tourPlan.selectionSourceIdentifier == "pinned" {
            return themedColor(SpellSchool.git.nsColor)
        }
        return themedColor(SpellSchool.insight.nsColor)
    }

    private func applyTimelineSceneFocusArenaEffect(
        _ descriptor: CinematicTimelineSceneFocusPlan.Descriptor,
        color: NSColor
    ) {
        switch descriptor.arenaEffect {
        case .none:
            return
        case .charge:
            chargeArena(color: color)
        case .seal:
            sealArena(color: color)
        case .victory:
            sealArena(color: color)
            portalPulse(color: color)
        case .activityPulse:
            arenaRing(
                radius: 3.2,
                color: color.withAlphaComponent(0.58),
                duration: 0.78,
                scale: 1.75,
                opacity: 0.44
            )
            pulsePhaseLight(color: color, intensity: descriptor.phaseLightIntensity, duration: 0.5)
        case .historyChains:
            historyChains(
                CinematicStageEffectPlanner.historyChainsEffect(),
                color: color
            )
        }
    }

    private func applyRunRecapSceneFocusArenaEffect(
        _ descriptor: CinematicRunRecapSceneFocusPlan.Descriptor,
        color: NSColor
    ) {
        switch descriptor.arenaEffect {
        case .none:
            return
        case .charge:
            chargeArena(color: color)
        case .seal:
            sealArena(color: color)
        case .victory:
            sealArena(color: color)
            portalPulse(color: color)
        case .activityPulse:
            arenaRing(
                radius: descriptor.usesFallbackTarget ? 2.7 : 3.45,
                color: color.withAlphaComponent(0.6),
                duration: 0.82,
                scale: 1.72,
                opacity: 0.44
            )
            pulsePhaseLight(color: color, intensity: descriptor.phaseLightIntensity, duration: 0.52)
        case .historyChains:
            historyChains(
                CinematicStageEffectPlanner.historyChainsEffect(),
                color: color
            )
        }
    }

    private func applyIdleStoryCycleArenaEffect(
        _ arenaEffect: CinematicStageArenaEffect,
        color: NSColor,
        phaseLightIntensity: Float,
        choreography: CinematicIdleStoryCyclePlan.Choreography
    ) {
        let damping = choreography.comfortDamping
        switch arenaEffect {
        case .none:
            return
        case .charge:
            chargeArena(color: color)
        case .seal:
            sealArena(color: color)
        case .victory:
            sealArena(color: color)
            portalPulse(color: color)
        case .activityPulse:
            arenaRing(
                radius: 3.05,
                color: color.withAlphaComponent(0.58),
                duration: 0.78 * Double(0.82 + damping * 0.18),
                scale: 1 + 0.68 * damping,
                opacity: 0.24 + 0.18 * damping
            )
            pulsePhaseLight(
                color: color,
                intensity: phaseLightIntensity * (0.92 + damping * 0.08),
                duration: 0.5 * Double(0.82 + damping * 0.18)
            )
        case .historyChains:
            historyChains(
                CinematicStageEffectPlanner.historyChainsEffect(),
                color: color
            )
        }
    }

    private func applyIdleStoryCycleChoreographyCues(
        _ choreography: CinematicIdleStoryCyclePlan.Choreography,
        color: NSColor,
        phaseLightIntensity: Float
    ) {
        if let pulse = choreography.pulseHint {
            pulsePhaseLight(
                color: color,
                intensity: phaseLightIntensity * pulse.intensityScale,
                duration: pulse.duration
            )
            staffOrbBoost = max(staffOrbBoost, pulse.orbBoost)
        }

        if let shake = choreography.shakeHint {
            shakeCamera(
                CinematicStageEffectPlan.CameraShake(
                    shouldShake: true,
                    duration: shake.duration,
                    scale: shake.scale * cameraShakeScale()
                )
            )
        }
    }

    private func hasActiveLiveFollowTarget(lines: [LiveLine]) -> Bool {
        lines.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private func addCommitConstellationNode(
        _ node: CinematicCommitConstellationPlan.Node,
        animated: Bool
    ) {
        let orb = Entity()
        orb.name = node.stableID
        orb.position = node.position
        orb.orientation = narrativeBillboardOrientation(
            from: node.position,
            to: CinematicCameraShot.home.position
        )
        orb.components.set(OpacityComponent(opacity: 0.95))

        let baseColor = themedColor(SpellSchool.git.nsColor)
        let subjectColor = node.rank == 0
            ? baseColor.mixing(with: NSColor(calibratedRed: 1, green: 0.86, blue: 0.38, alpha: 1), fraction: 0.34)
            : baseColor
        let core = ModelEntity(
            mesh: .generateSphere(radius: node.radius),
            materials: [glowMaterial(subjectColor, opacity: node.rank == 0 ? 0.9 : 0.72)]
        )
        core.name = "\(node.stableID).orb"
        core.components.set(OpacityComponent(opacity: node.rank == 0 ? 0.9 : 0.72))
        orb.addChild(core)

        let ring = ModelEntity(
            mesh: torusMesh(ringRadius: node.radius * 1.42, pipeRadius: 0.006),
            materials: [glowMaterial(subjectColor.withAlphaComponent(0.74), opacity: 0.6)]
        )
        ring.name = "\(node.stableID).ring"
        ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        ring.components.set(OpacityComponent(opacity: 0.6))
        orb.addChild(ring)

        if node.rank == 0 {
            let halo = ModelEntity(
                mesh: torusMesh(ringRadius: node.radius * 2.0, pipeRadius: 0.008),
                materials: [glowMaterial(subjectColor.withAlphaComponent(0.5), opacity: 0.42)]
            )
            halo.name = "\(node.stableID).halo"
            halo.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            halo.components.set(OpacityComponent(opacity: 0.42))
            orb.addChild(halo)
        }

        addCommitConstellationLabel(node, to: orb, color: subjectColor)
        commitConstellationRoot.addChild(orb)

        if animated {
            orb.scale = SIMD3<Float>(repeating: 0.001)
            animate(
                orb,
                toScale: SIMD3<Float>(repeating: 1),
                duration: 0.34,
                delay: Double(node.rank) * 0.035,
                timing: .easeOut
            )
        }
    }

    private func addCommitConstellationLabel(
        _ node: CinematicCommitConstellationPlan.Node,
        to orb: Entity,
        color: NSColor
    ) {
        let plate = ModelEntity(
            mesh: .generateBox(width: 1.54, height: 0.18, depth: 0.012, cornerRadius: 0.014),
            materials: [
                material(
                    diffuse: NSColor(calibratedRed: 0.012, green: 0.016, blue: 0.024, alpha: 1),
                    emission: color.withAlphaComponent(0.12),
                    opacity: 0.52
                )
            ]
        )
        plate.name = "\(node.stableID).label.plate"
        plate.position = [0, -0.31, 0.028]
        plate.components.set(OpacityComponent(opacity: 0.52))
        orb.addChild(plate)

        let frame = CGRect(x: -0.72, y: -0.045, width: 1.44, height: 0.13)
        let text = ModelEntity(
            mesh: MeshResource.generateText(
                node.label,
                extrusionDepth: 0.0025,
                font: .systemFont(ofSize: 0.075, weight: node.rank == 0 ? .semibold : .medium),
                containerFrame: frame,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            ),
            materials: [glowMaterial(color.withAlphaComponent(0.82), opacity: 0.82)]
        )
        text.name = "\(node.stableID).label.text"
        text.position = [0, -0.345, 0.041]
        text.components.set(OpacityComponent(opacity: 0.82))
        orb.addChild(text)
    }

    private func narrativeOrientation(
        for layout: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor
    ) -> simd_quatf {
        switch layout.facingMode {
        case .floorInscription:
            return simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        case .arenaCamera:
            let position = layout.anchorPosition
            let target = SIMD3<Float>(
                CinematicCameraShot.home.position.x,
                position.y,
                CinematicCameraShot.home.position.z
            )
            return narrativeBillboardOrientation(from: position, to: target)
        }
    }

    private func narrativeBillboardOrientation(from position: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        guard let direction = horizontalDirection(from: position, to: target) else {
            return simd_quatf()
        }
        return simd_quatf(from: [0, 0, 1], to: direction)
    }

    private func narrativeColor(for descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor) -> NSColor {
        let base = themedColor(descriptor.lightFamily.spell.nsColor)
        let tint = themedColor(descriptor.tintFamily.spell.nsColor)
        return base.mixing(with: tint, fraction: 0.32)
    }

    private func applyCinematicInfluenceChange() {
        stageCamera(currentCameraShot)
        applySetDressingPlan(animated: false)
        refreshAtmosphere(animated: false)
        let baseline = phaseLightBaseline(for: lastPhase)
        setPhaseLight(color: themedColor(baseline.color), intensity: baseline.intensity)

        if isThinking {
            startThinkingTimer(spawnImmediately: false)
        }
    }

    private func themedColor(_ color: NSColor) -> NSColor {
        languageMotif.phaseColor(color)
    }

    private func atmosphereColor(_ tint: CinematicStageAtmospherePlan.SurfaceTint) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(tint.red),
            green: CGFloat(tint.green),
            blue: CGFloat(tint.blue),
            alpha: CGFloat(tint.opacity)
        )
    }

    private func atmosphereScale(radius: Float, scale: Float) -> SIMD3<Float> {
        let value = max(0.001, radius * scale)
        return [value, 1, value]
    }

    private func staffOrientation(for pose: CinematicStagePhasePolishPlan.WizardPose) -> simd_quatf {
        simd_quatf(angle: pose.staffPitch, axis: [1, 0, 0])
            * simd_quatf(angle: pose.staffRoll, axis: [0, 0, 1])
    }

    private func armOrientation(_ lift: Float) -> simd_quatf {
        simd_quatf(angle: lift, axis: [0, 0, 1])
    }

    private func phaseLightBaseline(for phase: LoopPhase) -> (color: NSColor, intensity: Float) {
        if let descriptor = recoveryCuePlan.visualDescriptor {
            return (descriptor.lightFamily.spell.nsColor, descriptor.phaseLightIntensity)
        }
        let beat = stageBeat(for: phase)
        return (beat.lightFamily.spell.nsColor, beat.phaseLightIntensity)
    }

    private func shakeCamera() {
        shakeCamera(
            CinematicStageEffectPlan.CameraShake(
                shouldShake: true,
                duration: 0.22 * Double(cameraShakeScale()),
                scale: cameraShakeScale()
            )
        )
    }

    private func shakeCamera(_ cameraShake: CinematicStageEffectPlan.CameraShake) {
        guard cameraShake.shouldShake else { return }
        activeCameraShakeScale = cameraShake.scale
        shakeUntil = Date().addingTimeInterval(cameraShake.duration)
    }

    private func setPhaseLight(color: NSColor, intensity: Float) {
        guard var light = phaseLightNode.components[PointLightComponent.self] else { return }
        light.color = activityTint(for: color)
        light.intensity = intensity + activityLightBoost() + atmospherePhaseLightBoost()
        phaseLightNode.components.set(light)
    }

    private func atmospherePhaseLightBoost() -> Float {
        currentAtmospherePlan?.pressureLighting.phaseLightPressureBoost ?? 0
    }

    private func activityTint(for color: NSColor) -> NSColor {
        guard let tintSource = activityMotif.tintSource else { return color }
        return setDressingTint(
            color,
            fraction: setDressingPlan.pedestalFlames.activityTintFraction,
            tintSource: tintSource
        )
    }

    private func setDressingTint(
        _ color: NSColor,
        fraction: Float,
        tintSource: SpellSchool? = nil
    ) -> NSColor {
        let tint = tintSource ?? activityMotif.tintSource
        guard let tint else { return color }
        return color.mixing(with: themedColor(tint.nsColor), fraction: CGFloat(fraction))
    }

    private func activityLightBoost() -> Float {
        setDressingPlan.activityLightBoost
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

    private func setUnlitMaterial(_ material: UnlitMaterial, on entity: Entity) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = [material]
        entity.components.set(model)
    }

    private func setMaterial(_ material: PhysicallyBasedMaterial, on entity: Entity) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = [material]
        entity.components.set(model)
    }

    private func setDressingIndex(in name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    private func shardOrientation(
        for slot: CinematicSetDressingPlan.FloatingShardSlotGeometry
    ) -> simd_quatf {
        simd_quatf(angle: slot.yawRadians, axis: [0, 1, 0])
            * simd_quatf(angle: slot.pitchRadians, axis: [1, 0, 0])
            * simd_quatf(angle: slot.rollRadians, axis: [0, 0, 1])
    }

    private func pedestalStoneColors() -> (base: NSColor, column: NSColor, emission: NSColor) {
        let identifier = setDressingPlan.materialTextureVariants.pedestalMaterialIdentifier
        if identifier.contains("oxidized") {
            return (
                NSColor(calibratedRed: 0.078, green: 0.052, blue: 0.044, alpha: 1),
                NSColor(calibratedRed: 0.052, green: 0.044, blue: 0.04, alpha: 1),
                languageMotif.accent.withAlphaComponent(0.16)
            )
        }
        if identifier.contains("circuit") {
            return (
                NSColor(calibratedRed: 0.042, green: 0.058, blue: 0.076, alpha: 1),
                NSColor(calibratedRed: 0.028, green: 0.044, blue: 0.062, alpha: 1),
                languageMotif.accent.withAlphaComponent(0.18)
            )
        }
        if identifier.contains("etched") {
            return (
                NSColor(calibratedRed: 0.045, green: 0.047, blue: 0.058, alpha: 1),
                NSColor(calibratedRed: 0.032, green: 0.034, blue: 0.046, alpha: 1),
                languageMotif.secondaryAccent.withAlphaComponent(0.12)
            )
        }
        return (
            NSColor(calibratedRed: 0.052, green: 0.054, blue: 0.072, alpha: 1),
            NSColor(calibratedRed: 0.034, green: 0.038, blue: 0.054, alpha: 1),
            languageMotif.accent.withAlphaComponent(0.14)
        )
    }

    private func shardStoneColor() -> NSColor {
        let identifier = setDressingPlan.materialTextureVariants.shardMaterialIdentifier
        if identifier.contains("circuit") {
            return NSColor(calibratedRed: 0.04, green: 0.056, blue: 0.078, alpha: 1)
        }
        if identifier.contains("oxidized") {
            return NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.046, alpha: 1)
        }
        if identifier.contains("etched") {
            return NSColor(calibratedRed: 0.052, green: 0.052, blue: 0.064, alpha: 1)
        }
        return NSColor(calibratedRed: 0.055, green: 0.052, blue: 0.074, alpha: 1)
    }

    private func stageCamera(
        _ shot: CinematicCameraShot,
        animated: Bool = true,
        transitionDurationScale: Double = 1
    ) {
        currentCameraShot = shot
        let position = cameraPosition(for: shot)
        let fieldOfView = cameraFieldOfView(for: shot)
        let duration = cameraTransitionDuration(for: shot) * clamped(
            transitionDurationScale,
            to: CinematicIdleStoryCyclePlan.transitionDurationScaleRange
        )

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

    private func trackTarget(
        _ target: SIMD3<Float>,
        duration: TimeInterval,
        source: CameraFollowSource = .stageAction
    ) {
        let until = Date().addingTimeInterval(duration)
        wizardFacingTarget = target
        wizardFacingUntil = until
        followCameraTarget = target
        followCameraUntil = until
        followCameraSource = source
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
            self.animate(self.staffPivotNode, toOrientation: self.phaseStaffOrientation, duration: 0.28, timing: .easeInOut)
            self.animate(self.rightArmNode, toOrientation: self.phaseRightArmOrientation, duration: 0.28, timing: .easeInOut)
            self.animate(self.leftArmNode, toOrientation: self.phaseLeftArmOrientation, duration: 0.34, timing: .easeInOut)
            self.animate(self.headNode, toOrientation: self.phaseHeadOrientation, duration: 0.24, timing: .easeInOut)
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
        updateAtmosphere()
        updatePhasePolish()
        updateNarrativeCues()
        updateRunRecapEndCard()
        updateSavedRecapArtifactTour()
        updateCommitConstellation()
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
            let shakeScale = activeCameraShakeScale > 0 ? activeCameraShakeScale : cameraShakeScale()
            cameraOffset += SIMD3<Float>(
                Float.random(in: -0.16...0.16) * shakeScale,
                Float.random(in: -0.05...0.05) * shakeScale,
                0
            )
        } else {
            activeCameraShakeScale = 0
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
        let cadence = max(phaseOrbPulseCadence, 0.1)
        let orbWave = sin(Float(elapsedTime / cadence) * .pi * 2)
        let orbPulse = max(0.001, phaseOrbScale + orbWave * phaseOrbPulseAmplitude + staffOrbBoost)
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
        if let target = activeTimelineSceneFocusTarget() {
            return target
        }
        if let target = activeRunRecapSceneFocusTarget() {
            return target
        }
        if let target = activeIdleStoryCycleTarget() {
            return target
        }
        if let target = activeCommitConstellationFocusTarget() {
            return target
        }
        if isThinking {
            return closestEnemy(in: Array(enemyRoot.children).filter { $0.name != "dyingEnemy" })?.position(relativeTo: nil)
        }
        return nil
    }

    private func activeFollowTarget() -> SIMD3<Float>? {
        if let target = activeLiveFollowTarget() {
            return target
        }
        if activeTimelineSceneFocusTarget() != nil {
            return nil
        }
        if activeRunRecapSceneFocusTarget() != nil {
            return nil
        }
        if activeIdleStoryCycleTarget() != nil {
            return nil
        }
        if activeCommitConstellationFocusTarget() != nil {
            return nil
        }
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
        if let target = activeFollowTarget() {
            return mix(wizardPosition, target, 0.56) + [0, 0.84, 0]
        }
        if let target = activeTimelineSceneFocusTarget() {
            return target
        }
        if let target = activeRunRecapSceneFocusTarget() {
            return target
        }
        if let target = activeIdleStoryCycleTarget() {
            return target
        }
        guard let target = activeCommitConstellationFocusTarget() else {
            return wizardPosition + [0, 0.9, 0]
        }
        return target
    }

    private func activeTimelineSceneFocusTarget() -> SIMD3<Float>? {
        guard activeLiveFollowTarget() == nil,
              let descriptor = activeTimelineSceneFocusDescriptor else {
            return nil
        }
        return descriptor.lookTarget
    }

    private func activeRunRecapSceneFocusTarget() -> SIMD3<Float>? {
        guard activeLiveFollowTarget() == nil,
              let descriptor = activeRunRecapSceneFocusDescriptor else {
            return nil
        }
        return descriptor.lookTarget
    }

    private func activeIdleStoryCycleTarget() -> SIMD3<Float>? {
        guard activeLiveFollowTarget() == nil,
              let descriptor = activeIdleStoryCycleDescriptor else {
            return nil
        }
        return idleStoryCycleLookTarget(for: descriptor)
    }

    private func idleStoryCycleLookTarget(
        for descriptor: CinematicIdleStoryCyclePlan.Descriptor
    ) -> SIMD3<Float> {
        let wizardEye = wizardNode.position(relativeTo: nil) + [0, 0.9, 0]
        let targetBias = clamped(
            descriptor.choreography.targetBias,
            to: CinematicIdleStoryCyclePlan.targetBiasRange
        )
        return mix(wizardEye, descriptor.lookTarget, targetBias)
    }

    private func activeCommitConstellationFocusTarget() -> SIMD3<Float>? {
        guard activeLiveFollowTarget() == nil,
              Date() < commitConstellationFocusUntil,
              let focusPlan = activeCommitConstellationFocusPlan,
              !focusPlan.isFallback else {
            return nil
        }
        return focusPlan.lookTarget
    }

    private func activeLiveFollowTarget() -> SIMD3<Float>? {
        guard Date() < followCameraUntil,
              followCameraSource == .liveCommandOrFile,
              let followCameraTarget else {
            return nil
        }
        return followCameraTarget
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

    private func updateAtmosphere() {
        guard let plan = currentAtmospherePlan else { return }
        let cadence = max(plan.atmosphericPulse.cadence, 0.1)
        let wave = 0.5 + sin(Float(elapsedTime / cadence) * .pi * 2) * 0.5
        let haloScale = plan.pressureHalo.scale + plan.atmosphericPulse.amplitude * wave
        pressureHaloNode.scale = atmosphereScale(radius: plan.pressureHalo.radius, scale: haloScale)

        let pulseScale = plan.pressureHalo.scale * 0.74 + plan.atmosphericPulse.amplitude * (0.8 + wave)
        atmospherePulseNode.scale = atmosphereScale(radius: plan.pressureHalo.radius, scale: pulseScale)
        setOpacity(plan.atmosphericPulse.opacity * (0.52 + wave * 0.48), on: atmospherePulseNode)
    }

    private func updatePhasePolish() {
        guard let plan = currentPhasePolishPlan else { return }

        let sigilCadence = max(plan.cadence.sigilOrbitCadence, 0.1)
        let sigilAngle = Float(elapsedTime / sigilCadence) * .pi * 2
        let sigilWave = 0.5 + sin(sigilAngle) * 0.5
        let orbit = plan.sigilEmphasis.orbitRadius
        languageSigilRoot.position = languageSigilBasePosition + [
            cos(sigilAngle) * orbit,
            0,
            sin(sigilAngle) * orbit
        ]
        activitySigilRoot.position = activitySigilBasePosition + [
            cos(sigilAngle + .pi) * orbit,
            0,
            sin(sigilAngle + .pi) * orbit
        ]

        let sigilScale = 1
            + plan.sigilEmphasis.sealEmphasis * 0.14
            + plan.sigilEmphasis.victoryEmphasis * 0.12
            + plan.sigilEmphasis.pulseAmplitude * sigilWave
        languageSigilRoot.scale = SIMD3<Float>(repeating: max(0.001, sigilScale))
        activitySigilRoot.scale = SIMD3<Float>(
            repeating: max(0.001, sigilScale + plan.sigilEmphasis.victoryEmphasis * 0.04)
        )

        let portalCadence = max(plan.cadence.orbPulseCadence, 0.1)
        let portalWave = 0.5 + sin(Float(elapsedTime / portalCadence) * .pi * 2) * 0.5
        let portalScale = max(
            0.001,
            plan.portalBackdrop.portalScale + plan.portalBackdrop.portalPulseAmplitude * portalWave
        )
        portalApertureNode.scale = SIMD3<Float>(repeating: portalScale)
        portalFillNode.scale = SIMD3<Float>(repeating: max(0.001, portalScale * 0.88))
        setOpacity(plan.portalBackdrop.portalOpacity * (0.68 + portalWave * 0.32), on: portalApertureNode)
        setOpacity(plan.portalBackdrop.portalOpacity * 0.42 * (0.62 + portalWave * 0.38), on: portalFillNode)

        if let atmospherePlan = currentAtmospherePlan {
            let backdropOpacity = min(
                1,
                atmospherePlan.backdropTint.opacity + plan.portalBackdrop.backdropOpacityBoost * (0.72 + portalWave * 0.28)
            )
            setOpacity(backdropOpacity, on: backdropTintNode)
        }

        let fractureCadence = max(plan.cadence.fractureCadence, 0.1)
        let fractureAngle = Float(elapsedTime / fractureCadence) * .pi * 2
        let fractureWave = 0.5 + sin(fractureAngle) * 0.5
        let fractureScale = max(0.001, plan.fractureRecovery.fractureSpread * (0.92 + fractureWave * 0.08))
        phasePolishRoot.orientation = simd_quatf(angle: fractureAngle * 0.018, axis: [0, 1, 0])
        for (index, node) in fractureAccentNodes.enumerated() {
            let stagger = 0.72 + sin(fractureAngle + Float(index) * 0.73) * 0.14
            node.scale = [fractureScale, 1, fractureScale]
            setOpacity(plan.fractureRecovery.fractureOpacity * max(0.4, stagger), on: node)
        }

        let healingScale = max(0.001, 1 + plan.fractureRecovery.healingOpacity * 0.28 + fractureWave * 0.08)
        healingAccentNode.scale = SIMD3<Float>(repeating: healingScale)
        setOpacity(plan.fractureRecovery.healingOpacity * (0.58 + fractureWave * 0.42), on: healingAccentNode)
    }

    private func updateNarrativeCues() {
        guard let plan = currentNarrativeCuePlan else { return }
        updateNarrativeCueNode(narrativeQuestPlaqueNode, descriptor: plan.questPlaque, phaseOffset: 0)
        updateNarrativeCueNode(narrativeArenaInscriptionNode, descriptor: plan.arenaInscription, phaseOffset: 0.34)
        updateNarrativeCueNode(narrativeActivityBannerNode, descriptor: plan.activityBanner, phaseOffset: 0.68)
    }

    private func updateNarrativeCueNode(
        _ node: Entity,
        descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor,
        phaseOffset: Float
    ) {
        let cadence = max(descriptor.cadence, 0.1)
        let wave = 0.5 + sin(Float(elapsedTime / cadence) * .pi * 2 + phaseOffset * .pi * 2) * 0.5
        let pulseScale = descriptor.scale * (1 + wave * 0.025)
        node.scale = SIMD3<Float>(repeating: max(0.001, pulseScale))
        setOpacity(descriptor.opacity * (0.82 + wave * 0.18), on: node)
    }

    private func updateRunRecapEndCard() {
        guard let descriptor = currentRunRecapEndCardPlan.descriptor ?? activeIdleStoryCycleEndCardDescriptor else {
            return
        }
        let cadence = max(descriptor.cadence, 0.1)
        let phase = Float(elapsedTime / cadence) * Float.pi * 2
        let offset = Float(0.18) * Float.pi * 2
        let wave = Float(0.5) + sin(phase + offset) * Float(0.5)
        let pulseScale = descriptor.scale * (1 + wave * 0.032)
        runRecapEndCardNode.scale = SIMD3<Float>(repeating: max(0.001, pulseScale))
        runRecapEndCardNode.orientation = narrativeBillboardOrientation(
            from: runRecapEndCardNode.position(relativeTo: nil),
            to: cameraPosition
        )
        setOpacity(0.78 + wave * 0.16, on: runRecapEndCardNode)
    }

    private func updateSavedRecapArtifactTour() {
        guard let tourPlan = activeIdleStoryCycleArtifactTourPlan else {
            return
        }
        let cadence = max(currentIdleStoryCyclePlan.descriptor?.cadence ?? 6.8, 0.1)
        let phase = Float(elapsedTime / cadence) * Float.pi * 2
        let wave = Float(0.5) + sin(phase + 0.41 * Float.pi * 2) * Float(0.5)
        let pulseScale: Float = 1 + wave * (tourPlan.hasWarnings ? 0.04 : 0.026)
        savedRecapArtifactTourNode.scale = SIMD3<Float>(repeating: max(0.001, pulseScale))
        savedRecapArtifactTourNode.orientation = narrativeBillboardOrientation(
            from: savedRecapArtifactTourNode.position(relativeTo: nil),
            to: cameraPosition
        )
        setOpacity(0.74 + wave * 0.16, on: savedRecapArtifactTourNode)
    }

    private func updateCommitConstellation() {
        guard !currentCommitConstellationPlan.isEmpty else { return }

        for node in currentCommitConstellationPlan.nodes {
            guard let entity = commitConstellationRoot.children.first(where: { $0.name == node.stableID }) else {
                continue
            }

            entity.orientation = narrativeBillboardOrientation(
                from: node.position,
                to: cameraPosition
            )
            let cadence: Float = node.rank == 0 ? 3.8 : 5.2
            let wave = 0.5 + sin(Float(elapsedTime) / cadence * .pi * 2 + Float(node.rank) * 0.54) * 0.5
            let scale = 1 + wave * (node.rank == 0 ? 0.045 : 0.026)
            if !animations.contains(where: { $0.entity === entity }) {
                entity.scale = SIMD3<Float>(repeating: scale)
            }

            if let ring = entity.children.first(where: { $0.name == "\(node.stableID).ring" }) {
                ring.orientation = ring.orientation * simd_quatf(
                    angle: 0.006 + Float(node.rank) * 0.0008,
                    axis: [0, 1, 0]
                )
            }
        }
    }

    private func updateSetDressing() {
        let flamePlan = setDressingPlan.pedestalFlames
        for pedestal in setDressingRoot.children where pedestal.name.hasPrefix("set-pedestal-") {
            let index = setDressingIndex(in: pedestal.name, prefix: "set-pedestal-") ?? 0
            guard index < flamePlan.pedestalCount else { continue }
            if let flame = pedestal.children.first(where: { $0.name.hasPrefix("set-flame-core-") }) {
                let pulse = 1 + sin(
                    Float(elapsedTime) * setDressingPlan.animationCadence.flamePulseRate + Float(index)
                ) * setDressingPlan.animationCadence.flamePulseAmplitude
                flame.scale = [
                    flamePlan.flameXZScale * pulse,
                    flamePlan.flameHeightScale + pulse * 0.08,
                    flamePlan.flameXZScale * pulse
                ]
            }
        }

        let shardPlan = setDressingPlan.floatingShards
        for shard in setDressingRoot.children where shard.name.hasPrefix("floating-shard-") {
            let index = setDressingIndex(in: shard.name, prefix: "floating-shard-") ?? 0
            guard index < shardPlan.shardCount else { continue }
            if let baseY = setDressingBaseHeights[ObjectIdentifier(shard)] {
                shard.position.y = baseY + sin(
                    Float(elapsedTime) * setDressingPlan.animationCadence.shardBobRate + Float(index)
                ) * setDressingPlan.animationCadence.shardBobAmplitude
            }
            shard.orientation = shard.orientation * simd_quatf(
                angle: setDressingPlan.animationCadence.shardRotationStep + Float(index) * 0.0007,
                axis: [0.22, 1, 0.12]
            )
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

    private func clamped(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
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
