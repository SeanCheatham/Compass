import Foundation
@testable import Compass
import XCTest

final class CinematicIdleStoryCyclePlanTests: XCTestCase {
    func testPhaseOrderingRotatesThroughAvailableDescriptors() throws {
        let context = try makeContext()

        let phases = CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.enumerated().map { index, _ in
            plan(context: context, elapsedMultiplier: index).descriptor?.phase
        }

        XCTAssertEqual(phases, CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases)
        XCTAssertEqual(plan(context: context, elapsedMultiplier: 5).descriptor?.phase, .commitConstellation)
    }

    func testIdleOnlyActivationSuppressesLiveFollowAndExplicitUserFocus() throws {
        let context = try makeContext()

        let idle = plan(context: context)
        let liveFollow = plan(context: context, isLiveFollowActive: true)
        let userFocus = plan(context: context, hasExplicitUserFocus: true)
        let empty = CinematicIdleStoryCyclePlanner.plan(
            session: .init(),
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: .init(),
            commitConstellationPlan: .empty,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: .empty(reason: "no-finished-session"),
            runRecapSceneFocusPlan: .none,
            runRecapEndCardPlan: .none
        )

        XCTAssertTrue(idle.isActive)
        XCTAssertFalse(liveFollow.isActive)
        XCTAssertEqual(liveFollow.suppressionReason, "live-follow")
        XCTAssertFalse(userFocus.isActive)
        XCTAssertEqual(userFocus.suppressionReason, "user-focus")
        XCTAssertFalse(empty.isActive)
        XCTAssertEqual(empty.suppressionReason, "no-descriptors")
    }

    func testRecapAvailabilityGatesRecapFocusAndEndCardPhases() throws {
        var context = try makeContext()
        context.recapPlan = .empty(reason: "active-run")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none

        let phases = (0..<6).compactMap {
            plan(context: context, elapsedMultiplier: $0).descriptor?.phase
        }

        XCTAssertFalse(phases.contains(.runRecapFocus))
        XCTAssertFalse(phases.contains(.runRecapEndCard))
        XCTAssertTrue(phases.contains(.commitConstellation))
        XCTAssertTrue(phases.contains(.timelineFocus))
        XCTAssertTrue(phases.contains(.nativeFeedbackPlaque))
    }

    func testCriticalNativeFeedbackPlaqueTakesPriority() throws {
        var context = try makeContext()
        let criticalCue = try makeNativeFeedbackCue(
            milestone: .developRetrying,
            recentRunCues: [
                7: runCue(
                    kind: .failedVerify,
                    severity: .failure,
                    label: "Retry Develop",
                    detail: "swift test exited 65",
                    systemImage: "checkmark.seal.fill"
                )
            ]
        )
        context.nativeFeedbackCue = criticalCue
        context.nativeFeedbackPlaqueDescriptor = try XCTUnwrap(
            nativeFeedbackPlaqueDescriptor(for: criticalCue)
        )

        let selected = plan(context: context, elapsedMultiplier: 0)
        let descriptor = try XCTUnwrap(selected.descriptor)

        XCTAssertEqual(descriptor.phase, .nativeFeedbackPlaque)
        XCTAssertEqual(descriptor.targetKindIdentifier, "native-feedback-failure")
        XCTAssertEqual(descriptor.cameraShot, .failure)
        XCTAssertEqual(descriptor.lightFamily, .failure)
        XCTAssertTrue(descriptor.phaseCopy.contains("Retry"))
    }

    func testQuietModeSuppressesOnlyNonCriticalNativeFeedbackPlaques() throws {
        var context = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .follow, comfortMode: .quiet)
        )

        let nativeSlot = plan(context: context, elapsedMultiplier: 2)
        XCTAssertNotEqual(nativeSlot.descriptor?.phase, .nativeFeedbackPlaque)
        XCTAssertTrue(nativeSlot.isActive)

        context.commitConstellationPlan = .empty
        context.timelineFocusPlan = .none
        context.recapPlan = .empty(reason: "no-finished-session")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none
        let suppressedNativeOnly = plan(context: context, elapsedMultiplier: 2)
        XCTAssertFalse(suppressedNativeOnly.isActive)
        XCTAssertEqual(suppressedNativeOnly.suppressionReason, "quiet-noncritical-native-feedback")

        let criticalCue = try makeNativeFeedbackCue(
            milestone: .postChecksFailed,
            recentRunCues: [:]
        )
        context.nativeFeedbackCue = criticalCue
        context.nativeFeedbackPlaqueDescriptor = try XCTUnwrap(
            nativeFeedbackPlaqueDescriptor(
                for: criticalCue,
                settings: CinematicInfluenceSettings(cameraStyle: .follow, comfortMode: .quiet)
            )
        )
        let critical = plan(context: context, elapsedMultiplier: 0)
        XCTAssertEqual(critical.descriptor?.phase, .nativeFeedbackPlaque)
        XCTAssertEqual(critical.suppressionReason, "none")
    }

    func testIdentifiersAreStableBoundedAndReflectSelectedPhase() throws {
        let context = try makeContext()
        let first = plan(context: context, elapsedMultiplier: 1)
        let repeated = plan(context: context, elapsedMultiplier: 1)
        let changed = plan(context: context, elapsedMultiplier: 2)
        let descriptor = try XCTUnwrap(first.descriptor)

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.identifier, changed.identifier)
        XCTAssertLessThanOrEqual(first.identifier.count, CinematicIdleStoryCyclePlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicIdleStoryCyclePlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(
            descriptor.sourceDescriptorIdentifier.count,
            CinematicIdleStoryCyclePlan.sourceDescriptorMaxCharacters
        )
        XCTAssertLessThanOrEqual(descriptor.phaseCopy.count, CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters)
        XCTAssertInRange(descriptor.cadence, CinematicIdleStoryCyclePlan.cadenceRange)
    }

    func testPlanningDoesNotMutateTimelineSelectionOrRecapPlanning() throws {
        let context = try makeContext(selectedBeatID: "session-42-plan")
        let timelineBefore = context.timelinePlan
        let timelineFocusBefore = context.timelineFocusPlan
        let recapBefore = context.recapPlan
        let recapFocusBefore = context.recapFocusPlan
        let recapEndCardBefore = context.recapEndCardPlan

        _ = plan(context: context, elapsedMultiplier: 4)

        XCTAssertEqual(context.timelinePlan, timelineBefore)
        XCTAssertEqual(context.timelinePlan.selectedBeatID, "session-42-plan")
        XCTAssertEqual(context.timelineFocusPlan, timelineFocusBefore)
        XCTAssertEqual(context.recapPlan, recapBefore)
        XCTAssertEqual(context.recapFocusPlan, recapFocusBefore)
        XCTAssertEqual(context.recapEndCardPlan, recapEndCardBefore)
    }

    private struct Context {
        var settings: CinematicInfluenceSettings
        var session: SessionRecord
        var commitConstellationPlan: CinematicCommitConstellationPlan
        var timelinePlan: CinematicSessionTimelinePlan
        var timelineFocusPlan: CinematicTimelineSceneFocusPlan
        var nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
        var nativeFeedbackPlaqueDescriptor: CinematicIdleStoryCyclePlan.NativeFeedbackPlaqueDescriptor?
        var recapPlan: CinematicRunRecapPlan
        var recapFocusPlan: CinematicRunRecapSceneFocusPlan
        var recapEndCardPlan: CinematicRunRecapEndCardPlan
    }

    private func makeContext(
        selectedBeatID: String? = nil,
        settings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) throws -> Context {
        let session = makeSession(
            42,
            status: .succeeded,
            commits: [
                SessionCommit(
                    sha: "1234567890abcdef",
                    short: "1234567",
                    subject: "Add idle story cycle"
                )
            ],
            endedAt: 42_500
        )
        let commitConstellationPlan = CinematicCommitConstellationPlan(sessions: [session])
        let timelinePlan = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: selectedBeatID
        )
        let timelineFocusPlan = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelinePlan.selectedBeat,
            commitConstellationPlan: commitConstellationPlan,
            recoveryCuePlan: .none
        )
        let nativeCue = try makeNativeFeedbackCue(milestone: .verifyStarted, recentRunCues: [:])
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: recapState(),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let recapFocusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitConstellationPlan,
            timelinePlan: timelinePlan
        )
        let recapEndCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )

        return Context(
            settings: settings,
            session: session,
            commitConstellationPlan: commitConstellationPlan,
            timelinePlan: timelinePlan,
            timelineFocusPlan: timelineFocusPlan,
            nativeFeedbackCue: nativeCue,
            nativeFeedbackPlaqueDescriptor: try XCTUnwrap(
                nativeFeedbackPlaqueDescriptor(for: nativeCue, settings: settings)
            ),
            recapPlan: recapPlan,
            recapFocusPlan: recapFocusPlan,
            recapEndCardPlan: recapEndCardPlan
        )
    }

    private func plan(
        context: Context,
        elapsedMultiplier: Int = 0,
        isLiveFollowActive: Bool = false,
        hasExplicitUserFocus: Bool = false
    ) -> CinematicIdleStoryCyclePlan {
        CinematicIdleStoryCyclePlanner.plan(
            session: .init(
                elapsedTime: Double(elapsedMultiplier) * CinematicIdleStoryCyclePlan.defaultCadence,
                sessionOrdinal: 0
            ),
            isLiveFollowActive: isLiveFollowActive,
            hasExplicitUserFocus: hasExplicitUserFocus,
            influenceSettings: context.settings,
            commitConstellationPlan: context.commitConstellationPlan,
            timelineSceneFocusPlan: context.timelineFocusPlan,
            nativeFeedbackCue: context.nativeFeedbackCue,
            nativeFeedbackPlaqueDescriptor: context.nativeFeedbackPlaqueDescriptor,
            runRecapPlan: context.recapPlan,
            runRecapSceneFocusPlan: context.recapFocusPlan,
            runRecapEndCardPlan: context.recapEndCardPlan
        )
    }

    private func nativeFeedbackPlaqueDescriptor(
        for cue: CinematicNativeFeedbackCuePlan,
        settings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> CinematicIdleStoryCyclePlan.NativeFeedbackPlaqueDescriptor? {
        CinematicIdleStoryCyclePlanner.nativeFeedbackPlaqueDescriptor(
            phase: cue.phase,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: settings,
            worldText: .placeholder,
            briefing: .placeholder,
            recoveryCuePlan: .none,
            nativeFeedbackCue: cue
        )
    }

    private func makeNativeFeedbackCue(
        milestone: NativeFeedbackMilestone,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue]
    ) throws -> CinematicNativeFeedbackCuePlan {
        try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: milestone,
                content: NativeFeedbackContent(milestone: milestone, projectName: "Idle Story"),
                phase: milestone == .postChecksFailed ? .failed : .verifying,
                feedbackMode: .notifications,
                recentRunCues: recentRunCues
            )
        )
    }

    private func recapState() -> PlanState {
        PlanState(
            completed: ["Completed idle story cycle"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus,
        commits: [SessionCommit],
        endedAt: Double?
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Stage idle story cycle",
            verify: "swift test --filter CinematicIdleStoryCyclePlanTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
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
                id: "\(kind.rawValue)-idle-story-test",
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
    recentCommitCount: Int = 0
) -> RepositoryActivityProfile {
    RepositoryActivityProfile(
        isAvailable: true,
        worktreeChanges: RepositoryWorktreeChangeCounts(),
        recentSessionCount: 1,
        recentSucceededCount: 0,
        recentFailedCount: 0,
        recentCommitCount: recentCommitCount,
        lastTerminalStatus: nil,
        lastSuccessfulSession: nil,
        lastFailedSession: nil,
        successStreak: 0,
        failureStreak: 0,
        recoveredFromFailure: false
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
