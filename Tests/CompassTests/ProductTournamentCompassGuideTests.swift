import Foundation
import Testing

@testable import Compass

struct ProductTournamentCompassGuideTests {
  @Test
  func testPlanFirstBriefSummarizesTheTournamentState() throws {
    let runGuide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    let guide = ProductTournamentCompassGuide(runGuide: runGuide)

    try #require(guide.title == "Plan needed")
    try #require(guide.controlLabel == "Plan first")
    try #require(guide.tone == .info)
    try #require(guide.primaryActionTitle == "Run Loop")
    try #require(guide.primaryActionIsEnabled)
    try #require(
      guide.previewSteps.map(\.title) == [
        "Plan one slice", "Develop in the private workspace", "Verify and review",
      ])
    try #require(guide.handoffText.contains("Compass Product Tournament Brief"))
    try #require(guide.handoffText.contains("Current state: Plan needed"))
    try #require(guide.handoffText.contains("Recommended action: Run Loop (enabled)"))
  }

  @Test
  func testReadyBriefKeepsDevelopAndVerifyVisible() throws {
    let runGuide = ProjectRunControlGuide(
      state: makeState(
        immediate: PlanNext(
          plan: """
            ## Outcome
            Make the run controls explain the next tournament action.

            ## Acceptance checks
            - The run menu previews the next action before starting.
            """,
          verify: "swift test --filter ProductTournamentCompassGuideTests",
          requiresHostXcode: true
        )
      ),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    let guide = ProductTournamentCompassGuide(runGuide: runGuide)

    try #require(guide.title == "Ready for Develop")
    try #require(guide.controlLabel == "Ready")
    try #require(guide.tone == .ready)
    try #require(
      guide.previewSteps[0].detail == "Make the run controls explain the next tournament action.")
    try #require(
      guide.previewSteps[1].detail
        == "Host Xcode runs: swift test --filter ProductTournamentCompassGuideTests"
    )
    try #require(guide.handoffText.contains("Run signal: Ready -"))
    try #require(guide.handoffText.count <= ProductTournamentCompassGuide.handoffLimit)
  }

  @Test
  func testBriefIncludesRustProductTournamentHealthWhenProvided() throws {
    let runGuide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )
    let rustHealth = RustProductTournamentHealth(
      inputs: .init(
        engineBinaryURL: nil,
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )

    let guide = ProductTournamentCompassGuide(runGuide: runGuide, rustHealth: rustHealth)

    try #require(guide.rustHealth?.title == "Rust Product Tournament Needs Repair")
    try #require(guide.rustHealth?.nextAction == "./scripts/build-compass-engine.sh")
    try #require(guide.handoffText.contains("Rust Product Tournament health: Rust Product Tournament Needs Repair"))
  }

  @Test
  func testWarningBriefUsesSpecificSignalLabel() throws {
    let runGuide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      vision: ""
    )

    let guide = ProductTournamentCompassGuide(runGuide: runGuide)

    try #require(guide.title == "Vision missing")
    try #require(guide.controlLabel == "Vision first")
    try #require(guide.tone == .warning)
    try #require(guide.primaryActionTitle == "Run Loop")
    try #require(guide.handoffText.contains("Run signal: Vision first -"))
  }

  @Test
  func testReliabilityFailureBriefPointsAtRepairAction() throws {
    let feedback = PlanReliabilityFeedback(
      state: makeState(),
      sessions: [
        makeSession(
          status: .failed,
          verifyOutput: VerifyOutput(
            command: "swift test",
            exitCode: 1,
            tail: "ProductTournamentCompassGuideTests failed"
          )
        )
      ]
    )
    let runGuide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: ProjectReliabilityStatus(feedback: feedback),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    let guide = ProductTournamentCompassGuide(runGuide: runGuide)

    try #require(guide.title == "Verify failed")
    try #require(guide.controlLabel == "Needs repair")
    try #require(guide.tone == .failure)
    try #require(guide.primaryActionTitle == "Retry Develop")
    try #require(guide.signalDetail.contains("Retry Develop"))
    try #require(guide.previewSteps[0].title == "Retry Develop")
    try #require(guide.handoffText.contains("Run signal: Verify failed"))
  }

  private func emptyReliabilityStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(state: makeState(), sessions: [])
    )
  }

  private func makeState(
    immediate: PlanNext? = PlanNext(
      plan: "## Outcome\nImprove run controls.\n\n## Acceptance checks\n- Focused tests pass.",
      verify: "swift test --filter ProductTournamentCompassGuideTests"
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
    status: SessionStatus,
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
      notes: [],
      verifyOutput: verifyOutput,
      feedback: nil
    )
  }
}
