import Foundation
@testable import Compass
import XCTest

final class ProjectReliabilityStatusTests: XCTestCase {
    func testCleanFeedbackProducesNoCueStatus() {
        let sessions = [
            makeSession(1, status: .succeeded, feedback: "done"),
            makeSession(2, status: .skipped, notes: ["Plan returned no immediate work."])
        ]
        let feedback = PlanReliabilityFeedback(
            state: makeState(immediate: nil),
            sessions: sessions
        )

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertTrue(status.isEmpty)
        XCTAssertEqual(status.noticeCount, 0)
        XCTAssertEqual(status.countLabel, "0 cues")
        XCTAssertEqual(status.primaryCue, "")
        XCTAssertEqual(status.detail, "")
    }

    func testRejectedPlanTakesPriorityOverNewerVerifyFailure() {
        let newerFailedVerify = makeSession(
            2,
            startedAt: 2_000,
            status: .failed,
            verifyOutput: VerifyOutput(
                command: "swift test",
                exitCode: 1,
                tail: "latest verify failure"
            )
        )
        let olderRejectedPlan = makeSession(
            1,
            startedAt: 1_000,
            status: .failed,
            notes: [
                "Plan tried to clear a non-empty queue without recording completion. Refusing to overwrite state.json."
            ]
        )
        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [olderRejectedPlan, newerFailedVerify]
        )

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(feedback.notices.map(\.kind), [.failedVerify, .rejectedPlan])
        XCTAssertFalse(status.isEmpty)
        XCTAssertEqual(status.primaryCue, "Plan rejected")
        XCTAssertEqual(status.severity, .failure)
        XCTAssertEqual(status.actionLabel, "Retry Plan")
        XCTAssertEqual(status.metadata, "#1")
        XCTAssertEqual(status.countLabel, "2 cues")
    }

    func testDevelopBlockedAndFailedCuesUseDevelopActions() {
        let blockedFeedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [
                makeSession(
                    3,
                    status: .failed,
                    notes: ["Develop reported it was blocked but did not request verify bypass."],
                    feedback: "Missing signing credentials."
                )
            ]
        )
        let failedFeedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [
                makeSession(
                    4,
                    status: .failed,
                    notes: ["Develop reported failure: build settings were inconsistent"],
                    feedback: "build settings were inconsistent"
                )
            ]
        )

        let blockedStatus = ProjectReliabilityStatus(feedback: blockedFeedback)
        let failedStatus = ProjectReliabilityStatus(feedback: failedFeedback)

        XCTAssertEqual(blockedStatus.primaryCue, "Develop blocked")
        XCTAssertEqual(blockedStatus.severity, .warning)
        XCTAssertEqual(blockedStatus.actionLabel, "Retry Develop")
        XCTAssertEqual(blockedStatus.detail, "Missing signing credentials.")
        XCTAssertEqual(failedStatus.primaryCue, "Develop failed")
        XCTAssertEqual(failedStatus.severity, .failure)
        XCTAssertEqual(failedStatus.actionLabel, "Retry Develop")
        XCTAssertEqual(failedStatus.detail, "build settings were inconsistent")
    }

    func testFailedVerifyStatusCarriesVerifyMetadata() {
        let session = makeSession(
            5,
            status: .failed,
            verifyOutput: VerifyOutput(
                command: "swift test --filter ProjectReliabilityStatusTests",
                exitCode: 65,
                tail: """
                Test Suite failed

                Expected true but got false
                """
            )
        )
        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(status.primaryCue, "Verify failed")
        XCTAssertEqual(status.severity, .failure)
        XCTAssertEqual(status.actionLabel, "Retry Develop")
        XCTAssertEqual(
            status.metadata,
            "swift test --filter ProjectReliabilityStatusTests · exit 65"
        )
        XCTAssertEqual(status.detail, "Test Suite failed Expected true but got false")
    }

    func testDirtyWorktreeStatusCarriesPostCheckMetadata() {
        let session = makeSession(
            9,
            status: .failed,
            notes: [
                """
                Uncommitted or untracked changes remain after Develop ran. Commit them or add them to .gitignore.
                `git status --porcelain` output:
                ```
                 M Sources/Compass/AppModel.swift
                ```
                """
            ],
            feedback: "done"
        )
        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(status.primaryCue, "Worktree dirty")
        XCTAssertEqual(status.severity, .warning)
        XCTAssertEqual(status.actionLabel, "Clean Worktree")
        XCTAssertEqual(status.metadata, "#9 · 1 pending change")
        XCTAssertTrue(status.detail.hasPrefix("Uncommitted or untracked changes remain"))
    }

    func testPromotionFailureStatusCarriesPromotionMetadata() {
        let session = makeSession(
            10,
            status: .failed,
            notes: [
                "Develop sandbox produced no commit to promote."
            ],
            feedback: "done"
        )
        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(status.primaryCue, "Promotion failed")
        XCTAssertEqual(status.severity, .failure)
        XCTAssertEqual(status.actionLabel, "Resolve Promotion")
        XCTAssertEqual(status.metadata, "#10 · promotion")
        XCTAssertEqual(status.detail, "Develop sandbox produced no commit to promote.")
    }

    func testMutationRecoveryStatusCarriesReviewMetadata() {
        let session = makeSession(
            12,
            status: .failed,
            mutationTestingExecutions: [
                makeMutationExecution(
                    verify: "swift test --filter MutationRecovery",
                    exitCode: 65,
                    startedAt: 12_000,
                    endedAt: 12_900,
                    outputTail: "mutation failure tail"
                )
            ]
        )
        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(status.primaryCue, "Mutation recovery")
        XCTAssertEqual(status.severity, .failure)
        XCTAssertEqual(status.actionLabel, "Review Mutation")
        XCTAssertEqual(status.metadata, "#12 · swift test --filter MutationRecovery · exit 65")
        XCTAssertEqual(status.detail, "mutation failure tail")
    }

    func testAwaitingApprovalStatusUsesResumeCue() {
        let session = makeSession(
            6,
            status: .awaitingApproval,
            plan: "Implement the approved next slice"
        )
        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(status.primaryCue, "Develop ready")
        XCTAssertEqual(status.severity, .paused)
        XCTAssertEqual(status.actionLabel, "Resume Develop")
        XCTAssertEqual(status.metadata, "#6")
        XCTAssertEqual(status.detail, "Implement the approved next slice")
        XCTAssertEqual(status.countLabel, "1 cue")
    }

    func testMultipleCueStatusReportsCountLabel() {
        let session = makeSession(
            7,
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

        let status = ProjectReliabilityStatus(feedback: feedback)

        XCTAssertEqual(feedback.notices.map(\.kind), [.developFailed, .failedVerify])
        XCTAssertEqual(status.noticeCount, 2)
        XCTAssertEqual(status.countLabel, "2 cues")
        XCTAssertEqual(status.primaryCue, "Verify failed")
        XCTAssertEqual(status.metadata, "swift test · exit 1")
    }

    func testDetailCanBeBoundedForCompactProjectSurfaces() {
        let session = makeSession(
            11,
            status: .failed,
            notes: ["Develop reported it was blocked but did not request verify bypass."],
            feedback: "First line\n\nsecond line with enough extra words to force a compact project banner."
        )
        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [session],
            detailLimit: 200
        )

        let status = ProjectReliabilityStatus(feedback: feedback, detailLimit: 46)

        XCTAssertLessThanOrEqual(status.detail.count, 46)
        XCTAssertTrue(status.detail.hasPrefix("First line second line"))
        XCTAssertTrue(status.detail.hasSuffix("..."))
    }

    private func makeState(
        immediate: PlanNext? = PlanNext(
            plan: "Implement reliability feedback",
            verify: "swift test --filter ProjectReliabilityStatusTests"
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
        verify: String? = "swift test --filter ProjectReliabilityStatusTests",
        notes: [String] = [],
        verifyOutput: VerifyOutput? = nil,
        feedback: String? = nil,
        mutationTestingExecutions: [SessionMutationTestingExecution] = []
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
            feedback: feedback,
            mutationTestingExecutions: mutationTestingExecutions
        )
    }

    private func makeMutationExecution(
        verify: String,
        exitCode: Int?,
        startedAt: Double,
        endedAt: Double,
        outputTail: String
    ) -> SessionMutationTestingExecution {
        let launchPlan = AgentExecutionLaunchPlan.host()
        let readiness = AgentMutationTestingPlan(
            state: PlanState(
                completed: [],
                immediate: PlanNext(plan: "Run mutation testing", verify: verify),
                midTerm: "",
                longTerm: ""
            ),
            languageProfile: profile(.swift),
            launchPlan: launchPlan
        )
        return SessionMutationTestingExecution(
            readiness: readiness,
            exitCode: exitCode,
            startedAt: startedAt,
            endedAt: endedAt,
            outputTail: outputTail,
            launchPlan: launchPlan
        )
    }

    private func profile(_ language: RepositoryLanguage) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = 1
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: [],
            primaryLanguage: language,
            scannedFileCount: 1,
            scannedDirectoryCount: 1,
            wasTruncated: false
        )
    }
}
