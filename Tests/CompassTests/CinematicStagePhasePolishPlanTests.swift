import Foundation
@testable import Compass
import XCTest

final class CinematicStagePhasePolishPlanTests: XCTestCase {
    func testPlannerOutputIsDeterministicForRepeatedInputs() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.7)
        let profile = activityProfile(recentCommitCount: 2)

        let first = phasePolishPlan(
            phase: .verifying,
            activityProfile: profile,
            settings: settings
        )
        let second = phasePolishPlan(
            phase: .verifying,
            activityProfile: profile,
            settings: settings
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.posture, .archival)
        XCTAssertEqual(first.phaseIdentifier, "verifying")
        XCTAssertEqual(first.activityIdentifier, "commit")
        XCTAssertEqual(first.staffOrb.lightFamily, .git)
        XCTAssertFalse(first.wizardPose.identifier.isEmpty)
        XCTAssertFalse(first.staffOrb.identifier.isEmpty)
        XCTAssertFalse(first.sigilEmphasis.identifier.isEmpty)
        XCTAssertFalse(first.portalBackdrop.identifier.isEmpty)
        XCTAssertFalse(first.fractureRecovery.identifier.isEmpty)
        XCTAssertFalse(first.cadence.identifier.isEmpty)
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
                    let plan = phasePolishPlan(
                        phase: phase,
                        activityProfile: activityCase.profile,
                        settings: settings
                    )

                    assertPhasePolishPlanInBounds(plan, file: #filePath, line: #line)
                    XCTAssertFalse(plan.identifier.isEmpty, file: #filePath, line: #line)
                    XCTAssertFalse(plan.beatIdentifier.isEmpty, file: #filePath, line: #line)
                    XCTAssertFalse(plan.stageEffectTuningIdentifier.isEmpty, file: #filePath, line: #line)
                    XCTAssertFalse(plan.atmosphereIdentifier.isEmpty, file: #filePath, line: #line)
                    XCTAssertFalse(plan.influenceIdentifier.isEmpty, file: #filePath, line: #line)
                }
            }
        }
    }

    func testPhasePosturesReadDifferentlyAcrossCoreStates() {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity)
        let developing = phasePolishPlan(phase: .developing, activityProfile: activityProfile(), settings: settings)
        let verifying = phasePolishPlan(phase: .verifying, activityProfile: activityProfile(), settings: settings)
        let succeeded = phasePolishPlan(
            phase: .succeeded,
            activityProfile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 3),
            settings: settings
        )
        let failed = phasePolishPlan(
            phase: .failed,
            activityProfile: activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 1),
            settings: settings
        )
        let recovery = phasePolishPlan(
            phase: .failed,
            activityProfile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 1, recoveredFromFailure: true),
            settings: settings
        )

        XCTAssertEqual(developing.posture, .editing)
        XCTAssertEqual(verifying.posture, .sealing)
        XCTAssertEqual(succeeded.posture, .archival)
        XCTAssertEqual(failed.posture, .fracture)
        XCTAssertEqual(recovery.posture, .healing)
        XCTAssertNotEqual(developing.identifier, verifying.identifier)
        XCTAssertNotEqual(verifying.identifier, succeeded.identifier)
        XCTAssertNotEqual(succeeded.identifier, failed.identifier)
        XCTAssertNotEqual(failed.identifier, recovery.identifier)
        XCTAssertGreaterThan(verifying.sigilEmphasis.sealEmphasis, developing.sigilEmphasis.sealEmphasis)
        XCTAssertGreaterThan(succeeded.portalBackdrop.portalAperture, verifying.portalBackdrop.portalAperture)
        XCTAssertGreaterThan(failed.fractureRecovery.fractureOpacity, succeeded.fractureRecovery.fractureOpacity)
        XCTAssertGreaterThan(recovery.fractureRecovery.healingOpacity, failed.fractureRecovery.healingOpacity)
    }

    func testRecoveryAndCommitActivityOverridePhaseWithDifferentPersistentPolish() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        let commit = phasePolishPlan(
            phase: .verifying,
            activityProfile: activityProfile(recentCommitCount: 2),
            settings: settings
        )
        let recovery = phasePolishPlan(
            phase: .verifying,
            activityProfile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 1, recoveredFromFailure: true),
            settings: settings
        )

        XCTAssertEqual(commit.posture, .archival)
        XCTAssertEqual(recovery.posture, .healing)
        XCTAssertEqual(commit.activityIdentifier, "commit")
        XCTAssertEqual(recovery.activityIdentifier, "recovery")
        XCTAssertEqual(commit.staffOrb.lightFamily, .git)
        XCTAssertEqual(recovery.staffOrb.lightFamily, .verify)
        XCTAssertGreaterThan(commit.sigilEmphasis.victoryEmphasis, recovery.sigilEmphasis.victoryEmphasis)
        XCTAssertGreaterThan(commit.portalBackdrop.portalAperture, recovery.portalBackdrop.portalAperture)
        XCTAssertGreaterThan(recovery.fractureRecovery.healingOpacity, commit.fractureRecovery.healingOpacity)
    }

    func testUnavailableIdlePolishIsNeutral() {
        let plan = phasePolishPlan(
            phase: .idle,
            activityProfile: .empty,
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        XCTAssertEqual(plan.posture, .neutral)
        XCTAssertEqual(plan.activityIdentifier, "unavailable")
        XCTAssertEqual(plan.phaseIdentifier, "idle")
        XCTAssertEqual(plan.wizardPose.poseIntensity, 0)
        XCTAssertEqual(plan.staffOrb.emission, 0)
        XCTAssertEqual(plan.staffOrb.pulseAmplitude, 0)
        XCTAssertEqual(plan.sigilEmphasis.orbitRadius, 0)
        XCTAssertEqual(plan.sigilEmphasis.sealEmphasis, 0)
        XCTAssertEqual(plan.sigilEmphasis.victoryEmphasis, 0)
        XCTAssertEqual(plan.portalBackdrop.portalAperture, 0)
        XCTAssertEqual(plan.portalBackdrop.portalOpacity, 0)
        XCTAssertEqual(plan.portalBackdrop.backdropAperture, 0)
        XCTAssertEqual(plan.fractureRecovery.fractureOpacity, 0)
        XCTAssertEqual(plan.fractureRecovery.fractureSpread, 0)
        XCTAssertEqual(plan.fractureRecovery.healingOpacity, 0)
        XCTAssertEqual(plan.cadence.poseCadence, CinematicStagePhasePolishPlan.poseCadenceRange.upperBound)
        XCTAssertEqual(plan.cadence.orbPulseCadence, CinematicStagePhasePolishPlan.orbPulseCadenceRange.upperBound)
        assertPhasePolishPlanInBounds(plan)
    }
}

private func phasePolishPlan(
    phase: LoopPhase,
    activityProfile: RepositoryActivityProfile,
    settings: CinematicInfluenceSettings
) -> CinematicStagePhasePolishPlan {
    let languageProfile = languageProfile(primaryLanguage: .swift)
    let activityMotif = CinematicMotif.activity(for: activityProfile)
    let beat = CinematicStageBeatPlanner.plan(
        phase: phase,
        activityProfile: activityProfile,
        influenceSettings: settings
    )
    let setDressing = CinematicSetDressingPlanner.plan(
        languageProfile: languageProfile,
        activityProfile: activityProfile,
        influenceSettings: settings
    )
    let effectPlan = CinematicStageEffectPlanner.plan(
        beat: beat,
        setDressingPlan: setDressing,
        influenceSettings: settings
    )
    let atmospherePlan = CinematicStageAtmospherePlanner.plan(
        beat: beat,
        setDressingPlan: setDressing,
        stageEffectTuning: effectPlan.tuningMetadata,
        influenceSettings: settings
    )

    return CinematicStagePhasePolishPlanner.plan(
        beat: beat,
        stageEffectTuning: effectPlan.tuningMetadata,
        atmospherePlan: atmospherePlan,
        activityMotif: activityMotif,
        activityProfile: activityProfile,
        influenceSettings: settings
    )
}

private func assertPhasePolishPlanInBounds(
    _ plan: CinematicStagePhasePolishPlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(CinematicStagePhasePolishPosture.allCases.contains(plan.posture), file: file, line: line)
    XCTAssertInRange(plan.wizardPose.poseIntensity, CinematicStagePhasePolishPlan.poseIntensityRange, file: file, line: line)
    XCTAssertInRange(plan.wizardPose.staffPitch, CinematicStagePhasePolishPlan.staffPitchRange, file: file, line: line)
    XCTAssertInRange(plan.wizardPose.staffRoll, CinematicStagePhasePolishPlan.staffRollRange, file: file, line: line)
    XCTAssertInRange(plan.wizardPose.leftArmLift, CinematicStagePhasePolishPlan.armLiftRange, file: file, line: line)
    XCTAssertInRange(plan.wizardPose.rightArmLift, CinematicStagePhasePolishPlan.armLiftRange, file: file, line: line)
    XCTAssertInRange(plan.wizardPose.headTilt, CinematicStagePhasePolishPlan.headTiltRange, file: file, line: line)
    XCTAssertInRange(plan.staffOrb.scale, CinematicStagePhasePolishPlan.staffOrbScaleRange, file: file, line: line)
    XCTAssertInRange(plan.staffOrb.emission, CinematicStagePhasePolishPlan.staffOrbEmissionRange, file: file, line: line)
    XCTAssertInRange(plan.staffOrb.pulseAmplitude, CinematicStagePhasePolishPlan.staffOrbPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(plan.sigilEmphasis.orbitRadius, CinematicStagePhasePolishPlan.sigilOrbitRadiusRange, file: file, line: line)
    XCTAssertInRange(plan.sigilEmphasis.sealEmphasis, CinematicStagePhasePolishPlan.sigilSealEmphasisRange, file: file, line: line)
    XCTAssertInRange(plan.sigilEmphasis.victoryEmphasis, CinematicStagePhasePolishPlan.sigilVictoryEmphasisRange, file: file, line: line)
    XCTAssertInRange(plan.sigilEmphasis.pulseAmplitude, CinematicStagePhasePolishPlan.sigilPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(plan.portalBackdrop.portalAperture, CinematicStagePhasePolishPlan.portalApertureRange, file: file, line: line)
    XCTAssertInRange(plan.portalBackdrop.portalScale, CinematicStagePhasePolishPlan.portalScaleRange, file: file, line: line)
    XCTAssertInRange(plan.portalBackdrop.portalOpacity, CinematicStagePhasePolishPlan.portalOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.portalBackdrop.portalPulseAmplitude, CinematicStagePhasePolishPlan.portalPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(plan.portalBackdrop.backdropAperture, CinematicStagePhasePolishPlan.backdropApertureRange, file: file, line: line)
    XCTAssertInRange(plan.portalBackdrop.backdropOpacityBoost, CinematicStagePhasePolishPlan.backdropOpacityBoostRange, file: file, line: line)
    XCTAssertInRange(plan.fractureRecovery.fractureOpacity, CinematicStagePhasePolishPlan.fractureOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.fractureRecovery.fractureSpread, CinematicStagePhasePolishPlan.fractureSpreadRange, file: file, line: line)
    XCTAssertInRange(plan.fractureRecovery.healingOpacity, CinematicStagePhasePolishPlan.healingOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.cadence.poseCadence, CinematicStagePhasePolishPlan.poseCadenceRange, file: file, line: line)
    XCTAssertInRange(plan.cadence.orbPulseCadence, CinematicStagePhasePolishPlan.orbPulseCadenceRange, file: file, line: line)
    XCTAssertInRange(plan.cadence.sigilOrbitCadence, CinematicStagePhasePolishPlan.sigilOrbitCadenceRange, file: file, line: line)
    XCTAssertInRange(plan.cadence.fractureCadence, CinematicStagePhasePolishPlan.fractureCadenceRange, file: file, line: line)
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
