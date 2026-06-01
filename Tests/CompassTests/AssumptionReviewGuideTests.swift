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
  func guideExplainsArchivedOnlyLedger() {
    let guide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: [
        record(id: "archived", text: "The old setup flow should stay first.", status: .superseded)
      ])
    )

    #expect(guide.title == "All Assumptions Archived")
    #expect(guide.tone == .empty)
    #expect(
      guide.detail == "1 archived assumption is kept in history but no longer steer future runs.")
    #expect(guide.promptEffect == "Future prompts are not receiving active assumption guidance.")
    #expect(guide.steps.map(\.id) == ["archivedOnly"])
    #expect(guide.queue.isEmpty)
  }

  @Test
  func clipboardPayloadPackagesAssumptionMemoryForReuse() {
    let ledger = AssumptionLedger(assumptions: [
      record(
        id: "implicit",
        text: "The target user is a non-engineer operator.",
        status: .implicit,
        impact: "Use plain-language controls and copyable context.",
        rationale: "The goal asks for a heavy non-engineer UX focus.",
        evidence: ["/goal mentions non-engineer UX"],
        invalidation: "The user asks for engineer-only controls.",
        updatedAt: 30
      ),
      record(
        id: "affirmed",
        text: "Foundation Models should stay non-load-bearing.",
        status: .affirmed,
        impact: "Generated narration can polish copy but deterministic fallbacks must work.",
        userComment: "Keep tests independent of model availability.",
        updatedAt: 20
      ),
      record(
        id: "denied",
        text: "Compass can skip local verification.",
        status: .denied,
        impact: "Future agents must run the focused and local test commands.",
        updatedAt: 10
      ),
      record(
        id: "archived",
        text: "The old setup flow should stay first.",
        status: .superseded
      ),
    ])
    let guide = AssumptionReviewGuide(ledger: ledger)
    let payload = AssumptionReviewClipboardPayload(ledger: ledger, guide: guide)

    #expect(payload.text.contains("Compass Assumptions Handoff"))
    #expect(payload.text.contains("Recipient instructions:"))
    #expect(payload.text.contains("Do not invent files, credentials, product intent"))
    #expect(payload.text.contains("Status: Review Needed"))
    #expect(payload.text.contains("Counts: 1 implicit, 1 affirmed, 1 denied, 1 archived"))
    #expect(payload.text.contains("Needs review first:"))
    #expect(payload.text.contains("- The target user is a non-engineer operator."))
    #expect(payload.text.contains("User-affirmed assumptions (strong guidance)"))
    #expect(payload.text.contains("- [affirmed] Foundation Models should stay non-load-bearing."))
    #expect(payload.text.contains("User comment: Keep tests independent of model availability."))
    #expect(payload.text.contains("Implicit assumptions (verify before relying)"))
    #expect(payload.text.contains("- [implicit] The target user is a non-engineer operator."))
    #expect(payload.text.contains("Impact: Use plain-language controls and copyable context."))
    #expect(payload.text.contains("Rationale: The goal asks for a heavy non-engineer UX focus."))
    #expect(payload.text.contains("Invalidated by: The user asks for engineer-only controls."))
    #expect(payload.text.contains("Evidence:\n    - /goal mentions non-engineer UX"))
    #expect(payload.text.contains("Denied assumptions (corrections; do not rely)"))
    #expect(payload.text.contains("- [denied] Compass can skip local verification."))
    #expect(payload.text.contains("Archived assumptions: 1"))
    #expect(payload.text.count <= AssumptionReviewClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func clipboardPayloadIsEmptyWithoutAssumptionMemory() {
    let guide = AssumptionReviewGuide(ledger: .empty)
    let payload = AssumptionReviewClipboardPayload(ledger: .empty, guide: guide)

    #expect(payload.isEmpty)
    #expect(payload.text.isEmpty)
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
    evidence: [String] = [],
    invalidation: String = "",
    userComment: String? = nil,
    updatedAt: Double = 1
  ) -> AssumptionRecord {
    AssumptionRecord(
      id: id,
      text: text,
      rationale: rationale,
      evidence: evidence,
      impact: impact,
      invalidation: invalidation,
      scope: .project,
      status: status,
      createdByPhase: "plan",
      createdInSession: 2,
      createdAt: 1,
      updatedAt: updatedAt,
      userComment: userComment
    )
  }
}
