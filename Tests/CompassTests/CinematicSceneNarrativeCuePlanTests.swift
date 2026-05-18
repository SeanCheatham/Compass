import Foundation
@testable import Compass
import XCTest

final class CinematicSceneNarrativeCuePlanTests: XCTestCase {
    func testPlannerOutputIsDeterministicForRepeatedInputs() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.72)
        let profile = activityProfile(worktreeChanges: worktreeChanges(modified: 4))

        let first = narrativeCuePlan(
            phase: .developing,
            activityProfile: profile,
            settings: settings
        )
        let second = narrativeCuePlan(
            phase: .developing,
            activityProfile: profile,
            settings: settings
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.stageBeatIdentifier, second.stageBeatIdentifier)
        XCTAssertEqual(first.questPlaque.stableID, "narrative.quest.plaque")
        XCTAssertEqual(first.arenaInscription.stableID, "narrative.arena.inscription")
        XCTAssertEqual(first.activityBanner.stableID, "narrative.activity.banner")
        XCTAssertEqual(first.questPlaque.anchor, .leftForgePylon)
        XCTAssertEqual(first.arenaInscription.anchor, .arenaFront)
        XCTAssertEqual(first.activityBanner.anchor, .rightWarningPylon)
        XCTAssertEqual(first.questPlaque.visibility, .visible)
        XCTAssertEqual(first.activityBanner.lightFamily, .pressure)
        XCTAssertFalse(first.questPlaque.identifier.isEmpty)
        XCTAssertFalse(first.arenaInscription.identifier.isEmpty)
        XCTAssertFalse(first.activityBanner.identifier.isEmpty)
        XCTAssertEqual(first.questPlaque.layout, second.questPlaque.layout)
        XCTAssertEqual(first.questPlaque.layout.facingMode, .arenaCamera)
        XCTAssertEqual(first.activityBanner.layout.facingMode, .arenaCamera)
        XCTAssertEqual(first.arenaInscription.layout.facingMode, .floorInscription)
        XCTAssertTrue(first.questPlaque.identifier.contains(first.questPlaque.layout.identifier))
        XCTAssertTrue(first.arenaInscription.identifier.contains(first.arenaInscription.layout.identifier))
        XCTAssertTrue(first.activityBanner.identifier.contains(first.activityBanner.layout.identifier))
    }

    func testDisplayedStringsAreClampedToWorldTextAndBriefingBounds() {
        let plan = narrativeCuePlan(
            phase: .developing,
            worldText: CinematicWorldText(
                questLabel: "Implement a very long `quest` label with https://example.com extra tokens and #markdown markers",
                arenaCallout: "Extremely large arena callout over a repository with far too many descriptive words included",
                activityCallout: "Pressure shard: generated files modified deleted renamed untracked conflicted and many other changes"
            ),
            briefing: CinematicBriefing(
                title: "A deliberately oversized briefing title that should be clamped before it becomes an in world plaque subtitle",
                detail: "Detail is carried by the overlay and should not affect compact plaque bounds."
            ),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 7)),
            settings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.5)
        )

        assertCueTextBounds(plan.questPlaque, maxCharacters: CinematicWorldTextService.questLabelMaxCharacters, maxWords: CinematicWorldTextService.questLabelMaxWords)
        assertCueTextBounds(plan.arenaInscription, maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters, maxWords: CinematicWorldTextService.arenaCalloutMaxWords)
        assertCueTextBounds(plan.activityBanner, maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters, maxWords: CinematicWorldTextService.activityCalloutMaxWords)
        XCTAssertLessThanOrEqual(
            plan.questPlaque.secondaryText?.count ?? 0,
            CinematicBriefingService.titleMaxCharacters
        )
        XCTAssertFalse(plan.questPlaque.text.contains("https://"))
        XCTAssertFalse(plan.questPlaque.text.contains("`"))
        XCTAssertFalse(plan.questPlaque.text.contains("#"))
        assertNarrativeCuePlanInBounds(plan)
    }

    func testPhaseAndActivityStatesUseDifferentAnchors() {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.5)
        let clean = activityProfile()
        let dirty = activityProfile(worktreeChanges: worktreeChanges(modified: 3))
        let commit = activityProfile(recentCommitCount: 2)
        let failed = activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 1)
        let success = activityProfile(lastTerminalStatus: .succeeded, successStreak: 3)

        let planning = narrativeCuePlan(phase: .planning, activityProfile: clean, settings: settings)
        let developing = narrativeCuePlan(phase: .developing, activityProfile: clean, settings: settings)
        let verifying = narrativeCuePlan(phase: .verifying, activityProfile: clean, settings: settings)
        let succeeded = narrativeCuePlan(phase: .succeeded, activityProfile: success, settings: settings)
        let failure = narrativeCuePlan(phase: .failed, activityProfile: failed, settings: settings)
        let dirtyActivity = narrativeCuePlan(phase: .developing, activityProfile: dirty, settings: settings)
        let commitActivity = narrativeCuePlan(phase: .developing, activityProfile: commit, settings: settings)

        XCTAssertEqual(planning.questPlaque.anchor, .leftScoutPylon)
        XCTAssertEqual(developing.questPlaque.anchor, .leftForgePylon)
        XCTAssertEqual(verifying.questPlaque.anchor, .leftSealPylon)
        XCTAssertEqual(succeeded.questPlaque.anchor, .victoryArch)
        XCTAssertEqual(failure.questPlaque.anchor, .fractureGate)
        XCTAssertEqual(developing.arenaInscription.anchor, .arenaFront)
        XCTAssertEqual(verifying.arenaInscription.anchor, .arenaRear)
        XCTAssertEqual(dirtyActivity.activityBanner.anchor, .rightWarningPylon)
        XCTAssertEqual(commitActivity.activityBanner.anchor, .rightHistoryPylon)
        XCTAssertNotEqual(planning.questPlaque.layout.anchorPosition, planning.activityBanner.layout.anchorPosition)
        XCTAssertGreaterThan(dirtyActivity.activityBanner.layout.anchorPosition.x, dirtyActivity.questPlaque.layout.anchorPosition.x)
        XCTAssertEqual(verifying.arenaInscription.layout.facingMode, .floorInscription)
        XCTAssertNotEqual(planning.questPlaque.identifier, developing.questPlaque.identifier)
        XCTAssertNotEqual(dirtyActivity.activityBanner.identifier, commitActivity.activityBanner.identifier)
    }

    func testInfluenceChangesVisualsWithinBounds() {
        let profile = activityProfile(worktreeChanges: worktreeChanges(modified: 9))
        let steady = narrativeCuePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)
        )
        let dramatic = narrativeCuePlan(
            phase: .verifying,
            activityProfile: profile,
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        assertNarrativeCuePlanInBounds(steady)
        assertNarrativeCuePlanInBounds(dramatic)
        XCTAssertGreaterThan(dramatic.questPlaque.scale, steady.questPlaque.scale)
        XCTAssertGreaterThan(dramatic.activityBanner.opacity, steady.activityBanner.opacity)
        XCTAssertLessThan(dramatic.arenaInscription.cadence, steady.arenaInscription.cadence)
        XCTAssertGreaterThan(dramatic.questPlaque.layout.plateSize.x, steady.questPlaque.layout.plateSize.x)
        XCTAssertGreaterThan(dramatic.arenaInscription.layout.primaryFontSize, steady.arenaInscription.layout.primaryFontSize)
        XCTAssertGreaterThan(dramatic.activityBanner.layout.backingOpacity, steady.activityBanner.layout.backingOpacity)
        XCTAssertNotEqual(dramatic.influenceIdentifier, steady.influenceIdentifier)
        XCTAssertNotEqual(dramatic.identifier, steady.identifier)
    }

    func testFeaturedVisibilityStrengthensReadabilityWithoutOverpoweringFloorBacking() {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.5)
        let visible = narrativeCuePlan(
            phase: .developing,
            activityProfile: activityProfile(),
            settings: settings
        )
        let featured = narrativeCuePlan(
            phase: .succeeded,
            activityProfile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 2),
            settings: settings
        )

        XCTAssertEqual(visible.questPlaque.visibility, .visible)
        XCTAssertEqual(featured.questPlaque.visibility, .featured)
        XCTAssertGreaterThan(featured.questPlaque.layout.plateSize.x, visible.questPlaque.layout.plateSize.x)
        XCTAssertGreaterThan(featured.questPlaque.layout.primaryFontSize, visible.questPlaque.layout.primaryFontSize)
        XCTAssertGreaterThan(featured.activityBanner.layout.backingOpacity, visible.activityBanner.layout.backingOpacity)
        XCTAssertLessThan(featured.arenaInscription.layout.backingOpacity, featured.questPlaque.layout.backingOpacity)
        XCTAssertLessThan(featured.arenaInscription.layout.backingOpacity, featured.activityBanner.layout.backingOpacity)
    }

    func testActivityBannerLayoutsStaySeparatedAcrossPhaseAndActivityStates() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        let samples = [
            narrativeCuePlan(phase: .planning, activityProfile: activityProfile(), settings: settings),
            narrativeCuePlan(
                phase: .developing,
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 5)),
                settings: settings
            ),
            narrativeCuePlan(phase: .verifying, activityProfile: activityProfile(), settings: settings),
            narrativeCuePlan(
                phase: .succeeded,
                activityProfile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 2),
                settings: settings
            ),
            narrativeCuePlan(
                phase: .failed,
                activityProfile: activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 1),
                settings: settings
            ),
            narrativeCuePlan(
                phase: .idle,
                activityProfile: .empty,
                settings: settings
            )
        ]

        for plan in samples {
            assertActivityBannerSeparated(from: plan.questPlaque, and: plan.arenaInscription, in: plan)
            XCTAssertEqual(plan.activityBanner.layout.glyphSide, .trailing)
            XCTAssertGreaterThan(plan.activityBanner.layout.glyphOffset.x, 0)
        }
    }

    func testIdleUnavailableInputsUseNeutralPlaceholders() {
        let plan = narrativeCuePlan(
            phase: .idle,
            worldText: CinematicWorldText(
                questLabel: "Should not appear",
                arenaCallout: "Should not appear",
                activityCallout: "Should not appear"
            ),
            briefing: CinematicBriefing(
                title: "Should not appear",
                detail: "Should not appear"
            ),
            activityProfile: .empty,
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        XCTAssertEqual(plan.questPlaque.text, CinematicWorldText.placeholder.questLabel)
        XCTAssertEqual(plan.questPlaque.secondaryText, CinematicBriefing.placeholder.title)
        XCTAssertEqual(plan.arenaInscription.text, CinematicWorldText.placeholder.arenaCallout)
        XCTAssertEqual(plan.activityBanner.text, CinematicWorldText.placeholder.activityCallout)
        XCTAssertEqual(plan.questPlaque.anchor, .idleArchive)
        XCTAssertEqual(plan.activityBanner.anchor, .idleArchive)
        XCTAssertEqual(plan.questPlaque.visibility, .dim)
        XCTAssertEqual(plan.questPlaque.scale, CinematicSceneNarrativeCuePlan.cueScaleRange.lowerBound)
        XCTAssertEqual(plan.questPlaque.opacity, 0.24)
        XCTAssertEqual(plan.questPlaque.cadence, CinematicSceneNarrativeCuePlan.cueCadenceRange.upperBound)
        XCTAssertEqual(plan.questPlaque.lightFamily, .lifecycle)
        XCTAssertEqual(plan.questPlaque.tintFamily, .lifecycle)
        XCTAssertEqual(plan.questPlaque.layout.anchorPosition, [-5.05, 1.08, 3.22])
        XCTAssertEqual(plan.activityBanner.layout.anchorPosition, [5.05, 1.16, 3.22])
        XCTAssertEqual(plan.arenaInscription.layout.anchorPosition, [0, 0.13, 0.72])
        XCTAssertEqual(plan.arenaInscription.layout.facingMode, .floorInscription)
        XCTAssertEqual(plan.arenaInscription.layout.backingOpacity, 0.1)
        XCTAssertLessThan(plan.questPlaque.layout.plateSize.x, 2.7)
        XCTAssertLessThan(plan.activityBanner.layout.backingOpacity, plan.questPlaque.layout.backingOpacity)
        assertNarrativeCuePlanInBounds(plan)
    }

    func testNilNativeFeedbackCueKeepsPlannerOutputUnchanged() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.72)
        let activity = activityProfile(worktreeChanges: worktreeChanges(modified: 4))
        let omitted = narrativeCuePlan(
            phase: .developing,
            activityProfile: activity,
            settings: settings
        )
        let explicitNil = narrativeCuePlan(
            phase: .developing,
            activityProfile: activity,
            settings: settings,
            nativeFeedbackCue: nil
        )

        XCTAssertEqual(omitted, explicitNil)
        XCTAssertEqual(omitted.identifier, explicitNil.identifier)
        XCTAssertEqual(omitted.nativeFeedbackCueIdentifier, "none")
        XCTAssertEqual(omitted.nativeFeedbackAffectedDescriptorIdentifiers, [])
        XCTAssertFalse(omitted.identifier.contains("native-feedback:"))
    }

    func testVerifyStartedNativeFeedbackFeedsSealPlaques() throws {
        let nativeCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )

        let plan = narrativeCuePlan(
            phase: .verifying,
            activityProfile: activityProfile(),
            settings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.6),
            nativeFeedbackCue: nativeCue
        )

        XCTAssertEqual(plan.nativeFeedbackCueIdentifier, nativeCue.identifier)
        XCTAssertEqual(plan.nativeFeedbackSourceIdentifier, "native:verifyStarted")
        XCTAssertEqual(plan.nativeFeedbackStyleIdentifier, "verify")
        XCTAssertEqual(plan.nativeFeedbackMilestoneIdentifier, "verifyStarted")
        XCTAssertEqual(
            plan.nativeFeedbackAffectedDescriptorIdentifiers,
            ["narrative.quest.plaque", "narrative.arena.inscription", "narrative.activity.banner"]
        )
        XCTAssertTrue(plan.identifier.contains("native-feedback:\(nativeCue.identifier)"))
        XCTAssertTrue(plan.questPlaque.text.lowercased().contains("verify"))
        XCTAssertTrue(plan.questPlaque.text.lowercased().contains("seal"))
        XCTAssertTrue(plan.questPlaque.secondaryText?.contains("native:verifyStarted") == true)
        XCTAssertTrue(plan.arenaInscription.text.lowercased().contains("seal"))
        XCTAssertTrue(plan.activityBanner.text.lowercased().contains("verify"))
        XCTAssertEqual(plan.questPlaque.glyphIdentifier, "checkmark.seal")
        XCTAssertEqual(plan.questPlaque.anchor, .leftSealPylon)
        XCTAssertEqual(plan.arenaInscription.anchor, .arenaRear)
        XCTAssertEqual(plan.activityBanner.anchor, .rightHistoryPylon)
        XCTAssertEqual(plan.questPlaque.visibility, .featured)
        XCTAssertEqual(plan.questPlaque.lightFamily, .verify)
        XCTAssertEqual(plan.activityBanner.tintFamily, .verify)
        assertCueTextBounds(plan.questPlaque, maxCharacters: CinematicWorldTextService.questLabelMaxCharacters, maxWords: CinematicWorldTextService.questLabelMaxWords)
        assertCueTextBounds(plan.arenaInscription, maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters, maxWords: CinematicWorldTextService.arenaCalloutMaxWords)
        assertCueTextBounds(plan.activityBanner, maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters, maxWords: CinematicWorldTextService.activityCalloutMaxWords)
        assertNarrativeCuePlanInBounds(plan)
    }

    func testDevelopRetryingRunCueFeedsFailureAnchorsAndMetadata() throws {
        let nativeCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [
                    7: runCue(
                        kind: .failedVerify,
                        severity: .failure,
                        label: "Retry Develop",
                        detail: "Expected true but got false",
                        systemImage: "checkmark.seal.fill"
                    )
                ]
            )
        )

        let plan = narrativeCuePlan(
            phase: .developing,
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 3)),
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.9),
            nativeFeedbackCue: nativeCue
        )

        XCTAssertEqual(plan.nativeFeedbackSourceIdentifier, "run-cue:7:failedVerify")
        XCTAssertEqual(plan.nativeFeedbackStyleIdentifier, "failure")
        XCTAssertEqual(plan.questPlaque.glyphIdentifier, "checkmark.seal.fill")
        XCTAssertTrue(plan.questPlaque.text.lowercased().contains("failure"))
        XCTAssertTrue(plan.questPlaque.text.lowercased().contains("anchor"))
        XCTAssertTrue(plan.questPlaque.secondaryText?.contains("run-cue:7:failedVerify") == true)
        XCTAssertTrue(plan.arenaInscription.text.contains("failedVerify"))
        XCTAssertTrue(plan.activityBanner.text.contains("failedVerify"))
        XCTAssertEqual(plan.questPlaque.anchor, .fractureGate)
        XCTAssertEqual(plan.arenaInscription.anchor, .fractureGate)
        XCTAssertEqual(plan.activityBanner.anchor, .rightWarningPylon)
        XCTAssertEqual(plan.questPlaque.lightFamily, .failure)
        XCTAssertEqual(plan.activityBanner.tintFamily, .failure)
        XCTAssertEqual(plan.activityBanner.visibility, .featured)
        assertCueTextBounds(plan.questPlaque, maxCharacters: CinematicWorldTextService.questLabelMaxCharacters, maxWords: CinematicWorldTextService.questLabelMaxWords)
        assertCueTextBounds(plan.arenaInscription, maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters, maxWords: CinematicWorldTextService.arenaCalloutMaxWords)
        assertCueTextBounds(plan.activityBanner, maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters, maxWords: CinematicWorldTextService.activityCalloutMaxWords)
        assertNarrativeCuePlanInBounds(plan)

        let warningCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [
                    11: runCue(
                        kind: .dirtyWorktree,
                        severity: .warning,
                        label: "Clean Worktree",
                        detail: "2 pending changes",
                        systemImage: "pencil.and.outline"
                    )
                ]
            )
        )
        let warningPlan = narrativeCuePlan(
            phase: .developing,
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
            settings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.6),
            nativeFeedbackCue: warningCue
        )

        XCTAssertEqual(warningPlan.nativeFeedbackSourceIdentifier, "run-cue:11:dirtyWorktree")
        XCTAssertEqual(warningPlan.nativeFeedbackStyleIdentifier, "warning")
        XCTAssertTrue(warningPlan.questPlaque.text.lowercased().contains("warning"))
        XCTAssertTrue(warningPlan.activityBanner.text.contains("dirtyWorktree"))
        XCTAssertEqual(warningPlan.questPlaque.anchor, .rightWarningPylon)
        XCTAssertEqual(warningPlan.arenaInscription.anchor, .fractureGate)
        XCTAssertEqual(warningPlan.activityBanner.anchor, .rightWarningPylon)
        XCTAssertEqual(warningPlan.questPlaque.lightFamily, .pressure)
        XCTAssertEqual(warningPlan.activityBanner.tintFamily, .failure)
        assertNarrativeCuePlanInBounds(warningPlan)
    }
}

private func narrativeCuePlan(
    phase: LoopPhase,
    worldText: CinematicWorldText? = nil,
    briefing: CinematicBriefing? = nil,
    languageProfile: RepositoryLanguageProfile = languageProfile(primaryLanguage: .swift),
    activityProfile: RepositoryActivityProfile,
    settings: CinematicInfluenceSettings,
    nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil
) -> CinematicSceneNarrativeCuePlan {
    let latestEvent: CinematicBriefingEvent? = nil
    let inputWorldText = worldText ?? CinematicWorldTextService.deterministicWorldText(
        for: CinematicWorldTextInput(
            repoName: "Compass",
            currentPhase: phase.rawValue,
            immediatePlanTitle: "Add deterministic narrative scene cues",
            completedCount: 2,
            latestEvent: latestEvent,
            languageProfile: languageProfile,
            activityProfile: activityProfile
        )
    )
    let inputBriefing = briefing ?? CinematicBriefingService.deterministicBriefing(
        for: CinematicBriefingInput(
            repoName: "Compass",
            currentPhase: phase.rawValue,
            immediatePlanTitle: "Add deterministic narrative scene cues",
            completedCount: 2,
            latestEvent: latestEvent
        )
    )
    let languageMotif = CinematicMotif.language(for: languageProfile)
    let activityMotif = CinematicMotif.activity(for: activityProfile)
    let beat = CinematicStageBeatPlanner.plan(
        phase: phase,
        activityProfile: activityProfile,
        influenceSettings: settings
    )
    let setDressing = CinematicSetDressingPlanner.plan(
        languageMotif: languageMotif,
        activityMotif: activityMotif,
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
    let phasePolishPlan = CinematicStagePhasePolishPlanner.plan(
        beat: beat,
        stageEffectTuning: effectPlan.tuningMetadata,
        atmospherePlan: atmospherePlan,
        activityMotif: activityMotif,
        activityProfile: activityProfile,
        influenceSettings: settings
    )

    return CinematicSceneNarrativeCuePlanner.plan(
        worldText: inputWorldText,
        briefing: inputBriefing,
        stageBeat: beat,
        stagePhasePolishPlan: phasePolishPlan,
        languageMotif: languageMotif,
        activityMotif: activityMotif,
        influenceSettings: settings,
        nativeFeedbackCue: nativeFeedbackCue
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

private func assertCueTextBounds(
    _ descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor,
    maxCharacters: Int,
    maxWords: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual(descriptor.text.count, maxCharacters, file: file, line: line)
    XCTAssertLessThanOrEqual(wordCount(descriptor.text), maxWords, file: file, line: line)
    XCTAssertFalse(descriptor.text.isEmpty, file: file, line: line)
}

private func assertNarrativeCuePlanInBounds(
    _ plan: CinematicSceneNarrativeCuePlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for descriptor in [plan.questPlaque, plan.arenaInscription, plan.activityBanner] {
        XCTAssertTrue(CinematicNarrativeCueAnchor.allCases.contains(descriptor.anchor), file: file, line: line)
        XCTAssertTrue(CinematicNarrativeCueVisibility.allCases.contains(descriptor.visibility), file: file, line: line)
        XCTAssertInRange(descriptor.scale, CinematicSceneNarrativeCuePlan.cueScaleRange, file: file, line: line)
        XCTAssertInRange(descriptor.opacity, CinematicSceneNarrativeCuePlan.cueOpacityRange, file: file, line: line)
        XCTAssertInRange(descriptor.cadence, CinematicSceneNarrativeCuePlan.cueCadenceRange, file: file, line: line)
        XCTAssertTrue(CinematicStageLightFamily.allCases.contains(descriptor.lightFamily), file: file, line: line)
        XCTAssertTrue(CinematicStageLightFamily.allCases.contains(descriptor.tintFamily), file: file, line: line)
        XCTAssertFalse(descriptor.identifier.isEmpty, file: file, line: line)
        XCTAssertFalse(descriptor.stableID.isEmpty, file: file, line: line)
        XCTAssertFalse(descriptor.text.isEmpty, file: file, line: line)
        assertCueLayoutInBounds(descriptor.layout, file: file, line: line)
    }
    XCTAssertFalse(plan.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(plan.stageBeatIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(plan.stagePhasePolishIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(plan.languageIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(plan.activityIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(plan.influenceIdentifier.isEmpty, file: file, line: line)
}

private func assertCueLayoutInBounds(
    _ layout: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(layout.anchorPosition.x, CinematicSceneNarrativeCuePlan.cueAnchorXRange, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.y, CinematicSceneNarrativeCuePlan.cueAnchorYRange, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.z, CinematicSceneNarrativeCuePlan.cueAnchorZRange, file: file, line: line)
    XCTAssertTrue(
        CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor.FacingMode.allCases.contains(layout.facingMode),
        file: file,
        line: line
    )
    XCTAssertInRange(layout.plateSize.x, CinematicSceneNarrativeCuePlan.cuePlateWidthRange, file: file, line: line)
    XCTAssertInRange(layout.plateSize.y, CinematicSceneNarrativeCuePlan.cuePlateHeightRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextWidth, CinematicSceneNarrativeCuePlan.cueTextWidthRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextWidth, CinematicSceneNarrativeCuePlan.cueTextWidthRange, file: file, line: line)
    XCTAssertInRange(layout.primaryFontSize, CinematicSceneNarrativeCuePlan.cueFontSizeRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryFontSize, CinematicSceneNarrativeCuePlan.cueFontSizeRange, file: file, line: line)
    XCTAssertInRange(layout.backingOpacity, CinematicSceneNarrativeCuePlan.cueBackingOpacityRange, file: file, line: line)
    XCTAssertTrue(
        CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor.GlyphSide.allCases.contains(layout.glyphSide),
        file: file,
        line: line
    )
    XCTAssertInRange(layout.glyphOffset.x, CinematicSceneNarrativeCuePlan.cueOffsetXRange, file: file, line: line)
    XCTAssertInRange(layout.glyphOffset.y, CinematicSceneNarrativeCuePlan.cueOffsetYRange, file: file, line: line)
    XCTAssertInRange(layout.glyphOffset.z, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertInRange(layout.plateDepth, CinematicSceneNarrativeCuePlan.cuePlateDepthRange, file: file, line: line)
    XCTAssertInRange(layout.plateZOffset, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextOffset.x, CinematicSceneNarrativeCuePlan.cueOffsetXRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextOffset.y, CinematicSceneNarrativeCuePlan.cueOffsetYRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextOffset.z, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextOffset.x, CinematicSceneNarrativeCuePlan.cueOffsetXRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextOffset.y, CinematicSceneNarrativeCuePlan.cueOffsetYRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextOffset.z, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertFalse(layout.identifier.isEmpty, file: file, line: line)
}

private func assertActivityBannerSeparated(
    from questPlaque: CinematicSceneNarrativeCuePlan.CueDescriptor,
    and arenaInscription: CinematicSceneNarrativeCuePlan.CueDescriptor,
    in plan: CinematicSceneNarrativeCuePlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let activityLeftEdge = plan.activityBanner.layout.anchorPosition.x
        - plan.activityBanner.layout.plateSize.x * plan.activityBanner.scale / 2
    let questRightEdge = questPlaque.layout.anchorPosition.x
        + questPlaque.layout.plateSize.x * questPlaque.scale / 2
    let arenaRightEdge = arenaInscription.layout.anchorPosition.x
        + arenaInscription.layout.plateSize.x * arenaInscription.scale / 2

    XCTAssertGreaterThan(activityLeftEdge, questRightEdge + 0.65, file: file, line: line)
    XCTAssertGreaterThan(activityLeftEdge, arenaRightEdge + 0.35, file: file, line: line)
}

private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}

private func runCue(
    kind: PlanReliabilityFeedback.Kind,
    severity: PlanReliabilityFeedback.Severity,
    label: String,
    detail: String,
    systemImage: String
) -> PlanReliabilityFeedback.RunCue {
    PlanReliabilityFeedback.RunCue(
        notice: PlanReliabilityFeedback.Notice(
            id: "\(kind.rawValue)-narrative-test",
            kind: kind,
            severity: severity,
            sessionNumber: 0,
            title: label,
            detail: detail,
            actionLabel: label,
            metadata: nil,
            systemImage: systemImage
        )
    )
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
