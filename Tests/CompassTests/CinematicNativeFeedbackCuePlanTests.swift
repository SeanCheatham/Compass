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
        XCTAssertEqual(project.cinematicNativeFeedbackCueLifecycle.stateIdentifier, "active")
        XCTAssertTrue(secondCue.identifier.contains("lifecycle:active"))
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

        for offset in 1...(CinematicNativeFeedbackCueLifecycle.recentArchiveLimit + 3) {
            _ = lifecycle.record(cue, now: now.addingTimeInterval(Double(offset * 10)))
        }

        XCTAssertEqual(lifecycle.recentArchive.count, CinematicNativeFeedbackCueLifecycle.recentArchiveLimit)
        XCTAssertTrue(lifecycle.recentArchive.allSatisfy { $0.stateIdentifier == "archived" })
        XCTAssertTrue(lifecycle.identifier.contains("archive-count:\(CinematicNativeFeedbackCueLifecycle.recentArchiveLimit)"))
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
