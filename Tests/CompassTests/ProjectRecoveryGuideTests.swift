import Testing

@testable import Compass

struct ProjectRecoveryGuideTests {
  @Test
  func emptyRecoveryGuideDoesNotNarrate() async {
    let guide = ProjectRecoveryGuide(status: emptyStatus())

    #expect(guide.isEmpty)
    #expect(!guide.allowsNarration)
    #expect(guide.narrationIdentifier.isEmpty)

    await withMockFoundationModels(response: "Should not be used") {
      let narration = await ProjectRecoveryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func narrationIdentifierTracksRecoverySteps() throws {
    let guide = ProjectRecoveryGuide(status: rejectedPlanStatus())

    try #require(guide.allowsNarration)
    try #require(guide.narrationIdentifier.contains("Repair the Plan output"))
    try #require(guide.narrationIdentifier.contains("Read the rejection"))
    try #require(guide.narrationIdentifier.contains("Use coverage-ready verify"))
  }

  @Test
  func vagueAcceptanceCheckRecoveryNamesTheRepair() throws {
    let guide = ProjectRecoveryGuide(
      status: rejectedPlanStatus(
        note:
          "Plan returned an immediate handoff that is not executable enough for Develop. Acceptance checks are too vague (`The planned behavior is implemented.`)."
      )
    )

    try #require(!guide.isEmpty)
    try #require(guide.steps[1].title == "Replace vague acceptance checks")
    try #require(guide.steps[1].detail.contains("specific behavior"))
    try #require(guide.steps[1].detail.contains("test-proven signal"))
    try #require(guide.narrationIdentifier.contains("Replace vague acceptance checks"))
  }

  @Test
  func failureMaskingVerifyRecoveryNamesTheRepair() throws {
    let guide = ProjectRecoveryGuide(
      status: rejectedPlanStatus(
        note:
          "Plan returned failure-masking verify command `swift test || true`. Verify commands must fail when the check fails."
      )
    )

    try #require(!guide.isEmpty)
    try #require(guide.steps[1].title == "Replace the verify command")
    try #require(guide.steps[1].detail.contains("fallback clauses"))
    try #require(guide.steps[1].detail.contains("|| true"))
    try #require(guide.narrationIdentifier.contains("Replace the verify command"))
  }

  @Test
  func developMissingSubmitResultRecoveryNamesHandoffRepair() throws {
    let guide = ProjectRecoveryGuide(
      status: developFailedStatus(
        note: "Develop attempt 1 ended without submit_result: Agent exceeded max iterations (10)."
      )
    )

    try #require(!guide.isEmpty)
    try #require(guide.title == "Finish the Develop handoff")
    try #require(guide.steps[0].title == "Inspect the missing result")
    try #require(guide.steps[0].detail.contains("`submit_result` handoff"))
    try #require(guide.steps[1].title == "Ask for one smaller finish")
    try #require(guide.steps[1].detail.contains("one narrow change"))
    try #require(guide.steps[2].detail.contains("result handoff requirement"))
  }

  @Test
  func developMalformedToolCallRecoveryNamesToolShapeRepair() throws {
    let guide = ProjectRecoveryGuide(
      status: developFailedStatus(
        note: "Tool call edit_file had undecodable args: Missing required field `path`."
      )
    )

    try #require(!guide.isEmpty)
    try #require(guide.title == "Repair the tool request")
    try #require(guide.steps[0].title == "Inspect the malformed tool call")
    try #require(guide.steps[1].title == "Use simpler tool arguments")
    try #require(guide.steps[1].detail.contains("required fields"))
    try #require(guide.steps[1].detail.contains("smaller JSON"))
  }

  @Test
  func developProviderFailureRecoveryNamesConnectionRepair() throws {
    let guide = ProjectRecoveryGuide(
      status: developFailedStatus(
        note:
          "Develop failed: Chat completions stream failed: status code: 401 - upstream body: unauthorized."
      )
    )

    try #require(!guide.isEmpty)
    try #require(guide.title == "Restore the model connection")
    try #require(guide.steps[0].title == "Inspect the provider failure")
    try #require(guide.steps[0].detail.contains("model provider failed"))
    try #require(guide.steps[1].title == "Check the active provider")
    try #require(guide.steps[1].detail.contains("selected model"))
    try #require(guide.steps[1].detail.contains("credentials"))
    try #require(guide.steps[2].detail.contains("stream a complete response"))
  }

  @Test
  func dirtyWorktreeRecoveryUsesPlainFileLanguage() throws {
    let guide = ProjectRecoveryGuide(status: dirtyWorktreeStatus())

    try #require(!guide.isEmpty)
    try #require(guide.title == "Finish the pending files")
    try #require(guide.steps.map(\.title) == [
      "Review pending file changes", "Choose what belongs", "Clean Worktree",
    ])
    try #require(guide.steps[0].detail.contains("1 pending change"))
    try #require(guide.steps[1].detail.contains("intended edits"))
    try #require(guide.steps[1].detail.contains("remove accidental leftovers"))
    try #require(guide.steps[2].detail == "Retry when no pending file changes remain.")
    try #require(!guide.narrationIdentifier.contains("source control"))
  }

  @Test
  func recoveryClipboardPayloadPackagesFailureForReuse() throws {
    let status = rejectedPlanStatus()
    let guide = ProjectRecoveryGuide(status: status)

    let payload = ProjectRecoveryClipboardPayload(status: status, guide: guide)

    try #require(payload.text.contains("Compass Recovery Handoff"))
    try #require(payload.text.contains("Recipient instructions:"))
    try #require(payload.text.contains("Do not invent files, commands, credentials"))
    try #require(payload.text.contains("return one executable Immediate Work handoff"))
    try #require(payload.text.contains("Status: Plan rejected"))
    try #require(payload.text.contains("Action: Retry Plan"))
    try #require(payload.text.contains("Cue count: 1 cue"))
    try #require(payload.text.contains("Failure detail:"))
    try #require(payload.text.contains("Recovery plan: Repair the Plan output"))
    try #require(payload.text.contains("1. Read the rejection:"))
    try #require(payload.text.contains("2. Use coverage-ready verify:"))
    try #require(payload.text.contains("3. Retry Plan:"))
    try #require(payload.text.count <= ProjectRecoveryClipboardPayload.textLimit)
    try #require(!payload.isEmpty)
  }

  @Test
  func recoveryClipboardPayloadIsEmptyWithoutRecoverySteps() throws {
    let status = emptyStatus()
    let guide = ProjectRecoveryGuide(status: status)

    let payload = ProjectRecoveryClipboardPayload(status: status, guide: guide)

    try #require(payload.isEmpty)
    try #require(payload.text.isEmpty)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalRecoveryPolish() async throws {
    let guide = ProjectRecoveryGuide(status: rejectedPlanStatus())

    try await withMockFoundationModels(
      response: "Plan needs a coverage-ready verify command before Develop can safely continue."
    ) {
      let generatedNarration = await ProjectRecoveryGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "Plan needs a coverage-ready verify command before Develop can safely continue.")
    }
  }

  @Test
  func narratorRejectsStructuredBulletedOrLinkedOutput() async {
    let guide = ProjectRecoveryGuide(status: rejectedPlanStatus())

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await ProjectRecoveryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Retry with a hidden command") {
      let narration = await ProjectRecoveryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await ProjectRecoveryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  private func emptyStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(completed: [], immediate: nil, candidates: "", strategicContext: ""),
        sessions: []
      )
    )
  }

  private func rejectedPlanStatus(
    note: String = """
      Verify command must collect test coverage for Swift Package projects. \
      test verify must declare coverage: guest `swift test --enable-code-coverage`.
      """
  ) -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(
          completed: [],
          immediate: PlanNext(
            plan: "## Outcome\nImprove recovery copy.\n\n## Acceptance checks\n- Tests pass.",
            verify: "swift test --filter ProjectRecoveryGuideTests"
          ),
          candidates: "",
          strategicContext: ""
        ),
        sessions: [
          SessionRecord(
            session: 42,
            startedAt: 1_000,
            endedAt: 1_500,
            plan: "Plan",
            verify: "swift test",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .rejectedByPlan,
            notes: [note],
            verifyOutput: nil,
            feedback: nil
          )
        ]
      )
    )
  }

  private func developFailedStatus(note: String) -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(
          completed: [],
          immediate: PlanNext(
            plan: "## Outcome\nImprove recovery copy.\n\n## Acceptance checks\n- Tests pass.",
            verify: "swift test --filter ProjectRecoveryGuideTests"
          ),
          candidates: "",
          strategicContext: ""
        ),
        sessions: [
          SessionRecord(
            session: 43,
            startedAt: 1_000,
            endedAt: 1_500,
            plan: "Plan",
            verify: "swift test",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .failed,
            notes: [note],
            verifyOutput: nil,
            feedback: nil
          )
        ]
      )
    )
  }

  private func dirtyWorktreeStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(
          completed: [],
          immediate: PlanNext(
            plan: "## Outcome\nImprove recovery copy.\n\n## Acceptance checks\n- Tests pass.",
            verify: "swift test --filter ProjectRecoveryGuideTests"
          ),
          candidates: "",
          strategicContext: ""
        ),
        sessions: [
          SessionRecord(
            session: 44,
            startedAt: 1_000,
            endedAt: 1_500,
            plan: "Plan",
            verify: "swift test",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .failed,
            notes: [
              """
              Uncommitted or untracked changes remain after Develop ran. \
              Commit them or add them to .gitignore.
              `git status --porcelain` output:
              ```
               M Sources/Compass/AppModel.swift
              ```
              """
            ],
            verifyOutput: nil,
            feedback: nil
          )
        ]
      )
    )
  }
}
