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
    #expect(guide.scoreLabel == "0 of 4 signals")
    #expect(guide.missingSignalTitles == ["Audience", "Problem", "Success signal", "Guardrails"])
    #expect(guide.nextAction.title == "Add a first vision")
    #expect(payload.isEmpty)
    #expect(payload.text.isEmpty)
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
}
