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
        XCTAssertTrue(plan.chromeStyleIdentifier.hasPrefix("compact-active|"))
        XCTAssertLessThan(plan.worldTextPillBackgroundOpacity, 0.28)
        XCTAssertLessThan(plan.hudBackgroundOpacity, 0.30)
        XCTAssertTrue(plan.identifier.contains("mode:compact"))
        XCTAssertTrue(plan.identifier.contains("chrome:\(plan.chromeStyleIdentifier)"))
    }

    func testPlanningSuccessAndFailureRemainCompactWhenCuesAreReadable() {
        let planning = makeOverlayPlan(phase: .planning)
        let developing = makeOverlayPlan(phase: .developing)
        let succeeded = makeOverlayPlan(phase: .succeeded)
        let failed = makeOverlayPlan(phase: .failed)

        XCTAssertEqual(planning.mode, .compact)
        XCTAssertEqual(planning.visiblePills, [.quest])
        XCTAssertEqual(planning.hudProminence, .compact)
        XCTAssertTrue(planning.showsHUDDetail)
        XCTAssertTrue(planning.chromeStyleIdentifier.hasPrefix("compact-readable|"))
        XCTAssertGreaterThan(planning.worldTextPillBackgroundOpacity, developing.worldTextPillBackgroundOpacity)
        XCTAssertGreaterThan(planning.hudBackgroundOpacity, developing.hudBackgroundOpacity)
        XCTAssertGreaterThan(planning.hudDetailTextEmphasis, developing.hudDetailTextEmphasis)

        XCTAssertEqual(succeeded.mode, .compact)
        XCTAssertEqual(succeeded.visiblePills, [.activity])
        XCTAssertEqual(succeeded.hudProminence, .compact)
        XCTAssertEqual(succeeded.chromeStyleIdentifier, failed.chromeStyleIdentifier)

        XCTAssertEqual(failed.mode, .compact)
        XCTAssertEqual(failed.visiblePills, [.activity])
        XCTAssertEqual(failed.hudProminence, .compact)
    }

    func testFullAndFallbackChromeStylesStayIntentionallyStrongerThanCompact() {
        let active = makeOverlayPlan(phase: .developing)
        let readableCompact = makeOverlayPlan(phase: .planning)
        let full = makeOverlayPlan(phase: .idle, isRunning: false)
        let fallback = makeOverlayPlan(phase: .developing, hasRepository: false)

        XCTAssertTrue(full.chromeStyleIdentifier.hasPrefix("full-readable|"))
        XCTAssertTrue(fallback.chromeStyleIdentifier.hasPrefix("fallback-readable|"))
        XCTAssertGreaterThan(readableCompact.worldTextPillBackgroundOpacity, active.worldTextPillBackgroundOpacity)
        XCTAssertGreaterThan(full.worldTextPillBackgroundOpacity, readableCompact.worldTextPillBackgroundOpacity)
        XCTAssertGreaterThan(fallback.worldTextPillBackgroundOpacity, full.worldTextPillBackgroundOpacity)
        XCTAssertGreaterThan(readableCompact.hudStrokeOpacity, active.hudStrokeOpacity)
        XCTAssertGreaterThan(full.hudStrokeOpacity, readableCompact.hudStrokeOpacity)
        XCTAssertGreaterThan(fallback.hudStrokeOpacity, full.hudStrokeOpacity)
        XCTAssertGreaterThan(full.hudTitleEmphasis, active.hudTitleEmphasis)
        XCTAssertGreaterThanOrEqual(fallback.hudTitleEmphasis, full.hudTitleEmphasis)
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
            assertChromeStyleBounds(plan)
            XCTAssertFalse(plan.identifier.isEmpty)
            XCTAssertFalse(plan.chromeStyleIdentifier.isEmpty)
            XCTAssertFalse(plan.reasonIdentifier.isEmpty)
            XCTAssertFalse(plan.narrativeCueReadabilityIdentifier.isEmpty)
            XCTAssertFalse(plan.nativeFeedbackCueIdentifier.isEmpty)
            XCTAssertFalse(plan.nativeFeedbackBannerPolicyIdentifier.isEmpty)
        }
    }

    func testChromeStyleIdentifierIsStableForEquivalentInputs() {
        let first = makeOverlayPlan(
            phase: .verifying,
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.9)
        )
        let repeated = makeOverlayPlan(
            phase: .verifying,
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.9)
        )
        let full = makeOverlayPlan(phase: .idle, isRunning: false)

        XCTAssertEqual(first.chromeStyleIdentifier, repeated.chromeStyleIdentifier)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.chromeStyleIdentifier, full.chromeStyleIdentifier)
        XCTAssertTrue(first.chromeStyleIdentifier.contains("pill:bg"))
        XCTAssertTrue(first.chromeStyleIdentifier.contains("hud:bg"))
        XCTAssertTrue(first.chromeStyleIdentifier.contains("status"))
    }

    func testOverlayIdentifierCarriesNativeFeedbackCue() throws {
        let nativeCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )

        let plan = makeOverlayPlan(
            phase: .verifying,
            nativeFeedbackCue: nativeCue
        )
        let plain = makeOverlayPlan(phase: .verifying)

        XCTAssertEqual(plan.nativeFeedbackCueIdentifier, nativeCue.identifier)
        XCTAssertTrue(plan.identifier.contains("native:\(nativeCue.identifier)"))
        XCTAssertEqual(plain.nativeFeedbackCueIdentifier, "none")
        XCTAssertTrue(plain.identifier.contains("native:none"))
        XCTAssertNotEqual(plan.identifier, plain.identifier)
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

    func testNativeFeedbackReadabilitySignalsStayReadableAndAffectOverlayIdentifier() throws {
        let languageProfile = languageProfile(primaryLanguage: .swift)
        let activityProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 3))
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.8)
        let nativeCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        let plain = CinematicOverlayDisplayPlanner.narrativeCueReadabilitySignals(
            phase: .verifying,
            worldText: worldText(),
            briefing: briefing(),
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings
        )
        let withNativeCue = CinematicOverlayDisplayPlanner.narrativeCueReadabilitySignals(
            phase: .verifying,
            worldText: worldText(),
            briefing: briefing(),
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings,
            nativeFeedbackCue: nativeCue
        )

        XCTAssertTrue(plain.isReadable)
        XCTAssertTrue(withNativeCue.isReadable)
        XCTAssertNotEqual(withNativeCue.identifier, plain.identifier)
        XCTAssertGreaterThanOrEqual(withNativeCue.minimumScale, CinematicNarrativeCueReadabilitySignals.readableScaleThreshold)
        XCTAssertGreaterThanOrEqual(withNativeCue.minimumOpacity, CinematicNarrativeCueReadabilitySignals.readableOpacityThreshold)
        XCTAssertGreaterThanOrEqual(withNativeCue.minimumPrimaryFontSize, CinematicNarrativeCueReadabilitySignals.readablePrimaryFontSizeThreshold)
        XCTAssertGreaterThanOrEqual(withNativeCue.minimumBackingOpacity, CinematicNarrativeCueReadabilitySignals.readableBackingOpacityThreshold)

        let overlay = CinematicOverlayDisplayPlanner.plan(
            phase: .verifying,
            isRunning: true,
            isAutoPlaying: false,
            isPaused: false,
            hasRepository: true,
            worldText: worldText(),
            briefing: briefing(),
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings,
            narrativeCueReadability: withNativeCue,
            nativeFeedbackCue: nativeCue
        )

        XCTAssertEqual(overlay.nativeFeedbackCueIdentifier, nativeCue.identifier)
        XCTAssertTrue(overlay.identifier.contains("native:\(nativeCue.identifier)"))
        XCTAssertEqual(overlay.mode, .compact)
    }

    func testQuietModeCalmsChromeAndSuppressesNonCriticalNativeFeedbackBanner() throws {
        let nativeCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        let standard = makeOverlayPlan(
            phase: .verifying,
            nativeFeedbackCue: nativeCue
        )
        let quiet = makeOverlayPlan(
            phase: .verifying,
            influenceSettings: CinematicInfluenceSettings(
                cameraStyle: .follow,
                comfortMode: .quiet,
                intensity: 0.6
            ),
            nativeFeedbackCue: nativeCue
        )

        XCTAssertTrue(standard.showsNativeFeedbackBanner)
        XCTAssertEqual(standard.nativeFeedbackBannerPolicyIdentifier, "visible")
        XCTAssertFalse(quiet.showsNativeFeedbackBanner)
        XCTAssertEqual(quiet.nativeFeedbackBannerPolicyIdentifier, "suppressed-quiet-noncritical")
        XCTAssertEqual(quiet.nativeFeedbackCueIdentifier, nativeCue.identifier)
        XCTAssertLessThan(quiet.gradientStrength, standard.gradientStrength)
        XCTAssertLessThan(quiet.hudBackgroundOpacity, standard.hudBackgroundOpacity)
        XCTAssertLessThan(quiet.worldTextPillBackgroundOpacity, standard.worldTextPillBackgroundOpacity)
        XCTAssertTrue(quiet.chromeStyleIdentifier.hasPrefix("compact-active-quiet|"))
        XCTAssertTrue(quiet.identifier.contains("comfort:quiet"))
        XCTAssertTrue(quiet.identifier.contains("native-banner:suppressed-quiet-noncritical"))
    }

    func testQuietModeStillAllowsRetryWarningAndFailureNativeFeedbackBanners() throws {
        let retryCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        let failureCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .postChecksFailed,
                content: NativeFeedbackContent(milestone: .postChecksFailed, projectName: "Editor"),
                phase: .failed,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )

        for cue in [retryCue, failureCue] {
            let plan = makeOverlayPlan(
                phase: cue.phase,
                influenceSettings: CinematicInfluenceSettings(
                    cameraStyle: .follow,
                    comfortMode: .quiet,
                    intensity: 0.6
                ),
                nativeFeedbackCue: cue
            )

            XCTAssertTrue(plan.showsNativeFeedbackBanner, cue.identifier)
            XCTAssertEqual(plan.nativeFeedbackBannerPolicyIdentifier, "visible")
            XCTAssertTrue(plan.identifier.contains("native-banner:visible"))
        }
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
    readability: CinematicNarrativeCueReadabilitySignals = readableSignals(),
    nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil
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
        narrativeCueReadability: readability,
        nativeFeedbackCue: nativeFeedbackCue
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

private func assertChromeStyleBounds(
    _ plan: CinematicOverlayDisplayPlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(
        plan.worldTextPillBackgroundOpacity,
        CinematicOverlayDisplayPlan.worldTextPillBackgroundOpacityRange,
        file: file,
        line: line
    )
    XCTAssertInRange(
        plan.worldTextPillStrokeOpacity,
        CinematicOverlayDisplayPlan.worldTextPillStrokeOpacityRange,
        file: file,
        line: line
    )
    XCTAssertInRange(
        plan.worldTextPillHorizontalPadding,
        CinematicOverlayDisplayPlan.worldTextPillHorizontalPaddingRange,
        file: file,
        line: line
    )
    XCTAssertInRange(
        plan.worldTextPillVerticalPadding,
        CinematicOverlayDisplayPlan.worldTextPillVerticalPaddingRange,
        file: file,
        line: line
    )
    XCTAssertInRange(
        plan.worldTextPillCornerRadius,
        CinematicOverlayDisplayPlan.worldTextPillCornerRadiusRange,
        file: file,
        line: line
    )
    XCTAssertInRange(
        plan.worldTextPillIconEmphasis,
        CinematicOverlayDisplayPlan.worldTextPillIconEmphasisRange,
        file: file,
        line: line
    )
    XCTAssertInRange(
        plan.worldTextPillTextEmphasis,
        CinematicOverlayDisplayPlan.worldTextPillTextEmphasisRange,
        file: file,
        line: line
    )
    XCTAssertInRange(plan.hudBackgroundOpacity, CinematicOverlayDisplayPlan.hudBackgroundOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.hudStrokeOpacity, CinematicOverlayDisplayPlan.hudStrokeOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.hudHorizontalPadding, CinematicOverlayDisplayPlan.hudHorizontalPaddingRange, file: file, line: line)
    XCTAssertInRange(plan.hudVerticalPadding, CinematicOverlayDisplayPlan.hudVerticalPaddingRange, file: file, line: line)
    XCTAssertInRange(plan.hudCornerRadius, CinematicOverlayDisplayPlan.hudCornerRadiusRange, file: file, line: line)
    XCTAssertInRange(plan.hudIconEmphasis, CinematicOverlayDisplayPlan.hudIconEmphasisRange, file: file, line: line)
    XCTAssertInRange(plan.hudTitleEmphasis, CinematicOverlayDisplayPlan.hudTitleEmphasisRange, file: file, line: line)
    XCTAssertInRange(plan.hudDetailTextEmphasis, CinematicOverlayDisplayPlan.hudDetailTextEmphasisRange, file: file, line: line)
    XCTAssertInRange(plan.hudStatusTextEmphasis, CinematicOverlayDisplayPlan.hudStatusTextEmphasisRange, file: file, line: line)
    XCTAssertInRange(
        plan.hudPhaseBackgroundOpacity,
        CinematicOverlayDisplayPlan.hudPhaseBackgroundOpacityRange,
        file: file,
        line: line
    )
    XCTAssertInRange(plan.hudAccentOpacity, CinematicOverlayDisplayPlan.hudAccentOpacityRange, file: file, line: line)
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
