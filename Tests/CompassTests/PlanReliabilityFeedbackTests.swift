import Foundation
@testable import Compass
import XCTest

final class PlanReliabilityFeedbackTests: XCTestCase {
    func testRejectedPlanStatusUsesRejectionText() {
        let session = makeSession(
            1,
            status: .rejectedByPlan,
            notes: [
                "Plan tried to shrink completed history from 3 entries to 2. Refusing to overwrite state.json."
            ],
            feedback: "fallback"
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.count, 1)
        XCTAssertEqual(feedback.notices[0].kind, .rejectedPlan)
        XCTAssertEqual(feedback.notices[0].title, "Plan rejected")
        XCTAssertEqual(
            feedback.notices[0].detail,
            "Plan tried to shrink completed history from 3 entries to 2. Refusing to overwrite state.json."
        )
        XCTAssertEqual(feedback.notices[0].actionLabel, "Retry Plan")
        XCTAssertEqual(feedback.recentRunCues[1]?.kind, .rejectedPlan)
        XCTAssertEqual(feedback.recentRunCues[1]?.label, "Retry Plan")
    }

    func testFailedPlanTransitionNoteBecomesRejectedPlanNotice() {
        let session = makeSession(
            2,
            status: .failed,
            notes: [
                "Plan returned placeholder verify command `true`. Refusing to overwrite state.json."
            ]
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.rejectedPlan])
        XCTAssertEqual(
            feedback.notices[0].detail,
            "Plan returned placeholder verify command `true`. Refusing to overwrite state.json."
        )
    }

    func testDevelopBlockerUsesFeedbackText() {
        let session = makeSession(
            3,
            status: .failed,
            notes: ["Develop reported it was blocked but did not request verify bypass."],
            feedback: "  Missing signing credentials.\nAsk the next pass to add a local fixture. "
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.developBlocked])
        XCTAssertEqual(feedback.notices[0].title, "Develop blocked")
        XCTAssertEqual(feedback.notices[0].detail, "Missing signing credentials. Ask the next pass to add a local fixture.")
        XCTAssertEqual(feedback.notices[0].actionLabel, "Retry Develop")
    }

    func testFailedDevelopUsesFeedbackWhenNoVerifyOutputExists() {
        let session = makeSession(
            4,
            status: .failed,
            notes: ["Develop reported failure: build settings were inconsistent"],
            feedback: "build settings were inconsistent"
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.developFailed])
        XCTAssertEqual(feedback.notices[0].detail, "build settings were inconsistent")
        XCTAssertEqual(feedback.recentRunCues[4]?.label, "Retry Develop")
    }

    func testFailedVerifyIncludesTailMetadata() {
        let session = makeSession(
            5,
            status: .failed,
            verify: "swift test --filter Plan",
            verifyOutput: VerifyOutput(
                command: "swift test --filter PlanReliabilityFeedbackTests",
                exitCode: 65,
                tail: """
                Test Suite failed

                Expected true but got false
                """
            )
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.failedVerify])
        XCTAssertEqual(feedback.notices[0].title, "Verify failed")
        XCTAssertEqual(feedback.notices[0].detail, "Test Suite failed Expected true but got false")
        XCTAssertEqual(
            feedback.notices[0].metadata,
            "swift test --filter PlanReliabilityFeedbackTests · exit 65"
        )
        XCTAssertEqual(feedback.recentRunCues[5]?.kind, .failedVerify)
    }

    func testDirtyWorktreePostCheckNoteBecomesDistinctCue() {
        let session = makeSession(
            12,
            status: .failed,
            notes: [
                """
                Uncommitted or untracked changes remain after Develop ran. Commit them or add them to .gitignore.
                `git status --porcelain` output:
                ```
                 M Sources/Compass/AppModel.swift
                ?? Tests/CompassTests/NewTests.swift
                ```
                """
            ],
            feedback: "done"
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.dirtyWorktree])
        XCTAssertEqual(feedback.notices[0].title, "Worktree dirty")
        XCTAssertEqual(feedback.notices[0].severity, .warning)
        XCTAssertEqual(feedback.notices[0].actionLabel, "Clean Worktree")
        XCTAssertEqual(feedback.notices[0].metadata, "#12 · 2 pending changes")
        XCTAssertTrue(feedback.notices[0].detail.hasPrefix("Uncommitted or untracked changes remain"))
        XCTAssertEqual(feedback.recentRunCues[12]?.kind, .dirtyWorktree)
        XCTAssertEqual(feedback.recentRunCues[12]?.systemImage, "pencil.and.outline")
    }

    func testPromotionFailurePostCheckNoteBecomesDistinctCue() {
        let session = makeSession(
            13,
            status: .failed,
            notes: [
                "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
            ],
            feedback: "done"
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.promotionFailed])
        XCTAssertEqual(feedback.notices[0].title, "Promotion failed")
        XCTAssertEqual(feedback.notices[0].severity, .failure)
        XCTAssertEqual(feedback.notices[0].actionLabel, "Resolve Promotion")
        XCTAssertEqual(feedback.notices[0].metadata, "#13 · compass/dev-123")
        XCTAssertEqual(
            feedback.notices[0].detail,
            "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
        )
        XCTAssertEqual(feedback.recentRunCues[13]?.kind, .promotionFailed)
    }

    func testRecentRunCueUsesPostCheckPriorityWithinSession() {
        let session = makeSession(
            14,
            status: .failed,
            notes: ["Develop reported failure: compile failed"],
            verifyOutput: VerifyOutput(
                command: "swift test --filter PlanReliabilityFeedbackTests",
                exitCode: 1,
                tail: "compile failure"
            ),
            feedback: "compile failed"
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.developFailed, .failedVerify])
        XCTAssertEqual(feedback.recentRunCues[14]?.kind, .failedVerify)
        XCTAssertEqual(feedback.recentRunCues[14]?.label, "Retry Develop")
    }

    func testAwaitingApprovalShowsResumeCueWhenImmediatePlanExists() {
        let session = makeSession(
            6,
            status: .awaitingApproval,
            plan: "Implement the approved next slice"
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.resumeDevelop])
        XCTAssertEqual(feedback.notices[0].title, "Develop ready")
        XCTAssertEqual(feedback.notices[0].actionLabel, "Resume Develop")
        XCTAssertEqual(feedback.notices[0].detail, "Implement the approved next slice")
        XCTAssertEqual(feedback.recentRunCues[6]?.label, "Resume Develop")
    }

    func testSuccessfulAndCleanStatesStayEmpty() {
        let sessions = [
            makeSession(7, status: .succeeded, feedback: "done"),
            makeSession(8, status: .skipped, notes: ["Plan returned no immediate work."])
        ]

        let feedback = PlanReliabilityFeedback(
            state: makeState(immediate: nil),
            sessions: sessions
        )

        XCTAssertTrue(feedback.isEmpty)
        XCTAssertEqual(feedback.recentRunCues, [:])
    }

    func testLatestFailedMutationExecutionBecomesReadOnlyRecoveryCue() {
        let session = makeSession(
            15,
            status: .failed,
            mutationTestingExecutions: [
                makeMutationExecution(
                    verify: "swift test --filter MutationRecovery",
                    exitCode: 65,
                    startedAt: 15_000,
                    endedAt: 16_250,
                    outputTail: "mutation failure tail"
                )
            ]
        )

        let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

        XCTAssertEqual(feedback.notices.map(\.kind), [.mutationTestingRecovery])
        XCTAssertEqual(feedback.notices[0].title, "Mutation recovery")
        XCTAssertEqual(feedback.notices[0].actionLabel, "Review Mutation")
        XCTAssertEqual(feedback.notices[0].severity, .failure)
        XCTAssertEqual(feedback.recentRunCues[15]?.kind, .mutationTestingRecovery)
        XCTAssertEqual(feedback.recentRunCues[15]?.label, "Review Mutation")
    }

    func testSucceededMissingAndOldMutationExecutionsStayOutOfRecoveryCues() {
        let oldFailed = makeSession(
            16,
            startedAt: 16_000,
            status: .failed,
            mutationTestingExecutions: [
                makeMutationExecution(
                    verify: "swift test --filter OldMutation",
                    exitCode: 65,
                    startedAt: 16_000,
                    endedAt: 16_500,
                    outputTail: "old mutation failure"
                )
            ]
        )
        let latestSucceeded = makeSession(
            17,
            startedAt: 17_000,
            status: .succeeded,
            mutationTestingExecutions: [
                makeMutationExecution(
                    verify: "swift test --filter LatestMutation",
                    exitCode: 0,
                    startedAt: 17_000,
                    endedAt: 17_500,
                    outputTail: "mutation ok"
                )
            ]
        )
        let missing = makeSession(18, startedAt: 18_000, status: .succeeded)

        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [oldFailed, latestSucceeded, missing]
        )

        XCTAssertFalse(feedback.notices.contains { $0.kind == .mutationTestingRecovery })
        XCTAssertNil(feedback.recentRunCues[16])
        XCTAssertNil(feedback.recentRunCues[17])
        XCTAssertNil(feedback.recentRunCues[18])
    }

    func testLaterSuccessRetiresEarlierFailureCue() {
        let blocked = makeSession(
            4,
            startedAt: 4_000,
            status: .failed,
            notes: ["Develop reported it was blocked but did not request verify bypass."],
            feedback: "Missing signing credentials."
        )
        let later = makeSession(5, startedAt: 5_000, status: .succeeded, feedback: "ok")

        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [blocked, later]
        )

        XCTAssertTrue(feedback.notices.isEmpty)
        XCTAssertNil(feedback.recentRunCues[4])
        XCTAssertNil(feedback.recentRunCues[5])
    }

    func testInFlightSessionAfterFailureKeepsCue() {
        let blocked = makeSession(
            4,
            startedAt: 4_000,
            status: .failed,
            notes: ["Develop reported it was blocked but did not request verify bypass."],
            feedback: "Missing signing credentials."
        )
        let retrying = makeSession(5, startedAt: 5_000, status: .developing)

        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [blocked, retrying]
        )

        XCTAssertEqual(feedback.notices.map(\.kind), [.developBlocked])
        XCTAssertEqual(feedback.recentRunCues[4]?.kind, .developBlocked)
    }

    func testBoundsAndNormalizesDetails() {
        let session = makeSession(
            9,
            status: .failed,
            notes: ["Develop reported it was blocked but did not request verify bypass."],
            feedback: "  First line\n\n\tsecond   line with enough extra words to force truncation. "
        )

        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [session],
            detailLimit: 38
        )

        let detail = feedback.notices[0].detail
        XCTAssertLessThanOrEqual(detail.count, 38)
        XCTAssertEqual(detail, "First line second line with enough...")
    }

    func testNoticeSectionLimitAndRecentRunCuePropagationCanDiffer() {
        let newestFailedVerify = makeSession(
            10,
            startedAt: 9_000,
            status: .failed,
            verifyOutput: VerifyOutput(
                command: "swift test",
                exitCode: 1,
                tail: "latest failure"
            )
        )
        let olderRejectedPlan = makeSession(
            11,
            startedAt: 8_000,
            status: .failed,
            notes: ["Plan tried to clear a non-empty midTerm queue without recording a completion. Refusing to overwrite state.json."]
        )

        let feedback = PlanReliabilityFeedback(
            state: makeState(),
            sessions: [olderRejectedPlan, newestFailedVerify],
            noticeLimit: 1
        )

        XCTAssertEqual(feedback.notices.map(\.sessionNumber), [10])
        XCTAssertEqual(feedback.notices.map(\.kind), [.failedVerify])
        XCTAssertEqual(feedback.recentRunCues[10]?.kind, .failedVerify)
        XCTAssertEqual(feedback.recentRunCues[11]?.kind, .rejectedPlan)
    }

    private func makeState(
        immediate: PlanNext? = PlanNext(
            plan: "Implement reliability feedback",
            verify: "swift test --filter Plan"
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
        verify: String? = "swift test --filter Plan",
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
