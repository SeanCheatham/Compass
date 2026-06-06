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
    try #require(guide.decisionBadge.label == "Plan first")
    try #require(guide.decisionBadge.tone == .info)
    try #require(guide.decisionBadge.detail.contains("one executable slice"))
  }

  @Test
  func testNoImmediateWorkPreviewExplainsFullLoopPath() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(
      guide.previewSteps.map(\.title) == [
        "Plan one slice", "Develop in the private workspace", "Verify and review",
      ])
    try #require(
      guide.previewSteps[0].detail
        == "Plan will choose one executable next slice from the repository and strategic context.")
    try #require(
      guide.previewSteps[1].detail
        == "Develop edits the selected slice inside your private workspace.")
    try #require(!guide.previewSteps[1].detail.contains("host checkout"))
    try #require(guide.previewSteps[2].detail.contains("saved check"))
  }

  @Test
  func testEmptyVisionSurfacesBeforeBlankPlanRun() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      vision: ""
    )

    try #require(guide.primaryKind == .loop)
    try #require(
      guide.primaryHelp
        == "Capture Project Vision first, or run Plan if you want Compass to infer a starting slice."
    )
    try #require(guide.readiness.title == "Vision missing")
    try #require(
      guide.readiness.detail
        == "Capture Project Vision before Plan so the first slice has audience, problem, success, and guardrails."
    )
    try #require(guide.decisionBadge.label == "Vision first")
    try #require(guide.decisionBadge.tone == .warning)
    try #require(guide.options[0].detail.contains("Capture Project Vision first"))
    try #require(guide.options[1].detail.contains("ask Plan to infer one executable"))
    try #require(guide.previewSteps[0].detail.contains("Project Vision is empty"))
    try #require(guide.narrationIdentifier.contains("Vision first"))
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
        == "1 draft is ready for Plan; 1 draft needs detail. Plan will turn the queue into one executable slice.")
    try #require(
      guide.options[0].detail
        == "1 draft is ready for Plan; 1 draft needs detail. Drafts shows missing signals before Develop starts.")
    try #require(
      guide.options[1].detail
        == "1 draft is ready for Plan; 1 draft needs detail. Ask Plan to use ready drafts and keep unclear drafts queued.")
    try #require(!guide.options[2].isEnabled)
    try #require(guide.decisionBadge.label == "Draft details")
    try #require(guide.decisionBadge.tone == .warning)
    try #require(guide.decisionBadge.detail.contains("Missing across queue"))
  }

  @Test
  func testCappedQueuedDraftsKeepRawQueueScopeInRunControls() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      drafts: """
        - Make setup faster because users get stuck; success looks like tests pass.
        - Show recovery copy because users get locked out; done when recovery copy appears.
        - Explain failed verifies because owners get confused; success shows the first error.
        - Add draft polish because planning starts rough; success shows clearer queue copy.
        - Improve sandbox setup because onboarding is hard; done when the readiness panel shows progress.
        - Surface provider failures because API keys expire; success shows a model connection repair.
        - Improve onboarding copy
        """
    )

    try #require(guide.readiness.title == "Drafts need detail")
    try #require(guide.readiness.detail.contains("7 queued drafts"))
    try #require(guide.readiness.detail.contains("Showing first 6"))
    try #require(guide.readiness.detail.contains("1 more draft remains in the raw draft list"))
    try #require(
      guide.primaryHelp
        == "6 drafts are ready for Plan; 1 draft needs detail. Drafts is checking the first 6; 1 more draft remains in the raw queue. Plan will turn the queue into one executable slice."
    )
    try #require(
      guide.options[0].detail
        == "6 drafts are ready for Plan; 1 draft needs detail. Drafts shows missing signals before Develop starts. Drafts is checking the first 6; 1 more draft remains in the raw queue."
    )
    try #require(
      guide.options[1].detail
        == "6 drafts are ready for Plan; 1 draft needs detail. Ask Plan to use ready drafts and keep unclear drafts queued. Drafts is checking the first 6; 1 more draft remains in the raw queue."
    )
    try #require(
      guide.previewSteps[0].detail
        == "6 drafts are ready for Plan; 1 draft needs detail. Plan will create one executable handoff. Drafts is checking the first 6; 1 more draft remains in the raw queue."
    )
    try #require(guide.narrationIdentifier.contains("1 more draft remains"))
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
        == "2 drafts are ready for Plan. Plan will choose one executable slice, then Develop it.")
    try #require(
      guide.options[1].detail
        == "2 drafts are ready for Plan. Ask Plan to create one executable handoff.")
    try #require(guide.decisionBadge.label == "Draft queue")
    try #require(guide.decisionBadge.tone == .info)
    try #require(guide.decisionBadge.detail == "2 drafts are ready for Plan.")
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
    try #require(guide.decisionBadge.label == "Ready")
    try #require(guide.decisionBadge.tone == .ready)
    try #require(guide.decisionBadge.detail.contains("verify command"))
  }

  @Test
  func testImmediateWorkPreviewNamesCurrentSliceAndVerify() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(
        immediate: PlanNext(
          plan: """
            ## Outcome
            Make run controls explain the next tournament action.

            ## Acceptance checks
            - The run menu previews the next action before starting.
            """,
          verify: "swift test --filter ProjectRunControlGuideTests",
          requiresHostXcode: true
        )
      ),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(
      guide.previewSteps.map(\.title) == [
        "Develop current slice", "Run verification", "Review and continue",
      ])
    try #require(
      guide.previewSteps[0].detail == "Make run controls explain the next tournament action.")
    try #require(
      guide.previewSteps[1].detail
        == "Host Xcode runs: swift test --filter ProjectRunControlGuideTests")
    try #require(guide.previewSteps[1].systemImage == "macwindow")
  }

  @Test
  func testRunControlClipboardPayloadPackagesReadyRunModesForReuse() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    let payload = ProjectRunControlClipboardPayload(guide: guide)

    try #require(payload.text.contains("Compass Run Controls Handoff"))
    try #require(payload.text.contains("Do not invent repository state"))
    try #require(payload.text.contains("Primary: Run Loop (loop, enabled)"))
    try #require(payload.text.contains("Readiness: Ready for Develop"))
    try #require(payload.text.contains("Run signal: Ready -"))
    try #require(payload.text.contains("[enabled] Run Develop Only (develop-only)"))
    try #require(payload.text.contains("Next run preview:"))
    try #require(payload.text.contains("Run verification: Compass runs"))
    try #require(payload.text.count <= ProjectRunControlClipboardPayload.textLimit)
    try #require(!payload.isEmpty)
  }

  @Test
  func testRunControlClipboardPayloadNamesDisabledDevelopRepair() throws {
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

    let payload = ProjectRunControlClipboardPayload(guide: guide)

    try #require(payload.text.contains("Primary: Run Plan Only (plan-only, enabled)"))
    try #require(payload.text.contains("Readiness: Plan repair needed"))
    try #require(payload.text.contains("[disabled] Run Develop Only (develop-only)"))
    try #require(payload.text.contains("Acceptance checks before Develop"))
    try #require(payload.text.contains("Disabled options stay disabled"))
  }

  @Test
  func testRunControlClipboardPayloadPreservesRunningLockout() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: true,
      isAutoPlaying: false,
      isPaused: false
    )

    let payload = ProjectRunControlClipboardPayload(guide: guide)

    try #require(payload.text.contains("Primary: Run Loop (loop, disabled)"))
    try #require(payload.text.contains("Readiness: Run in progress"))
    try #require(payload.text.contains("[disabled] Run Plan Only (plan-only)"))
    try #require(payload.text.contains("Finish the current run"))
  }

  @Test
  func testCoverageMissingVerifyMakesPlanPrimaryAndDisablesDevelop() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(
        immediate: PlanNext(
          plan: """
            ## Outcome
            Add Rust coverage for parser failures.

            ## Acceptance checks
            - Rust tests exercise parser failures.
            """,
          verify: "cargo test"
        )
      ),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      languageProfile: profile(.rust),
      forgeProfile: .rustCargo
    )

    try #require(
      guide.primaryHelp
        == "Repair Immediate Work before Develop: add Coverage-ready verify. Add coverage to the verify command for Rust (Cargo)."
    )
    try #require(guide.readiness.title == "Plan repair needed")
    try #require(
      guide.readiness.detail
        == "Immediate Work needs Coverage-ready verify before Develop. Add coverage to the verify command for Rust (Cargo)."
    )
    try #require(guide.primaryKind == .planOnly)
    try #require(!guide.options[2].isEnabled)
    try #require(
      guide.options[2].detail
        == "Disabled until Immediate Work has Coverage-ready verify. Add coverage to the verify command for Rust (Cargo)."
    )
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
      guide.primaryHelp
        == "Repair Immediate Work before Develop: add Acceptance checks. List observable finish-line checks."
    )
    try #require(guide.readiness.title == "Plan repair needed")
    try #require(
      guide.readiness.detail
        == "Immediate Work needs Acceptance checks before Develop. List observable finish-line checks."
    )
    try #require(guide.primaryKind == .planOnly)
    try #require(guide.primaryOption.title == "Run Plan Only")
    try #require(
      guide.primaryOption.detail
        == "Ask Plan to add Acceptance checks before Develop starts. List observable finish-line checks."
    )
    try #require(guide.options[0].detail.contains("repair Immediate Work"))
    try #require(!guide.options[2].isEnabled)
    try #require(
      guide.options[2].detail
        == "Disabled until Immediate Work has Acceptance checks. List observable finish-line checks."
    )
    try #require(guide.decisionBadge.label == "Repair first")
    try #require(guide.decisionBadge.tone == .warning)
    try #require(guide.decisionBadge.detail.contains("Acceptance checks"))
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
          verify: "exit 0"
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
      guide.primaryHelp
        == "Repair Immediate Work before Develop: add Verify command. Choose a real command Compass can run after Develop."
    )
    try #require(
      guide.readiness.detail
        == "Immediate Work needs Verify command before Develop. Choose a real command Compass can run after Develop."
    )
    try #require(guide.primaryKind == .planOnly)
    try #require(!guide.options[2].isEnabled)
    try #require(
      guide.options[2].detail
        == "Disabled until Immediate Work has Verify command. Choose a real command Compass can run after Develop."
    )
  }

  @Test
  func testFailureMaskingVerifyExplainsTheConcreteRepair() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(
        immediate: PlanNext(
          plan: """
            ## Outcome
            Keep failed verification visible.

            ## Acceptance checks
            - Failed tests still block the Develop handoff.
            """,
          verify: "swift test || true"
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
      guide.primaryHelp
        == "Repair Immediate Work before Develop: add Verify command. Remove fallback no-op clauses so failed checks still fail."
    )
    try #require(
      guide.readiness.detail
        == "Immediate Work needs Verify command before Develop. Remove fallback no-op clauses so failed checks still fail."
    )
    try #require(guide.primaryKind == .planOnly)
    try #require(!guide.options[2].isEnabled)
    try #require(
      guide.options[2].detail
        == "Disabled until Immediate Work has Verify command. Remove fallback no-op clauses so failed checks still fail."
    )
  }

  @Test
  func testRepairPreviewNamesMissingHandoffPiece() throws {
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

    try #require(guide.previewSteps.map(\.title) == ["Plan one slice", "Stop for review"])
    try #require(
      guide.previewSteps[0].detail
        == "Plan will add Acceptance checks so Develop has a clear finish line. List observable finish-line checks."
    )
    try #require(guide.previewSteps[1].detail.contains("stops before Develop"))
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

    try #require(guide.primaryHelp == "Choose how to resume the paused Product Tournament.")
    try #require(guide.primaryKind == .loop)
    try #require(guide.options[0].title == "Resume Loop")
    try #require(guide.options[0].detail == "Resume the Product Tournament from its paused gate.")
    try #require(guide.decisionBadge.label == "Paused")
    try #require(guide.decisionBadge.tone == .paused)
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
    try #require(guide.decisionBadge.label == "Verify failed")
    try #require(guide.decisionBadge.tone == .failure)
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
    try #require(running.decisionBadge.label == "Running")
    try #require(running.decisionBadge.tone == .info)
    try #require(
      missingRepository.primaryHelp == "Add a Git repository before running the Product Tournament.")
    try #require(missingRepository.options.allSatisfy { !$0.isEnabled })
    try #require(missingRepository.decisionBadge.label == "Needs repo")
    try #require(missingRepository.decisionBadge.tone == .warning)
  }

  @Test
  func testNarrationIdentifierTracksRunControlFacts() throws {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try #require(guide.allowsNarration)
    try #require(guide.narrationIdentifier.contains("primary:loop"))
    try #require(guide.narrationIdentifier.contains("Ready for Develop"))
    try #require(guide.narrationIdentifier.contains("signal:Ready"))
    try #require(guide.narrationIdentifier.contains("Run Develop Only"))
  }

  @Test
  func testRunningGuideDoesNotNarrate() async {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: true,
      isAutoPlaying: false,
      isPaused: false
    )

    #expect(!guide.allowsNarration)
    await withMockFoundationModels(response: "Compass is already running.") {
      let narration = await ProjectRunControlGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func testNarratorUsesFoundationModelsAsOptionalRunControlPolish() async throws {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    try await withMockFoundationModels(
      response: "Compass can run the full loop now, or you can choose Plan or Develop first."
    ) {
      let generatedNarration = await ProjectRunControlGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "Compass can run the full loop now, or you can choose Plan or Develop first.")
    }
  }

  @Test
  func testNarratorReturnsNilWhenFoundationModelsAreUnavailable() async {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    await withMockFoundationModels(available: false, response: "Should not be used") {
      let narration = await ProjectRunControlGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func testNarratorRejectsStructuredBulletedOrLinkedOutput() async {
    let guide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await ProjectRunControlGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Run a hidden setup step") {
      let narration = await ProjectRunControlGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await ProjectRunControlGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
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
      candidates: "",
      strategicContext: ""
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
