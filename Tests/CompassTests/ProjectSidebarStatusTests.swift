import Foundation
import Testing

@testable import Compass

struct ProjectSidebarStatusTests {
  @Test
  func testCleanFeedbackProducesImmediatePlanSubtitleWithoutCue() {
    let feedback = PlanReliabilityFeedback(
      state: makeState(immediate: nil),
      sessions: [
        makeSession(1, status: .succeeded, feedback: "done"),
        makeSession(2, status: .skipped, notes: ["Plan returned no immediate work."]),
      ]
    )

    let sidebarStatus = makeSidebarStatus(
      reliabilityStatus: ProjectReliabilityStatus(feedback: feedback),
      immediateTitle: "Add sidebar attention badges",
      phase: .idle
    )

    #require(!sidebarStatus.hasReliabilityCue)
    #require(!sidebarStatus.showsProgress)
    #require(sidebarStatus.title == "")
    #require(sidebarStatus.subtitle == "Add sidebar attention badges")
    #require(sidebarStatus.countLabel == "0 cues")
    #require(sidebarStatus.phaseLabel == "Idle")
    #require(sidebarStatus.badgeLabel == "")
  }

  @Test
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

    #require(feedback.notices.map(\.kind) == [.failedVerify, .rejectedPlan])
    #require(sidebarStatus.hasReliabilityCue)
    #require(sidebarStatus.title == "Plan rejected")
    #require(sidebarStatus.badgeLabel == "Plan rejected")
    #require(sidebarStatus.actionLabel == "Retry Plan")
    #require(sidebarStatus.metadata == "#2")
    #require(sidebarStatus.countLabel == "2 cues")
    #require(sidebarStatus.helpText.contains("Retry Plan"))
    #require(sidebarStatus.helpText.contains("#2"))
    #require(sidebarStatus.accessibilityLabel.contains("2 cues"))
  }

  @Test
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
    let dirtyStatus = makeSidebarStatus(
      reliabilityStatus: ProjectReliabilityStatus(
        feedback: PlanReliabilityFeedback(
          state: makeState(),
          sessions: [
            makeSession(
              11,
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
          ]
        )
      )
    )
    let promotionStatus = makeSidebarStatus(
      reliabilityStatus: ProjectReliabilityStatus(
        feedback: PlanReliabilityFeedback(
          state: makeState(),
          sessions: [
            makeSession(
              12,
              status: .failed,
              notes: [
                "Failed to promote Develop sandbox branch compass/dev-123: fatal: Not possible to fast-forward, aborting."
              ],
              feedback: "done"
            )
          ]
        )
      )
    )

    #require(blockedStatus.title == "Develop blocked")
    #require(blockedStatus.subtitle == "Missing signing credentials.")
    #require(failedStatus.title == "Develop failed")
    #require(failedStatus.subtitle == "build settings were inconsistent")
    #require(failedVerifyStatus.title == "Verify failed")
    #require(failedVerifyStatus.subtitle == "Test Suite failed Expected true but got false")
    #require(resumeStatus.title == "Develop ready")
    #require(resumeStatus.subtitle == "Implement the approved next slice")
    #require(dirtyStatus.title == "Worktree dirty")
    #require(dirtyStatus.subtitle.hasPrefix("Uncommitted or untracked changes remain"))
    #require(dirtyStatus.actionLabel == "Clean Worktree")
    #require(promotionStatus.title == "Promotion failed")
    #require(promotionStatus.actionLabel == "Resolve Promotion")
    #require(promotionStatus.metadata == "#12 · compass/dev-123")
  }

  @Test
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

    #require(sidebarStatus.cueCount == 2)
    #require(sidebarStatus.countLabel == "2 cues")
    #require(sidebarStatus.title == "Verify failed")
    #require(sidebarStatus.helpText.contains("2 cues"))
    #require(sidebarStatus.accessibilityLabel.contains("2 cues"))
  }

  @Test
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

    #require(sidebarStatus.subtitle.count <= 45)
    #require(sidebarStatus.subtitle.hasPrefix("First line second line"))
    #require(sidebarStatus.subtitle.hasSuffix("..."))
  }

  @Test
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

    #require(pausedWhileRunning.hasReliabilityCue)
    #require(pausedWhileRunning.showsProgress)
    #require(pausedWhileRunning.phaseLabel == "Pausing after iteration")
    #require(pausedWhileRunning.title == "Develop blocked")
    #require(autoPlaying.hasReliabilityCue)
    #require(autoPlaying.showsProgress)
    #require(autoPlaying.phaseLabel == "Auto - Verifying")
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
