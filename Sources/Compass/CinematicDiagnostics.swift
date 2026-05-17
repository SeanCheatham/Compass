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
        var backdropTextureName: String
        var arenaTextureName: String
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
        return CinematicVisualSmokeReport(reports: reports)
    }

    private static func makeChecks(reports: [CinematicDiagnosticsReport]) -> [Check] {
        [
            narrativeCueReadabilityCheck(reports: reports),
            overlayFallbackUsageCheck(reports: reports),
            chromeStrengthCheck(reports: reports),
            textBoundsCheck(reports: reports),
            assetAvailabilityCheck(reports: reports),
            cameraPhaseCoverageCheck(reports: reports),
            pressureInfluenceSpreadCheck(reports: reports)
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
        let textureVariants = Set(reports.map(\.setDressing.materialTextureVariantIdentifier))
        let architectureCount = Set(reports.map(\.setDressing.languageArchitectureIdentifier)).count
        let markerCount = Set(reports.map(\.setDressing.activityMarkerIdentifier)).count
        let isPassing = !reports.isEmpty && availableCount == reports.count

        return check(
            id: "asset-availability",
            label: "Asset availability",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.asset-availability",
            detail: [
                "assets \(availableCount)/\(reports.count)",
                "texture variants \(textureVariants.count)",
                "architecture \(architectureCount)",
                "markers \(markerCount)"
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
        [
            report.setDressing.identifier,
            report.setDressing.languageArchitectureIdentifier,
            report.setDressing.activityMarkerIdentifier,
            report.setDressing.runeIntensityIdentifier,
            report.setDressing.animationCadenceIdentifier,
            report.setDressing.materialTextureVariantIdentifier,
            report.setDressing.backdropTextureName,
            report.setDressing.arenaTextureName
        ]
        .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    static let maxRows = 32
    static let labelMaxCharacters = 32
    static let detailMaxCharacters = 512

    var rows: [Row]
    var sections: [Section]
    var visualSmoke: CinematicVisualSmokeReport
    var exportText: String

    struct Row: Identifiable, Equatable {
        var id: String
        var label: String
        var detail: String
    }

    struct Section: Identifiable, Equatable {
        var id: String
        var label: String
        var rows: [Row]

        var rowCountLabel: String {
            rows.count == 1 ? "1 row" : "\(rows.count) rows"
        }
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
            rowIDs: ["repository", "immediate"]
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

    init(report: CinematicDiagnosticsReport, visualSmoke: CinematicVisualSmokeReport = .representative()) {
        let rows = Self.makeRows(report: report)
        self.rows = Array(rows.prefix(Self.maxRows))
        sections = Self.makeSections(rows: self.rows)
        self.visualSmoke = visualSmoke
        exportText = Self.makeExportText(report: report, sections: sections, visualSmoke: visualSmoke)
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
            row(id: "world-quest", label: "World quest", detail: report.worldText.questLabel),
            row(id: "world-arena", label: "World arena", detail: report.worldText.arenaCallout),
            row(id: "world-activity", label: "World activity", detail: report.worldText.activityCallout),
            row(
                id: "set-dressing",
                label: "Set dressing",
                detail: [
                    report.setDressing.languageArchitectureIdentifier,
                    report.setDressing.activityMarkerIdentifier,
                    "runes \(report.setDressing.runeIntensityIdentifier)",
                    "cadence \(report.setDressing.animationCadenceIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "textures",
                label: "Textures",
                detail: [
                    report.setDressing.materialTextureVariantIdentifier,
                    report.setDressing.backdropTextureName,
                    report.setDressing.arenaTextureName
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
                rows: sectionRows
            )
        }

        let unmatchedRows = rows.filter { !matchedRowIDs.contains($0.id) }
        if !unmatchedRows.isEmpty {
            sections.append(
                Section(
                    id: "other",
                    label: bounded("Other", limit: labelMaxCharacters),
                    rows: unmatchedRows
                )
            )
        }

        return sections
    }

    private static func makeExportText(
        report: CinematicDiagnosticsReport,
        sections: [Section],
        visualSmoke: CinematicVisualSmokeReport
    ) -> String {
        var lines = [
            "Cinematic Diagnostics",
            "Report: \(bounded(report.identifier, limit: detailMaxCharacters))"
        ]

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

        return lines.joined(separator: "\n")
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
        [
            narrativeCueDescriptorDetail("quest", snapshot.questPlaque),
            narrativeCueDescriptorDetail("arena", snapshot.arenaInscription),
            narrativeCueDescriptorDetail("activity", snapshot.activityBanner)
        ].joined(separator: " | ")
    }

    private static func narrativeLayoutDetail(_ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot) -> String {
        [
            narrativeCueLayoutDescriptorDetail("quest", snapshot.questPlaque.layout),
            narrativeCueLayoutDescriptorDetail("arena", snapshot.arenaInscription.layout),
            narrativeCueLayoutDescriptorDetail("activity", snapshot.activityBanner.layout)
        ].joined(separator: " | ")
    }

    private static func overlayDisplayDetail(_ snapshot: CinematicDiagnosticsReport.OverlayDisplaySnapshot) -> String {
        [
            "mode \(snapshot.modeIdentifier)",
            "reason \(snapshot.reasonIdentifier)",
            "pills \(snapshot.visiblePillIdentifiers.isEmpty ? "none" : snapshot.visiblePillIdentifiers.joined(separator: ","))",
            "hud \(snapshot.hudProminenceIdentifier)",
            "chrome \(snapshot.chromeStyleIdentifier)",
            "gradient \(fixed(snapshot.gradientStrength))",
            "width \(fixed(snapshot.worldTextMaxWidth))/\(fixed(snapshot.hudMaxWidth))",
            "lines \(snapshot.pillLineLimit)/\(snapshot.hudTitleLineLimit)/\(snapshot.hudDetailLineLimit)/\(snapshot.hudProfileLineLimit)/\(snapshot.hudStatusLineLimit)",
            "opacity \(fixed(snapshot.overlayOpacity))"
        ].joined(separator: " | ")
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
            "scale \(fixed(descriptor.scale))",
            "opacity \(fixed(descriptor.opacity))",
            "cadence \(fixed(descriptor.cadence))s",
            "\"\(descriptor.text)\""
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
    static func currentReport(for project: CompassProject) -> CinematicDiagnosticsReport {
        report(
            repoName: project.displayName,
            phase: (project.isPaused ? LoopPhase.paused : project.phase).rawValue,
            immediateTitle: project.immediateTitle,
            completedCount: project.state.completed.count,
            latestEvent: project.liveLog.last.map(CinematicBriefingEvent.init(line:)),
            languageProfile: project.languageProfile,
            activityProfile: project.activityProfile,
            influenceSettings: project.cinematicInfluenceSettings,
            isRunning: project.isRunning,
            isAutoPlaying: project.isAutoPlaying,
            isPaused: project.isPaused,
            hasRepository: project.hasRepository
        )
    }

    static func report(
        repoName: String,
        phase: String,
        immediateTitle: String,
        completedCount: Int,
        latestEvent: CinematicBriefingEvent?,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        isRunning: Bool = true,
        isAutoPlaying: Bool = false,
        isPaused: Bool = false,
        hasRepository: Bool = true
    ) -> CinematicDiagnosticsReport {
        let languageMotif = CinematicMotif.language(for: languageProfile)
        let activityMotif = CinematicMotif.activity(for: activityProfile)
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent
            )
        )
        let worldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent,
                languageProfile: languageProfile,
                activityProfile: activityProfile
            )
        )
        let influenceIdentifier = settingsIdentifier(influenceSettings)
        let languageSnapshot = languageSnapshot(for: languageMotif)
        let activitySnapshot = activitySnapshot(for: activityMotif)
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
            influenceSettings: influenceSettings
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
            influenceSettings: influenceSettings
        )
        let narrativeCuePlan = CinematicSceneNarrativeCuePlanner.plan(
            worldText: worldText,
            briefing: briefing,
            stageBeat: stageBeat,
            stagePhasePolishPlan: stagePhasePolishPlan,
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            influenceSettings: influenceSettings
        )
        let stageBeatSnapshot = stageBeatSnapshot(for: stageBeat)
        let stageEffectSnapshot = stageEffectSnapshot(for: stageEffectPlan)
        let stageAtmosphereSnapshot = stageAtmosphereSnapshot(for: stageAtmospherePlan)
        let stagePhasePolishSnapshot = stagePhasePolishSnapshot(for: stagePhasePolishPlan)
        let narrativeCueSnapshot = narrativeCueSnapshot(for: narrativeCuePlan)
        let narrativeCueReadability = CinematicNarrativeCueReadabilitySignals(plan: narrativeCuePlan)
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
            narrativeCueReadability: narrativeCueReadability
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
        let cameraSnapshots = CinematicCameraShot.allCases.map {
            cameraSnapshot(for: $0, settings: influenceSettings)
        }

        return CinematicDiagnosticsReport(
            identifier: [
                "repo:\(repoName)",
                "phase:\(phase)",
                "language:\(languageSnapshot.identifier)",
                "activity:\(activitySnapshot.identifier)",
                "stage:\(stageBeatSnapshot.identifier)",
                "stage-effect:\(stageEffectSnapshot.identifier)",
                "stage-atmosphere:\(stageAtmosphereSnapshot.identifier)",
                "phase-polish:\(stagePhasePolishSnapshot.identifier)",
                "narrative-cues:\(narrativeCueSnapshot.identifier)",
                "overlay:\(overlayDisplaySnapshot.identifier)",
                "influence:\(influenceIdentifier)",
                "set-dressing:\(setDressingSnapshot.identifier)"
            ].joined(separator: "|"),
            repoName: repoName,
            phase: phase,
            immediateTitle: immediateTitle,
            completedCount: completedCount,
            influenceIdentifier: influenceIdentifier,
            languageMotif: languageSnapshot,
            activityMotif: activitySnapshot,
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
            cameraSnapshots: cameraSnapshots
        )
    }

    static func representativeSmokeMatrix(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        RepositoryLanguage.allCases.flatMap { language in
            representativeActivityCases().map { activityCase in
                report(
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
                    hasRepository: activityCase.hasRepository
                )
            }
        }
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
            "rings:\(ringIdentifiers.joined(separator: ","))",
            "pulses:\(phaseLightPulseIdentifiers.joined(separator: ","))",
            "sparks:\(sparkBurstIdentifiers.joined(separator: ","))",
            "history:\(historyTrailIdentifiers.joined(separator: ","))",
            "victory:\(victoryCadenceIdentifier ?? "none")",
            "camera:\(cameraShakeIdentifiers.joined(separator: ","))",
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
            "influence:\(plan.influenceIdentifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.NarrativeCueSnapshot(
            identifier: identifier,
            stageBeatIdentifier: plan.stageBeatIdentifier,
            stagePhasePolishIdentifier: plan.stagePhasePolishIdentifier,
            languageIdentifier: plan.languageIdentifier,
            activityIdentifier: plan.activityIdentifier,
            influenceIdentifier: plan.influenceIdentifier,
            questPlaque: quest,
            arenaInscription: arena,
            activityBanner: activity
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
            narrativeCueReadabilityIdentifier: plan.narrativeCueReadabilityIdentifier
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
            backdropTextureName: plan.materialTextureVariants.backdropTextureName,
            arenaTextureName: plan.materialTextureVariants.arenaTextureName
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
        "\(settings.cameraStyle.rawValue)|\(fixed(settings.intensity))"
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
