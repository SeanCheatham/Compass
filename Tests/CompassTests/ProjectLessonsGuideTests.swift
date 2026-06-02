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
}
