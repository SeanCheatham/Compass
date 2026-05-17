import Foundation

enum CinematicStageBeatKind: String, CaseIterable, Equatable {
    case idle
    case planning
    case developing
    case verifying
    case succeeded
    case failed
    case paused
    case cancelled
}

enum CinematicStageLightFamily: String, CaseIterable, Equatable {
    case scan
    case shell
    case edit
    case git
    case verify
    case insight
    case lifecycle
    case pressure
    case failure

    var spell: SpellSchool {
        switch self {
        case .scan:
            return .scan
        case .shell:
            return .shell
        case .edit:
            return .edit
        case .git:
            return .git
        case .verify:
            return .verify
        case .insight:
            return .insight
        case .lifecycle:
            return .lifecycle
        case .pressure:
            return .pressure
        case .failure:
            return .failure
        }
    }
}

enum CinematicStageArenaEffect: String, CaseIterable, Equatable {
    case none
    case charge
    case seal
    case victory
    case activityPulse = "activity-pulse"
    case historyChains = "history-chains"
}

struct CinematicStageActivityAccent: Equatable {
    var eventKind: CinematicActivityEventKind
    var lightFamily: CinematicStageLightFamily
    var arenaEffect: CinematicStageArenaEffect
    var pulseRadius: Float
    var pulseColorAlpha: Float
    var pulseScaleMultiplier: Float
    var pulseOpacity: Float
    var shouldShakeCamera: Bool
    var shouldRunHistoryChains: Bool

    var identifier: String {
        [
            eventKind.rawValue,
            lightFamily.rawValue,
            arenaEffect.rawValue,
            CinematicStageBeatPlanner.fixed(pulseRadius),
            CinematicStageBeatPlanner.fixed(pulseColorAlpha),
            CinematicStageBeatPlanner.fixed(pulseScaleMultiplier),
            CinematicStageBeatPlanner.fixed(pulseOpacity),
            shouldShakeCamera ? "shake" : "steady",
            shouldRunHistoryChains ? "history" : "no-history"
        ].joined(separator: "|")
    }
}

struct CinematicStageBeat: Equatable {
    var phase: LoopPhase
    var kind: CinematicStageBeatKind
    var cameraShot: CinematicCameraShot
    var lightFamily: CinematicStageLightFamily
    var phaseLightIntensity: Float
    var arenaEffect: CinematicStageArenaEffect
    var shouldShakeCamera: Bool
    var shouldRunVictorySurge: Bool
    var shouldRunHistoryChains: Bool
    var activityAccent: CinematicStageActivityAccent?
    var influenceIdentifier: String

    var kindIdentifier: String { kind.rawValue }
    var phaseIdentifier: String { phase.rawValue }
    var cameraShotIdentifier: String { cameraShot.identifier }
    var lightFamilyIdentifier: String { lightFamily.rawValue }
    var arenaEffectIdentifier: String { arenaEffect.rawValue }
    var activityAccentIdentifier: String { activityAccent?.identifier ?? "none" }

    var identifier: String {
        [
            phaseIdentifier,
            kindIdentifier,
            cameraShotIdentifier,
            lightFamilyIdentifier,
            CinematicStageBeatPlanner.fixed(phaseLightIntensity),
            arenaEffectIdentifier,
            shouldShakeCamera ? "shake" : "steady",
            shouldRunVictorySurge ? "victory" : "no-victory",
            shouldRunHistoryChains ? "history" : "no-history",
            activityAccentIdentifier,
            influenceIdentifier
        ].joined(separator: "|")
    }
}

enum CinematicStageBeatPlanner {
    static let phaseLightIntensityRange: ClosedRange<Float> = 320...900
    static let activityPulseRadiusRange: ClosedRange<Float> = 0...8
    static let activityPulseColorAlphaRange: ClosedRange<Float> = 0...1
    static let activityPulseScaleMultiplierRange: ClosedRange<Float> = 0...2
    static let activityPulseOpacityRange: ClosedRange<Float> = 0...1

    static func plan(
        phase: LoopPhase,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStageBeat {
        let phaseBeat = phaseDecision(for: phase)
        let activityAccent = activityAccent(for: activityProfile)

        return CinematicStageBeat(
            phase: phase,
            kind: phaseBeat.kind,
            cameraShot: phaseBeat.cameraShot,
            lightFamily: phaseBeat.lightFamily,
            phaseLightIntensity: clamp(phaseBeat.phaseLightIntensity, to: phaseLightIntensityRange),
            arenaEffect: phaseBeat.arenaEffect,
            shouldShakeCamera: phaseBeat.shouldShakeCamera || (activityAccent?.shouldShakeCamera ?? false),
            shouldRunVictorySurge: phaseBeat.shouldRunVictorySurge,
            shouldRunHistoryChains: activityAccent?.shouldRunHistoryChains ?? false,
            activityAccent: activityAccent,
            influenceIdentifier: influenceIdentifier(influenceSettings)
        )
    }

    static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    private struct PhaseDecision {
        var kind: CinematicStageBeatKind
        var cameraShot: CinematicCameraShot
        var lightFamily: CinematicStageLightFamily
        var phaseLightIntensity: Float
        var arenaEffect: CinematicStageArenaEffect
        var shouldShakeCamera: Bool
        var shouldRunVictorySurge: Bool
    }

    private static func phaseDecision(for phase: LoopPhase) -> PhaseDecision {
        switch phase {
        case .planning:
            return PhaseDecision(
                kind: .planning,
                cameraShot: .wide,
                lightFamily: .scan,
                phaseLightIntensity: 520,
                arenaEffect: .charge,
                shouldShakeCamera: false,
                shouldRunVictorySurge: false
            )
        case .developing:
            return PhaseDecision(
                kind: .developing,
                cameraShot: .castPrep,
                lightFamily: .shell,
                phaseLightIntensity: 680,
                arenaEffect: .charge,
                shouldShakeCamera: false,
                shouldRunVictorySurge: false
            )
        case .verifying:
            return PhaseDecision(
                kind: .verifying,
                cameraShot: .overhead,
                lightFamily: .verify,
                phaseLightIntensity: 760,
                arenaEffect: .seal,
                shouldShakeCamera: false,
                shouldRunVictorySurge: false
            )
        case .succeeded:
            return PhaseDecision(
                kind: .succeeded,
                cameraShot: .victory,
                lightFamily: .verify,
                phaseLightIntensity: 760,
                arenaEffect: .victory,
                shouldShakeCamera: false,
                shouldRunVictorySurge: true
            )
        case .failed:
            return PhaseDecision(
                kind: .failed,
                cameraShot: .failure,
                lightFamily: .failure,
                phaseLightIntensity: 900,
                arenaEffect: .charge,
                shouldShakeCamera: true,
                shouldRunVictorySurge: false
            )
        case .paused:
            return PhaseDecision(
                kind: .paused,
                cameraShot: .home,
                lightFamily: .lifecycle,
                phaseLightIntensity: 320,
                arenaEffect: .none,
                shouldShakeCamera: false,
                shouldRunVictorySurge: false
            )
        case .cancelled:
            return PhaseDecision(
                kind: .cancelled,
                cameraShot: .home,
                lightFamily: .lifecycle,
                phaseLightIntensity: 320,
                arenaEffect: .none,
                shouldShakeCamera: false,
                shouldRunVictorySurge: false
            )
        case .idle:
            return PhaseDecision(
                kind: .idle,
                cameraShot: .home,
                lightFamily: .lifecycle,
                phaseLightIntensity: 320,
                arenaEffect: .none,
                shouldShakeCamera: false,
                shouldRunVictorySurge: false
            )
        }
    }

    private static func activityAccent(for profile: RepositoryActivityProfile) -> CinematicStageActivityAccent? {
        let motif = CinematicMotif.activity(for: profile)
        switch motif.eventKind {
        case .conflicted, .failure:
            return pulseAccent(
                eventKind: motif.eventKind,
                lightFamily: .failure,
                radius: 5.4,
                colorAlpha: 0.68,
                scaleMultiplier: 1.22,
                opacity: 0.5,
                shouldShakeCamera: motif.shouldShakeOnTransition
            )
        case .dirty:
            return pulseAccent(
                eventKind: motif.eventKind,
                lightFamily: .pressure,
                radius: 4.4,
                colorAlpha: 0.58,
                scaleMultiplier: 1.18,
                opacity: 0.4,
                shouldShakeCamera: false
            )
        case .success, .recovery:
            return pulseAccent(
                eventKind: motif.eventKind,
                lightFamily: .verify,
                radius: 5.8,
                colorAlpha: 0.58,
                scaleMultiplier: 1.14,
                opacity: 0.34,
                shouldShakeCamera: false
            )
        case .commit:
            return CinematicStageActivityAccent(
                eventKind: motif.eventKind,
                lightFamily: .git,
                arenaEffect: .historyChains,
                pulseRadius: 0,
                pulseColorAlpha: 0,
                pulseScaleMultiplier: 0,
                pulseOpacity: 0,
                shouldShakeCamera: false,
                shouldRunHistoryChains: true
            )
        case .clean, .unavailable:
            return nil
        }
    }

    private static func pulseAccent(
        eventKind: CinematicActivityEventKind,
        lightFamily: CinematicStageLightFamily,
        radius: Float,
        colorAlpha: Float,
        scaleMultiplier: Float,
        opacity: Float,
        shouldShakeCamera: Bool
    ) -> CinematicStageActivityAccent {
        CinematicStageActivityAccent(
            eventKind: eventKind,
            lightFamily: lightFamily,
            arenaEffect: .activityPulse,
            pulseRadius: clamp(radius, to: activityPulseRadiusRange),
            pulseColorAlpha: clamp(colorAlpha, to: activityPulseColorAlphaRange),
            pulseScaleMultiplier: clamp(scaleMultiplier, to: activityPulseScaleMultiplierRange),
            pulseOpacity: clamp(opacity, to: activityPulseOpacityRange),
            shouldShakeCamera: shouldShakeCamera,
            shouldRunHistoryChains: false
        )
    }

    private static func influenceIdentifier(_ settings: CinematicInfluenceSettings) -> String {
        [
            settings.cameraStyle.rawValue,
            String(format: "%.4f", CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        ].joined(separator: "|")
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
