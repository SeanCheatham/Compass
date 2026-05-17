import Foundation

enum CinematicStagePhasePolishPosture: String, CaseIterable, Equatable {
    case neutral
    case planning
    case editing
    case sealing
    case archival
    case fracture
    case healing
}

struct CinematicStagePhasePolishPlan: Equatable {
    static let poseIntensityRange: ClosedRange<Float> = 0...1
    static let staffPitchRange: ClosedRange<Float> = -0.62...0.16
    static let staffRollRange: ClosedRange<Float> = -0.62...0.32
    static let armLiftRange: ClosedRange<Float> = -1.0...1.05
    static let headTiltRange: ClosedRange<Float> = -0.18...0.16
    static let staffOrbScaleRange: ClosedRange<Float> = 0.72...1.9
    static let staffOrbEmissionRange: ClosedRange<Float> = 0...1
    static let staffOrbPulseAmplitudeRange: ClosedRange<Float> = 0...0.24
    static let sigilOrbitRadiusRange: ClosedRange<Float> = 0...0.46
    static let sigilSealEmphasisRange: ClosedRange<Float> = 0...1
    static let sigilVictoryEmphasisRange: ClosedRange<Float> = 0...1
    static let sigilPulseAmplitudeRange: ClosedRange<Float> = 0...0.18
    static let portalApertureRange: ClosedRange<Float> = 0...1
    static let portalScaleRange: ClosedRange<Float> = 0.72...2.4
    static let portalOpacityRange: ClosedRange<Float> = 0...0.62
    static let portalPulseAmplitudeRange: ClosedRange<Float> = 0...0.22
    static let backdropApertureRange: ClosedRange<Float> = 0...1
    static let backdropOpacityBoostRange: ClosedRange<Float> = 0...0.18
    static let fractureOpacityRange: ClosedRange<Float> = 0...0.82
    static let fractureSpreadRange: ClosedRange<Float> = 0...1.5
    static let healingOpacityRange: ClosedRange<Float> = 0...0.76
    static let poseCadenceRange: ClosedRange<TimeInterval> = 1.1...5.8
    static let orbPulseCadenceRange: ClosedRange<TimeInterval> = 1.0...4.8
    static let sigilOrbitCadenceRange: ClosedRange<TimeInterval> = 2.2...8.0
    static let fractureCadenceRange: ClosedRange<TimeInterval> = 1.2...5.5

    var identifier: String
    var beatIdentifier: String
    var stageEffectTuningIdentifier: String
    var atmosphereIdentifier: String
    var phaseIdentifier: String
    var activityIdentifier: String
    var influenceIdentifier: String
    var posture: CinematicStagePhasePolishPosture
    var wizardPose: WizardPose
    var staffOrb: StaffOrb
    var sigilEmphasis: SigilEmphasis
    var portalBackdrop: PortalBackdropAperture
    var fractureRecovery: FractureRecoveryAccent
    var cadence: PhaseCadence

    var postureIdentifier: String { posture.rawValue }

    struct WizardPose: Equatable {
        var posture: CinematicStagePhasePolishPosture
        var poseIntensity: Float
        var staffPitch: Float
        var staffRoll: Float
        var leftArmLift: Float
        var rightArmLift: Float
        var headTilt: Float

        var identifier: String {
            [
                posture.rawValue,
                "i\(CinematicStagePhasePolishPlanner.fixed(poseIntensity))",
                "staff\(CinematicStagePhasePolishPlanner.fixed(staffPitch)),\(CinematicStagePhasePolishPlanner.fixed(staffRoll))",
                "arms\(CinematicStagePhasePolishPlanner.fixed(leftArmLift)),\(CinematicStagePhasePolishPlanner.fixed(rightArmLift))",
                "head\(CinematicStagePhasePolishPlanner.fixed(headTilt))"
            ].joined(separator: "/")
        }
    }

    struct StaffOrb: Equatable {
        var lightFamily: CinematicStageLightFamily
        var scale: Float
        var emission: Float
        var pulseAmplitude: Float

        var identifier: String {
            [
                lightFamily.rawValue,
                "s\(CinematicStagePhasePolishPlanner.fixed(scale))",
                "e\(CinematicStagePhasePolishPlanner.fixed(emission))",
                "p\(CinematicStagePhasePolishPlanner.fixed(pulseAmplitude))"
            ].joined(separator: "/")
        }
    }

    struct SigilEmphasis: Equatable {
        var orbitRadius: Float
        var sealEmphasis: Float
        var victoryEmphasis: Float
        var pulseAmplitude: Float

        var identifier: String {
            [
                "orbit\(CinematicStagePhasePolishPlanner.fixed(orbitRadius))",
                "seal\(CinematicStagePhasePolishPlanner.fixed(sealEmphasis))",
                "victory\(CinematicStagePhasePolishPlanner.fixed(victoryEmphasis))",
                "pulse\(CinematicStagePhasePolishPlanner.fixed(pulseAmplitude))"
            ].joined(separator: "/")
        }
    }

    struct PortalBackdropAperture: Equatable {
        var lightFamily: CinematicStageLightFamily
        var portalAperture: Float
        var portalScale: Float
        var portalOpacity: Float
        var portalPulseAmplitude: Float
        var backdropAperture: Float
        var backdropOpacityBoost: Float

        var identifier: String {
            [
                lightFamily.rawValue,
                "portal\(CinematicStagePhasePolishPlanner.fixed(portalAperture))",
                "scale\(CinematicStagePhasePolishPlanner.fixed(portalScale))",
                "opacity\(CinematicStagePhasePolishPlanner.fixed(portalOpacity))",
                "pulse\(CinematicStagePhasePolishPlanner.fixed(portalPulseAmplitude))",
                "backdrop\(CinematicStagePhasePolishPlanner.fixed(backdropAperture))",
                "boost\(CinematicStagePhasePolishPlanner.fixed(backdropOpacityBoost))"
            ].joined(separator: "/")
        }
    }

    struct FractureRecoveryAccent: Equatable {
        var lightFamily: CinematicStageLightFamily
        var fractureOpacity: Float
        var fractureSpread: Float
        var healingOpacity: Float

        var identifier: String {
            [
                lightFamily.rawValue,
                "fracture\(CinematicStagePhasePolishPlanner.fixed(fractureOpacity))",
                "spread\(CinematicStagePhasePolishPlanner.fixed(fractureSpread))",
                "heal\(CinematicStagePhasePolishPlanner.fixed(healingOpacity))"
            ].joined(separator: "/")
        }
    }

    struct PhaseCadence: Equatable {
        var poseCadence: TimeInterval
        var orbPulseCadence: TimeInterval
        var sigilOrbitCadence: TimeInterval
        var fractureCadence: TimeInterval

        var identifier: String {
            [
                "pose\(CinematicStagePhasePolishPlanner.fixed(poseCadence))",
                "orb\(CinematicStagePhasePolishPlanner.fixed(orbPulseCadence))",
                "sigil\(CinematicStagePhasePolishPlanner.fixed(sigilOrbitCadence))",
                "fracture\(CinematicStagePhasePolishPlanner.fixed(fractureCadence))"
            ].joined(separator: "/")
        }
    }
}

enum CinematicStagePhasePolishPlanner {
    static func plan(
        beat: CinematicStageBeat,
        stageEffectTuning: CinematicStageEffectPlan.StageEffectTuning,
        atmospherePlan: CinematicStageAtmospherePlan,
        activityMotif: CinematicActivityMotif,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicStagePhasePolishPlan {
        let isIdleUnavailable = beat.kind == .idle && activityMotif.eventKind == .unavailable
        let posture = posture(for: beat, activityMotif: activityMotif)
        let pressureFraction = isIdleUnavailable
            ? 0
            : clamp(stageEffectTuning.pressureFraction, to: CinematicStageEffectPlan.stageEffectPressureRange)
        let influenceIntensity = clamp(
            Float(CinematicInfluenceSettings.clampedIntensity(influenceSettings.intensity)),
            to: CinematicStageEffectPlan.stageEffectInfluenceRange
        )
        let influenceFraction = clamp(
            stageEffectTuning.influenceFraction,
            to: CinematicStageEffectPlan.stageEffectInfluenceRange
        )
        let activityLoad = activityLoadFraction(for: activityProfile)
        let activityUrgency = isIdleUnavailable ? 0 : urgency(for: activityMotif.eventKind)
        let postureEnergy = energy(for: posture)
        let energy = isIdleUnavailable
            ? 0
            : clamp(
                stageEffectTuning.energy * 0.42
                    + atmospherePlan.energy * 0.34
                    + postureEnergy * 0.14
                    + activityLoad * 0.1,
                to: 0...1
            )

        let wizardPose = wizardPose(
            posture: posture,
            energy: energy,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            activityUrgency: activityUrgency,
            isIdleUnavailable: isIdleUnavailable
        )
        let staffOrb = staffOrb(
            beat: beat,
            posture: posture,
            activityMotif: activityMotif,
            energy: energy,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            activityUrgency: activityUrgency,
            isIdleUnavailable: isIdleUnavailable
        )
        let sigilEmphasis = sigilEmphasis(
            posture: posture,
            energy: energy,
            pressureFraction: pressureFraction,
            influenceFraction: influenceFraction,
            activityUrgency: activityUrgency,
            isIdleUnavailable: isIdleUnavailable
        )
        let portalBackdrop = portalBackdrop(
            beat: beat,
            posture: posture,
            energy: energy,
            atmosphereEnergy: atmospherePlan.energy,
            influenceFraction: influenceFraction,
            activityUrgency: activityUrgency,
            isIdleUnavailable: isIdleUnavailable
        )
        let fractureRecovery = fractureRecovery(
            posture: posture,
            pressureFraction: pressureFraction,
            energy: energy,
            activityUrgency: activityUrgency,
            isIdleUnavailable: isIdleUnavailable
        )
        let cadence = phaseCadence(
            posture: posture,
            energy: energy,
            influenceIntensity: influenceIntensity,
            isIdleUnavailable: isIdleUnavailable
        )
        let influenceIdentifier = [
            influenceSettings.cameraStyle.rawValue,
            fixed(influenceIntensity),
            fixed(influenceFraction)
        ].joined(separator: "|")
        let identifier = [
            "beat:\(beat.identifier)",
            "effect:\(stageEffectTuning.identifier)",
            "atmosphere:\(atmospherePlan.identifier)",
            "phase:\(beat.kindIdentifier)",
            "activity:\(activityMotif.eventKind.rawValue)",
            "posture:\(posture.rawValue)",
            "pose:\(wizardPose.identifier)",
            "orb:\(staffOrb.identifier)",
            "sigil:\(sigilEmphasis.identifier)",
            "portal:\(portalBackdrop.identifier)",
            "fracture:\(fractureRecovery.identifier)",
            "cadence:\(cadence.identifier)",
            "influence:\(influenceIdentifier)"
        ].joined(separator: "|")

        return CinematicStagePhasePolishPlan(
            identifier: identifier,
            beatIdentifier: beat.identifier,
            stageEffectTuningIdentifier: stageEffectTuning.identifier,
            atmosphereIdentifier: atmospherePlan.identifier,
            phaseIdentifier: beat.kindIdentifier,
            activityIdentifier: activityMotif.eventKind.rawValue,
            influenceIdentifier: influenceIdentifier,
            posture: posture,
            wizardPose: wizardPose,
            staffOrb: staffOrb,
            sigilEmphasis: sigilEmphasis,
            portalBackdrop: portalBackdrop,
            fractureRecovery: fractureRecovery,
            cadence: cadence
        )
    }

    static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    static func fixed(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }

    private static func posture(
        for beat: CinematicStageBeat,
        activityMotif: CinematicActivityMotif
    ) -> CinematicStagePhasePolishPosture {
        switch activityMotif.eventKind {
        case .recovery:
            return .healing
        case .commit, .success:
            return .archival
        case .conflicted, .failure:
            return .fracture
        case .unavailable, .clean, .dirty:
            break
        }

        switch beat.kind {
        case .planning:
            return .planning
        case .developing:
            return .editing
        case .verifying:
            return .sealing
        case .succeeded:
            return .archival
        case .failed:
            return .fracture
        case .idle, .paused, .cancelled:
            return .neutral
        }
    }

    private static func wizardPose(
        posture: CinematicStagePhasePolishPosture,
        energy: Float,
        pressureFraction: Float,
        influenceFraction: Float,
        activityUrgency: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStagePhasePolishPlan.WizardPose {
        let base = basePose(for: posture)
        let intensity = isIdleUnavailable ? 0 : clamp(
            base.intensity + energy * 0.14 + pressureFraction * 0.08 + influenceFraction * 0.04 + activityUrgency * 0.03,
            to: CinematicStagePhasePolishPlan.poseIntensityRange
        )
        let liftBoost = intensity * 0.08
        return CinematicStagePhasePolishPlan.WizardPose(
            posture: posture,
            poseIntensity: intensity,
            staffPitch: clamp(base.staffPitch - intensity * 0.04, to: CinematicStagePhasePolishPlan.staffPitchRange),
            staffRoll: clamp(base.staffRoll - pressureFraction * 0.04 + influenceFraction * 0.03, to: CinematicStagePhasePolishPlan.staffRollRange),
            leftArmLift: clamp(base.leftArmLift + liftBoost, to: CinematicStagePhasePolishPlan.armLiftRange),
            rightArmLift: clamp(base.rightArmLift - liftBoost, to: CinematicStagePhasePolishPlan.armLiftRange),
            headTilt: clamp(base.headTilt - pressureFraction * 0.025 + influenceFraction * 0.018, to: CinematicStagePhasePolishPlan.headTiltRange)
        )
    }

    private static func staffOrb(
        beat: CinematicStageBeat,
        posture: CinematicStagePhasePolishPosture,
        activityMotif: CinematicActivityMotif,
        energy: Float,
        pressureFraction: Float,
        influenceFraction: Float,
        activityUrgency: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStagePhasePolishPlan.StaffOrb {
        let base = baseOrb(for: posture)
        return CinematicStagePhasePolishPlan.StaffOrb(
            lightFamily: staffLightFamily(
                beat: beat,
                posture: posture,
                activityMotif: activityMotif
            ),
            scale: isIdleUnavailable ? base.scale : clamp(
                base.scale + energy * 0.18 + influenceFraction * 0.08,
                to: CinematicStagePhasePolishPlan.staffOrbScaleRange
            ),
            emission: isIdleUnavailable ? 0 : clamp(
                base.emission + energy * 0.22 + pressureFraction * 0.12,
                to: CinematicStagePhasePolishPlan.staffOrbEmissionRange
            ),
            pulseAmplitude: isIdleUnavailable ? 0 : clamp(
                0.035 + energy * 0.09 + activityUrgency * 0.04,
                to: CinematicStagePhasePolishPlan.staffOrbPulseAmplitudeRange
            )
        )
    }

    private static func sigilEmphasis(
        posture: CinematicStagePhasePolishPosture,
        energy: Float,
        pressureFraction: Float,
        influenceFraction: Float,
        activityUrgency: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStagePhasePolishPlan.SigilEmphasis {
        guard !isIdleUnavailable else {
            return CinematicStagePhasePolishPlan.SigilEmphasis(
                orbitRadius: 0,
                sealEmphasis: 0,
                victoryEmphasis: 0,
                pulseAmplitude: 0
            )
        }

        let base = baseSigil(for: posture)
        return CinematicStagePhasePolishPlan.SigilEmphasis(
            orbitRadius: clamp(
                base.orbitRadius + influenceFraction * 0.055 + activityUrgency * 0.025,
                to: CinematicStagePhasePolishPlan.sigilOrbitRadiusRange
            ),
            sealEmphasis: clamp(
                base.sealEmphasis + energy * 0.11 + pressureFraction * 0.035,
                to: CinematicStagePhasePolishPlan.sigilSealEmphasisRange
            ),
            victoryEmphasis: clamp(
                base.victoryEmphasis + (posture == .archival ? energy * 0.16 : 0),
                to: CinematicStagePhasePolishPlan.sigilVictoryEmphasisRange
            ),
            pulseAmplitude: clamp(
                0.025 + energy * 0.06 + base.sealEmphasis * 0.04 + base.victoryEmphasis * 0.05,
                to: CinematicStagePhasePolishPlan.sigilPulseAmplitudeRange
            )
        )
    }

    private static func portalBackdrop(
        beat: CinematicStageBeat,
        posture: CinematicStagePhasePolishPosture,
        energy: Float,
        atmosphereEnergy: Float,
        influenceFraction: Float,
        activityUrgency: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStagePhasePolishPlan.PortalBackdropAperture {
        guard !isIdleUnavailable else {
            return CinematicStagePhasePolishPlan.PortalBackdropAperture(
                lightFamily: beat.lightFamily,
                portalAperture: 0,
                portalScale: CinematicStagePhasePolishPlan.portalScaleRange.lowerBound,
                portalOpacity: 0,
                portalPulseAmplitude: 0,
                backdropAperture: 0,
                backdropOpacityBoost: 0
            )
        }

        let base = basePortal(for: posture)
        let portalAperture = clamp(
            base.aperture + energy * 0.08 + activityUrgency * 0.045,
            to: CinematicStagePhasePolishPlan.portalApertureRange
        )
        let backdropAperture = clamp(
            base.backdrop + atmosphereEnergy * 0.24 + influenceFraction * 0.08,
            to: CinematicStagePhasePolishPlan.backdropApertureRange
        )
        return CinematicStagePhasePolishPlan.PortalBackdropAperture(
            lightFamily: portalLightFamily(beat: beat, posture: posture),
            portalAperture: portalAperture,
            portalScale: clamp(
                0.72 + portalAperture * 1.5,
                to: CinematicStagePhasePolishPlan.portalScaleRange
            ),
            portalOpacity: clamp(
                portalAperture * 0.56,
                to: CinematicStagePhasePolishPlan.portalOpacityRange
            ),
            portalPulseAmplitude: clamp(
                0.025 + portalAperture * 0.11 + energy * 0.035,
                to: CinematicStagePhasePolishPlan.portalPulseAmplitudeRange
            ),
            backdropAperture: backdropAperture,
            backdropOpacityBoost: clamp(
                backdropAperture * 0.16,
                to: CinematicStagePhasePolishPlan.backdropOpacityBoostRange
            )
        )
    }

    private static func fractureRecovery(
        posture: CinematicStagePhasePolishPosture,
        pressureFraction: Float,
        energy: Float,
        activityUrgency: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStagePhasePolishPlan.FractureRecoveryAccent {
        guard !isIdleUnavailable else {
            return CinematicStagePhasePolishPlan.FractureRecoveryAccent(
                lightFamily: .failure,
                fractureOpacity: 0,
                fractureSpread: 0,
                healingOpacity: 0
            )
        }

        let fractureOpacity: Float
        let healingOpacity: Float
        switch posture {
        case .fracture:
            fractureOpacity = 0.48 + pressureFraction * 0.22 + activityUrgency * 0.12
            healingOpacity = 0
        case .healing:
            fractureOpacity = 0.14 + pressureFraction * 0.08
            healingOpacity = 0.48 + energy * 0.2 + activityUrgency * 0.08
        case .archival:
            fractureOpacity = 0
            healingOpacity = 0.08 + energy * 0.08
        case .neutral, .planning, .editing, .sealing:
            fractureOpacity = 0
            healingOpacity = 0
        }

        return CinematicStagePhasePolishPlan.FractureRecoveryAccent(
            lightFamily: posture == .healing ? .verify : .failure,
            fractureOpacity: clamp(fractureOpacity, to: CinematicStagePhasePolishPlan.fractureOpacityRange),
            fractureSpread: clamp(
                posture == .fracture || posture == .healing ? 0.72 + pressureFraction * 0.5 + energy * 0.18 : 0,
                to: CinematicStagePhasePolishPlan.fractureSpreadRange
            ),
            healingOpacity: clamp(healingOpacity, to: CinematicStagePhasePolishPlan.healingOpacityRange)
        )
    }

    private static func phaseCadence(
        posture: CinematicStagePhasePolishPosture,
        energy: Float,
        influenceIntensity: Float,
        isIdleUnavailable: Bool
    ) -> CinematicStagePhasePolishPlan.PhaseCadence {
        guard !isIdleUnavailable else {
            return CinematicStagePhasePolishPlan.PhaseCadence(
                poseCadence: CinematicStagePhasePolishPlan.poseCadenceRange.upperBound,
                orbPulseCadence: CinematicStagePhasePolishPlan.orbPulseCadenceRange.upperBound,
                sigilOrbitCadence: CinematicStagePhasePolishPlan.sigilOrbitCadenceRange.upperBound,
                fractureCadence: CinematicStagePhasePolishPlan.fractureCadenceRange.upperBound
            )
        }

        let base = baseCadence(for: posture)
        return CinematicStagePhasePolishPlan.PhaseCadence(
            poseCadence: clamp(
                base.pose - TimeInterval(energy * 0.7 + influenceIntensity * 0.18),
                to: CinematicStagePhasePolishPlan.poseCadenceRange
            ),
            orbPulseCadence: clamp(
                base.orb - TimeInterval(energy * 0.48),
                to: CinematicStagePhasePolishPlan.orbPulseCadenceRange
            ),
            sigilOrbitCadence: clamp(
                base.sigil - TimeInterval(energy * 0.95 + influenceIntensity * 0.25),
                to: CinematicStagePhasePolishPlan.sigilOrbitCadenceRange
            ),
            fractureCadence: clamp(
                base.fracture - TimeInterval(energy * 0.45),
                to: CinematicStagePhasePolishPlan.fractureCadenceRange
            )
        )
    }

    private static func basePose(
        for posture: CinematicStagePhasePolishPosture
    ) -> (intensity: Float, staffPitch: Float, staffRoll: Float, leftArmLift: Float, rightArmLift: Float, headTilt: Float) {
        switch posture {
        case .neutral:
            return (0, 0, 0.18, 0.44, -0.34, 0)
        case .planning:
            return (0.28, -0.1, 0.06, 0.46, -0.38, -0.02)
        case .editing:
            return (0.58, -0.28, -0.42, 0.64, -0.74, -0.06)
        case .sealing:
            return (0.76, -0.48, -0.18, 0.92, -0.86, -0.09)
        case .archival:
            return (0.68, -0.22, 0.14, 0.78, -0.58, 0.04)
        case .fracture:
            return (0.9, -0.58, -0.52, 1.0, -0.96, -0.14)
        case .healing:
            return (0.74, -0.38, 0.22, 0.82, -0.7, -0.03)
        }
    }

    private static func baseOrb(
        for posture: CinematicStagePhasePolishPosture
    ) -> (scale: Float, emission: Float) {
        switch posture {
        case .neutral:
            return (0.82, 0)
        case .planning:
            return (0.98, 0.2)
        case .editing:
            return (1.16, 0.38)
        case .sealing:
            return (1.3, 0.5)
        case .archival:
            return (1.42, 0.58)
        case .fracture:
            return (1.5, 0.72)
        case .healing:
            return (1.36, 0.62)
        }
    }

    private static func baseSigil(
        for posture: CinematicStagePhasePolishPosture
    ) -> (orbitRadius: Float, sealEmphasis: Float, victoryEmphasis: Float) {
        switch posture {
        case .neutral:
            return (0, 0, 0)
        case .planning:
            return (0.08, 0.08, 0)
        case .editing:
            return (0.24, 0.18, 0)
        case .sealing:
            return (0.16, 0.72, 0.08)
        case .archival:
            return (0.3, 0.48, 0.68)
        case .fracture:
            return (0.1, 0.12, 0)
        case .healing:
            return (0.26, 0.58, 0.22)
        }
    }

    private static func basePortal(
        for posture: CinematicStagePhasePolishPosture
    ) -> (aperture: Float, backdrop: Float) {
        switch posture {
        case .neutral:
            return (0, 0)
        case .planning:
            return (0.1, 0.14)
        case .editing:
            return (0.18, 0.22)
        case .sealing:
            return (0.28, 0.34)
        case .archival:
            return (0.72, 0.68)
        case .fracture:
            return (0.2, 0.32)
        case .healing:
            return (0.5, 0.56)
        }
    }

    private static func baseCadence(
        for posture: CinematicStagePhasePolishPosture
    ) -> (pose: TimeInterval, orb: TimeInterval, sigil: TimeInterval, fracture: TimeInterval) {
        switch posture {
        case .neutral:
            return (5.8, 4.8, 8.0, 5.5)
        case .planning:
            return (3.6, 2.8, 6.2, 4.8)
        case .editing:
            return (2.4, 1.9, 4.6, 4.2)
        case .sealing:
            return (2.0, 1.55, 5.0, 4.0)
        case .archival:
            return (2.8, 2.35, 4.2, 4.6)
        case .fracture:
            return (1.6, 1.22, 3.2, 1.55)
        case .healing:
            return (2.1, 1.62, 3.8, 2.25)
        }
    }

    private static func staffLightFamily(
        beat: CinematicStageBeat,
        posture: CinematicStagePhasePolishPosture,
        activityMotif: CinematicActivityMotif
    ) -> CinematicStageLightFamily {
        switch activityMotif.eventKind {
        case .dirty:
            return .edit
        case .commit:
            return .git
        case .success, .recovery:
            return .verify
        case .conflicted, .failure:
            return .failure
        case .unavailable, .clean:
            break
        }

        switch posture {
        case .editing:
            return .edit
        case .sealing, .healing:
            return .verify
        case .archival:
            return .git
        case .fracture:
            return .failure
        case .neutral, .planning:
            return beat.lightFamily
        }
    }

    private static func portalLightFamily(
        beat: CinematicStageBeat,
        posture: CinematicStagePhasePolishPosture
    ) -> CinematicStageLightFamily {
        switch posture {
        case .archival:
            return .git
        case .healing, .sealing:
            return .verify
        case .fracture:
            return .failure
        case .editing:
            return .edit
        case .neutral, .planning:
            return beat.lightFamily
        }
    }

    private static func urgency(for kind: CinematicActivityEventKind) -> Float {
        switch kind {
        case .unavailable:
            return 0
        case .clean:
            return 0.08
        case .commit:
            return 0.42
        case .success:
            return 0.48
        case .recovery:
            return 0.58
        case .dirty:
            return 0.58
        case .conflicted:
            return 0.92
        case .failure:
            return 1
        }
    }

    private static func energy(for posture: CinematicStagePhasePolishPosture) -> Float {
        switch posture {
        case .neutral:
            return 0
        case .planning:
            return 0.22
        case .editing:
            return 0.5
        case .sealing:
            return 0.66
        case .archival:
            return 0.74
        case .fracture:
            return 0.92
        case .healing:
            return 0.62
        }
    }

    private static func activityLoadFraction(for profile: RepositoryActivityProfile) -> Float {
        guard !profile.isEmpty else { return 0 }
        return clamp(Float(profile.pressureScore) / 24, to: 0...1)
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
