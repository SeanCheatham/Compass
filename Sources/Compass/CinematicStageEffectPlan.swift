import Foundation

struct CinematicStageEffectPlan: Equatable {
    static let arenaRingRadiusRange: ClosedRange<Float> = 0...12
    static let arenaRingDurationRange: ClosedRange<TimeInterval> = 0.1...2.4
    static let arenaRingScaleRange: ClosedRange<Float> = 0.1...8
    static let arenaRingOpacityRange: ClosedRange<Float> = 0...1
    static let colorAlphaRange: ClosedRange<Float> = 0...1
    static let phaseLightPulseIntensityRange: ClosedRange<Float> = 0...1_600
    static let phaseLightPulseDurationRange: ClosedRange<TimeInterval> = 0.1...1.6
    static let phaseLightResetIntensityRange: ClosedRange<Float> = 0...900
    static let sparkBirthRateRange: ClosedRange<Float> = 0...2_000
    static let cameraShakeDurationRange: ClosedRange<TimeInterval> = 0...0.5
    static let historyTrailCountRange = 0...6

    var identifier: String
    var beatIdentifier: String
    var phaseEffect: EffectChoreography
    var activityEffect: EffectChoreography?
    var influenceIdentifier: String

    var effects: [EffectChoreography] {
        var values = [phaseEffect]
        if let activityEffect {
            values.append(activityEffect)
        }
        return values
    }

    struct EffectChoreography: Equatable {
        var identifier: String
        var sourceIdentifier: String
        var arenaEffect: CinematicStageArenaEffect
        var lightFamily: CinematicStageLightFamily
        var arenaRings: [ArenaRing]
        var phaseLightPulse: PhaseLightPulse?
        var sparkBursts: [SparkBurst]
        var historyTrails: [HistoryTrail]
        var victoryCadence: VictoryCadence?
        var cameraShake: CameraShake?
    }

    struct ArenaRing: Equatable {
        var radius: Float
        var duration: TimeInterval
        var scale: Float
        var opacity: Float
        var colorAlpha: Float

        var identifier: String {
            [
                "r\(CinematicStageEffectPlanner.fixed(radius))",
                "d\(CinematicStageEffectPlanner.fixed(duration))",
                "s\(CinematicStageEffectPlanner.fixed(scale))",
                "o\(CinematicStageEffectPlanner.fixed(opacity))",
                "a\(CinematicStageEffectPlanner.fixed(colorAlpha))"
            ].joined(separator: "/")
        }
    }

    struct PhaseLightPulse: Equatable {
        var intensity: Float
        var duration: TimeInterval
        var resetIntensity: Float

        var identifier: String {
            [
                "i\(CinematicStageEffectPlanner.fixed(intensity))",
                "d\(CinematicStageEffectPlanner.fixed(duration))",
                "reset\(CinematicStageEffectPlanner.fixed(resetIntensity))"
            ].joined(separator: "/")
        }
    }

    struct SparkBurst: Equatable {
        var position: SIMD3<Float>
        var birthRate: Float
        var colorAlpha: Float

        var identifier: String {
            [
                "p\(CinematicStageEffectPlanner.positionIdentifier(position))",
                "b\(CinematicStageEffectPlanner.fixed(birthRate))",
                "a\(CinematicStageEffectPlanner.fixed(colorAlpha))"
            ].joined(separator: "/")
        }
    }

    struct HistoryTrail: Equatable {
        var start: SIMD3<Float>
        var end: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily

        var identifier: String {
            [
                "from:\(CinematicStageEffectPlanner.positionIdentifier(start))",
                "to:\(CinematicStageEffectPlanner.positionIdentifier(end))",
                lightFamily.rawValue
            ].joined(separator: "/")
        }
    }

    struct VictoryCadence: Equatable {
        var cameraShot: CinematicCameraShot
        var ambientSpawnDelay: TimeInterval
        var shouldVolleyActiveEnemies: Bool
        var shouldRunPortalPulse: Bool
        var portalLightFamily: CinematicStageLightFamily

        var identifier: String {
            [
                cameraShot.identifier,
                "ambient\(CinematicStageEffectPlanner.fixed(ambientSpawnDelay))",
                shouldVolleyActiveEnemies ? "volley" : "no-volley",
                shouldRunPortalPulse ? "portal" : "no-portal",
                portalLightFamily.rawValue
            ].joined(separator: "/")
        }
    }

    struct CameraShake: Equatable {
        var shouldShake: Bool
        var duration: TimeInterval
        var scale: Float

        var identifier: String {
            [
                shouldShake ? "shake" : "steady",
                "d\(CinematicStageEffectPlanner.fixed(duration))",
                "s\(CinematicStageEffectPlanner.fixed(scale))"
            ].joined(separator: "/")
        }
    }
}

enum CinematicStageEffectPlanner {
    static func plan(
        beat: CinematicStageBeat,
        setDressingPlan: CinematicSetDressingPlan,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStageEffectPlan {
        let phaseEffect = phaseEffect(
            for: beat,
            influenceSettings: influenceSettings
        )
        let activityEffect = beat.activityAccent.map {
            effect(
                for: $0,
                setDressingPlan: setDressingPlan,
                influenceSettings: influenceSettings
            )
        }
        let influenceIdentifier = influenceIdentifier(influenceSettings)
        let identifier = [
            "beat:\(beat.identifier)",
            "phase:\(phaseEffect.identifier)",
            "activity:\(activityEffect?.identifier ?? "none")",
            "influence:\(influenceIdentifier)"
        ].joined(separator: "||")

        return CinematicStageEffectPlan(
            identifier: identifier,
            beatIdentifier: beat.identifier,
            phaseEffect: phaseEffect,
            activityEffect: activityEffect,
            influenceIdentifier: influenceIdentifier
        )
    }

    static func historyChainsEffect(
        lightFamily: CinematicStageLightFamily = .git,
        sourceIdentifier: String = "history-chains"
    ) -> CinematicStageEffectPlan.EffectChoreography {
        effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .historyChains,
            lightFamily: lightFamily,
            arenaRings: [
                arenaRing(radius: 4.0, duration: 0.95, scale: 1.45, opacity: 0.58, colorAlpha: 1)
            ],
            historyTrails: historyTrails(lightFamily: lightFamily)
        )
    }

    static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    static func fixed(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }

    static func positionIdentifier(_ value: SIMD3<Float>) -> String {
        [
            fixed(value.x),
            fixed(value.y),
            fixed(value.z)
        ].joined(separator: ",")
    }

    private static func phaseEffect(
        for beat: CinematicStageBeat,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let sourceIdentifier = "phase:\(beat.kindIdentifier)"
        let cameraShake = beat.kind == .failed && beat.shouldShakeCamera
            ? cameraShake(settings: influenceSettings)
            : nil

        switch beat.arenaEffect {
        case .charge:
            return chargeEffect(
                lightFamily: beat.lightFamily,
                sourceIdentifier: sourceIdentifier,
                cameraShake: cameraShake
            )
        case .seal:
            return sealEffect(
                lightFamily: beat.lightFamily,
                sourceIdentifier: sourceIdentifier,
                cameraShake: cameraShake
            )
        case .victory:
            return victoryEffect(
                lightFamily: beat.lightFamily,
                sourceIdentifier: sourceIdentifier,
                cameraShake: cameraShake
            )
        case .none, .activityPulse, .historyChains:
            return effect(
                sourceIdentifier: sourceIdentifier,
                arenaEffect: beat.arenaEffect,
                lightFamily: beat.lightFamily,
                cameraShake: cameraShake
            )
        }
    }

    private static func effect(
        for accent: CinematicStageActivityAccent,
        setDressingPlan: CinematicSetDressingPlan,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let sourceIdentifier = "activity:\(accent.eventKind.rawValue)"
        let cameraShake = accent.shouldShakeCamera ? cameraShake(settings: influenceSettings) : nil

        switch accent.arenaEffect {
        case .activityPulse:
            let duration = clamp(
                setDressingPlan.animationCadence.activityPulseDuration,
                to: CinematicStageEffectPlan.arenaRingDurationRange
            )
            let scale = clamp(
                accent.pulseScaleMultiplier * setDressingPlan.runeIntensity.activityPulseScale,
                to: CinematicStageEffectPlan.arenaRingScaleRange
            )
            return effect(
                sourceIdentifier: sourceIdentifier,
                arenaEffect: accent.arenaEffect,
                lightFamily: accent.lightFamily,
                arenaRings: [
                    arenaRing(
                        radius: accent.pulseRadius,
                        duration: duration,
                        scale: scale,
                        opacity: accent.pulseOpacity,
                        colorAlpha: accent.pulseColorAlpha
                    )
                ],
                cameraShake: cameraShake
            )
        case .historyChains:
            var historyEffect = historyChainsEffect(
                lightFamily: accent.lightFamily,
                sourceIdentifier: sourceIdentifier
            )
            historyEffect.cameraShake = cameraShake
            historyEffect.identifier = identifier(for: historyEffect)
            return historyEffect
        case .none, .charge, .seal, .victory:
            return effect(
                sourceIdentifier: sourceIdentifier,
                arenaEffect: accent.arenaEffect,
                lightFamily: accent.lightFamily,
                cameraShake: cameraShake
            )
        }
    }

    private static func chargeEffect(
        lightFamily: CinematicStageLightFamily,
        sourceIdentifier: String,
        cameraShake: CinematicStageEffectPlan.CameraShake?
    ) -> CinematicStageEffectPlan.EffectChoreography {
        effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .charge,
            lightFamily: lightFamily,
            arenaRings: [
                arenaRing(radius: 1.1, duration: 0.55, scale: 5.8, opacity: 0.72, colorAlpha: 1),
                arenaRing(radius: 2.4, duration: 0.85, scale: 2.7, opacity: 0.46, colorAlpha: 0.8)
            ],
            phaseLightPulse: phaseLightPulse(intensity: 880, duration: 0.42),
            cameraShake: cameraShake
        )
    }

    private static func sealEffect(
        lightFamily: CinematicStageLightFamily,
        sourceIdentifier: String,
        cameraShake: CinematicStageEffectPlan.CameraShake?
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let rings = [Float(0.9), 1.8, 3.0, 4.4].enumerated().map { index, radius in
            arenaRing(
                radius: radius,
                duration: 0.85 + TimeInterval(index) * 0.12,
                scale: 1.9,
                opacity: 0.7,
                colorAlpha: 0.9 - Float(index) * 0.12
            )
        }
        return effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .seal,
            lightFamily: lightFamily,
            arenaRings: rings,
            phaseLightPulse: phaseLightPulse(intensity: 1_200, duration: 0.8),
            sparkBursts: [
                sparkBurst(position: [0, 0.5, 0], birthRate: 1_200, colorAlpha: 1)
            ],
            cameraShake: cameraShake
        )
    }

    private static func victoryEffect(
        lightFamily: CinematicStageLightFamily,
        sourceIdentifier: String,
        cameraShake: CinematicStageEffectPlan.CameraShake?
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let rings = (0...6).map { index in
            arenaRing(
                radius: 0.9 + Float(index) * 1.1,
                duration: 1.1,
                scale: 1.35,
                opacity: 0.54,
                colorAlpha: 0.7
            )
        }
        return effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .victory,
            lightFamily: lightFamily,
            arenaRings: rings,
            phaseLightPulse: phaseLightPulse(intensity: 1_500, duration: 1.0),
            sparkBursts: [
                sparkBurst(position: [0, 1.3, -0.4], birthRate: 1_600, colorAlpha: 1)
            ],
            victoryCadence: CinematicStageEffectPlan.VictoryCadence(
                cameraShot: .victory,
                ambientSpawnDelay: 2.2,
                shouldVolleyActiveEnemies: true,
                shouldRunPortalPulse: true,
                portalLightFamily: lightFamily
            ),
            cameraShake: cameraShake
        )
    }

    private static func effect(
        sourceIdentifier: String,
        arenaEffect: CinematicStageArenaEffect,
        lightFamily: CinematicStageLightFamily,
        arenaRings: [CinematicStageEffectPlan.ArenaRing] = [],
        phaseLightPulse: CinematicStageEffectPlan.PhaseLightPulse? = nil,
        sparkBursts: [CinematicStageEffectPlan.SparkBurst] = [],
        historyTrails: [CinematicStageEffectPlan.HistoryTrail] = [],
        victoryCadence: CinematicStageEffectPlan.VictoryCadence? = nil,
        cameraShake: CinematicStageEffectPlan.CameraShake? = nil
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let boundedHistoryTrails = Array(historyTrails.prefix(CinematicStageEffectPlan.historyTrailCountRange.upperBound))
        let effect = CinematicStageEffectPlan.EffectChoreography(
            identifier: "",
            sourceIdentifier: sourceIdentifier,
            arenaEffect: arenaEffect,
            lightFamily: lightFamily,
            arenaRings: arenaRings,
            phaseLightPulse: phaseLightPulse,
            sparkBursts: sparkBursts,
            historyTrails: boundedHistoryTrails,
            victoryCadence: victoryCadence,
            cameraShake: cameraShake
        )
        var identified = effect
        identified.identifier = identifier(for: effect)
        return identified
    }

    private static func identifier(for effect: CinematicStageEffectPlan.EffectChoreography) -> String {
        [
            effect.sourceIdentifier,
            effect.arenaEffect.rawValue,
            effect.lightFamily.rawValue,
            "rings:\(effect.arenaRings.map(\.identifier).joined(separator: ","))",
            "pulse:\(effect.phaseLightPulse?.identifier ?? "none")",
            "sparks:\(effect.sparkBursts.map(\.identifier).joined(separator: ","))",
            "history:\(effect.historyTrails.map(\.identifier).joined(separator: ","))",
            "victory:\(effect.victoryCadence?.identifier ?? "none")",
            "camera:\(effect.cameraShake?.identifier ?? "steady")"
        ].joined(separator: "|")
    }

    private static func arenaRing(
        radius: Float,
        duration: TimeInterval,
        scale: Float,
        opacity: Float,
        colorAlpha: Float
    ) -> CinematicStageEffectPlan.ArenaRing {
        CinematicStageEffectPlan.ArenaRing(
            radius: clamp(radius, to: CinematicStageEffectPlan.arenaRingRadiusRange),
            duration: clamp(duration, to: CinematicStageEffectPlan.arenaRingDurationRange),
            scale: clamp(scale, to: CinematicStageEffectPlan.arenaRingScaleRange),
            opacity: clamp(opacity, to: CinematicStageEffectPlan.arenaRingOpacityRange),
            colorAlpha: clamp(colorAlpha, to: CinematicStageEffectPlan.colorAlphaRange)
        )
    }

    private static func phaseLightPulse(
        intensity: Float,
        duration: TimeInterval,
        resetIntensity: Float = 360
    ) -> CinematicStageEffectPlan.PhaseLightPulse {
        CinematicStageEffectPlan.PhaseLightPulse(
            intensity: clamp(intensity, to: CinematicStageEffectPlan.phaseLightPulseIntensityRange),
            duration: clamp(duration, to: CinematicStageEffectPlan.phaseLightPulseDurationRange),
            resetIntensity: clamp(resetIntensity, to: CinematicStageEffectPlan.phaseLightResetIntensityRange)
        )
    }

    private static func sparkBurst(
        position: SIMD3<Float>,
        birthRate: Float,
        colorAlpha: Float
    ) -> CinematicStageEffectPlan.SparkBurst {
        CinematicStageEffectPlan.SparkBurst(
            position: position,
            birthRate: clamp(birthRate, to: CinematicStageEffectPlan.sparkBirthRateRange),
            colorAlpha: clamp(colorAlpha, to: CinematicStageEffectPlan.colorAlphaRange)
        )
    }

    private static func historyTrails(
        lightFamily: CinematicStageLightFamily
    ) -> [CinematicStageEffectPlan.HistoryTrail] {
        [
            CinematicStageEffectPlan.HistoryTrail(
                start: [-3.8, 0.18, -1.8],
                end: [3.6, 0.18, 1.6],
                lightFamily: lightFamily
            ),
            CinematicStageEffectPlan.HistoryTrail(
                start: [-3.2, 0.24, 2.0],
                end: [3.3, 0.24, -1.6],
                lightFamily: lightFamily
            ),
            CinematicStageEffectPlan.HistoryTrail(
                start: [0, 0.26, -4.2],
                end: [0, 0.26, 4.2],
                lightFamily: lightFamily
            )
        ]
    }

    private static func cameraShake(
        settings: CinematicInfluenceSettings
    ) -> CinematicStageEffectPlan.CameraShake {
        let scale = clamp(
            CinematicTuning.cameraShakeScale(settings: settings),
            to: CinematicTuning.cameraShakeScaleRange
        )
        return CinematicStageEffectPlan.CameraShake(
            shouldShake: true,
            duration: clamp(0.22 * TimeInterval(scale), to: CinematicStageEffectPlan.cameraShakeDurationRange),
            scale: scale
        )
    }

    private static func influenceIdentifier(_ settings: CinematicInfluenceSettings) -> String {
        [
            settings.cameraStyle.rawValue,
            fixed(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        ].joined(separator: "|")
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
