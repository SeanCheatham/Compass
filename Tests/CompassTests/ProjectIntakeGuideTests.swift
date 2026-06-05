import Foundation
import Testing

@testable import Compass

struct ProjectIntakeGuideTests {
  @Test
  func firstProjectGuideExplainsGitIntake() throws {
    let guide = ProjectIntakeGuide(projectCount: 0)

    try #require(guide.title == "Add Your First Project")
    try #require(guide.statusLabel == "No projects yet")
    try #require(guide.actionLabel == "Add Project")
    try #require(guide.systemImageName == "folder.badge.plus")
    try #require(guide.steps.map(\.id) == [
      "choose-git-folder", "capture-project-vision", "write-first-draft",
      "let-compass-verify",
    ])
    try #require(guide.steps[0].isPrimary)
    try #require(guide.steps[0].detail.contains("project folder"))
    try #require(guide.steps[0].detail.contains("repository root"))
    try #require(!guide.steps[0].detail.contains("Git root"))
    try #require(guide.steps[1].title == "Describe the pain")
    try #require(guide.steps[1].detail.contains("What user pain should Compass explore?"))
    try #require(guide.steps[1].detail.contains("current alternatives"))
    try #require(guide.steps[1].detail.contains("guardrails"))
    try #require(guide.steps[1].detail.contains("Project Vision"))
    try #require(guide.signals.map(\.id) == [
      "git", "verification", "project-vision", "plain-language-goal",
    ])
    try #require(guide.signals.contains { $0.id == "project-vision" && $0.label == "Pain context" })
    try #require(guide.allowsNarration)
    try #require(guide.narrationIdentifier.contains("count:0"))
    try #require(guide.narrationIdentifier.contains("Add Your First Project"))
  }

  @Test
  func existingProjectGuidePointsBackToSidebarSelection() throws {
    let guide = ProjectIntakeGuide(projectCount: 3)

    try #require(guide.title == "Choose a Project")
    try #require(guide.statusLabel == "3 projects available")
    try #require(guide.actionLabel == "Add Missing Repo")
    try #require(guide.steps.first?.id == "select-sidebar-row")
    try #require(guide.steps.contains { $0.id == "add-missing-repo" })
    try #require(guide.detail.contains("sidebar"))
    try #require(guide.narrationIdentifier.contains("count:3"))
    try #require(guide.narrationIdentifier.contains("Choose a Project"))
  }

  @Test
  func negativeProjectCountIsClampedForDisplay() throws {
    let guide = ProjectIntakeGuide(projectCount: -4)

    try #require(guide.projectCount == 0)
    try #require(guide.statusLabel == "No projects yet")
  }

  @Test
  func clipboardPayloadPackagesPlainLanguageHandoff() throws {
    let guide = ProjectIntakeGuide(projectCount: 0)
    let payload = ProjectIntakeClipboardPayload(guide: guide)

    try #require(payload.text.contains("Compass Project Intake Handoff"))
    try #require(payload.text.contains("Recipient instructions:"))
    try #require(payload.text.contains("capture the user pain"))
    try #require(payload.text.contains("Status: No projects yet"))
    try #require(payload.text.contains("- Choose a Git folder:"))
    try #require(payload.text.contains("- Describe the pain:"))
    try #require(payload.text.contains("Pain context:"))
    try #require(payload.text.contains("Good project signals:"))
    try #require(payload.text.count <= ProjectIntakeGuide.handoffLimit)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalIntakeCoaching() async throws {
    let guide = ProjectIntakeGuide(projectCount: 0)

    try await withMockFoundationModels(
      response: "Start by choosing a real Git folder; Compass will help turn rough goals into verified work."
    ) {
      let prompt = ProjectIntakeGuideNarrator.prompt(for: guide)
      #expect(prompt.contains("Status: No projects yet"))
      #expect(prompt.contains("Recommended action: Add Project"))
      #expect(prompt.contains("Do not invent repository paths"))
      #expect(prompt.contains("Project Vision"))

      let generatedNarration = await ProjectIntakeGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "Start by choosing a real Git folder; Compass will help turn rough goals into verified work.")
    }
  }

  @Test
  func narratorSkipsUnavailableFoundationModels() async {
    let guide = ProjectIntakeGuide(projectCount: 2)

    await withMockFoundationModels(available: false, response: "Should not be used") {
      let narration = await ProjectIntakeGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredBulletedOrLinkedOutput() async {
    let guide = ProjectIntakeGuide(projectCount: 0)

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await ProjectIntakeGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Add a hidden repository") {
      let narration = await ProjectIntakeGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await ProjectIntakeGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
