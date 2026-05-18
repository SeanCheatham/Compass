import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapPlanTests: XCTestCase {
    func testEmptyWhileRunningOrWithoutFinishedSession() {
        let finished = makeSession(1, status: .succeeded, endedAt: 1_500)
        let state = PlanState(
            completed: ["Wire run recap"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [finished])

        let running = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [finished],
            isRunning: true,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )

        XCTAssertFalse(running.isAvailable)
        XCTAssertEqual(running.availabilityIdentifier, "active-run")
        XCTAssertEqual(running.identifier, "run-recap.empty|reason:active-run")
        XCTAssertEqual(running.commitHighlightCount, 0)
        XCTAssertEqual(running.eventChipCount, 0)

        let noFinished = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [makeSession(2, status: .developing, endedAt: nil)],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: .empty,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )

        XCTAssertFalse(noFinished.isAvailable)
        XCTAssertEqual(noFinished.availabilityIdentifier, "no-finished-session")
        XCTAssertNil(noFinished.sessionNumber)
        XCTAssertEqual(noFinished.statusIdentifier, "none")
    }

    func testSuccessAndFailureRecapsExposeTerminalStyling() throws {
        let successSession = makeSession(3, status: .succeeded, endedAt: 3_400)
        let failureSession = makeSession(4, status: .failed, endedAt: 4_400)
        let state = PlanState(
            completed: ["Finished recap overlay"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )

        let success = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [successSession],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [successSession]),
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let failure = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [successSession, failureSession],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [
                4: runCue(
                    kind: .failedVerify,
                    severity: .failure,
                    label: "Retry Develop",
                    detail: "swift test failed",
                    systemImage: "checkmark.seal.fill"
                )
            ],
            commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [successSession, failureSession]),
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )

        XCTAssertTrue(success.isAvailable)
        XCTAssertEqual(success.sessionNumber, 3)
        XCTAssertEqual(success.statusIdentifier, "succeeded")
        XCTAssertEqual(success.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(success.style, .success)
        XCTAssertEqual(success.colorIdentifier, "green")
        XCTAssertTrue(success.title.contains("succeeded"))
        XCTAssertEqual(success.detail, "Finished recap overlay")

        XCTAssertTrue(failure.isAvailable)
        XCTAssertEqual(failure.sessionNumber, 4)
        XCTAssertEqual(failure.statusIdentifier, "failed")
        XCTAssertEqual(failure.systemImage, "xmark.octagon.fill")
        XCTAssertEqual(failure.style, .failure)
        XCTAssertEqual(failure.colorIdentifier, "red")
        XCTAssertEqual(failure.eventChips.first?.sourceIdentifier, "run-cue:4:failedVerify")
    }

    func testCommitHighlightsAndNativeFeedbackHistoryAreBounded() throws {
        let commits = (1...8).map { index in
            SessionCommit(
                sha: "abcdef123456789\(index)",
                short: "abc\(index)",
                subject: "Commit highlight \(index) with enough detail to fit in the recap"
            )
        }
        let session = makeSession(9, commits: commits, endedAt: 9_500)
        let completed = (1...5).map { "Completed item \($0)" }
        let state = PlanState(
            completed: completed + [String(repeating: "Latest completed summary ", count: 8)],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let cue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Recap"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        for offset in 0..<6 {
            _ = lifecycle.record(cue, now: Date(timeIntervalSinceReferenceDate: Double(8_000 + offset)))
        }

        let plan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [session]),
            nativeFeedbackLifecycle: lifecycle
        )

        XCTAssertTrue(plan.isAvailable)
        XCTAssertEqual(plan.commitHighlightCount, CinematicCommitConstellationPlan.maxCommitCount)
        XCTAssertEqual(plan.completedCount, 6)
        XCTAssertLessThanOrEqual(plan.latestCompletedSummary.count, CinematicRunRecapPlan.completedSummaryLimit)
        XCTAssertLessThanOrEqual(plan.newestCommitHighlight?.count ?? 0, CinematicRunRecapPlan.commitHighlightLimit)
        XCTAssertEqual(plan.eventChipCount, CinematicRunRecapPlan.eventChipLimit)
        XCTAssertTrue(plan.eventChips.allSatisfy { $0.sourceIdentifier.hasPrefix("native-feedback:") })
        XCTAssertTrue(plan.eventChips.allSatisfy { $0.label.count <= CinematicRunRecapPlan.eventChipLabelLimit })
        XCTAssertTrue(plan.eventChips.allSatisfy { $0.detail.count <= CinematicRunRecapPlan.eventChipDetailLimit })
        XCTAssertTrue(plan.status.contains("6 commit highlights"))
        XCTAssertTrue(plan.status.contains("6 completed items"))
        XCTAssertTrue(plan.status.contains("3 events"))
    }

    func testIdentifiersAreStableAndReflectRecapDrivingInputs() {
        let session = makeSession(
            10,
            commits: [
                SessionCommit(
                    sha: "feedface1234567890",
                    short: "feedfac",
                    subject: "Stabilize run recap identifier"
                )
            ],
            endedAt: 10_500
        )
        let firstState = PlanState(
            completed: ["Initial recap input"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let secondState = PlanState(
            completed: ["Initial recap input", "Changed recap input"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])

        let first = CinematicRunRecapPlanner.plan(
            state: firstState,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let repeated = CinematicRunRecapPlanner.plan(
            state: firstState,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let changed = CinematicRunRecapPlanner.plan(
            state: secondState,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.identifier, changed.identifier)
        XCTAssertTrue(first.identifier.contains("session:10"))
        XCTAssertTrue(first.identifier.contains("commit-count:1"))
    }

    func testRecapPlanningDoesNotChangeTimelineOrNativeFeedbackLifecycle() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9_500)
        let session = makeSession(11, status: .succeeded, endedAt: 11_500)
        let cue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Recap"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        _ = lifecycle.record(cue, now: now)
        let lifecycleBefore = lifecycle
        let timelineBefore = CinematicSessionTimelinePlan(sessions: [session])

        _ = CinematicRunRecapPlanner.plan(
            state: PlanState(completed: ["No mutation"], immediate: nil, midTerm: "", longTerm: ""),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [session]),
            nativeFeedbackLifecycle: lifecycle
        )

        XCTAssertEqual(lifecycle, lifecycleBefore)
        XCTAssertEqual(CinematicSessionTimelinePlan(sessions: [session]), timelineBefore)
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus = .succeeded,
        plan: String? = "Implement recap overlay",
        verify: String? = "swift test --filter CinematicRunRecapPlanTests",
        commits: [SessionCommit] = [],
        endedAt: Double? = nil,
        feedback: String? = nil
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: plan,
            verify: verify,
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: feedback
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
                id: "\(kind.rawValue)-recap-test",
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
