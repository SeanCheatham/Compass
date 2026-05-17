import Foundation
@testable import Compass
import XCTest

final class ProjectSidebarStatusTests: XCTestCase {
    func testCleanFeedbackProducesImmediatePlanSubtitleWithoutCue() {
        let feedback = PlanReliabilityFeedback(
            state: makeState(immediate: nil),
            sessions: [
                makeSession(1, status: .succeeded, feedback: "done"),
                makeSession(2, status: .skipped, notes: ["Plan returned no immediate work."])
            ]
        )

        let sidebarStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(feedback: feedback),
            immediateTitle: "Add sidebar attention badges",
            phase: .idle
        )

        XCTAssertFalse(sidebarStatus.hasReliabilityCue)
        XCTAssertFalse(sidebarStatus.showsProgress)
        XCTAssertEqual(sidebarStatus.title, "")
        XCTAssertEqual(sidebarStatus.subtitle, "Add sidebar attention badges")
        XCTAssertEqual(sidebarStatus.countLabel, "0 cues")
        XCTAssertEqual(sidebarStatus.phaseLabel, "Idle")
        XCTAssertEqual(sidebarStatus.badgeLabel, "")
    }

    func testRejectedPlanTakesPriorityForSidebarBadge() {
        let newerFailedVerify = makeSession(
            3,
            startedAt: 3_000,
            status: .failed,
            verifyOutput: VerifyOutput(
                command: "swift test",
                exitCode: 1,
                tail: "latest verify failure"
            )
        )
        let olderRejectedPlan = makeSession(
            2,
            startedAt: 2_000,
            status: .failed,
            notes: [
                "Plan tried to clear a non-empty queue without recording completion. Refusing to overwrite state.json."
            ]
        )
        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [olderRejectedPlan, newerFailedVerify]
        )

        let reliabilityStatus = ProjectReliabilityStatus(feedback: feedback)
        let sidebarStatus = makeSidebarStatus(reliabilityStatus: reliabilityStatus)

        XCTAssertEqual(feedback.notices.map(\.kind), [.failedVerify, .rejectedPlan])
        XCTAssertTrue(sidebarStatus.hasReliabilityCue)
        XCTAssertEqual(sidebarStatus.title, "Plan rejected")
        XCTAssertEqual(sidebarStatus.badgeLabel, "Plan rejected")
        XCTAssertEqual(sidebarStatus.actionLabel, "Retry Plan")
        XCTAssertEqual(sidebarStatus.metadata, "#2")
        XCTAssertEqual(sidebarStatus.countLabel, "2 cues")
        XCTAssertTrue(sidebarStatus.helpText.contains("Retry Plan"))
        XCTAssertTrue(sidebarStatus.helpText.contains("#2"))
        XCTAssertTrue(sidebarStatus.accessibilityLabel.contains("2 cues"))
    }

    func testSidebarSubtitlesUsePrimaryReliabilityDetail() {
        let blockedStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(
                feedback: PlanReliabilityFeedback(
                    state: makeState(),
                    sessions: [
                        makeSession(
                            4,
                            status: .failed,
                            notes: ["Develop reported it was blocked but did not request verify bypass."],
                            feedback: "Missing signing credentials."
                        )
                    ]
                )
            )
        )
        let failedStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(
                feedback: PlanReliabilityFeedback(
                    state: makeState(),
                    sessions: [
                        makeSession(
                            5,
                            status: .failed,
                            notes: ["Develop reported failure: build settings were inconsistent"],
                            feedback: "build settings were inconsistent"
                        )
                    ]
                )
            )
        )
        let failedVerifyStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(
                feedback: PlanReliabilityFeedback(
                    state: makeState(),
                    sessions: [
                        makeSession(
                            6,
                            status: .failed,
                            verifyOutput: VerifyOutput(
                                command: "swift test --filter ProjectSidebarStatusTests",
                                exitCode: 65,
                                tail: "Test Suite failed\n\nExpected true but got false"
                            )
                        )
                    ]
                )
            )
        )
        let resumeStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(
                feedback: PlanReliabilityFeedback(
                    state: makeState(),
                    sessions: [
                        makeSession(
                            7,
                            status: .awaitingApproval,
                            plan: "Implement the approved next slice"
                        )
                    ]
                )
            )
        )

        XCTAssertEqual(blockedStatus.title, "Develop blocked")
        XCTAssertEqual(blockedStatus.subtitle, "Missing signing credentials.")
        XCTAssertEqual(failedStatus.title, "Develop failed")
        XCTAssertEqual(failedStatus.subtitle, "build settings were inconsistent")
        XCTAssertEqual(failedVerifyStatus.title, "Verify failed")
        XCTAssertEqual(failedVerifyStatus.subtitle, "Test Suite failed Expected true but got false")
        XCTAssertEqual(resumeStatus.title, "Develop ready")
        XCTAssertEqual(resumeStatus.subtitle, "Implement the approved next slice")
    }

    func testMultipleCueSidebarStatusReportsCountLabel() {
        let session = makeSession(
            8,
            status: .failed,
            notes: ["Develop reported failure: compile failed"],
            verifyOutput: VerifyOutput(
                command: "swift test",
                exitCode: 1,
                tail: "compile failure"
            ),
            feedback: "compile failed"
        )
        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        let sidebarStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(feedback: feedback)
        )

        XCTAssertEqual(sidebarStatus.cueCount, 2)
        XCTAssertEqual(sidebarStatus.countLabel, "2 cues")
        XCTAssertEqual(sidebarStatus.title, "Develop failed")
        XCTAssertTrue(sidebarStatus.helpText.contains("2 cues"))
        XCTAssertTrue(sidebarStatus.accessibilityLabel.contains("2 cues"))
    }

    func testSidebarSubtitleIsBoundedForCompactRows() {
        let session = makeSession(
            9,
            status: .failed,
            notes: ["Develop reported it was blocked but did not request verify bypass."],
            feedback: "First line\n\nsecond line with enough extra words to force a compact sidebar row."
        )
        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [session],
            detailLimit: 200
        )

        let sidebarStatus = makeSidebarStatus(
            reliabilityStatus: ProjectReliabilityStatus(feedback: feedback, detailLimit: 120),
            subtitleLimit: 45
        )

        XCTAssertLessThanOrEqual(sidebarStatus.subtitle.count, 45)
        XCTAssertTrue(sidebarStatus.subtitle.hasPrefix("First line second line"))
        XCTAssertTrue(sidebarStatus.subtitle.hasSuffix("..."))
    }

    func testRunningAndPausedPhaseCanCoexistWithReliabilityCue() {
        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [
                makeSession(
                    10,
                    status: .failed,
                    notes: ["Develop reported it was blocked but did not request verify bypass."],
                    feedback: "Waiting on local account credentials."
                )
            ]
        )
        let reliabilityStatus = ProjectReliabilityStatus(feedback: feedback)

        let pausedWhileRunning = makeSidebarStatus(
            reliabilityStatus: reliabilityStatus,
            phase: .developing,
            isRunning: true,
            isPaused: true,
            pauseMode: .afterIteration
        )
        let autoPlaying = makeSidebarStatus(
            reliabilityStatus: reliabilityStatus,
            phase: .verifying,
            isAutoPlaying: true
        )

        XCTAssertTrue(pausedWhileRunning.hasReliabilityCue)
        XCTAssertTrue(pausedWhileRunning.showsProgress)
        XCTAssertEqual(pausedWhileRunning.phaseLabel, "Pausing after iteration")
        XCTAssertEqual(pausedWhileRunning.title, "Develop blocked")
        XCTAssertTrue(autoPlaying.hasReliabilityCue)
        XCTAssertTrue(autoPlaying.showsProgress)
        XCTAssertEqual(autoPlaying.phaseLabel, "Auto - Verifying")
    }

    private func makeSidebarStatus(
        reliabilityStatus: ProjectReliabilityStatus,
        immediateTitle: String = "Implement reliability feedback",
        phase: LoopPhase = .idle,
        isRunning: Bool = false,
        isAutoPlaying: Bool = false,
        isPaused: Bool = false,
        pauseMode: PauseMode = .immediate,
        subtitleLimit: Int = ProjectSidebarStatus.defaultSubtitleLimit
    ) -> ProjectSidebarStatus {
        ProjectSidebarStatus(
            reliabilityStatus: reliabilityStatus,
            immediateTitle: immediateTitle,
            phase: phase,
            isRunning: isRunning,
            isAutoPlaying: isAutoPlaying,
            isPaused: isPaused,
            pauseMode: pauseMode,
            subtitleLimit: subtitleLimit
        )
    }

    private func makeState(
        immediate: PlanNext? = PlanNext(
            plan: "Implement reliability feedback",
            verify: "swift test --filter ProjectSidebarStatusTests"
        )
    ) -> PlanState {
        PlanState(
            completed: [],
            immediate: immediate,
            midTerm: "",
            longTerm: ""
        )
    }

    private func makeSession(
        _ number: Int,
        startedAt: Double? = nil,
        status: SessionStatus,
        plan: String? = "Plan",
        verify: String? = "swift test --filter ProjectSidebarStatusTests",
        notes: [String] = [],
        verifyOutput: VerifyOutput? = nil,
        feedback: String? = nil
    ) -> SessionRecord {
        let start = startedAt ?? Double(number) * 1_000
        return SessionRecord(
            session: number,
            startedAt: start,
            endedAt: start + 500,
            plan: plan,
            verify: verify,
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: status,
            notes: notes,
            verifyOutput: verifyOutput,
            feedback: feedback
        )
    }
}
