import Foundation
@testable import Compass
import XCTest

final class CinematicStageEffectPlanTests: XCTestCase {
    func testPlannerCoversEveryArenaEffectRecipe() throws {
        let settings = CinematicInfluenceSettings()
        let setDressing = setDressingPlan(settings: settings, activityProfile: .empty)
        let phaseCases: [(LoopPhase, CinematicStageArenaEffect, Int, Int, Int, Bool)] = [
            (.idle, .none, 0, 0, 0, false),
            (.planning, .charge, 2, 1, 0, false),
            (.developing, .charge, 2, 1, 0, false),
            (.verifying, .seal, 4, 1, 1, false),
            (.paused, .none, 0, 0, 0, false),
            (.failed, .charge, 2, 1, 0, false),
            (.succeeded, .victory, 7, 1, 1, true),
            (.cancelled, .none, 0, 0, 0, false)
        ]

        XCTAssertEqual(phaseCases.map(\.0), LoopPhase.allCases)

        var coveredEffects = Set<String>()
        for (phase, arenaEffect, ringCount, pulseCount, sparkCount, hasVictory) in phaseCases {
            let beat = CinematicStageBeatPlanner.plan(
                phase: phase,
                activityProfile: .empty,
                influenceSettings: settings
            )
            let plan = CinematicStageEffectPlanner.plan(
                beat: beat,
                setDressingPlan: setDressing,
                influenceSettings: settings
            )

            coveredEffects.insert(plan.phaseEffect.arenaEffect.rawValue)
            XCTAssertEqual(plan.phaseEffect.arenaEffect, arenaEffect, phase.rawValue)
            XCTAssertEqual(plan.phaseEffect.arenaRings.count, ringCount, phase.rawValue)
            XCTAssertEqual(plan.phaseEffect.phaseLightPulse == nil ? 0 : 1, pulseCount, phase.rawValue)
            XCTAssertEqual(plan.phaseEffect.sparkBursts.count, sparkCount, phase.rawValue)
            XCTAssertEqual(plan.phaseEffect.victoryCadence != nil, hasVictory, phase.rawValue)
            XCTAssertNil(plan.activityEffect, phase.rawValue)
        }

        let activityCases: [(String, RepositoryActivityProfile, CinematicActivityEventKind, CinematicStageArenaEffect, Int, Int, Bool)] = [
            (
                "dirty",
                activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
                .dirty,
                .activityPulse,
                1,
                0,
                false
            ),
            (
                "conflicted",
                activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)),
                .conflicted,
                .activityPulse,
                1,
                0,
                true
            ),
            (
                "commit",
                activityProfile(recentCommitCount: 2),
                .commit,
                .historyChains,
                1,
                3,
                false
            ),
            (
                "success",
                activityProfile(lastTerminalStatus: .succeeded, successStreak: 3),
                .success,
                .activityPulse,
                1,
                0,
                false
            ),
            (
                "recovery",
                activityProfile(lastTerminalStatus: .succeeded, successStreak: 1, recoveredFromFailure: true),
                .recovery,
                .activityPulse,
                1,
                0,
                false
            ),
            (
                "failure",
                activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 1),
                .failure,
                .activityPulse,
                1,
                0,
                true
            )
        ]

        for (name, profile, eventKind, arenaEffect, ringCount, historyCount, shouldShake) in activityCases {
            let beat = CinematicStageBeatPlanner.plan(
                phase: .developing,
                activityProfile: profile,
                influenceSettings: settings
            )
            let plan = CinematicStageEffectPlanner.plan(
                beat: beat,
                setDressingPlan: setDressingPlan(settings: settings, activityProfile: profile),
                influenceSettings: settings
            )
            let activityEffect = try XCTUnwrap(plan.activityEffect, name)

            coveredEffects.insert(activityEffect.arenaEffect.rawValue)
            XCTAssertEqual(beat.activityAccent?.eventKind, eventKind, name)
            XCTAssertEqual(activityEffect.sourceIdentifier, "activity:\(eventKind.rawValue)", name)
            XCTAssertEqual(activityEffect.arenaEffect, arenaEffect, name)
            XCTAssertEqual(activityEffect.arenaRings.count, ringCount, name)
            XCTAssertEqual(activityEffect.historyTrails.count, historyCount, name)
            XCTAssertEqual(activityEffect.cameraShake?.shouldShake ?? false, shouldShake, name)
        }

        XCTAssertEqual(coveredEffects, Set(CinematicStageArenaEffect.allCases.map(\.rawValue)))
    }

    func testPlansStayInsideBoundedDescriptorRanges() {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]

        for settings in settingsSamples {
            for phase in LoopPhase.allCases {
                for activityCase in CinematicDiagnostics.representativeActivityCases() {
                    let setDressing = setDressingPlan(
                        settings: settings,
                        activityProfile: activityCase.profile
                    )
                    let beat = CinematicStageBeatPlanner.plan(
                        phase: phase,
                        activityProfile: activityCase.profile,
                        influenceSettings: settings
                    )
                    let plan = CinematicStageEffectPlanner.plan(
                        beat: beat,
                        setDressingPlan: setDressing,
                        influenceSettings: settings
                    )

                    assertPlanInBounds(plan, file: #filePath, line: #line)
                    XCTAssertFalse(plan.identifier.isEmpty)
                    XCTAssertFalse(plan.phaseEffect.identifier.isEmpty)
                    XCTAssertEqual(plan.beatIdentifier, beat.identifier)
                }
            }
        }
    }

    func testPlannerOutputIsDeterministicForRepeatedInputs() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.7)
        let profile = activityProfile(recentCommitCount: 2)
        let beat = CinematicStageBeatPlanner.plan(
            phase: .verifying,
            activityProfile: profile,
            influenceSettings: settings
        )
        let setDressing = setDressingPlan(settings: settings, activityProfile: profile)

        let first = CinematicStageEffectPlanner.plan(
            beat: beat,
            setDressingPlan: setDressing,
            influenceSettings: settings
        )
        let second = CinematicStageEffectPlanner.plan(
            beat: beat,
            setDressingPlan: setDressing,
            influenceSettings: settings
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.influenceIdentifier, "dramatic|0.7000")
        XCTAssertEqual(first.tuningMetadata.identifier, second.tuningMetadata.identifier)
        XCTAssertEqual(first.tuningMetadata.influenceStyleIdentifier, "dramatic")
        XCTAssertTrue(first.phaseEffect.identifier.contains("seal"))
        XCTAssertTrue(first.activityEffect?.identifier.contains("history-chains") ?? false)
    }

    func testPressureTuningIncreasesVisibleChoreographyFromCleanToHeavy() throws {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity)
        let cleanPlan = effectPlan(
            phase: .developing,
            activityProfile: activityProfile(),
            settings: settings
        )
        let heavyPlan = effectPlan(
            phase: .developing,
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 16)),
            settings: settings
        )

        let cleanRing = try XCTUnwrap(cleanPlan.phaseEffect.arenaRings.first)
        let heavyRing = try XCTUnwrap(heavyPlan.phaseEffect.arenaRings.first)
        let cleanPulse = try XCTUnwrap(cleanPlan.phaseEffect.phaseLightPulse)
        let heavyPulse = try XCTUnwrap(heavyPlan.phaseEffect.phaseLightPulse)
        let heavyActivityRing = try XCTUnwrap(heavyPlan.activityEffect?.arenaRings.first)

        XCTAssertEqual(cleanPlan.tuningMetadata.pressureLevelIdentifier, "clean")
        XCTAssertEqual(heavyPlan.tuningMetadata.pressureLevelIdentifier, "heavy")
        XCTAssertGreaterThan(heavyPlan.tuningMetadata.pressureFraction, cleanPlan.tuningMetadata.pressureFraction)
        XCTAssertGreaterThan(heavyPlan.tuningMetadata.energy, cleanPlan.tuningMetadata.energy)
        XCTAssertGreaterThan(heavyRing.scale, cleanRing.scale)
        XCTAssertGreaterThan(heavyRing.opacity, cleanRing.opacity)
        XCTAssertLessThan(heavyRing.duration, cleanRing.duration)
        XCTAssertGreaterThan(heavyPulse.intensity, cleanPulse.intensity)
        XCTAssertGreaterThan(heavyActivityRing.scale, 1)
    }

    func testInfluenceTuningChangesStayBoundedFromSteadyToDramatic() throws {
        let profile = activityProfile(worktreeChanges: worktreeChanges(modified: 8))
        let steadyPlan = effectPlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)
        )
        let dramaticPlan = effectPlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        let steadySpark = try XCTUnwrap(steadyPlan.phaseEffect.sparkBursts.first)
        let dramaticSpark = try XCTUnwrap(dramaticPlan.phaseEffect.sparkBursts.first)
        let steadyRing = try XCTUnwrap(steadyPlan.phaseEffect.arenaRings.first)
        let dramaticRing = try XCTUnwrap(dramaticPlan.phaseEffect.arenaRings.first)

        XCTAssertEqual(steadyPlan.tuningMetadata.influenceStyleIdentifier, "steady")
        XCTAssertEqual(dramaticPlan.tuningMetadata.influenceStyleIdentifier, "dramatic")
        XCTAssertGreaterThan(dramaticPlan.tuningMetadata.influenceFraction, steadyPlan.tuningMetadata.influenceFraction)
        XCTAssertGreaterThan(dramaticPlan.tuningMetadata.energy, steadyPlan.tuningMetadata.energy)
        XCTAssertGreaterThan(dramaticRing.scale, steadyRing.scale)
        XCTAssertLessThan(dramaticRing.duration, steadyRing.duration)
        XCTAssertGreaterThan(dramaticSpark.birthRate, steadySpark.birthRate)
        assertPlanInBounds(steadyPlan)
        assertPlanInBounds(dramaticPlan)
    }

    func testInfluenceIntensityScalesActivityPulseAndCameraShakeDescriptors() throws {
        let lowSettings = CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)
        let highSettings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        let dirtyProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 8))

        let lowDirtyPlan = effectPlan(
            phase: .developing,
            activityProfile: dirtyProfile,
            settings: lowSettings
        )
        let highDirtyPlan = effectPlan(
            phase: .developing,
            activityProfile: dirtyProfile,
            settings: highSettings
        )
        let lowPulse = try XCTUnwrap(lowDirtyPlan.activityEffect?.arenaRings.first)
        let highPulse = try XCTUnwrap(highDirtyPlan.activityEffect?.arenaRings.first)

        XCTAssertGreaterThan(highPulse.scale, lowPulse.scale)
        XCTAssertLessThan(highPulse.duration, lowPulse.duration)

        let failureProfile = activityProfile(
            recentFailedCount: 1,
            lastTerminalStatus: .failed,
            failureStreak: 1
        )
        let lowFailurePlan = effectPlan(
            phase: .failed,
            activityProfile: failureProfile,
            settings: lowSettings
        )
        let highFailurePlan = effectPlan(
            phase: .failed,
            activityProfile: failureProfile,
            settings: highSettings
        )
        let lowShake = try XCTUnwrap(lowFailurePlan.phaseEffect.cameraShake)
        let highShake = try XCTUnwrap(highFailurePlan.phaseEffect.cameraShake)

        XCTAssertGreaterThan(highShake.scale, lowShake.scale)
        XCTAssertGreaterThan(highShake.duration, lowShake.duration)
    }

    func testRecoveryCueEffectsUseDistinctArenaTreatmentsAndStayBounded() throws {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        let verifyCue = CinematicRecoveryCuePlanner.representativePlans(influenceSettings: settings)[1]
        let dirtyCue = CinematicRecoveryCuePlanner.representativePlans(influenceSettings: settings)[2]
        let promotionCue = CinematicRecoveryCuePlanner.representativePlans(influenceSettings: settings)[4]

        let verifyPlan = effectPlan(
            phase: .failed,
            activityProfile: activityProfile(),
            settings: settings,
            recoveryCuePlan: verifyCue
        )
        let dirtyPlan = effectPlan(
            phase: .developing,
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
            settings: settings,
            recoveryCuePlan: dirtyCue
        )
        let promotionPlan = effectPlan(
            phase: .failed,
            activityProfile: activityProfile(recentCommitCount: 2),
            settings: settings,
            recoveryCuePlan: promotionCue
        )

        let verifyEffect = try XCTUnwrap(verifyPlan.recoveryEffect)
        let dirtyEffect = try XCTUnwrap(dirtyPlan.recoveryEffect)
        let promotionEffect = try XCTUnwrap(promotionPlan.recoveryEffect)

        XCTAssertEqual(verifyEffect.lightFamily, .failure)
        XCTAssertEqual(verifyEffect.arenaEffect, .charge)
        XCTAssertEqual(dirtyEffect.lightFamily, .edit)
        XCTAssertEqual(dirtyEffect.arenaEffect, .activityPulse)
        XCTAssertEqual(promotionEffect.lightFamily, .git)
        XCTAssertEqual(promotionEffect.arenaEffect, .historyChains)
        XCTAssertTrue(verifyEffect.cameraShake?.shouldShake ?? false)
        XCTAssertNil(dirtyEffect.cameraShake)
        XCTAssertTrue(promotionEffect.cameraShake?.shouldShake ?? false)
        XCTAssertEqual(verifyPlan.recoveryCueKindIdentifier, "failedVerify")
        XCTAssertEqual(dirtyPlan.recoveryCueKindIdentifier, "dirtyWorktree")
        XCTAssertEqual(promotionPlan.recoveryCueKindIdentifier, "promotionFailed")

        assertPlanInBounds(verifyPlan)
        assertPlanInBounds(dirtyPlan)
        assertPlanInBounds(promotionPlan)
    }

    func testDiagnosticsReportIncludesStageEffectSnapshotAndSummaryRows() {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.6)
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Expose effect choreography diagnostics",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 2),
            influenceSettings: settings
        )

        XCTAssertTrue(report.identifier.contains("stage-effect:"))
        XCTAssertEqual(report.stageEffect.phaseArenaEffectIdentifier, "seal")
        XCTAssertEqual(report.stageEffect.activityArenaEffectIdentifier, "history-chains")
        XCTAssertEqual(report.stageEffect.arenaRingCount, 5)
        XCTAssertEqual(report.stageEffect.phaseLightPulseCount, 1)
        XCTAssertEqual(report.stageEffect.sparkBurstCount, 1)
        XCTAssertEqual(report.stageEffect.historyTrailCount, 3)
        XCTAssertNil(report.stageEffect.victoryCadenceIdentifier)
        XCTAssertTrue(report.stageEffect.cameraShakeIdentifiers.isEmpty)
        XCTAssertTrue(report.stageEffect.arenaRingIdentifiers.contains { $0.contains("r4.0000") })
        XCTAssertTrue(report.stageEffect.phaseLightPulseIdentifiers.contains { $0.contains("reset") })
        XCTAssertTrue(report.stageEffect.sparkBurstIdentifiers.contains { $0.contains("b") })
        XCTAssertEqual(report.stageEffect.pressureLevelIdentifier, "clean")
        XCTAssertEqual(report.stageEffect.influenceStyleIdentifier, "follow")
        XCTAssertGreaterThan(report.stageEffect.energy, 0)
        XCTAssertGreaterThan(report.stageEffect.ringScaleMultiplier, 0)
        XCTAssertGreaterThan(report.stageEffect.pulseIntensityMultiplier, 0)
        XCTAssertGreaterThan(report.stageEffect.sparkBirthRateMultiplier, 0)
        XCTAssertEqual(report.stageEffect.historyTrailTargetCount, 3)
        XCTAssertEqual(report.stageAtmosphere.pressureLevelIdentifier, report.stageEffect.pressureLevelIdentifier)
        XCTAssertEqual(report.stageAtmosphere.influenceStyleIdentifier, report.stageEffect.influenceStyleIdentifier)
        XCTAssertGreaterThan(report.stageAtmosphere.pressureHaloRadius, 0)
        XCTAssertGreaterThan(report.stageAtmosphere.pressureHaloOpacity, 0)
        XCTAssertGreaterThan(report.stageAtmosphere.phaseLightPressureBoost, 0)

        let summary = CinematicDiagnosticsSummary(report: report)
        XCTAssertTrue(summary.rows.contains { $0.id == "stage-effect" })
        XCTAssertTrue(summary.rows.contains { $0.id == "effect-tuning" })
        XCTAssertTrue(summary.rows.contains { $0.id == "effect-rings" })
        XCTAssertTrue(summary.rows.contains { $0.id == "effect-pulses" })
        XCTAssertTrue(summary.rows.contains { $0.id == "effect-history" })
        XCTAssertTrue(summary.rows.contains { $0.id == "stage-atmosphere" })
        XCTAssertTrue(summary.rows.contains { $0.id == "atmosphere-tints" })
        XCTAssertTrue(summary.exportText.contains("Stage effect:"))
        XCTAssertTrue(summary.exportText.contains("Effect tuning:"))
        XCTAssertTrue(summary.exportText.contains("Effect rings:"))
        XCTAssertTrue(summary.exportText.contains("Effect pulses:"))
        XCTAssertTrue(summary.exportText.contains("Effect history:"))
        XCTAssertTrue(summary.exportText.contains("Atmosphere:"))
        XCTAssertTrue(summary.exportText.contains("Atmosphere tints:"))
        XCTAssertTrue(summary.exportText.contains("history-chains"))
    }
}

private func effectPlan(
    phase: LoopPhase,
    activityProfile: RepositoryActivityProfile,
    settings: CinematicInfluenceSettings,
    recoveryCuePlan: CinematicRecoveryCuePlan = .none
) -> CinematicStageEffectPlan {
    let beat = CinematicStageBeatPlanner.plan(
        phase: phase,
        activityProfile: activityProfile,
        influenceSettings: settings
    )
    return CinematicStageEffectPlanner.plan(
        beat: beat,
        setDressingPlan: setDressingPlan(settings: settings, activityProfile: activityProfile),
        influenceSettings: settings,
        recoveryCuePlan: recoveryCuePlan
    )
}

private func setDressingPlan(
    settings: CinematicInfluenceSettings,
    activityProfile: RepositoryActivityProfile
) -> CinematicSetDressingPlan {
    CinematicSetDressingPlanner.plan(
        languageProfile: languageProfile(primaryLanguage: .swift),
        activityProfile: activityProfile,
        influenceSettings: settings
    )
}

private func assertPlanInBounds(
    _ plan: CinematicStageEffectPlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(plan.tuningMetadata.pressureFraction, CinematicStageEffectPlan.stageEffectPressureRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.energy, CinematicStageEffectPlan.stageEffectEnergyRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.influenceIntensity, CinematicStageEffectPlan.stageEffectInfluenceRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.influenceFraction, CinematicStageEffectPlan.stageEffectInfluenceRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.activityLightBoost, CinematicStageEffectPlan.stageEffectActivityLightBoostRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.activityLightBoostFraction, CinematicStageEffectPlan.stageEffectEnergyRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.runePulseScale, CinematicStageEffectPlan.stageEffectRunePulseScaleRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.activityPulseDuration, CinematicStageEffectPlan.stageEffectActivityPulseDurationRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.ringDurationScale, CinematicStageEffectPlan.ringDurationScaleRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.ringScaleMultiplier, CinematicStageEffectPlan.ringScaleMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.ringOpacityMultiplier, CinematicStageEffectPlan.ringOpacityMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.colorAlphaMultiplier, CinematicStageEffectPlan.colorAlphaMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.pulseIntensityMultiplier, CinematicStageEffectPlan.pulseIntensityMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.pulseDurationMultiplier, CinematicStageEffectPlan.pulseDurationMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.sparkBirthRateMultiplier, CinematicStageEffectPlan.sparkBirthRateMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.historyTrailCount, CinematicStageEffectPlan.historyTrailTuningCountRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.cameraShakeMultiplier, CinematicStageEffectPlan.cameraShakeMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.cameraShakeDurationMultiplier, CinematicStageEffectPlan.cameraShakeDurationMultiplierRange, file: file, line: line)
    XCTAssertInRange(plan.tuningMetadata.victoryCadenceMultiplier, CinematicStageEffectPlan.victoryCadenceMultiplierRange, file: file, line: line)
    XCTAssertFalse(plan.tuningMetadata.identifier.isEmpty, file: file, line: line)

    for effect in plan.effects {
        for ring in effect.arenaRings {
            XCTAssertInRange(ring.radius, CinematicStageEffectPlan.arenaRingRadiusRange, file: file, line: line)
            XCTAssertInRange(ring.duration, CinematicStageEffectPlan.arenaRingDurationRange, file: file, line: line)
            XCTAssertInRange(ring.scale, CinematicStageEffectPlan.arenaRingScaleRange, file: file, line: line)
            XCTAssertInRange(ring.opacity, CinematicStageEffectPlan.arenaRingOpacityRange, file: file, line: line)
            XCTAssertInRange(ring.colorAlpha, CinematicStageEffectPlan.colorAlphaRange, file: file, line: line)
            XCTAssertFalse(ring.identifier.isEmpty, file: file, line: line)
        }

        if let pulse = effect.phaseLightPulse {
            XCTAssertInRange(
                pulse.intensity,
                CinematicStageEffectPlan.phaseLightPulseIntensityRange,
                file: file,
                line: line
            )
            XCTAssertInRange(
                pulse.duration,
                CinematicStageEffectPlan.phaseLightPulseDurationRange,
                file: file,
                line: line
            )
            XCTAssertInRange(
                pulse.resetIntensity,
                CinematicStageEffectPlan.phaseLightResetIntensityRange,
                file: file,
                line: line
            )
            XCTAssertFalse(pulse.identifier.isEmpty, file: file, line: line)
        }

        for spark in effect.sparkBursts {
            XCTAssertFinite(spark.position, file: file, line: line)
            XCTAssertInRange(spark.birthRate, CinematicStageEffectPlan.sparkBirthRateRange, file: file, line: line)
            XCTAssertInRange(spark.colorAlpha, CinematicStageEffectPlan.colorAlphaRange, file: file, line: line)
            XCTAssertFalse(spark.identifier.isEmpty, file: file, line: line)
        }

        XCTAssertInRange(
            effect.historyTrails.count,
            CinematicStageEffectPlan.historyTrailCountRange,
            file: file,
            line: line
        )
        for trail in effect.historyTrails {
            XCTAssertFinite(trail.start, file: file, line: line)
            XCTAssertFinite(trail.end, file: file, line: line)
            XCTAssertFalse(trail.identifier.isEmpty, file: file, line: line)
        }

        if let cameraShake = effect.cameraShake {
            XCTAssertTrue(cameraShake.shouldShake, file: file, line: line)
            XCTAssertInRange(
                cameraShake.duration,
                CinematicStageEffectPlan.cameraShakeDurationRange,
                file: file,
                line: line
            )
            XCTAssertInRange(cameraShake.scale, CinematicTuning.cameraShakeScaleRange, file: file, line: line)
            XCTAssertFalse(cameraShake.identifier.isEmpty, file: file, line: line)
        }

        XCTAssertFalse(effect.identifier.isEmpty, file: file, line: line)
    }
}

private func languageProfile(primaryLanguage: RepositoryLanguage) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[primaryLanguage] = primaryLanguage == .unknown ? 0 : 4
    return RepositoryLanguageProfile(
        counts: counts,
        manifestHints: [],
        primaryLanguage: primaryLanguage,
        scannedFileCount: primaryLanguage == .unknown ? 0 : 4,
        scannedDirectoryCount: primaryLanguage == .unknown ? 0 : 1,
        wasTruncated: false
    )
}

private func activityProfile(
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

private func worktreeChanges(
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

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}

private func XCTAssertFinite(
    _ value: SIMD3<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value.x.isFinite, file: file, line: line)
    XCTAssertTrue(value.y.isFinite, file: file, line: line)
    XCTAssertTrue(value.z.isFinite, file: file, line: line)
}
