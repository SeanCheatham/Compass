import Foundation
import Testing

@testable import CompassCore

@Suite("ProjectBrief")
struct ProjectBriefTests {
  @Test
  func encodeDecodeRoundTrip() throws {
    let brief = ProjectBrief(
      audience: "Maintainers",
      problem: "Freeform briefs hide requirements",
      productRequirements: [
        ProductRequirement(id: "req-1", text: "Structured fields"),
        ProductRequirement(id: "req-2", text: "Repeatable requirements"),
      ]
    )

    let data = try JSONEncoder().encode(brief)
    let decoded = try JSONDecoder().decode(ProjectBrief.self, from: data)

    #expect(decoded == brief)
  }

  @Test
  func sanitizedDropsBlankRequirements() {
    var editable = ProjectBrief(audience: "  Users  ", problem: " Pain ")
    editable.productRequirements = [
      ProductRequirement(id: "a", text: "Keep me"),
      ProductRequirement(id: "b", text: "  "),
      ProductRequirement(id: "c", text: ""),
    ]
    let cleaned = editable.sanitized()

    #expect(cleaned.audience == "Users")
    #expect(cleaned.problem == "Pain")
    #expect(cleaned.productRequirements.map(\.text) == ["Keep me"])
    #expect(cleaned.isReady)
  }

  @Test
  func renderedMarkdownIncludesSections() {
    let markdown = ProjectBrief(
      audience: "Operators",
      problem: "Missing checklist",
      productRequirements: [ProductRequirement(text: "Show requirements")]
    ).renderedMarkdown()

    #expect(markdown.contains("### Audience"))
    #expect(markdown.contains("Operators"))
    #expect(markdown.contains("### Problem"))
    #expect(markdown.contains("Missing checklist"))
    #expect(markdown.contains("### Product Requirements"))
    #expect(markdown.contains("- Show requirements"))
  }

  @Test
  func renderedMarkdownMarksEmptyFields() {
    let markdown = ProjectBrief.empty.renderedMarkdown()
    #expect(markdown.contains("_(not set)_"))
    #expect(markdown.contains("- _(none)_"))
  }
}

@Suite("ProjectVisionGuide")
struct ProjectVisionGuideTests {
  @Test
  func emptyBrief() {
    let guide = ProjectVisionGuide(brief: .empty)
    #expect(guide.status == .empty)
    #expect(guide.isEmpty)
    #expect(guide.cues.map(\.isSatisfied) == [false, false, false, false])
  }

  @Test
  func partialBriefNeedsFocus() {
    let guide = ProjectVisionGuide(
      brief: ProjectBrief(audience: "Users", problem: "", productRequirements: [])
    )
    #expect(guide.status == .needsFocus)
    #expect(guide.satisfiedSignalTitles == ["Audience"])
    #expect(guide.missingSignalTitles == ["Problem", "Requirements", "Verified"])
  }

  @Test
  func completeBriefIsReady() {
    let guide = ProjectVisionGuide(
      brief: ProjectBrief.problemFocused("Ship structured brief")
    )
    #expect(guide.status == .ready)
    #expect(guide.title == "Brief ready")
    #expect(guide.scoreLabel == "3 of 4 signals")
    #expect(guide.cues.map(\.isSatisfied) == [true, true, true, false])
  }

  @Test
  func verifiedBriefMarksVerificationCue() {
    let brief = ProjectBrief.problemFocused("Ship structured brief")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .satisfied)]
    )
    let guide = ProjectVisionGuide(brief: brief, ledger: ledger)
    #expect(guide.status == .ready)
    #expect(guide.title == "Requirements verified")
    #expect(guide.cues.allSatisfy { $0.isSatisfied })
    #expect(guide.scoreLabel == "4 of 4 signals")
  }
}
