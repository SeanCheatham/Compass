import Foundation
@testable import Compass
import XCTest

final class CinematicStageBeatTests: XCTestCase {
    func testPlannerCoversEveryLoopPhaseWithBaselineSceneDecisions() {
        let cases: [(LoopPhase, CinematicStageBeatKind, CinematicCameraShot, CinematicStageLightFamily, Float, CinematicStageArenaEffect, Bool, Bool)] = [
            (.idle, .idle, .home, .lifecycle, 320, .none, false, false),
            (.planning, .planning, .wide, .scan, 520, .charge, false, false),
            (.developing, .developing, .castPrep, .shell, 680, .charge, false, false),
            (.verifying, .verifying, .overhead, .verify, 760, .seal, false, false),
            (.paused, .paused, .home, .lifecycle, 320, .none, false, false),
            (.failed, .failed, .failure, .failure, 900, .charge, true, false),
            (.succeeded, .succeeded, .victory, .verify, 760, .victory, false, true),
            (.cancelled, .cancelled, .home, .lifecycle, 320, .none, false, false)
        ]

        XCTAssertEqual(cases.map(\.0), LoopPhase.allCases)

        for (phase, kind, cameraShot, lightFamily, intensity, arenaEffect, shouldShake, shouldRunVictory) in cases {
            let beat = CinematicStageBeatPlanner.plan(
                phase: phase,
                activityProfile: .empty,
                influenceSettings: CinematicInfluenceSettings()
            )

            XCTAssertEqual(beat.phase, phase)
            XCTAssertEqual(beat.kind, kind)
            XCTAssertEqual(beat.kindIdentifier, kind.rawValue)
            XCTAssertEqual(beat.cameraShot, cameraShot)
            XCTAssertEqual(beat.cameraShotIdentifier, cameraShot.identifier)
            XCTAssertEqual(beat.lightFamily, lightFamily)
            XCTAssertEqual(beat.lightFamilyIdentifier, lightFamily.rawValue)
            XCTAssertEqual(beat.phaseLightIntensity, intensity)
            XCTAssertEqual(beat.arenaEffect, arenaEffect)
            XCTAssertEqual(beat.arenaEffectIdentifier, arenaEffect.rawValue)
            XCTAssertEqual(beat.shouldShakeCamera, shouldShake)
            XCTAssertEqual(beat.shouldRunVictorySurge, shouldRunVictory)
            XCTAssertFalse(beat.shouldRunHistoryChains)
            XCTAssertNil(beat.activityAccent)
        }
    }

    func testPlannerCoversRepositoryActivityAccents() throws {
        let cases: [(String, RepositoryActivityProfile, CinematicActivityEventKind, CinematicStageLightFamily, CinematicStageArenaEffect, Float, Float, Float, Float, Bool, Bool)] = [
            (
                "dirty",
                activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
                .dirty,
                .pressure,
                .activityPulse,
                4.4,
                0.58,
                1.18,
                0.4,
                false,
                false
            ),
            (
                "conflicted",
                activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)),
                .conflicted,
                .failure,
                .activityPulse,
                5.4,
                0.68,
                1.22,
                0.5,
                true,
                false
            ),
            (
                "commit",
                activityProfile(recentCommitCount: 2),
                .commit,
                .git,
                .historyChains,
                0,
                0,
                0,
                0,
                false,
                true
            ),
            (
                "success",
                activityProfile(lastTerminalStatus: .succeeded, successStreak: 3),
                .success,
                .verify,
                .activityPulse,
                5.8,
                0.58,
                1.14,
                0.34,
                false,
                false
            ),
            (
                "recovery",
                activityProfile(lastTerminalStatus: .succeeded, successStreak: 1, recoveredFromFailure: true),
                .recovery,
                .verify,
                .activityPulse,
                5.8,
                0.58,
                1.14,
                0.34,
                false,
                false
            ),
            (
                "failure",
                activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 1),
                .failure,
                .failure,
                .activityPulse,
                5.4,
                0.68,
                1.22,
                0.5,
                true,
                false
            )
        ]

        for (name, profile, eventKind, lightFamily, arenaEffect, radius, alpha, scale, opacity, shouldShake, shouldRunHistory) in cases {
            let beat = CinematicStageBeatPlanner.plan(
                phase: .developing,
                activityProfile: profile,
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.8)
            )
            let accent = try XCTUnwrap(beat.activityAccent, name)

            XCTAssertEqual(accent.eventKind, eventKind, name)
            XCTAssertEqual(accent.lightFamily, lightFamily, name)
            XCTAssertEqual(accent.arenaEffect, arenaEffect, name)
            XCTAssertEqual(accent.pulseRadius, radius, accuracy: 0.0001, name)
            XCTAssertEqual(accent.pulseColorAlpha, alpha, accuracy: 0.0001, name)
            XCTAssertEqual(accent.pulseScaleMultiplier, scale, accuracy: 0.0001, name)
            XCTAssertEqual(accent.pulseOpacity, opacity, accuracy: 0.0001, name)
            XCTAssertEqual(accent.shouldShakeCamera, shouldShake, name)
            XCTAssertEqual(accent.shouldRunHistoryChains, shouldRunHistory, name)
            XCTAssertEqual(beat.shouldShakeCamera, shouldShake, name)
            XCTAssertEqual(beat.shouldRunHistoryChains, shouldRunHistory, name)
            XCTAssertEqual(beat.activityAccentIdentifier, accent.identifier, name)
        }
    }

    func testPlannerUsesStableIdentifiersAndDeterministicOutput() {
        let profile = activityProfile(worktreeChanges: worktreeChanges(conflicted: 1))
        let settings = CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.25)

        let first = CinematicStageBeatPlanner.plan(
            phase: .verifying,
            activityProfile: profile,
            influenceSettings: settings
        )
        let second = CinematicStageBeatPlanner.plan(
            phase: .verifying,
            activityProfile: profile,
            influenceSettings: settings
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.influenceIdentifier, "steady|0.2500")
        XCTAssertFalse(first.identifier.isEmpty)
        XCTAssertFalse(first.kindIdentifier.isEmpty)
        XCTAssertFalse(first.phaseIdentifier.isEmpty)
        XCTAssertFalse(first.cameraShotIdentifier.isEmpty)
        XCTAssertFalse(first.lightFamilyIdentifier.isEmpty)
        XCTAssertFalse(first.arenaEffectIdentifier.isEmpty)
        XCTAssertFalse(first.activityAccentIdentifier.isEmpty)
    }

    func testPlannerOutputsStayInsideBoundedRanges() {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.5),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]
        let profiles = [
            RepositoryActivityProfile.empty,
            activityProfile(),
            activityProfile(worktreeChanges: worktreeChanges(modified: 8)),
            activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)),
            activityProfile(recentCommitCount: 1),
            activityProfile(lastTerminalStatus: .succeeded, successStreak: 3),
            activityProfile(lastTerminalStatus: .succeeded, successStreak: 1, recoveredFromFailure: true),
            activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 2)
        ]

        for settings in settingsSamples {
            for phase in LoopPhase.allCases {
                for profile in profiles {
                    let beat = CinematicStageBeatPlanner.plan(
                        phase: phase,
                        activityProfile: profile,
                        influenceSettings: settings
                    )

                    XCTAssertInRange(beat.phaseLightIntensity, CinematicStageBeatPlanner.phaseLightIntensityRange)
                    XCTAssertFalse(beat.identifier.isEmpty)

                    if let accent = beat.activityAccent {
                        XCTAssertInRange(accent.pulseRadius, CinematicStageBeatPlanner.activityPulseRadiusRange)
                        XCTAssertInRange(accent.pulseColorAlpha, CinematicStageBeatPlanner.activityPulseColorAlphaRange)
                        XCTAssertInRange(accent.pulseScaleMultiplier, CinematicStageBeatPlanner.activityPulseScaleMultiplierRange)
                        XCTAssertInRange(accent.pulseOpacity, CinematicStageBeatPlanner.activityPulseOpacityRange)
                        XCTAssertFalse(accent.identifier.isEmpty)
                    }
                }
            }
        }
    }

    func testCleanAndUnavailableProfilesDoNotEmitActivityAccent() {
        let cleanBeat = CinematicStageBeatPlanner.plan(
            phase: .planning,
            activityProfile: activityProfile(),
            influenceSettings: CinematicInfluenceSettings()
        )
        let unavailableBeat = CinematicStageBeatPlanner.plan(
            phase: .planning,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings()
        )

        XCTAssertNil(cleanBeat.activityAccent)
        XCTAssertNil(unavailableBeat.activityAccent)
        XCTAssertEqual(cleanBeat.activityAccentIdentifier, "none")
        XCTAssertEqual(unavailableBeat.activityAccentIdentifier, "none")
    }

    func testDiagnosticsReportIncludesStageBeatSnapshotAndSummaryRow() {
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Expose stage beat diagnostics",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 2),
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.6)
        )

        XCTAssertTrue(report.identifier.contains("stage:"))
        XCTAssertEqual(report.stageBeat.phaseIdentifier, "Verifying")
        XCTAssertEqual(report.stageBeat.kindIdentifier, "verifying")
        XCTAssertEqual(report.stageBeat.cameraShotIdentifier, "overhead")
        XCTAssertEqual(report.stageBeat.lightFamilyIdentifier, "verify")
        XCTAssertEqual(report.stageBeat.arenaEffectIdentifier, "seal")
        XCTAssertEqual(report.stageBeat.activityEventKindIdentifier, "commit")
        XCTAssertEqual(report.stageBeat.activityLightFamilyIdentifier, "git")
        XCTAssertEqual(report.stageBeat.activityArenaEffectIdentifier, "history-chains")
        XCTAssertTrue(report.stageBeat.shouldRunHistoryChains)

        let summary = CinematicDiagnosticsSummary(report: report)
        XCTAssertTrue(summary.rows.contains { $0.id == "stage-beat" })
        XCTAssertTrue(summary.exportText.contains("Stage beat:"))
        XCTAssertTrue(summary.exportText.contains("overhead"))
        XCTAssertTrue(summary.exportText.contains("history"))
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
