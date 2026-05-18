import Foundation

struct CinematicTimelineSceneFocusPlan: Equatable {
    static let identifierMaxCharacters = 240
    static let labelMaxCharacters = 72
    static let targetXRange: ClosedRange<Float> = -7.8...7.8
    static let targetYRange: ClosedRange<Float> = 0.45...3.25
    static let targetZRange: ClosedRange<Float> = -6.35...2.4

    static let none = CinematicTimelineSceneFocusPlan(
        identifier: "timeline-focus.none",
        selectedBeatID: nil,
        descriptor: nil
    )

    var identifier: String
    var selectedBeatID: String?
    var descriptor: Descriptor?

    var isActive: Bool { descriptor != nil }
    var kindIdentifier: String { descriptor?.kind.rawValue ?? "none" }

    struct Descriptor: Equatable {
        enum Kind: String, Equatable {
            case plan
            case develop
            case verify
            case outcome
            case commit
            case recovery
            case failedVerify = "failed-verify"
        }

        var identifier: String
        var beatID: String
        var label: String
        var kind: Kind
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
        var commitNodeIdentifier: String?
        var recoveryTreatmentIdentifier: String?
        var recoveryVisualIdentifier: String?
        var usesFallbackTarget: Bool

        var kindIdentifier: String { kind.rawValue }
        var cameraShotIdentifier: String { cameraShot.identifier }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var arenaEffectIdentifier: String { arenaEffect.rawValue }
    }

    fileprivate init(
        identifier: String,
        selectedBeatID: String?,
        descriptor: Descriptor?
    ) {
        self.identifier = identifier
        self.selectedBeatID = selectedBeatID
        self.descriptor = descriptor
    }
}

enum CinematicTimelineSceneFocusPlanner {
    static func plan(
        selectedBeat beat: CinematicSessionTimelinePlan.Beat?,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        recoveryCuePlan: CinematicRecoveryCuePlan
    ) -> CinematicTimelineSceneFocusPlan {
        guard let beat else { return .none }

        let descriptor: CinematicTimelineSceneFocusPlan.Descriptor
        if beat.moment == .commit {
            descriptor = commitDescriptor(for: beat, commitConstellationPlan: commitConstellationPlan)
        } else if beat.hasAttention, let visualDescriptor = recoveryCuePlan.visualDescriptor {
            descriptor = recoveryFocusDescriptor(
                for: beat,
                visualDescriptor: visualDescriptor
            )
        } else if isFailedVerifyBeat(beat) {
            descriptor = failedVerifyDescriptor(for: beat)
        } else {
            descriptor = ordinaryDescriptor(for: beat)
        }

        return CinematicTimelineSceneFocusPlan(
            identifier: bounded(
                [
                    "timeline-focus",
                    "beat:\(beat.stableID)",
                    "descriptor:\(descriptor.identifier)"
                ].joined(separator: "|"),
                limit: CinematicTimelineSceneFocusPlan.identifierMaxCharacters
            ),
            selectedBeatID: beat.stableID,
            descriptor: descriptor
        )
    }

    static func representativePlan(
        activityCaseIdentifier: String,
        recoveryCuePlan: CinematicRecoveryCuePlan,
        commitConstellationPlan: CinematicCommitConstellationPlan
    ) -> CinematicTimelineSceneFocusPlan {
        if let selectedCue = recoveryCuePlan.selectedCue {
            return plan(
                selectedBeat: representativeRecoveryBeat(for: selectedCue),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        }

        switch activityCaseIdentifier {
        case "unavailable":
            return .none
        case "missing-repository":
            return plan(
                selectedBeat: representativeOrdinaryBeat(moment: .plan, sessionNumber: 50),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        case "commit":
            return plan(
                selectedBeat: representativeCommitBeat(commitConstellationPlan: commitConstellationPlan),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        case "failure":
            return plan(
                selectedBeat: representativeFailedVerifyBeat(sessionNumber: 57),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        case "success", "recovery":
            return plan(
                selectedBeat: representativeOrdinaryBeat(moment: .outcome, sessionNumber: 58, style: .success),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        case "dirty-heavy":
            return plan(
                selectedBeat: representativeOrdinaryBeat(moment: .verify, sessionNumber: 56, style: .success),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        default:
            return plan(
                selectedBeat: representativeOrdinaryBeat(moment: .develop, sessionNumber: 55),
                commitConstellationPlan: commitConstellationPlan,
                recoveryCuePlan: recoveryCuePlan
            )
        }
    }

    static func representativeCommitConstellationPlan() -> CinematicCommitConstellationPlan {
        CinematicCommitConstellationPlan(
            sessions: [
                SessionRecord(
                    session: 61,
                    startedAt: 61_000,
                    endedAt: 61_500,
                    plan: "Render representative commit constellation",
                    verify: nil,
                    beforeSha: nil,
                    afterSha: nil,
                    commits: [
                        SessionCommit(
                            sha: "4dd7f0c051af9876543210",
                            short: "4dd7f0c",
                            subject: "Stage timeline focus handoff"
                        ),
                        SessionCommit(
                            sha: "7ac15e9b2d340123456789",
                            short: "7ac15e9",
                            subject: "Add cinematic diagnostics smoke coverage"
                        )
                    ],
                    status: .succeeded,
                    notes: [],
                    verifyOutput: nil,
                    feedback: nil
                )
            ]
        )
    }

    private static func commitDescriptor(
        for beat: CinematicSessionTimelinePlan.Beat,
        commitConstellationPlan: CinematicCommitConstellationPlan
    ) -> CinematicTimelineSceneFocusPlan.Descriptor {
        let commitIdentifier = commitIdentifier(from: beat.stableID)
        let matchingNode = commitIdentifier.flatMap { identifier in
            commitConstellationPlan.nodes.first {
                $0.commitIdentifier == identifier || $0.stableID == "commit-node-\(identifier)"
            }
        }
        let fallbackFocus = commitConstellationPlan.focusPlan
        let target = boundedTarget(matchingNode?.position ?? fallbackFocus.lookTarget)
        let usesFallback = matchingNode == nil || fallbackFocus.isFallback
        let cameraShot = matchingNode == nil ? fallbackFocus.shot : .commitConstellation
        return descriptor(
            beat: beat,
            kind: .commit,
            cameraShot: cameraShot,
            lookTarget: target,
            lightFamily: .git,
            arenaEffect: .historyChains,
            phaseLightIntensity: 760,
            commitNodeIdentifier: matchingNode?.stableID,
            recoveryTreatmentIdentifier: nil,
            recoveryVisualIdentifier: nil,
            usesFallbackTarget: usesFallback,
            discriminator: [
                "commit",
                "node:\(matchingNode?.stableID ?? "fallback")",
                "target:\(positionIdentifier(target))",
                usesFallback ? "fallback" : "matched"
            ]
        )
    }

    private static func recoveryFocusDescriptor(
        for beat: CinematicSessionTimelinePlan.Beat,
        visualDescriptor: CinematicRecoveryCuePlan.VisualDescriptor
    ) -> CinematicTimelineSceneFocusPlan.Descriptor {
        descriptor(
            beat: beat,
            kind: .recovery,
            cameraShot: visualDescriptor.shouldShakeCamera ? .failure : .castPrep,
            lookTarget: target(for: visualDescriptor),
            lightFamily: visualDescriptor.lightFamily,
            arenaEffect: visualDescriptor.arenaEffect,
            phaseLightIntensity: visualDescriptor.phaseLightIntensity,
            commitNodeIdentifier: nil,
            recoveryTreatmentIdentifier: visualDescriptor.treatmentIdentifier,
            recoveryVisualIdentifier: visualDescriptor.identifier,
            usesFallbackTarget: false,
            discriminator: [
                "recovery",
                visualDescriptor.treatmentIdentifier,
                visualDescriptor.identifier
            ]
        )
    }

    private static func failedVerifyDescriptor(
        for beat: CinematicSessionTimelinePlan.Beat
    ) -> CinematicTimelineSceneFocusPlan.Descriptor {
        descriptor(
            beat: beat,
            kind: .failedVerify,
            cameraShot: .failure,
            lookTarget: boundedTarget([0, 1.36, -2.6]),
            lightFamily: .failure,
            arenaEffect: .charge,
            phaseLightIntensity: 900,
            commitNodeIdentifier: nil,
            recoveryTreatmentIdentifier: "verify-failure",
            recoveryVisualIdentifier: nil,
            usesFallbackTarget: false,
            discriminator: ["failed-verify", beat.style.rawValue]
        )
    }

    private static func ordinaryDescriptor(
        for beat: CinematicSessionTimelinePlan.Beat
    ) -> CinematicTimelineSceneFocusPlan.Descriptor {
        let mapping = ordinaryMapping(for: beat)
        return descriptor(
            beat: beat,
            kind: mapping.kind,
            cameraShot: mapping.cameraShot,
            lookTarget: mapping.lookTarget,
            lightFamily: mapping.lightFamily,
            arenaEffect: mapping.arenaEffect,
            phaseLightIntensity: mapping.phaseLightIntensity,
            commitNodeIdentifier: nil,
            recoveryTreatmentIdentifier: nil,
            recoveryVisualIdentifier: nil,
            usesFallbackTarget: false,
            discriminator: [
                "ordinary",
                mapping.kind.rawValue,
                beat.style.rawValue,
                mapping.cameraShot.identifier
            ]
        )
    }

    private struct OrdinaryMapping {
        var kind: CinematicTimelineSceneFocusPlan.Descriptor.Kind
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
    }

    private static func ordinaryMapping(for beat: CinematicSessionTimelinePlan.Beat) -> OrdinaryMapping {
        switch beat.moment {
        case .plan:
            return OrdinaryMapping(
                kind: .plan,
                cameraShot: .wide,
                lookTarget: boundedTarget([-2.35, 1.22, -2.05]),
                lightFamily: .scan,
                arenaEffect: .charge,
                phaseLightIntensity: 520
            )
        case .develop:
            return OrdinaryMapping(
                kind: .develop,
                cameraShot: .castPrep,
                lookTarget: boundedTarget([1.65, 1.24, -1.3]),
                lightFamily: .shell,
                arenaEffect: .charge,
                phaseLightIntensity: 680
            )
        case .verify:
            return OrdinaryMapping(
                kind: .verify,
                cameraShot: .overhead,
                lookTarget: boundedTarget([0, 0.72, -0.2]),
                lightFamily: .verify,
                arenaEffect: .seal,
                phaseLightIntensity: 760
            )
        case .outcome:
            return outcomeMapping(for: beat)
        case .commit:
            return OrdinaryMapping(
                kind: .commit,
                cameraShot: .commitConstellation,
                lookTarget: CinematicCommitConstellationPlan.fallbackFocusLookTarget,
                lightFamily: .git,
                arenaEffect: .historyChains,
                phaseLightIntensity: 760
            )
        }
    }

    private static func outcomeMapping(for beat: CinematicSessionTimelinePlan.Beat) -> OrdinaryMapping {
        switch beat.style {
        case .success:
            return OrdinaryMapping(
                kind: .outcome,
                cameraShot: .victory,
                lookTarget: boundedTarget([0, 1.7, -3.1]),
                lightFamily: .verify,
                arenaEffect: .victory,
                phaseLightIntensity: 760
            )
        case .failure:
            return OrdinaryMapping(
                kind: .outcome,
                cameraShot: .failure,
                lookTarget: boundedTarget([0, 1.32, -2.4]),
                lightFamily: .failure,
                arenaEffect: .charge,
                phaseLightIntensity: 900
            )
        case .warning:
            return OrdinaryMapping(
                kind: .outcome,
                cameraShot: .wide,
                lookTarget: boundedTarget([0.85, 1.14, -1.5]),
                lightFamily: .pressure,
                arenaEffect: .activityPulse,
                phaseLightIntensity: 620
            )
        case .paused:
            return OrdinaryMapping(
                kind: .outcome,
                cameraShot: .home,
                lookTarget: boundedTarget([0, 1.1, 0]),
                lightFamily: .lifecycle,
                arenaEffect: .none,
                phaseLightIntensity: 360
            )
        case .neutral, .active, .commit:
            return OrdinaryMapping(
                kind: .outcome,
                cameraShot: .home,
                lookTarget: boundedTarget([0, 1.1, -0.2]),
                lightFamily: .lifecycle,
                arenaEffect: .none,
                phaseLightIntensity: 420
            )
        }
    }

    private static func descriptor(
        beat: CinematicSessionTimelinePlan.Beat,
        kind: CinematicTimelineSceneFocusPlan.Descriptor.Kind,
        cameraShot: CinematicCameraShot,
        lookTarget: SIMD3<Float>,
        lightFamily: CinematicStageLightFamily,
        arenaEffect: CinematicStageArenaEffect,
        phaseLightIntensity: Float,
        commitNodeIdentifier: String?,
        recoveryTreatmentIdentifier: String?,
        recoveryVisualIdentifier: String?,
        usesFallbackTarget: Bool,
        discriminator: [String]
    ) -> CinematicTimelineSceneFocusPlan.Descriptor {
        let boundedTarget = boundedTarget(lookTarget)
        let identifier = bounded(
            ([
                "timeline-scene-focus",
                "beat:\(beat.stableID)",
                "kind:\(kind.rawValue)",
                "shot:\(cameraShot.identifier)",
                "light:\(lightFamily.rawValue)",
                "effect:\(arenaEffect.rawValue)",
                "target:\(positionIdentifier(boundedTarget))",
                "phase:\(fixed(phaseLightIntensity))"
            ] + discriminator).joined(separator: "|"),
            limit: CinematicTimelineSceneFocusPlan.identifierMaxCharacters
        )

        return CinematicTimelineSceneFocusPlan.Descriptor(
            identifier: identifier,
            beatID: beat.stableID,
            label: bounded(beat.label, limit: CinematicTimelineSceneFocusPlan.labelMaxCharacters),
            kind: kind,
            cameraShot: cameraShot,
            lookTarget: boundedTarget,
            lightFamily: lightFamily,
            arenaEffect: arenaEffect,
            phaseLightIntensity: clamp(
                phaseLightIntensity,
                to: CinematicRecoveryCuePlan.phaseLightIntensityRange
            ),
            commitNodeIdentifier: commitNodeIdentifier,
            recoveryTreatmentIdentifier: recoveryTreatmentIdentifier,
            recoveryVisualIdentifier: recoveryVisualIdentifier,
            usesFallbackTarget: usesFallbackTarget
        )
    }

    private static func representativeCommitBeat(
        commitConstellationPlan: CinematicCommitConstellationPlan
    ) -> CinematicSessionTimelinePlan.Beat? {
        guard let node = commitConstellationPlan.nodes.first else { return nil }
        return CinematicSessionTimelinePlan.Beat(
            stableID: "session-61-commit-\(node.commitIdentifier)",
            sessionNumber: 61,
            moment: .commit,
            title: "Commit \(node.shortHash)",
            label: node.label,
            detail: node.subject,
            metadata: "#61",
            timestamp: Date(timeIntervalSince1970: 61_500),
            chronologyIndex: 0,
            position: 1,
            style: .commit,
            systemImage: "arrow.triangle.branch",
            attentionLabel: nil,
            attentionDetail: nil
        )
    }

    private static func representativeRecoveryBeat(
        for selectedCue: CinematicRecoveryCuePlan.SelectedCue
    ) -> CinematicSessionTimelinePlan.Beat {
        let moment: CinematicSessionTimelinePlan.Beat.Moment
        switch selectedCue.kind {
        case .failedVerify:
            moment = .verify
        case .dirtyWorktree, .developBlocked, .developFailed, .resumeDevelop:
            moment = .develop
        case .promotionFailed, .rejectedPlan:
            moment = .outcome
        }

        return CinematicSessionTimelinePlan.Beat(
            stableID: "session-\(selectedCue.sessionNumber)-\(moment.rawValue)-attention",
            sessionNumber: selectedCue.sessionNumber,
            moment: moment,
            title: selectedCue.label,
            label: selectedCue.label,
            detail: selectedCue.detail,
            metadata: "#\(selectedCue.sessionNumber)",
            timestamp: Date(timeIntervalSince1970: Double(selectedCue.sessionNumber) * 1_000),
            chronologyIndex: 0,
            position: 0.72,
            style: selectedCue.severity == .warning ? .warning : .failure,
            systemImage: selectedCue.systemImage,
            attentionLabel: selectedCue.label,
            attentionDetail: selectedCue.detail
        )
    }

    private static func representativeFailedVerifyBeat(
        sessionNumber: Int
    ) -> CinematicSessionTimelinePlan.Beat {
        CinematicSessionTimelinePlan.Beat(
            stableID: "session-\(sessionNumber)-verify",
            sessionNumber: sessionNumber,
            moment: .verify,
            title: "Verify #\(sessionNumber)",
            label: "Verify #\(sessionNumber)",
            detail: "swift test exited 65",
            metadata: "swift test | exit 65",
            timestamp: Date(timeIntervalSince1970: Double(sessionNumber) * 1_000),
            chronologyIndex: 0,
            position: 0.68,
            style: .failure,
            systemImage: "checkmark.seal.fill",
            attentionLabel: nil,
            attentionDetail: nil
        )
    }

    private static func representativeOrdinaryBeat(
        moment: CinematicSessionTimelinePlan.Beat.Moment,
        sessionNumber: Int,
        style: CinematicSessionTimelinePlan.Beat.Style = .neutral
    ) -> CinematicSessionTimelinePlan.Beat {
        let title = "\(moment.shortTitle) #\(sessionNumber)"
        return CinematicSessionTimelinePlan.Beat(
            stableID: "session-\(sessionNumber)-\(moment.rawValue)",
            sessionNumber: sessionNumber,
            moment: moment,
            title: title,
            label: title,
            detail: "Representative \(moment.shortTitle.lowercased()) beat",
            metadata: "#\(sessionNumber)",
            timestamp: Date(timeIntervalSince1970: Double(sessionNumber) * 1_000),
            chronologyIndex: 0,
            position: 0.5,
            style: style,
            systemImage: "circle",
            attentionLabel: nil,
            attentionDetail: nil
        )
    }

    private static func isFailedVerifyBeat(_ beat: CinematicSessionTimelinePlan.Beat) -> Bool {
        beat.moment == .verify
            && (beat.style == .failure || beat.systemImage == "checkmark.seal.fill")
    }

    private static func target(
        for descriptor: CinematicRecoveryCuePlan.VisualDescriptor
    ) -> SIMD3<Float> {
        switch descriptor.treatmentIdentifier {
        case "verify-failure":
            return boundedTarget([0, 1.34, -2.7])
        case "dirty-cleanup":
            return boundedTarget([1.45, 1.08, -1.15])
        case "promotion-branch":
            return boundedTarget([-1.62, 1.5, -3.05])
        default:
            return boundedTarget([0, 1.2, -1.5])
        }
    }

    private static func commitIdentifier(from beatID: String) -> String? {
        guard let range = beatID.range(of: "-commit-") else { return nil }
        let suffix = beatID[range.upperBound...]
        let identifier = suffix
            .split(separator: "|", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier?.isEmpty == false ? identifier : nil
    }

    private static func boundedTarget(_ target: SIMD3<Float>) -> SIMD3<Float> {
        [
            clamp(target.x, to: CinematicTimelineSceneFocusPlan.targetXRange),
            clamp(target.y, to: CinematicTimelineSceneFocusPlan.targetYRange),
            clamp(target.z, to: CinematicTimelineSceneFocusPlan.targetZRange)
        ]
    }

    private static func positionIdentifier(_ value: SIMD3<Float>) -> String {
        [
            fixed(value.x),
            fixed(value.y),
            fixed(value.z)
        ].joined(separator: ",")
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
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
