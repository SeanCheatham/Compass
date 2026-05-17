import Foundation

struct CinematicStageAtmospherePlan: Equatable {
    static let atmospherePressureRange: ClosedRange<Float> = 0...1
    static let atmosphereInfluenceRange: ClosedRange<Float> = 0...1
    static let atmosphereEnergyRange: ClosedRange<Float> = 0...1
    static let pressureHaloRadiusRange: ClosedRange<Float> = 5.4...12.4
    static let pressureHaloOpacityRange: ClosedRange<Float> = 0...0.38
    static let pressureHaloScaleRange: ClosedRange<Float> = 0.88...1.32
    static let atmosphericPulseCadenceRange: ClosedRange<TimeInterval> = 1.35...4.8
    static let atmosphericPulseAmplitudeRange: ClosedRange<Float> = 0...0.18
    static let atmosphericPulseOpacityRange: ClosedRange<Float> = 0...0.3
    static let phaseLightPressureBoostRange: ClosedRange<Float> = 0...260
    static let rimLightPressureBoostRange: ClosedRange<Float> = 0...420
    static let colorComponentRange: ClosedRange<Float> = 0...1
    static let colorAlphaRange: ClosedRange<Float> = 0...1
    static let backdropTintOpacityRange: ClosedRange<Float> = 0...0.22
    static let floorTintOpacityRange: ClosedRange<Float> = 0...0.3
    static let surfaceTintBlendRange: ClosedRange<Float> = 0...0.42

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
    var pressureHalo: PressureHalo
    var atmosphericPulse: AtmosphericPulse
    var pressureLighting: PressureLighting
    var backdropTint: SurfaceTint
    var floorTint: SurfaceTint

    struct PressureHalo: Equatable {
        var radius: Float
        var opacity: Float
        var scale: Float
        var colorAlpha: Float

        var identifier: String {
            [
                "r\(CinematicStageAtmospherePlanner.fixed(radius))",
                "o\(CinematicStageAtmospherePlanner.fixed(opacity))",
                "s\(CinematicStageAtmospherePlanner.fixed(scale))",
                "a\(CinematicStageAtmospherePlanner.fixed(colorAlpha))"
            ].joined(separator: "/")
        }
    }

    struct AtmosphericPulse: Equatable {
        var cadence: TimeInterval
        var amplitude: Float
        var opacity: Float

        var identifier: String {
            [
                "c\(CinematicStageAtmospherePlanner.fixed(cadence))",
                "a\(CinematicStageAtmospherePlanner.fixed(amplitude))",
                "o\(CinematicStageAtmospherePlanner.fixed(opacity))"
            ].joined(separator: "/")
        }
    }

    struct PressureLighting: Equatable {
        var phaseLightPressureBoost: Float
        var rimLightPressureBoost: Float
        var colorAlpha: Float

        var identifier: String {
            [
                "phase\(CinematicStageAtmospherePlanner.fixed(phaseLightPressureBoost))",
                "rim\(CinematicStageAtmospherePlanner.fixed(rimLightPressureBoost))",
                "a\(CinematicStageAtmospherePlanner.fixed(colorAlpha))"
            ].joined(separator: "/")
        }
    }

    struct SurfaceTint: Equatable {
        var red: Float
        var green: Float
        var blue: Float
        var opacity: Float
        var blendFraction: Float

        var identifier: String {
            [
                "rgb\(CinematicStageAtmospherePlanner.fixed(red)),\(CinematicStageAtmospherePlanner.fixed(green)),\(CinematicStageAtmospherePlanner.fixed(blue))",
                "o\(CinematicStageAtmospherePlanner.fixed(opacity))",
                "b\(CinematicStageAtmospherePlanner.fixed(blendFraction))"
            ].joined(separator: "/")
        }
    }
}

enum CinematicStageAtmospherePlanner {
    static func plan(
        beat: CinematicStageBeat,
        setDressingPlan: CinematicSetDressingPlan,
        stageEffectTuning: CinematicStageEffectPlan.StageEffectTuning,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStageAtmospherePlan {
        let activityIdentifier = setDressingPlan.activityMarker.eventKindIdentifier
        let isIdleUnavailable = beat.kind == .idle && activityIdentifier == CinematicActivityEventKind.unavailable.rawValue
        let pressureFraction = isIdleUnavailable
            ? 0
            : clamp(stageEffectTuning.pressureFraction, to: CinematicStageAtmospherePlan.atmospherePressureRange)
        let influenceIntensity = clamp(
            Float(CinematicInfluenceSettings.clampedIntensity(influenceSettings.intensity)),
            to: CinematicStageAtmospherePlan.atmosphereInfluenceRange
        )
        let influenceFraction = clamp(
            stageEffectTuning.influenceFraction,
            to: CinematicStageAtmospherePlan.atmosphereInfluenceRange
        )
        let activityLightFraction = normalized(
            stageEffectTuning.activityLightBoost,
            in: CinematicStageEffectPlan.stageEffectActivityLightBoostRange
        )
        let phaseFraction = phaseEnergy(for: beat.kind)
        let energy = isIdleUnavailable
            ? 0
            : clamp(
                0.08
                    + pressureFraction * 0.32
                    + stageEffectTuning.energy * 0.28
                    + influenceFraction * 0.18
                    + phaseFraction * 0.14
                    + activityLightFraction * 0.08,
                to: CinematicStageAtmospherePlan.atmosphereEnergyRange
            )

        let halo = pressureHalo(
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            energy: energy,
            isIdleUnavailable: isIdleUnavailable
        )
        let pulse = atmosphericPulse(
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            energy: energy,
            isIdleUnavailable: isIdleUnavailable
        )
        let lighting = pressureLighting(
            beat: beat,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            activityLightFraction: activityLightFraction,
            energy: energy,
            isIdleUnavailable: isIdleUnavailable
        )
        let backdropTint = surfaceTint(
            phaseLightFamily: beat.lightFamily,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            activityLightFraction: activityLightFraction,
            energy: energy,
            opacityRange: CinematicStageAtmospherePlan.backdropTintOpacityRange,
            baseOpacity: 0.024,
            pressureOpacity: 0.07,
            energyOpacity: 0.052,
            blendBase: 0.055,
            pressureBlend: 0.22,
            influenceBlend: 0.1,
            isIdleUnavailable: isIdleUnavailable
        )
        let floorTint = surfaceTint(
            phaseLightFamily: beat.lightFamily,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            activityLightFraction: activityLightFraction,
            energy: energy,
            opacityRange: CinematicStageAtmospherePlan.floorTintOpacityRange,
            baseOpacity: 0.03,
            pressureOpacity: 0.12,
            energyOpacity: 0.07,
            blendBase: 0.08,
            pressureBlend: 0.27,
            influenceBlend: 0.06 + activityLightFraction * 0.08,
            isIdleUnavailable: isIdleUnavailable
        )

        let identifier = [
            "beat:\(beat.identifier)",
            "phase:\(beat.kindIdentifier)",
            "activity:\(activityIdentifier)",
            "pressure:\(stageEffectTuning.pressureLevelIdentifier):\(fixed(pressureFraction))",
            "energy:\(fixed(energy))",
            "influence:\(influenceSettings.cameraStyle.rawValue):\(fixed(influenceIntensity)):\(fixed(influenceFraction))",
            "halo:\(halo.identifier)",
            "pulse:\(pulse.identifier)",
            "light:\(lighting.identifier)",
            "backdrop:\(backdropTint.identifier)",
            "floor:\(floorTint.identifier)"
        ].joined(separator: "|")

        return CinematicStageAtmospherePlan(
            identifier: identifier,
            beatIdentifier: beat.identifier,
            phaseIdentifier: beat.kindIdentifier,
            activityIdentifier: activityIdentifier,
            pressureLevelIdentifier: stageEffectTuning.pressureLevelIdentifier,
            influenceStyleIdentifier: influenceSettings.cameraStyle.rawValue,
            influenceIntensity: influenceIntensity,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            energy: energy,
            pressureHalo: halo,
            atmosphericPulse: pulse,
            pressureLighting: lighting,
            backdropTint: backdropTint,
            floorTint: floorTint
        )
    }

    static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    static func fixed(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }

    private static func pressureHalo(
        pressureFraction: Float,
        influenceFraction: Float,
        energy: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStageAtmospherePlan.PressureHalo {
        CinematicStageAtmospherePlan.PressureHalo(
            radius: clamp(
                5.7 + pressureFraction * 4.65 + influenceFraction * 0.7 + energy * 0.95,
                to: CinematicStageAtmospherePlan.pressureHaloRadiusRange
            ),
            opacity: isIdleUnavailable ? 0 : clamp(
                0.035 + pressureFraction * 0.17 + energy * 0.12,
                to: CinematicStageAtmospherePlan.pressureHaloOpacityRange
            ),
            scale: clamp(
                0.94 + pressureFraction * 0.16 + influenceFraction * 0.12 + energy * 0.04,
                to: CinematicStageAtmospherePlan.pressureHaloScaleRange
            ),
            colorAlpha: isIdleUnavailable ? 0 : clamp(
                0.22 + pressureFraction * 0.42 + energy * 0.18,
                to: CinematicStageAtmospherePlan.colorAlphaRange
            )
        )
    }

    private static func atmosphericPulse(
        pressureFraction: Float,
        influenceFraction: Float,
        energy: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStageAtmospherePlan.AtmosphericPulse {
        CinematicStageAtmospherePlan.AtmosphericPulse(
            cadence: isIdleUnavailable
                ? CinematicStageAtmospherePlan.atmosphericPulseCadenceRange.upperBound
                : clamp(
                    4.65 - TimeInterval(energy * 2.1 + influenceFraction * 0.45 + pressureFraction * 0.4),
                    to: CinematicStageAtmospherePlan.atmosphericPulseCadenceRange
                ),
            amplitude: isIdleUnavailable ? 0 : clamp(
                0.028 + energy * 0.08 + pressureFraction * 0.045,
                to: CinematicStageAtmospherePlan.atmosphericPulseAmplitudeRange
            ),
            opacity: isIdleUnavailable ? 0 : clamp(
                0.028 + pressureFraction * 0.11 + energy * 0.08,
                to: CinematicStageAtmospherePlan.atmosphericPulseOpacityRange
            )
        )
    }

    private static func pressureLighting(
        beat: CinematicStageBeat,
        pressureFraction: Float,
        influenceFraction: Float,
        activityLightFraction: Float,
        energy: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStageAtmospherePlan.PressureLighting {
        let failureBoost: Float = beat.kind == .failed ? 48 : 0
        return CinematicStageAtmospherePlan.PressureLighting(
            phaseLightPressureBoost: isIdleUnavailable ? 0 : clamp(
                pressureFraction * 150 + energy * 60 + activityLightFraction * 70 + failureBoost,
                to: CinematicStageAtmospherePlan.phaseLightPressureBoostRange
            ),
            rimLightPressureBoost: isIdleUnavailable ? 0 : clamp(
                pressureFraction * 260 + influenceFraction * 90 + energy * 80,
                to: CinematicStageAtmospherePlan.rimLightPressureBoostRange
            ),
            colorAlpha: isIdleUnavailable ? 0 : clamp(
                0.18 + pressureFraction * 0.5 + energy * 0.18,
                to: CinematicStageAtmospherePlan.colorAlphaRange
            )
        )
    }

    private static func surfaceTint(
        phaseLightFamily: CinematicStageLightFamily,
        pressureFraction: Float,
        influenceFraction: Float,
        activityLightFraction: Float,
        energy: Float,
        opacityRange: ClosedRange<Float>,
        baseOpacity: Float,
        pressureOpacity: Float,
        energyOpacity: Float,
        blendBase: Float,
        pressureBlend: Float,
        influenceBlend: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStageAtmospherePlan.SurfaceTint {
        let opacity = isIdleUnavailable ? 0 : clamp(
            baseOpacity + pressureFraction * pressureOpacity + energy * energyOpacity + activityLightFraction * 0.035,
            to: opacityRange
        )
        let blendFraction = isIdleUnavailable ? 0 : clamp(
            blendBase + pressureFraction * pressureBlend + influenceFraction * influenceBlend,
            to: CinematicStageAtmospherePlan.surfaceTintBlendRange
        )
        let color = mix(
            color(for: phaseLightFamily),
            color(for: .pressure),
            blendFraction
        )

        return CinematicStageAtmospherePlan.SurfaceTint(
            red: clamp(color.x, to: CinematicStageAtmospherePlan.colorComponentRange),
            green: clamp(color.y, to: CinematicStageAtmospherePlan.colorComponentRange),
            blue: clamp(color.z, to: CinematicStageAtmospherePlan.colorComponentRange),
            opacity: opacity,
            blendFraction: blendFraction
        )
    }

    private static func phaseEnergy(for kind: CinematicStageBeatKind) -> Float {
        switch kind {
        case .idle, .paused, .cancelled:
            return 0
        case .planning:
            return 0.24
        case .developing:
            return 0.48
        case .verifying:
            return 0.62
        case .succeeded:
            return 0.74
        case .failed:
            return 0.86
        }
    }

    private static func color(for lightFamily: CinematicStageLightFamily) -> SIMD3<Float> {
        switch lightFamily {
        case .scan:
            return [0.18, 0.64, 1.0]
        case .shell:
            return [0.58, 0.44, 1.0]
        case .edit:
            return [0.15, 0.96, 0.72]
        case .git:
            return [0.46, 0.95, 0.3]
        case .verify:
            return [1.0, 0.72, 0.2]
        case .insight:
            return [0.86, 0.52, 1.0]
        case .lifecycle:
            return [0.32, 0.84, 1.0]
        case .pressure:
            return [1.0, 0.22, 0.18]
        case .failure:
            return [1.0, 0.12, 0.18]
        }
    }

    private static func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * clamp(t, to: 0...1)
    }

    private static func normalized(_ value: Float, in range: ClosedRange<Float>) -> Float {
        guard range.upperBound > range.lowerBound else { return 0 }
        return clamp((value - range.lowerBound) / (range.upperBound - range.lowerBound), to: 0...1)
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
