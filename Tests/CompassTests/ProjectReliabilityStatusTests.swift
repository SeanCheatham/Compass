import Foundation
import Testing

@testable import Compass

struct ProjectReliabilityStatusTests {
  @Test
  func testCleanFeedbackProducesNoCueStatus() throws {
    let sessions = [
      makeSession(1, status: .succeeded, feedback: "done"),
      makeSession(2, status: .skipped, notes: ["Plan returned no immediate work."]),
    ]
    let feedback = PlanReliabilityFeedback(
      state: makeState(immediate: nil),
      sessions: sessions
    )

    let status = ProjectReliabilityStatus(feedback: feedback)

    try #require(status.isEmpty)
    try #require(status.noticeCount == 0)
    try #require(status.countLabel == "0 cues")
    try #require(status.primaryCue == "")
    try #require(status.detail == "")
    try #require(status.primaryKind == nil)

    let guide = ProjectRecoveryGuide(status: status)
    try #require(guide.isEmpty)
  }

  @Test
  func testRejectedPlanTakesPriorityOverNewerVerifyFailure() throws {
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

    try #require(feedback.notices.map(\.kind) == [.failedVerify, .rejectedPlan])
    try #require(!status.isEmpty)
    try #require(status.primaryCue == "Plan rejected")
    try #require(status.severity == .failure)
    try #require(status.actionLabel == "Retry Plan")
    try #require(status.metadata == "#1")
    try #require(status.countLabel == "2 cues")
    try #require(status.primaryKind == .rejectedPlan)
  }

  @Test
  func testDevelopBlockedAndFailedCuesUseDevelopActions() throws {
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

    try #require(blockedStatus.primaryCue == "Develop blocked")
    try #require(blockedStatus.severity == .warning)
    try #require(blockedStatus.actionLabel == "Retry Develop")
    try #require(blockedStatus.detail == "Missing signing credentials.")
    try #require(failedStatus.primaryCue == "Develop failed")
    try #require(failedStatus.severity == .failure)
    try #require(failedStatus.actionLabel == "Retry Develop")
    try #require(failedStatus.detail == "build settings were inconsistent")
  }

  @Test
  func testFailedVerifyStatusCarriesVerifyMetadata() throws {
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

    try #require(status.primaryCue == "Verify failed")
    try #require(status.primaryKind == .failedVerify)
    try #require(status.severity == .failure)
    try #require(status.actionLabel == "Retry Develop")
    try #require(
      status.metadata == "swift test --filter ProjectReliabilityStatusTests · exit 65"
    )
    try #require(status.detail == "Test Suite failed Expected true but got false")
  }

  @Test
  func testRecoveryGuideForRejectedPlanPointsBackToPlanRepair() throws {
    let session = makeSession(
      12,
      status: .failed,
      notes: [
        "Plan returned an immediate handoff that is not executable enough for Develop. Missing Acceptance checks."
      ]
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(guide.title == "Repair the Plan output")
    try #require(
      guide.steps.map(\.title) == [
        "Read the rejection", "Add the missing handoff fields", "Retry Plan",
      ])
    try #require(guide.steps[0].detail.contains("Missing Acceptance checks"))
    try #require(guide.steps[1].detail.contains("Outcome and Acceptance checks"))
    try #require(guide.steps[2].detail.contains("one smaller executable slice"))
  }

  @Test
  func testRecoveryGuideForCoverageRejectedPlanNamesCoverageRepair() throws {
    let session = makeSession(
      15,
      status: .rejectedByPlan,
      notes: [
        """
        Verify command must collect test coverage for Swift Package projects. \
        test verify must declare coverage: guest `swift test --enable-code-coverage`.
        """
      ]
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(guide.title == "Repair the Plan output")
    try #require(guide.steps.map(\.title).contains("Use coverage-ready verify"))
    try #require(guide.steps[1].detail.contains("coverage flag or artifact"))
    try #require(guide.steps[1].detail.contains("build-only"))
  }

  @Test
  func testRecoveryGuideForVerifyBypassNamesPlanRepair() throws {
    let session = makeSession(
      16,
      status: .failed,
      notes: [
        """
        [verify] Verify was skipped because Develop reported the planned command is wrong or out of scope.
        Planned verify command: `swift test --filter RemovedSuite`
        Plan should replace the verify command or rescope Immediate Work before Develop continues.
        """
      ]
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(status.primaryCue == "Plan rejected")
    try #require(status.actionLabel == "Retry Plan")
    try #require(guide.title == "Repair the Plan output")
    try #require(guide.steps.map(\.title).contains("Replace the verify command"))
    try #require(guide.steps[1].detail.contains("matches the current slice"))
  }

  @Test
  func testRecoveryGuideForVerifyFailureUsesCapturedOutput() throws {
    let session = makeSession(
      13,
      status: .failed,
      verifyOutput: VerifyOutput(
        command: "swift test",
        exitCode: 1,
        tail: "Expected passing check, got failing check"
      )
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(guide.title == "Fix the failing check")
    try #require(
      guide.steps.map(\.title) == [
        "Inspect the failing assertion", "Fix the behavior under test", "Retry Develop",
      ])
    try #require(guide.steps[0].detail.contains("test failure"))
    try #require(guide.steps[0].detail.contains("Expected passing check, got failing check"))
    try #require(guide.steps[1].detail.contains("code or expectation"))
    try #require(
      guide.steps[2].detail
        == "Compass will rerun the same test command after Develop patches the failure."
    )
  }

  @Test
  func testRecoveryGuideForVerifyFailureWithoutImmediateNamesPlanRepair() throws {
    let session = makeSession(
      19,
      status: .failed,
      verifyOutput: VerifyOutput(
        command: "swift test",
        exitCode: 1,
        tail: "Expected passing check, got failing check"
      )
    )
    let feedback = PlanReliabilityFeedback(state: makeState(immediate: nil), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(status.actionLabel == "Plan Next Step")
    try #require(guide.steps[2].title == "Plan Next Step")
    try #require(
      guide.steps[2].detail
        == "Ask Plan to create one repair slice from the captured verify output before Develop runs again."
    )
  }

  @Test
  func testRecoveryGuideForBuildVerifyFailureNamesCompilerRepair() throws {
    let session = makeSession(
      17,
      status: .failed,
      verifyOutput: VerifyOutput(
        command: "swift test",
        exitCode: 1,
        tail: "Sources/App.swift:10:5: error: cannot find 'WidgetStore' in scope"
      )
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(guide.steps.map(\.title).contains("Fix the first compiler error"))
    try #require(guide.steps[0].detail.contains("compile or build error"))
    try #require(guide.steps[1].detail.contains("file, symbol, module, or syntax error"))
  }

  @Test
  func testRecoveryGuideForTimedOutVerifyFailureNamesBoundedRepair() throws {
    let session = makeSession(
      18,
      status: .failed,
      verifyOutput: VerifyOutput(
        command: "swift test",
        exitCode: 124,
        tail: "Process timed out after 600 seconds waiting for integration tests"
      )
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])
    let status = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(guide.steps.map(\.title).contains("Unblock the hanging check"))
    try #require(guide.steps[0].detail.contains("timed out"))
    try #require(guide.steps[2].detail.contains("bounded path"))
  }

  @Test
  func testRecoveryGuideBoundsLongDetails() throws {
    let longTail = String(repeating: "verify output line ", count: 30)
    let session = makeSession(
      14,
      status: .failed,
      verifyOutput: VerifyOutput(command: "swift test", exitCode: 1, tail: longTail)
    )
    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [session],
      tailLimit: 1_000
    )
    let status = ProjectReliabilityStatus(feedback: feedback, detailLimit: 1_000)

    let guide = ProjectRecoveryGuide(status: status)

    try #require(guide.steps[0].detail.count <= ProjectRecoveryGuide.detailLimit)
    try #require(guide.steps[0].detail.hasSuffix("..."))
  }

  @Test
  func testDirtyWorktreeStatusCarriesPostCheckMetadata() throws {
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

    try #require(status.primaryCue == "Worktree dirty")
    try #require(status.severity == .warning)
    try #require(status.actionLabel == "Clean Worktree")
    try #require(status.metadata == "#9 · 1 pending change")
    try #require(status.detail.hasPrefix("Uncommitted or untracked changes remain"))
  }

  @Test
  func testPromotionFailureStatusCarriesPromotionMetadata() throws {
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

    try #require(status.primaryCue == "Promotion failed")
    try #require(status.severity == .failure)
    try #require(status.actionLabel == "Resolve Promotion")
    try #require(status.metadata == "#10 · promotion")
    try #require(status.detail == "Develop sandbox produced no commit to promote.")
  }

  @Test
  func testAwaitingApprovalStatusUsesResumeCue() throws {
    let session = makeSession(
      6,
      status: .awaitingApproval,
      plan: "Implement the approved next slice"
    )
    let feedback = PlanReliabilityFeedback(state: makeState(), sessions: [session])

    let status = ProjectReliabilityStatus(feedback: feedback)

    try #require(status.primaryCue == "Develop ready")
    try #require(status.severity == .paused)
    try #require(status.actionLabel == "Resume Develop")
    try #require(status.metadata == "#6")
    try #require(status.detail == "Implement the approved next slice")
    try #require(status.countLabel == "1 cue")
  }

  @Test
  func testMultipleCueStatusReportsCountLabel() throws {
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

    try #require(feedback.notices.map(\.kind) == [.developFailed, .failedVerify])
    try #require(status.noticeCount == 2)
    try #require(status.countLabel == "2 cues")
    try #require(status.primaryCue == "Verify failed")
    try #require(status.metadata == "swift test · exit 1")
  }

  @Test
  func testDetailCanBeBoundedForCompactProjectSurfaces() throws {
    let session = makeSession(
      11,
      status: .failed,
      notes: ["Develop reported it was blocked but did not request verify bypass."],
      feedback:
        "First line\n\nsecond line with enough extra words to force a compact project banner."
    )
    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [session],
      detailLimit: 200
    )

    let status = ProjectReliabilityStatus(feedback: feedback, detailLimit: 46)

    try #require(status.detail.count <= 46)
    try #require(status.detail.hasPrefix("First line second line"))
    try #require(status.detail.hasSuffix("..."))
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
      candidates: "",
      strategicContext: ""
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
