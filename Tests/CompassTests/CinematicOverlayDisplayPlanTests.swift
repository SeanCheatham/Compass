import Foundation
@testable import Compass
import XCTest

final class CinematicOverlayDisplayPlanTests: XCTestCase {
    func testActiveReadableNarrativeCuesUseCompactInWorldFirstOverlay() {
        let plan = makeOverlayPlan(phase: .developing)

        XCTAssertEqual(plan.mode, .compact)
        XCTAssertEqual(plan.reasonIdentifier, "in-world-readable-cues")
        XCTAssertEqual(plan.visiblePills, [.activity])
        XCTAssertEqual(plan.hudProminence, .minimal)
        XCTAssertLessThan(plan.gradientStrength, 0.32)
        XCTAssertLessThan(plan.worldTextMaxWidth, 340)
        XCTAssertLessThan(plan.hudMaxWidth, 430)
        XCTAssertFalse(plan.showsHUDDetail)
        XCTAssertFalse(plan.showsHUDProfiles)
        XCTAssertTrue(plan.identifier.contains("mode:compact"))
    }

    func testPlanningSuccessAndFailureRemainCompactWhenCuesAreReadable() {
        let planning = makeOverlayPlan(phase: .planning)
        let succeeded = makeOverlayPlan(phase: .succeeded)
        let failed = makeOverlayPlan(phase: .failed)

        XCTAssertEqual(planning.mode, .compact)
        XCTAssertEqual(planning.visiblePills, [.quest])
        XCTAssertEqual(planning.hudProminence, .compact)
        XCTAssertTrue(planning.showsHUDDetail)

        XCTAssertEqual(succeeded.mode, .compact)
        XCTAssertEqual(succeeded.visiblePills, [.activity])
        XCTAssertEqual(succeeded.hudProminence, .compact)

        XCTAssertEqual(failed.mode, .compact)
        XCTAssertEqual(failed.visiblePills, [.activity])
        XCTAssertEqual(failed.hudProminence, .compact)
    }

    func testIdleUnavailablePausedAndMissingRepositoryStayReadable() {
        let idle = makeOverlayPlan(phase: .idle, isRunning: false)
        let unavailable = makeOverlayPlan(phase: .developing, activityProfile: .empty)
        let paused = makeOverlayPlan(phase: .developing, isPaused: true)
        let missingRepository = makeOverlayPlan(phase: .developing, hasRepository: false)

        XCTAssertEqual(idle.mode, .full)
        XCTAssertEqual(idle.visiblePills, [.quest, .arena, .activity])
        XCTAssertEqual(idle.hudProminence, .full)
        XCTAssertTrue(idle.showsHUDDetail)
        XCTAssertTrue(idle.showsHUDProfiles)

        XCTAssertEqual(unavailable.mode, .full)
        XCTAssertEqual(unavailable.reasonIdentifier, "activity-unavailable")
        XCTAssertEqual(unavailable.visiblePills, [.quest, .arena, .activity])

        XCTAssertEqual(paused.mode, .full)
        XCTAssertEqual(paused.reasonIdentifier, "paused")
        XCTAssertEqual(paused.visiblePills, [.quest, .arena, .activity])

        XCTAssertEqual(missingRepository.mode, .fallback)
        XCTAssertEqual(missingRepository.reasonIdentifier, "missing-repository")
        XCTAssertEqual(missingRepository.visiblePills, [.quest, .arena, .activity])
        XCTAssertEqual(missingRepository.hudDetailLineLimit, 3)
    }

    func testLowReadabilityFallsBackToReadableOverlay() {
        let plan = makeOverlayPlan(
            phase: .verifying,
            readability: CinematicNarrativeCueReadabilitySignals(
                hasQuestPlaque: true,
                hasArenaInscription: true,
                hasActivityBanner: true,
                readableCueCount: 3,
                minimumScale: 0.66,
                minimumOpacity: 0.24,
                minimumPrimaryFontSize: 0.09,
                minimumBackingOpacity: 0.07,
                hasReadableText: true,
                hasReadableLayout: true
            )
        )

        XCTAssertEqual(plan.mode, .fallback)
        XCTAssertEqual(plan.reasonIdentifier, "low-narrative-readability")
        XCTAssertEqual(plan.visiblePills, [.quest, .arena, .activity])
        XCTAssertEqual(plan.hudProminence, .full)
        XCTAssertEqual(plan.pillLineLimit, 2)
        XCTAssertEqual(plan.hudStatusLineLimit, 2)
        XCTAssertTrue(plan.identifier.contains("readability:"))
    }

    func testDisplayValuesStayBoundedAcrossRepresentativeStates() {
        let plans = [
            makeOverlayPlan(phase: .idle, isRunning: false),
            makeOverlayPlan(phase: .planning, influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)),
            makeOverlayPlan(phase: .developing),
            makeOverlayPlan(phase: .verifying, influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)),
            makeOverlayPlan(phase: .succeeded),
            makeOverlayPlan(phase: .failed),
            makeOverlayPlan(phase: .developing, isPaused: true),
            makeOverlayPlan(phase: .developing, hasRepository: false),
            makeOverlayPlan(phase: .developing, activityProfile: .empty)
        ]

        for plan in plans {
            XCTAssertInRange(plan.gradientStrength, CinematicOverlayDisplayPlan.gradientStrengthRange)
            XCTAssertInRange(plan.worldTextMaxWidth, CinematicOverlayDisplayPlan.worldTextMaxWidthRange)
            XCTAssertInRange(plan.hudMaxWidth, CinematicOverlayDisplayPlan.hudMaxWidthRange)
            XCTAssertInRange(plan.overlayOpacity, CinematicOverlayDisplayPlan.overlayOpacityRange)
            XCTAssertInRange(plan.pillLineLimit, CinematicOverlayDisplayPlan.pillLineLimitRange)
            XCTAssertInRange(plan.hudTitleLineLimit, CinematicOverlayDisplayPlan.hudTitleLineLimitRange)
            XCTAssertInRange(plan.hudDetailLineLimit, CinematicOverlayDisplayPlan.hudDetailLineLimitRange)
            XCTAssertInRange(plan.hudProfileLineLimit, CinematicOverlayDisplayPlan.hudProfileLineLimitRange)
            XCTAssertInRange(plan.hudStatusLineLimit, CinematicOverlayDisplayPlan.hudStatusLineLimitRange)
            XCTAssertFalse(plan.identifier.isEmpty)
            XCTAssertFalse(plan.reasonIdentifier.isEmpty)
            XCTAssertFalse(plan.narrativeCueReadabilityIdentifier.isEmpty)
        }
    }

    func testNarrativeCueReadabilityFromPlannerEnablesCompactOverlay() {
        let languageProfile = languageProfile(primaryLanguage: .swift)
        let activityProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 3))
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.65)
        let worldText = worldText()
        let briefing = briefing()
        let readability = CinematicOverlayDisplayPlanner.narrativeCueReadabilitySignals(
            phase: .developing,
            worldText: worldText,
            briefing: briefing,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings
        )

        let plan = CinematicOverlayDisplayPlanner.plan(
            phase: .developing,
            isRunning: true,
            isAutoPlaying: false,
            isPaused: false,
            hasRepository: true,
            worldText: worldText,
            briefing: briefing,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings,
            narrativeCueReadability: readability
        )

        XCTAssertTrue(readability.isReadable)
        XCTAssertGreaterThanOrEqual(readability.minimumOpacity, CinematicNarrativeCueReadabilitySignals.readableOpacityThreshold)
        XCTAssertGreaterThanOrEqual(readability.minimumPrimaryFontSize, CinematicNarrativeCueReadabilitySignals.readablePrimaryFontSizeThreshold)
        XCTAssertEqual(plan.mode, .compact)
        XCTAssertEqual(plan.reasonIdentifier, "in-world-readable-cues")
    }
}

private func makeOverlayPlan(
    phase: LoopPhase,
    isRunning: Bool = true,
    isAutoPlaying: Bool = false,
    isPaused: Bool = false,
    hasRepository: Bool = true,
    worldText: CinematicWorldText = worldText(),
    briefing: CinematicBriefing = briefing(),
    languageProfile: RepositoryLanguageProfile = languageProfile(primaryLanguage: .swift),
    activityProfile: RepositoryActivityProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
    influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.6),
    readability: CinematicNarrativeCueReadabilitySignals = readableSignals()
) -> CinematicOverlayDisplayPlan {
    CinematicOverlayDisplayPlanner.plan(
        phase: phase,
        isRunning: isRunning,
        isAutoPlaying: isAutoPlaying,
        isPaused: isPaused,
        hasRepository: hasRepository,
        worldText: worldText,
        briefing: briefing,
        languageProfile: languageProfile,
        activityProfile: activityProfile,
        influenceSettings: influenceSettings,
        narrativeCueReadability: readability
    )
}

private func readableSignals() -> CinematicNarrativeCueReadabilitySignals {
    CinematicNarrativeCueReadabilitySignals(
        hasQuestPlaque: true,
        hasArenaInscription: true,
        hasActivityBanner: true,
        readableCueCount: 3,
        minimumScale: 0.92,
        minimumOpacity: 0.56,
        minimumPrimaryFontSize: 0.13,
        minimumBackingOpacity: 0.14,
        hasReadableText: true,
        hasReadableLayout: true
    )
}

private func worldText() -> CinematicWorldText {
    CinematicWorldText(
        questLabel: "Swift forge: Overlay policy",
        arenaCallout: "Comet forge over Compass",
        activityCallout: "Pressure shard: Tests shaping display"
    )
}

private func briefing() -> CinematicBriefing {
    CinematicBriefing(
        title: "Compass: Overlay policy",
        detail: "Developing with deterministic cinematic overlay routing."
    )
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
