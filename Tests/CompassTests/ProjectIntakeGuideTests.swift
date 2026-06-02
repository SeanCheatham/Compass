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
      "choose-git-folder", "write-human-goals", "let-compass-verify",
    ])
    try #require(guide.steps[0].isPrimary)
    try #require(guide.signals.map(\.id) == [
      "git", "verification", "plain-language-goal",
    ])
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
    try #require(payload.text.contains("Status: No projects yet"))
    try #require(payload.text.contains("- Choose a Git folder:"))
    try #require(payload.text.contains("Good project signals:"))
    try #require(payload.text.count <= ProjectIntakeGuide.handoffLimit)
  }
}
