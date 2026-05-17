import Foundation
@testable import Compass
import XCTest

final class CinematicStageAtmospherePlanTests: XCTestCase {
    func testPlannerOutputIsDeterministicForRepeatedInputs() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.7)
        let profile = activityProfile(recentCommitCount: 2)

        let first = atmospherePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: settings
        )
        let second = atmospherePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: settings
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.influenceStyleIdentifier, "dramatic")
        XCTAssertEqual(first.activityIdentifier, "commit")
        XCTAssertEqual(first.phaseIdentifier, "verifying")
        XCTAssertFalse(first.pressureHalo.identifier.isEmpty)
        XCTAssertFalse(first.atmosphericPulse.identifier.isEmpty)
        XCTAssertFalse(first.pressureLighting.identifier.isEmpty)
        XCTAssertFalse(first.backdropTint.identifier.isEmpty)
        XCTAssertFalse(first.floorTint.identifier.isEmpty)
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
                    let plan = atmospherePlan(
                        phase: phase,
                        activityProfile: activityCase.profile,
                        settings: settings
                    )

                    assertAtmospherePlanInBounds(plan, file: #filePath, line: #line)
                    XCTAssertFalse(plan.identifier.isEmpty, file: #filePath, line: #line)
                    XCTAssertFalse(plan.beatIdentifier.isEmpty, file: #filePath, line: #line)
                }
            }
        }
    }

    func testPressureAtmosphereIncreasesFromCleanThroughHeavy() {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity)
        let plans = [
            atmospherePlan(phase: .developing, activityProfile: activityProfile(), settings: settings),
            atmospherePlan(
                phase: .developing,
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
                settings: settings
            ),
            atmospherePlan(
                phase: .developing,
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 8)),
                settings: settings
            ),
            atmospherePlan(
                phase: .developing,
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 16)),
                settings: settings
            )
        ]

        XCTAssertEqual(plans.map(\.pressureLevelIdentifier), ["clean", "light", "moderate", "heavy"])

        for (lower, higher) in zip(plans, plans.dropFirst()) {
            XCTAssertGreaterThan(higher.pressureFraction, lower.pressureFraction)
            XCTAssertGreaterThan(higher.energy, lower.energy)
            XCTAssertGreaterThan(higher.pressureHalo.radius, lower.pressureHalo.radius)
            XCTAssertGreaterThan(higher.pressureHalo.opacity, lower.pressureHalo.opacity)
            XCTAssertGreaterThan(higher.pressureHalo.scale, lower.pressureHalo.scale)
            XCTAssertLessThan(higher.atmosphericPulse.cadence, lower.atmosphericPulse.cadence)
            XCTAssertGreaterThan(higher.pressureLighting.phaseLightPressureBoost, lower.pressureLighting.phaseLightPressureBoost)
            XCTAssertGreaterThan(higher.pressureLighting.rimLightPressureBoost, lower.pressureLighting.rimLightPressureBoost)
            XCTAssertGreaterThan(higher.backdropTint.opacity, lower.backdropTint.opacity)
            XCTAssertGreaterThan(higher.floorTint.opacity, lower.floorTint.opacity)
            XCTAssertGreaterThan(higher.floorTint.blendFraction, lower.floorTint.blendFraction)
        }
    }

    func testInfluenceAtmosphereDifferencesStayBoundedFromSteadyToDramatic() {
        let profile = activityProfile(worktreeChanges: worktreeChanges(modified: 8))
        let steady = atmospherePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)
        )
        let follow = atmospherePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity)
        )
        let dramatic = atmospherePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        XCTAssertLessThan(steady.influenceFraction, follow.influenceFraction)
        XCTAssertLessThan(follow.influenceFraction, dramatic.influenceFraction)
        XCTAssertGreaterThan(dramatic.energy, steady.energy)
        XCTAssertGreaterThan(dramatic.pressureHalo.scale, steady.pressureHalo.scale)
        XCTAssertLessThan(dramatic.atmosphericPulse.cadence, steady.atmosphericPulse.cadence)
        XCTAssertGreaterThan(dramatic.pressureLighting.rimLightPressureBoost, steady.pressureLighting.rimLightPressureBoost)
        XCTAssertGreaterThan(dramatic.backdropTint.blendFraction, steady.backdropTint.blendFraction)
        assertAtmospherePlanInBounds(steady)
        assertAtmospherePlanInBounds(follow)
        assertAtmospherePlanInBounds(dramatic)
    }

    func testUnavailableIdleAtmosphereRemainsVisuallyNeutral() {
        let plan = atmospherePlan(
            phase: .idle,
            activityProfile: .empty,
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        XCTAssertEqual(plan.activityIdentifier, "unavailable")
        XCTAssertEqual(plan.phaseIdentifier, "idle")
        XCTAssertEqual(plan.pressureLevelIdentifier, "clean")
        XCTAssertEqual(plan.pressureFraction, 0)
        XCTAssertEqual(plan.energy, 0)
        XCTAssertEqual(plan.pressureHalo.opacity, 0)
        XCTAssertEqual(plan.pressureHalo.colorAlpha, 0)
        XCTAssertEqual(plan.atmosphericPulse.amplitude, 0)
        XCTAssertEqual(plan.atmosphericPulse.opacity, 0)
        XCTAssertEqual(plan.pressureLighting.phaseLightPressureBoost, 0)
        XCTAssertEqual(plan.pressureLighting.rimLightPressureBoost, 0)
        XCTAssertEqual(plan.backdropTint.opacity, 0)
        XCTAssertEqual(plan.backdropTint.blendFraction, 0)
        XCTAssertEqual(plan.floorTint.opacity, 0)
        XCTAssertEqual(plan.floorTint.blendFraction, 0)
        assertAtmospherePlanInBounds(plan)
    }
}

private func atmospherePlan(
    phase: LoopPhase,
    activityProfile: RepositoryActivityProfile,
    settings: CinematicInfluenceSettings
) -> CinematicStageAtmospherePlan {
    let beat = CinematicStageBeatPlanner.plan(
        phase: phase,
        activityProfile: activityProfile,
        influenceSettings: settings
    )
    let setDressing = CinematicSetDressingPlanner.plan(
        languageProfile: languageProfile(primaryLanguage: .swift),
        activityProfile: activityProfile,
        influenceSettings: settings
    )
    let effectPlan = CinematicStageEffectPlanner.plan(
        beat: beat,
        setDressingPlan: setDressing,
        influenceSettings: settings
    )

    return CinematicStageAtmospherePlanner.plan(
        beat: beat,
        setDressingPlan: setDressing,
        stageEffectTuning: effectPlan.tuningMetadata,
        influenceSettings: settings
    )
}

private func assertAtmospherePlanInBounds(
    _ plan: CinematicStageAtmospherePlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(plan.pressureFraction, CinematicStageAtmospherePlan.atmospherePressureRange, file: file, line: line)
    XCTAssertInRange(plan.influenceIntensity, CinematicStageAtmospherePlan.atmosphereInfluenceRange, file: file, line: line)
    XCTAssertInRange(plan.influenceFraction, CinematicStageAtmospherePlan.atmosphereInfluenceRange, file: file, line: line)
    XCTAssertInRange(plan.energy, CinematicStageAtmospherePlan.atmosphereEnergyRange, file: file, line: line)
    XCTAssertInRange(plan.pressureHalo.radius, CinematicStageAtmospherePlan.pressureHaloRadiusRange, file: file, line: line)
    XCTAssertInRange(plan.pressureHalo.opacity, CinematicStageAtmospherePlan.pressureHaloOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.pressureHalo.scale, CinematicStageAtmospherePlan.pressureHaloScaleRange, file: file, line: line)
    XCTAssertInRange(plan.pressureHalo.colorAlpha, CinematicStageAtmospherePlan.colorAlphaRange, file: file, line: line)
    XCTAssertInRange(plan.atmosphericPulse.cadence, CinematicStageAtmospherePlan.atmosphericPulseCadenceRange, file: file, line: line)
    XCTAssertInRange(plan.atmosphericPulse.amplitude, CinematicStageAtmospherePlan.atmosphericPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(plan.atmosphericPulse.opacity, CinematicStageAtmospherePlan.atmosphericPulseOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.pressureLighting.phaseLightPressureBoost, CinematicStageAtmospherePlan.phaseLightPressureBoostRange, file: file, line: line)
    XCTAssertInRange(plan.pressureLighting.rimLightPressureBoost, CinematicStageAtmospherePlan.rimLightPressureBoostRange, file: file, line: line)
    XCTAssertInRange(plan.pressureLighting.colorAlpha, CinematicStageAtmospherePlan.colorAlphaRange, file: file, line: line)
    assertTintInBounds(plan.backdropTint, opacityRange: CinematicStageAtmospherePlan.backdropTintOpacityRange, file: file, line: line)
    assertTintInBounds(plan.floorTint, opacityRange: CinematicStageAtmospherePlan.floorTintOpacityRange, file: file, line: line)
}

private func assertTintInBounds(
    _ tint: CinematicStageAtmospherePlan.SurfaceTint,
    opacityRange: ClosedRange<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(tint.red, CinematicStageAtmospherePlan.colorComponentRange, file: file, line: line)
    XCTAssertInRange(tint.green, CinematicStageAtmospherePlan.colorComponentRange, file: file, line: line)
    XCTAssertInRange(tint.blue, CinematicStageAtmospherePlan.colorComponentRange, file: file, line: line)
    XCTAssertInRange(tint.opacity, opacityRange, file: file, line: line)
    XCTAssertInRange(tint.blendFraction, CinematicStageAtmospherePlan.surfaceTintBlendRange, file: file, line: line)
    XCTAssertFalse(tint.identifier.isEmpty, file: file, line: line)
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
