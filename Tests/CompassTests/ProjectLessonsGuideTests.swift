import Foundation
import Testing

@testable import Compass

struct ProjectLessonsGuideTests {
  @Test
  func emptyLessonsExplainWhyProjectMemoryMatters() {
    let guide = ProjectLessonsGuide(lessons: "")
    let payload = ProjectLessonsClipboardPayload(guide: guide)

    #expect(guide.status == .empty)
    #expect(guide.title == "Lessons empty")
    #expect(guide.scoreLabel == "0 of 4 signals")
    #expect(guide.entryCount == 0)
    #expect(guide.missingSignalTitles == ["Learning", "Proof", "Decision", "Reuse cue"])
    #expect(guide.nextAction.title == "Capture a first lesson")
    #expect(!guide.allowsNarration)
    #expect(payload.isEmpty)
    #expect(payload.text.isEmpty)
  }

  @Test
  func partialLessonsNameMissingSignals() {
    let guide = ProjectLessonsGuide(
      lessons: "- Learned that verify output was too hard to inspect because the full log was hidden."
    )

    #expect(guide.status == .needsFocus)
    #expect(guide.title == "Lessons need context")
    #expect(guide.scoreLabel == "2 of 4 signals")
    #expect(guide.entryCount == 1)
    #expect(guide.satisfiedSignalTitles == ["Learning", "Proof"])
    #expect(guide.missingSignalTitles == ["Decision", "Reuse cue"])
    #expect(guide.detail == "Missing: Decision, Reuse cue.")
    #expect(guide.allowsNarration)
  }

  @Test
  func reusableLessonsPayloadPackagesProjectMemoryForReuse() {
    let guide = ProjectLessonsGuide(
      lessons: """
        - Learned that non-developers trust runs faster when full Verify output is visible; tests passed with PlanSessionHistoryTests.
        - Decision: preserve audit artifact paths in Run History and reuse this before future verification UI work.
        """
    )
    let payload = ProjectLessonsClipboardPayload(guide: guide)

    #expect(guide.status == .ready)
    #expect(guide.title == "Lessons reusable")
    #expect(guide.scoreLabel == "4 of 4 signals")
    #expect(guide.entryCount == 2)
    #expect(guide.missingSignalText == "none")
    #expect(payload.text.contains("Compass Project Lessons Handoff"))
    #expect(payload.text.contains("Do not invent decisions, proof"))
    #expect(payload.text.contains("Status: Lessons reusable"))
    #expect(payload.text.contains("Signals present: Learning, Proof, Decision, Reuse cue"))
    #expect(payload.text.contains("Missing signals: none"))
    #expect(payload.text.contains("[present] Proof"))
    #expect(payload.text.count <= ProjectLessonsClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
    #expect(guide.allowsNarration)
  }

  @Test
  func narrationIdentifierTracksLessonsSignalChanges() {
    let initial = ProjectLessonsGuide(lessons: "Learned the setup flow is confusing.")
    let refined = ProjectLessonsGuide(
      lessons:
        "Learned setup is confusing; tests passed after the fix. Decision: prefer visible setup proof next time."
    )

    #expect(initial.narrationIdentifier.contains("missing:Proof,Decision,Reuse cue"))
    #expect(refined.narrationIdentifier.contains("present:Learning,Proof,Decision,Reuse cue"))
    #expect(initial.narrationIdentifier != refined.narrationIdentifier)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalLessonsCoaching() async throws {
    let guide = ProjectLessonsGuide(
      lessons: "- Learned that Verify output was hidden even though tests passed."
    )

    try await withMockFoundationModels(
      response: "This lesson has learning and proof; add the decision and when to reuse it."
    ) {
      let prompt = ProjectLessonsGuideNarrator.prompt(for: guide)
      #expect(prompt.contains("Status: Lessons need context"))
      #expect(prompt.contains("Missing signals: Decision, Reuse cue"))
      #expect(prompt.contains("Do not invent files, commands"))

      let generatedNarration = await ProjectLessonsGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "This lesson has learning and proof; add the decision and when to reuse it.")
    }
  }

  @Test
  func narratorSkipsEmptyLessonsAndUnavailableFoundationModels() async {
    let emptyGuide = ProjectLessonsGuide(lessons: "")
    let reusableGuide = ProjectLessonsGuide(
      lessons:
        "Learned setup is confusing; tests passed after the fix. Decision: prefer visible setup proof next time."
    )

    await withMockFoundationModels(response: "Should not be used") {
      let narration = await ProjectLessonsGuideNarrator.narrate(guide: emptyGuide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(available: false, response: "Should not be used") {
      let narration = await ProjectLessonsGuideNarrator.narrate(guide: reusableGuide)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredBulletedOrLinkedOutput() async {
    let guide = ProjectLessonsGuide(
      lessons:
        "Learned setup is confusing; tests passed after the fix. Decision: prefer visible setup proof next time."
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await ProjectLessonsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Add a hidden requirement") {
      let narration = await ProjectLessonsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await ProjectLessonsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
