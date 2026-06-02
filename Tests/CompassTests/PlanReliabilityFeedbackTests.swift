import Foundation
import Testing

@testable import Compass

struct PlanReliabilityFeedbackTests {
  @Test func testRejectedPlanStatusUsesRejectionText() throws {
    let session = makeSession(
      1,
      status: .rejectedByPlan,
      notes: [
        "Plan tried to shrink completed history from 3 entries to 2. Refusing to overwrite state.json."
      ],
      feedback: "fallback"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.count == 1)
    try #require(feedback.notices[0].kind == .rejectedPlan)
    try #require(feedback.notices[0].title == "Plan rejected")
    try #require(
      feedback.notices[0].detail
        == "Plan tried to shrink completed history from 3 entries to 2. Refusing to overwrite state.json."
    )
    try #require(feedback.notices[0].actionLabel == "Retry Plan")
    try #require(feedback.recentRunCues[1]?.kind == .rejectedPlan)
    try #require(feedback.recentRunCues[1]?.label == "Retry Plan")
  }

  @Test func testFailedPlanTransitionNoteBecomesRejectedPlanNotice() throws {
    let session = makeSession(
      2,
      status: .failed,
      notes: [
        "Plan returned placeholder verify command `true`. Refusing to overwrite state.json."
      ]
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.rejectedPlan])
    try #require(
      feedback.notices[0].detail
        == "Plan returned placeholder verify command `true`. Refusing to overwrite state.json."
    )
  }

  @Test func testCoverageRequirementNoteBecomesRejectedPlanNotice() throws {
    let session = makeSession(
      15,
      status: .failed,
      notes: [
        """
        Verify command must collect test coverage for Swift Package projects. \
        test verify must declare coverage: guest `swift test --enable-code-coverage`.
        """
      ]
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.rejectedPlan])
    try #require(feedback.notices[0].title == "Plan rejected")
    try #require(feedback.notices[0].detail.contains("must collect test coverage"))
    try #require(feedback.recentRunCues[15]?.kind == .rejectedPlan)
  }

  @Test func testVerifyBypassHandoffBecomesRejectedPlanNotice() throws {
    let session = makeSession(
      16,
      status: .failed,
      notes: [
        """
        [verify] Verify was skipped because Develop reported the planned command is wrong or out of scope.
        Planned verify command: `swift test --filter RemovedSuite`
        Develop handoff: Verify command is wrong because RemovedSuite no longer exists.
        Plan should replace the verify command or rescope Immediate Work before Develop continues.
        """
      ]
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.rejectedPlan])
    try #require(feedback.notices[0].title == "Plan rejected")
    try #require(feedback.notices[0].actionLabel == "Retry Plan")
    try #require(feedback.notices[0].detail.contains("Verify was skipped"))
    try #require(feedback.recentRunCues[16]?.label == "Retry Plan")
  }

  @Test func testDevelopBlockerUsesFeedbackText() throws {
    let session = makeSession(
      3,
      status: .failed,
      notes: ["Develop reported it was blocked but did not request verify bypass."],
      feedback: "  Missing signing credentials.\nAsk the next pass to add a local fixture. "
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.developBlocked])
    try #require(feedback.notices[0].title == "Develop blocked")
    try #require(
      feedback.notices[0].detail
        == "Missing signing credentials. Ask the next pass to add a local fixture.")
    try #require(feedback.notices[0].actionLabel == "Retry Develop")
  }

  @Test func testFailedDevelopUsesFeedbackWhenNoVerifyOutputExists() throws {
    let session = makeSession(
      4,
      status: .failed,
      notes: ["Develop reported failure: build settings were inconsistent"],
      feedback: "build settings were inconsistent"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.developFailed])
    try #require(feedback.notices[0].detail == "build settings were inconsistent")
    try #require(feedback.recentRunCues[4]?.label == "Retry Develop")
  }

  @Test func testAgentHandoffFailureNoteBecomesDevelopFailedNotice() throws {
    let session = makeSession(
      17,
      status: .failed,
      notes: [
        "Develop attempt 1 ended without submit_result: Agent exceeded max iterations (10)."
      ]
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.developFailed])
    try #require(feedback.notices[0].title == "Develop failed")
    try #require(feedback.notices[0].detail.contains("ended without submit_result"))
    try #require(feedback.recentRunCues[17]?.label == "Retry Develop")
  }

  @Test func testFailedVerifyIncludesTailMetadata() throws {
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

    try #require(feedback.notices.map(\.kind) == [.failedVerify])
    try #require(feedback.notices[0].title == "Verify failed")
    try #require(feedback.notices[0].detail == "Test Suite failed Expected true but got false")
    try #require(
      feedback.notices[0].metadata == "swift test --filter PlanReliabilityFeedbackTests · exit 65"
    )
    try #require(feedback.recentRunCues[5]?.kind == .failedVerify)
  }

  @Test func testDirtyWorktreePostCheckNoteBecomesDistinctCue() throws {
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

    try #require(feedback.notices.map(\.kind) == [.dirtyWorktree])
    try #require(feedback.notices[0].title == "Worktree dirty")
    try #require(feedback.notices[0].severity == .warning)
    try #require(feedback.notices[0].actionLabel == "Clean Worktree")
    try #require(feedback.notices[0].metadata == "#12 · 2 pending changes")
    try #require(feedback.notices[0].detail.hasPrefix("Uncommitted or untracked changes remain"))
    try #require(feedback.recentRunCues[12]?.kind == .dirtyWorktree)
    try #require(feedback.recentRunCues[12]?.systemImage == "pencil.and.outline")
  }

  @Test func testPromotionFailurePostCheckNoteBecomesDistinctCue() throws {
    let session = makeSession(
      13,
      status: .failed,
      notes: [
        "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
      ],
      feedback: "done"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.promotionFailed])
    try #require(feedback.notices[0].title == "Promotion failed")
    try #require(feedback.notices[0].severity == .failure)
    try #require(feedback.notices[0].actionLabel == "Resolve Promotion")
    try #require(feedback.notices[0].metadata == "#13 · compass/dev-123")
    try #require(
      feedback.notices[0].detail
        == "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
    )
    try #require(feedback.recentRunCues[13]?.kind == .promotionFailed)
  }

  @Test func testRecentRunCueUsesPostCheckPriorityWithinSession() throws {
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

    try #require(feedback.notices.map(\.kind) == [.developFailed, .failedVerify])
    try #require(feedback.recentRunCues[14]?.kind == .failedVerify)
    try #require(feedback.recentRunCues[14]?.label == "Retry Develop")
  }

  @Test func testAwaitingApprovalShowsResumeCueWhenImmediatePlanExists() throws {
    let session = makeSession(
      6,
      status: .awaitingApproval,
      plan: "Implement the approved next slice"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    try #require(feedback.notices.map(\.kind) == [.resumeDevelop])
    try #require(feedback.notices[0].title == "Develop ready")
    try #require(feedback.notices[0].actionLabel == "Resume Develop")
    try #require(feedback.notices[0].detail == "Implement the approved next slice")
    try #require(feedback.recentRunCues[6]?.label == "Resume Develop")
  }

  @Test func testSuccessfulAndCleanStatesStayEmpty() throws {
    let sessions = [
      makeSession(7, status: .succeeded, feedback: "done"),
      makeSession(8, status: .skipped, notes: ["Plan returned no immediate work."]),
    ]

    let feedback = PlanReliabilityFeedback(
      state: makeState(immediate: nil),
      sessions: sessions
    )

    try #require(feedback.isEmpty)
    try #require(feedback.recentRunCues == [:])
  }

  @Test func testLaterSuccessRetiresEarlierFailureCue() throws {
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

    try #require(feedback.notices.isEmpty)
    try #require(feedback.recentRunCues[4] == nil)
    try #require(feedback.recentRunCues[5] == nil)
  }

  @Test func testInFlightSessionAfterFailureKeepsCue() throws {
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

    try #require(feedback.notices.map(\.kind) == [.developBlocked])
    try #require(feedback.recentRunCues[4]?.kind == .developBlocked)
  }

  @Test func testBoundsAndNormalizesDetails() throws {
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
    try #require(detail.count <= 38)
    try #require(detail == "First line second line with enough...")
  }

  @Test func testNoticeSectionLimitAndRecentRunCuePropagationCanDiffer() throws {
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
      notes: [
        "Plan tried to clear all actionable candidates without recording a completion. Refusing to overwrite state.json."
      ]
    )

    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [olderRejectedPlan, newestFailedVerify],
      noticeLimit: 1
    )

    try #require(feedback.notices.map(\.sessionNumber) == [10])
    try #require(feedback.notices.map(\.kind) == [.failedVerify])
    try #require(feedback.recentRunCues[10]?.kind == .failedVerify)
    try #require(feedback.recentRunCues[11]?.kind == .rejectedPlan)
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
      candidates: "",
      strategicContext: ""
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
