import Foundation

struct CinematicRecoveryCuePlan: Equatable {
    static let intensityRange: ClosedRange<Float> = 0...1
    static let phaseLightIntensityRange: ClosedRange<Float> = 360...1_240
    static let fractureOpacityRange = CinematicStagePhasePolishPlan.fractureOpacityRange
    static let fractureSpreadRange = CinematicStagePhasePolishPlan.fractureSpreadRange
    static let healingOpacityRange = CinematicStagePhasePolishPlan.healingOpacityRange

    static let none = CinematicRecoveryCuePlan(
        identifier: "recovery:none",
        selectedCue: nil,
        visualDescriptor: nil
    )

    var identifier: String
    var selectedCue: SelectedCue?
    var visualDescriptor: VisualDescriptor?

    var hasActionableCue: Bool { selectedCue != nil }
    var selectedKindIdentifier: String { selectedCue?.kind.rawValue ?? "none" }
    var visualIdentifier: String { visualDescriptor?.identifier ?? "none" }

    struct SelectedCue: Equatable {
        var sessionNumber: Int
        var kind: PlanReliabilityFeedback.Kind
        var severity: PlanReliabilityFeedback.Severity
        var label: String
        var detail: String
        var systemImage: String

        var identifier: String {
            [
                "session\(sessionNumber)",
                kind.rawValue,
                severity.rawValue,
                systemImage
            ].joined(separator: "|")
        }
    }

    struct VisualDescriptor: Equatable {
        var identifier: String
        var treatmentIdentifier: String
        var lightFamily: CinematicStageLightFamily
        var fractureLightFamily: CinematicStageLightFamily
        var symbolIdentifier: String
        var systemImage: String
        var phaseLightIntensity: Float
        var intensity: Float
        var posture: CinematicStagePhasePolishPosture
        var arenaEffect: CinematicStageArenaEffect
        var fractureOpacity: Float
        var fractureSpread: Float
        var healingOpacity: Float
        var shouldShakeCamera: Bool
        var cameraShakeDuration: TimeInterval
        var cameraShakeScale: Float
    }
}

enum CinematicRecoveryCuePlanner {
    static let actionableKinds: Set<PlanReliabilityFeedback.Kind> = [
        .failedVerify,
        .mutationTestingRecovery,
        .dirtyWorktree,
        .promotionFailed
    ]

    static func plan(
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> CinematicRecoveryCuePlan {
        guard let selected = recentRunCues
            .filter({ actionableKinds.contains($0.value.kind) })
            .max(by: { $0.key < $1.key }) else {
            return .none
        }

        let selectedCue = CinematicRecoveryCuePlan.SelectedCue(
            sessionNumber: selected.key,
            kind: selected.value.kind,
            severity: selected.value.severity,
            label: selected.value.label,
            detail: selected.value.detail,
            systemImage: selected.value.systemImage
        )
        let descriptor = visualDescriptor(for: selectedCue, influenceSettings: influenceSettings)
        let identifier = [
            "recovery:\(selectedCue.identifier)",
            "visual:\(descriptor.identifier)"
        ].joined(separator: "|")

        return CinematicRecoveryCuePlan(
            identifier: identifier,
            selectedCue: selectedCue,
            visualDescriptor: descriptor
        )
    }

    static func representativePlans(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicRecoveryCuePlan] {
        [
            .none,
            plan(
                recentRunCues: [
                    41: runCue(
                        kind: .failedVerify,
                        severity: .failure,
                        label: "Retry Develop",
                        detail: "swift test --filter CinematicRecoveryCuePlanTests exited 65",
                        systemImage: "checkmark.seal.fill"
                    )
                ],
                influenceSettings: influenceSettings
            ),
            plan(
                recentRunCues: [
                    42: runCue(
                        kind: .dirtyWorktree,
                        severity: .warning,
                        label: "Clean Worktree",
                        detail: "M Sources/Compass/CinematicRealityScene.swift",
                        systemImage: "pencil.and.outline"
                    )
                ],
                influenceSettings: influenceSettings
            ),
            plan(
                recentRunCues: [
                    44: runCue(
                        kind: .mutationTestingRecovery,
                        severity: .failure,
                        label: "Review Mutation",
                        detail: "latest mutation run failed with exit 65",
                        systemImage: "testtube.2"
                    )
                ],
                influenceSettings: influenceSettings
            ),
            plan(
                recentRunCues: [
                    43: runCue(
                        kind: .promotionFailed,
                        severity: .failure,
                        label: "Resolve Promotion",
                        detail: "promotion branch could not fast-forward",
                        systemImage: "arrow.triangle.branch"
                    )
                ],
                influenceSettings: influenceSettings
            )
        ]
    }

    private static func visualDescriptor(
        for cue: CinematicRecoveryCuePlan.SelectedCue,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicRecoveryCuePlan.VisualDescriptor {
        let shakeScale = CinematicTuning.cameraShakeScale(settings: influenceSettings)

        switch cue.kind {
        case .failedVerify:
            return descriptor(
                cue: cue,
                treatmentIdentifier: "verify-failure",
                lightFamily: .failure,
                fractureLightFamily: .failure,
                symbolIdentifier: "verify-fracture-seal",
                phaseLightIntensity: 1_180,
                intensity: 1,
                posture: .fracture,
                arenaEffect: .charge,
                fractureOpacity: 0.72,
                fractureSpread: 1.18,
                healingOpacity: 0.06,
                shouldShakeCamera: true,
                cameraShakeDuration: 0.24,
                cameraShakeScale: shakeScale
            )
        case .mutationTestingRecovery:
            return descriptor(
                cue: cue,
                treatmentIdentifier: "mutation-recovery",
                lightFamily: .verify,
                fractureLightFamily: .failure,
                symbolIdentifier: "mutation-red-testtube",
                phaseLightIntensity: 1_140,
                intensity: 0.94,
                posture: .fracture,
                arenaEffect: .charge,
                fractureOpacity: 0.66,
                fractureSpread: 1.1,
                healingOpacity: 0.04,
                shouldShakeCamera: true,
                cameraShakeDuration: 0.2,
                cameraShakeScale: shakeScale * 0.9
            )
        case .dirtyWorktree:
            return descriptor(
                cue: cue,
                treatmentIdentifier: "dirty-cleanup",
                lightFamily: .edit,
                fractureLightFamily: .edit,
                symbolIdentifier: "edit-amber-cleanup",
                phaseLightIntensity: 780,
                intensity: 0.62,
                posture: .editing,
                arenaEffect: .activityPulse,
                fractureOpacity: 0.18,
                fractureSpread: 0.62,
                healingOpacity: 0.28,
                shouldShakeCamera: false,
                cameraShakeDuration: 0,
                cameraShakeScale: shakeScale
            )
        case .promotionFailed:
            return descriptor(
                cue: cue,
                treatmentIdentifier: "promotion-branch",
                lightFamily: .git,
                fractureLightFamily: .git,
                symbolIdentifier: "git-failure-branch",
                phaseLightIntensity: 1_040,
                intensity: 0.88,
                posture: .fracture,
                arenaEffect: .historyChains,
                fractureOpacity: 0.6,
                fractureSpread: 1.28,
                healingOpacity: 0.03,
                shouldShakeCamera: true,
                cameraShakeDuration: 0.18,
                cameraShakeScale: shakeScale * 0.82
            )
        case .rejectedPlan, .developBlocked, .developFailed, .resumeDevelop:
            return descriptor(
                cue: cue,
                treatmentIdentifier: "non-actionable",
                lightFamily: .lifecycle,
                fractureLightFamily: .failure,
                symbolIdentifier: "recovery-none",
                phaseLightIntensity: 360,
                intensity: 0,
                posture: .neutral,
                arenaEffect: .none,
                fractureOpacity: 0,
                fractureSpread: 0,
                healingOpacity: 0,
                shouldShakeCamera: false,
                cameraShakeDuration: 0,
                cameraShakeScale: shakeScale
            )
        }
    }

    private static func descriptor(
        cue: CinematicRecoveryCuePlan.SelectedCue,
        treatmentIdentifier: String,
        lightFamily: CinematicStageLightFamily,
        fractureLightFamily: CinematicStageLightFamily,
        symbolIdentifier: String,
        phaseLightIntensity: Float,
        intensity: Float,
        posture: CinematicStagePhasePolishPosture,
        arenaEffect: CinematicStageArenaEffect,
        fractureOpacity: Float,
        fractureSpread: Float,
        healingOpacity: Float,
        shouldShakeCamera: Bool,
        cameraShakeDuration: TimeInterval,
        cameraShakeScale: Float
    ) -> CinematicRecoveryCuePlan.VisualDescriptor {
        let boundedIntensity = clamp(intensity, to: CinematicRecoveryCuePlan.intensityRange)
        let boundedPhaseLightIntensity = clamp(
            phaseLightIntensity,
            to: CinematicRecoveryCuePlan.phaseLightIntensityRange
        )
        let boundedFractureOpacity = clamp(
            fractureOpacity,
            to: CinematicRecoveryCuePlan.fractureOpacityRange
        )
        let boundedFractureSpread = clamp(
            fractureSpread,
            to: CinematicRecoveryCuePlan.fractureSpreadRange
        )
        let boundedHealingOpacity = clamp(
            healingOpacity,
            to: CinematicRecoveryCuePlan.healingOpacityRange
        )
        let boundedShakeScale = clamp(cameraShakeScale, to: CinematicTuning.cameraShakeScaleRange)
        let boundedShakeDuration = min(
            max(cameraShakeDuration, CinematicStageEffectPlan.cameraShakeDurationRange.lowerBound),
            CinematicStageEffectPlan.cameraShakeDurationRange.upperBound
        )
        let identifier = [
            treatmentIdentifier,
            cue.kind.rawValue,
            "s\(cue.sessionNumber)",
            lightFamily.rawValue,
            fractureLightFamily.rawValue,
            symbolIdentifier,
            "i\(fixed(boundedIntensity))",
            "phase\(fixed(boundedPhaseLightIntensity))",
            "fracture\(fixed(boundedFractureOpacity))",
            "spread\(fixed(boundedFractureSpread))",
            "heal\(fixed(boundedHealingOpacity))",
            shouldShakeCamera ? "shake" : "steady"
        ].joined(separator: "|")

        return CinematicRecoveryCuePlan.VisualDescriptor(
            identifier: identifier,
            treatmentIdentifier: treatmentIdentifier,
            lightFamily: lightFamily,
            fractureLightFamily: fractureLightFamily,
            symbolIdentifier: symbolIdentifier,
            systemImage: cue.systemImage,
            phaseLightIntensity: boundedPhaseLightIntensity,
            intensity: boundedIntensity,
            posture: posture,
            arenaEffect: arenaEffect,
            fractureOpacity: boundedFractureOpacity,
            fractureSpread: boundedFractureSpread,
            healingOpacity: boundedHealingOpacity,
            shouldShakeCamera: shouldShakeCamera,
            cameraShakeDuration: boundedShakeDuration,
            cameraShakeScale: boundedShakeScale
        )
    }

    private static func runCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity,
        label: String,
        detail: String,
        systemImage: String
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-representative",
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

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
