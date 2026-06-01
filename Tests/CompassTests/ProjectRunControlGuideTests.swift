import Foundation
import Testing

@testable import Compass

struct ProjectRunControlGuideTests {
  @Test
  func testNoImmediateWorkSteersTowardPlanFirst() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(
      guide.primaryHelp == "Run Plan first, or let the full loop choose and build the next slice.")
    try #require(guide.primaryKind == .loop)
    try #require(guide.primaryOption.title == "Run Loop")
    try #require(guide.options.map(\.kind) == [.loop, .planOnly, .developOnly])
    try #require(guide.alternativeOptions.map(\.kind) == [.planOnly, .developOnly])
    try #require(guide.options[0].isEnabled)
    try #require(guide.options[1].isEnabled)
    try #require(!guide.options[2].isEnabled)
    try #require(guide.options[2].detail == "Disabled until Plan selects Immediate Work.")
  }

  @Test
  func testImmediateWorkEnablesDevelopOnly() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(
      guide.primaryHelp
        == "Choose whether to run the full loop, re-plan, or develop the current slice.")
    try #require(guide.primaryKind == .loop)
    try #require(guide.primaryOption.kind == .loop)
    try #require(guide.options.allSatisfy { $0.isEnabled })
    try #require(guide.options[0].title == "Run Loop")
    try #require(guide.options[1].title == "Run Plan Only")
    try #require(guide.options[2].title == "Run Develop Only")
    try #require(guide.options[2].detail.contains("Immediate Work"))
  }

  @Test
  func testPausedStateUsesResumeCopy() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: true
    )

    try #require(guide.primaryHelp == "Choose how to resume the paused factory.")
    try #require(guide.primaryKind == .loop)
    try #require(guide.options[0].title == "Resume Loop")
    try #require(guide.options[0].detail == "Resume the factory from its paused gate.")
  }

  @Test
  func testReliabilityCueFeedsPrimaryLoopCopy() throws {
    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [
        makeSession(
          status: .failed,
          verifyOutput: VerifyOutput(
            command: "swift test",
            exitCode: 1,
            tail: "Expected true but got false"
          )
        )
      ]
    )
    let reliabilityStatus = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: reliabilityStatus,
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(guide.primaryHelp == "Verify failed: Retry Develop")
    try #require(guide.primaryKind == .developOnly)
    try #require(guide.primaryOption.title == "Retry Develop")
    try #require(
      guide.primaryOption.detail
        == "Retry the current Immediate Work with the captured issue still visible.")
    try #require(guide.options[0].detail == "Verify failed: Retry Develop.")
  }

  @Test
  func testRejectedPlanMakesPlanThePrimaryRepairAction() throws {
    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [
        makeSession(
          status: .failed,
          notes: [
            "Plan returned an immediate handoff that is not executable enough for Develop. Missing Acceptance checks."
          ]
        )
      ]
    )
    let reliabilityStatus = ProjectReliabilityStatus(feedback: feedback)

    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: reliabilityStatus,
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(guide.primaryHelp == "Plan rejected: Retry Plan")
    try #require(guide.primaryKind == ProjectRunControlGuide.Kind.planOnly)
    try #require(guide.primaryOption.title == "Retry Plan")
    try #require(
      guide.primaryOption.detail == "Ask Plan to repair the rejected handoff before Develop starts."
    )
  }

  @Test
  func testRunningAndMissingRepositoryDisableEveryAction() throws {
    let running = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: true,
      isAutoPlaying: false,
      isPaused: false
    )
    let missingRepository = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: false,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(running.primaryHelp == "Compass is already running.")
    try #require(running.options.allSatisfy { !$0.isEnabled })
    try #require(
      missingRepository.primaryHelp == "Add a Git repository before running the factory.")
    try #require(missingRepository.options.allSatisfy { !$0.isEnabled })
  }

  private func emptyReliabilityStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(state: makeState(), sessions: [])
    )
  }

  private func makeState(
    immediate: PlanNext? = PlanNext(
      plan: "## Outcome\nImprove run controls.\n\n## Acceptance checks\n- Focused tests pass.",
      verify: "swift test --filter ProjectRunControlGuideTests"
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
    status: SessionStatus,
    notes: [String] = [],
    verifyOutput: VerifyOutput? = nil
  ) -> SessionRecord {
    SessionRecord(
      session: 1,
      startedAt: 1_000,
      endedAt: 1_500,
      plan: "Plan",
      verify: "swift test",
      beforeSha: nil,
      afterSha: nil,
      commits: [],
      status: status,
      notes: notes,
      verifyOutput: verifyOutput,
      feedback: nil
    )
  }
}
