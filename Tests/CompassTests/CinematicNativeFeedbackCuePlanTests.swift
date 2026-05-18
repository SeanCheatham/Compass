@testable import Compass
import XCTest

final class CinematicNativeFeedbackCuePlanTests: XCTestCase {
    func testCuePlanIsDeterministicAndBoundsCopy() throws {
        let content = NativeFeedbackContent(
            milestone: .verifyStarted,
            projectName: String(repeating: "Verifier Project ", count: 8)
        )

        let first = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: content,
                phase: .verifying,
                feedbackMode: .speechAndNotifications,
                recentRunCues: [:]
            )
        )
        let second = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: content,
                phase: .verifying,
                feedbackMode: .speechAndNotifications,
                recentRunCues: [:]
            )
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertLessThanOrEqual(first.title.count, CinematicNativeFeedbackCuePlan.titleLimit)
        XCTAssertLessThanOrEqual(first.detail.count, CinematicNativeFeedbackCuePlan.detailLimit)
        XCTAssertLessThanOrEqual(first.status.count, CinematicNativeFeedbackCuePlan.statusLimit)
        XCTAssertEqual(first.feedbackMode, .speechAndNotifications)
        XCTAssertEqual(first.phase, .verifying)
        XCTAssertTrue(first.identifier.contains("mode:speech_and_notifications"))
        XCTAssertTrue(first.identifier.contains("phase:Verifying"))
        XCTAssertTrue(first.identifier.contains("color:\(first.colorIdentifier)"))
    }

    @MainActor
    func testModeOffSuppressesPlanAndClearsProjectCue() throws {
        let suppressed = CinematicNativeFeedbackCuePlanner.plan(
            milestone: .verifyStarted,
            content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
            phase: .verifying,
            feedbackMode: .off,
            recentRunCues: [:]
        )
        XCTAssertNil(suppressed)

        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/Editor"),
            nativeFeedbackMode: .notifications
        )
        project.phase = .verifying
        project.recordCinematicNativeFeedback(.verifyStarted)
        XCTAssertEqual(project.cinematicNativeFeedbackCue?.milestone, .verifyStarted)

        project.nativeFeedbackMode = .off
        XCTAssertNil(project.cinematicNativeFeedbackCue)
        XCTAssertNil(project.cinematicNativeFeedbackCueLifecycle.activeCue)
        XCTAssertEqual(project.cinematicNativeFeedbackCueLifecycle.recentArchive.first?.archiveReason, .modeOff)

        project.recordCinematicNativeFeedback(.verifyStarted)
        XCTAssertNil(project.cinematicNativeFeedbackCue)
        XCTAssertNil(project.cinematicNativeFeedbackCueLifecycle.activeCue)
    }

    func testVerifyStartedAndDevelopRetryingStyles() throws {
        let verifyCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )

        XCTAssertEqual(verifyCue.title, "Editor: Verify started")
        XCTAssertEqual(verifyCue.detail, "Compass is running the verify command.")
        XCTAssertEqual(verifyCue.systemImage, "checkmark.seal")
        XCTAssertEqual(verifyCue.style, .verify)
        XCTAssertEqual(verifyCue.colorIdentifier, "yellow")
        XCTAssertEqual(verifyCue.priority, 40)
        XCTAssertEqual(verifyCue.sourceIdentifier, "native:verifyStarted")

        let retryCue = try XCTUnwrap(
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

        XCTAssertEqual(retryCue.title, "Retry Develop")
        XCTAssertEqual(retryCue.detail, "Expected true but got false")
        XCTAssertEqual(retryCue.systemImage, "checkmark.seal.fill")
        XCTAssertEqual(retryCue.style, .failure)
        XCTAssertEqual(retryCue.colorIdentifier, "red")
        XCTAssertEqual(retryCue.runCueKind, .failedVerify)
        XCTAssertEqual(retryCue.runCueSessionNumber, 7)
        XCTAssertEqual(retryCue.sourceIdentifier, "run-cue:7:failedVerify")
        XCTAssertFalse(verifyCue.isCriticalCinematicBanner)
        XCTAssertTrue(retryCue.isCriticalCinematicBanner)
    }

    func testCriticalBannerPolicyIncludesWarningFailureAndRetryCues() throws {
        let retryCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        let warningCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [
                    1: runCue(
                        kind: .dirtyWorktree,
                        severity: .warning,
                        label: "Clean Worktree",
                        detail: "Pending changes need review",
                        systemImage: "pencil.and.outline"
                    )
                ]
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
        let nonCriticalCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyPassed,
                content: NativeFeedbackContent(milestone: .verifyPassed, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )

        XCTAssertTrue(retryCue.isCriticalCinematicBanner)
        XCTAssertTrue(warningCue.isCriticalCinematicBanner)
        XCTAssertTrue(failureCue.isCriticalCinematicBanner)
        XCTAssertFalse(nonCriticalCue.isCriticalCinematicBanner)
    }

    func testRunCuePriorityBeatsNewestRetryCue() throws {
        let cue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [
                    12: runCue(
                        kind: .dirtyWorktree,
                        severity: .warning,
                        label: "Clean Worktree",
                        detail: "2 pending changes",
                        systemImage: "pencil.and.outline"
                    ),
                    9: runCue(
                        kind: .failedVerify,
                        severity: .failure,
                        label: "Retry Develop",
                        detail: "swift test exited 65",
                        systemImage: "checkmark.seal.fill"
                    )
                ]
            )
        )

        XCTAssertEqual(cue.runCueKind, .failedVerify)
        XCTAssertEqual(cue.runCueSessionNumber, 9)
        XCTAssertEqual(cue.title, "Retry Develop")
        XCTAssertEqual(cue.priority, 10 + PlanReliabilityFeedback.priority(for: .failedVerify))
        XCTAssertLessThan(cue.priority, 10 + PlanReliabilityFeedback.priority(for: .dirtyWorktree))
    }

    func testDevelopReadyCueUsesReadinessCopyAndIsDeterministic() throws {
        let state = PlanState(
            completed: ["Mapped readiness cue"],
            immediate: PlanNext(
                plan: "Wait for Develop approval",
                verify: "swift test",
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "",
            longTerm: ""
        )
        let plan = CinematicPlanCompassPlan(state: state)
        let feedback = PlanReliabilityFeedback(state: state, sessions: [])
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: feedback
        )
        let content = NativeFeedbackContent(readinessPlan: readiness, projectName: "Editor")
        let first = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developReady,
                content: content,
                phase: .paused,
                feedbackMode: .notifications,
                recentRunCues: feedback.recentRunCues,
                readinessPlan: readiness
            )
        )
        let repeated = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developReady,
                content: content,
                phase: .paused,
                feedbackMode: .notifications,
                recentRunCues: feedback.recentRunCues,
                readinessPlan: readiness
            )
        )

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.milestone, .developReady)
        XCTAssertEqual(first.phase, .paused)
        XCTAssertEqual(first.style, .verify)
        XCTAssertEqual(first.colorIdentifier, "yellow")
        XCTAssertEqual(first.systemImage, readiness.systemImage)
        XCTAssertEqual(first.sourceIdentifier, "plan-readiness:ready")
        XCTAssertEqual(first.priority, 56)
        XCTAssertFalse(first.isCriticalCinematicBanner)
        XCTAssertTrue(first.title.contains("Ready for Develop"))
        XCTAssertTrue(first.status.contains("Ready for Develop"))
        XCTAssertTrue(first.status.contains("1 completed"))
        XCTAssertTrue(first.detail.contains("Prove: swift test"))
        XCTAssertTrue(first.detail.contains("Timeout 2m"))
        XCTAssertTrue(first.detail.contains("Medium"))
        XCTAssertTrue(first.detail.contains("warnings clear"))
        XCTAssertTrue(first.detail.contains("retry none"))
        XCTAssertLessThanOrEqual(first.title.count, CinematicNativeFeedbackCuePlan.titleLimit)
        XCTAssertLessThanOrEqual(first.detail.count, CinematicNativeFeedbackCuePlan.detailLimit)
        XCTAssertLessThanOrEqual(first.status.count, CinematicNativeFeedbackCuePlan.statusLimit)
        XCTAssertTrue(first.identifier.contains("native-feedback:developReady"))
        XCTAssertTrue(first.identifier.contains("source:plan-readiness:ready"))
    }

    func testDevelopReadyWarningStylesStayCriticalForMissingMetadataAndRetryCues() throws {
        let missingState = PlanState(
            completed: ["Accepted incomplete metadata"],
            immediate: PlanNext(plan: "Fill readiness metadata", verify: "swift test"),
            midTerm: "",
            longTerm: ""
        )
        let missingCue = try readinessCue(for: missingState, sessions: [])

        XCTAssertEqual(missingCue.style, .warning)
        XCTAssertEqual(missingCue.colorIdentifier, "orange")
        XCTAssertEqual(missingCue.sourceIdentifier, "plan-readiness:missing-metadata")
        XCTAssertEqual(missingCue.priority, 28)
        XCTAssertTrue(missingCue.isCriticalCinematicBanner)
        XCTAssertTrue(missingCue.detail.contains("warnings warning"))

        let retryState = PlanState(
            completed: ["Accepted retry metadata"],
            immediate: PlanNext(
                plan: "Retry readiness metadata",
                verify: "swift test",
                verifyTimeoutMs: 60_000,
                estimatedDifficulty: .low
            ),
            midTerm: "",
            longTerm: ""
        )
        let retryCue = try readinessCue(for: retryState, sessions: [failedVerifySession()])

        XCTAssertEqual(retryCue.style, .warning)
        XCTAssertEqual(retryCue.sourceIdentifier, "plan-readiness:retry-cue")
        XCTAssertTrue(retryCue.isCriticalCinematicBanner)
        XCTAssertTrue(retryCue.detail.contains("retry notice.failedVerify.4"))
    }

    func testLifecycleDurationsAreDeterministicAndBoundedBySeverity() throws {
        let verifyCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        let retryCue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developRetrying,
                content: NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor"),
                phase: .developing,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )

        XCTAssertEqual(
            CinematicNativeFeedbackCueLifecycle.displayDuration(for: verifyCue),
            CinematicNativeFeedbackCueLifecycle.standardDisplayDuration
        )
        XCTAssertEqual(
            CinematicNativeFeedbackCueLifecycle.displayDuration(for: retryCue),
            CinematicNativeFeedbackCueLifecycle.criticalDisplayDuration
        )
        XCTAssertGreaterThan(
            CinematicNativeFeedbackCueLifecycle.criticalDisplayDuration,
            CinematicNativeFeedbackCueLifecycle.standardDisplayDuration
        )
        XCTAssertTrue(
            CinematicNativeFeedbackCueLifecycle.displayDurationRange.contains(
                CinematicNativeFeedbackCueLifecycle.standardDisplayDuration
            )
        )
        XCTAssertTrue(
            CinematicNativeFeedbackCueLifecycle.displayDurationRange.contains(
                CinematicNativeFeedbackCueLifecycle.criticalDisplayDuration
            )
        )
    }

    @MainActor
    func testRepeatedMilestoneReplacesAndArchivesPreviousActiveCue() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/Editor"),
            nativeFeedbackMode: .notifications
        )
        project.phase = .verifying

        project.recordCinematicNativeFeedback(.verifyStarted, now: now)
        let firstCue = try XCTUnwrap(project.cinematicNativeFeedbackCue)
        project.recordCinematicNativeFeedback(.verifyStarted, now: now.addingTimeInterval(1))
        let secondCue = try XCTUnwrap(project.cinematicNativeFeedbackCue)

        XCTAssertNotEqual(firstCue.identifier, secondCue.identifier)
        XCTAssertEqual(firstCue.baseIdentifier, secondCue.baseIdentifier)
        XCTAssertEqual(project.cinematicNativeFeedbackCueLifecycle.recentArchive.count, 1)
        XCTAssertEqual(
            project.cinematicNativeFeedbackCueLifecycle.recentArchive.first?.cueIdentifier,
            firstCue.identifier
        )
        XCTAssertEqual(
            project.cinematicNativeFeedbackCueLifecycle.recentArchive.first?.archiveReason,
            .replaced
        )
        XCTAssertEqual(
            project.cinematicNativeFeedbackCueLifecycle.recentArchive.first?.sourceIdentifier,
            "native:verifyStarted"
        )
        XCTAssertEqual(
            project.cinematicNativeFeedbackCueLifecycle.recentArchive.first?.styleIdentifier,
            "verify"
        )
        XCTAssertEqual(project.cinematicNativeFeedbackCueLifecycle.stateIdentifier, "active")
        XCTAssertTrue(secondCue.identifier.contains("lifecycle:active"))
    }

    @MainActor
    func testProjectReadinessGateCueTriggersOnlyWithImmediateAndDoesNotMutatePlanContext() throws {
        let now = Date(timeIntervalSinceReferenceDate: 8_000)
        let readyState = PlanState(
            completed: ["Prepared Plan-only readiness"],
            immediate: PlanNext(
                plan: "Wait at the Plan-only gate",
                verify: "swift test",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "Keep the plan untouched",
            longTerm: "Keep storage untouched"
        )
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/ReadinessGate"),
            nativeFeedbackMode: .notifications
        )
        project.state = readyState
        project.sessions = [SessionRecord.started(1)]
        let stateBefore = project.state
        let sessionsBefore = project.sessions
        let activeStorageBefore = project.activeStorage
        let recapContextBefore = project.cinematicRunRecapShareArtifactLibraryContext
        let warningHistoryBefore = project.cinematicDiagnosticsWarningBundleHistory

        let planOnlyCue = try XCTUnwrap(
            project.recordPlanReadinessNativeFeedback(
                state: readyState,
                gate: .planOnly,
                now: now
            )
        )

        XCTAssertEqual(planOnlyCue.milestone, .developReady)
        XCTAssertEqual(planOnlyCue.sourceIdentifier, "plan-readiness:ready")
        XCTAssertEqual(planOnlyCue.phase, .idle)
        XCTAssertEqual(project.state, stateBefore)
        XCTAssertEqual(project.sessions, sessionsBefore)
        XCTAssertEqual(project.activeStorage, activeStorageBefore)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactLibraryContext, recapContextBefore)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory, warningHistoryBefore)

        project.isPaused = true
        project.phase = .paused
        let pausedCue = try XCTUnwrap(
            project.recordPlanReadinessNativeFeedback(
                state: readyState,
                gate: .pausedBeforeDevelop,
                now: now.addingTimeInterval(1)
            )
        )

        XCTAssertEqual(pausedCue.milestone, .developReady)
        XCTAssertEqual(pausedCue.phase, .paused)
        XCTAssertEqual(project.cinematicNativeFeedbackCueLifecycle.recentArchive.first?.milestoneIdentifier, "developReady")
        XCTAssertEqual(project.state, stateBefore)
        XCTAssertEqual(project.sessions, sessionsBefore)
        XCTAssertEqual(project.activeStorage, activeStorageBefore)

        let noImmediateProject = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/ReadinessGateNoImmediate"),
            nativeFeedbackMode: .notifications
        )
        let noImmediateState = PlanState(completed: [], immediate: nil, midTerm: "", longTerm: "")
        noImmediateProject.state = noImmediateState
        XCTAssertNil(
            noImmediateProject.recordPlanReadinessNativeFeedback(
                state: noImmediateState,
                gate: .planOnly,
                now: now
            )
        )
        XCTAssertNil(noImmediateProject.cinematicNativeFeedbackCue)
        XCTAssertEqual(noImmediateProject.state, noImmediateState)
    }

    func testLifecycleExpiryArchivesAndBoundsRecentCueHistory() throws {
        let now = Date(timeIntervalSinceReferenceDate: 2_000)
        let cue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        let activeCue = lifecycle.record(cue, now: now)

        XCTAssertEqual(activeCue.lifecycleStateIdentifier, "active")
        XCTAssertEqual(activeCue.lifecycleDisplayDuration, CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
        XCTAssertFalse(
            lifecycle.expire(
                now: now.addingTimeInterval(CinematicNativeFeedbackCueLifecycle.standardDisplayDuration - 0.1)
            )
        )
        XCTAssertTrue(
            lifecycle.expire(
                now: now.addingTimeInterval(CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
            )
        )
        XCTAssertNil(lifecycle.activeCue)
        XCTAssertEqual(lifecycle.stateIdentifier, "expired")
        XCTAssertEqual(lifecycle.recentArchive.first?.archiveReason, .expired)
        XCTAssertEqual(lifecycle.recentArchive.first?.sourceIdentifier, "native:verifyStarted")
        XCTAssertEqual(lifecycle.recentArchive.first?.styleIdentifier, "verify")

        for offset in 1...(CinematicNativeFeedbackCueLifecycle.recentArchiveLimit + 3) {
            _ = lifecycle.record(cue, now: now.addingTimeInterval(Double(offset * 10)))
        }

        XCTAssertEqual(lifecycle.recentArchive.count, CinematicNativeFeedbackCueLifecycle.recentArchiveLimit)
        XCTAssertTrue(lifecycle.recentArchive.allSatisfy { $0.stateIdentifier == "archived" })
        XCTAssertTrue(lifecycle.identifier.contains("archive-count:\(CinematicNativeFeedbackCueLifecycle.recentArchiveLimit)"))
    }

    private func readinessCue(
        for state: PlanState,
        sessions: [SessionRecord]
    ) throws -> CinematicNativeFeedbackCuePlan {
        let plan = CinematicPlanCompassPlan(state: state)
        let feedback = PlanReliabilityFeedback(state: state, sessions: sessions)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: feedback
        )
        return try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .developReady,
                content: NativeFeedbackContent(readinessPlan: readiness, projectName: "Editor"),
                phase: .idle,
                feedbackMode: .notifications,
                recentRunCues: feedback.recentRunCues,
                readinessPlan: readiness
            )
        )
    }

    private func failedVerifySession() -> SessionRecord {
        SessionRecord(
            session: 4,
            startedAt: 4_000,
            endedAt: 4_500,
            plan: "Retry readiness",
            verify: "swift test",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .failed,
            notes: [],
            verifyOutput: VerifyOutput(
                command: "swift test",
                exitCode: 65,
                tail: "Tests failed"
            ),
            feedback: nil
        )
    }
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
            id: "\(kind.rawValue)-test",
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
