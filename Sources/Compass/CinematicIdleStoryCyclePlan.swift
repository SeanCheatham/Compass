import Foundation

struct CinematicIdleStoryCyclePlan: Equatable {
    typealias NativeFeedbackPlaqueDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor

    static let identifierMaxCharacters = 320
    static let phaseCopyMaxCharacters = 96
    static let sourceDescriptorMaxCharacters = 160
    static let cadenceRange: ClosedRange<TimeInterval> = 4.5...18
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
    var phaseCopy: String { descriptor?.phaseCopy ?? "" }

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
            case runRecapFocus = "run-recap-focus"
            case runRecapEndCard = "run-recap-end-card"
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
        var commitConstellationFocusPlan: CinematicCommitConstellationPlan.FocusPlan?
        var timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan?
        var nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?
        var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan?
        var runRecapEndCardPlan: CinematicRunRecapEndCardPlan?

        var phaseIdentifier: String { phase.rawValue }
        var cameraShotIdentifier: String { cameraShot.identifier }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var arenaEffectIdentifier: String { arenaEffect.rawValue }
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
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?,
        runRecapPlan: CinematicRunRecapPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
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
            commitConstellationPlan: commitConstellationPlan,
            timelineSceneFocusPlan: timelineSceneFocusPlan,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackPlaqueDescriptor: nativeFeedbackPlaqueDescriptor,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan,
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
            return .inactive(reason: "no-descriptors")
        }

        let cycleSlot = Int(floor(session.elapsedTime / max(0.1, boundedCadence)))
        let selectedIndex = (cycleSlot + session.sessionOrdinal) % candidates.count
        return activePlan(
            candidate: candidates[selectedIndex],
            phaseIndex: selectedIndex,
            cycleSlot: cycleSlot,
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
        var cadence: TimeInterval
        var cameraTreatmentIdentifier: String
        var anchorTreatmentIdentifier: String
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
        var phaseCopy: String
        var isPriority: Bool = false
        var commitConstellationFocusPlan: CinematicCommitConstellationPlan.FocusPlan?
        var timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan?
        var nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?
        var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan?
        var runRecapEndCardPlan: CinematicRunRecapEndCardPlan?
    }

    private static func candidates(
        influenceSettings: CinematicInfluenceSettings,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        nativeFeedbackPlaqueDescriptor: NativeFeedbackPlaqueDescriptor?,
        runRecapPlan: CinematicRunRecapPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        cadence: TimeInterval
    ) -> [Candidate] {
        [
            commitConstellationCandidate(
                commitConstellationPlan: commitConstellationPlan,
                cadence: cadence
            ),
            timelineFocusCandidate(
                timelineSceneFocusPlan: timelineSceneFocusPlan,
                cadence: cadence
            ),
            nativeFeedbackPlaqueCandidate(
                nativeFeedbackCue: nativeFeedbackCue,
                plaqueDescriptor: nativeFeedbackPlaqueDescriptor,
                influenceSettings: influenceSettings,
                cadence: cadence
            ),
            runRecapFocusCandidate(
                runRecapPlan: runRecapPlan,
                runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                cadence: cadence
            ),
            runRecapEndCardCandidate(
                runRecapEndCardPlan: runRecapEndCardPlan,
                cadence: cadence
            )
        ].compactMap { $0 }
    }

    private static func commitConstellationCandidate(
        commitConstellationPlan: CinematicCommitConstellationPlan,
        cadence: TimeInterval
    ) -> Candidate? {
        guard !commitConstellationPlan.isEmpty else { return nil }
        let focusPlan = commitConstellationPlan.focusPlan
        guard !focusPlan.isFallback else { return nil }
        let copy = commitConstellationPlan.newestSubject ?? "Recent commit constellation"

        return Candidate(
            phase: .commitConstellation,
            sourceDescriptorIdentifier: focusPlan.identifier,
            targetKindIdentifier: "commit-constellation",
            cadence: cadence,
            cameraTreatmentIdentifier: "shot:\(focusPlan.shot.identifier)",
            anchorTreatmentIdentifier: "look:\(positionIdentifier(focusPlan.lookTarget))",
            cameraShot: focusPlan.shot,
            lookTarget: focusPlan.lookTarget,
            lightFamily: .git,
            arenaEffect: .historyChains,
            phaseLightIntensity: 740,
            phaseCopy: copy,
            commitConstellationFocusPlan: focusPlan
        )
    }

    private static func timelineFocusCandidate(
        timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let descriptor = timelineSceneFocusPlan.descriptor else { return nil }

        return Candidate(
            phase: .timelineFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: "timeline-\(descriptor.kindIdentifier)",
            cadence: cadence,
            cameraTreatmentIdentifier: "shot:\(descriptor.cameraShotIdentifier)",
            anchorTreatmentIdentifier: "look:\(positionIdentifier(descriptor.lookTarget))",
            cameraShot: descriptor.cameraShot,
            lookTarget: descriptor.lookTarget,
            lightFamily: descriptor.lightFamily,
            arenaEffect: descriptor.arenaEffect,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            phaseCopy: descriptor.label,
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

        return Candidate(
            phase: .nativeFeedbackPlaque,
            sourceDescriptorIdentifier: plaqueDescriptor.identifier,
            targetKindIdentifier: "native-feedback-\(nativeFeedbackCue.styleIdentifier)",
            cadence: cadence,
            cameraTreatmentIdentifier: "shot:\(nativeFeedbackCameraShot(for: nativeFeedbackCue).identifier)",
            anchorTreatmentIdentifier: "anchor:\(plaqueDescriptor.anchorIdentifier)",
            cameraShot: nativeFeedbackCameraShot(for: nativeFeedbackCue),
            lookTarget: plaqueDescriptor.layout.anchorPosition,
            lightFamily: plaqueDescriptor.lightFamily,
            arenaEffect: nativeFeedbackArenaEffect(for: nativeFeedbackCue),
            phaseLightIntensity: nativeFeedbackPhaseLightIntensity(for: nativeFeedbackCue),
            phaseCopy: nativeFeedbackCue.title,
            isPriority: nativeFeedbackCue.isCriticalCinematicBanner,
            nativeFeedbackPlaqueDescriptor: plaqueDescriptor
        )
    }

    private static func runRecapFocusCandidate(
        runRecapPlan: CinematicRunRecapPlan,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan,
        cadence: TimeInterval
    ) -> Candidate? {
        guard runRecapPlan.isAvailable,
              let descriptor = runRecapSceneFocusPlan.descriptor else {
            return nil
        }

        return Candidate(
            phase: .runRecapFocus,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: "run-recap-\(descriptor.terminalStyleIdentifier)",
            cadence: cadence,
            cameraTreatmentIdentifier: "shot:\(descriptor.cameraShotIdentifier)",
            anchorTreatmentIdentifier: "look:\(positionIdentifier(descriptor.lookTarget))",
            cameraShot: descriptor.cameraShot,
            lookTarget: descriptor.lookTarget,
            lightFamily: descriptor.lightFamily,
            arenaEffect: descriptor.arenaEffect,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            phaseCopy: runRecapPlan.title,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan
        )
    }

    private static func runRecapEndCardCandidate(
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan,
        cadence: TimeInterval
    ) -> Candidate? {
        guard let descriptor = runRecapEndCardPlan.descriptor else { return nil }
        let cameraShot = runRecapEndCardCameraShot(for: descriptor)

        return Candidate(
            phase: .runRecapEndCard,
            sourceDescriptorIdentifier: descriptor.identifier,
            targetKindIdentifier: "run-recap-end-card-\(descriptor.styleIdentifier)",
            cadence: cadence,
            cameraTreatmentIdentifier: "shot:\(cameraShot.identifier)",
            anchorTreatmentIdentifier: "anchor:\(descriptor.anchorIdentifier)",
            cameraShot: cameraShot,
            lookTarget: descriptor.layout.anchorPosition,
            lightFamily: descriptor.lightFamily,
            arenaEffect: runRecapEndCardArenaEffect(for: descriptor),
            phaseLightIntensity: runRecapEndCardPhaseLightIntensity(for: descriptor),
            phaseCopy: descriptor.title,
            runRecapEndCardPlan: runRecapEndCardPlan
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
                "cadence:\(fixed(candidate.cadence))",
                "camera:\(candidate.cameraTreatmentIdentifier)",
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
            cadence: candidate.cadence,
            cameraTreatmentIdentifier: candidate.cameraTreatmentIdentifier,
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
            commitConstellationFocusPlan: candidate.commitConstellationFocusPlan,
            timelineSceneFocusPlan: candidate.timelineSceneFocusPlan,
            nativeFeedbackPlaqueDescriptor: candidate.nativeFeedbackPlaqueDescriptor,
            runRecapSceneFocusPlan: candidate.runRecapSceneFocusPlan,
            runRecapEndCardPlan: candidate.runRecapEndCardPlan
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

    private static func phaseOrder(
        _ phase: CinematicIdleStoryCyclePlan.Descriptor.Phase
    ) -> Int {
        CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.firstIndex(of: phase) ?? 0
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
