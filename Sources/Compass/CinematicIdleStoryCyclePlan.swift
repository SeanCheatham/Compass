import Foundation

struct CinematicIdleStoryCyclePlan: Equatable {
    typealias NativeFeedbackPlaqueDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor

    static let identifierMaxCharacters = 320
    static let phaseCopyMaxCharacters = 96
    static let sourceDescriptorMaxCharacters = 160
    static let choreographyIdentifierMaxCharacters = 220
    static let choreographyTreatmentIdentifierMaxCharacters = 120
    static let choreographyHintIdentifierMaxCharacters = 96
    static let cadenceRange: ClosedRange<TimeInterval> = 4.5...18
    static let dwellDurationRange: ClosedRange<TimeInterval> = 1.8...15
    static let transitionDurationScaleRange: ClosedRange<Double> = 0.62...1.72
    static let targetBiasRange: ClosedRange<Float> = 0.42...0.9
    static let comfortDampingRange: ClosedRange<Float> = 0.32...1
    static let pulseIntensityScaleRange: ClosedRange<Float> = 0.88...1.2
    static let pulseOrbBoostRange: ClosedRange<Float> = 0...0.28
    static let shakeHintScaleRange: ClosedRange<Float> = 0.04...1.1
    static let shakeHintDurationRange: ClosedRange<TimeInterval> = 0.08...0.34
    static let defaultCadence: TimeInterval = 7.2

    static let none = inactive(reason: "none")

    var identifier: String
    var descriptor: Descriptor?
    var suppressionReason: String

    var isActive: Bool { descriptor != nil }
    var phaseIdentifier: String { descriptor?.phaseIdentifier ?? "none" }
    var sourceDescriptorIdentifier: String { descriptor?.sourceDescriptorIdentifier ?? "none" }
    var targetKindIdentifier: String { descriptor?.targetKindIdentifier ?? "none" }
    var cadence: TimeInterval { descriptor?.cadence ?? 0 }
    var cameraTreatmentIdentifier: String { descriptor?.cameraTreatmentIdentifier ?? "none" }
    var anchorTreatmentIdentifier: String { descriptor?.anchorTreatmentIdentifier ?? "none" }
    var choreographyIdentifier: String { descriptor?.choreography.identifier ?? "none" }
    var dwellDuration: TimeInterval { descriptor?.choreography.dwellDuration ?? 0 }
    var transitionDurationScale: Double { descriptor?.choreography.transitionDurationScale ?? 0 }
    var cameraPressureIdentifier: String { descriptor?.choreography.cameraPressureIdentifier ?? "none" }
    var targetBias: Float { descriptor?.choreography.targetBias ?? 0 }
    var comfortDamping: Float { descriptor?.choreography.comfortDamping ?? 0 }
    var shakeHintIdentifier: String { descriptor?.choreography.shakeHintIdentifier ?? "none" }
    var pulseHintIdentifier: String { descriptor?.choreography.pulseHintIdentifier ?? "none" }
    var phaseCopy: String { descriptor?.phaseCopy ?? "" }
    var diagnosticsWarningBundleIdentifier: String {
        descriptor?.diagnosticsWarningPulseDescriptor?.bundleIdentifier ?? "none"
    }
    var diagnosticsWarningIdentifiers: [String] {
        descriptor?.diagnosticsWarningPulseDescriptor?.warningIdentifiers ?? []
    }
    var diagnosticsWarningTargetAnchors: [String] {
        descriptor?.diagnosticsWarningPulseDescriptor?.targetAnchors ?? []
    }

    struct SessionInput: Equatable {
        static let elapsedTimeRange: ClosedRange<TimeInterval> = 0...(24 * 60 * 60)
        static let sessionOrdinalRange: ClosedRange<Int> = 0...10_000

        var elapsedTime: TimeInterval
        var sessionOrdinal: Int

        init(elapsedTime: TimeInterval = 0, sessionOrdinal: Int = 0) {
            let finiteElapsed = elapsedTime.isFinite ? elapsedTime : 0
            let boundedElapsed = max(0, finiteElapsed)
                .truncatingRemainder(dividingBy: Self.elapsedTimeRange.upperBound)
            self.elapsedTime = min(
                max(boundedElapsed, Self.elapsedTimeRange.lowerBound),
                Self.elapsedTimeRange.upperBound
            )
            self.sessionOrdinal = min(
                max(sessionOrdinal, Self.sessionOrdinalRange.lowerBound),
                Self.sessionOrdinalRange.upperBound
            )
        }
    }

    struct Descriptor: Equatable {
        enum Phase: String, CaseIterable, Equatable {
            case commitConstellation = "commit-constellation"
            case timelineFocus = "timeline-focus"
            case nativeFeedbackPlaque = "native-feedback-plaque"
            case diagnosticsWarningPulse = "diagnostics-warning-pulse"
            case planCompassFocus = "plan-compass-focus"
            case runRecapFocus = "run-recap-focus"
            case runRecapEndCard = "run-recap-end-card"
            case savedRecapArtifactTour = "saved-recap-artifact-tour"
            case activitySourceBeacon = "activity-source-beacon"
        }

        var identifier: String
        var phase: Phase
        var phaseIndex: Int
        var cycleSlot: Int
        var sourceDescriptorIdentifier: String
        var targetKindIdentifier: String
        var cadence: TimeInterval
        var cameraTreatmentIdentifier: String
        var anchorTreatmentIdentifier: String
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
        var phaseCopy: String
        var choreography: Choreography
        var commitConstellationFocusPlan: CinematicCommitConstellationPlan.FocusPlan?
        var timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan?
        var planCompassSceneFocusPlan: CinematicPlanCompassSceneFocusPlan?
        var nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?
        var diagnosticsWarningPulseDescriptor: DiagnosticsWarningPulseDescriptor?
        var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan?
        var runRecapEndCardPlan: CinematicRunRecapEndCardPlan?
        var runRecapShareArtifactTourPlan: CinematicRunRecapShareArtifactTourPlan?
        var activitySourceBeaconDescriptor: CinematicActivitySourceBeaconPlan.Descriptor?

        var phaseIdentifier: String { phase.rawValue }
        var cameraShotIdentifier: String { cameraShot.identifier }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var arenaEffectIdentifier: String { arenaEffect.rawValue }
    }

    struct Choreography: Equatable {
        var identifier: String
        var phaseCadence: TimeInterval
        var dwellDuration: TimeInterval
        var transitionDurationScale: Double
        var cameraTreatmentIdentifier: String
        var cameraPressureIdentifier: String
        var targetBias: Float
        var comfortDamping: Float
        var shakeHint: ShakeHint?
        var pulseHint: PulseHint?

        var shakeHintIdentifier: String { shakeHint?.identifier ?? "none" }
        var pulseHintIdentifier: String { pulseHint?.identifier ?? "none" }
    }

    struct DiagnosticsWarningPulseDescriptor: Equatable {
        var identifier: String
        var bundleIdentifier: String
        var sequence: Int
        var captureCount: Int
        var targetCount: Int
        var warningCount: Int
        var targetIdentifiers: [String]
        var warningIdentifiers: [String]
        var repeatedWarningIdentifiers: [String]
        var targetAnchors: [String]
        var relatedRowAnchors: [String]
    }

    struct ShakeHint: Equatable {
        var identifier: String
        var duration: TimeInterval
        var scale: Float
    }

    struct PulseHint: Equatable {
        var identifier: String
        var duration: TimeInterval
        var intensityScale: Float
        var orbBoost: Float
    }

    fileprivate init(
        identifier: String,
        descriptor: Descriptor?,
        suppressionReason: String
    ) {
        self.identifier = identifier
        self.descriptor = descriptor
        self.suppressionReason = suppressionReason
    }

    static func inactive(reason: String) -> CinematicIdleStoryCyclePlan {
        let boundedReason = bounded(reason, limit: 80)
        return CinematicIdleStoryCyclePlan(
            identifier: bounded(
                "idle-story-cycle.none|reason:\(boundedReason)",
                limit: identifierMaxCharacters
            ),
            descriptor: nil,
            suppressionReason: boundedReason
        )
    }

    fileprivate static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }
}

enum CinematicIdleStoryCyclePlanner {
    typealias NativeFeedbackPlaqueDescriptor = CinematicIdleStoryCyclePlan.NativeFeedbackPlaqueDescriptor

    static func plan(
        session: CinematicIdleStoryCyclePlan.SessionInput,
        isLiveFollowActive: Bool,
        hasExplicitUserFocus: Bool,
        influenceSettings: CinematicInfluenceSettings,
        activitySourceBeaconPlan: CinematicActivitySourceBeaconPlan = .hidden,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        planCompassSceneFocusPlan: CinematicPlanCompassSceneFocusPlan = .none,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?,
        diagnosticsWarningBundleHistory: CinematicDiagnosticsWarningBundleHistory = CinematicDiagnosticsWarningBundleHistory(),
        runRecapPlan: CinematicRunRecapPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        runRecapShareArtifactTourPlan: CinematicRunRecapShareArtifactTourPlan? = nil,
        cadence: TimeInterval = CinematicIdleStoryCyclePlan.defaultCadence
    ) -> CinematicIdleStoryCyclePlan {
        if isLiveFollowActive {
            return .inactive(reason: "live-follow")
        }
        if hasExplicitUserFocus {
            return .inactive(reason: "user-focus")
        }

        let boundedCadence = clamp(cadence, to: CinematicIdleStoryCyclePlan.cadenceRange)
        let candidates = candidates(
            influenceSettings: influenceSettings,
            activitySourceBeaconPlan: activitySourceBeaconPlan,
            commitConstellationPlan: commitConstellationPlan,
            timelineSceneFocusPlan: timelineSceneFocusPlan,
            planCompassSceneFocusPlan: planCompassSceneFocusPlan,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackPlaqueDescriptor: nativeFeedbackPlaqueDescriptor,
            diagnosticsWarningBundle: diagnosticsWarningBundleHistory.currentUnresolvedBundle,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan,
            runRecapShareArtifactTourPlan: runRecapShareArtifactTourPlan,
            cadence: boundedCadence
        )

        if let priorityCandidate = candidates.first(where: \.isPriority) {
            return activePlan(
                candidate: priorityCandidate,
                phaseIndex: phaseOrder(priorityCandidate.phase),
                cycleSlot: 0,
                session: session
            )
        }

        guard !candidates.isEmpty else {
            if let nativeFeedbackCue,
               influenceSettings.comfortMode == .quiet,
               !nativeFeedbackCue.isCriticalCinematicBanner {
                return .inactive(reason: "quiet-noncritical-native-feedback")
            }
            if activitySourceBeaconPlan.suppressionReason == "quiet-noncritical" {
                return .inactive(reason: "quiet-noncritical-activity-source")
            }
            return .inactive(reason: "no-descriptors")
        }

        let selection = selectedCandidate(candidates, session: session)
        return activePlan(
            candidate: selection.candidate,
            phaseIndex: selection.phaseIndex,
            cycleSlot: selection.cycleSlot,
            session: session
        )
    }

    static func nativeFeedbackPlaqueDescriptor(
        phase: LoopPhase,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        recoveryCuePlan: CinematicRecoveryCuePlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
    ) -> NativeFeedbackPlaqueDescriptor? {
        guard let nativeFeedbackCue else { return nil }

        let languageMotif = CinematicMotif.language(for: languageProfile)
        let activityMotif = CinematicMotif.activity(for: activityProfile)
        let stageBeat = CinematicStageBeatPlanner.plan(
            phase: phase,
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
        let atmospherePlan = CinematicStageAtmospherePlanner.plan(
            beat: stageBeat,
            setDressingPlan: setDressingPlan,
            stageEffectTuning: stageEffectPlan.tuningMetadata,
            influenceSettings: influenceSettings
        )
        let phasePolishPlan = CinematicStagePhasePolishPlanner.plan(
            beat: stageBeat,
            stageEffectTuning: stageEffectPlan.tuningMetadata,
            atmospherePlan: atmospherePlan,
            activityMotif: activityMotif,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
        )
        let narrativePlan = CinematicSceneNarrativeCuePlanner.plan(
            worldText: worldText,
            briefing: briefing,
            stageBeat: stageBeat,
            stagePhasePolishPlan: phasePolishPlan,
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nativeFeedbackCue
        )

        return narrativePlan.questPlaque
    }

    static func hasLiveFollowTarget(lines: [LiveLine]) -> Bool {
        lines.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private struct Candidate {
        var phase: CinematicIdleStoryCyclePlan.Descriptor.Phase
        var sourceDescriptorIdentifier: String
        var targetKindIdentifier: String
        var anchorTreatmentIdentifier: String
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
        var phaseCopy: String
        var choreography: CinematicIdleStoryCyclePlan.Choreography
        var isPriority: Bool = false
        var commitConstellationFocusPlan: CinematicCommitConstellationPlan.FocusPlan?
        var timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan?
        var planCompassSceneFocusPlan: CinematicPlanCompassSceneFocusPlan?
        var nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?
        var diagnosticsWarningPulseDescriptor: CinematicIdleStoryCyclePlan.DiagnosticsWarningPulseDescriptor?
        var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan?
        var runRecapEndCardPlan: CinematicRunRecapEndCardPlan?
        var runRecapShareArtifactTourPlan: CinematicRunRecapShareArtifactTourPlan?
        var activitySourceBeaconDescriptor: CinematicActivitySourceBeaconPlan.Descriptor?
    }

    private static func candidates(
        influenceSettings: CinematicInfluenceSettings,
        activitySourceBeaconPlan: CinematicActivitySourceBeaconPlan,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        planCompassSceneFocusPlan: CinematicPlanCompassSceneFocusPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?,
        diagnosticsWarningBundle: CinematicDiagnosticsWarningBundleHistory.Entry?,
        runRecapPlan: CinematicRunRecapPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        runRecapShareArtifactTourPlan: CinematicRunRecapShareArtifactTourPlan?,
        cadence: TimeInterval
    ) -> [Candidate] {
        [
            commitConstellationCandidate(
                commitConstellationPlan: commitConstellationPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            timelineFocusCandidate(
                timelineSceneFocusPlan: timelineSceneFocusPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            nativeFeedbackPlaqueCandidate(
                nativeFeedbackCue: nativeFeedbackCue,
                plaqueDescriptor: nativeFeedbackPlaqueDescriptor,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            diagnosticsWarningPulseCandidate(
                bundle: diagnosticsWarningBundle,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            planCompassFocusCandidate(
                planCompassSceneFocusPlan: planCompassSceneFocusPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            runRecapFocusCandidate(
                runRecapPlan: runRecapPlan,
                runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            runRecapEndCardCandidate(
                runRecapEndCardPlan: runRecapEndCardPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            savedRecapArtifactTourCandidate(
                tourPlan: runRecapShareArtifactTourPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            activitySourceBeaconCandidate(
                beaconPlan: activitySourceBeaconPlan,
                influenceSettings: influenceSettings,
                cadence: cadence
            )
        ].compactMap { $0 }
    }

    private static func commitConstellationCandidate(
        commitConstellationPlan: CinematicCommitConstellationPlan,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard !commitConstellationPlan.isEmpty else { return nil }
        let focusPlan = commitConstellationPlan.focusPlan
        guard !focusPlan.isFallback else { return nil }
        let copy = commitConstellationPlan.newestSubject ?? "Recent commit constellation"
        let targetKindIdentifier = "commit-constellation"
        let choreography = choreography(
            phase: .commitConstellation,
            sourceDescriptorIdentifier: focusPlan.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: focusPlan.shot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: 1.38,
            dwellScale: 1.22,
            transitionDurationScale: 1.24,
            cameraPressureIdentifier: "expansive",
            targetBias: 0.68,
            pulseDuration: 0.74,
            pulseIntensityScale: 1.04,
            pulseOrbBoost: 0.08
        )

        return Candidate(
            phase: .commitConstellation,
            sourceDescriptorIdentifier: focusPlan.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "look:\(positionIdentifier(focusPlan.lookTarget))",
            cameraShot: focusPlan.shot,
            lookTarget: focusPlan.lookTarget,
            lightFamily: .git,
            arenaEffect: .historyChains,
            phaseLightIntensity: 740,
            phaseCopy: copy,
            choreography: choreography,
            commitConstellationFocusPlan: focusPlan
        )
    }

    private static func timelineFocusCandidate(
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let descriptor = timelineSceneFocusPlan.descriptor else { return nil }
        let targetKindIdentifier = "timeline-\(descriptor.kindIdentifier)"
        let choreography = choreography(
            phase: .timelineFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: descriptor.cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: 0.86,
            dwellScale: 0.68,
            transitionDurationScale: 0.82,
            cameraPressureIdentifier: "tight",
            targetBias: 0.84,
            pulseDuration: 0.46,
            pulseIntensityScale: 1.08,
            pulseOrbBoost: 0.12,
            shakeScale: descriptor.lightFamily == .failure ? 0.42 : nil
        )

        return Candidate(
            phase: .timelineFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "look:\(positionIdentifier(descriptor.lookTarget))",
            cameraShot: descriptor.cameraShot,
            lookTarget: descriptor.lookTarget,
            lightFamily: descriptor.lightFamily,
            arenaEffect: descriptor.arenaEffect,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            phaseCopy: descriptor.label,
            choreography: choreography,
            timelineSceneFocusPlan: timelineSceneFocusPlan
        )
    }

    private static func nativeFeedbackPlaqueCandidate(
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        plaqueDescriptor: NativeFeedbackPlaqueDescriptor?,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let nativeFeedbackCue, let plaqueDescriptor else { return nil }
        guard influenceSettings.comfortMode != .quiet || nativeFeedbackCue.isCriticalCinematicBanner else {
            return nil
        }
        let cameraShot = nativeFeedbackCameraShot(for: nativeFeedbackCue)
        let targetKindIdentifier = "native-feedback-\(nativeFeedbackCue.styleIdentifier)"
        let isCritical = nativeFeedbackCue.isCriticalCinematicBanner
        let choreography = choreography(
            phase: .nativeFeedbackPlaque,
            sourceDescriptorIdentifier: plaqueDescriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: isCritical ? 0.68 : 0.78,
            dwellScale: isCritical ? 0.6 : 0.66,
            transitionDurationScale: isCritical ? 0.68 : 0.76,
            cameraPressureIdentifier: isCritical ? "critical-plaque" : "plaque",
            targetBias: isCritical ? 0.9 : 0.86,
            pulseDuration: isCritical ? 0.38 : 0.44,
            pulseIntensityScale: isCritical ? 1.16 : 1.1,
            pulseOrbBoost: isCritical ? 0.18 : 0.12,
            shakeScale: (isCritical || nativeFeedbackCue.style == .failure) ? 0.82 : nil
        )

        return Candidate(
            phase: .nativeFeedbackPlaque,
            sourceDescriptorIdentifier: plaqueDescriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "anchor:\(plaqueDescriptor.anchorIdentifier)",
            cameraShot: cameraShot,
            lookTarget: plaqueDescriptor.layout.anchorPosition,
            lightFamily: plaqueDescriptor.lightFamily,
            arenaEffect: nativeFeedbackArenaEffect(for: nativeFeedbackCue),
            phaseLightIntensity: nativeFeedbackPhaseLightIntensity(for: nativeFeedbackCue),
            phaseCopy: nativeFeedbackCue.title,
            choreography: choreography,
            isPriority: nativeFeedbackCue.isCriticalCinematicBanner,
            nativeFeedbackPlaqueDescriptor: plaqueDescriptor
        )
    }

    private static func diagnosticsWarningPulseCandidate(
        bundle: CinematicDiagnosticsWarningBundleHistory.Entry?,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let bundle else { return nil }

        let warningDescriptor = diagnosticsWarningPulseDescriptor(for: bundle)
        let isHighPressure = warningDescriptor.warningCount > 1
            || warningDescriptor.targetCount > 1
            || !warningDescriptor.repeatedWarningIdentifiers.isEmpty
        let targetKindIdentifier = bounded(
            "diagnostics-warning-\(warningDescriptor.bundleIdentifier)",
            limit: CinematicIdleStoryCyclePlan.choreographyTreatmentIdentifierMaxCharacters
        )
        let cameraShot = diagnosticsWarningCameraShot(for: warningDescriptor)
        let choreography = choreography(
            phase: .diagnosticsWarningPulse,
            sourceDescriptorIdentifier: warningDescriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: isHighPressure ? 0.74 : 0.82,
            dwellScale: isHighPressure ? 0.62 : 0.7,
            transitionDurationScale: isHighPressure ? 0.72 : 0.78,
            cameraPressureIdentifier: isHighPressure ? "diagnostics-warning-hot" : "diagnostics-warning",
            targetBias: isHighPressure ? 0.89 : 0.86,
            pulseDuration: isHighPressure ? 0.4 : 0.46,
            pulseIntensityScale: isHighPressure ? 1.14 : 1.1,
            pulseOrbBoost: isHighPressure ? 0.16 : 0.12,
            shakeScale: isHighPressure ? 0.36 : nil
        )

        return Candidate(
            phase: .diagnosticsWarningPulse,
            sourceDescriptorIdentifier: warningDescriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "anchor:\(warningDescriptor.targetAnchors.first ?? warningDescriptor.bundleIdentifier)",
            cameraShot: cameraShot,
            lookTarget: diagnosticsWarningLookTarget(for: warningDescriptor),
            lightFamily: .pressure,
            arenaEffect: .activityPulse,
            phaseLightIntensity: isHighPressure ? 740 : 700,
            phaseCopy: diagnosticsWarningPulseCopy(for: warningDescriptor),
            choreography: choreography,
            diagnosticsWarningPulseDescriptor: warningDescriptor
        )
    }

    private static func planCompassFocusCandidate(
        planCompassSceneFocusPlan: CinematicPlanCompassSceneFocusPlan,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let descriptor = planCompassSceneFocusPlan.descriptor else { return nil }

        let targetKindIdentifier = "plan-compass-\(descriptor.selectedSectionRouteIdentifier)-\(descriptor.selectedSectionStateIdentifier)"
        let isEmpty = descriptor.selectedSectionIsEmpty
        let choreography = choreography(
            phase: .planCompassFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: descriptor.cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: isEmpty ? 1.16 : 1.04,
            dwellScale: isEmpty ? 1.02 : 0.96,
            transitionDurationScale: isEmpty ? 1.08 : 1.0,
            cameraPressureIdentifier: isEmpty ? "plan-compass-empty" : "plan-compass-focus",
            targetBias: isEmpty ? 0.72 : 0.78,
            pulseDuration: 0.62,
            pulseIntensityScale: isEmpty ? 1.02 : 1.06,
            pulseOrbBoost: isEmpty ? 0.05 : 0.09
        )

        return Candidate(
            phase: .planCompassFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "route:\(descriptor.selectedSectionRouteIdentifier)",
            cameraShot: descriptor.cameraShot,
            lookTarget: descriptor.lookTarget,
            lightFamily: descriptor.lightFamily,
            arenaEffect: descriptor.arenaEffect,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            phaseCopy: descriptor.plaqueTitle,
            choreography: choreography,
            planCompassSceneFocusPlan: planCompassSceneFocusPlan
        )
    }

    private static func runRecapFocusCandidate(
        runRecapPlan: CinematicRunRecapPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard runRecapPlan.isAvailable,
              let descriptor = runRecapSceneFocusPlan.descriptor else {
            return nil
        }
        let targetKindIdentifier = "run-recap-\(descriptor.terminalStyleIdentifier)"
        let choreography = choreography(
            phase: .runRecapFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: descriptor.cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: 1.18,
            dwellScale: 1.08,
            transitionDurationScale: 1.08,
            cameraPressureIdentifier: "recap-review",
            targetBias: 0.74,
            pulseDuration: 0.68,
            pulseIntensityScale: 1.05,
            pulseOrbBoost: 0.08,
            shakeScale: descriptor.lightFamily == .failure ? 0.58 : nil
        )

        return Candidate(
            phase: .runRecapFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "look:\(positionIdentifier(descriptor.lookTarget))",
            cameraShot: descriptor.cameraShot,
            lookTarget: descriptor.lookTarget,
            lightFamily: descriptor.lightFamily,
            arenaEffect: descriptor.arenaEffect,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            phaseCopy: runRecapPlan.title,
            choreography: choreography,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan
        )
    }

    private static func runRecapEndCardCandidate(
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let descriptor = runRecapEndCardPlan.descriptor else { return nil }
        let cameraShot = runRecapEndCardCameraShot(for: descriptor)
        let targetKindIdentifier = "run-recap-end-card-\(descriptor.styleIdentifier)"
        let choreography = choreography(
            phase: .runRecapEndCard,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: 1.48,
            dwellScale: 1.32,
            transitionDurationScale: 1.22,
            cameraPressureIdentifier: "end-card-hold",
            targetBias: 0.66,
            pulseDuration: 0.88,
            pulseIntensityScale: 1.07,
            pulseOrbBoost: 0.1,
            shakeScale: descriptor.lightFamily == .failure ? 0.7 : nil
        )

        return Candidate(
            phase: .runRecapEndCard,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "anchor:\(descriptor.anchorIdentifier)",
            cameraShot: cameraShot,
            lookTarget: descriptor.layout.anchorPosition,
            lightFamily: descriptor.lightFamily,
            arenaEffect: runRecapEndCardArenaEffect(for: descriptor),
            phaseLightIntensity: runRecapEndCardPhaseLightIntensity(for: descriptor),
            phaseCopy: descriptor.title,
            choreography: choreography,
            runRecapEndCardPlan: runRecapEndCardPlan
        )
    }

    private static func savedRecapArtifactTourCandidate(
        tourPlan: CinematicRunRecapShareArtifactTourPlan?,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let tourPlan, tourPlan.shouldDisplay else { return nil }
        let targetKindIdentifier = "saved-recap-artifact-\(tourPlan.stateIdentifier)"
        let cameraShot = savedRecapArtifactTourCameraShot(for: tourPlan)
        let lookTarget = savedRecapArtifactTourLookTarget(for: tourPlan)
        let choreography = choreography(
            phase: .savedRecapArtifactTour,
            sourceDescriptorIdentifier: tourPlan.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: 1.28,
            dwellScale: 1.18,
            transitionDurationScale: 1.14,
            cameraPressureIdentifier: "archive-tour",
            targetBias: 0.7,
            pulseDuration: 0.72,
            pulseIntensityScale: tourPlan.hasWarnings ? 1.1 : 1.04,
            pulseOrbBoost: tourPlan.hasWarnings ? 0.12 : 0.08,
            shakeScale: tourPlan.hasWarnings ? 0.28 : nil
        )

        return Candidate(
            phase: .savedRecapArtifactTour,
            sourceDescriptorIdentifier: tourPlan.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "anchor:saved-recap-artifact-archive",
            cameraShot: cameraShot,
            lookTarget: lookTarget,
            lightFamily: savedRecapArtifactTourLightFamily(for: tourPlan),
            arenaEffect: savedRecapArtifactTourArenaEffect(for: tourPlan),
            phaseLightIntensity: savedRecapArtifactTourPhaseLightIntensity(for: tourPlan),
            phaseCopy: tourPlan.titleSnippet,
            choreography: choreography,
            runRecapShareArtifactTourPlan: tourPlan
        )
    }

    private static func activitySourceBeaconCandidate(
        beaconPlan: CinematicActivitySourceBeaconPlan,
        influenceSettings: CinematicInfluenceSettings,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let descriptor = beaconPlan.descriptor else { return nil }
        guard influenceSettings.comfortMode != .quiet || !descriptor.isQuietModeSuppressible else {
            return nil
        }

        let targetKindIdentifier = bounded(
            "activity-source-beacon-\(descriptor.kindIdentifier)-\(descriptor.availabilityIdentifier)",
            limit: CinematicIdleStoryCyclePlan.choreographyTreatmentIdentifierMaxCharacters
        )
        let isCritical = descriptor.isCritical
        let choreography = choreography(
            phase: .activitySourceBeacon,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            cameraShot: descriptor.cameraShot,
            influenceSettings: influenceSettings,
            baseCadence: cadence,
            cadenceScale: isCritical ? 0.9 : 1.12,
            dwellScale: isCritical ? 0.78 : 0.88,
            transitionDurationScale: isCritical ? 0.84 : 0.98,
            cameraPressureIdentifier: isCritical ? "activity-source-warning" : "activity-source-beacon",
            targetBias: isCritical ? 0.86 : 0.78,
            pulseDuration: isCritical ? 0.52 : 0.64,
            pulseIntensityScale: isCritical ? 1.12 : 1.04,
            pulseOrbBoost: isCritical ? 0.14 : 0.08,
            shakeScale: descriptor.severityIdentifier == "failure" ? 0.38 : nil
        )

        return Candidate(
            phase: .activitySourceBeacon,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: targetKindIdentifier,
            anchorTreatmentIdentifier: "entity:\(descriptor.entityNamePrefix)",
            cameraShot: descriptor.cameraShot,
            lookTarget: descriptor.lookTarget,
            lightFamily: descriptor.lightFamily,
            arenaEffect: descriptor.arenaEffect,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            phaseCopy: descriptor.label,
            choreography: choreography,
            activitySourceBeaconDescriptor: descriptor
        )
    }

    private static func activePlan(
        candidate: Candidate,
        phaseIndex: Int,
        cycleSlot: Int,
        session: CinematicIdleStoryCyclePlan.SessionInput
    ) -> CinematicIdleStoryCyclePlan {
        let descriptorIdentifier = bounded(
            [
                "idle-story-cycle",
                "phase:\(candidate.phase.rawValue)",
                "slot:\(cycleSlot)",
                "source:\(fingerprint(candidate.sourceDescriptorIdentifier))",
                "target:\(candidate.targetKindIdentifier)",
                "cadence:\(fixed(candidate.choreography.phaseCadence))",
                "dwell:\(fixed(candidate.choreography.dwellDuration))",
                "transition:\(fixed(candidate.choreography.transitionDurationScale))",
                "camera:\(candidate.choreography.cameraTreatmentIdentifier)",
                "pressure:\(candidate.choreography.cameraPressureIdentifier)",
                "bias:\(fixed(candidate.choreography.targetBias))",
                "damping:\(fixed(candidate.choreography.comfortDamping))",
                "anchor:\(candidate.anchorTreatmentIdentifier)",
                "light:\(candidate.lightFamily.rawValue)",
                "effect:\(candidate.arenaEffect.rawValue)",
                "phase-light:\(fixed(candidate.phaseLightIntensity))",
                "copy:\(fingerprint(candidate.phaseCopy))",
                "session:\(session.sessionOrdinal)"
            ].joined(separator: "|"),
            limit: CinematicIdleStoryCyclePlan.identifierMaxCharacters
        )
        let descriptor = CinematicIdleStoryCyclePlan.Descriptor(
            identifier: descriptorIdentifier,
            phase: candidate.phase,
            phaseIndex: phaseIndex,
            cycleSlot: cycleSlot,
            sourceDescriptorIdentifier: bounded(
                candidate.sourceDescriptorIdentifier,
                limit: CinematicIdleStoryCyclePlan.sourceDescriptorMaxCharacters
            ),
            targetKindIdentifier: candidate.targetKindIdentifier,
            cadence: candidate.choreography.phaseCadence,
            cameraTreatmentIdentifier: candidate.choreography.cameraTreatmentIdentifier,
            anchorTreatmentIdentifier: candidate.anchorTreatmentIdentifier,
            cameraShot: candidate.cameraShot,
            lookTarget: candidate.lookTarget,
            lightFamily: candidate.lightFamily,
            arenaEffect: candidate.arenaEffect,
            phaseLightIntensity: clamp(
                candidate.phaseLightIntensity,
                to: CinematicRecoveryCuePlan.phaseLightIntensityRange
            ),
            phaseCopy: bounded(
                candidate.phaseCopy,
                limit: CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters
            ),
            choreography: candidate.choreography,
            commitConstellationFocusPlan: candidate.commitConstellationFocusPlan,
            timelineSceneFocusPlan: candidate.timelineSceneFocusPlan,
            planCompassSceneFocusPlan: candidate.planCompassSceneFocusPlan,
            nativeFeedbackPlaqueDescriptor: candidate.nativeFeedbackPlaqueDescriptor,
            diagnosticsWarningPulseDescriptor: candidate.diagnosticsWarningPulseDescriptor,
            runRecapSceneFocusPlan: candidate.runRecapSceneFocusPlan,
            runRecapEndCardPlan: candidate.runRecapEndCardPlan,
            runRecapShareArtifactTourPlan: candidate.runRecapShareArtifactTourPlan,
            activitySourceBeaconDescriptor: candidate.activitySourceBeaconDescriptor
        )

        return CinematicIdleStoryCyclePlan(
            identifier: bounded(
                [
                    "idle-story-cycle.active",
                    "descriptor:\(descriptor.identifier)"
                ].joined(separator: "|"),
                limit: CinematicIdleStoryCyclePlan.identifierMaxCharacters
            ),
            descriptor: descriptor,
            suppressionReason: "none"
        )
    }

    private static func selectedCandidate(
        _ candidates: [Candidate],
        session: CinematicIdleStoryCyclePlan.SessionInput
    ) -> (candidate: Candidate, phaseIndex: Int, cycleSlot: Int) {
        let count = max(candidates.count, 1)
        let ordinalOffset = session.sessionOrdinal % count
        let orderedIndices = (0..<count).map { ($0 + ordinalOffset) % count }
        let durations = orderedIndices.map {
            clamp(candidates[$0].choreography.phaseCadence, to: CinematicIdleStoryCyclePlan.cadenceRange)
        }
        let cycleDuration = max(0.1, durations.reduce(0, +))
        let elapsedInCycle = session.elapsedTime.truncatingRemainder(dividingBy: cycleDuration)
        let cycleSlot = Int(floor(session.elapsedTime / cycleDuration))
        var elapsedCursor: TimeInterval = 0

        for (orderIndex, candidateIndex) in orderedIndices.enumerated() {
            let duration = durations[orderIndex]
            if elapsedInCycle < elapsedCursor + duration || orderIndex == orderedIndices.count - 1 {
                let candidate = candidates[candidateIndex]
                return (
                    candidate: candidate,
                    phaseIndex: phaseOrder(candidate.phase),
                    cycleSlot: cycleSlot
                )
            }
            elapsedCursor += duration
        }

        let fallback = candidates[0]
        return (
            candidate: fallback,
            phaseIndex: phaseOrder(fallback.phase),
            cycleSlot: cycleSlot
        )
    }

    private static func choreography(
        phase: CinematicIdleStoryCyclePlan.Descriptor.Phase,
        sourceDescriptorIdentifier: String,
        targetKindIdentifier: String,
        cameraShot: CinematicCameraShot,
        influenceSettings: CinematicInfluenceSettings,
        baseCadence: TimeInterval,
        cadenceScale: Double,
        dwellScale: Double,
        transitionDurationScale: Double,
        cameraPressureIdentifier: String,
        targetBias: Float,
        pulseDuration: TimeInterval?,
        pulseIntensityScale: Float?,
        pulseOrbBoost: Float,
        shakeScale: Float? = nil
    ) -> CinematicIdleStoryCyclePlan.Choreography {
        let comfortDamping = comfortDamping(settings: influenceSettings)
        let phaseCadence = clamp(
            baseCadence
                * cadenceScale
                * styleCadenceScale(settings: influenceSettings)
                * (1 + Double(1 - comfortDamping) * 0.12),
            to: CinematicIdleStoryCyclePlan.cadenceRange
        )
        let dwellCeiling = max(
            CinematicIdleStoryCyclePlan.dwellDurationRange.lowerBound,
            phaseCadence * 0.92
        )
        let dwellDuration = min(
            clamp(
                baseCadence
                    * dwellScale
                    * (1 + Double(1 - comfortDamping) * 0.16),
                to: CinematicIdleStoryCyclePlan.dwellDurationRange
            ),
            dwellCeiling
        )
        let transitionScale = clamp(
            transitionDurationScale
                * styleTransitionScale(settings: influenceSettings)
                * comfortTransitionScale(settings: influenceSettings),
            to: CinematicIdleStoryCyclePlan.transitionDurationScaleRange
        )
        let biasedTarget = clamp(
            targetBias + styleTargetBiasOffset(settings: influenceSettings) - (1 - comfortDamping) * 0.08,
            to: CinematicIdleStoryCyclePlan.targetBiasRange
        )
        let boundedPressure = bounded(
            cameraPressureIdentifier,
            limit: CinematicIdleStoryCyclePlan.choreographyTreatmentIdentifierMaxCharacters
        )
        let cameraTreatmentIdentifier = bounded(
            [
                "shot:\(cameraShot.identifier)",
                "pressure:\(boundedPressure)",
                "style:\(influenceSettings.cameraStyle.rawValue)",
                "comfort:\(influenceSettings.comfortMode.rawValue)"
            ].joined(separator: "/"),
            limit: CinematicIdleStoryCyclePlan.choreographyTreatmentIdentifierMaxCharacters
        )
        let pulseHint = pulseHint(
            phase: phase,
            duration: pulseDuration,
            intensityScale: pulseIntensityScale,
            orbBoost: pulseOrbBoost,
            comfortDamping: comfortDamping
        )
        let shakeHint = shakeHint(
            phase: phase,
            scale: shakeScale,
            influenceSettings: influenceSettings,
            comfortDamping: comfortDamping
        )
        let identifier = bounded(
            [
                "choreo:\(phase.rawValue)",
                "route:\(fingerprint(sourceDescriptorIdentifier))",
                "target:\(fingerprint(targetKindIdentifier))",
                "cadence:\(fixed(phaseCadence))",
                "dwell:\(fixed(dwellDuration))",
                "transition:\(fixed(transitionScale))",
                "camera:\(cameraTreatmentIdentifier)",
                "bias:\(fixed(biasedTarget))",
                "damping:\(fixed(comfortDamping))",
                "shake:\(shakeHint?.identifier ?? "none")",
                "pulse:\(pulseHint?.identifier ?? "none")"
            ].joined(separator: "|"),
            limit: CinematicIdleStoryCyclePlan.choreographyIdentifierMaxCharacters
        )

        return CinematicIdleStoryCyclePlan.Choreography(
            identifier: identifier,
            phaseCadence: phaseCadence,
            dwellDuration: dwellDuration,
            transitionDurationScale: transitionScale,
            cameraTreatmentIdentifier: cameraTreatmentIdentifier,
            cameraPressureIdentifier: boundedPressure,
            targetBias: biasedTarget,
            comfortDamping: comfortDamping,
            shakeHint: shakeHint,
            pulseHint: pulseHint
        )
    }

    private static func pulseHint(
        phase: CinematicIdleStoryCyclePlan.Descriptor.Phase,
        duration: TimeInterval?,
        intensityScale: Float?,
        orbBoost: Float,
        comfortDamping: Float
    ) -> CinematicIdleStoryCyclePlan.PulseHint? {
        guard let duration, let intensityScale else { return nil }
        let boundedDuration = clamp(
            duration * Double(0.76 + comfortDamping * 0.24),
            to: 0.2...1.1
        )
        let boundedIntensityScale = clamp(
            1 + (intensityScale - 1) * comfortDamping,
            to: CinematicIdleStoryCyclePlan.pulseIntensityScaleRange
        )
        let boundedOrbBoost = clamp(
            orbBoost * comfortDamping,
            to: CinematicIdleStoryCyclePlan.pulseOrbBoostRange
        )
        let identifier = bounded(
            [
                "pulse",
                phase.rawValue,
                "d\(fixed(boundedDuration))",
                "i\(fixed(boundedIntensityScale))",
                "o\(fixed(boundedOrbBoost))"
            ].joined(separator: "/"),
            limit: CinematicIdleStoryCyclePlan.choreographyHintIdentifierMaxCharacters
        )
        return CinematicIdleStoryCyclePlan.PulseHint(
            identifier: identifier,
            duration: boundedDuration,
            intensityScale: boundedIntensityScale,
            orbBoost: boundedOrbBoost
        )
    }

    private static func shakeHint(
        phase: CinematicIdleStoryCyclePlan.Descriptor.Phase,
        scale: Float?,
        influenceSettings: CinematicInfluenceSettings,
        comfortDamping: Float
    ) -> CinematicIdleStoryCyclePlan.ShakeHint? {
        guard let scale else { return nil }
        let boundedScale = clamp(
            scale * comfortDamping * styleShakeScale(settings: influenceSettings),
            to: CinematicIdleStoryCyclePlan.shakeHintScaleRange
        )
        let boundedDuration = clamp(
            0.22 * Double(0.72 + comfortDamping * 0.28),
            to: CinematicIdleStoryCyclePlan.shakeHintDurationRange
        )
        let identifier = bounded(
            [
                "shake",
                phase.rawValue,
                "d\(fixed(boundedDuration))",
                "s\(fixed(boundedScale))"
            ].joined(separator: "/"),
            limit: CinematicIdleStoryCyclePlan.choreographyHintIdentifierMaxCharacters
        )
        return CinematicIdleStoryCyclePlan.ShakeHint(
            identifier: identifier,
            duration: boundedDuration,
            scale: boundedScale
        )
    }

    private static func comfortDamping(settings: CinematicInfluenceSettings) -> Float {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 0.72
        case .quiet:
            return 0.48
        }
    }

    private static func comfortTransitionScale(settings: CinematicInfluenceSettings) -> Double {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 1.12
        case .quiet:
            return 1.28
        }
    }

    private static func styleCadenceScale(settings: CinematicInfluenceSettings) -> Double {
        let intensity = CinematicInfluenceSettings.clampedIntensity(settings.intensity)
        switch settings.cameraStyle {
        case .steady:
            return 1.08 + (1 - intensity) * 0.04
        case .follow:
            return 1
        case .dramatic:
            return 0.96 - intensity * 0.04
        }
    }

    private static func styleTransitionScale(settings: CinematicInfluenceSettings) -> Double {
        let intensity = CinematicInfluenceSettings.clampedIntensity(settings.intensity)
        switch settings.cameraStyle {
        case .steady:
            return 1.1 + (1 - intensity) * 0.04
        case .follow:
            return 1
        case .dramatic:
            return 0.94 - intensity * 0.04
        }
    }

    private static func styleTargetBiasOffset(settings: CinematicInfluenceSettings) -> Float {
        let intensity = Float(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        switch settings.cameraStyle {
        case .steady:
            return -0.035 - (1 - intensity) * 0.015
        case .follow:
            return 0
        case .dramatic:
            return 0.025 + intensity * 0.025
        }
    }

    private static func styleShakeScale(settings: CinematicInfluenceSettings) -> Float {
        let intensity = Float(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        switch settings.cameraStyle {
        case .steady:
            return 0.72 + intensity * 0.08
        case .follow:
            return 1
        case .dramatic:
            return 1.08 + intensity * 0.12
        }
    }

    private static func nativeFeedbackCameraShot(
        for cue: CinematicNativeFeedbackCuePlan
    ) -> CinematicCameraShot {
        if cue.milestone == .verifyStarted {
            return .overhead
        }
        switch cue.style {
        case .failure:
            return .failure
        case .warning:
            return .castPrep
        case .success:
            return .victory
        case .plan, .develop, .verify:
            return .wide
        case .paused, .idle:
            return .home
        }
    }

    private static func nativeFeedbackArenaEffect(
        for cue: CinematicNativeFeedbackCuePlan
    ) -> CinematicStageArenaEffect {
        if cue.milestone == .verifyStarted {
            return .seal
        }
        switch cue.style {
        case .failure:
            return .charge
        case .warning:
            return .activityPulse
        case .success:
            return .victory
        case .plan, .develop, .verify:
            return .charge
        case .paused, .idle:
            return .none
        }
    }

    private static func nativeFeedbackPhaseLightIntensity(
        for cue: CinematicNativeFeedbackCuePlan
    ) -> Float {
        if cue.milestone == .verifyStarted {
            return 760
        }
        switch cue.style {
        case .failure:
            return 900
        case .warning:
            return 720
        case .success:
            return 780
        case .plan:
            return 520
        case .develop:
            return 680
        case .verify:
            return 760
        case .paused, .idle:
            return 420
        }
    }

    private static func diagnosticsWarningPulseDescriptor(
        for entry: CinematicDiagnosticsWarningBundleHistory.Entry
    ) -> CinematicIdleStoryCyclePlan.DiagnosticsWarningPulseDescriptor {
        let targetIdentifiers = boundedIdentifiers(
            entry.targetIdentifiers,
            limit: CinematicDiagnosticsWarningBundleHistory.visibleAnchorLimit
        )
        let warningIdentifiers = boundedIdentifiers(
            entry.warningIdentifiers,
            limit: CinematicDiagnosticsWarningBundleHistory.visibleWarningIdentifierLimit
        )
        let repeatedWarningIdentifiers = boundedIdentifiers(
            entry.repeatedWarningIdentifiers,
            limit: CinematicDiagnosticsWarningBundleHistory.visibleWarningIdentifierLimit
        )
        let targetAnchors = boundedIdentifiers(
            entry.targetAnchors,
            limit: CinematicDiagnosticsWarningBundleHistory.visibleAnchorLimit
        )
        let relatedRowAnchors = boundedIdentifiers(
            entry.relatedRowAnchors,
            limit: CinematicDiagnosticsWarningBundleHistory.visibleAnchorLimit
        )
        let identifier = bounded(
            [
                "diagnostics-warning-pulse",
                "bundle:\(entry.bundleIdentifier)",
                "sequence:\(entry.sequence)",
                "captures:\(entry.captureCount)",
                "targets:\(entry.targetCount)",
                "warnings:\(entry.warningCount)",
                "warning-ids:\(fingerprint(warningIdentifiers.joined(separator: ",")))",
                "target-anchors:\(fingerprint(targetAnchors.joined(separator: ",")))"
            ].joined(separator: "|"),
            limit: CinematicIdleStoryCyclePlan.sourceDescriptorMaxCharacters
        )

        return CinematicIdleStoryCyclePlan.DiagnosticsWarningPulseDescriptor(
            identifier: identifier,
            bundleIdentifier: bounded(
                entry.bundleIdentifier,
                limit: CinematicDiagnosticsWarningBundleHistory.identifierMaxCharacters
            ),
            sequence: entry.sequence,
            captureCount: entry.captureCount,
            targetCount: entry.targetCount,
            warningCount: entry.warningCount,
            targetIdentifiers: targetIdentifiers,
            warningIdentifiers: warningIdentifiers,
            repeatedWarningIdentifiers: repeatedWarningIdentifiers,
            targetAnchors: targetAnchors,
            relatedRowAnchors: relatedRowAnchors
        )
    }

    private static func diagnosticsWarningCameraShot(
        for descriptor: CinematicIdleStoryCyclePlan.DiagnosticsWarningPulseDescriptor
    ) -> CinematicCameraShot {
        if descriptor.warningCount >= 3 || !descriptor.repeatedWarningIdentifiers.isEmpty {
            return .wide
        }
        return descriptor.targetCount > 1 ? .overhead : .castPrep
    }

    private static func diagnosticsWarningLookTarget(
        for descriptor: CinematicIdleStoryCyclePlan.DiagnosticsWarningPulseDescriptor
    ) -> SIMD3<Float> {
        let warningOffset = Float(min(descriptor.warningCount, 5)) * 0.08
        let targetOffset = Float(min(descriptor.targetCount, 4)) * 0.05
        return [-0.74 - targetOffset, 1.12 + warningOffset, 1.34]
    }

    private static func diagnosticsWarningPulseCopy(
        for descriptor: CinematicIdleStoryCyclePlan.DiagnosticsWarningPulseDescriptor
    ) -> String {
        let warningCopy = descriptor.warningCount == 1 ? "1 warning" : "\(descriptor.warningCount) warnings"
        let targetCopy = descriptor.targetCount == 1 ? "1 target" : "\(descriptor.targetCount) targets"
        return bounded(
            "Diagnostics warning pulse: \(warningCopy) across \(targetCopy)",
            limit: CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters
        )
    }

    private static func runRecapEndCardCameraShot(
        for descriptor: CinematicRunRecapEndCardPlan.Descriptor
    ) -> CinematicCameraShot {
        switch descriptor.styleIdentifier {
        case CinematicRunRecapPlan.Style.success.rawValue:
            return .victory
        case CinematicRunRecapPlan.Style.failure.rawValue:
            return .failure
        case CinematicRunRecapPlan.Style.warning.rawValue:
            return .wide
        default:
            return .home
        }
    }

    private static func runRecapEndCardArenaEffect(
        for descriptor: CinematicRunRecapEndCardPlan.Descriptor
    ) -> CinematicStageArenaEffect {
        switch descriptor.styleIdentifier {
        case CinematicRunRecapPlan.Style.success.rawValue:
            return .victory
        case CinematicRunRecapPlan.Style.failure.rawValue:
            return .charge
        case CinematicRunRecapPlan.Style.warning.rawValue:
            return .activityPulse
        default:
            return .none
        }
    }

    private static func runRecapEndCardPhaseLightIntensity(
        for descriptor: CinematicRunRecapEndCardPlan.Descriptor
    ) -> Float {
        switch descriptor.styleIdentifier {
        case CinematicRunRecapPlan.Style.success.rawValue:
            return 820
        case CinematicRunRecapPlan.Style.failure.rawValue:
            return 900
        case CinematicRunRecapPlan.Style.warning.rawValue:
            return 680
        default:
            return 420
        }
    }

    private static func savedRecapArtifactTourCameraShot(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> CinematicCameraShot {
        if tourPlan.stateIdentifier.contains("no-match")
            || tourPlan.stateIdentifier.contains("filtered-pin")
            || tourPlan.stateIdentifier.contains("filtered-hold") {
            return .overhead
        }
        if tourPlan.stateIdentifier.contains("missing-pin")
            || tourPlan.stateIdentifier.contains("missing-hold")
            || tourPlan.hasWarnings {
            return .wide
        }
        return .overShoulder
    }

    private static func savedRecapArtifactTourLookTarget(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> SIMD3<Float> {
        let sessionOffset = Float((tourPlan.sessionNumber ?? 0) % 5) * 0.12
        let pinOffset: Float
        switch tourPlan.selectionSourceIdentifier {
        case "held":
            pinOffset = -0.04
        case "pinned":
            pinOffset = -0.18
        default:
            pinOffset = 0.18
        }
        return [-1.62 + pinOffset, 1.18 + sessionOffset, 1.62]
    }

    private static func savedRecapArtifactTourLightFamily(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> CinematicStageLightFamily {
        if tourPlan.stateIdentifier.contains("missing-pin")
            || tourPlan.stateIdentifier.contains("missing-hold") {
            return .failure
        }
        if tourPlan.stateIdentifier.contains("filtered-pin")
            || tourPlan.stateIdentifier.contains("filtered-hold")
            || tourPlan.stateIdentifier.contains("no-match") {
            return .scan
        }
        if tourPlan.hasWarnings {
            return .pressure
        }
        if tourPlan.selectionSourceIdentifier == "held" {
            return .verify
        }
        if tourPlan.selectionSourceIdentifier == "pinned" {
            return .git
        }
        return .insight
    }

    private static func savedRecapArtifactTourArenaEffect(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> CinematicStageArenaEffect {
        if tourPlan.stateIdentifier.contains("missing-pin")
            || tourPlan.stateIdentifier.contains("missing-hold") {
            return .charge
        }
        if tourPlan.stateIdentifier.contains("filtered-pin")
            || tourPlan.stateIdentifier.contains("filtered-hold")
            || tourPlan.stateIdentifier.contains("no-match")
            || tourPlan.hasWarnings {
            return .activityPulse
        }
        if tourPlan.selectionSourceIdentifier == "held" {
            return .seal
        }
        return tourPlan.selectionSourceIdentifier == "pinned" ? .historyChains : .seal
    }

    private static func savedRecapArtifactTourPhaseLightIntensity(
        for tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> Float {
        if tourPlan.stateIdentifier.contains("missing-pin")
            || tourPlan.stateIdentifier.contains("missing-hold") {
            return 720
        }
        if tourPlan.stateIdentifier.contains("filtered-pin")
            || tourPlan.stateIdentifier.contains("filtered-hold")
            || tourPlan.stateIdentifier.contains("no-match") {
            return 620
        }
        if tourPlan.hasWarnings {
            return 700
        }
        if tourPlan.selectionSourceIdentifier == "held" {
            return 720
        }
        return tourPlan.selectionSourceIdentifier == "pinned" ? 680 : 560
    }

    private static func phaseOrder(
        _ phase: CinematicIdleStoryCyclePlan.Descriptor.Phase
    ) -> Int {
        CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.firstIndex(of: phase) ?? 0
    }

    private static func boundedIdentifiers(_ values: [String], limit: Int) -> [String] {
        values.prefix(max(0, limit)).map {
            bounded($0, limit: CinematicDiagnosticsWarningBundleHistory.identifierMaxCharacters)
        }
    }

    private static func positionIdentifier(_ value: SIMD3<Float>) -> String {
        [
            fixed(value.x),
            fixed(value.y),
            fixed(value.z)
        ].joined(separator: ",")
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    private static func fixed(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        CinematicIdleStoryCyclePlan.bounded(text, limit: limit)
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
