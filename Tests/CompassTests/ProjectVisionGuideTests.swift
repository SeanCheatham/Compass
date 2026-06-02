import Foundation
import Testing

@testable import Compass

struct ProjectVisionGuideTests {
  @Test
  func emptyVisionExplainsFirstUsefulSignals() {
    let guide = ProjectVisionGuide(vision: "")
    let payload = ProjectVisionClipboardPayload(guide: guide)

    #expect(guide.status == .empty)
    #expect(guide.title == "Vision empty")
    #expect(guide.detail.contains("must-have guardrails"))
    #expect(guide.scoreLabel == "0 of 4 signals")
    #expect(guide.missingSignalTitles == ["Audience", "Problem", "Success signal", "Guardrails"])
    #expect(guide.nextAction.title == "Add a first vision")
    #expect(guide.nextAction.detail.contains("one guardrail"))
    #expect(!guide.allowsNarration)
    #expect(payload.isEmpty)
    #expect(payload.text.isEmpty)
  }

  @Test
  func emptyVisionStartsInEditMode() {
    #expect(MarkdownDocumentMode.initial(for: "") == .edit)
    #expect(MarkdownDocumentMode.initial(for: " \n\t ") == .edit)
    #expect(MarkdownDocumentMode.initial(for: "Compass helps non-developers.") == .preview)
  }

  @Test
  func groundedVisionAsksForGuardrails() {
    let guide = ProjectVisionGuide(
      vision:
        "Compass helps non-developer users because shipping software is confusing. Success shows a visible run audit when the work is done."
    )

    #expect(guide.status == .grounded)
    #expect(guide.title == "Vision grounded")
    #expect(guide.scoreLabel == "3 of 4 signals")
    #expect(guide.satisfiedSignalTitles == ["Audience", "Problem", "Success signal"])
    #expect(guide.missingSignalTitles == ["Guardrails"])
    #expect(guide.allowsNarration)
    #expect(guide.nextAction.title == "Add guardrails")
  }

  @Test
  func readyVisionPayloadPackagesProductIntentForReuse() {
    let guide = ProjectVisionGuide(
      vision: """
        Compass helps non-engineer operators build high-quality macOS software because setup, planning, and verification are hard.
        Success shows a visible run audit, passing tests, and plain-language next steps.
        It must preserve privacy, use native Apple capabilities where possible, and avoid hiding risky assumptions.
        """
    )
    let payload = ProjectVisionClipboardPayload(guide: guide)

    #expect(guide.status == .ready)
    #expect(guide.title == "Vision ready")
    #expect(guide.scoreLabel == "4 of 4 signals")
    #expect(guide.missingSignalText == "none")
    #expect(guide.nextAction.title == "Use vision in Plan")
    #expect(payload.text.contains("Compass Project Vision Handoff"))
    #expect(payload.text.contains("Do not invent users, requirements"))
    #expect(payload.text.contains("Status: Vision ready"))
    #expect(payload.text.contains("Signals present: Audience, Problem, Success signal, Guardrails"))
    #expect(payload.text.contains("Missing signals: none"))
    #expect(payload.text.contains("Compass helps non-engineer operators"))
    #expect(payload.text.contains("[present] Guardrails"))
    #expect(payload.text.count <= ProjectVisionClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func narrationIdentifierTracksVisionSignalChanges() {
    let initial = ProjectVisionGuide(vision: "Compass helps users.")
    let refined = ProjectVisionGuide(
      vision:
        "Compass helps users because planning is hard. Success shows passing tests. It must stay macOS native."
    )

    #expect(initial.narrationIdentifier.contains("missing:Problem,Success signal,Guardrails"))
    #expect(refined.narrationIdentifier.contains("present:Audience,Problem,Success signal,Guardrails"))
    #expect(initial.narrationIdentifier != refined.narrationIdentifier)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalVisionCoaching() async throws {
    let guide = ProjectVisionGuide(
      vision:
        "Compass helps non-developer users because shipping software is confusing. Success shows a visible run audit when the work is done."
    )

    try await withMockFoundationModels(
      response: "The audience, problem, and success are clear; add one guardrail before planning."
    ) {
      let prompt = ProjectVisionGuideNarrator.prompt(for: guide)
      #expect(prompt.contains("Status: Vision grounded"))
      #expect(prompt.contains("Missing signals: Guardrails"))
      #expect(prompt.contains("Do not invent users, requirements"))

      let generatedNarration = await ProjectVisionGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "The audience, problem, and success are clear; add one guardrail before planning.")
    }
  }

  @Test
  func narratorSkipsEmptyVisionAndUnavailableFoundationModels() async {
    let emptyGuide = ProjectVisionGuide(vision: "")
    let groundedGuide = ProjectVisionGuide(
      vision:
        "Compass helps users because setup is hard. Success shows passing tests when it is done."
    )

    await withMockFoundationModels(response: "Should not be used") {
      let narration = await ProjectVisionGuideNarrator.narrate(guide: emptyGuide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(available: false, response: "Should not be used") {
      let narration = await ProjectVisionGuideNarrator.narrate(guide: groundedGuide)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredBulletedOrLinkedOutput() async {
    let guide = ProjectVisionGuide(
      vision:
        "Compass helps non-engineer operators because software setup is hard. Success shows passing tests. It must stay macOS native."
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await ProjectVisionGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Add hidden requirements") {
      let narration = await ProjectVisionGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await ProjectVisionGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
