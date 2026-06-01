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
  func testQueuedDraftsSurfaceInRunReadinessBeforePlanning() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      drafts: """
        - Make setup faster because users get stuck; success looks like tests pass.
        - Improve onboarding copy
        """
    )

    try #require(guide.readiness.title == "Drafts need detail")
    try #require(
      guide.readiness.detail
        == "2 queued drafts. 1 of 2 ready. Missing across queue: Why, Success signal.")
    try #require(
      guide.primaryHelp
        == "1 of 2 ready in Drafts; Plan will turn the queue into one executable slice.")
    try #require(
      guide.options[0].detail
        == "Plan can use 2 queued drafts, but Drafts shows missing signals before Develop starts.")
    try #require(
      guide.options[1].detail
        == "Ask Plan to use the queue, with Drafts showing which signals still need detail.")
    try #require(!guide.options[2].isEnabled)
  }

  @Test
  func testReadyQueuedDraftsTellRunControlsPlanCanUseQueue() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      drafts: """
        - Make setup faster because users get stuck; success looks like tests pass.
        - Show clearer progress because customers wait; done when the progress banner appears.
        """
    )

    try #require(guide.readiness.title == "Drafts ready for Plan")
    try #require(guide.readiness.detail.contains("Every queued draft"))
    try #require(
      guide.options[0].detail
        == "Plan will use 2 queued drafts to choose one executable slice, then Develop it.")
    try #require(
      guide.options[1].detail
        == "Ask Plan to turn 2 queued drafts into one executable handoff.")
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
    try #require(guide.readiness.title == "Ready for Develop")
    try #require(guide.readiness.detail.contains("runnable verify command"))
    try #require(guide.primaryKind == .loop)
    try #require(guide.primaryOption.kind == .loop)
    try #require(guide.options.allSatisfy { $0.isEnabled })
    try #require(guide.options[0].title == "Run Loop")
    try #require(guide.options[1].title == "Run Plan Only")
    try #require(guide.options[2].title == "Run Develop Only")
    try #require(guide.options[2].detail.contains("Immediate Work"))
  }

  @Test
  func testWeakImmediateWorkMakesPlanPrimaryAndDisablesDevelop() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(
        immediate: PlanNext(
          plan: "Make the Plan tab easier to read.",
          verify: "swift test --filter ProjectRunControlGuideTests"
        )
      ),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      languageProfile: profile(.swift)
    )

    try #require(
      guide.primaryHelp == "Repair Immediate Work before Develop: add Acceptance checks.")
    try #require(guide.readiness.title == "Plan repair needed")
    try #require(guide.readiness.detail == "Immediate Work needs Acceptance checks before Develop.")
    try #require(guide.primaryKind == .planOnly)
    try #require(guide.primaryOption.title == "Run Plan Only")
    try #require(
      guide.primaryOption.detail == "Ask Plan to add Acceptance checks before Develop starts.")
    try #require(guide.options[0].detail.contains("repair Immediate Work"))
    try #require(!guide.options[2].isEnabled)
    try #require(
      guide.options[2].detail == "Disabled until Immediate Work has Acceptance checks.")
  }

  @Test
  func testPlaceholderVerifyMakesPlanPrimaryAndDisablesDevelop() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(
        immediate: PlanNext(
          plan: """
            ## Outcome
            Make the run controls safer.

            ## Acceptance checks
            - Develop is disabled until the verify command is real.
            """,
          verify: "true"
        )
      ),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      languageProfile: profile(.swift)
    )

    try #require(guide.primaryHelp == "Repair Immediate Work before Develop: add Verify command.")
    try #require(guide.readiness.detail == "Immediate Work needs Verify command before Develop.")
    try #require(guide.primaryKind == .planOnly)
    try #require(!guide.options[2].isEnabled)
    try #require(guide.options[2].detail == "Disabled until Immediate Work has Verify command.")
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
