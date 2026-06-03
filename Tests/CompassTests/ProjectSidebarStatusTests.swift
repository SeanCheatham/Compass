import Foundation
import Testing

@testable import Compass

struct ProjectSidebarStatusTests {
  @Test
  func testWorkspaceSidebarRowUsesPrivateWorkspaceCopy() throws {
    let row = SidebarSandboxRow(readiness: .notProvisioned, isSelected: false, action: {})

    try #require(row.statusText == "Not prepared")
    try #require(row.helpText == "Open the private workspace")
    try #require(row.accessibilityText == "Private workspace, Not prepared")
    try #require(!row.helpText.contains("shared macOS VM"))
    try #require(!row.accessibilityText.contains("Sandbox"))
    try #require(!row.statusText.contains("Not installed"))
  }

  @Test
  func testWorkspaceStatusButtonUsesPrivateWorkspaceAccessibilityCopy() throws {
    let button = SidebarSharedVMStatusButton(readiness: .guestPrepping, action: {})

    try #require(button.helpText == "Private workspace status: Finishing workspace setup")
    try #require(button.accessibilityText == "Private workspace status, Finishing workspace setup")
    try #require(!button.helpText.contains("Shared VM"))
    try #require(!button.accessibilityText.contains("headless"))
  }

  @Test
  func testCleanFeedbackProducesImmediatePlanSubtitleWithoutCue() throws {
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

    try #require(!sidebarStatus.hasReliabilityCue)
    try #require(!sidebarStatus.showsProgress)
    try #require(sidebarStatus.title == "")
    try #require(sidebarStatus.subtitle == "Add sidebar attention badges")
    try #require(sidebarStatus.countLabel == "0 cues")
    try #require(sidebarStatus.phaseLabel == "Idle")
    try #require(sidebarStatus.badgeLabel == "")
  }

  @Test
  func testRejectedPlanTakesPriorityForSidebarBadge() throws {
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

    try #require(feedback.notices.map(\.kind) == [.failedVerify, .rejectedPlan])
    try #require(sidebarStatus.hasReliabilityCue)
    try #require(sidebarStatus.title == "Plan rejected")
    try #require(sidebarStatus.badgeLabel == "Plan rejected")
    try #require(sidebarStatus.actionLabel == "Retry Plan")
    try #require(sidebarStatus.metadata == "#2")
    try #require(sidebarStatus.countLabel == "2 cues")
    try #require(sidebarStatus.helpText.contains("Retry Plan"))
    try #require(sidebarStatus.helpText.contains("#2"))
    try #require(sidebarStatus.accessibilityLabel.contains("2 cues"))
  }

  @Test
  func testSidebarSubtitlesUsePrimaryReliabilityDetail() throws {
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

    try #require(blockedStatus.title == "Develop blocked")
    try #require(blockedStatus.subtitle == "Missing signing credentials.")
    try #require(failedStatus.title == "Develop failed")
    try #require(failedStatus.subtitle == "build settings were inconsistent")
    try #require(failedVerifyStatus.title == "Verify failed")
    try #require(failedVerifyStatus.subtitle == "Test Suite failed Expected true but got false")
    try #require(resumeStatus.title == "Develop ready")
    try #require(resumeStatus.subtitle == "Implement the approved next slice")
    try #require(dirtyStatus.title == "Worktree dirty")
    try #require(dirtyStatus.subtitle.hasPrefix("Uncommitted or untracked changes remain"))
    try #require(dirtyStatus.actionLabel == "Clean Worktree")
    try #require(promotionStatus.title == "Promotion failed")
    try #require(promotionStatus.actionLabel == "Resolve Promotion")
    try #require(promotionStatus.metadata == "#12 · compass/dev-123")
  }

  @Test
  func testMultipleCueSidebarStatusReportsCountLabel() throws {
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

    try #require(sidebarStatus.cueCount == 2)
    try #require(sidebarStatus.countLabel == "2 cues")
    try #require(sidebarStatus.title == "Verify failed")
    try #require(sidebarStatus.helpText.contains("2 cues"))
    try #require(sidebarStatus.accessibilityLabel.contains("2 cues"))
  }

  @Test
  func testSidebarSubtitleIsBoundedForCompactRows() throws {
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

    try #require(sidebarStatus.subtitle.count <= 45)
    try #require(sidebarStatus.subtitle.hasPrefix("First line second line"))
    try #require(sidebarStatus.subtitle.hasSuffix("..."))
  }

  @Test
  func testRunningAndPausedPhaseCanCoexistWithReliabilityCue() throws {
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

    try #require(pausedWhileRunning.hasReliabilityCue)
    try #require(pausedWhileRunning.showsProgress)
    try #require(pausedWhileRunning.phaseLabel == "Pausing after iteration")
    try #require(pausedWhileRunning.title == "Develop blocked")
    try #require(autoPlaying.hasReliabilityCue)
    try #require(autoPlaying.showsProgress)
    try #require(autoPlaying.phaseLabel == "Auto - Verifying")
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
      candidates: "",
      strategicContext: ""
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
