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
        state: PlanState(completed: [], immediate: nil, midTerm: "", longTerm: ""),
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
          midTerm: "",
          longTerm: ""
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
}
