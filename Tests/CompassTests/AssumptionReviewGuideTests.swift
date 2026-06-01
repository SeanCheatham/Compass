import Testing

@testable import Compass

struct AssumptionReviewGuideTests {
  @Test
  func emptyLedgerExplainsNoMemoryYet() async throws {
    let guide = AssumptionReviewGuide(ledger: .empty)

    #expect(guide.title == "No Memory Yet")
    #expect(guide.tone == .empty)
    #expect(guide.promptEffect == "Future prompts are not receiving assumption guidance yet.")
    #expect(guide.steps.map(\.id) == ["waitForSignals"])
    #expect(guide.queue.isEmpty)
    #expect(!guide.narrationIdentifier.isEmpty)

    await withMockFoundationModels {
      let narration = await AssumptionReviewGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func guidePrioritizesImplicitAssumptionsForReview() {
    let guide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: [
        record(
          id: "affirmed",
          text: "Compass should keep plans copyable.",
          status: .affirmed,
          updatedAt: 10
        ),
        record(
          id: "olderImplicit",
          text: "The user prefers World-first UX.",
          status: .implicit,
          impact: "World polish should lead the next slice.",
          updatedAt: 20
        ),
        record(
          id: "denied",
          text: "The user wants a marketing page.",
          status: .denied,
          updatedAt: 30
        ),
        record(
          id: "newerImplicit",
          text: "The next run can assume the app was restarted.",
          status: .implicit,
          rationale: "The user asked whether to restart Compass.",
          updatedAt: 40
        ),
      ])
    )

    #expect(guide.title == "Review Needed")
    #expect(guide.tone == .review)
    #expect(
      guide.promptEffect
        == "Implicit assumptions are still sent to agents, but marked as lower confidence.")
    #expect(guide.steps.map(\.id) == ["reviewImplicit", "keepCorrections", "reuseGuidance"])
    #expect(guide.queue.map(\.id) == ["newerImplicit", "olderImplicit"])
    #expect(guide.queue.first?.detail.contains("session 2") == true)
    #expect(
      guide.queue.first?.detail.contains("The user asked whether to restart Compass.") == true)
  }

  @Test
  func guideUsesCorrectionsWhenNoImplicitReviewRemains() {
    let guide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: [
        record(id: "denied", text: "Do not assume no tests are needed.", status: .denied),
        record(id: "affirmed", text: "Keep handoffs copyable.", status: .affirmed),
      ])
    )

    #expect(guide.title == "Corrections Active")
    #expect(guide.tone == .correction)
    #expect(
      guide.promptEffect
        == "Denied assumptions are injected as corrections agents must not rely on.")
    #expect(guide.queue.isEmpty)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalPolish() async throws {
    let guide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: [
        record(id: "implicit", text: "Compass should explain hidden state.", status: .implicit)
      ])
    )

    try await withMockFoundationModels(response: "Compass has one guess waiting for review.") {
      let generatedNarration = await AssumptionReviewGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(narration.text == "Compass has one guess waiting for review.")
    }

    await withMockFoundationModels(available: false) {
      let narration = await AssumptionReviewGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredOrLinkedOutput() async throws {
    let guide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: [
        record(id: "implicit", text: "Compass should explain hidden state.", status: .implicit)
      ])
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await AssumptionReviewGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await AssumptionReviewGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  private func record(
    id: String,
    text: String,
    status: AssumptionRecord.Status,
    impact: String = "",
    rationale: String = "",
    updatedAt: Double = 1
  ) -> AssumptionRecord {
    AssumptionRecord(
      id: id,
      text: text,
      rationale: rationale,
      impact: impact,
      scope: .project,
      status: status,
      createdByPhase: "plan",
      createdInSession: 2,
      createdAt: 1,
      updatedAt: updatedAt
    )
  }
}
