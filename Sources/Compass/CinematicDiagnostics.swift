import Foundation

struct CinematicDiagnosticsReport: Equatable {
    var identifier: String
    var repoName: String
    var phase: String
    var immediateTitle: String
    var completedCount: Int
    var influenceIdentifier: String
    var languageMotif: LanguageMotifSnapshot
    var activityMotif: ActivityMotifSnapshot
    var nativeFeedback: NativeFeedbackSnapshot
    var recoveryCue: RecoveryCueSnapshot
    var stageBeat: StageBeatSnapshot
    var stageEffect: StageEffectSnapshot
    var stageAtmosphere: StageAtmosphereSnapshot
    var stagePhasePolish: StagePhasePolishSnapshot
    var narrativeCue: NarrativeCueSnapshot
    var overlayDisplay: OverlayDisplaySnapshot
    var worldText: WorldTextSnapshot
    var briefing: BriefingSnapshot
    var cameraTuning: CameraTuningSnapshot
    var activityTuning: ActivityTuningSnapshot
    var setDressing: SetDressingSnapshot
    var commitConstellation: CommitConstellationSnapshot
    var idleStoryCycle: IdleStoryCycleSnapshot
    var timelineFocus: TimelineFocusSnapshot
    var runRecap: RunRecapSnapshot
    var runRecapShare: RunRecapShareSnapshot
    var runRecapSceneFocus: RunRecapSceneFocusSnapshot
    var runRecapEndCard: RunRecapEndCardSnapshot
    var cameraSnapshots: [CameraSnapshot]

    struct LanguageMotifSnapshot: Equatable {
        var identifier: String
        var language: RepositoryLanguage
        var sigilIdentifier: String
        var styleIdentifier: String
        var ambientSpellIdentifier: String
        var phaseBlend: Double
    }

    struct ActivityMotifSnapshot: Equatable {
        var identifier: String
        var eventKindIdentifier: String
        var sigilIdentifier: String
        var styleIdentifier: String
        var tintSourceIdentifier: String?
        var transitionSpellIdentifier: String?
        var ambientOverrideIdentifier: String?
        var usesCommitAmbient: Bool
        var usesSuccessAmbient: Bool
        var shouldShakeOnTransition: Bool
    }

    struct NativeFeedbackSnapshot: Equatable {
        var identifier: String
        var cueIdentifier: String
        var lifecycleIdentifier: String
        var lifecycleStateIdentifier: String
        var lifecycleActiveCueIdentifier: String
        var lifecycleRecentArchiveIdentifiers: [String]
        var lifecycleRecentArchiveCount: Int
        var lifecycleActiveHistoryEntry: NativeFeedbackHistoryEntrySnapshot?
        var lifecycleArchiveHistoryEntries: [NativeFeedbackHistoryEntrySnapshot]
        var lifecycleHistoryEntryCount: Int
        var sourceIdentifier: String
        var styleIdentifier: String
        var milestoneIdentifier: String
        var affectedNarrativeDescriptorIdentifiers: [String]
    }

    struct NativeFeedbackHistoryEntrySnapshot: Equatable {
        var identifier: String
        var cueIdentifier: String
        var lifecycleIdentifier: String
        var sequence: Int
        var stateIdentifier: String
        var reasonIdentifier: String?
        var milestoneIdentifier: String
        var sourceIdentifier: String?
        var styleIdentifier: String?
        var displayDuration: TimeInterval
    }

    struct RecoveryCueSnapshot: Equatable {
        var identifier: String
        var selectedCueIdentifier: String?
        var sessionNumber: Int?
        var kindIdentifier: String
        var severityIdentifier: String?
        var label: String?
        var detail: String?
        var systemImage: String?
        var visualIdentifier: String
        var treatmentIdentifier: String
        var lightFamilyIdentifier: String
        var fractureLightFamilyIdentifier: String
        var symbolIdentifier: String?
        var phaseLightIntensity: Float
        var intensity: Float
        var postureIdentifier: String
        var arenaEffectIdentifier: String
        var fractureOpacity: Float
        var fractureSpread: Float
        var healingOpacity: Float
        var shouldShakeCamera: Bool
        var cameraShakeIdentifier: String?
    }

    struct StageBeatSnapshot: Equatable {
        var identifier: String
        var phaseIdentifier: String
        var kindIdentifier: String
        var cameraShotIdentifier: String
        var lightFamilyIdentifier: String
        var arenaEffectIdentifier: String
        var phaseLightIntensity: Float
        var shouldShakeCamera: Bool
        var shouldRunVictorySurge: Bool
        var shouldRunHistoryChains: Bool
        var activityAccentIdentifier: String
        var activityEventKindIdentifier: String?
        var activityLightFamilyIdentifier: String?
        var activityArenaEffectIdentifier: String?
    }

    struct StageEffectSnapshot: Equatable {
        var identifier: String
        var phaseEffectIdentifier: String
        var phaseSourceIdentifier: String
        var phaseArenaEffectIdentifier: String
        var activityEffectIdentifier: String?
        var activitySourceIdentifier: String?
        var activityArenaEffectIdentifier: String?
        var recoveryEffectIdentifier: String?
        var recoverySourceIdentifier: String?
        var recoveryArenaEffectIdentifier: String?
        var arenaRingIdentifiers: [String]
        var phaseLightPulseIdentifiers: [String]
        var sparkBurstIdentifiers: [String]
        var historyTrailIdentifiers: [String]
        var victoryCadenceIdentifier: String?
        var cameraShakeIdentifiers: [String]
        var arenaRingCount: Int
        var phaseLightPulseCount: Int
        var sparkBurstCount: Int
        var historyTrailCount: Int
        var tuningIdentifier: String
        var recoveryCueIdentifier: String
        var recoveryCueKindIdentifier: String
        var pressureLevelIdentifier: String
        var pressureFraction: Float
        var energy: Float
        var influenceStyleIdentifier: String
        var influenceIntensity: Float
        var influenceFraction: Float
        var activityLightBoost: Float
        var activityLightBoostFraction: Float
        var runePulseScale: Float
        var activityPulseDuration: TimeInterval
        var ringDurationScale: Float
        var ringScaleMultiplier: Float
        var ringOpacityMultiplier: Float
        var colorAlphaMultiplier: Float
        var pulseIntensityMultiplier: Float
        var pulseDurationMultiplier: Float
        var sparkBirthRateMultiplier: Float
        var historyTrailTargetCount: Int
        var cameraShakeMultiplier: Float
        var cameraShakeDurationMultiplier: Float
        var victoryCadenceMultiplier: Float
    }

    struct StageAtmosphereSnapshot: Equatable {
        var identifier: String
        var beatIdentifier: String
        var phaseIdentifier: String
        var activityIdentifier: String
        var pressureLevelIdentifier: String
        var influenceStyleIdentifier: String
        var influenceIntensity: Float
        var pressureFraction: Float
        var influenceFraction: Float
        var energy: Float
        var pressureHaloIdentifier: String
        var pressureHaloRadius: Float
        var pressureHaloOpacity: Float
        var pressureHaloScale: Float
        var pressureHaloColorAlpha: Float
        var atmosphericPulseIdentifier: String
        var atmosphericPulseCadence: TimeInterval
        var atmosphericPulseAmplitude: Float
        var atmosphericPulseOpacity: Float
        var pressureLightingIdentifier: String
        var phaseLightPressureBoost: Float
        var rimLightPressureBoost: Float
        var pressureLightColorAlpha: Float
        var backdropTintIdentifier: String
        var backdropTintRed: Float
        var backdropTintGreen: Float
        var backdropTintBlue: Float
        var backdropTintOpacity: Float
        var backdropTintBlendFraction: Float
        var floorTintIdentifier: String
        var floorTintRed: Float
        var floorTintGreen: Float
        var floorTintBlue: Float
        var floorTintOpacity: Float
        var floorTintBlendFraction: Float
    }

    struct StagePhasePolishSnapshot: Equatable {
        var identifier: String
        var beatIdentifier: String
        var stageEffectTuningIdentifier: String
        var atmosphereIdentifier: String
        var phaseIdentifier: String
        var activityIdentifier: String
        var recoveryCueIdentifier: String
        var recoveryCueKindIdentifier: String
        var influenceIdentifier: String
        var postureIdentifier: String
        var wizardPoseIdentifier: String
        var poseIntensity: Float
        var staffOrbIdentifier: String
        var staffOrbLightFamilyIdentifier: String
        var staffOrbScale: Float
        var staffOrbEmission: Float
        var staffOrbPulseAmplitude: Float
        var sigilEmphasisIdentifier: String
        var sigilOrbitRadius: Float
        var sigilSealEmphasis: Float
        var sigilVictoryEmphasis: Float
        var sigilPulseAmplitude: Float
        var portalBackdropIdentifier: String
        var portalLightFamilyIdentifier: String
        var portalAperture: Float
        var portalScale: Float
        var portalOpacity: Float
        var backdropAperture: Float
        var backdropOpacityBoost: Float
        var fractureRecoveryIdentifier: String
        var fractureLightFamilyIdentifier: String
        var fractureOpacity: Float
        var fractureSpread: Float
        var healingOpacity: Float
        var cadenceIdentifier: String
        var poseCadence: TimeInterval
        var orbPulseCadence: TimeInterval
        var sigilOrbitCadence: TimeInterval
        var fractureCadence: TimeInterval
    }

    struct NarrativeCueSnapshot: Equatable {
        var identifier: String
        var stageBeatIdentifier: String
        var stagePhasePolishIdentifier: String
        var languageIdentifier: String
        var activityIdentifier: String
        var influenceIdentifier: String
        var nativeFeedbackCueIdentifier: String
        var nativeFeedbackLifecycleIdentifier: String
        var nativeFeedbackSourceIdentifier: String
        var nativeFeedbackStyleIdentifier: String
        var nativeFeedbackMilestoneIdentifier: String
        var nativeFeedbackAffectedDescriptorIdentifiers: [String]
        var questPlaque: NarrativeCueDescriptorSnapshot
        var arenaInscription: NarrativeCueDescriptorSnapshot
        var activityBanner: NarrativeCueDescriptorSnapshot
    }

    struct OverlayDisplaySnapshot: Equatable {
        var identifier: String
        var modeIdentifier: String
        var visiblePillIdentifiers: [String]
        var hudProminenceIdentifier: String
        var chromeStyleIdentifier: String
        var gradientStrength: Double
        var worldTextMaxWidth: Double
        var hudMaxWidth: Double
        var pillLineLimit: Int
        var hudTitleLineLimit: Int
        var hudDetailLineLimit: Int
        var hudProfileLineLimit: Int
        var hudStatusLineLimit: Int
        var overlayOpacity: Double
        var reasonIdentifier: String
        var narrativeCueReadabilityIdentifier: String
        var nativeFeedbackCueIdentifier: String
        var nativeFeedbackLifecycleIdentifier: String
        var nativeFeedbackBannerPolicyIdentifier: String
        var showsNativeFeedbackBanner: Bool
    }

    struct NarrativeCueDescriptorSnapshot: Equatable {
        var identifier: String
        var stableID: String
        var text: String
        var secondaryText: String?
        var glyphIdentifier: String?
        var anchorIdentifier: String
        var visibilityIdentifier: String
        var scale: Float
        var opacity: Float
        var lightFamilyIdentifier: String
        var tintFamilyIdentifier: String
        var cadence: TimeInterval
        var plaqueTreatmentIdentifier: String
        var plaqueTreatmentAccentIdentifier: String
        var plaqueTreatmentRouteIdentifier: String
        var plaqueTreatmentRenderRecipeIdentifier: String
        var plaqueTreatmentRenderPrimitiveIdentifiers: [String]
        var plaqueTreatmentRenderPrimitiveCount: Int
        var layout: NarrativeCueLayoutSnapshot
    }

    struct NarrativeCueLayoutSnapshot: Equatable {
        var identifier: String
        var anchorPosition: SIMD3<Float>
        var facingModeIdentifier: String
        var plateWidth: Float
        var plateHeight: Float
        var primaryTextWidth: Float
        var secondaryTextWidth: Float
        var primaryFontSize: Float
        var secondaryFontSize: Float
        var backingOpacity: Float
        var glyphSideIdentifier: String
        var glyphOffset: SIMD3<Float>
        var plateDepth: Float
        var plateZOffset: Float
        var primaryTextOffset: SIMD3<Float>
        var secondaryTextOffset: SIMD3<Float>
    }

    struct WorldTextSnapshot: Equatable {
        var identifier: String
        var questLabel: String
        var arenaCallout: String
        var activityCallout: String
    }

    struct BriefingSnapshot: Equatable {
        var identifier: String
        var title: String
        var detail: String
    }

    struct CameraTuningSnapshot: Equatable {
        var identifier: String
        var orbitScale: Float
        var pullbackScale: Float
        var heightOffset: Float
        var followResponsiveness: Float
        var followFieldOfView: Float
        var driftScale: Float
        var shakeScale: Float
    }

    struct ActivityTuningSnapshot: Equatable {
        var identifier: String
        var pressureLevelIdentifier: String
        var ambientSpawnCadence: TimeInterval
        var ambientEnemyLimit: Int
        var activityLightBoost: Float
        var activityPressureScale: Float
    }

    struct SetDressingSnapshot: Equatable {
        var identifier: String
        var languageArchitectureIdentifier: String
        var activityMarkerIdentifier: String
        var pedestalLayoutIdentifier: String
        var shardFormationIdentifier: String
        var pedestalSlotCount: Int
        var shardSlotCount: Int
        var layoutGeometryCoverageIdentifier: String
        var layoutGeometryIsBounded: Bool
        var pedestalCount: Int
        var flameLightIntensity: Float
        var flameOpacity: Float
        var rimOpacity: Float
        var shardCount: Int
        var shardEmissionOpacity: Float
        var runeIntensityIdentifier: String
        var animationCadenceIdentifier: String
        var flamePulseRate: Float
        var shardBobRate: Float
        var ambientSpawnCadence: TimeInterval
        var ambientEnemyLimit: Int
        var activityLightBoost: Float
        var materialTextureVariantIdentifier: String
        var backdropTextureAssetIdentifier: String
        var arenaTextureAssetIdentifier: String
        var backdropTextureRouteIdentifier: String
        var arenaTextureRouteIdentifier: String
        var textureRoleCoverageIdentifier: String
        var runeMaterialIdentifier: String
        var runeMaterialTreatmentIdentifier: String
        var runeFloorEmissionOpacity: Float
        var runeSegmentOpacityScale: Float
        var arenaAccentOpacityScale: Float
        var backdropTextureName: String
        var arenaTextureName: String
        var usesFallbackTextureAsset: Bool
    }

    struct CommitConstellationSnapshot: Equatable {
        var identifier: String
        var count: Int
        var newestSubject: String?
        var nodeIdentifiers: [String]
        var branchIdentifiers: [String]
        var focusIdentifier: String
        var focusShotIdentifier: String
        var focusLookTarget: SIMD3<Float>
        var usesFallbackFocus: Bool
    }

    struct IdleStoryCycleSnapshot: Equatable {
        var identifier: String
        var isActive: Bool
        var phaseIdentifier: String
        var sourceDescriptorIdentifier: String
        var targetKindIdentifier: String
        var cadence: TimeInterval
        var cameraTreatmentIdentifier: String
        var anchorTreatmentIdentifier: String
        var choreographyIdentifier: String
        var dwellDuration: TimeInterval
        var transitionDurationScale: Double
        var cameraPressureIdentifier: String
        var targetBias: Float
        var comfortDamping: Float
        var shakeHintIdentifier: String
        var pulseHintIdentifier: String
        var suppressionReason: String
        var phaseCopy: String
        var descriptorIdentifier: String
        var cycleSlot: Int
        var phaseIndex: Int
    }

    struct TimelineFocusSnapshot: Equatable {
        var identifier: String
        var selectedBeatID: String?
        var isActive: Bool
        var kindIdentifier: String
        var descriptorIdentifier: String
        var label: String?
        var cameraShotIdentifier: String
        var lookTarget: SIMD3<Float>?
        var lightFamilyIdentifier: String
        var arenaEffectIdentifier: String
        var phaseLightIntensity: Float
        var commitNodeIdentifier: String?
        var recoveryTreatmentIdentifier: String?
        var recoveryVisualIdentifier: String?
        var usesFallbackTarget: Bool
    }

    struct RunRecapSnapshot: Equatable {
        var identifier: String
        var availabilityIdentifier: String
        var isAvailable: Bool
        var sessionNumber: Int?
        var title: String
        var detail: String
        var status: String
        var statusIdentifier: String
        var styleIdentifier: String
        var colorIdentifier: String
        var systemImage: String
        var latestCompletedSummary: String
        var newestCommitHighlight: String?
        var completedCount: Int
        var commitHighlightCount: Int
        var eventChipCount: Int
        var eventChipIdentifiers: [String]
        var sourceIdentifier: String?
        var flavorStateIdentifier: String
        var flavorIdentifier: String?
        var flavorSourceIdentifier: String?
        var titleSourceIdentifier: String
    }

    struct RunRecapShareSnapshot: Equatable {
        var identifier: String
        var availabilityIdentifier: String
        var availabilityReason: String
        var isAvailable: Bool
        var recapIdentifier: String
        var recapFocusIdentifier: String?
        var endCardIdentifier: String?
        var title: String
        var detail: String
        var status: String
        var commitHighlight: String?
        var eventSummaries: [String]
        var eventSummaryCount: Int
        var visualDescriptorTokens: [String]
        var visualDescriptorTokenCount: Int
        var text: String
        var textLength: Int
    }

    struct RunRecapSceneFocusSnapshot: Equatable {
        var identifier: String
        var isActive: Bool
        var descriptorIdentifier: String
        var recapIdentifier: String
        var terminalBeatID: String?
        var terminalStatusIdentifier: String
        var terminalStyleIdentifier: String
        var cameraShotIdentifier: String
        var lookTarget: SIMD3<Float>?
        var lightFamilyIdentifier: String
        var arenaEffectIdentifier: String
        var phaseLightIntensity: Float
        var commitNodeIdentifier: String?
        var fallbackTargetIdentifier: String?
        var usesFallbackTarget: Bool
    }

    struct RunRecapEndCardSnapshot: Equatable {
        var identifier: String
        var isActive: Bool
        var descriptorIdentifier: String
        var recapIdentifier: String
        var title: String
        var detail: String
        var status: String
        var titleSourceIdentifier: String
        var flavorStateIdentifier: String
        var flavorIdentifier: String?
        var flavorSourceIdentifier: String?
        var styleIdentifier: String
        var colorIdentifier: String
        var anchorIdentifier: String
        var scale: Float
        var cadence: TimeInterval
        var lightFamilyIdentifier: String
        var tintFamilyIdentifier: String
        var glyphIdentifier: String
        var layoutIdentifier: String
        var plateWidth: Float
        var plateHeight: Float
        var plaqueTreatmentIdentifier: String
        var plaqueTreatmentAccentIdentifier: String
        var plaqueTreatmentRouteIdentifier: String
        var plaqueTreatmentRenderRecipeIdentifier: String
        var plaqueTreatmentRenderPrimitiveIdentifiers: [String]
        var plaqueTreatmentRenderPrimitiveCount: Int
        var titleLength: Int
        var detailLength: Int
        var statusLength: Int
    }

    struct CameraSnapshot: Equatable {
        var identifier: String
        var shotIdentifier: String
        var position: SIMD3<Float>
        var fieldOfView: Float
        var transitionDuration: TimeInterval
    }
}

struct CinematicVisualSmokeReport: Equatable {
    static let labelMaxCharacters = 32
    static let detailMaxCharacters = 120
    static let warningIdentifierMaxCharacters = 72

    var status: Status
    var warningIdentifiers: [String]
    var checks: [Check]

    enum Status: String, Equatable {
        case pass
        case warning
    }

    struct Check: Identifiable, Equatable {
        var id: String
        var label: String
        var status: Status
        var warningIdentifier: String?
        var detail: String
    }

    init(reports: [CinematicDiagnosticsReport]) {
        let checks = Self.makeChecks(reports: reports)
        self.checks = checks
        warningIdentifiers = checks.compactMap(\.warningIdentifier)
        status = warningIdentifiers.isEmpty ? .pass : .warning
    }

    static func representative() -> CinematicVisualSmokeReport {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]
        let reports = settingsSamples.flatMap {
            CinematicDiagnostics.representativeSmokeMatrix(influenceSettings: $0)
        }
        let nativeFeedbackReports = CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        let idleStoryReports = CinematicDiagnostics.representativeIdleStoryCycleSmokeReports()
        return CinematicVisualSmokeReport(reports: reports + nativeFeedbackReports + idleStoryReports)
    }

    private static func makeChecks(reports: [CinematicDiagnosticsReport]) -> [Check] {
        [
            narrativeCueReadabilityCheck(reports: reports),
            overlayFallbackUsageCheck(reports: reports),
            chromeStrengthCheck(reports: reports),
            textBoundsCheck(reports: reports),
            assetAvailabilityCheck(reports: reports),
            textureRoleCoverageCheck(reports: reports),
            languageLayoutCoverageCheck(reports: reports),
            activityMaterialTreatmentCoverageCheck(reports: reports),
            cameraPhaseCoverageCheck(reports: reports),
            pressureInfluenceSpreadCheck(reports: reports),
            recoveryCueCoverageCheck(reports: reports),
            nativeFeedbackCueCoverageCheck(reports: reports),
            nativeFeedbackTreatmentCoverageCheck(reports: reports),
            idleStoryCycleCoverageCheck(reports: reports),
            timelineFocusCoverageCheck(reports: reports),
            runRecapSceneFocusCoverageCheck(reports: reports),
            runRecapEndCardCoverageCheck(reports: reports)
        ]
    }

    private static func narrativeCueReadabilityCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let total = reports.count
        guard total > 0 else {
            return check(
                id: "narrative-cue-readability",
                label: "Narrative cue readability",
                isPassing: false,
                warningIdentifier: "visual-smoke.no-reports",
                detail: "no representative reports available"
            )
        }

        let compactReports = reports.filter { $0.overlayDisplay.modeIdentifier == "compact" }
        let metrics = compactReports.map(readabilityMetrics)
        let readableCount = metrics.filter(\.isReadable).count
        let minimumScale = metrics.map(\.minimumScale).min() ?? 0
        let minimumOpacity = metrics.map(\.minimumOpacity).min() ?? 0
        let minimumFontSize = metrics.map(\.minimumPrimaryFontSize).min() ?? 0
        let minimumBackingOpacity = metrics.map(\.minimumBackingOpacity).min() ?? 0
        let isPassing = !compactReports.isEmpty && readableCount == compactReports.count

        return check(
            id: "narrative-cue-readability",
            label: "Narrative cue readability",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.narrative-readability",
            detail: [
                "compact readable \(readableCount)/\(compactReports.count)",
                "reports \(total)",
                "scale \(fixed(minimumScale))",
                "opacity \(fixed(minimumOpacity))",
                "font \(fixed(minimumFontSize))",
                "backing \(fixed(minimumBackingOpacity))"
            ].joined(separator: " | ")
        )
    }

    private static func overlayFallbackUsageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let modes = Set(reports.map(\.overlayDisplay.modeIdentifier))
        let reasons = Set(reports.map(\.overlayDisplay.reasonIdentifier))
        let requiredModes: Set<String> = ["compact", "full", "fallback"]
        let requiredReasons: Set<String> = [
            "in-world-readable-cues",
            "activity-unavailable",
            "missing-repository"
        ]
        let missingModes = requiredModes.subtracting(modes).sorted()
        let missingReasons = requiredReasons.subtracting(reasons).sorted()
        let isPassing = !reports.isEmpty && missingModes.isEmpty && missingReasons.isEmpty
        let fallbackReasons = reasons.filter { reason in
            reports.contains {
                $0.overlayDisplay.modeIdentifier == "fallback"
                    && $0.overlayDisplay.reasonIdentifier == reason
            }
        }
        .sorted()

        return check(
            id: "overlay-fallback-usage",
            label: "Overlay fallback",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.overlay-coverage",
            detail: [
                "modes \(joined(modes))",
                "fallback \(fallbackReasons.isEmpty ? "none" : joined(fallbackReasons))",
                missingModes.isEmpty ? nil : "missing modes \(missingModes.joined(separator: ","))",
                missingReasons.isEmpty ? nil : "missing reasons \(missingReasons.joined(separator: ","))"
            ].compactMap { $0 }.joined(separator: " | ")
        )
    }

    private static func chromeStrengthCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let styleNames = Set(reports.map { chromeStyleName($0.overlayDisplay.chromeStyleIdentifier) })
        let compactGradients = gradients(for: "compact", in: reports)
        let fullGradients = gradients(for: "full", in: reports)
        let fallbackGradients = gradients(for: "fallback", in: reports)
        let modes = Set(reports.map(\.overlayDisplay.modeIdentifier))
        let hasExpectedModes = ["compact", "full", "fallback"].allSatisfy(modes.contains)
        let stylesMatchModes = reports.allSatisfy { report in
            let styleName = chromeStyleName(report.overlayDisplay.chromeStyleIdentifier)
            switch report.overlayDisplay.modeIdentifier {
            case "compact":
                return styleName.hasPrefix("compact-")
            case "full":
                return styleName.hasPrefix("full-")
            case "fallback":
                return styleName.hasPrefix("fallback-")
            default:
                return false
            }
        }
        let strengthOrdering = compactGradients.maxValue < fullGradients.minValue
            && fullGradients.maxValue <= fallbackGradients.minValue
        let isPassing = !reports.isEmpty
            && !styleNames.contains("")
            && hasExpectedModes
            && stylesMatchModes
            && strengthOrdering

        return check(
            id: "chrome-strength",
            label: "Chrome strength",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.chrome-strength",
            detail: [
                "styles \(joined(styleNames))",
                "gradients c\(range(compactGradients))/f\(range(fullGradients))/b\(range(fallbackGradients))"
            ].joined(separator: " | ")
        )
    }

    private static func textBoundsCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let boundedCount = reports.filter(textIsBounded).count
        let isPassing = !reports.isEmpty && boundedCount == reports.count

        return check(
            id: "text-bounds",
            label: "Text bounds",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.text-bounds",
            detail: "\(boundedCount)/\(reports.count) reports fit world, briefing, and cue copy limits"
        )
    }

    private static func assetAvailabilityCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let availableCount = reports.filter(assetsAreAvailable).count
        let backdropTextures = Set(reports.map(\.setDressing.backdropTextureName))
        let arenaTextures = Set(reports.map(\.setDressing.arenaTextureName))
        let generatedBackdropTextures = Set(
            backdropTextures.filter(CinematicTextureAssetCatalog.isGeneratedBackdropTextureName)
        )
        let generatedArenaTextures = Set(
            arenaTextures.filter(CinematicTextureAssetCatalog.isGeneratedArenaTextureName)
        )
        let packagedGeneratedBackdrops = Set(
            generatedBackdropTextures.filter {
                CinematicTextureAssetCatalog.isPackagedResourceAvailable($0, role: .backdrop)
            }
        )
        let packagedGeneratedArenas = Set(
            generatedArenaTextures.filter {
                CinematicTextureAssetCatalog.isPackagedResourceAvailable($0, role: .arena)
            }
        )
        let isPassing = !reports.isEmpty && availableCount == reports.count

        return check(
            id: "asset-availability",
            label: "Asset availability",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.asset-availability",
            detail: [
                "assets \(availableCount)/\(reports.count)",
                "gen backdrops \(generatedBackdropTextures.count)/\(CinematicTextureAssetCatalog.generatedBackdropNames.count)",
                "gen arenas \(generatedArenaTextures.count)/\(CinematicTextureAssetCatalog.generatedArenaNames.count)",
                "packaged backdrops \(packagedGeneratedBackdrops.count)/\(generatedBackdropTextures.count)",
                "packaged arenas \(packagedGeneratedArenas.count)/\(generatedArenaTextures.count)"
            ].joined(separator: " | ")
        )
    }

    private static func textureRoleCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedBackdropRoutes = CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .backdrop)
        let expectedArenaRoutes = CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .arena)
        let backdropRoutes = Set(reports.map(\.setDressing.backdropTextureRouteIdentifier))
        let arenaRoutes = Set(reports.map(\.setDressing.arenaTextureRouteIdentifier))
        let generatedBackdropRoutes = Set(reports.compactMap { report in
            CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(report.setDressing.backdropTextureName)
                ? report.setDressing.backdropTextureRouteIdentifier
                : nil
        })
        let generatedArenaRoutes = Set(reports.compactMap { report in
            CinematicTextureAssetCatalog.isGeneratedArenaTextureName(report.setDressing.arenaTextureName)
                ? report.setDressing.arenaTextureRouteIdentifier
                : nil
        })
        let directRouteCount = reports.filter { !$0.setDressing.usesFallbackTextureAsset }.count
        let isPassing = !reports.isEmpty
            && backdropRoutes.isSuperset(of: expectedBackdropRoutes)
            && generatedBackdropRoutes.isSuperset(of: expectedBackdropRoutes)
            && arenaRoutes.isSuperset(of: expectedArenaRoutes)
            && generatedArenaRoutes.isSuperset(of: expectedArenaRoutes)
            && directRouteCount == reports.count

        return check(
            id: "texture-role-coverage",
            label: "Texture role coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.texture-role-coverage",
            detail: [
                "backdrop \(backdropRoutes.intersection(expectedBackdropRoutes).count)/\(expectedBackdropRoutes.count)",
                "gen backdrop \(generatedBackdropRoutes.intersection(expectedBackdropRoutes).count)/\(expectedBackdropRoutes.count)",
                "arena \(arenaRoutes.intersection(expectedArenaRoutes).count)/\(expectedArenaRoutes.count)",
                "gen arena \(generatedArenaRoutes.intersection(expectedArenaRoutes).count)/\(expectedArenaRoutes.count)",
                "direct \(directRouteCount)/\(reports.count)"
            ].joined(separator: " | ")
        )
    }

    private static func languageLayoutCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedPedestalLayouts = CinematicSetDressingGeometryCatalog.expectedPedestalLayoutIdentifiers
        let expectedShardFormations = CinematicSetDressingGeometryCatalog.expectedShardFormationIdentifiers
        let pedestalLayouts = Set(reports.map(\.setDressing.pedestalLayoutIdentifier))
        let shardFormations = Set(reports.map(\.setDressing.shardFormationIdentifier))
        let completePedestalReports = reports.filter {
            $0.setDressing.pedestalSlotCount == CinematicSetDressingPlan.pedestalCountRange.upperBound
        }.count
        let completeShardReports = reports.filter {
            $0.setDressing.shardSlotCount == CinematicSetDressingPlan.shardCountRange.upperBound
        }.count
        let boundedReports = reports.filter(\.setDressing.layoutGeometryIsBounded).count
        let isPassing = !reports.isEmpty
            && pedestalLayouts.isSuperset(of: expectedPedestalLayouts)
            && shardFormations.isSuperset(of: expectedShardFormations)
            && completePedestalReports == reports.count
            && completeShardReports == reports.count
            && boundedReports == reports.count

        return check(
            id: "language-layout-coverage",
            label: "Language layout coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.language-layout-coverage",
            detail: [
                "pedestals \(pedestalLayouts.intersection(expectedPedestalLayouts).count)/\(expectedPedestalLayouts.count)",
                "shards \(shardFormations.intersection(expectedShardFormations).count)/\(expectedShardFormations.count)",
                "slot maps \(completePedestalReports)/\(completeShardReports)",
                "bounds \(boundedReports)/\(reports.count)"
            ].joined(separator: " | ")
        )
    }

    private static func activityMaterialTreatmentCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedMaterials = CinematicRuneMaterialTreatmentCatalog.expectedRuneMaterialIdentifiers
        let expectedTreatments = CinematicRuneMaterialTreatmentCatalog.expectedTreatmentIdentifiers
        let materials = Set(reports.map(\.setDressing.runeMaterialIdentifier))
        let treatments = Set(reports.map(\.setDressing.runeMaterialTreatmentIdentifier))
        let treatmentValuesInBounds = reports.filter { report in
            CinematicSetDressingPlan.runeFloorEmissionOpacityRange.contains(report.setDressing.runeFloorEmissionOpacity)
                && CinematicSetDressingPlan.runeSegmentOpacityScaleRange.contains(report.setDressing.runeSegmentOpacityScale)
                && CinematicSetDressingPlan.arenaAccentOpacityScaleRange.contains(report.setDressing.arenaAccentOpacityScale)
        }.count
        let isPassing = !reports.isEmpty
            && materials.isSuperset(of: expectedMaterials)
            && treatments.isSuperset(of: expectedTreatments)
            && treatmentValuesInBounds == reports.count

        return check(
            id: "activity-material-treatment",
            label: "Activity material treatment",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.activity-material-treatment",
            detail: [
                "materials \(materials.intersection(expectedMaterials).count)/\(expectedMaterials.count)",
                "treatments \(treatments.intersection(expectedTreatments).count)/\(expectedTreatments.count)",
                "bounds \(treatmentValuesInBounds)/\(reports.count)"
            ].joined(separator: " | ")
        )
    }

    private static func cameraPhaseCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedShots = Set(CinematicCameraShot.allCases.map(\.identifier))
        let expectedEvents = Set(CinematicActivityEventKind.allCases.map(\.rawValue))
        let expectedActivityCaseIDs = Set(CinematicDiagnostics.representativeActivityCases().map(\.identifier))
        let completeCameraReports = reports.filter {
            Set($0.cameraSnapshots.map(\.shotIdentifier)) == expectedShots
        }.count
        let phases = Set(reports.map(\.phase))
        let shotCoverage = Set(reports.flatMap { $0.cameraSnapshots.map(\.shotIdentifier) })
        let eventCoverage = Set(reports.map(\.activityMotif.eventKindIdentifier))
        let activityCaseCoverage = Set(reports.compactMap(activityCaseIdentifier))
        let isPassing = !reports.isEmpty
            && completeCameraReports == reports.count
            && shotCoverage == expectedShots
            && eventCoverage.isSuperset(of: expectedEvents)
            && activityCaseCoverage.isSuperset(of: expectedActivityCaseIDs)

        return check(
            id: "camera-phase-coverage",
            label: "Camera/phase coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.camera-phase-coverage",
            detail: [
                "shots \(shotCoverage.count)/\(expectedShots.count)",
                "complete \(completeCameraReports)/\(reports.count)",
                "phases \(phases.count)",
                "activity cases \(activityCaseCoverage.count)/\(expectedActivityCaseIDs.count)"
            ].joined(separator: " | ")
        )
    }

    private static func pressureInfluenceSpreadCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedPressure = Set(["clean", "light", "moderate", "heavy"])
        let effectPressure = Set(reports.map(\.stageEffect.pressureLevelIdentifier))
        let atmospherePressure = Set(reports.map(\.stageAtmosphere.pressureLevelIdentifier))
        let activityPressure = Set(reports.map(\.activityTuning.pressureLevelIdentifier))
        let influenceStyles = Set(reports.map(\.stageEffect.influenceStyleIdentifier))
        let pressureFractions = reports.map(\.stageEffect.pressureFraction)
        let influenceFractions = reports.map(\.stageEffect.influenceFraction)
        let pressureRange = valueRange(pressureFractions)
        let influenceRange = valueRange(influenceFractions)
        let isPassing = !reports.isEmpty
            && effectPressure.isSuperset(of: expectedPressure)
            && atmospherePressure.isSuperset(of: expectedPressure)
            && activityPressure.isSuperset(of: expectedPressure)
            && influenceStyles == Set(CinematicInfluenceSettings.CameraStyle.allCases.map(\.rawValue))
            && pressureRange.hasSpread
            && influenceRange.hasSpread

        return check(
            id: "pressure-influence-spread",
            label: "Pressure/influence spread",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.pressure-influence-spread",
            detail: [
                "pressure \(joined(effectPressure)) \(range(pressureRange))",
                "influence \(joined(influenceStyles)) \(range(influenceRange))"
            ].joined(separator: " | ")
        )
    }

    private static func recoveryCueCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedKinds = Set(["none", "failedVerify", "dirtyWorktree", "promotionFailed"])
        let expectedTreatments = Set(["none", "verify-failure", "dirty-cleanup", "promotion-branch"])
        let kinds = Set(reports.map(\.recoveryCue.kindIdentifier))
        let treatments = Set(reports.map(\.recoveryCue.treatmentIdentifier))
        let lights = Set(reports.map(\.recoveryCue.lightFamilyIdentifier))
        let symbols = Set(reports.compactMap(\.recoveryCue.symbolIdentifier))
        let cueReports = reports.filter { $0.recoveryCue.kindIdentifier != "none" }
        let distinctEffects = Set(cueReports.compactMap(\.stageEffect.recoveryArenaEffectIdentifier))
        let isPassing = !reports.isEmpty
            && kinds.isSuperset(of: expectedKinds)
            && treatments.isSuperset(of: expectedTreatments)
            && lights.isSuperset(of: ["edit", "failure", "git"])
            && symbols.isSuperset(of: ["verify-fracture-seal", "edit-amber-cleanup", "git-failure-branch"])
            && distinctEffects.isSuperset(of: ["charge", "activity-pulse", "history-chains"])

        return check(
            id: "recovery-cue-coverage",
            label: "Recovery cue coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.recovery-cue-coverage",
            detail: [
                "kinds \(joined(kinds))",
                "effects \(joined(distinctEffects))"
            ].joined(separator: " | ")
        )
    }

    private static func nativeFeedbackCueCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter {
            $0.nativeFeedback.cueIdentifier != "none"
                && $0.nativeFeedback.lifecycleStateIdentifier == "active"
        }
        let expectedStyles = Set(["verify", "warning", "failure"])
        let styles = Set(activeReports.map(\.nativeFeedback.styleIdentifier))
        let sourceFamilies = Set(activeReports.compactMap(nativeFeedbackSourceFamily))
        let affectedDescriptors = Set(activeReports.flatMap(\.nativeFeedback.affectedNarrativeDescriptorIdentifiers))
        let expectedDescriptors = Set([
            "narrative.quest.plaque",
            "narrative.arena.inscription",
            "narrative.activity.banner"
        ])
        let anchorRoutes = Set(activeReports.flatMap(nativeFeedbackAnchorRouteIdentifiers))
        let expectedAnchorRoutes = Set(["seal", "warning", "fracture"])
        let visibleBannerReports = activeReports.filter {
            $0.overlayDisplay.showsNativeFeedbackBanner
                && $0.overlayDisplay.nativeFeedbackBannerPolicyIdentifier == "visible"
        }.count
        let consistentActiveReports = activeReports.filter(nativeFeedbackActiveRoutesAreConsistent).count
        let expiredArchivedReports = reports.filter(nativeFeedbackExpiredLifecycleIsArchived).count

        let isPassing = !activeReports.isEmpty
            && styles.isSuperset(of: expectedStyles)
            && sourceFamilies.isSuperset(of: ["native", "run-cue"])
            && affectedDescriptors.isSuperset(of: expectedDescriptors)
            && anchorRoutes.isSuperset(of: expectedAnchorRoutes)
            && visibleBannerReports == activeReports.count
            && consistentActiveReports == activeReports.count
            && expiredArchivedReports > 0

        return check(
            id: "native-feedback-cue-coverage",
            label: "Native feedback coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.native-feedback-cue-coverage",
            detail: [
                "active \(activeReports.count)",
                "styles \(styles.intersection(expectedStyles).count)/\(expectedStyles.count)",
                "sources \(joined(sourceFamilies))",
                "desc \(affectedDescriptors.intersection(expectedDescriptors).count)/\(expectedDescriptors.count)",
                "routes \(joined(anchorRoutes))",
                "visible \(visibleBannerReports)/\(activeReports.count)",
                "life \(consistentActiveReports)/\(activeReports.count)",
                "expired \(expiredArchivedReports)"
            ].joined(separator: "|")
        )
    }

    private static func nativeFeedbackTreatmentCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter {
            $0.nativeFeedback.cueIdentifier != "none"
                && $0.nativeFeedback.lifecycleStateIdentifier == "active"
        }
        let expectedPairs = nativeFeedbackTreatmentExpectations
        let expectedAccents = Set(expectedPairs.map(\.accentIdentifier))
        let expectedRoutes = Set(expectedPairs.map(\.routeIdentifier))
        let expectedPairIdentifiers = Set(expectedPairs.map(\.pairIdentifier))
        let observedAccents = Set(activeReports.map(\.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier))
        let observedRoutes = Set(activeReports.map(\.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier))
        let observedPairIdentifiers = Set(activeReports.compactMap(nativeFeedbackTreatmentPairIdentifier))
        let expectedReportCount = activeReports.filter(nativeFeedbackTreatmentMatchesExpectedPair).count
        let consistentSurfaceCount = activeReports.filter(nativeFeedbackTreatmentSurfacesMatch).count
        let meaningfulParameterCount = activeReports.filter(nativeFeedbackTreatmentParametersAreMeaningful).count
        let primitiveSetCount = activeReports.filter(nativeFeedbackTreatmentPrimitivesMatchExpected).count

        let isPassing = !activeReports.isEmpty
            && observedAccents.isSuperset(of: expectedAccents)
            && observedRoutes.isSuperset(of: expectedRoutes)
            && observedPairIdentifiers.isSuperset(of: expectedPairIdentifiers)
            && expectedReportCount == activeReports.count
            && consistentSurfaceCount == activeReports.count
            && meaningfulParameterCount == activeReports.count
            && primitiveSetCount == activeReports.count

        return check(
            id: "native-feedback-treatment-coverage",
            label: "Native feedback treatment",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.native-feedback-treatment-coverage",
            detail: [
                "active \(activeReports.count)",
                "accents \(observedAccents.intersection(expectedAccents).count)/\(expectedAccents.count)",
                "routes \(observedRoutes.intersection(expectedRoutes).count)/\(expectedRoutes.count)",
                "pairs \(observedPairIdentifiers.intersection(expectedPairIdentifiers).count)/\(expectedPairIdentifiers.count)",
                "surfaces \(consistentSurfaceCount)/\(activeReports.count)",
                "params \(meaningfulParameterCount)/\(activeReports.count)",
                "prims \(primitiveSetCount)/\(activeReports.count)"
            ].joined(separator: "|")
        )
    }

    private static func idleStoryCycleCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedPhases = Set(
            CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.map(\.rawValue)
        )
        let activeReports = reports.filter(\.idleStoryCycle.isActive)
        let emptyCount = reports.filter { !$0.idleStoryCycle.isActive }.count
        let phases = Set(activeReports.map(\.idleStoryCycle.phaseIdentifier))
        let sourceRouteCount = activeReports.filter {
            $0.idleStoryCycle.sourceDescriptorIdentifier != "none"
                && !$0.idleStoryCycle.sourceDescriptorIdentifier.isEmpty
        }.count
        let cameraTreatmentCount = activeReports.filter {
            $0.idleStoryCycle.cameraTreatmentIdentifier != "none"
        }.count
        let anchorTreatmentCount = activeReports.filter {
            $0.idleStoryCycle.anchorTreatmentIdentifier != "none"
        }.count
        let choreographyRouteCount = activeReports.filter {
            $0.idleStoryCycle.choreographyIdentifier != "none"
                && !$0.idleStoryCycle.choreographyIdentifier.isEmpty
        }.count
        let cameraPressureCount = activeReports.filter {
            $0.idleStoryCycle.cameraPressureIdentifier != "none"
                && !$0.idleStoryCycle.cameraPressureIdentifier.isEmpty
        }.count
        let boundedCopyCount = activeReports.filter {
            !$0.idleStoryCycle.phaseCopy.isEmpty
                && $0.idleStoryCycle.phaseCopy.count <= CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters
        }.count
        let cadenceCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.cadenceRange.contains($0.idleStoryCycle.cadence)
        }.count
        let dwellCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.dwellDurationRange.contains($0.idleStoryCycle.dwellDuration)
        }.count
        let transitionScaleCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.transitionDurationScaleRange.contains(
                $0.idleStoryCycle.transitionDurationScale
            )
        }.count
        let targetBiasCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.targetBiasRange.contains($0.idleStoryCycle.targetBias)
        }.count
        let comfortDampingCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.comfortDampingRange.contains($0.idleStoryCycle.comfortDamping)
        }.count
        let distinctChoreographyCount = Set(activeReports.map(\.idleStoryCycle.choreographyIdentifier)).count
        let distinctCameraPressureCount = Set(activeReports.map(\.idleStoryCycle.cameraPressureIdentifier)).count
        let distinctTimingCount = Set(
            activeReports.map {
                [
                    fixed($0.idleStoryCycle.cadence),
                    fixed($0.idleStoryCycle.dwellDuration),
                    fixed($0.idleStoryCycle.transitionDurationScale),
                    fixed($0.idleStoryCycle.targetBias)
                ].joined(separator: "/")
            }
        ).count
        let orderedPhaseDetail = CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases
            .map(\.rawValue)
            .filter(phases.contains)
            .joined(separator: "/")
        let expectedDistinctRoutes = expectedPhases.count
        let isPassing = !reports.isEmpty
            && !activeReports.isEmpty
            && emptyCount > 0
            && phases.isSuperset(of: expectedPhases)
            && sourceRouteCount == activeReports.count
            && cameraTreatmentCount == activeReports.count
            && anchorTreatmentCount == activeReports.count
            && choreographyRouteCount == activeReports.count
            && cameraPressureCount == activeReports.count
            && boundedCopyCount == activeReports.count
            && cadenceCount == activeReports.count
            && dwellCount == activeReports.count
            && transitionScaleCount == activeReports.count
            && targetBiasCount == activeReports.count
            && comfortDampingCount == activeReports.count
            && distinctChoreographyCount >= expectedDistinctRoutes
            && distinctCameraPressureCount >= expectedDistinctRoutes
            && distinctTimingCount >= expectedDistinctRoutes
        let detail = isPassing
            ? [
                orderedPhaseDetail,
                "routes \(sourceRouteCount)/\(activeReports.count)",
                "c\(distinctChoreographyCount)/\(expectedDistinctRoutes)",
                "t\(distinctTimingCount)/\(expectedDistinctRoutes)",
                "p\(distinctCameraPressureCount)/\(expectedDistinctRoutes)"
            ].joined(separator: " ")
            : [
                "routes \(sourceRouteCount)/\(activeReports.count)",
                "choreo \(distinctChoreographyCount)/\(expectedDistinctRoutes)",
                "timing \(distinctTimingCount)/\(expectedDistinctRoutes)",
                "pressure \(distinctCameraPressureCount)/\(expectedDistinctRoutes)",
                "phases \(orderedPhaseDetail)"
            ].joined(separator: " ")

        return check(
            id: "idle-story-cycle-coverage",
            label: "Idle story cycle",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.idle-story-cycle",
            detail: detail
        )
    }

    private static func timelineFocusCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedKinds = Set(["none", "plan", "develop", "verify", "outcome", "commit", "recovery", "failed-verify"])
        let kinds = Set(reports.map(\.timelineFocus.kindIdentifier))
        let shots = Set(reports.map(\.timelineFocus.cameraShotIdentifier))
        let lights = Set(reports.map(\.timelineFocus.lightFamilyIdentifier))
        let recoveryTreatments = Set(reports.compactMap(\.timelineFocus.recoveryTreatmentIdentifier))
        let commitNodeCount = reports.compactMap(\.timelineFocus.commitNodeIdentifier).count
        let fallbackCount = reports.filter(\.timelineFocus.usesFallbackTarget).count
        let isPassing = !reports.isEmpty
            && kinds.isSuperset(of: expectedKinds)
            && shots.isSuperset(of: ["none", "wide", "cast-prep", "overhead", "victory", "commit-constellation", "failure"])
            && lights.isSuperset(of: ["none", "scan", "shell", "verify", "git", "failure"])
            && recoveryTreatments.isSuperset(of: ["verify-failure", "dirty-cleanup", "promotion-branch"])
            && commitNodeCount > 0

        return check(
            id: "timeline-focus-coverage",
            label: "Timeline focus coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.timeline-focus-coverage",
            detail: [
                "kinds \(joined(kinds))",
                "shots \(joined(shots))",
                "recovery \(joined(recoveryTreatments))",
                "commit nodes \(commitNodeCount)",
                "fallbacks \(fallbackCount)"
            ].joined(separator: " | ")
        )
    }

    private static func runRecapSceneFocusCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter(\.runRecapSceneFocus.isActive)
        let emptyCount = reports.filter { !$0.runRecapSceneFocus.isActive }.count
        let styles = Set(activeReports.map(\.runRecapSceneFocus.terminalStyleIdentifier))
        let shots = Set(activeReports.map(\.runRecapSceneFocus.cameraShotIdentifier))
        let lights = Set(activeReports.map(\.runRecapSceneFocus.lightFamilyIdentifier))
        let effects = Set(activeReports.map(\.runRecapSceneFocus.arenaEffectIdentifier))
        let descriptorCount = Set(activeReports.map(\.runRecapSceneFocus.descriptorIdentifier)).count
        let commitNodeCount = activeReports.compactMap(\.runRecapSceneFocus.commitNodeIdentifier).count
        let fallbackCount = activeReports.filter(\.runRecapSceneFocus.usesFallbackTarget).count
        let lookTargetCount = activeReports.compactMap(\.runRecapSceneFocus.lookTarget).count
        let isPassing = !reports.isEmpty
            && !activeReports.isEmpty
            && emptyCount > 0
            && styles.isSuperset(of: ["success", "failure", "warning"])
            && shots.isSuperset(of: ["victory", "failure", "wide"])
            && lights.isSuperset(of: ["verify", "failure", "pressure"])
            && effects.isSuperset(of: ["victory", "charge", "activity-pulse"])
            && descriptorCount > 0
            && commitNodeCount > 0
            && fallbackCount > 0
            && lookTargetCount == activeReports.count

        return check(
            id: "run-recap-focus-coverage",
            label: "Run recap focus coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.run-recap-focus-coverage",
            detail: [
                "active \(activeReports.count)",
                "empty \(emptyCount)",
                "styles \(slashJoined(styles))",
                "shots \(slashJoined(shots))",
                "l/e \(lights.count)/\(effects.count)",
                "commit nodes \(commitNodeCount) fallbacks \(fallbackCount)"
            ].joined(separator: " ")
        )
    }

    private static func runRecapEndCardCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter(\.runRecapEndCard.isActive)
        let emptyCount = reports.filter { !$0.runRecapEndCard.isActive }.count
        let styles = Set(activeReports.map(\.runRecapEndCard.styleIdentifier))
        let titleSources = Set(activeReports.map(\.runRecapEndCard.titleSourceIdentifier))
        let flavorStates = Set(activeReports.map(\.runRecapEndCard.flavorStateIdentifier))
        let anchors = Set(activeReports.map(\.runRecapEndCard.anchorIdentifier))
        let treatments = Set(activeReports.map(\.runRecapEndCard.plaqueTreatmentAccentIdentifier))
        let glyphs = Set(activeReports.map(\.runRecapEndCard.glyphIdentifier))
        let boundedCount = reports.filter(runRecapEndCardCopyIsBounded).count
        let isPassing = !reports.isEmpty
            && !activeReports.isEmpty
            && emptyCount > 0
            && styles.isSuperset(of: ["success", "failure", "warning"])
            && titleSources.isSuperset(of: ["deterministic", "generated"])
            && flavorStates.isSuperset(of: ["deterministic", "applied"])
            && anchors.isSuperset(of: ["victory-arch", "fracture-gate", "right-warning-pylon"])
            && treatments.isSuperset(of: ["verify-seal", "failure-fracture", "warning-rails"])
            && glyphs.isSuperset(of: ["recap.success.seal", "recap.failure.fracture", "recap.warning.rails"])
            && boundedCount == reports.count

        return check(
            id: "run-recap-end-card-coverage",
            label: "Run recap end card",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.run-recap-end-card",
            detail: [
                "active \(activeReports.count) empty \(emptyCount)",
                "bounded \(boundedCount)/\(reports.count)",
                "styles \(slashJoined(styles))",
                "titles \(slashJoined(titleSources))",
                "flavors \(slashJoined(flavorStates))",
                "treat \(treatments.count)"
            ].joined(separator: " ")
        )
    }

    private struct ReadabilityMetrics {
        var isReadable: Bool
        var minimumScale: Float
        var minimumOpacity: Float
        var minimumPrimaryFontSize: Float
        var minimumBackingOpacity: Float
    }

    private struct NumericRange {
        var minValue: Float
        var maxValue: Float

        var hasSpread: Bool {
            maxValue > minValue
        }
    }

    private struct NativeFeedbackTreatmentExpectation {
        var sourceIdentifier: String
        var accentIdentifier: String
        var routeIdentifier: String
        var primitiveIdentifiers: [String]

        var pairIdentifier: String {
            "\(accentIdentifier)/\(routeIdentifier)"
        }

        var primitiveSetIdentifier: String {
            primitiveIdentifiers.isEmpty ? "none" : primitiveIdentifiers.joined(separator: ",")
        }
    }

    private struct NativeFeedbackTreatmentParameters {
        var accentIdentifier: String
        var routeIdentifier: String
        var emissionBoost: Float
        var edgeRailOpacity: Float
        var braceOpacity: Float
        var fractureOpacity: Float
        var pulseScale: Float

        var valuesAreBounded: Bool {
            (Float(0)...Float(0.42)).contains(emissionBoost)
                && (Float(0)...Float(0.9)).contains(edgeRailOpacity)
                && (Float(0)...Float(0.9)).contains(braceOpacity)
                && (Float(0)...Float(0.9)).contains(fractureOpacity)
                && (Float(0.96)...Float(1.12)).contains(pulseScale)
        }

        init?(_ identifier: String) {
            let pieces = identifier.split(separator: "|").map(String.init)
            guard let accentIdentifier = pieces.first,
                  accentIdentifier != "none",
                  let routePiece = pieces.first(where: { $0.hasPrefix("route:") })
            else {
                return nil
            }

            func tokenValue(_ prefix: String) -> Float? {
                guard let piece = pieces.first(where: { $0.hasPrefix(prefix) }) else {
                    return nil
                }
                return Float(String(piece.dropFirst(prefix.count)))
            }

            let routeIdentifier = String(routePiece.dropFirst("route:".count))
            guard !routeIdentifier.isEmpty,
                  routeIdentifier != "none",
                  let emissionBoost = tokenValue("emit"),
                  let edgeRailOpacity = tokenValue("rails"),
                  let braceOpacity = tokenValue("braces"),
                  let fractureOpacity = tokenValue("fracture"),
                  let pulseScale = tokenValue("pulse")
            else {
                return nil
            }

            self.accentIdentifier = accentIdentifier
            self.routeIdentifier = routeIdentifier
            self.emissionBoost = emissionBoost
            self.edgeRailOpacity = edgeRailOpacity
            self.braceOpacity = braceOpacity
            self.fractureOpacity = fractureOpacity
            self.pulseScale = pulseScale
        }

        func hasMeaningfulValues(for accentIdentifier: String) -> Bool {
            guard valuesAreBounded,
                  self.accentIdentifier == accentIdentifier,
                  emissionBoost > 0,
                  edgeRailOpacity > 0,
                  braceOpacity > 0,
                  pulseScale > 1
            else {
                return false
            }

            switch accentIdentifier {
            case "verify-seal":
                return fractureOpacity == 0
            case "warning-rails", "failure-fracture", "retry-braces":
                return fractureOpacity > 0
            default:
                return false
            }
        }
    }

    private static let nativeFeedbackTreatmentExpectations = [
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "native:verifyStarted",
            accentIdentifier: "verify-seal",
            routeIdentifier: "verifyStarted.verify",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "seal.left", "seal.right"]
        ),
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "run-cue:11:dirtyWorktree",
            accentIdentifier: "warning-rails",
            routeIdentifier: "developRetrying.warning.dirtyWorktree",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "warning.left", "warning.right"]
        ),
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "native:postChecksFailed",
            accentIdentifier: "failure-fracture",
            routeIdentifier: "postChecksFailed.failure",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "fracture.diagonal.a", "fracture.diagonal.b"]
        ),
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "run-cue:7:failedVerify",
            accentIdentifier: "retry-braces",
            routeIdentifier: "developRetrying.failure.failedVerify",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "retry.brace.left", "retry.brace.right", "retry.cross"]
        )
    ]

    private static func readabilityMetrics(_ report: CinematicDiagnosticsReport) -> ReadabilityMetrics {
        let descriptors = narrativeCueDescriptors(report)
        let minimumScale = descriptors.map(\.scale).min() ?? 0
        let minimumOpacity = descriptors.map(\.opacity).min() ?? 0
        let minimumPrimaryFontSize = descriptors.map(\.layout.primaryFontSize).min() ?? 0
        let minimumBackingOpacity = descriptors.map(\.layout.backingOpacity).min() ?? 0
        let hasReadableText = descriptors.allSatisfy {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.visibilityIdentifier != "dim"
        }
        let hasReadableLayout = descriptors.allSatisfy {
            $0.layout.plateWidth > 0
                && $0.layout.plateHeight > 0
                && $0.layout.primaryTextWidth > 0
                && $0.layout.primaryFontSize > 0
        }
        let isReadable = descriptors.count == 3
            && hasReadableText
            && hasReadableLayout
            && minimumScale >= CinematicNarrativeCueReadabilitySignals.readableScaleThreshold
            && minimumOpacity >= CinematicNarrativeCueReadabilitySignals.readableOpacityThreshold
            && minimumPrimaryFontSize >= CinematicNarrativeCueReadabilitySignals.readablePrimaryFontSizeThreshold
            && minimumBackingOpacity >= CinematicNarrativeCueReadabilitySignals.readableBackingOpacityThreshold

        return ReadabilityMetrics(
            isReadable: isReadable,
            minimumScale: minimumScale,
            minimumOpacity: minimumOpacity,
            minimumPrimaryFontSize: minimumPrimaryFontSize,
            minimumBackingOpacity: minimumBackingOpacity
        )
    }

    private static func narrativeCueDescriptors(
        _ report: CinematicDiagnosticsReport
    ) -> [CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot] {
        [
            report.narrativeCue.questPlaque,
            report.narrativeCue.arenaInscription,
            report.narrativeCue.activityBanner
        ]
    }

    private static func textIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        string(report.worldText.questLabel, maxCharacters: CinematicWorldTextService.questLabelMaxCharacters)
            && string(report.worldText.arenaCallout, maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters)
            && string(report.worldText.activityCallout, maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters)
            && wordCount(report.worldText.questLabel) <= CinematicWorldTextService.questLabelMaxWords
            && wordCount(report.worldText.arenaCallout) <= CinematicWorldTextService.arenaCalloutMaxWords
            && wordCount(report.worldText.activityCallout) <= CinematicWorldTextService.activityCalloutMaxWords
            && string(report.briefing.title, maxCharacters: CinematicBriefingService.titleMaxCharacters)
            && string(report.briefing.detail, maxCharacters: CinematicBriefingService.detailMaxCharacters)
            && cueTextIsBounded(
                report.narrativeCue.questPlaque,
                maxCharacters: CinematicWorldTextService.questLabelMaxCharacters,
                maxWords: CinematicWorldTextService.questLabelMaxWords
            )
            && cueTextIsBounded(
                report.narrativeCue.arenaInscription,
                maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters,
                maxWords: CinematicWorldTextService.arenaCalloutMaxWords
            )
            && cueTextIsBounded(
                report.narrativeCue.activityBanner,
                maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters,
                maxWords: CinematicWorldTextService.activityCalloutMaxWords
            )
            && (report.narrativeCue.questPlaque.secondaryText?.count ?? 0)
                <= CinematicBriefingService.titleMaxCharacters
            && runRecapShareCopyIsBounded(report)
            && runRecapEndCardCopyIsBounded(report)
    }

    private static func runRecapShareCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShare
        return string(snapshot.identifier, maxCharacters: CinematicRunRecapSharePlan.identifierMaxCharacters)
            && string(snapshot.title, maxCharacters: CinematicRunRecapPlan.titleLimit)
            && string(snapshot.detail, maxCharacters: CinematicRunRecapPlan.detailLimit)
            && string(snapshot.status, maxCharacters: CinematicRunRecapPlan.statusLimit)
            && string(snapshot.text, maxCharacters: CinematicRunRecapSharePlan.textMaxCharacters)
            && snapshot.textLength == snapshot.text.count
            && snapshot.eventSummaryCount == snapshot.eventSummaries.count
            && snapshot.eventSummaryCount <= CinematicRunRecapSharePlan.eventSummaryLimit
            && snapshot.eventSummaries.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapSharePlan.eventSummaryMaxCharacters)
            }
            && snapshot.visualDescriptorTokenCount == snapshot.visualDescriptorTokens.count
            && snapshot.visualDescriptorTokenCount <= CinematicRunRecapSharePlan.visualDescriptorTokenLimit
            && snapshot.visualDescriptorTokens.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapSharePlan.visualDescriptorTokenMaxCharacters)
            }
    }

    private static func runRecapEndCardCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapEndCard
        guard snapshot.isActive else {
            return snapshot.titleLength == 0
                && snapshot.detailLength == 0
                && snapshot.statusLength == 0
        }

        return string(snapshot.title, maxCharacters: CinematicRunRecapEndCardPlan.titleMaxCharacters)
            && string(snapshot.detail, maxCharacters: CinematicRunRecapEndCardPlan.detailMaxCharacters)
            && string(snapshot.status, maxCharacters: CinematicRunRecapEndCardPlan.statusMaxCharacters)
            && snapshot.titleLength == snapshot.title.count
            && snapshot.detailLength == snapshot.detail.count
            && snapshot.statusLength == snapshot.status.count
    }

    private static func cueTextIsBounded(
        _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot,
        maxCharacters: Int,
        maxWords: Int
    ) -> Bool {
        string(descriptor.text, maxCharacters: maxCharacters)
            && wordCount(descriptor.text) <= maxWords
    }

    private static func assetsAreAvailable(_ report: CinematicDiagnosticsReport) -> Bool {
        let identifiersArePresent = [
            report.setDressing.identifier,
            report.setDressing.languageArchitectureIdentifier,
            report.setDressing.activityMarkerIdentifier,
            report.setDressing.pedestalLayoutIdentifier,
            report.setDressing.shardFormationIdentifier,
            report.setDressing.layoutGeometryCoverageIdentifier,
            report.setDressing.runeIntensityIdentifier,
            report.setDressing.animationCadenceIdentifier,
            report.setDressing.materialTextureVariantIdentifier,
            report.setDressing.backdropTextureAssetIdentifier,
            report.setDressing.arenaTextureAssetIdentifier,
            report.setDressing.backdropTextureRouteIdentifier,
            report.setDressing.arenaTextureRouteIdentifier,
            report.setDressing.textureRoleCoverageIdentifier,
            report.setDressing.runeMaterialIdentifier,
            report.setDressing.runeMaterialTreatmentIdentifier,
            report.setDressing.backdropTextureName,
            report.setDressing.arenaTextureName
        ]
        .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let textureNamesAreRecognized = CinematicTextureAssetCatalog.recognizes(
            report.setDressing.backdropTextureName,
            role: .backdrop
        ) && CinematicTextureAssetCatalog.recognizes(
            report.setDressing.arenaTextureName,
            role: .arena
        )
        let backdropTextureIsPackaged = CinematicTextureAssetCatalog.isPackagedResourceAvailable(
            report.setDressing.backdropTextureName,
            role: .backdrop
        )
        let arenaTextureIsPackaged = CinematicTextureAssetCatalog.isPackagedResourceAvailable(
            report.setDressing.arenaTextureName,
            role: .arena
        )

        return identifiersArePresent
            && textureNamesAreRecognized
            && backdropTextureIsPackaged
            && arenaTextureIsPackaged
    }

    private static func activityCaseIdentifier(_ report: CinematicDiagnosticsReport) -> String? {
        if report.overlayDisplay.reasonIdentifier == "missing-repository" {
            return "missing-repository"
        }
        switch report.activityMotif.eventKindIdentifier {
        case "unavailable":
            return "unavailable"
        case "clean":
            return "clean"
        case "dirty":
            switch report.stageEffect.pressureLevelIdentifier {
            case "light":
                return "dirty-light"
            case "moderate":
                return "dirty-moderate"
            case "heavy":
                return "dirty-heavy"
            default:
                return nil
            }
        case "conflicted":
            return "conflicted"
        case "commit":
            return "commit"
        case "success":
            return "success"
        case "recovery":
            return "recovery"
        case "failure":
            return "failure"
        default:
            return nil
        }
    }

    private static func nativeFeedbackSourceFamily(_ report: CinematicDiagnosticsReport) -> String? {
        let source = report.nativeFeedback.sourceIdentifier
        if source.hasPrefix("native:") {
            return "native"
        }
        if source.hasPrefix("run-cue:") {
            return "run-cue"
        }
        return nil
    }

    private static func nativeFeedbackAnchorRouteIdentifiers(
        _ report: CinematicDiagnosticsReport
    ) -> [String] {
        [
            nativeFeedbackAnchorRouteIdentifier(report.narrativeCue.questPlaque.anchorIdentifier),
            nativeFeedbackAnchorRouteIdentifier(report.narrativeCue.arenaInscription.anchorIdentifier),
            nativeFeedbackAnchorRouteIdentifier(report.narrativeCue.activityBanner.anchorIdentifier)
        ].compactMap { $0 }
    }

    private static func nativeFeedbackAnchorRouteIdentifier(_ anchorIdentifier: String) -> String? {
        switch anchorIdentifier {
        case "left-seal-pylon", "arena-rear":
            return "seal"
        case "right-warning-pylon":
            return "warning"
        case "fracture-gate":
            return "fracture"
        default:
            return nil
        }
    }

    private static func nativeFeedbackTreatmentPairIdentifier(
        _ report: CinematicDiagnosticsReport
    ) -> String? {
        let descriptor = report.narrativeCue.questPlaque
        guard descriptor.plaqueTreatmentAccentIdentifier != "none",
              descriptor.plaqueTreatmentRouteIdentifier != "none"
        else {
            return nil
        }

        return "\(descriptor.plaqueTreatmentAccentIdentifier)/\(descriptor.plaqueTreatmentRouteIdentifier)"
    }

    private static func nativeFeedbackTreatmentMatchesExpectedPair(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        guard let expectation = nativeFeedbackTreatmentExpectations.first(where: {
            $0.sourceIdentifier == report.nativeFeedback.sourceIdentifier
        }) else {
            return false
        }

        return narrativeCueDescriptors(report).allSatisfy {
            $0.plaqueTreatmentAccentIdentifier == expectation.accentIdentifier
                && $0.plaqueTreatmentRouteIdentifier == expectation.routeIdentifier
        }
    }

    private static func nativeFeedbackTreatmentSurfacesMatch(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        let descriptors = narrativeCueDescriptors(report)
        let treatmentIdentifiers = Set(descriptors.map(\.plaqueTreatmentIdentifier))
        let accentIdentifiers = Set(descriptors.map(\.plaqueTreatmentAccentIdentifier))
        let routeIdentifiers = Set(descriptors.map(\.plaqueTreatmentRouteIdentifier))

        return descriptors.count == 3
            && treatmentIdentifiers.count == 1
            && accentIdentifiers.count == 1
            && routeIdentifiers.count == 1
            && !treatmentIdentifiers.contains("none")
            && !accentIdentifiers.contains("none")
            && !routeIdentifiers.contains("none")
            && descriptors.allSatisfy {
                !$0.plaqueTreatmentIdentifier.isEmpty
                    && $0.identifier.contains($0.plaqueTreatmentIdentifier)
            }
    }

    private static func nativeFeedbackTreatmentParametersAreMeaningful(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        narrativeCueDescriptors(report).allSatisfy { descriptor in
            guard let parameters = NativeFeedbackTreatmentParameters(descriptor.plaqueTreatmentIdentifier) else {
                return false
            }

            return parameters.routeIdentifier == descriptor.plaqueTreatmentRouteIdentifier
                && parameters.hasMeaningfulValues(for: descriptor.plaqueTreatmentAccentIdentifier)
        }
    }

    private static func nativeFeedbackTreatmentPrimitivesMatchExpected(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        guard let expectation = nativeFeedbackTreatmentExpectations.first(where: {
            $0.sourceIdentifier == report.nativeFeedback.sourceIdentifier
        }) else {
            return false
        }

        let descriptors = narrativeCueDescriptors(report)
        let expectedPrimitiveCount = expectation.primitiveIdentifiers.count
        let expectedRecipeIdentifier = expectation.primitiveSetIdentifier

        return descriptors.count == 3
            && descriptors.allSatisfy { descriptor in
                descriptor.plaqueTreatmentRenderRecipeIdentifier == expectedRecipeIdentifier
                    && descriptor.plaqueTreatmentRenderPrimitiveIdentifiers == expectation.primitiveIdentifiers
                    && descriptor.plaqueTreatmentRenderPrimitiveCount == expectedPrimitiveCount
                    && descriptor.plaqueTreatmentIdentifier.contains("primitives:\(expectedRecipeIdentifier)")
                    && descriptor.plaqueTreatmentIdentifier.contains("primitive-count:\(expectedPrimitiveCount)")
            }
    }

    private static func nativeFeedbackActiveRoutesAreConsistent(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        report.nativeFeedback.lifecycleStateIdentifier == "active"
            && report.nativeFeedback.lifecycleActiveCueIdentifier == report.nativeFeedback.cueIdentifier
            && report.nativeFeedback.cueIdentifier == report.narrativeCue.nativeFeedbackCueIdentifier
            && report.nativeFeedback.cueIdentifier == report.overlayDisplay.nativeFeedbackCueIdentifier
            && report.nativeFeedback.sourceIdentifier == report.narrativeCue.nativeFeedbackSourceIdentifier
            && report.nativeFeedback.styleIdentifier == report.narrativeCue.nativeFeedbackStyleIdentifier
            && report.nativeFeedback.milestoneIdentifier == report.narrativeCue.nativeFeedbackMilestoneIdentifier
            && report.nativeFeedback.affectedNarrativeDescriptorIdentifiers
                == report.narrativeCue.nativeFeedbackAffectedDescriptorIdentifiers
            && report.nativeFeedback.lifecycleIdentifier == report.overlayDisplay.nativeFeedbackLifecycleIdentifier
            && report.narrativeCue.nativeFeedbackLifecycleIdentifier != "none"
    }

    private static func nativeFeedbackExpiredLifecycleIsArchived(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        report.nativeFeedback.cueIdentifier == "none"
            && report.nativeFeedback.lifecycleStateIdentifier == "expired"
            && report.nativeFeedback.lifecycleActiveCueIdentifier == "none"
            && report.nativeFeedback.lifecycleRecentArchiveCount > 0
            && report.narrativeCue.nativeFeedbackCueIdentifier == "none"
            && report.overlayDisplay.nativeFeedbackCueIdentifier == "none"
            && report.nativeFeedback.lifecycleIdentifier == report.overlayDisplay.nativeFeedbackLifecycleIdentifier
            && !report.overlayDisplay.showsNativeFeedbackBanner
            && report.overlayDisplay.nativeFeedbackBannerPolicyIdentifier == "none"
    }

    private static func gradients(
        for mode: String,
        in reports: [CinematicDiagnosticsReport]
    ) -> NumericRange {
        valueRange(
            reports
                .filter { $0.overlayDisplay.modeIdentifier == mode }
                .map { Float($0.overlayDisplay.gradientStrength) }
        )
    }

    private static func valueRange(_ values: [Float]) -> NumericRange {
        NumericRange(minValue: values.min() ?? 0, maxValue: values.max() ?? 0)
    }

    private static func range(_ range: NumericRange) -> String {
        "\(fixed(range.minValue))...\(fixed(range.maxValue))"
    }

    private static func chromeStyleName(_ identifier: String) -> String {
        identifier.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
    }

    private static func joined<S: Sequence>(_ values: S) -> String where S.Element == String {
        let sortedValues = values.sorted()
        return sortedValues.isEmpty ? "none" : sortedValues.joined(separator: ",")
    }

    private static func slashJoined<S: Sequence>(_ values: S) -> String where S.Element == String {
        let sortedValues = values.sorted()
        return sortedValues.isEmpty ? "none" : sortedValues.joined(separator: "/")
    }

    private static func string(_ text: String, maxCharacters: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxCharacters
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func check(
        id: String,
        label: String,
        isPassing: Bool,
        warningIdentifier: String,
        detail: String
    ) -> Check {
        Check(
            id: bounded(id, limit: warningIdentifierMaxCharacters),
            label: bounded(label, limit: labelMaxCharacters),
            status: isPassing ? .pass : .warning,
            warningIdentifier: isPassing
                ? nil
                : bounded(warningIdentifier, limit: warningIdentifierMaxCharacters),
            detail: bounded(detail, limit: detailMaxCharacters)
        )
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct CinematicDiagnosticsSummary: Equatable {
    static let maxRows = 41
    static let labelMaxCharacters = 32
    static let detailMaxCharacters = 512
    static let headerDetailMaxCharacters = 128
    static let visualSmokeCountMaxCharacters = 24
    static let attentionSummaryMaxTargets = 4
    static let attentionSummaryMaxVisibleWarnings = 3
    static let attentionSummaryDetailMaxCharacters = 96

    var rows: [Row]
    var sections: [Section]
    var visualSmoke: VisualSmokeSection
    var plaqueTreatmentLegend: PlaqueTreatmentLegend
    var attentionSummary: AttentionSummary
    var exportText: String

    struct Row: Identifiable, Equatable {
        var id: String
        var label: String
        var detail: String
    }

    enum AttentionState: String, Equatable {
        case normal
        case warning
    }

    struct PresentationMetadata: Equatable {
        var headerDetail: String
        var defaultExpanded: Bool
        var attentionState: AttentionState
        var warningIdentifiers: [String]

        var needsAttention: Bool {
            attentionState == .warning || !warningIdentifiers.isEmpty
        }
    }

    struct Section: Identifiable, Equatable {
        var id: String
        var label: String
        var rows: [Row]
        var presentation: PresentationMetadata

        var rowCountLabel: String {
            rows.count == 1 ? "1 row" : "\(rows.count) rows"
        }
    }

    struct VisualSmokeSection: Identifiable, Equatable {
        var id: String
        var label: String
        var status: CinematicVisualSmokeReport.Status
        var statusLabel: String
        var warningCount: Int
        var warningCountLabel: String
        var warningBadgeLabel: String
        var help: String
        var warningIdentifiers: [String]
        var checks: [CinematicVisualSmokeReport.Check]
        var presentation: PresentationMetadata

        var checkCountLabel: String {
            checks.count == 1 ? "1 check" : "\(checks.count) checks"
        }
    }

    struct PlaqueTreatmentLegend: Identifiable, Equatable {
        var id: String
        var label: String
        var status: CinematicVisualSmokeReport.Status
        var statusLabel: String
        var detail: String
        var warningIdentifier: String?
        var rows: [Row]
        var presentation: PresentationMetadata

        var rowCountLabel: String {
            rows.count == 1 ? "1 recipe" : "\(rows.count) recipes"
        }
    }

    struct AttentionSummary: Equatable {
        var targets: [AttentionTarget]

        var isEmpty: Bool {
            targets.isEmpty
        }
    }

    struct AttentionTarget: Identifiable, Equatable {
        var targetGroupID: String
        var label: String
        var detail: String
        var warningCount: Int
        var visibleWarningIdentifiers: [String]

        var id: String {
            targetGroupID
        }
    }

    private struct PlaqueTreatmentLegendEntry {
        var accentIdentifier: String
        var routeIdentifier: String
        var renderRecipeIdentifier: String
        var primitiveIdentifiers: [String]
        var primitiveCount: Int
    }

    private struct SectionDefinition {
        var id: String
        var label: String
        var rowIDs: Set<String>
        var rowIDPrefixes: [String] = []

        func contains(_ row: Row) -> Bool {
            rowIDs.contains(row.id) || rowIDPrefixes.contains { row.id.hasPrefix($0) }
        }
    }

    private static let sectionDefinitions: [SectionDefinition] = [
        SectionDefinition(
            id: "repository-context",
            label: "Repository/context",
            rowIDs: [
                "repository",
                "immediate",
                "commit-constellation",
                "idle-story-cycle",
                "timeline-focus",
                "run-recap",
                "run-recap-share",
                "run-recap-focus",
                "run-recap-end-card"
            ]
        ),
        SectionDefinition(
            id: "motifs",
            label: "Motifs",
            rowIDs: ["language-motif", "activity-motif"]
        ),
        SectionDefinition(
            id: "stage-motion-effects",
            label: "Stage motion/effects",
            rowIDs: [
                "recovery-cue",
                "stage-beat",
                "stage-effect",
                "effect-rings",
                "effect-pulses",
                "effect-history",
                "stage-atmosphere",
                "atmosphere-tints",
                "phase-polish"
            ]
        ),
        SectionDefinition(
            id: "narrative-overlay",
            label: "Narrative/overlay",
            rowIDs: [
                "narrative-cues",
                "narrative-layout",
                "overlay-display",
                "native-feedback-history",
                "world-quest",
                "world-arena",
                "world-activity"
            ]
        ),
        SectionDefinition(
            id: "assets-textures",
            label: "Assets/textures",
            rowIDs: ["set-dressing", "textures"]
        ),
        SectionDefinition(
            id: "tuning",
            label: "Tuning",
            rowIDs: [
                "effect-tuning",
                "activity-tuning",
                "camera-tuning",
                "camera-follow"
            ]
        ),
        SectionDefinition(
            id: "camera-shots",
            label: "Camera shots",
            rowIDs: [],
            rowIDPrefixes: ["camera-shot-"]
        )
    ]

    private static let collapsedByDefaultSectionIDs: Set<String> = [
        "stage-motion-effects",
        "camera-shots"
    ]

    init(report: CinematicDiagnosticsReport, visualSmoke: CinematicVisualSmokeReport = .representative()) {
        let rows = Self.makeRows(report: report)
        self.rows = Array(rows.prefix(Self.maxRows))
        sections = Self.makeSections(rows: self.rows)
        self.visualSmoke = Self.makeVisualSmokeSection(visualSmoke)
        plaqueTreatmentLegend = Self.makePlaqueTreatmentLegend(visualSmoke: self.visualSmoke)
        attentionSummary = Self.makeAttentionSummary(
            visualSmoke: self.visualSmoke,
            plaqueTreatmentLegend: plaqueTreatmentLegend
        )
        exportText = Self.makeExportText(
            report: report,
            attentionSummary: attentionSummary,
            sections: sections,
            visualSmoke: self.visualSmoke,
            plaqueTreatmentLegend: plaqueTreatmentLegend
        )
    }

    private static func makeRows(report: CinematicDiagnosticsReport) -> [Row] {
        var rows: [Row] = [
            row(
                id: "repository",
                label: "Repository",
                detail: [
                    report.repoName,
                    report.phase,
                    completedLabel(report.completedCount)
                ].joined(separator: " | ")
            ),
            row(id: "immediate", label: "Immediate", detail: report.immediateTitle),
            row(
                id: "commit-constellation",
                label: "Commit constellation",
                detail: commitConstellationDetail(report.commitConstellation)
            ),
            row(
                id: "idle-story-cycle",
                label: "Idle story cycle",
                detail: idleStoryCycleDetail(report.idleStoryCycle)
            ),
            row(
                id: "timeline-focus",
                label: "Timeline focus",
                detail: timelineFocusDetail(report.timelineFocus)
            ),
            row(
                id: "run-recap",
                label: "Run recap",
                detail: runRecapDetail(report.runRecap)
            ),
            row(
                id: "run-recap-share",
                label: "Run recap share",
                detail: runRecapShareDetail(report.runRecapShare)
            ),
            row(
                id: "run-recap-focus",
                label: "Run recap focus",
                detail: runRecapSceneFocusDetail(report.runRecapSceneFocus)
            ),
            row(
                id: "run-recap-end-card",
                label: "Run recap end card",
                detail: runRecapEndCardDetail(report.runRecapEndCard)
            ),
            row(
                id: "language-motif",
                label: "Language motif",
                detail: [
                    report.languageMotif.language.displayName,
                    report.languageMotif.sigilIdentifier,
                    report.languageMotif.styleIdentifier,
                    "ambient \(report.languageMotif.ambientSpellIdentifier)",
                    "blend \(fixed(report.languageMotif.phaseBlend))"
                ].joined(separator: " | ")
            ),
            row(
                id: "activity-motif",
                label: "Activity motif",
                detail: [
                    report.activityMotif.eventKindIdentifier,
                    report.activityMotif.sigilIdentifier,
                    report.activityMotif.styleIdentifier,
                    optionalIdentifier("tint", report.activityMotif.tintSourceIdentifier),
                    optionalIdentifier("transition", report.activityMotif.transitionSpellIdentifier),
                    optionalIdentifier("ambient", report.activityMotif.ambientOverrideIdentifier),
                    report.activityMotif.shouldShakeOnTransition ? "shake" : nil
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "recovery-cue",
                label: "Recovery cue",
                detail: [
                    report.recoveryCue.kindIdentifier,
                    "treatment \(report.recoveryCue.treatmentIdentifier)",
                    "light \(report.recoveryCue.lightFamilyIdentifier)",
                    "symbol \(report.recoveryCue.symbolIdentifier ?? "none")",
                    "intensity \(fixed(report.recoveryCue.intensity))",
                    "fracture \(fixed(report.recoveryCue.fractureOpacity))",
                    "heal \(fixed(report.recoveryCue.healingOpacity))",
                    report.recoveryCue.shouldShakeCamera ? "shake" : nil
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "stage-beat",
                label: "Stage beat",
                detail: [
                    report.stageBeat.kindIdentifier,
                    "shot \(report.stageBeat.cameraShotIdentifier)",
                    "light \(report.stageBeat.lightFamilyIdentifier)",
                    "effect \(report.stageBeat.arenaEffectIdentifier)",
                    "intensity \(fixed(report.stageBeat.phaseLightIntensity))",
                    optionalIdentifier("activity", report.stageBeat.activityEventKindIdentifier),
                    optionalIdentifier("accent", report.stageBeat.activityAccentIdentifier),
                    report.stageBeat.shouldShakeCamera ? "shake" : nil,
                    report.stageBeat.shouldRunVictorySurge ? "victory" : nil,
                    report.stageBeat.shouldRunHistoryChains ? "history" : nil
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "stage-effect",
                label: "Stage effect",
                detail: [
                    "phase \(report.stageEffect.phaseSourceIdentifier)/\(report.stageEffect.phaseArenaEffectIdentifier)",
                    report.stageEffect.activitySourceIdentifier.flatMap { source in
                        report.stageEffect.activityArenaEffectIdentifier.map { "activity \(source)/\($0)" }
                    },
                    report.stageEffect.recoverySourceIdentifier.flatMap { source in
                        report.stageEffect.recoveryArenaEffectIdentifier.map { "recovery \(source)/\($0)" }
                    },
                    "rings \(report.stageEffect.arenaRingCount)",
                    "pulses \(report.stageEffect.phaseLightPulseCount)",
                    "sparks \(report.stageEffect.sparkBurstCount)",
                    "history \(report.stageEffect.historyTrailCount)",
                    optionalIdentifier("victory", report.stageEffect.victoryCadenceIdentifier),
                    report.stageEffect.cameraShakeIdentifiers.isEmpty
                        ? nil
                        : "camera \(report.stageEffect.cameraShakeIdentifiers.joined(separator: ","))"
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "effect-tuning",
                label: "Effect tuning",
                detail: [
                    "pressure \(report.stageEffect.pressureLevelIdentifier) \(fixed(report.stageEffect.pressureFraction))",
                    "energy \(fixed(report.stageEffect.energy))",
                    "influence \(report.stageEffect.influenceStyleIdentifier) \(fixed(report.stageEffect.influenceIntensity))/\(fixed(report.stageEffect.influenceFraction))",
                    "light \(fixed(report.stageEffect.activityLightBoost))/\(fixed(report.stageEffect.activityLightBoostFraction))",
                    "rune \(fixed(report.stageEffect.runePulseScale))",
                    "cadence \(fixed(report.stageEffect.activityPulseDuration))s",
                    "ring \(fixed(report.stageEffect.ringScaleMultiplier))/\(fixed(report.stageEffect.ringDurationScale))/\(fixed(report.stageEffect.ringOpacityMultiplier))",
                    "alpha \(fixed(report.stageEffect.colorAlphaMultiplier))",
                    "pulse \(fixed(report.stageEffect.pulseIntensityMultiplier))/\(fixed(report.stageEffect.pulseDurationMultiplier))",
                    "spark \(fixed(report.stageEffect.sparkBirthRateMultiplier))",
                    "trails \(report.stageEffect.historyTrailTargetCount)",
                    "shake \(fixed(report.stageEffect.cameraShakeMultiplier))/\(fixed(report.stageEffect.cameraShakeDurationMultiplier))",
                    "victory \(fixed(report.stageEffect.victoryCadenceMultiplier))"
                ].joined(separator: " | ")
            ),
            row(
                id: "effect-rings",
                label: "Effect rings",
                detail: report.stageEffect.arenaRingIdentifiers.isEmpty
                    ? "none"
                    : report.stageEffect.arenaRingIdentifiers.joined(separator: " | ")
            ),
            row(
                id: "effect-pulses",
                label: "Effect pulses",
                detail: effectPulseDetail(report.stageEffect)
            ),
            row(
                id: "effect-history",
                label: "Effect history",
                detail: report.stageEffect.historyTrailIdentifiers.isEmpty
                    ? "none"
                    : report.stageEffect.historyTrailIdentifiers.joined(separator: " | ")
            ),
            row(
                id: "stage-atmosphere",
                label: "Atmosphere",
                detail: [
                    "pressure \(report.stageAtmosphere.pressureLevelIdentifier) \(fixed(report.stageAtmosphere.pressureFraction))",
                    "energy \(fixed(report.stageAtmosphere.energy))",
                    "influence \(report.stageAtmosphere.influenceStyleIdentifier) \(fixed(report.stageAtmosphere.influenceIntensity))/\(fixed(report.stageAtmosphere.influenceFraction))",
                    "halo \(report.stageAtmosphere.pressureHaloIdentifier)",
                    "pulse \(report.stageAtmosphere.atmosphericPulseIdentifier)",
                    "light \(report.stageAtmosphere.pressureLightingIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "atmosphere-tints",
                label: "Atmosphere tints",
                detail: [
                    "backdrop \(report.stageAtmosphere.backdropTintIdentifier)",
                    "floor \(report.stageAtmosphere.floorTintIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "phase-polish",
                label: "Phase polish",
                detail: [
                    report.stagePhasePolish.postureIdentifier,
                    "recovery \(report.stagePhasePolish.recoveryCueKindIdentifier)",
                    "pose \(fixed(report.stagePhasePolish.poseIntensity))",
                    "orb \(report.stagePhasePolish.staffOrbLightFamilyIdentifier) \(fixed(report.stagePhasePolish.staffOrbScale))/\(fixed(report.stagePhasePolish.staffOrbEmission))",
                    "sigil \(fixed(report.stagePhasePolish.sigilSealEmphasis))/\(fixed(report.stagePhasePolish.sigilOrbitRadius))",
                    "victory \(fixed(report.stagePhasePolish.sigilVictoryEmphasis))",
                    "portal \(fixed(report.stagePhasePolish.portalAperture))",
                    "backdrop \(fixed(report.stagePhasePolish.backdropAperture))",
                    "fracture \(fixed(report.stagePhasePolish.fractureOpacity))",
                    "heal \(fixed(report.stagePhasePolish.healingOpacity))",
                    "cadence \(report.stagePhasePolish.cadenceIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "narrative-cues",
                label: "Narrative cues",
                detail: narrativeCueDetail(report.narrativeCue)
            ),
            row(
                id: "narrative-layout",
                label: "Narrative layout",
                detail: narrativeLayoutDetail(report.narrativeCue)
            ),
            row(
                id: "overlay-display",
                label: "Overlay display",
                detail: overlayDisplayDetail(report.overlayDisplay)
            ),
            row(
                id: "native-feedback-history",
                label: "Native feedback history",
                detail: nativeFeedbackHistoryDetail(report.nativeFeedback)
            ),
            row(id: "world-quest", label: "World quest", detail: report.worldText.questLabel),
            row(id: "world-arena", label: "World arena", detail: report.worldText.arenaCallout),
            row(id: "world-activity", label: "World activity", detail: report.worldText.activityCallout),
            row(
                id: "set-dressing",
                label: "Set dressing",
                detail: [
                    report.setDressing.languageArchitectureIdentifier,
                    report.setDressing.activityMarkerIdentifier,
                    "layout \(report.setDressing.layoutGeometryCoverageIdentifier)",
                    report.setDressing.layoutGeometryIsBounded ? "layout bounded" : "layout out-of-bounds",
                    "runes \(report.setDressing.runeIntensityIdentifier)",
                    "rune material \(report.setDressing.runeMaterialIdentifier)",
                    "material \(report.setDressing.runeMaterialTreatmentIdentifier)",
                    "cadence \(report.setDressing.animationCadenceIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "textures",
                label: "Textures",
                detail: [
                    report.setDressing.materialTextureVariantIdentifier,
                    report.setDressing.backdropTextureAssetIdentifier,
                    report.setDressing.arenaTextureAssetIdentifier,
                    "routes \(report.setDressing.textureRoleCoverageIdentifier)",
                    report.setDressing.backdropTextureName,
                    report.setDressing.arenaTextureName,
                    CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(
                        report.setDressing.backdropTextureName
                    ) ? "backdrop generated" : "backdrop fallback",
                    CinematicTextureAssetCatalog.isGeneratedArenaTextureName(
                        report.setDressing.arenaTextureName
                    ) ? "arena generated" : "arena fallback",
                    CinematicTextureAssetCatalog.isPackagedResourceAvailable(
                        report.setDressing.backdropTextureName,
                        role: .backdrop
                    ) ? "backdrop packaged" : "backdrop missing",
                    CinematicTextureAssetCatalog.isPackagedResourceAvailable(
                        report.setDressing.arenaTextureName,
                        role: .arena
                    ) ? "arena packaged" : "arena missing",
                    report.setDressing.usesFallbackTextureAsset ? "fallback" : "direct"
                ].joined(separator: " | ")
            ),
            row(
                id: "activity-tuning",
                label: "Activity tuning",
                detail: [
                    report.activityTuning.pressureLevelIdentifier,
                    "spawn \(fixed(report.activityTuning.ambientSpawnCadence))s",
                    "limit \(report.activityTuning.ambientEnemyLimit)",
                    "light \(fixed(report.activityTuning.activityLightBoost))",
                    "scale \(fixed(report.activityTuning.activityPressureScale))"
                ].joined(separator: " | ")
            ),
            row(
                id: "camera-tuning",
                label: "Camera tuning",
                detail: [
                    report.cameraTuning.identifier,
                    "orbit \(fixed(report.cameraTuning.orbitScale))",
                    "pullback \(fixed(report.cameraTuning.pullbackScale))",
                    "height \(fixed(report.cameraTuning.heightOffset))"
                ].joined(separator: " | ")
            ),
            row(
                id: "camera-follow",
                label: "Camera follow",
                detail: [
                    "fov \(fixed(report.cameraTuning.followFieldOfView))",
                    "response \(fixed(report.cameraTuning.followResponsiveness))",
                    "drift \(fixed(report.cameraTuning.driftScale))",
                    "shake \(fixed(report.cameraTuning.shakeScale))"
                ].joined(separator: " | ")
            )
        ]

        rows.append(contentsOf: report.cameraSnapshots.map { snapshot in
            row(
                id: "camera-shot-\(snapshot.shotIdentifier)",
                label: "Shot \(snapshot.shotIdentifier)",
                detail: [
                    snapshot.identifier,
                    "pos \(position(snapshot.position))",
                    "fov \(fixed(snapshot.fieldOfView))",
                    "transition \(fixed(snapshot.transitionDuration))s"
                ].joined(separator: " | ")
            )
        })

        return rows
    }

    private static func makeSections(rows: [Row]) -> [Section] {
        var matchedRowIDs = Set<String>()
        var sections = sectionDefinitions.compactMap { definition -> Section? in
            let sectionRows = rows.filter(definition.contains)
            guard !sectionRows.isEmpty else { return nil }

            matchedRowIDs.formUnion(sectionRows.map(\.id))
            return Section(
                id: definition.id,
                label: bounded(definition.label, limit: labelMaxCharacters),
                rows: sectionRows,
                presentation: sectionPresentation(
                    id: definition.id,
                    rowCount: sectionRows.count
                )
            )
        }

        let unmatchedRows = rows.filter { !matchedRowIDs.contains($0.id) }
        if !unmatchedRows.isEmpty {
            sections.append(
                Section(
                    id: "other",
                    label: bounded("Other", limit: labelMaxCharacters),
                    rows: unmatchedRows,
                    presentation: sectionPresentation(
                        id: "other",
                        rowCount: unmatchedRows.count
                    )
                )
            )
        }

        return sections
    }

    private static func sectionPresentation(id: String, rowCount: Int) -> PresentationMetadata {
        PresentationMetadata(
            headerDetail: bounded(
                rowCountCopy(rowCount, singular: "row", plural: "rows"),
                limit: headerDetailMaxCharacters
            ),
            defaultExpanded: !collapsedByDefaultSectionIDs.contains(id),
            attentionState: .normal,
            warningIdentifiers: []
        )
    }

    var defaultExpandedGroupStates: [String: Bool] {
        var states = Dictionary(uniqueKeysWithValues: sections.map { section in
            (section.id, section.presentation.defaultExpanded)
        })
        states[visualSmoke.id] = visualSmoke.presentation.defaultExpanded
        states[plaqueTreatmentLegend.id] = plaqueTreatmentLegend.presentation.defaultExpanded
        return states
    }

    private static func makeAttentionSummary(
        visualSmoke: VisualSmokeSection,
        plaqueTreatmentLegend: PlaqueTreatmentLegend
    ) -> AttentionSummary {
        let targets = [
            attentionTarget(
                targetGroupID: visualSmoke.id,
                label: visualSmoke.label,
                detail: [
                    visualSmoke.checkCountLabel,
                    visualSmoke.statusLabel
                ].joined(separator: " | "),
                presentation: visualSmoke.presentation
            ),
            attentionTarget(
                targetGroupID: plaqueTreatmentLegend.id,
                label: plaqueTreatmentLegend.label,
                detail: [
                    plaqueTreatmentLegend.rowCountLabel,
                    plaqueTreatmentLegend.statusLabel
                ].joined(separator: " | "),
                presentation: plaqueTreatmentLegend.presentation
            )
        ]
        .compactMap { $0 }
        .prefix(attentionSummaryMaxTargets)

        return AttentionSummary(targets: Array(targets))
    }

    private static func attentionTarget(
        targetGroupID: String,
        label: String,
        detail: String,
        presentation: PresentationMetadata
    ) -> AttentionTarget? {
        guard presentation.needsAttention else {
            return nil
        }

        let warningCount = presentation.warningIdentifiers.isEmpty ? 1 : presentation.warningIdentifiers.count
        return AttentionTarget(
            targetGroupID: targetGroupID,
            label: bounded(label, limit: labelMaxCharacters),
            detail: bounded(detail, limit: attentionSummaryDetailMaxCharacters),
            warningCount: warningCount,
            visibleWarningIdentifiers: Array(
                presentation.warningIdentifiers.prefix(attentionSummaryMaxVisibleWarnings)
            )
        )
    }

    private static func makeVisualSmokeSection(
        _ report: CinematicVisualSmokeReport
    ) -> VisualSmokeSection {
        let warningCount = report.warningIdentifiers.count
        let checkCountLabel = report.checks.count == 1 ? "1 check" : "\(report.checks.count) checks"
        let warningIdentifiers = report.warningIdentifiers
        let presentation = PresentationMetadata(
            headerDetail: bounded(
                [
                    checkCountLabel,
                    warningHeaderDetail(warningIdentifiers)
                ].joined(separator: " | "),
                limit: headerDetailMaxCharacters
            ),
            defaultExpanded: !warningIdentifiers.isEmpty,
            attentionState: warningIdentifiers.isEmpty ? .normal : .warning,
            warningIdentifiers: warningIdentifiers
        )

        return VisualSmokeSection(
            id: "visual-smoke",
            label: bounded("Visual smoke", limit: labelMaxCharacters),
            status: report.status,
            statusLabel: bounded(visualSmokeStatusLabel(for: report.status), limit: labelMaxCharacters),
            warningCount: warningCount,
            warningCountLabel: bounded(
                warningCountCopy(for: warningCount),
                limit: visualSmokeCountMaxCharacters
            ),
            warningBadgeLabel: bounded(
                warningBadgeCopy(for: warningCount),
                limit: visualSmokeCountMaxCharacters
            ),
            help: bounded(
                visualSmokeHelp(status: report.status, warningIdentifiers: report.warningIdentifiers),
                limit: detailMaxCharacters
            ),
            warningIdentifiers: warningIdentifiers,
            checks: report.checks,
            presentation: presentation
        )
    }

    private static func makePlaqueTreatmentLegend(
        visualSmoke: VisualSmokeSection
    ) -> PlaqueTreatmentLegend {
        let treatmentCheck = visualSmoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        let status = treatmentCheck?.status ?? .warning
        let statusLabel = visualSmokeStatusLabel(for: status)
        let warningIdentifier = treatmentCheck?.warningIdentifier
        let detail = warningIdentifier.map { "smoke \(status.rawValue) \($0)" }
            ?? "smoke \(status.rawValue)"
        let entries = plaqueTreatmentLegendEntries(
            reports: CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        )
        let rows = entries.map { entry in
            row(
                id: "plaque-treatment-\(entry.accentIdentifier)",
                label: entry.accentIdentifier,
                detail: plaqueTreatmentLegendDetail(entry)
            )
        }
        let warningIdentifiers = warningIdentifier.map { [$0] } ?? []
        let rowCountLabel = rows.count == 1 ? "1 recipe" : "\(rows.count) recipes"
        let presentation = PresentationMetadata(
            headerDetail: bounded(
                [
                    rowCountLabel,
                    statusLabel,
                    warningHeaderDetail(warningIdentifiers)
                ].joined(separator: " | "),
                limit: headerDetailMaxCharacters
            ),
            defaultExpanded: status == .warning || !warningIdentifiers.isEmpty,
            attentionState: status == .warning || !warningIdentifiers.isEmpty ? .warning : .normal,
            warningIdentifiers: warningIdentifiers
        )

        return PlaqueTreatmentLegend(
            id: "plaque-treatment-legend",
            label: bounded("Plaque treatments", limit: labelMaxCharacters),
            status: status,
            statusLabel: bounded(statusLabel, limit: labelMaxCharacters),
            detail: bounded(detail, limit: detailMaxCharacters),
            warningIdentifier: warningIdentifier,
            rows: rows,
            presentation: presentation
        )
    }

    private static func makeExportText(
        report: CinematicDiagnosticsReport,
        attentionSummary: AttentionSummary,
        sections: [Section],
        visualSmoke: VisualSmokeSection,
        plaqueTreatmentLegend: PlaqueTreatmentLegend
    ) -> String {
        var lines = [
            "Cinematic Diagnostics",
            "Report: \(bounded(report.identifier, limit: detailMaxCharacters))"
        ]

        if !attentionSummary.targets.isEmpty {
            lines.append(
                "Warning summary (\(rowCountCopy(attentionSummary.targets.count, singular: "target", plural: "targets")))"
            )
            lines.append(contentsOf: attentionSummary.targets.map { target in
                let visibleWarnings = target.visibleWarningIdentifiers.isEmpty
                    ? "no visible warning identifiers"
                    : target.visibleWarningIdentifiers.joined(separator: ", ")
                return "\(target.label) -> \(target.targetGroupID) (\(warningCountCopy(for: target.warningCount))): \(target.detail) | \(visibleWarnings)"
            })
        }

        for section in sections {
            lines.append("\(section.label) (\(section.rowCountLabel))")
            lines.append(contentsOf: section.rows.map { "\($0.label): \($0.detail)" })
        }

        lines.append(
            "Visual smoke (\(visualSmoke.status.rawValue), \(visualSmoke.checks.count) checks)"
        )
        lines.append(contentsOf: visualSmoke.checks.map { check in
            let warning = check.warningIdentifier.map { " | warning \($0)" } ?? ""
            return "\(check.label): \(check.status.rawValue) | \(check.detail)\(warning)"
        })

        lines.append(
            "\(plaqueTreatmentLegend.label) (\(plaqueTreatmentLegend.status.rawValue), \(plaqueTreatmentLegend.rowCountLabel)): \(plaqueTreatmentLegend.detail)"
        )
        lines.append(contentsOf: plaqueTreatmentLegend.rows.map { "\($0.label): \($0.detail)" })

        return lines.joined(separator: "\n")
    }

    private static func warningCountCopy(for count: Int) -> String {
        switch count {
        case 0:
            return "No warnings"
        case 1:
            return "1 warning"
        default:
            return "\(count) warnings"
        }
    }

    private static func warningBadgeCopy(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private static func rowCountCopy(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private static func warningHeaderDetail(_ warningIdentifiers: [String]) -> String {
        guard !warningIdentifiers.isEmpty else {
            return "No warnings"
        }

        let visibleWarnings = warningIdentifiers.prefix(2).joined(separator: ", ")
        if warningIdentifiers.count <= 2 {
            return "\(warningCountCopy(for: warningIdentifiers.count)) | \(visibleWarnings)"
        }

        return "\(warningCountCopy(for: warningIdentifiers.count)) | \(visibleWarnings) +\(warningIdentifiers.count - 2)"
    }

    private static func visualSmokeHelp(
        status: CinematicVisualSmokeReport.Status,
        warningIdentifiers: [String]
    ) -> String {
        switch status {
        case .pass:
            return "Visual smoke checks passing"
        case .warning:
            let warnings = warningIdentifiers.isEmpty
                ? "warnings unavailable"
                : warningIdentifiers.joined(separator: ", ")
            return "Visual smoke warning: \(warningCountCopy(for: warningIdentifiers.count)) (\(warnings))"
        }
    }

    private static func visualSmokeStatusLabel(for status: CinematicVisualSmokeReport.Status) -> String {
        switch status {
        case .pass:
            return "Passing"
        case .warning:
            return "Warning"
        }
    }

    private static func row(id: String, label: String, detail: String) -> Row {
        Row(
            id: id,
            label: bounded(label, limit: labelMaxCharacters),
            detail: bounded(detail, limit: detailMaxCharacters)
        )
    }

    private static func optionalIdentifier(_ label: String, _ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return "\(label) \(identifier)"
    }

    private static func plaqueTreatmentLegendEntries(
        reports: [CinematicDiagnosticsReport]
    ) -> [PlaqueTreatmentLegendEntry] {
        let entries = reports
            .filter {
                $0.nativeFeedback.cueIdentifier != "none"
                    && $0.nativeFeedback.lifecycleStateIdentifier == "active"
            }
            .flatMap(narrativeCueDescriptors)
            .filter { $0.plaqueTreatmentAccentIdentifier != "none" }
            .reduce(into: [String: PlaqueTreatmentLegendEntry]()) { entries, descriptor in
                let accent = descriptor.plaqueTreatmentAccentIdentifier
                guard entries[accent] == nil else { return }
                entries[accent] = PlaqueTreatmentLegendEntry(
                    accentIdentifier: accent,
                    routeIdentifier: descriptor.plaqueTreatmentRouteIdentifier,
                    renderRecipeIdentifier: descriptor.plaqueTreatmentRenderRecipeIdentifier,
                    primitiveIdentifiers: descriptor.plaqueTreatmentRenderPrimitiveIdentifiers,
                    primitiveCount: descriptor.plaqueTreatmentRenderPrimitiveCount
                )
            }

        return entries.values.sorted { lhs, rhs in
            plaqueTreatmentLegendOrder(lhs.accentIdentifier)
                < plaqueTreatmentLegendOrder(rhs.accentIdentifier)
        }
    }

    private static func plaqueTreatmentLegendDetail(_ entry: PlaqueTreatmentLegendEntry) -> String {
        let primitiveIdentifiers = entry.primitiveIdentifiers.isEmpty
            ? "none"
            : entry.primitiveIdentifiers.joined(separator: ",")
        return [
            "accent \(entry.accentIdentifier)",
            "route \(entry.routeIdentifier)",
            "recipe \(entry.renderRecipeIdentifier)",
            "primitives \(entry.primitiveCount) \(primitiveIdentifiers)"
        ].joined(separator: " | ")
    }

    private static func plaqueTreatmentLegendOrder(_ accentIdentifier: String) -> Int {
        switch accentIdentifier {
        case "verify-seal":
            return 0
        case "warning-rails":
            return 1
        case "failure-fracture":
            return 2
        case "retry-braces":
            return 3
        default:
            return 100
        }
    }

    private static func narrativeCueDescriptors(
        _ report: CinematicDiagnosticsReport
    ) -> [CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot] {
        [
            report.narrativeCue.questPlaque,
            report.narrativeCue.arenaInscription,
            report.narrativeCue.activityBanner
        ]
    }

    private static func effectPulseDetail(_ snapshot: CinematicDiagnosticsReport.StageEffectSnapshot) -> String {
        let values = [
            snapshot.phaseLightPulseIdentifiers.isEmpty
                ? nil
                : "light \(snapshot.phaseLightPulseIdentifiers.joined(separator: ","))",
            snapshot.sparkBurstIdentifiers.isEmpty
                ? nil
                : "sparks \(snapshot.sparkBurstIdentifiers.joined(separator: ","))",
            snapshot.cameraShakeIdentifiers.isEmpty
                ? nil
                : "camera \(snapshot.cameraShakeIdentifiers.joined(separator: ","))",
            optionalIdentifier("victory", snapshot.victoryCadenceIdentifier)
        ].compactMap { $0 }

        return values.isEmpty ? "none" : values.joined(separator: " | ")
    }

    private static func narrativeCueDetail(_ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot) -> String {
        var details = [String]()
        if let nativeDetail = nativeFeedbackNarrativeDetail(snapshot) {
            details.append(nativeDetail)
        }
        details.append(contentsOf: [
            narrativeCueDescriptorDetail("quest", snapshot.questPlaque),
            narrativeCueDescriptorDetail("arena", snapshot.arenaInscription),
            narrativeCueDescriptorDetail("activity", snapshot.activityBanner)
        ])
        return details.joined(separator: " | ")
    }

    private static func narrativeLayoutDetail(_ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot) -> String {
        [
            narrativeCueLayoutDescriptorDetail("quest", snapshot.questPlaque.layout),
            narrativeCueLayoutDescriptorDetail("arena", snapshot.arenaInscription.layout),
            narrativeCueLayoutDescriptorDetail("activity", snapshot.activityBanner.layout)
        ].joined(separator: " | ")
    }

    private static func overlayDisplayDetail(_ snapshot: CinematicDiagnosticsReport.OverlayDisplaySnapshot) -> String {
        let details = [
            "mode \(snapshot.modeIdentifier)",
            "reason \(snapshot.reasonIdentifier)",
            "pills \(snapshot.visiblePillIdentifiers.isEmpty ? "none" : snapshot.visiblePillIdentifiers.joined(separator: ","))",
            "hud \(snapshot.hudProminenceIdentifier)",
            snapshot.nativeFeedbackCueIdentifier == "none" ? nil : "native \(snapshot.nativeFeedbackCueIdentifier)",
            snapshot.nativeFeedbackLifecycleIdentifier == "none"
                ? nil
                : "native-lifecycle \(snapshot.nativeFeedbackLifecycleIdentifier)",
            "native-banner \(snapshot.nativeFeedbackBannerPolicyIdentifier)",
            "chrome \(snapshot.chromeStyleIdentifier)",
            "gradient \(fixed(snapshot.gradientStrength))",
            "width \(fixed(snapshot.worldTextMaxWidth))/\(fixed(snapshot.hudMaxWidth))",
            "lines \(snapshot.pillLineLimit)/\(snapshot.hudTitleLineLimit)/\(snapshot.hudDetailLineLimit)/\(snapshot.hudProfileLineLimit)/\(snapshot.hudStatusLineLimit)",
            "opacity \(fixed(snapshot.overlayOpacity))"
        ].compactMap { $0 }
        return details.joined(separator: " | ")
    }

    private static func nativeFeedbackHistoryDetail(
        _ snapshot: CinematicDiagnosticsReport.NativeFeedbackSnapshot
    ) -> String {
        let entries = [snapshot.lifecycleActiveHistoryEntry].compactMap { $0 }
            + snapshot.lifecycleArchiveHistoryEntries
        guard !entries.isEmpty else { return "none" }
        return entries
            .map(nativeFeedbackHistoryEntryDetail)
            .joined(separator: " | ")
    }

    private static func nativeFeedbackHistoryEntryDetail(
        _ entry: CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot
    ) -> String {
        [
            "#\(entry.sequence)",
            stateAndReasonDetail(entry),
            "milestone \(entry.milestoneIdentifier)",
            entry.sourceIdentifier.map { "source \($0)" },
            entry.styleIdentifier.map { "style \($0)" },
            "duration \(fixed(entry.displayDuration))s",
            "lifecycle \(entry.lifecycleIdentifier)"
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func stateAndReasonDetail(
        _ entry: CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot
    ) -> String {
        if let reason = entry.reasonIdentifier {
            return "\(entry.stateIdentifier)/\(reason)"
        }
        return entry.stateIdentifier
    }

    private static func nativeFeedbackNarrativeDetail(
        _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot
    ) -> String? {
        guard snapshot.nativeFeedbackCueIdentifier != "none" else { return nil }
        let affected = snapshot.nativeFeedbackAffectedDescriptorIdentifiers.isEmpty
            ? "none"
            : snapshot.nativeFeedbackAffectedDescriptorIdentifiers.joined(separator: ",")
        let treatments = nativeFeedbackPlaqueTreatmentAccents(snapshot)
        let primitiveSets = nativeFeedbackPlaqueTreatmentPrimitiveSets(snapshot)
        return [
            "native",
            "source \(snapshot.nativeFeedbackSourceIdentifier)",
            "style \(snapshot.nativeFeedbackStyleIdentifier)",
            "milestone \(snapshot.nativeFeedbackMilestoneIdentifier)",
            "lifecycle \(snapshot.nativeFeedbackLifecycleIdentifier)",
            "treatments \(treatments.isEmpty ? "none" : treatments.joined(separator: ","))",
            "primitives \(primitiveSets.isEmpty ? "none" : primitiveSets.joined(separator: ","))",
            "affects \(affected)"
        ].joined(separator: " ")
    }

    private static func nativeFeedbackPlaqueTreatmentAccents(
        _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot
    ) -> [String] {
        Array(
            Set([
                snapshot.questPlaque.plaqueTreatmentAccentIdentifier,
                snapshot.arenaInscription.plaqueTreatmentAccentIdentifier,
                snapshot.activityBanner.plaqueTreatmentAccentIdentifier
            ].filter { $0 != "none" })
        ).sorted()
    }

    private static func nativeFeedbackPlaqueTreatmentPrimitiveSets(
        _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot
    ) -> [String] {
        Array(
            Set([
                snapshot.questPlaque.plaqueTreatmentRenderRecipeIdentifier,
                snapshot.arenaInscription.plaqueTreatmentRenderRecipeIdentifier,
                snapshot.activityBanner.plaqueTreatmentRenderRecipeIdentifier
            ].filter { $0 != "none" })
        ).sorted()
    }

    private static func commitConstellationDetail(
        _ snapshot: CinematicDiagnosticsReport.CommitConstellationSnapshot
    ) -> String {
        [
            "count \(snapshot.count)",
            optionalIdentifier("newest", snapshot.newestSubject),
            snapshot.nodeIdentifiers.isEmpty ? "nodes none" : "nodes \(snapshot.nodeIdentifiers.joined(separator: ","))",
            snapshot.branchIdentifiers.isEmpty ? "branches none" : "branches \(snapshot.branchIdentifiers.joined(separator: ","))",
            "focus \(snapshot.focusIdentifier)",
            "shot \(snapshot.focusShotIdentifier)",
            "look \(position(snapshot.focusLookTarget))",
            snapshot.usesFallbackFocus ? "fallback focus" : nil
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func idleStoryCycleDetail(
        _ snapshot: CinematicDiagnosticsReport.IdleStoryCycleSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "empty \(snapshot.suppressionReason)"
        }

        return [
            "active",
            "phase \(snapshot.phaseIdentifier)",
            "choreo \(bounded(snapshot.choreographyIdentifier, limit: 80))",
            "source \(bounded(snapshot.sourceDescriptorIdentifier, limit: 80))",
            "target \(snapshot.targetKindIdentifier)",
            "cadence \(fixed(snapshot.cadence))",
            "dwell \(fixed(snapshot.dwellDuration))",
            "transition \(fixed(snapshot.transitionDurationScale))",
            "camera \(bounded(snapshot.cameraTreatmentIdentifier, limit: 96))",
            "pressure \(snapshot.cameraPressureIdentifier)",
            "anchor \(snapshot.anchorTreatmentIdentifier)",
            "bias \(fixed(snapshot.targetBias))",
            "damping \(fixed(snapshot.comfortDamping))",
            "shake \(snapshot.shakeHintIdentifier)",
            "pulse \(snapshot.pulseHintIdentifier)",
            "slot \(snapshot.cycleSlot)",
            "index \(snapshot.phaseIndex)",
            "suppression \(snapshot.suppressionReason)",
            "copy \(bounded(snapshot.phaseCopy, limit: 96))",
            "id \(bounded(snapshot.descriptorIdentifier, limit: 140))"
        ].joined(separator: " | ")
    }

    private static func timelineFocusDetail(
        _ snapshot: CinematicDiagnosticsReport.TimelineFocusSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "none"
        }

        return [
            snapshot.selectedBeatID.map { "beat \($0)" },
            "kind \(snapshot.kindIdentifier)",
            snapshot.label.map { "label \($0)" },
            "shot \(snapshot.cameraShotIdentifier)",
            snapshot.lookTarget.map { "look \(position($0))" },
            "light \(snapshot.lightFamilyIdentifier)",
            "effect \(snapshot.arenaEffectIdentifier)",
            "phase \(fixed(snapshot.phaseLightIntensity))",
            optionalIdentifier("node", snapshot.commitNodeIdentifier),
            optionalIdentifier("recovery", snapshot.recoveryTreatmentIdentifier),
            snapshot.usesFallbackTarget ? "fallback target" : nil
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityIdentifier)"
        return [
            availability,
            snapshot.sessionNumber.map { "session \($0)" },
            "title \(snapshot.title)",
            "detail \(snapshot.detail)",
            "status \(snapshot.status)",
            "terminal \(snapshot.statusIdentifier)",
            "style \(snapshot.styleIdentifier)/\(snapshot.colorIdentifier)",
            "flavor \(snapshot.flavorStateIdentifier)",
            "title-source \(snapshot.titleSourceIdentifier)",
            "completed \(snapshot.completedCount)",
            "commits \(snapshot.commitHighlightCount)",
            "events \(snapshot.eventChipCount)",
            "image \(snapshot.systemImage)",
            snapshot.flavorIdentifier.map { "flavor-id \(bounded($0, limit: 96))" },
            snapshot.flavorSourceIdentifier.map { "flavor-source \(bounded($0, limit: 96))" },
            snapshot.sourceIdentifier.map { "source \(bounded($0, limit: 96))" },
            optionalIdentifier("newest", snapshot.newestCommitHighlight),
            snapshot.eventChipIdentifiers.isEmpty
                ? "chips none"
                : "chips \(snapshot.eventChipIdentifiers.joined(separator: ","))",
            "id \(bounded(snapshot.identifier, limit: 180))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            "share \(bounded(snapshot.identifier, limit: 64))",
            "recap \(bounded(snapshot.recapIdentifier, limit: 40))",
            "focus \(bounded(snapshot.recapFocusIdentifier ?? "none", limit: 40))",
            "end-card \(bounded(snapshot.endCardIdentifier ?? "none", limit: 40))",
            "copy \(snapshot.textLength) chars",
            "events \(snapshot.eventSummaryCount)",
            snapshot.visualDescriptorTokens.isEmpty
                ? "visual none"
                : "visual \(bounded(snapshot.visualDescriptorTokens.joined(separator: ","), limit: 260))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapSceneFocusDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "empty"
        }

        return [
            "active",
            "descriptor \(snapshot.descriptorIdentifier)",
            snapshot.terminalBeatID.map { "beat \($0)" },
            "terminal \(snapshot.terminalStatusIdentifier)",
            "style \(snapshot.terminalStyleIdentifier)",
            "shot \(snapshot.cameraShotIdentifier)",
            snapshot.lookTarget.map { "look \(position($0))" },
            optionalIdentifier("node", snapshot.commitNodeIdentifier),
            snapshot.usesFallbackTarget
                ? "fallback \(snapshot.fallbackTargetIdentifier ?? "target")"
                : nil,
            "light \(snapshot.lightFamilyIdentifier)",
            "effect \(snapshot.arenaEffectIdentifier)",
            "phase \(fixed(snapshot.phaseLightIntensity))",
            "id \(bounded(snapshot.identifier, limit: 180))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapEndCardDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapEndCardSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "empty"
        }

        return [
            "active",
            "descriptor \(bounded(snapshot.descriptorIdentifier, limit: 56))",
            "recap \(bounded(snapshot.recapIdentifier, limit: 56))",
            "title-source \(snapshot.titleSourceIdentifier)",
            "flavor \(snapshot.flavorStateIdentifier)",
            "style \(snapshot.styleIdentifier)/\(snapshot.colorIdentifier)",
            "anchor \(snapshot.anchorIdentifier)",
            "treatment \(snapshot.plaqueTreatmentAccentIdentifier)/\(snapshot.plaqueTreatmentRouteIdentifier)",
            "lengths \(snapshot.titleLength)/\(snapshot.detailLength)/\(snapshot.statusLength)",
            "title \(bounded(snapshot.title, limit: 64))",
            "detail \(bounded(snapshot.detail, limit: 72))",
            "status \(bounded(snapshot.status, limit: 72))",
            "scale \(fixed(snapshot.scale))",
            "cadence \(fixed(snapshot.cadence))",
            "light \(snapshot.lightFamilyIdentifier)/\(snapshot.tintFamilyIdentifier)",
            "glyph \(snapshot.glyphIdentifier)",
            "plate \(fixed(snapshot.plateWidth))x\(fixed(snapshot.plateHeight))",
            "recipe \(snapshot.plaqueTreatmentRenderRecipeIdentifier)"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func narrativeCueLayoutDescriptorDetail(
        _ label: String,
        _ layout: CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot
    ) -> String {
        [
            label,
            layout.facingModeIdentifier,
            "pos \(position(layout.anchorPosition))",
            "box \(fixed(layout.plateWidth))x\(fixed(layout.plateHeight))",
            "text \(fixed(layout.primaryTextWidth))/\(fixed(layout.secondaryTextWidth))",
            "font \(fixed(layout.primaryFontSize))/\(fixed(layout.secondaryFontSize))",
            "back \(fixed(layout.backingOpacity))",
            "glyph \(layout.glyphSideIdentifier)@\(position(layout.glyphOffset))",
            "z \(fixed(layout.plateZOffset))/\(fixed(layout.primaryTextOffset.z))/\(fixed(layout.glyphOffset.z))"
        ].joined(separator: " ")
    }

    private static func narrativeCueDescriptorDetail(
        _ label: String,
        _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot
    ) -> String {
        [
            label,
            descriptor.anchorIdentifier,
            descriptor.visibilityIdentifier,
            descriptor.lightFamilyIdentifier,
            "tint \(descriptor.tintFamilyIdentifier)",
            narrativeCueTreatmentDetail(descriptor),
            "scale \(fixed(descriptor.scale))",
            "opacity \(fixed(descriptor.opacity))",
            "cadence \(fixed(descriptor.cadence))s",
            "\"\(descriptor.text)\""
        ].joined(separator: " ")
    }

    private static func narrativeCueTreatmentDetail(
        _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot
    ) -> String {
        guard descriptor.plaqueTreatmentAccentIdentifier != "none" else {
            return "treatment none"
        }
        let primitives = descriptor.plaqueTreatmentRenderPrimitiveIdentifiers.isEmpty
            ? "none"
            : descriptor.plaqueTreatmentRenderPrimitiveIdentifiers.joined(separator: ",")
        return [
            "treatment \(descriptor.plaqueTreatmentAccentIdentifier)/\(descriptor.plaqueTreatmentRouteIdentifier)",
            "primitives \(primitives)",
            "count \(descriptor.plaqueTreatmentRenderPrimitiveCount)"
        ].joined(separator: " ")
    }

    private static func completedLabel(_ count: Int) -> String {
        count == 1 ? "1 completed" : "\(count) completed"
    }

    private static func position(_ value: SIMD3<Float>) -> String {
        [
            fixed(value.x),
            fixed(value.y),
            fixed(value.z)
        ].joined(separator: ",")
    }

    private static func fixed(_ value: Float) -> String {
        fixed(Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum CinematicDiagnostics {
    struct ActivityCase: Equatable {
        var identifier: String
        var phase: String
        var immediateTitle: String
        var completedCount: Int
        var profile: RepositoryActivityProfile
        var isRunning: Bool = true
        var isAutoPlaying: Bool = false
        var isPaused: Bool = false
        var hasRepository: Bool = true
    }

    @MainActor
    static func currentReport(
        for project: CompassProject,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan? = nil,
        timelineFocusPlan: CinematicTimelineSceneFocusPlan = .none,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none
    ) -> CinematicDiagnosticsReport {
        let commitConstellationPlan = project.cinematicCommitConstellationPlan
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: project.state,
            sessions: project.sessions
        )
        let recoveryCuePlan = CinematicRecoveryCuePlanner.plan(
            recentRunCues: reliabilityFeedback.recentRunCues,
            influenceSettings: project.cinematicInfluenceSettings
        )
        let runRecapPlan = CinematicRunRecapPlanner.plan(
            state: project.state,
            sessions: project.sessions,
            isRunning: project.isRunning,
            isAutoPlaying: project.isAutoPlaying,
            recentRunCues: reliabilityFeedback.recentRunCues,
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle,
            flavor: project.cinematicRunRecapFlavor
        )
        return report(
            repoName: project.displayName,
            phase: (project.isPaused ? LoopPhase.paused : project.phase).rawValue,
            immediateTitle: project.immediateTitle,
            completedCount: project.state.completed.count,
            latestEvent: project.liveLog.last.map(CinematicBriefingEvent.init(line:)),
            latestCommitSubject: commitConstellationPlan.newestSubject,
            languageProfile: project.languageProfile,
            activityProfile: project.activityProfile,
            influenceSettings: project.cinematicInfluenceSettings,
            isRunning: project.isRunning,
            isAutoPlaying: project.isAutoPlaying,
            isPaused: project.isPaused,
            hasRepository: project.hasRepository,
            commitConstellationPlan: commitConstellationPlan,
            recoveryCuePlan: recoveryCuePlan,
            idleStoryCyclePlan: idleStoryCyclePlan,
            isLiveFollowActive: CinematicIdleStoryCyclePlanner.hasLiveFollowTarget(lines: project.liveLog),
            hasExplicitUserFocus: timelineFocusPlan.descriptor != nil
                || runRecapSceneFocusPlan.descriptor != nil
                || runRecapEndCardPlan.descriptor != nil,
            timelineFocusPlan: timelineFocusPlan,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan,
            nativeFeedbackCue: project.cinematicNativeFeedbackCue,
            nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle
        )
    }

    static func report(
        repoName: String,
        phase: String,
        immediateTitle: String,
        completedCount: Int,
        latestEvent: CinematicBriefingEvent?,
        latestCommitSubject: String? = nil,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        isRunning: Bool = true,
        isAutoPlaying: Bool = false,
        isPaused: Bool = false,
        hasRepository: Bool = true,
        commitConstellationPlan: CinematicCommitConstellationPlan = .empty,
        recoveryCuePlan: CinematicRecoveryCuePlan = .none,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan? = nil,
        idleStoryCycleSession: CinematicIdleStoryCyclePlan.SessionInput = CinematicIdleStoryCyclePlan.SessionInput(),
        isLiveFollowActive: Bool = false,
        hasExplicitUserFocus: Bool = false,
        timelineFocusPlan: CinematicTimelineSceneFocusPlan = .none,
        runRecapPlan: CinematicRunRecapPlan = .empty(reason: "no-finished-session"),
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil,
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle = CinematicNativeFeedbackCueLifecycle()
    ) -> CinematicDiagnosticsReport {
        let languageMotif = CinematicMotif.language(for: languageProfile)
        let activityMotif = CinematicMotif.activity(for: activityProfile)
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent,
                latestCommitSubject: latestCommitSubject
            )
        )
        let worldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent,
                latestCommitSubject: latestCommitSubject,
                languageProfile: languageProfile,
                activityProfile: activityProfile
            )
        )
        let influenceIdentifier = settingsIdentifier(influenceSettings)
        let languageSnapshot = languageSnapshot(for: languageMotif)
        let activitySnapshot = activitySnapshot(for: activityMotif)
        let recoveryCueSnapshot = recoveryCueSnapshot(for: recoveryCuePlan)
        let loopPhase = loopPhase(from: phase)
        let effectivePhase: LoopPhase = isPaused ? .paused : loopPhase
        let stageBeat = CinematicStageBeatPlanner.plan(
            phase: effectivePhase,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
        let setDressingPlan = CinematicSetDressingPlanner.plan(
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
        let stageEffectPlan = CinematicStageEffectPlanner.plan(
            beat: stageBeat,
            setDressingPlan: setDressingPlan,
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
        )
        let stageAtmospherePlan = CinematicStageAtmospherePlanner.plan(
            beat: stageBeat,
            setDressingPlan: setDressingPlan,
            stageEffectTuning: stageEffectPlan.tuningMetadata,
            influenceSettings: influenceSettings
        )
        let stagePhasePolishPlan = CinematicStagePhasePolishPlanner.plan(
            beat: stageBeat,
            stageEffectTuning: stageEffectPlan.tuningMetadata,
            atmospherePlan: stageAtmospherePlan,
            activityMotif: activityMotif,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
        )
        let narrativeCuePlan = CinematicSceneNarrativeCuePlanner.plan(
            worldText: worldText,
            briefing: briefing,
            stageBeat: stageBeat,
            stagePhasePolishPlan: stagePhasePolishPlan,
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nativeFeedbackCue
        )
        let resolvedIdleStoryCyclePlan = idleStoryCyclePlan ?? CinematicIdleStoryCyclePlanner.plan(
            session: idleStoryCycleSession,
            isLiveFollowActive: isLiveFollowActive,
            hasExplicitUserFocus: hasExplicitUserFocus,
            influenceSettings: influenceSettings,
            commitConstellationPlan: commitConstellationPlan,
            timelineSceneFocusPlan: timelineFocusPlan,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackPlaqueDescriptor: nativeFeedbackCue == nil ? nil : narrativeCuePlan.questPlaque,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan
        )
        let stageBeatSnapshot = stageBeatSnapshot(for: stageBeat)
        let stageEffectSnapshot = stageEffectSnapshot(for: stageEffectPlan)
        let stageAtmosphereSnapshot = stageAtmosphereSnapshot(for: stageAtmospherePlan)
        let stagePhasePolishSnapshot = stagePhasePolishSnapshot(for: stagePhasePolishPlan)
        let narrativeCueSnapshot = narrativeCueSnapshot(for: narrativeCuePlan)
        let nativeFeedbackSnapshot = nativeFeedbackSnapshot(
            for: nativeFeedbackCue,
            lifecycle: nativeFeedbackLifecycle,
            narrativeCuePlan: narrativeCuePlan
        )
        let narrativeCueReadability = CinematicNarrativeCueReadabilitySignals(plan: narrativeCuePlan)
        let nativeFeedbackLifecycleIdentifier = nativeFeedbackLifecycle.hasState
            ? nativeFeedbackLifecycle.identifier
            : nil
        let overlayDisplayPlan = CinematicOverlayDisplayPlanner.plan(
            phase: loopPhase,
            isRunning: isRunning,
            isAutoPlaying: isAutoPlaying,
            isPaused: isPaused,
            hasRepository: hasRepository,
            worldText: worldText,
            briefing: briefing,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            narrativeCueReadability: narrativeCueReadability,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackLifecycleIdentifier: nativeFeedbackLifecycleIdentifier
        )
        let overlayDisplaySnapshot = overlayDisplaySnapshot(for: overlayDisplayPlan)
        let worldTextSnapshot = worldTextSnapshot(for: worldText)
        let briefingSnapshot = briefingSnapshot(for: briefing)
        let cameraTuningSnapshot = cameraTuningSnapshot(settings: influenceSettings)
        let activityTuningSnapshot = activityTuningSnapshot(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
        let setDressingSnapshot = setDressingSnapshot(for: setDressingPlan)
        let commitConstellationSnapshot = commitConstellationSnapshot(for: commitConstellationPlan)
        let idleStoryCycleSnapshot = idleStoryCycleSnapshot(for: resolvedIdleStoryCyclePlan)
        let timelineFocusSnapshot = timelineFocusSnapshot(for: timelineFocusPlan)
        let runRecapSnapshot = runRecapSnapshot(for: runRecapPlan)
        let runRecapSceneFocusSnapshot = runRecapSceneFocusSnapshot(for: runRecapSceneFocusPlan)
        let runRecapEndCardSnapshot = runRecapEndCardSnapshot(for: runRecapEndCardPlan)
        let runRecapSharePlan = CinematicRunRecapSharePlanner.plan(
            recapPlan: runRecapPlan,
            recapFocusDescriptor: runRecapSceneFocusPlan.descriptor,
            endCardDescriptor: runRecapEndCardPlan.descriptor
        )
        let runRecapShareSnapshot = runRecapShareSnapshot(for: runRecapSharePlan)
        let cameraSnapshots = CinematicCameraShot.allCases.map {
            cameraSnapshot(for: $0, settings: influenceSettings)
        }

        return CinematicDiagnosticsReport(
            identifier: [
                "repo:\(repoName)",
                "phase:\(phase)",
                "language:\(languageSnapshot.identifier)",
                "activity:\(activitySnapshot.identifier)",
                "recovery:\(recoveryCueSnapshot.identifier)",
                "stage:\(stageBeatSnapshot.identifier)",
                "stage-effect:\(stageEffectSnapshot.identifier)",
                "stage-atmosphere:\(stageAtmosphereSnapshot.identifier)",
                "phase-polish:\(stagePhasePolishSnapshot.identifier)",
                "narrative-cues:\(narrativeCueSnapshot.identifier)",
                "native-feedback:\(nativeFeedbackSnapshot.identifier)",
                "overlay:\(overlayDisplaySnapshot.identifier)",
                "influence:\(influenceIdentifier)",
                "set-dressing:\(setDressingSnapshot.identifier)",
                "commit-constellation:\(commitConstellationSnapshot.identifier)",
                "idle-story-cycle:\(idleStoryCycleSnapshot.identifier)",
                "timeline-focus:\(timelineFocusSnapshot.identifier)",
                "run-recap:\(runRecapSnapshot.identifier)",
                "run-recap-share:\(runRecapShareSnapshot.identifier)",
                "run-recap-focus:\(runRecapSceneFocusSnapshot.identifier)",
                "run-recap-end-card:\(runRecapEndCardSnapshot.identifier)"
            ].joined(separator: "|"),
            repoName: repoName,
            phase: phase,
            immediateTitle: immediateTitle,
            completedCount: completedCount,
            influenceIdentifier: influenceIdentifier,
            languageMotif: languageSnapshot,
            activityMotif: activitySnapshot,
            nativeFeedback: nativeFeedbackSnapshot,
            recoveryCue: recoveryCueSnapshot,
            stageBeat: stageBeatSnapshot,
            stageEffect: stageEffectSnapshot,
            stageAtmosphere: stageAtmosphereSnapshot,
            stagePhasePolish: stagePhasePolishSnapshot,
            narrativeCue: narrativeCueSnapshot,
            overlayDisplay: overlayDisplaySnapshot,
            worldText: worldTextSnapshot,
            briefing: briefingSnapshot,
            cameraTuning: cameraTuningSnapshot,
            activityTuning: activityTuningSnapshot,
            setDressing: setDressingSnapshot,
            commitConstellation: commitConstellationSnapshot,
            idleStoryCycle: idleStoryCycleSnapshot,
            timelineFocus: timelineFocusSnapshot,
            runRecap: runRecapSnapshot,
            runRecapShare: runRecapShareSnapshot,
            runRecapSceneFocus: runRecapSceneFocusSnapshot,
            runRecapEndCard: runRecapEndCardSnapshot,
            cameraSnapshots: cameraSnapshots
        )
    }

    static func representativeSmokeMatrix(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        RepositoryLanguage.allCases.flatMap { language in
            representativeActivityCases().flatMap { activityCase in
                CinematicRecoveryCuePlanner.representativePlans(influenceSettings: influenceSettings).map { recoveryCuePlan in
                    let commitConstellationPlan = representativeCommitConstellationPlan(for: activityCase)
                    let timelineFocusPlan = CinematicTimelineSceneFocusPlanner.representativePlan(
                        activityCaseIdentifier: activityCase.identifier,
                        recoveryCuePlan: recoveryCuePlan,
                        commitConstellationPlan: commitConstellationPlan
                    )
                    let runRecapContext = representativeRunRecapFocusContext(
                        for: activityCase,
                        commitConstellationPlan: commitConstellationPlan
                    )
                    return report(
                        repoName: "Diagnostics \(language.displayName)",
                        phase: activityCase.phase,
                        immediateTitle: activityCase.immediateTitle,
                        completedCount: activityCase.completedCount,
                        latestEvent: nil,
                        languageProfile: representativeLanguageProfile(for: language),
                        activityProfile: activityCase.profile,
                        influenceSettings: influenceSettings,
                        isRunning: activityCase.isRunning,
                        isAutoPlaying: activityCase.isAutoPlaying,
                        isPaused: activityCase.isPaused,
                        hasRepository: activityCase.hasRepository,
                        commitConstellationPlan: commitConstellationPlan,
                        recoveryCuePlan: recoveryCuePlan,
                        timelineFocusPlan: timelineFocusPlan,
                        runRecapPlan: runRecapContext.runRecapPlan,
                        runRecapSceneFocusPlan: runRecapContext.runRecapSceneFocusPlan,
                        runRecapEndCardPlan: runRecapContext.runRecapEndCardPlan
                    )
                }
            }
        }
    }

    static func representativeNativeFeedbackSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        let start = Date(timeIntervalSinceReferenceDate: 7_000)
        let activeReports = [
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Verify",
                phase: .verifying,
                immediateTitle: "Verify native feedback seal route",
                completedCount: 3,
                language: .swift,
                activityProfile: activityProfile(recentCommitCount: 1),
                influenceSettings: influenceSettings,
                milestone: .verifyStarted,
                recentRunCues: [:],
                now: start
            ),
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Warning",
                phase: .developing,
                immediateTitle: "Retry develop with warning cue",
                completedCount: 2,
                language: .typeScriptJavaScript,
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
                influenceSettings: influenceSettings,
                milestone: .developRetrying,
                recentRunCues: [
                    11: representativeRunCue(
                        kind: .dirtyWorktree,
                        severity: .warning,
                        label: "Clean Worktree",
                        detail: "2 pending changes",
                        systemImage: "pencil.and.outline"
                    )
                ],
                now: start.addingTimeInterval(1)
            ),
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Retry",
                phase: .developing,
                immediateTitle: "Retry develop after verify failure",
                completedCount: 2,
                language: .python,
                activityProfile: activityProfile(
                    recentFailedCount: 1,
                    lastTerminalStatus: .failed,
                    failureStreak: 1
                ),
                influenceSettings: influenceSettings,
                milestone: .developRetrying,
                recentRunCues: [
                    7: representativeRunCue(
                        kind: .failedVerify,
                        severity: .failure,
                        label: "Retry Develop",
                        detail: "swift test exited 65",
                        systemImage: "checkmark.seal.fill"
                    )
                ],
                now: start.addingTimeInterval(2)
            ),
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Post Checks",
                phase: .failed,
                immediateTitle: "Post-check failure native cue",
                completedCount: 4,
                language: .go,
                activityProfile: activityProfile(recentCommitCount: 2),
                influenceSettings: influenceSettings,
                milestone: .postChecksFailed,
                recentRunCues: [:],
                now: start.addingTimeInterval(3)
            )
        ].compactMap { $0 }

        guard let expiredReport = representativeExpiredNativeFeedbackSmokeReport(
            influenceSettings: influenceSettings,
            now: start.addingTimeInterval(4)
        ) else {
            return activeReports
        }

        return activeReports + [expiredReport]
    }

    static func representativeIdleStoryCycleSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        let commitConstellationPlan = CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
        let timelineFocusPlan = CinematicTimelineSceneFocusPlanner.representativePlan(
            activityCaseIdentifier: "commit",
            recoveryCuePlan: .none,
            commitConstellationPlan: commitConstellationPlan
        )
        let activityCase = ActivityCase(
            identifier: "commit",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Cycle idle cinematic story",
            completedCount: 5,
            profile: activityProfile(recentCommitCount: 2, lastTerminalStatus: .succeeded, successStreak: 2),
            isRunning: false
        )
        let recapContext = representativeRunRecapFocusContext(
            for: activityCase,
            commitConstellationPlan: commitConstellationPlan
        )
        let nativeFeedbackCue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: .verifyStarted,
            content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Idle Story Cycle"),
            phase: .verifying,
            feedbackMode: .notifications,
            recentRunCues: [:]
        )
        var elapsedTime: TimeInterval = 0
        var phaseReports: [CinematicDiagnosticsReport] = []
        for _ in CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases {
            let report = representativeIdleStoryCycleSmokeReport(
                influenceSettings: influenceSettings,
                activityCase: activityCase,
                commitConstellationPlan: commitConstellationPlan,
                timelineFocusPlan: timelineFocusPlan,
                nativeFeedbackCue: nativeFeedbackCue,
                recapContext: recapContext,
                session: CinematicIdleStoryCyclePlan.SessionInput(
                    elapsedTime: elapsedTime,
                    sessionOrdinal: 0
                ),
                isLiveFollowActive: false,
                hasExplicitUserFocus: false
            )
            phaseReports.append(report)
            elapsedTime += max(report.idleStoryCycle.cadence, 0.1) + 0.01
        }
        let suppressedReport = representativeIdleStoryCycleSmokeReport(
            influenceSettings: influenceSettings,
            activityCase: activityCase,
            commitConstellationPlan: commitConstellationPlan,
            timelineFocusPlan: timelineFocusPlan,
            nativeFeedbackCue: nativeFeedbackCue,
            recapContext: recapContext,
            session: CinematicIdleStoryCyclePlan.SessionInput(),
            isLiveFollowActive: true,
            hasExplicitUserFocus: false
        )

        return phaseReports + [suppressedReport]
    }

    static func representativeActivityCases() -> [ActivityCase] {
        [
            ActivityCase(
                identifier: "unavailable",
                phase: "Staging",
                immediateTitle: "No immediate plan",
                completedCount: 0,
                profile: .empty
            ),
            ActivityCase(
                identifier: "missing-repository",
                phase: "Staging",
                immediateTitle: "Reconnect repository for cinematic diagnostics",
                completedCount: 0,
                profile: .empty,
                hasRepository: false
            ),
            ActivityCase(
                identifier: "clean",
                phase: "Developing",
                immediateTitle: "Add deterministic cinematic diagnostics",
                completedCount: 1,
                profile: activityProfile()
            ),
            ActivityCase(
                identifier: "dirty-light",
                phase: "Developing",
                immediateTitle: "Update renderer smoke copy",
                completedCount: 2,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 2))
            ),
            ActivityCase(
                identifier: "dirty-moderate",
                phase: "Developing",
                immediateTitle: "Refine camera pressure tuning",
                completedCount: 3,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 8))
            ),
            ActivityCase(
                identifier: "dirty-heavy",
                phase: "Verifying",
                immediateTitle: "Stabilize intense activity tuning",
                completedCount: 4,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 16))
            ),
            ActivityCase(
                identifier: "conflicted",
                phase: "Recovering",
                immediateTitle: "Resolve deterministic cinematic conflict",
                completedCount: 2,
                profile: activityProfile(worktreeChanges: worktreeChanges(conflicted: 1))
            ),
            ActivityCase(
                identifier: "commit",
                phase: "Committing",
                immediateTitle: "Record cinematic diagnostics commit",
                completedCount: 5,
                profile: activityProfile(recentCommitCount: 2)
            ),
            ActivityCase(
                identifier: "success",
                phase: "Verifying",
                immediateTitle: "Confirm cinematic diagnostics smoke path",
                completedCount: 6,
                profile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 3)
            ),
            ActivityCase(
                identifier: "recovery",
                phase: "Recovering",
                immediateTitle: "Recover cinematic diagnostics after failure",
                completedCount: 3,
                profile: activityProfile(
                    lastTerminalStatus: .succeeded,
                    successStreak: 1,
                    recoveredFromFailure: true
                )
            ),
            ActivityCase(
                identifier: "failure",
                phase: "Repairing",
                immediateTitle: "Fix cinematic diagnostics failure state",
                completedCount: 1,
                profile: activityProfile(
                    recentFailedCount: 1,
                    lastTerminalStatus: .failed,
                    failureStreak: 1
                )
            )
        ]
    }

    private static func representativeCommitConstellationPlan(
        for activityCase: ActivityCase
    ) -> CinematicCommitConstellationPlan {
        guard activityCase.identifier == "commit" else { return .empty }
        return CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
    }

    private struct RunRecapFocusContext {
        var runRecapPlan: CinematicRunRecapPlan
        var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan
        var runRecapEndCardPlan: CinematicRunRecapEndCardPlan
    }

    private static func representativeRunRecapFocusContext(
        for activityCase: ActivityCase,
        commitConstellationPlan: CinematicCommitConstellationPlan
    ) -> RunRecapFocusContext {
        guard let status = representativeRunRecapStatus(for: activityCase.identifier) else {
            return RunRecapFocusContext(
                runRecapPlan: .empty(reason: "no-finished-session"),
                runRecapSceneFocusPlan: .none,
                runRecapEndCardPlan: .none
            )
        }

        let sessionNumber = 70 + activityCase.completedCount
        let session = SessionRecord(
            session: sessionNumber,
            startedAt: Double(sessionNumber * 1_000),
            endedAt: Double(sessionNumber * 1_000 + 620),
            plan: activityCase.immediateTitle,
            verify: "swift test --filter CinematicVisualSmokeReportTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
        let flavorInput = CinematicRunRecapPlanner.flavorInput(
            state: PlanState(
                completed: ["Completed \(activityCase.immediateTitle.lowercased())"],
                immediate: nil,
                midTerm: "",
                longTerm: ""
            ),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let generatedFlavor = activityCase.identifier == "recovery"
            ? flavorInput.map {
                CinematicRunRecapFlavor(
                    sourceIdentifier: $0.sourceIdentifier,
                    title: "Generated Recovery Recap",
                    detail: "Recovered diagnostics are ready with a generated recap card.",
                    titleSource: .generated
                )
            }
            : nil
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: PlanState(
                completed: ["Completed \(activityCase.immediateTitle.lowercased())"],
                immediate: nil,
                midTerm: "",
                longTerm: ""
            ),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: generatedFlavor
        )
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitConstellationPlan,
            timelinePlan: timelinePlan
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )

        return RunRecapFocusContext(
            runRecapPlan: recapPlan,
            runRecapSceneFocusPlan: focusPlan,
            runRecapEndCardPlan: endCardPlan
        )
    }

    private static func representativeRunRecapStatus(
        for activityCaseIdentifier: String
    ) -> SessionStatus? {
        switch activityCaseIdentifier {
        case "commit", "success", "recovery":
            return .succeeded
        case "failure":
            return .failed
        case "dirty-heavy":
            return .cancelled
        default:
            return nil
        }
    }

    private static func representativeNativeFeedbackSmokeReport(
        repoName: String,
        phase: LoopPhase,
        immediateTitle: String,
        completedCount: Int,
        language: RepositoryLanguage,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        milestone: NativeFeedbackMilestone,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        now: Date
    ) -> CinematicDiagnosticsReport? {
        guard let cue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: milestone,
            content: NativeFeedbackContent(milestone: milestone, projectName: repoName),
            phase: phase,
            feedbackMode: .notifications,
            recentRunCues: recentRunCues
        ) else {
            return nil
        }

        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        let activeCue = lifecycle.record(cue, now: now)
        return report(
            repoName: repoName,
            phase: phase.rawValue,
            immediateTitle: immediateTitle,
            completedCount: completedCount,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: language),
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            nativeFeedbackCue: activeCue,
            nativeFeedbackLifecycle: lifecycle
        )
    }

    private static func representativeIdleStoryCycleSmokeReport(
        influenceSettings: CinematicInfluenceSettings,
        activityCase: ActivityCase,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelineFocusPlan: CinematicTimelineSceneFocusPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        recapContext: RunRecapFocusContext,
        session: CinematicIdleStoryCyclePlan.SessionInput,
        isLiveFollowActive: Bool,
        hasExplicitUserFocus: Bool
    ) -> CinematicDiagnosticsReport {
        report(
            repoName: "Idle Story Cycle",
            phase: activityCase.phase,
            immediateTitle: activityCase.immediateTitle,
            completedCount: activityCase.completedCount,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityCase.profile,
            influenceSettings: influenceSettings,
            isRunning: false,
            isAutoPlaying: false,
            isPaused: false,
            hasRepository: true,
            commitConstellationPlan: commitConstellationPlan,
            idleStoryCycleSession: session,
            isLiveFollowActive: isLiveFollowActive,
            hasExplicitUserFocus: hasExplicitUserFocus,
            timelineFocusPlan: timelineFocusPlan,
            runRecapPlan: recapContext.runRecapPlan,
            runRecapSceneFocusPlan: recapContext.runRecapSceneFocusPlan,
            runRecapEndCardPlan: recapContext.runRecapEndCardPlan,
            nativeFeedbackCue: nativeFeedbackCue
        )
    }

    private static func representativeExpiredNativeFeedbackSmokeReport(
        influenceSettings: CinematicInfluenceSettings,
        now: Date
    ) -> CinematicDiagnosticsReport? {
        guard let cue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: .verifyStarted,
            content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Native Feedback Expired"),
            phase: .verifying,
            feedbackMode: .notifications,
            recentRunCues: [:]
        ) else {
            return nil
        }

        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        _ = lifecycle.record(cue, now: now)
        _ = lifecycle.expire(
            now: now.addingTimeInterval(CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
        )

        return report(
            repoName: "Native Feedback Expired",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Archive expired native feedback cue",
            completedCount: 3,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nil,
            nativeFeedbackLifecycle: lifecycle
        )
    }

    private static func representativeRunCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity,
        label: String,
        detail: String,
        systemImage: String
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-native-feedback-smoke",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: label,
                detail: detail,
                actionLabel: label,
                metadata: nil,
                systemImage: systemImage
            )
        )
    }

    private static func languageSnapshot(
        for motif: CinematicLanguageMotif
    ) -> CinematicDiagnosticsReport.LanguageMotifSnapshot {
        let ambientSpellIdentifier = motif.ambientSpell.diagnosticsIdentifier
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            ambientSpellIdentifier,
            fixed(Double(motif.phaseBlend))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.LanguageMotifSnapshot(
            identifier: identifier,
            language: motif.language,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            ambientSpellIdentifier: ambientSpellIdentifier,
            phaseBlend: Double(motif.phaseBlend)
        )
    }

    private static func activitySnapshot(
        for motif: CinematicActivityMotif
    ) -> CinematicDiagnosticsReport.ActivityMotifSnapshot {
        let tintSourceIdentifier = motif.tintSource?.diagnosticsIdentifier
        let transitionSpellIdentifier = motif.transitionSpell?.diagnosticsIdentifier
        let ambientOverrideIdentifier = motif.ambientOverride?.diagnosticsIdentifier
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            motif.eventKind.rawValue,
            tintSourceIdentifier ?? "none",
            transitionSpellIdentifier ?? "none",
            ambientOverrideIdentifier ?? "none"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.ActivityMotifSnapshot(
            identifier: identifier,
            eventKindIdentifier: motif.eventKind.rawValue,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            tintSourceIdentifier: tintSourceIdentifier,
            transitionSpellIdentifier: transitionSpellIdentifier,
            ambientOverrideIdentifier: ambientOverrideIdentifier,
            usesCommitAmbient: motif.usesCommitAmbient,
            usesSuccessAmbient: motif.usesSuccessAmbient,
            shouldShakeOnTransition: motif.shouldShakeOnTransition
        )
    }

    private static func recoveryCueSnapshot(
        for plan: CinematicRecoveryCuePlan
    ) -> CinematicDiagnosticsReport.RecoveryCueSnapshot {
        let selectedCue = plan.selectedCue
        let descriptor = plan.visualDescriptor
        let cameraShakeIdentifier = descriptor.flatMap { cueDescriptor -> String? in
            guard cueDescriptor.shouldShakeCamera else { return nil }
            return CinematicStageEffectPlan.CameraShake(
                shouldShake: true,
                duration: cueDescriptor.cameraShakeDuration,
                scale: cueDescriptor.cameraShakeScale
            ).identifier
        }
        let identifier = [
            "cue:\(selectedCue?.identifier ?? "none")",
            "visual:\(descriptor?.identifier ?? "none")",
            "camera:\(cameraShakeIdentifier ?? "steady")"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.RecoveryCueSnapshot(
            identifier: identifier,
            selectedCueIdentifier: selectedCue?.identifier,
            sessionNumber: selectedCue?.sessionNumber,
            kindIdentifier: selectedCue?.kind.rawValue ?? "none",
            severityIdentifier: selectedCue?.severity.rawValue,
            label: selectedCue?.label,
            detail: selectedCue?.detail,
            systemImage: selectedCue?.systemImage,
            visualIdentifier: descriptor?.identifier ?? "none",
            treatmentIdentifier: descriptor?.treatmentIdentifier ?? "none",
            lightFamilyIdentifier: descriptor?.lightFamily.rawValue ?? "none",
            fractureLightFamilyIdentifier: descriptor?.fractureLightFamily.rawValue ?? "none",
            symbolIdentifier: descriptor?.symbolIdentifier,
            phaseLightIntensity: descriptor?.phaseLightIntensity ?? 0,
            intensity: descriptor?.intensity ?? 0,
            postureIdentifier: descriptor?.posture.rawValue ?? "none",
            arenaEffectIdentifier: descriptor?.arenaEffect.rawValue ?? "none",
            fractureOpacity: descriptor?.fractureOpacity ?? 0,
            fractureSpread: descriptor?.fractureSpread ?? 0,
            healingOpacity: descriptor?.healingOpacity ?? 0,
            shouldShakeCamera: descriptor?.shouldShakeCamera ?? false,
            cameraShakeIdentifier: cameraShakeIdentifier
        )
    }

    private static func stageBeatSnapshot(
        for beat: CinematicStageBeat
    ) -> CinematicDiagnosticsReport.StageBeatSnapshot {
        let accent = beat.activityAccent
        return CinematicDiagnosticsReport.StageBeatSnapshot(
            identifier: beat.identifier,
            phaseIdentifier: beat.phaseIdentifier,
            kindIdentifier: beat.kindIdentifier,
            cameraShotIdentifier: beat.cameraShotIdentifier,
            lightFamilyIdentifier: beat.lightFamilyIdentifier,
            arenaEffectIdentifier: beat.arenaEffectIdentifier,
            phaseLightIntensity: beat.phaseLightIntensity,
            shouldShakeCamera: beat.shouldShakeCamera,
            shouldRunVictorySurge: beat.shouldRunVictorySurge,
            shouldRunHistoryChains: beat.shouldRunHistoryChains,
            activityAccentIdentifier: beat.activityAccentIdentifier,
            activityEventKindIdentifier: accent?.eventKind.rawValue,
            activityLightFamilyIdentifier: accent?.lightFamily.rawValue,
            activityArenaEffectIdentifier: accent?.arenaEffect.rawValue
        )
    }

    private static func stageEffectSnapshot(
        for plan: CinematicStageEffectPlan
    ) -> CinematicDiagnosticsReport.StageEffectSnapshot {
        let effects = plan.effects
        let tuning = plan.tuningMetadata
        let ringIdentifiers = effects.flatMap(\.arenaRings).map(\.identifier)
        let phaseLightPulseIdentifiers = effects.compactMap { $0.phaseLightPulse?.identifier }
        let sparkBurstIdentifiers = effects.flatMap(\.sparkBursts).map(\.identifier)
        let historyTrailIdentifiers = effects.flatMap(\.historyTrails).map(\.identifier)
        let victoryCadenceIdentifier = effects.compactMap { $0.victoryCadence?.identifier }.first
        let cameraShakeIdentifiers = effects.compactMap { $0.cameraShake?.identifier }
        let identifier = [
            "phase:\(plan.phaseEffect.identifier)",
            "activity:\(plan.activityEffect?.identifier ?? "none")",
            "recovery:\(plan.recoveryEffect?.identifier ?? "none")",
            "rings:\(ringIdentifiers.joined(separator: ","))",
            "pulses:\(phaseLightPulseIdentifiers.joined(separator: ","))",
            "sparks:\(sparkBurstIdentifiers.joined(separator: ","))",
            "history:\(historyTrailIdentifiers.joined(separator: ","))",
            "victory:\(victoryCadenceIdentifier ?? "none")",
            "camera:\(cameraShakeIdentifiers.joined(separator: ","))",
            "recovery-cue:\(plan.recoveryCueIdentifier)",
            "tuning:\(tuning.identifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.StageEffectSnapshot(
            identifier: identifier,
            phaseEffectIdentifier: plan.phaseEffect.identifier,
            phaseSourceIdentifier: plan.phaseEffect.sourceIdentifier,
            phaseArenaEffectIdentifier: plan.phaseEffect.arenaEffect.rawValue,
            activityEffectIdentifier: plan.activityEffect?.identifier,
            activitySourceIdentifier: plan.activityEffect?.sourceIdentifier,
            activityArenaEffectIdentifier: plan.activityEffect?.arenaEffect.rawValue,
            recoveryEffectIdentifier: plan.recoveryEffect?.identifier,
            recoverySourceIdentifier: plan.recoveryEffect?.sourceIdentifier,
            recoveryArenaEffectIdentifier: plan.recoveryEffect?.arenaEffect.rawValue,
            arenaRingIdentifiers: ringIdentifiers,
            phaseLightPulseIdentifiers: phaseLightPulseIdentifiers,
            sparkBurstIdentifiers: sparkBurstIdentifiers,
            historyTrailIdentifiers: historyTrailIdentifiers,
            victoryCadenceIdentifier: victoryCadenceIdentifier,
            cameraShakeIdentifiers: cameraShakeIdentifiers,
            arenaRingCount: ringIdentifiers.count,
            phaseLightPulseCount: phaseLightPulseIdentifiers.count,
            sparkBurstCount: sparkBurstIdentifiers.count,
            historyTrailCount: historyTrailIdentifiers.count,
            tuningIdentifier: tuning.identifier,
            recoveryCueIdentifier: plan.recoveryCueIdentifier,
            recoveryCueKindIdentifier: plan.recoveryCueKindIdentifier,
            pressureLevelIdentifier: tuning.pressureLevelIdentifier,
            pressureFraction: tuning.pressureFraction,
            energy: tuning.energy,
            influenceStyleIdentifier: tuning.influenceStyleIdentifier,
            influenceIntensity: tuning.influenceIntensity,
            influenceFraction: tuning.influenceFraction,
            activityLightBoost: tuning.activityLightBoost,
            activityLightBoostFraction: tuning.activityLightBoostFraction,
            runePulseScale: tuning.runePulseScale,
            activityPulseDuration: tuning.activityPulseDuration,
            ringDurationScale: tuning.ringDurationScale,
            ringScaleMultiplier: tuning.ringScaleMultiplier,
            ringOpacityMultiplier: tuning.ringOpacityMultiplier,
            colorAlphaMultiplier: tuning.colorAlphaMultiplier,
            pulseIntensityMultiplier: tuning.pulseIntensityMultiplier,
            pulseDurationMultiplier: tuning.pulseDurationMultiplier,
            sparkBirthRateMultiplier: tuning.sparkBirthRateMultiplier,
            historyTrailTargetCount: tuning.historyTrailCount,
            cameraShakeMultiplier: tuning.cameraShakeMultiplier,
            cameraShakeDurationMultiplier: tuning.cameraShakeDurationMultiplier,
            victoryCadenceMultiplier: tuning.victoryCadenceMultiplier
        )
    }

    private static func stageAtmosphereSnapshot(
        for plan: CinematicStageAtmospherePlan
    ) -> CinematicDiagnosticsReport.StageAtmosphereSnapshot {
        let identifier = [
            "beat:\(plan.beatIdentifier)",
            "phase:\(plan.phaseIdentifier)",
            "activity:\(plan.activityIdentifier)",
            "pressure:\(plan.pressureLevelIdentifier):\(fixed(Double(plan.pressureFraction)))",
            "energy:\(fixed(Double(plan.energy)))",
            "influence:\(plan.influenceStyleIdentifier):\(fixed(Double(plan.influenceIntensity))):\(fixed(Double(plan.influenceFraction)))",
            "halo:\(plan.pressureHalo.identifier)",
            "pulse:\(plan.atmosphericPulse.identifier)",
            "light:\(plan.pressureLighting.identifier)",
            "backdrop:\(plan.backdropTint.identifier)",
            "floor:\(plan.floorTint.identifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.StageAtmosphereSnapshot(
            identifier: identifier,
            beatIdentifier: plan.beatIdentifier,
            phaseIdentifier: plan.phaseIdentifier,
            activityIdentifier: plan.activityIdentifier,
            pressureLevelIdentifier: plan.pressureLevelIdentifier,
            influenceStyleIdentifier: plan.influenceStyleIdentifier,
            influenceIntensity: plan.influenceIntensity,
            pressureFraction: plan.pressureFraction,
            influenceFraction: plan.influenceFraction,
            energy: plan.energy,
            pressureHaloIdentifier: plan.pressureHalo.identifier,
            pressureHaloRadius: plan.pressureHalo.radius,
            pressureHaloOpacity: plan.pressureHalo.opacity,
            pressureHaloScale: plan.pressureHalo.scale,
            pressureHaloColorAlpha: plan.pressureHalo.colorAlpha,
            atmosphericPulseIdentifier: plan.atmosphericPulse.identifier,
            atmosphericPulseCadence: plan.atmosphericPulse.cadence,
            atmosphericPulseAmplitude: plan.atmosphericPulse.amplitude,
            atmosphericPulseOpacity: plan.atmosphericPulse.opacity,
            pressureLightingIdentifier: plan.pressureLighting.identifier,
            phaseLightPressureBoost: plan.pressureLighting.phaseLightPressureBoost,
            rimLightPressureBoost: plan.pressureLighting.rimLightPressureBoost,
            pressureLightColorAlpha: plan.pressureLighting.colorAlpha,
            backdropTintIdentifier: plan.backdropTint.identifier,
            backdropTintRed: plan.backdropTint.red,
            backdropTintGreen: plan.backdropTint.green,
            backdropTintBlue: plan.backdropTint.blue,
            backdropTintOpacity: plan.backdropTint.opacity,
            backdropTintBlendFraction: plan.backdropTint.blendFraction,
            floorTintIdentifier: plan.floorTint.identifier,
            floorTintRed: plan.floorTint.red,
            floorTintGreen: plan.floorTint.green,
            floorTintBlue: plan.floorTint.blue,
            floorTintOpacity: plan.floorTint.opacity,
            floorTintBlendFraction: plan.floorTint.blendFraction
        )
    }

    private static func stagePhasePolishSnapshot(
        for plan: CinematicStagePhasePolishPlan
    ) -> CinematicDiagnosticsReport.StagePhasePolishSnapshot {
        let identifier = [
            "beat:\(plan.beatIdentifier)",
            "effect:\(plan.stageEffectTuningIdentifier)",
            "atmosphere:\(plan.atmosphereIdentifier)",
            "phase:\(plan.phaseIdentifier)",
            "activity:\(plan.activityIdentifier)",
            "recovery:\(plan.recoveryCueIdentifier)",
            "posture:\(plan.postureIdentifier)",
            "pose:\(plan.wizardPose.identifier)",
            "orb:\(plan.staffOrb.identifier)",
            "sigil:\(plan.sigilEmphasis.identifier)",
            "portal:\(plan.portalBackdrop.identifier)",
            "fracture:\(plan.fractureRecovery.identifier)",
            "cadence:\(plan.cadence.identifier)",
            "influence:\(plan.influenceIdentifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.StagePhasePolishSnapshot(
            identifier: identifier,
            beatIdentifier: plan.beatIdentifier,
            stageEffectTuningIdentifier: plan.stageEffectTuningIdentifier,
            atmosphereIdentifier: plan.atmosphereIdentifier,
            phaseIdentifier: plan.phaseIdentifier,
            activityIdentifier: plan.activityIdentifier,
            recoveryCueIdentifier: plan.recoveryCueIdentifier,
            recoveryCueKindIdentifier: plan.recoveryCueKindIdentifier,
            influenceIdentifier: plan.influenceIdentifier,
            postureIdentifier: plan.postureIdentifier,
            wizardPoseIdentifier: plan.wizardPose.identifier,
            poseIntensity: plan.wizardPose.poseIntensity,
            staffOrbIdentifier: plan.staffOrb.identifier,
            staffOrbLightFamilyIdentifier: plan.staffOrb.lightFamily.rawValue,
            staffOrbScale: plan.staffOrb.scale,
            staffOrbEmission: plan.staffOrb.emission,
            staffOrbPulseAmplitude: plan.staffOrb.pulseAmplitude,
            sigilEmphasisIdentifier: plan.sigilEmphasis.identifier,
            sigilOrbitRadius: plan.sigilEmphasis.orbitRadius,
            sigilSealEmphasis: plan.sigilEmphasis.sealEmphasis,
            sigilVictoryEmphasis: plan.sigilEmphasis.victoryEmphasis,
            sigilPulseAmplitude: plan.sigilEmphasis.pulseAmplitude,
            portalBackdropIdentifier: plan.portalBackdrop.identifier,
            portalLightFamilyIdentifier: plan.portalBackdrop.lightFamily.rawValue,
            portalAperture: plan.portalBackdrop.portalAperture,
            portalScale: plan.portalBackdrop.portalScale,
            portalOpacity: plan.portalBackdrop.portalOpacity,
            backdropAperture: plan.portalBackdrop.backdropAperture,
            backdropOpacityBoost: plan.portalBackdrop.backdropOpacityBoost,
            fractureRecoveryIdentifier: plan.fractureRecovery.identifier,
            fractureLightFamilyIdentifier: plan.fractureRecovery.lightFamily.rawValue,
            fractureOpacity: plan.fractureRecovery.fractureOpacity,
            fractureSpread: plan.fractureRecovery.fractureSpread,
            healingOpacity: plan.fractureRecovery.healingOpacity,
            cadenceIdentifier: plan.cadence.identifier,
            poseCadence: plan.cadence.poseCadence,
            orbPulseCadence: plan.cadence.orbPulseCadence,
            sigilOrbitCadence: plan.cadence.sigilOrbitCadence,
            fractureCadence: plan.cadence.fractureCadence
        )
    }

    private static func narrativeCueSnapshot(
        for plan: CinematicSceneNarrativeCuePlan
    ) -> CinematicDiagnosticsReport.NarrativeCueSnapshot {
        let quest = narrativeCueDescriptorSnapshot(for: plan.questPlaque)
        let arena = narrativeCueDescriptorSnapshot(for: plan.arenaInscription)
        let activity = narrativeCueDescriptorSnapshot(for: plan.activityBanner)
        let identifier = [
            "beat:\(plan.stageBeatIdentifier)",
            "phase-polish:\(plan.stagePhasePolishIdentifier)",
            "language:\(plan.languageIdentifier)",
            "activity:\(plan.activityIdentifier)",
            "quest:\(quest.identifier)",
            "arena:\(arena.identifier)",
            "banner:\(activity.identifier)",
            "influence:\(plan.influenceIdentifier)",
            "native:\(plan.nativeFeedbackCueIdentifier)",
            "native-lifecycle:\(plan.nativeFeedbackLifecycleIdentifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.NarrativeCueSnapshot(
            identifier: identifier,
            stageBeatIdentifier: plan.stageBeatIdentifier,
            stagePhasePolishIdentifier: plan.stagePhasePolishIdentifier,
            languageIdentifier: plan.languageIdentifier,
            activityIdentifier: plan.activityIdentifier,
            influenceIdentifier: plan.influenceIdentifier,
            nativeFeedbackCueIdentifier: plan.nativeFeedbackCueIdentifier,
            nativeFeedbackLifecycleIdentifier: plan.nativeFeedbackLifecycleIdentifier,
            nativeFeedbackSourceIdentifier: plan.nativeFeedbackSourceIdentifier,
            nativeFeedbackStyleIdentifier: plan.nativeFeedbackStyleIdentifier,
            nativeFeedbackMilestoneIdentifier: plan.nativeFeedbackMilestoneIdentifier,
            nativeFeedbackAffectedDescriptorIdentifiers: plan.nativeFeedbackAffectedDescriptorIdentifiers,
            questPlaque: quest,
            arenaInscription: arena,
            activityBanner: activity
        )
    }

    private static func nativeFeedbackSnapshot(
        for cue: CinematicNativeFeedbackCuePlan?,
        lifecycle: CinematicNativeFeedbackCueLifecycle,
        narrativeCuePlan: CinematicSceneNarrativeCuePlan
    ) -> CinematicDiagnosticsReport.NativeFeedbackSnapshot {
        let lifecycleIdentifier = lifecycle.hasState
            ? lifecycle.identifier
            : cue?.lifecycleIdentifier ?? "none"
        let lifecycleStateIdentifier = lifecycle.hasState
            ? lifecycle.stateIdentifier
            : cue?.lifecycleStateIdentifier ?? "none"
        let activeCueIdentifier = lifecycle.active?.cueIdentifier ?? "none"
        let archiveIdentifiers = lifecycle.recentArchiveIdentifiers
        let activeHistoryEntry = lifecycle.active.map(nativeFeedbackHistoryEntry)
        let archiveHistoryEntries = lifecycle.recentArchive.map(nativeFeedbackHistoryEntry)
        let historyEntries = [activeHistoryEntry].compactMap { $0 } + archiveHistoryEntries
        let historyIdentifier = historyEntries.isEmpty
            ? "none"
            : historyEntries.map(\.identifier).joined(separator: ",")

        guard let cue else {
            return CinematicDiagnosticsReport.NativeFeedbackSnapshot(
                identifier: [
                    "native-feedback.none",
                    "lifecycle:\(lifecycleIdentifier)",
                    "state:\(lifecycleStateIdentifier)",
                    "archives:\(archiveIdentifiers.isEmpty ? "none" : archiveIdentifiers.joined(separator: ","))",
                    "history:\(historyIdentifier)"
                ].joined(separator: "|"),
                cueIdentifier: "none",
                lifecycleIdentifier: lifecycleIdentifier,
                lifecycleStateIdentifier: lifecycleStateIdentifier,
                lifecycleActiveCueIdentifier: activeCueIdentifier,
                lifecycleRecentArchiveIdentifiers: archiveIdentifiers,
                lifecycleRecentArchiveCount: archiveIdentifiers.count,
                lifecycleActiveHistoryEntry: activeHistoryEntry,
                lifecycleArchiveHistoryEntries: archiveHistoryEntries,
                lifecycleHistoryEntryCount: historyEntries.count,
                sourceIdentifier: "none",
                styleIdentifier: "none",
                milestoneIdentifier: "none",
                affectedNarrativeDescriptorIdentifiers: []
            )
        }

        let affectedDescriptors = narrativeCuePlan.nativeFeedbackAffectedDescriptorIdentifiers
        let identifier = [
            cue.identifier,
            "source:\(cue.sourceIdentifier)",
            "style:\(cue.styleIdentifier)",
            "milestone:\(cue.milestoneIdentifier)",
            "lifecycle:\(lifecycleIdentifier)",
            "state:\(lifecycleStateIdentifier)",
            "archives:\(archiveIdentifiers.count)",
            "history:\(historyIdentifier)",
            "affects:\(affectedDescriptors.isEmpty ? "none" : affectedDescriptors.joined(separator: ","))"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.NativeFeedbackSnapshot(
            identifier: identifier,
            cueIdentifier: cue.identifier,
            lifecycleIdentifier: lifecycleIdentifier,
            lifecycleStateIdentifier: lifecycleStateIdentifier,
            lifecycleActiveCueIdentifier: activeCueIdentifier,
            lifecycleRecentArchiveIdentifiers: archiveIdentifiers,
            lifecycleRecentArchiveCount: archiveIdentifiers.count,
            lifecycleActiveHistoryEntry: activeHistoryEntry,
            lifecycleArchiveHistoryEntries: archiveHistoryEntries,
            lifecycleHistoryEntryCount: historyEntries.count,
            sourceIdentifier: cue.sourceIdentifier,
            styleIdentifier: cue.styleIdentifier,
            milestoneIdentifier: cue.milestoneIdentifier,
            affectedNarrativeDescriptorIdentifiers: affectedDescriptors
        )
    }

    private static func nativeFeedbackHistoryEntry(
        _ active: CinematicNativeFeedbackCueLifecycle.ActiveCue
    ) -> CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot {
        let cue = active.cue
        let metadata = active.metadata
        return nativeFeedbackHistoryEntry(
            cueIdentifier: cue.identifier,
            lifecycleIdentifier: metadata.identifier,
            sequence: metadata.sequence,
            stateIdentifier: metadata.state.rawValue,
            reasonIdentifier: nil,
            milestoneIdentifier: cue.milestoneIdentifier,
            sourceIdentifier: cue.sourceIdentifier,
            styleIdentifier: cue.styleIdentifier,
            displayDuration: metadata.displayDuration
        )
    }

    private static func nativeFeedbackHistoryEntry(
        _ archived: CinematicNativeFeedbackCueLifecycle.ArchivedCue
    ) -> CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot {
        nativeFeedbackHistoryEntry(
            cueIdentifier: archived.cueIdentifier,
            lifecycleIdentifier: archived.lifecycleIdentifier,
            sequence: archived.sequence,
            stateIdentifier: archived.stateIdentifier,
            reasonIdentifier: archived.archiveReason.rawValue,
            milestoneIdentifier: archived.milestoneIdentifier,
            sourceIdentifier: archived.sourceIdentifier,
            styleIdentifier: archived.styleIdentifier,
            displayDuration: archived.displayDuration
        )
    }

    private static func nativeFeedbackHistoryEntry(
        cueIdentifier: String,
        lifecycleIdentifier: String,
        sequence: Int,
        stateIdentifier: String,
        reasonIdentifier: String?,
        milestoneIdentifier: String,
        sourceIdentifier: String?,
        styleIdentifier: String?,
        displayDuration: TimeInterval
    ) -> CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot {
        let identifier = [
            "seq:\(sequence)",
            "state:\(stateIdentifier)",
            reasonIdentifier.map { "reason:\($0)" },
            "milestone:\(milestoneIdentifier)",
            sourceIdentifier.map { "source:\($0)" },
            styleIdentifier.map { "style:\($0)" },
            "duration:\(fixed(displayDuration))",
            "lifecycle:\(lifecycleIdentifier)"
        ].compactMap { $0 }.joined(separator: "|")

        return CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot(
            identifier: identifier,
            cueIdentifier: cueIdentifier,
            lifecycleIdentifier: lifecycleIdentifier,
            sequence: sequence,
            stateIdentifier: stateIdentifier,
            reasonIdentifier: reasonIdentifier,
            milestoneIdentifier: milestoneIdentifier,
            sourceIdentifier: sourceIdentifier,
            styleIdentifier: styleIdentifier,
            displayDuration: displayDuration
        )
    }

    private static func narrativeCueDescriptorSnapshot(
        for descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor
    ) -> CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot {
        CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot(
            identifier: descriptor.identifier,
            stableID: descriptor.stableID,
            text: descriptor.text,
            secondaryText: descriptor.secondaryText,
            glyphIdentifier: descriptor.glyphIdentifier,
            anchorIdentifier: descriptor.anchorIdentifier,
            visibilityIdentifier: descriptor.visibilityIdentifier,
            scale: descriptor.scale,
            opacity: descriptor.opacity,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            tintFamilyIdentifier: descriptor.tintFamilyIdentifier,
            cadence: descriptor.cadence,
            plaqueTreatmentIdentifier: descriptor.plaqueTreatmentIdentifier,
            plaqueTreatmentAccentIdentifier: descriptor.plaqueTreatmentAccentIdentifier,
            plaqueTreatmentRouteIdentifier: descriptor.plaqueTreatmentRouteIdentifier,
            plaqueTreatmentRenderRecipeIdentifier: descriptor.plaqueTreatmentRenderRecipeIdentifier,
            plaqueTreatmentRenderPrimitiveIdentifiers: descriptor.plaqueTreatmentRenderPrimitiveIdentifiers,
            plaqueTreatmentRenderPrimitiveCount: descriptor.plaqueTreatmentRenderPrimitiveCount,
            layout: narrativeCueLayoutSnapshot(for: descriptor.layout)
        )
    }

    private static func narrativeCueLayoutSnapshot(
        for layout: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor
    ) -> CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot {
        CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot(
            identifier: layout.identifier,
            anchorPosition: layout.anchorPosition,
            facingModeIdentifier: layout.facingModeIdentifier,
            plateWidth: layout.plateSize.x,
            plateHeight: layout.plateSize.y,
            primaryTextWidth: layout.primaryTextWidth,
            secondaryTextWidth: layout.secondaryTextWidth,
            primaryFontSize: layout.primaryFontSize,
            secondaryFontSize: layout.secondaryFontSize,
            backingOpacity: layout.backingOpacity,
            glyphSideIdentifier: layout.glyphSideIdentifier,
            glyphOffset: layout.glyphOffset,
            plateDepth: layout.plateDepth,
            plateZOffset: layout.plateZOffset,
            primaryTextOffset: layout.primaryTextOffset,
            secondaryTextOffset: layout.secondaryTextOffset
        )
    }

    private static func overlayDisplaySnapshot(
        for plan: CinematicOverlayDisplayPlan
    ) -> CinematicDiagnosticsReport.OverlayDisplaySnapshot {
        CinematicDiagnosticsReport.OverlayDisplaySnapshot(
            identifier: plan.identifier,
            modeIdentifier: plan.modeIdentifier,
            visiblePillIdentifiers: plan.visiblePillIdentifiers,
            hudProminenceIdentifier: plan.hudProminenceIdentifier,
            chromeStyleIdentifier: plan.chromeStyleIdentifier,
            gradientStrength: plan.gradientStrength,
            worldTextMaxWidth: plan.worldTextMaxWidth,
            hudMaxWidth: plan.hudMaxWidth,
            pillLineLimit: plan.pillLineLimit,
            hudTitleLineLimit: plan.hudTitleLineLimit,
            hudDetailLineLimit: plan.hudDetailLineLimit,
            hudProfileLineLimit: plan.hudProfileLineLimit,
            hudStatusLineLimit: plan.hudStatusLineLimit,
            overlayOpacity: plan.overlayOpacity,
            reasonIdentifier: plan.reasonIdentifier,
            narrativeCueReadabilityIdentifier: plan.narrativeCueReadabilityIdentifier,
            nativeFeedbackCueIdentifier: plan.nativeFeedbackCueIdentifier,
            nativeFeedbackLifecycleIdentifier: plan.nativeFeedbackLifecycleIdentifier,
            nativeFeedbackBannerPolicyIdentifier: plan.nativeFeedbackBannerPolicyIdentifier,
            showsNativeFeedbackBanner: plan.showsNativeFeedbackBanner
        )
    }

    private static func worldTextSnapshot(
        for worldText: CinematicWorldText
    ) -> CinematicDiagnosticsReport.WorldTextSnapshot {
        let identifier = [
            worldText.questLabel,
            worldText.arenaCallout,
            worldText.activityCallout
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.WorldTextSnapshot(
            identifier: identifier,
            questLabel: worldText.questLabel,
            arenaCallout: worldText.arenaCallout,
            activityCallout: worldText.activityCallout
        )
    }

    private static func briefingSnapshot(
        for briefing: CinematicBriefing
    ) -> CinematicDiagnosticsReport.BriefingSnapshot {
        let identifier = [briefing.title, briefing.detail].joined(separator: "|")
        return CinematicDiagnosticsReport.BriefingSnapshot(
            identifier: identifier,
            title: briefing.title,
            detail: briefing.detail
        )
    }

    private static func cameraTuningSnapshot(
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.CameraTuningSnapshot {
        let orbitScale = CinematicTuning.cameraOrbitScale(settings: settings)
        let pullbackScale = CinematicTuning.cameraPullbackScale(settings: settings)
        let heightOffset = CinematicTuning.cameraHeightOffset(settings: settings)
        let followResponsiveness = CinematicTuning.cameraFollowResponsiveness(settings: settings)
        let followFieldOfView = CinematicTuning.cameraFollowFieldOfView(settings: settings)
        let driftScale = CinematicTuning.cameraDriftScale(settings: settings)
        let shakeScale = CinematicTuning.cameraShakeScale(settings: settings)
        let identifier = [
            settingsIdentifier(settings),
            fixed(Double(orbitScale)),
            fixed(Double(pullbackScale)),
            fixed(Double(heightOffset)),
            fixed(Double(followResponsiveness)),
            fixed(Double(followFieldOfView)),
            fixed(Double(driftScale)),
            fixed(Double(shakeScale))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.CameraTuningSnapshot(
            identifier: identifier,
            orbitScale: orbitScale,
            pullbackScale: pullbackScale,
            heightOffset: heightOffset,
            followResponsiveness: followResponsiveness,
            followFieldOfView: followFieldOfView,
            driftScale: driftScale,
            shakeScale: shakeScale
        )
    }

    private static func activityTuningSnapshot(
        activityProfile: RepositoryActivityProfile,
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.ActivityTuningSnapshot {
        let ambientSpawnCadence = CinematicTuning.ambientSpawnCadence(
            activityProfile: activityProfile,
            settings: settings
        )
        let ambientEnemyLimit = CinematicTuning.ambientEnemyLimit(
            activityProfile: activityProfile,
            settings: settings
        )
        let activityLightBoost = CinematicTuning.activityLightBoost(
            activityProfile: activityProfile,
            settings: settings
        )
        let activityPressureScale = CinematicTuning.activityPressureScale(settings: settings)
        let pressureLevelIdentifier = activityProfile.pressureLevel.rawValue
        let identifier = [
            settingsIdentifier(settings),
            pressureLevelIdentifier,
            fixed(ambientSpawnCadence),
            String(ambientEnemyLimit),
            fixed(Double(activityLightBoost)),
            fixed(Double(activityPressureScale))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.ActivityTuningSnapshot(
            identifier: identifier,
            pressureLevelIdentifier: pressureLevelIdentifier,
            ambientSpawnCadence: ambientSpawnCadence,
            ambientEnemyLimit: ambientEnemyLimit,
            activityLightBoost: activityLightBoost,
            activityPressureScale: activityPressureScale
        )
    }

    private static func setDressingSnapshot(
        for plan: CinematicSetDressingPlan
    ) -> CinematicDiagnosticsReport.SetDressingSnapshot {
        CinematicDiagnosticsReport.SetDressingSnapshot(
            identifier: plan.identifier,
            languageArchitectureIdentifier: plan.languageArchitecture.identifier,
            activityMarkerIdentifier: plan.activityMarker.identifier,
            pedestalLayoutIdentifier: plan.languageArchitecture.pedestalLayoutIdentifier,
            shardFormationIdentifier: plan.languageArchitecture.shardFormationIdentifier,
            pedestalSlotCount: plan.languageArchitecture.pedestalSlots.count,
            shardSlotCount: plan.languageArchitecture.shardSlots.count,
            layoutGeometryCoverageIdentifier: plan.languageArchitecture.layoutCoverageIdentifier,
            layoutGeometryIsBounded: plan.languageArchitecture.geometryIsBounded,
            pedestalCount: plan.pedestalFlames.pedestalCount,
            flameLightIntensity: plan.pedestalFlames.flameLightIntensity,
            flameOpacity: plan.pedestalFlames.flameOpacity,
            rimOpacity: plan.pedestalFlames.rimOpacity,
            shardCount: plan.floatingShards.shardCount,
            shardEmissionOpacity: plan.floatingShards.emissionOpacity,
            runeIntensityIdentifier: plan.runeIntensity.identifier,
            animationCadenceIdentifier: plan.animationCadence.identifier,
            flamePulseRate: plan.animationCadence.flamePulseRate,
            shardBobRate: plan.animationCadence.shardBobRate,
            ambientSpawnCadence: plan.ambientSpawnCadence,
            ambientEnemyLimit: plan.ambientEnemyLimit,
            activityLightBoost: plan.activityLightBoost,
            materialTextureVariantIdentifier: plan.materialTextureVariants.identifier,
            backdropTextureAssetIdentifier: plan.materialTextureVariants.backdropTextureAsset.identifier,
            arenaTextureAssetIdentifier: plan.materialTextureVariants.arenaTextureAsset.identifier,
            backdropTextureRouteIdentifier: plan.materialTextureVariants.backdropTextureAsset.routeIdentifier,
            arenaTextureRouteIdentifier: plan.materialTextureVariants.arenaTextureAsset.routeIdentifier,
            textureRoleCoverageIdentifier: plan.materialTextureVariants.textureRoleCoverageIdentifier,
            runeMaterialIdentifier: plan.materialTextureVariants.runeMaterialIdentifier,
            runeMaterialTreatmentIdentifier: plan.materialTextureVariants.runeMaterialTreatment.identifier,
            runeFloorEmissionOpacity: plan.materialTextureVariants.runeMaterialTreatment.floorEmissionOpacity,
            runeSegmentOpacityScale: plan.materialTextureVariants.runeMaterialTreatment.segmentOpacityScale,
            arenaAccentOpacityScale: plan.materialTextureVariants.runeMaterialTreatment.arenaAccentOpacityScale,
            backdropTextureName: plan.materialTextureVariants.backdropTextureName,
            arenaTextureName: plan.materialTextureVariants.arenaTextureName,
            usesFallbackTextureAsset: plan.materialTextureVariants.usesFallbackTextureAsset
        )
    }

    private static func commitConstellationSnapshot(
        for plan: CinematicCommitConstellationPlan
    ) -> CinematicDiagnosticsReport.CommitConstellationSnapshot {
        let focusPlan = plan.focusPlan
        return CinematicDiagnosticsReport.CommitConstellationSnapshot(
            identifier: [
                plan.identifier,
                "focus:\(focusPlan.identifier)"
            ].joined(separator: "|"),
            count: plan.count,
            newestSubject: plan.newestSubject,
            nodeIdentifiers: plan.nodeIdentifiers,
            branchIdentifiers: plan.branchIdentifiers,
            focusIdentifier: focusPlan.identifier,
            focusShotIdentifier: focusPlan.shot.identifier,
            focusLookTarget: focusPlan.lookTarget,
            usesFallbackFocus: focusPlan.isFallback
        )
    }

    private static func idleStoryCycleSnapshot(
        for plan: CinematicIdleStoryCyclePlan
    ) -> CinematicDiagnosticsReport.IdleStoryCycleSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.IdleStoryCycleSnapshot(
                identifier: plan.identifier,
                isActive: false,
                phaseIdentifier: "none",
                sourceDescriptorIdentifier: "none",
                targetKindIdentifier: "none",
                cadence: 0,
                cameraTreatmentIdentifier: "none",
                anchorTreatmentIdentifier: "none",
                choreographyIdentifier: "none",
                dwellDuration: 0,
                transitionDurationScale: 0,
                cameraPressureIdentifier: "none",
                targetBias: 0,
                comfortDamping: 0,
                shakeHintIdentifier: "none",
                pulseHintIdentifier: "none",
                suppressionReason: plan.suppressionReason,
                phaseCopy: "",
                descriptorIdentifier: "none",
                cycleSlot: 0,
                phaseIndex: -1
            )
        }

        return CinematicDiagnosticsReport.IdleStoryCycleSnapshot(
            identifier: plan.identifier,
            isActive: true,
            phaseIdentifier: descriptor.phaseIdentifier,
            sourceDescriptorIdentifier: descriptor.sourceDescriptorIdentifier,
            targetKindIdentifier: descriptor.targetKindIdentifier,
            cadence: descriptor.cadence,
            cameraTreatmentIdentifier: descriptor.cameraTreatmentIdentifier,
            anchorTreatmentIdentifier: descriptor.anchorTreatmentIdentifier,
            choreographyIdentifier: descriptor.choreography.identifier,
            dwellDuration: descriptor.choreography.dwellDuration,
            transitionDurationScale: descriptor.choreography.transitionDurationScale,
            cameraPressureIdentifier: descriptor.choreography.cameraPressureIdentifier,
            targetBias: descriptor.choreography.targetBias,
            comfortDamping: descriptor.choreography.comfortDamping,
            shakeHintIdentifier: descriptor.choreography.shakeHintIdentifier,
            pulseHintIdentifier: descriptor.choreography.pulseHintIdentifier,
            suppressionReason: plan.suppressionReason,
            phaseCopy: descriptor.phaseCopy,
            descriptorIdentifier: descriptor.identifier,
            cycleSlot: descriptor.cycleSlot,
            phaseIndex: descriptor.phaseIndex
        )
    }

    private static func timelineFocusSnapshot(
        for plan: CinematicTimelineSceneFocusPlan
    ) -> CinematicDiagnosticsReport.TimelineFocusSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.TimelineFocusSnapshot(
                identifier: plan.identifier,
                selectedBeatID: plan.selectedBeatID,
                isActive: false,
                kindIdentifier: "none",
                descriptorIdentifier: "none",
                label: nil,
                cameraShotIdentifier: "none",
                lookTarget: nil,
                lightFamilyIdentifier: "none",
                arenaEffectIdentifier: "none",
                phaseLightIntensity: 0,
                commitNodeIdentifier: nil,
                recoveryTreatmentIdentifier: nil,
                recoveryVisualIdentifier: nil,
                usesFallbackTarget: false
            )
        }

        return CinematicDiagnosticsReport.TimelineFocusSnapshot(
            identifier: plan.identifier,
            selectedBeatID: plan.selectedBeatID,
            isActive: true,
            kindIdentifier: descriptor.kindIdentifier,
            descriptorIdentifier: descriptor.identifier,
            label: descriptor.label,
            cameraShotIdentifier: descriptor.cameraShotIdentifier,
            lookTarget: descriptor.lookTarget,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            arenaEffectIdentifier: descriptor.arenaEffectIdentifier,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            commitNodeIdentifier: descriptor.commitNodeIdentifier,
            recoveryTreatmentIdentifier: descriptor.recoveryTreatmentIdentifier,
            recoveryVisualIdentifier: descriptor.recoveryVisualIdentifier,
            usesFallbackTarget: descriptor.usesFallbackTarget
        )
    }

    private static func runRecapSnapshot(
        for plan: CinematicRunRecapPlan
    ) -> CinematicDiagnosticsReport.RunRecapSnapshot {
        CinematicDiagnosticsReport.RunRecapSnapshot(
            identifier: plan.identifier,
            availabilityIdentifier: plan.availabilityIdentifier,
            isAvailable: plan.isAvailable,
            sessionNumber: plan.sessionNumber,
            title: plan.title,
            detail: plan.detail,
            status: plan.status,
            statusIdentifier: plan.statusIdentifier,
            styleIdentifier: plan.style.rawValue,
            colorIdentifier: plan.colorIdentifier,
            systemImage: plan.systemImage,
            latestCompletedSummary: plan.latestCompletedSummary,
            newestCommitHighlight: plan.newestCommitHighlight,
            completedCount: plan.completedCount,
            commitHighlightCount: plan.commitHighlightCount,
            eventChipCount: plan.eventChipCount,
            eventChipIdentifiers: plan.eventChips.map(\.identifier),
            sourceIdentifier: plan.sourceIdentifier,
            flavorStateIdentifier: plan.flavorStateIdentifier,
            flavorIdentifier: plan.flavorIdentifier,
            flavorSourceIdentifier: plan.flavorSourceIdentifier,
            titleSourceIdentifier: plan.titleSourceIdentifier
        )
    }

    private static func runRecapShareSnapshot(
        for plan: CinematicRunRecapSharePlan
    ) -> CinematicDiagnosticsReport.RunRecapShareSnapshot {
        CinematicDiagnosticsReport.RunRecapShareSnapshot(
            identifier: plan.identifier,
            availabilityIdentifier: plan.availabilityIdentifier,
            availabilityReason: plan.availabilityReason,
            isAvailable: plan.isAvailable,
            recapIdentifier: plan.recapIdentifier,
            recapFocusIdentifier: plan.recapFocusIdentifier,
            endCardIdentifier: plan.endCardIdentifier,
            title: plan.title,
            detail: plan.detail,
            status: plan.status,
            commitHighlight: plan.commitHighlight,
            eventSummaries: plan.eventSummaries,
            eventSummaryCount: plan.eventSummaryCount,
            visualDescriptorTokens: plan.visualDescriptorTokens,
            visualDescriptorTokenCount: plan.visualDescriptorTokenCount,
            text: plan.text,
            textLength: plan.textLength
        )
    }

    private static func runRecapSceneFocusSnapshot(
        for plan: CinematicRunRecapSceneFocusPlan
    ) -> CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot(
                identifier: plan.identifier,
                isActive: false,
                descriptorIdentifier: "none",
                recapIdentifier: "none",
                terminalBeatID: nil,
                terminalStatusIdentifier: "none",
                terminalStyleIdentifier: "none",
                cameraShotIdentifier: "none",
                lookTarget: nil,
                lightFamilyIdentifier: "none",
                arenaEffectIdentifier: "none",
                phaseLightIntensity: 0,
                commitNodeIdentifier: nil,
                fallbackTargetIdentifier: nil,
                usesFallbackTarget: false
            )
        }

        return CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot(
            identifier: plan.identifier,
            isActive: true,
            descriptorIdentifier: descriptor.identifier,
            recapIdentifier: descriptor.recapIdentifier,
            terminalBeatID: descriptor.terminalBeatID,
            terminalStatusIdentifier: descriptor.terminalStatusIdentifier,
            terminalStyleIdentifier: descriptor.terminalStyleIdentifier,
            cameraShotIdentifier: descriptor.cameraShotIdentifier,
            lookTarget: descriptor.lookTarget,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            arenaEffectIdentifier: descriptor.arenaEffectIdentifier,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            commitNodeIdentifier: descriptor.commitNodeIdentifier,
            fallbackTargetIdentifier: descriptor.fallbackTargetIdentifier,
            usesFallbackTarget: descriptor.usesFallbackTarget
        )
    }

    private static func runRecapEndCardSnapshot(
        for plan: CinematicRunRecapEndCardPlan
    ) -> CinematicDiagnosticsReport.RunRecapEndCardSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.RunRecapEndCardSnapshot(
                identifier: plan.identifier,
                isActive: false,
                descriptorIdentifier: "none",
                recapIdentifier: "none",
                title: "",
                detail: "",
                status: "",
                titleSourceIdentifier: "none",
                flavorStateIdentifier: "none",
                flavorIdentifier: nil,
                flavorSourceIdentifier: nil,
                styleIdentifier: "none",
                colorIdentifier: "none",
                anchorIdentifier: "none",
                scale: 0,
                cadence: 0,
                lightFamilyIdentifier: "none",
                tintFamilyIdentifier: "none",
                glyphIdentifier: "none",
                layoutIdentifier: "none",
                plateWidth: 0,
                plateHeight: 0,
                plaqueTreatmentIdentifier: "none",
                plaqueTreatmentAccentIdentifier: "none",
                plaqueTreatmentRouteIdentifier: "none",
                plaqueTreatmentRenderRecipeIdentifier: "none",
                plaqueTreatmentRenderPrimitiveIdentifiers: [],
                plaqueTreatmentRenderPrimitiveCount: 0,
                titleLength: 0,
                detailLength: 0,
                statusLength: 0
            )
        }

        return CinematicDiagnosticsReport.RunRecapEndCardSnapshot(
            identifier: plan.identifier,
            isActive: true,
            descriptorIdentifier: descriptor.identifier,
            recapIdentifier: descriptor.recapIdentifier,
            title: descriptor.title,
            detail: descriptor.detail,
            status: descriptor.status,
            titleSourceIdentifier: descriptor.titleSourceIdentifier,
            flavorStateIdentifier: descriptor.flavorStateIdentifier,
            flavorIdentifier: descriptor.flavorIdentifier,
            flavorSourceIdentifier: descriptor.flavorSourceIdentifier,
            styleIdentifier: descriptor.styleIdentifier,
            colorIdentifier: descriptor.colorIdentifier,
            anchorIdentifier: descriptor.anchorIdentifier,
            scale: descriptor.scale,
            cadence: descriptor.cadence,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            tintFamilyIdentifier: descriptor.tintFamilyIdentifier,
            glyphIdentifier: descriptor.glyphIdentifier,
            layoutIdentifier: descriptor.layout.identifier,
            plateWidth: descriptor.layout.plateSize.x,
            plateHeight: descriptor.layout.plateSize.y,
            plaqueTreatmentIdentifier: descriptor.plaqueTreatmentIdentifier,
            plaqueTreatmentAccentIdentifier: descriptor.plaqueTreatmentAccentIdentifier,
            plaqueTreatmentRouteIdentifier: descriptor.plaqueTreatmentRouteIdentifier,
            plaqueTreatmentRenderRecipeIdentifier: descriptor.plaqueTreatmentRenderRecipeIdentifier,
            plaqueTreatmentRenderPrimitiveIdentifiers: descriptor.plaqueTreatmentRenderPrimitiveIdentifiers,
            plaqueTreatmentRenderPrimitiveCount: descriptor.plaqueTreatmentRenderPrimitiveCount,
            titleLength: descriptor.titleLength,
            detailLength: descriptor.detailLength,
            statusLength: descriptor.statusLength
        )
    }

    private static func cameraSnapshot(
        for shot: CinematicCameraShot,
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.CameraSnapshot {
        let position = CinematicTuning.cameraPosition(for: shot, settings: settings)
        let fieldOfView = CinematicTuning.cameraFieldOfView(for: shot, settings: settings)
        let transitionDuration = CinematicTuning.cameraTransitionDuration(for: shot, settings: settings)
        let identifier = [
            shot.identifier,
            settingsIdentifier(settings),
            positionIdentifier(position),
            fixed(Double(fieldOfView)),
            fixed(transitionDuration)
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.CameraSnapshot(
            identifier: identifier,
            shotIdentifier: shot.identifier,
            position: position,
            fieldOfView: fieldOfView,
            transitionDuration: transitionDuration
        )
    }

    private static func representativeLanguageProfile(
        for language: RepositoryLanguage
    ) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = language == .unknown ? 0 : 4
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: manifestHints(for: language),
            primaryLanguage: language,
            scannedFileCount: language == .unknown ? 0 : 4,
            scannedDirectoryCount: language == .unknown ? 0 : 1,
            wasTruncated: false
        )
    }

    private static func manifestHints(for language: RepositoryLanguage) -> [RepositoryManifestHint] {
        switch language {
        case .typeScriptJavaScript:
            return [.packageJSON]
        case .python:
            return [.pyprojectToml]
        case .go:
            return [.goMod]
        case .rust:
            return [.cargoToml]
        case .swift:
            return [.packageSwift]
        case .markdown, .other, .unknown:
            return []
        }
    }

    private static func activityProfile(
        worktreeChanges: RepositoryWorktreeChangeCounts = RepositoryWorktreeChangeCounts(),
        recentSessionCount: Int = 1,
        recentSucceededCount: Int = 0,
        recentFailedCount: Int = 0,
        recentCommitCount: Int = 0,
        lastTerminalStatus: SessionStatus? = nil,
        successStreak: Int = 0,
        failureStreak: Int = 0,
        recoveredFromFailure: Bool = false
    ) -> RepositoryActivityProfile {
        RepositoryActivityProfile(
            isAvailable: true,
            worktreeChanges: worktreeChanges,
            recentSessionCount: recentSessionCount,
            recentSucceededCount: recentSucceededCount,
            recentFailedCount: recentFailedCount,
            recentCommitCount: recentCommitCount,
            lastTerminalStatus: lastTerminalStatus,
            lastSuccessfulSession: successStreak > 0 ? 1 : nil,
            lastFailedSession: failureStreak > 0 || recoveredFromFailure ? 0 : nil,
            successStreak: successStreak,
            failureStreak: failureStreak,
            recoveredFromFailure: recoveredFromFailure
        )
    }

    private static func worktreeChanges(
        added: Int = 0,
        modified: Int = 0,
        deleted: Int = 0,
        renamed: Int = 0,
        untracked: Int = 0,
        conflicted: Int = 0,
        other: Int = 0
    ) -> RepositoryWorktreeChangeCounts {
        var changes = RepositoryWorktreeChangeCounts()
        changes.added = added
        changes.modified = modified
        changes.deleted = deleted
        changes.renamed = renamed
        changes.untracked = untracked
        changes.conflicted = conflicted
        changes.other = other
        return changes
    }

    private static func loopPhase(from phase: String) -> LoopPhase {
        if let loopPhase = LoopPhase(rawValue: phase) {
            return loopPhase
        }

        let lowercased = phase.lowercased()
        if lowercased.contains("develop") {
            return .developing
        }
        if lowercased.contains("verify") || lowercased.contains("commit") {
            return .verifying
        }
        if lowercased.contains("recover") || lowercased.contains("repair") || lowercased.contains("fail") {
            return .failed
        }
        if lowercased.contains("plan") {
            return .planning
        }
        if lowercased.contains("pause") {
            return .paused
        }
        if lowercased.contains("cancel") {
            return .cancelled
        }
        return .idle
    }

    private static func settingsIdentifier(_ settings: CinematicInfluenceSettings) -> String {
        "\(settings.cameraStyle.rawValue)|\(fixed(settings.intensity))|\(settings.comfortMode.rawValue)"
    }

    private static func positionIdentifier(_ position: SIMD3<Float>) -> String {
        [
            fixed(Double(position.x)),
            fixed(Double(position.y)),
            fixed(Double(position.z))
        ].joined(separator: ",")
    }

    private static func fixed(_ value: Float) -> String {
        fixed(Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

private extension SpellSchool {
    var diagnosticsIdentifier: String {
        switch self {
        case .scan:
            return "scan"
        case .shell:
            return "shell"
        case .edit:
            return "edit"
        case .git:
            return "git"
        case .verify:
            return "verify"
        case .insight:
            return "insight"
        case .lifecycle:
            return "lifecycle"
        case .pressure:
            return "pressure"
        case .failure:
            return "failure"
        }
    }
}
