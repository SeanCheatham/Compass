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
    static let stageEffectPressureRange: ClosedRange<Float> = 0...1
    static let stageEffectEnergyRange: ClosedRange<Float> = 0...1
    static let stageEffectInfluenceRange: ClosedRange<Float> = 0...1
    static let stageEffectActivityLightBoostRange: ClosedRange<Float> = 0...560
    static let stageEffectRunePulseScaleRange: ClosedRange<Float> = 0.55...1.35
    static let stageEffectActivityPulseDurationRange: ClosedRange<TimeInterval> = 0.56...1.24
    static let ringDurationScaleRange: ClosedRange<Float> = 0.74...1.18
    static let ringScaleMultiplierRange: ClosedRange<Float> = 0.88...1.38
    static let ringOpacityMultiplierRange: ClosedRange<Float> = 0.9...1.2
    static let colorAlphaMultiplierRange: ClosedRange<Float> = 0.92...1.12
    static let pulseIntensityMultiplierRange: ClosedRange<Float> = 0.86...1.32
    static let pulseDurationMultiplierRange: ClosedRange<Float> = 0.8...1.16
    static let sparkBirthRateMultiplierRange: ClosedRange<Float> = 0.82...1.45
    static let historyTrailTuningCountRange = 3...6
    static let cameraShakeMultiplierRange: ClosedRange<Float> = 0.75...1.3
    static let cameraShakeDurationMultiplierRange: ClosedRange<Float> = 0.88...1.16
    static let victoryCadenceMultiplierRange: ClosedRange<Float> = 0.78...1.16
    static let victoryAmbientSpawnDelayRange: ClosedRange<TimeInterval> = 1.2...2.8

    var identifier: String
    var beatIdentifier: String
    var phaseEffect: EffectChoreography
    var activityEffect: EffectChoreography?
    var recoveryEffect: EffectChoreography?
    var recoveryCueIdentifier: String
    var recoveryCueKindIdentifier: String
    var influenceIdentifier: String
    var tuningMetadata: StageEffectTuning

    var effects: [EffectChoreography] {
        var values = [phaseEffect]
        if let activityEffect {
            values.append(activityEffect)
        }
        if let recoveryEffect {
            values.append(recoveryEffect)
        }
        return values
    }

    static var neutralStageEffectTuning: StageEffectTuning {
        StageEffectTuning(
            pressureLevelIdentifier: RepositoryWorktreePressureLevel.clean.rawValue,
            pressureFraction: 0,
            energy: 0.5,
            influenceStyleIdentifier: CinematicInfluenceSettings.CameraStyle.follow.rawValue,
            influenceIntensity: Float(CinematicInfluenceSettings.defaultIntensity),
            influenceFraction: 0.5,
            activityLightBoost: 0,
            activityLightBoostFraction: 0,
            runePulseScale: 1,
            activityPulseDuration: 0.9,
            ringDurationScale: 1,
            ringScaleMultiplier: 1,
            ringOpacityMultiplier: 1,
            colorAlphaMultiplier: 1,
            pulseIntensityMultiplier: 1,
            pulseDurationMultiplier: 1,
            sparkBirthRateMultiplier: 1,
            historyTrailCount: 3,
            cameraShakeMultiplier: 1,
            cameraShakeDurationMultiplier: 1,
            victoryCadenceMultiplier: 1
        )
    }

    struct StageEffectTuning: Equatable {
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
        var historyTrailCount: Int
        var cameraShakeMultiplier: Float
        var cameraShakeDurationMultiplier: Float
        var victoryCadenceMultiplier: Float

        var identifier: String {
            [
                "pressure:\(pressureLevelIdentifier):\(CinematicStageEffectPlanner.fixed(pressureFraction))",
                "energy:\(CinematicStageEffectPlanner.fixed(energy))",
                "influence:\(influenceStyleIdentifier):\(CinematicStageEffectPlanner.fixed(influenceIntensity)):\(CinematicStageEffectPlanner.fixed(influenceFraction))",
                "light:\(CinematicStageEffectPlanner.fixed(activityLightBoost)):\(CinematicStageEffectPlanner.fixed(activityLightBoostFraction))",
                "rune:\(CinematicStageEffectPlanner.fixed(runePulseScale))",
                "cadence:\(CinematicStageEffectPlanner.fixed(activityPulseDuration))",
                "ring:\(CinematicStageEffectPlanner.fixed(ringDurationScale)):\(CinematicStageEffectPlanner.fixed(ringScaleMultiplier)):\(CinematicStageEffectPlanner.fixed(ringOpacityMultiplier)):\(CinematicStageEffectPlanner.fixed(colorAlphaMultiplier))",
                "pulse:\(CinematicStageEffectPlanner.fixed(pulseIntensityMultiplier)):\(CinematicStageEffectPlanner.fixed(pulseDurationMultiplier))",
                "spark:\(CinematicStageEffectPlanner.fixed(sparkBirthRateMultiplier))",
                "trail:\(historyTrailCount)",
                "shake:\(CinematicStageEffectPlanner.fixed(cameraShakeMultiplier)):\(CinematicStageEffectPlanner.fixed(cameraShakeDurationMultiplier))",
                "victory:\(CinematicStageEffectPlanner.fixed(victoryCadenceMultiplier))"
            ].joined(separator: "|")
        }
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
        influenceSettings: CinematicInfluenceSettings,
        recoveryCuePlan: CinematicRecoveryCuePlan = .none
    ) -> CinematicStageEffectPlan {
        let tuningMetadata = stageEffectTuning(
            setDressingPlan: setDressingPlan,
            influenceSettings: influenceSettings
        )
        let phaseEffect = phaseEffect(
            for: beat,
            influenceSettings: influenceSettings,
            tuningMetadata: tuningMetadata
        )
        let activityEffect = beat.activityAccent.map {
            effect(
                for: $0,
                setDressingPlan: setDressingPlan,
                influenceSettings: influenceSettings,
                tuningMetadata: tuningMetadata
            )
        }
        let recoveryEffect = recoveryEffect(
            for: recoveryCuePlan,
            tuningMetadata: tuningMetadata
        )
        let influenceIdentifier = influenceIdentifier(influenceSettings)
        let identifier = [
            "beat:\(beat.identifier)",
            "phase:\(phaseEffect.identifier)",
            "activity:\(activityEffect?.identifier ?? "none")",
            "recovery:\(recoveryEffect?.identifier ?? "none")",
            "recovery-cue:\(recoveryCuePlan.identifier)",
            "influence:\(influenceIdentifier)",
            "tuning:\(tuningMetadata.identifier)"
        ].joined(separator: "||")

        return CinematicStageEffectPlan(
            identifier: identifier,
            beatIdentifier: beat.identifier,
            phaseEffect: phaseEffect,
            activityEffect: activityEffect,
            recoveryEffect: recoveryEffect,
            recoveryCueIdentifier: recoveryCuePlan.identifier,
            recoveryCueKindIdentifier: recoveryCuePlan.selectedKindIdentifier,
            influenceIdentifier: influenceIdentifier,
            tuningMetadata: tuningMetadata
        )
    }

    static func historyChainsEffect(
        lightFamily: CinematicStageLightFamily = .git,
        sourceIdentifier: String = "history-chains",
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning = CinematicStageEffectPlan.neutralStageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography {
        effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .historyChains,
            lightFamily: lightFamily,
            arenaRings: [
                tunedArenaRing(radius: 4.0, duration: 0.95, scale: 1.45, opacity: 0.58, colorAlpha: 1, tuningMetadata: tuningMetadata)
            ],
            historyTrails: historyTrails(lightFamily: lightFamily, tuningMetadata: tuningMetadata)
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
        influenceSettings: CinematicInfluenceSettings,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let sourceIdentifier = "phase:\(beat.kindIdentifier)"
        let cameraShake = beat.kind == .failed && beat.shouldShakeCamera
            ? cameraShake(settings: influenceSettings, tuningMetadata: tuningMetadata)
            : nil

        switch beat.arenaEffect {
        case .charge:
            return chargeEffect(
                lightFamily: beat.lightFamily,
                sourceIdentifier: sourceIdentifier,
                cameraShake: cameraShake,
                tuningMetadata: tuningMetadata
            )
        case .seal:
            return sealEffect(
                lightFamily: beat.lightFamily,
                sourceIdentifier: sourceIdentifier,
                cameraShake: cameraShake,
                tuningMetadata: tuningMetadata
            )
        case .victory:
            return victoryEffect(
                lightFamily: beat.lightFamily,
                sourceIdentifier: sourceIdentifier,
                cameraShake: cameraShake,
                tuningMetadata: tuningMetadata
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
        influenceSettings: CinematicInfluenceSettings,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let sourceIdentifier = "activity:\(accent.eventKind.rawValue)"
        let cameraShake = accent.shouldShakeCamera
            ? cameraShake(settings: influenceSettings, tuningMetadata: tuningMetadata)
            : nil

        switch accent.arenaEffect {
        case .activityPulse:
            let duration = clamp(
                tuningMetadata.activityPulseDuration * TimeInterval(tuningMetadata.pulseDurationMultiplier),
                to: CinematicStageEffectPlan.arenaRingDurationRange
            )
            let scale = clamp(
                accent.pulseScaleMultiplier
                    * setDressingPlan.runeIntensity.activityPulseScale
                    * tuningMetadata.ringScaleMultiplier,
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
                        opacity: accent.pulseOpacity * tuningMetadata.ringOpacityMultiplier,
                        colorAlpha: accent.pulseColorAlpha * tuningMetadata.colorAlphaMultiplier
                    )
                ],
                cameraShake: cameraShake
            )
        case .historyChains:
            var historyEffect = historyChainsEffect(
                lightFamily: accent.lightFamily,
                sourceIdentifier: sourceIdentifier,
                tuningMetadata: tuningMetadata
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

    private static func recoveryEffect(
        for plan: CinematicRecoveryCuePlan,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography? {
        guard let descriptor = plan.visualDescriptor else { return nil }

        let sourceIdentifier = "recovery:\(descriptor.treatmentIdentifier):\(plan.selectedCue?.sessionNumber ?? 0)"
        let cameraShake = descriptor.shouldShakeCamera
            ? CinematicStageEffectPlan.CameraShake(
                shouldShake: true,
                duration: descriptor.cameraShakeDuration,
                scale: descriptor.cameraShakeScale
            )
            : nil

        switch descriptor.arenaEffect {
        case .historyChains:
            var historyEffect = historyChainsEffect(
                lightFamily: descriptor.lightFamily,
                sourceIdentifier: sourceIdentifier,
                tuningMetadata: tuningMetadata
            )
            historyEffect.phaseLightPulse = tunedPhaseLightPulse(
                intensity: descriptor.phaseLightIntensity,
                duration: 0.46 + TimeInterval(descriptor.intensity) * 0.22,
                resetIntensity: 420,
                tuningMetadata: tuningMetadata
            )
            historyEffect.cameraShake = cameraShake
            historyEffect.identifier = identifier(for: historyEffect)
            return historyEffect
        case .activityPulse:
            return effect(
                sourceIdentifier: sourceIdentifier,
                arenaEffect: .activityPulse,
                lightFamily: descriptor.lightFamily,
                arenaRings: [
                    tunedArenaRing(
                        radius: 4.2 + descriptor.intensity,
                        duration: 0.9,
                        scale: 1.55 + descriptor.intensity * 0.34,
                        opacity: 0.34 + descriptor.intensity * 0.16,
                        colorAlpha: 0.72,
                        tuningMetadata: tuningMetadata
                    )
                ],
                phaseLightPulse: tunedPhaseLightPulse(
                    intensity: descriptor.phaseLightIntensity,
                    duration: 0.34 + TimeInterval(descriptor.intensity) * 0.2,
                    resetIntensity: 420,
                    tuningMetadata: tuningMetadata
                ),
                sparkBursts: [
                    tunedSparkBurst(
                        position: [0, 0.42, 1.05],
                        birthRate: 480 + descriptor.intensity * 520,
                        colorAlpha: 0.78,
                        tuningMetadata: tuningMetadata
                    )
                ],
                cameraShake: cameraShake
            )
        case .charge:
            return effect(
                sourceIdentifier: sourceIdentifier,
                arenaEffect: .charge,
                lightFamily: descriptor.lightFamily,
                arenaRings: [
                    tunedArenaRing(
                        radius: 1.2,
                        duration: 0.42,
                        scale: 5.2 + descriptor.intensity * 0.8,
                        opacity: 0.64,
                        colorAlpha: 1,
                        tuningMetadata: tuningMetadata
                    ),
                    tunedArenaRing(
                        radius: 3.4,
                        duration: 0.78,
                        scale: 2.35 + descriptor.intensity * 0.55,
                        opacity: 0.42,
                        colorAlpha: 0.82,
                        tuningMetadata: tuningMetadata
                    )
                ],
                phaseLightPulse: tunedPhaseLightPulse(
                    intensity: descriptor.phaseLightIntensity,
                    duration: 0.4 + TimeInterval(descriptor.intensity) * 0.18,
                    resetIntensity: 420,
                    tuningMetadata: tuningMetadata
                ),
                sparkBursts: [
                    tunedSparkBurst(
                        position: [0, 0.52, -0.55],
                        birthRate: 720 + descriptor.intensity * 560,
                        colorAlpha: 0.92,
                        tuningMetadata: tuningMetadata
                    )
                ],
                cameraShake: cameraShake
            )
        case .seal, .victory, .none:
            return effect(
                sourceIdentifier: sourceIdentifier,
                arenaEffect: descriptor.arenaEffect,
                lightFamily: descriptor.lightFamily,
                phaseLightPulse: tunedPhaseLightPulse(
                    intensity: descriptor.phaseLightIntensity,
                    duration: 0.36,
                    resetIntensity: 420,
                    tuningMetadata: tuningMetadata
                ),
                cameraShake: cameraShake
            )
        }
    }

    private static func chargeEffect(
        lightFamily: CinematicStageLightFamily,
        sourceIdentifier: String,
        cameraShake: CinematicStageEffectPlan.CameraShake?,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography {
        effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .charge,
            lightFamily: lightFamily,
            arenaRings: [
                tunedArenaRing(radius: 1.1, duration: 0.55, scale: 5.8, opacity: 0.72, colorAlpha: 1, tuningMetadata: tuningMetadata),
                tunedArenaRing(radius: 2.4, duration: 0.85, scale: 2.7, opacity: 0.46, colorAlpha: 0.8, tuningMetadata: tuningMetadata)
            ],
            phaseLightPulse: tunedPhaseLightPulse(intensity: 880, duration: 0.42, tuningMetadata: tuningMetadata),
            cameraShake: cameraShake
        )
    }

    private static func sealEffect(
        lightFamily: CinematicStageLightFamily,
        sourceIdentifier: String,
        cameraShake: CinematicStageEffectPlan.CameraShake?,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let rings = [Float(0.9), 1.8, 3.0, 4.4].enumerated().map { index, radius in
            tunedArenaRing(
                radius: radius,
                duration: 0.85 + TimeInterval(index) * 0.12,
                scale: 1.9,
                opacity: 0.7,
                colorAlpha: 0.9 - Float(index) * 0.12,
                tuningMetadata: tuningMetadata
            )
        }
        return effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .seal,
            lightFamily: lightFamily,
            arenaRings: rings,
            phaseLightPulse: tunedPhaseLightPulse(intensity: 1_200, duration: 0.8, tuningMetadata: tuningMetadata),
            sparkBursts: [
                tunedSparkBurst(position: [0, 0.5, 0], birthRate: 1_200, colorAlpha: 1, tuningMetadata: tuningMetadata)
            ],
            cameraShake: cameraShake
        )
    }

    private static func victoryEffect(
        lightFamily: CinematicStageLightFamily,
        sourceIdentifier: String,
        cameraShake: CinematicStageEffectPlan.CameraShake?,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.EffectChoreography {
        let rings = (0...6).map { index in
            tunedArenaRing(
                radius: 0.9 + Float(index) * 1.1,
                duration: 1.1,
                scale: 1.35,
                opacity: 0.54,
                colorAlpha: 0.7,
                tuningMetadata: tuningMetadata
            )
        }
        return effect(
            sourceIdentifier: sourceIdentifier,
            arenaEffect: .victory,
            lightFamily: lightFamily,
            arenaRings: rings,
            phaseLightPulse: tunedPhaseLightPulse(intensity: 1_500, duration: 1.0, tuningMetadata: tuningMetadata),
            sparkBursts: [
                tunedSparkBurst(position: [0, 1.3, -0.4], birthRate: 1_600, colorAlpha: 1, tuningMetadata: tuningMetadata)
            ],
            victoryCadence: CinematicStageEffectPlan.VictoryCadence(
                cameraShot: .victory,
                ambientSpawnDelay: clamp(
                    2.2 * TimeInterval(tuningMetadata.victoryCadenceMultiplier),
                    to: CinematicStageEffectPlan.victoryAmbientSpawnDelayRange
                ),
                shouldVolleyActiveEnemies: true,
                shouldRunPortalPulse: true,
                portalLightFamily: lightFamily
            ),
            cameraShake: cameraShake
        )
    }

    private static func stageEffectTuning(
        setDressingPlan: CinematicSetDressingPlan,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStageEffectPlan.StageEffectTuning {
        let pressureLevelIdentifier = setDressingPlan.activityMarker.pressureLevelIdentifier
        let pressureFraction = clamp(
            pressureFraction(for: pressureLevelIdentifier),
            to: CinematicStageEffectPlan.stageEffectPressureRange
        )
        let influenceIntensity = clamp(
            Float(CinematicInfluenceSettings.clampedIntensity(influenceSettings.intensity)),
            to: CinematicStageEffectPlan.stageEffectInfluenceRange
        )
        let influenceFraction = clamp(
            influenceFraction(for: influenceSettings),
            to: CinematicStageEffectPlan.stageEffectInfluenceRange
        )
        let activityLightBoost = clamp(
            setDressingPlan.activityLightBoost,
            to: CinematicStageEffectPlan.stageEffectActivityLightBoostRange
        )
        let activityLightBoostFraction = normalized(
            activityLightBoost,
            in: CinematicStageEffectPlan.stageEffectActivityLightBoostRange
        )
        let runePulseScale = clamp(
            setDressingPlan.runeIntensity.activityPulseScale,
            to: CinematicStageEffectPlan.stageEffectRunePulseScaleRange
        )
        let runeFraction = normalized(
            runePulseScale,
            in: CinematicStageEffectPlan.stageEffectRunePulseScaleRange
        )
        let activityPulseDuration = clamp(
            setDressingPlan.animationCadence.activityPulseDuration,
            to: CinematicStageEffectPlan.stageEffectActivityPulseDurationRange
        )
        let cadenceFraction = clamp(
            Float(
                (CinematicStageEffectPlan.stageEffectActivityPulseDurationRange.upperBound - activityPulseDuration)
                    / (CinematicStageEffectPlan.stageEffectActivityPulseDurationRange.upperBound - CinematicStageEffectPlan.stageEffectActivityPulseDurationRange.lowerBound)
            ),
            to: CinematicStageEffectPlan.stageEffectEnergyRange
        )
        let energy = clamp(
            0.18
                + pressureFraction * 0.3
                + activityLightBoostFraction * 0.16
                + runeFraction * 0.14
                + cadenceFraction * 0.1
                + influenceFraction * 0.28,
            to: CinematicStageEffectPlan.stageEffectEnergyRange
        )
        let ringDurationScale = clamp(
            1.14 - energy * 0.32 + (1 - influenceFraction) * 0.03,
            to: CinematicStageEffectPlan.ringDurationScaleRange
        )
        let ringScaleMultiplier = clamp(
            0.9 + energy * 0.32 + pressureFraction * 0.11 + (runeFraction - 0.5) * 0.1,
            to: CinematicStageEffectPlan.ringScaleMultiplierRange
        )
        let ringOpacityMultiplier = clamp(
            0.92 + energy * 0.2 + activityLightBoostFraction * 0.08,
            to: CinematicStageEffectPlan.ringOpacityMultiplierRange
        )
        let colorAlphaMultiplier = clamp(
            0.92 + energy * 0.12 + pressureFraction * 0.06,
            to: CinematicStageEffectPlan.colorAlphaMultiplierRange
        )
        let pulseIntensityMultiplier = clamp(
            0.86 + energy * 0.28 + influenceFraction * 0.12 + pressureFraction * 0.06,
            to: CinematicStageEffectPlan.pulseIntensityMultiplierRange
        )
        let pulseDurationMultiplier = clamp(
            1.12 - energy * 0.28,
            to: CinematicStageEffectPlan.pulseDurationMultiplierRange
        )
        let sparkBirthRateMultiplier = clamp(
            0.82 + energy * 0.36 + pressureFraction * 0.16 + activityLightBoostFraction * 0.11,
            to: CinematicStageEffectPlan.sparkBirthRateMultiplierRange
        )
        let rawTrailBonus = Int(max(0, ((energy - 0.62) / 0.16)).rounded(.down))
        let historyTrailCount = clamp(
            CinematicStageEffectPlan.historyTrailTuningCountRange.lowerBound + rawTrailBonus,
            to: CinematicStageEffectPlan.historyTrailTuningCountRange
        )
        let cameraShakeMultiplier = clamp(
            0.82 + energy * 0.23 + pressureFraction * 0.15 + influenceFraction * 0.08,
            to: CinematicStageEffectPlan.cameraShakeMultiplierRange
        )
        let cameraShakeDurationMultiplier = clamp(
            0.9 + energy * 0.24,
            to: CinematicStageEffectPlan.cameraShakeDurationMultiplierRange
        )
        let victoryCadenceMultiplier = clamp(
            1.16 - energy * 0.32,
            to: CinematicStageEffectPlan.victoryCadenceMultiplierRange
        )

        return CinematicStageEffectPlan.StageEffectTuning(
            pressureLevelIdentifier: pressureLevelIdentifier,
            pressureFraction: pressureFraction,
            energy: energy,
            influenceStyleIdentifier: influenceSettings.cameraStyle.rawValue,
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            activityLightBoost: activityLightBoost,
            activityLightBoostFraction: activityLightBoostFraction,
            runePulseScale: runePulseScale,
            activityPulseDuration: activityPulseDuration,
            ringDurationScale: ringDurationScale,
            ringScaleMultiplier: ringScaleMultiplier,
            ringOpacityMultiplier: ringOpacityMultiplier,
            colorAlphaMultiplier: colorAlphaMultiplier,
            pulseIntensityMultiplier: pulseIntensityMultiplier,
            pulseDurationMultiplier: pulseDurationMultiplier,
            sparkBirthRateMultiplier: sparkBirthRateMultiplier,
            historyTrailCount: historyTrailCount,
            cameraShakeMultiplier: cameraShakeMultiplier,
            cameraShakeDurationMultiplier: cameraShakeDurationMultiplier,
            victoryCadenceMultiplier: victoryCadenceMultiplier
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

    private static func tunedArenaRing(
        radius: Float,
        duration: TimeInterval,
        scale: Float,
        opacity: Float,
        colorAlpha: Float,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.ArenaRing {
        arenaRing(
            radius: radius,
            duration: duration * TimeInterval(tuningMetadata.ringDurationScale),
            scale: scale * tuningMetadata.ringScaleMultiplier,
            opacity: opacity * tuningMetadata.ringOpacityMultiplier,
            colorAlpha: colorAlpha * tuningMetadata.colorAlphaMultiplier
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

    private static func tunedPhaseLightPulse(
        intensity: Float,
        duration: TimeInterval,
        resetIntensity: Float = 360,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.PhaseLightPulse {
        phaseLightPulse(
            intensity: intensity * tuningMetadata.pulseIntensityMultiplier,
            duration: duration * TimeInterval(tuningMetadata.pulseDurationMultiplier),
            resetIntensity: resetIntensity * tuningMetadata.pulseIntensityMultiplier
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

    private static func tunedSparkBurst(
        position: SIMD3<Float>,
        birthRate: Float,
        colorAlpha: Float,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.SparkBurst {
        sparkBurst(
            position: position,
            birthRate: birthRate * tuningMetadata.sparkBirthRateMultiplier,
            colorAlpha: colorAlpha * tuningMetadata.colorAlphaMultiplier
        )
    }

    private static func historyTrails(
        lightFamily: CinematicStageLightFamily,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> [CinematicStageEffectPlan.HistoryTrail] {
        let trails = [
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
            ),
            CinematicStageEffectPlan.HistoryTrail(
                start: [-4.4, 0.22, 0.2],
                end: [4.1, 0.22, 0.4],
                lightFamily: lightFamily
            ),
            CinematicStageEffectPlan.HistoryTrail(
                start: [-1.7, 0.3, 4.5],
                end: [2.1, 0.3, -4.1],
                lightFamily: lightFamily
            ),
            CinematicStageEffectPlan.HistoryTrail(
                start: [2.7, 0.28, 3.7],
                end: [-2.9, 0.28, -3.5],
                lightFamily: lightFamily
            )
        ]
        return Array(trails.prefix(tuningMetadata.historyTrailCount))
    }

    private static func cameraShake(
        settings: CinematicInfluenceSettings,
        tuningMetadata: CinematicStageEffectPlan.StageEffectTuning
    ) -> CinematicStageEffectPlan.CameraShake {
        let scale = clamp(
            CinematicTuning.cameraShakeScale(settings: settings) * tuningMetadata.cameraShakeMultiplier,
            to: CinematicTuning.cameraShakeScaleRange
        )
        return CinematicStageEffectPlan.CameraShake(
            shouldShake: true,
            duration: clamp(
                0.22 * TimeInterval(scale) * TimeInterval(tuningMetadata.cameraShakeDurationMultiplier),
                to: CinematicStageEffectPlan.cameraShakeDurationRange
            ),
            scale: scale
        )
    }

    private static func pressureFraction(for identifier: String) -> Float {
        switch RepositoryWorktreePressureLevel(rawValue: identifier) {
        case .clean:
            return 0.08
        case .light:
            return 0.34
        case .moderate:
            return 0.66
        case .heavy:
            return 1
        case nil:
            return 0.08
        }
    }

    private static func influenceFraction(for settings: CinematicInfluenceSettings) -> Float {
        let intensity = Float(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        let base: Float
        let span: Float
        switch settings.cameraStyle {
        case .steady:
            base = 0.1
            span = 0.2
        case .follow:
            base = 0.38
            span = 0.26
        case .dramatic:
            base = 0.68
            span = 0.32
        }
        return clamp(base + intensity * span, to: CinematicStageEffectPlan.stageEffectInfluenceRange)
    }

    private static func normalized(_ value: Float, in range: ClosedRange<Float>) -> Float {
        guard range.upperBound > range.lowerBound else { return 0 }
        return clamp((value - range.lowerBound) / (range.upperBound - range.lowerBound), to: 0...1)
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

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
