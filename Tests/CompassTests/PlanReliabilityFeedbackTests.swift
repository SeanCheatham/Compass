import Foundation
import Testing

@testable import Compass

struct PlanReliabilityFeedbackTests {
  @Test func testRejectedPlanStatusUsesRejectionText() {
    let session = makeSession(
      1,
      status: .rejectedByPlan,
      notes: [
        "Plan tried to shrink completed history from 3 entries to 2. Refusing to overwrite state.json."
      ],
      feedback: "fallback"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    #require(feedback.notices.count == 1)
    #require(feedback.notices[0].kind == .rejectedPlan)
    #require(feedback.notices[0].title == "Plan rejected")
    #require(
      feedback.notices[0].detail ==
      "Plan tried to shrink completed history from 3 entries to 2. Refusing to overwrite state.json."
    )
    #require(feedback.notices[0].actionLabel == "Retry Plan")
    #require(feedback.recentRunCues[1]?.kind == .rejectedPlan)
    #require(feedback.recentRunCues[1]?.label == "Retry Plan")
  }

  @Test func testFailedPlanTransitionNoteBecomesRejectedPlanNotice() {
    let session = makeSession(
      2,
      status: .failed,
      notes: [
        "Plan returned placeholder verify command `true`. Refusing to overwrite state.json."
      ]
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    #require(feedback.notices.map(\.kind) == [.rejectedPlan])
    #require(
      feedback.notices[0].detail ==
      "Plan returned placeholder verify command `true`. Refusing to overwrite state.json."
    )
  }

  @Test func testDevelopBlockerUsesFeedbackText() {
    let session = makeSession(
      3,
      status: .failed,
      notes: ["Develop reported it was blocked but did not request verify bypass."],
      feedback: "  Missing signing credentials.\nAsk the next pass to add a local fixture. "
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    #require(feedback.notices.map(\.kind) == [.developBlocked])
    #require(feedback.notices[0].title == "Develop blocked")
    #require(
      feedback.notices[0].detail ==
      "Missing signing credentials. Ask the next pass to add a local fixture.")
    #require(feedback.notices[0].actionLabel == "Retry Develop")
  }

  @Test func testFailedDevelopUsesFeedbackWhenNoVerifyOutputExists() {
    let session = makeSession(
      4,
      status: .failed,
      notes: ["Develop reported failure: build settings were inconsistent"],
      feedback: "build settings were inconsistent"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    #require(feedback.notices.map(\.kind) == [.developFailed])
    #require(feedback.notices[0].detail == "build settings were inconsistent")
    #require(feedback.recentRunCues[4]?.label == "Retry Develop")
  }

  @Test func testFailedVerifyIncludesTailMetadata() {
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

    #require(feedback.notices.map(\.kind) == [.failedVerify])
    #require(feedback.notices[0].title == "Verify failed")
    #require(feedback.notices[0].detail == "Test Suite failed Expected true but got false")
    #require(
      feedback.notices[0].metadata ==
      "swift test --filter PlanReliabilityFeedbackTests · exit 65"
    )
    #require(feedback.recentRunCues[5]?.kind == .failedVerify)
  }

  @Test func testDirtyWorktreePostCheckNoteBecomesDistinctCue() {
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

    #require(feedback.notices.map(\.kind) == [.dirtyWorktree])
    #require(feedback.notices[0].title == "Worktree dirty")
    #require(feedback.notices[0].severity == .warning)
    #require(feedback.notices[0].actionLabel == "Clean Worktree")
    #require(feedback.notices[0].metadata == "#12 · 2 pending changes")
    #require(feedback.notices[0].detail.hasPrefix("Uncommitted or untracked changes remain"))
    #require(feedback.recentRunCues[12]?.kind == .dirtyWorktree)
    #require(feedback.recentRunCues[12]?.systemImage == "pencil.and.outline")
  }

  @Test func testPromotionFailurePostCheckNoteBecomesDistinctCue() {
    let session = makeSession(
      13,
      status: .failed,
      notes: [
        "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
      ],
      feedback: "done"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    #require(feedback.notices.map(\.kind) == [.promotionFailed])
    #require(feedback.notices[0].title == "Promotion failed")
    #require(feedback.notices[0].severity == .failure)
    #require(feedback.notices[0].actionLabel == "Resolve Promotion")
    #require(feedback.notices[0].metadata == "#13 · compass/dev-123")
    #require(
      feedback.notices[0].detail ==
      "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
    )
    #require(feedback.recentRunCues[13]?.kind == .promotionFailed)
  }

  @Test func testRecentRunCueUsesPostCheckPriorityWithinSession() {
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

    #require(feedback.notices.map(\.kind) == [.developFailed, .failedVerify])
    #require(feedback.recentRunCues[14]?.kind == .failedVerify)
    #require(feedback.recentRunCues[14]?.label == "Retry Develop")
  }

  @Test func testAwaitingApprovalShowsResumeCueWhenImmediatePlanExists() {
    let session = makeSession(
      6,
      status: .awaitingApproval,
      plan: "Implement the approved next slice"
    )

    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    #require(feedback.notices.map(\.kind) == [.resumeDevelop])
    #require(feedback.notices[0].title == "Develop ready")
    #require(feedback.notices[0].actionLabel == "Resume Develop")
    #require(feedback.notices[0].detail == "Implement the approved next slice")
    #require(feedback.recentRunCues[6]?.label == "Resume Develop")
  }

  @Test func testSuccessfulAndCleanStatesStayEmpty() {
    let sessions = [
      makeSession(7, status: .succeeded, feedback: "done"),
      makeSession(8, status: .skipped, notes: ["Plan returned no immediate work."]),
    ]

    let feedback = PlanReliabilityFeedback(
      state: makeState(immediate: nil),
      sessions: sessions
    )

    #require(feedback.isEmpty)
    #require(feedback.recentRunCues == [:])
  }

  @Test func testLaterSuccessRetiresEarlierFailureCue() {
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

    #require(feedback.notices.isEmpty)
    #require(feedback.recentRunCues[4] == nil)
    #require(feedback.recentRunCues[5] == nil)
  }

  @Test func testInFlightSessionAfterFailureKeepsCue() {
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

    #require(feedback.notices.map(\.kind) == [.developBlocked])
    #require(feedback.recentRunCues[4]?.kind == .developBlocked)
  }

  @Test func testBoundsAndNormalizesDetails() {
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
    #require(detail.count <= 38)
    #require(detail == "First line second line with enough...")
  }

  @Test func testNoticeSectionLimitAndRecentRunCuePropagationCanDiffer() {
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
        "Plan tried to clear a non-empty midTerm queue without recording a completion. Refusing to overwrite state.json."
      ]
    )

    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [olderRejectedPlan, newestFailedVerify],
      noticeLimit: 1
    )

    #require(feedback.notices.map(\.sessionNumber) == [10])
    #require(feedback.notices.map(\.kind) == [.failedVerify])
    #require(feedback.recentRunCues[10]?.kind == .failedVerify)
    #require(feedback.recentRunCues[11]?.kind == .rejectedPlan)
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