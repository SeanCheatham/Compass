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

        project.recordCinematicNativeFeedback(.verifyStarted)
        XCTAssertNil(project.cinematicNativeFeedbackCue)
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
