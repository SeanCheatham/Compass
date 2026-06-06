import Foundation
import Testing

@testable import Compass

struct ProductTournamentSettingsGuideTests {
  @Test
  func emptyGuideExplainsProjectSetup() {
    let guide = ProductTournamentSettingsGuide(projects: [])

    #expect(guide.title == "Add a Project")
    #expect(guide.actionLabel == "No projects")
    #expect(guide.tone == .empty)
    #expect(guide.routingCoverage.label == "No projects yet")
    #expect(guide.routingCoverage.fraction == 0)
    #expect(guide.rows.map(\.id) == ["projects"])
    #expect(guide.rows[0].detail.contains("Add a repository"))
  }

  @Test
  func recommendedSwiftProjectNeedsToggle() {
    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(
        name: "Swift App",
        hostXcodeBuildTestEnabled: false,
        recommendsHostXcode: true,
        isSelected: true
      )
    ])

    #expect(guide.title == "Tournament Needs One Toggle")
    #expect(guide.actionLabel == "1 recommended")
    #expect(guide.tone == .attention)
    #expect(guide.detail.contains("Enable Host Xcode Build/Test"))
    #expect(guide.routingCoverage.label == "0 of 1 recommended enabled")
    #expect(guide.routingCoverage.fraction == 0)
    #expect(guide.rows[0].label == "Swift App (selected)")
    #expect(guide.rows[0].status == .recommended)
    #expect(guide.rows[0].detail.contains("Recommended for this legacy repo"))
  }

  @Test
  func multipleRecommendedProjectsUsePluralCopy() {
    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(name: "One", hostXcodeBuildTestEnabled: false, recommendsHostXcode: true),
      makeProject(name: "Two", hostXcodeBuildTestEnabled: false, recommendsHostXcode: true),
    ])

    #expect(guide.title == "Tournament Needs 2 Toggles")
    #expect(guide.actionLabel == "2 recommended")
    #expect(guide.routingCoverage.label == "0 of 2 recommended enabled")
    #expect(guide.rows.map(\.label) == ["One", "Two"])
    #expect(guide.rows.allSatisfy { $0.status == .recommended })
  }

  @Test
  func enabledHostXcodeProjectMarksVerificationReady() {
    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(name: "Swift App", hostXcodeBuildTestEnabled: true, recommendsHostXcode: true)
    ])

    #expect(guide.title == "Tournament Verification Ready")
    #expect(guide.actionLabel == "Ready")
    #expect(guide.tone == .ready)
    #expect(guide.routingCoverage.label == "All 1 recommended enabled")
    #expect(guide.routingCoverage.fraction == 1)
    #expect(guide.rows[0].status == .ready)
    #expect(guide.rows[0].detail.contains("full Xcode on this Mac"))
  }

  @Test
  func nonSwiftProjectCanKeepHostXcodeOff() {
    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(
        name: "Rust Service", hostXcodeBuildTestEnabled: false, recommendsHostXcode: false)
    ])

    #expect(guide.title == "Tournament Defaults Ready")
    #expect(guide.tone == .ready)
    #expect(guide.routingCoverage.label == "No recommended toggles")
    #expect(guide.routingCoverage.fraction == 1)
    #expect(guide.rows[0].status == .off)
    #expect(guide.rows[0].detail.contains("no SwiftPM, Xcode project, or workspace signal"))
  }

  @Test
  func tournamentClipboardPayloadPackagesRecommendedRowsForReuse() {
    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(
        name: "Swift App",
        hostXcodeBuildTestEnabled: false,
        recommendsHostXcode: true,
        isSelected: true
      ),
      makeProject(
        name: "CLI Tools",
        hostXcodeBuildTestEnabled: true,
        recommendsHostXcode: true
      ),
      makeProject(
        name: "Rust Service",
        hostXcodeBuildTestEnabled: false,
        recommendsHostXcode: false
      ),
    ])

    let payload = ProductTournamentSettingsClipboardPayload(guide: guide)

    #expect(payload.text.contains("Compass Product Tournament Settings Handoff"))
    #expect(payload.text.contains("Do not invent projects"))
    #expect(payload.text.contains("Status: Tournament Needs One Toggle (attention)"))
    #expect(payload.text.contains("Action: 1 recommended"))
    #expect(payload.text.contains("Routing coverage: 1 of 2 recommended enabled"))
    #expect(payload.text.contains("Rows: 1 ready, 1 recommended, 1 off"))
    #expect(payload.text.contains("[recommended] Swift App (selected)"))
    #expect(payload.text.contains("[ready] CLI Tools"))
    #expect(payload.text.contains("[off] Rust Service"))
    #expect(payload.text.contains("Host Xcode Build/Test changes the verification route only"))
    #expect(payload.text.count <= ProductTournamentSettingsClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func tournamentClipboardPayloadCoversEmptyProjectList() {
    let guide = ProductTournamentSettingsGuide(projects: [])

    let payload = ProductTournamentSettingsClipboardPayload(guide: guide)

    #expect(payload.text.contains("Status: Add a Project (empty)"))
    #expect(payload.text.contains("Action: No projects"))
    #expect(payload.text.contains("Rows: 0 ready, 0 recommended, 1 off"))
    #expect(payload.text.contains("[off] Projects: Add a repository"))
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalTournamentPolish() async throws {
    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(name: "Swift App", hostXcodeBuildTestEnabled: false, recommendsHostXcode: true)
    ])

    try await withMockFoundationModels(
      response: "Enable Host Xcode for Swift App so build and test checks use full Xcode."
    ) {
      let prompt = ProductTournamentSettingsGuideNarrator.prompt(for: guide)
      #expect(prompt.contains("Routing coverage: 0 of 1 recommended enabled"))

      let generatedNarration = await ProductTournamentSettingsGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text == "Enable Host Xcode for Swift App so build and test checks use full Xcode."
      )
    }
  }

  @Test
  func narratorSkipsEmptyAndRejectsStructuredBulletedOrLinkedOutput() async {
    let emptyGuide = ProductTournamentSettingsGuide(projects: [])
    await withMockFoundationModels(response: "Should not be used") {
      let narration = await ProductTournamentSettingsGuideNarrator.narrate(guide: emptyGuide)
      #expect(narration == nil)
    }

    let guide = ProductTournamentSettingsGuide(projects: [
      makeProject(name: "Swift App", hostXcodeBuildTestEnabled: false, recommendsHostXcode: true)
    ])

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await ProductTournamentSettingsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Enable a hidden service") {
      let narration = await ProductTournamentSettingsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await ProductTournamentSettingsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  private func makeProject(
    name: String,
    hostXcodeBuildTestEnabled: Bool,
    recommendsHostXcode: Bool,
    isSelected: Bool = false
  ) -> ProductTournamentSettingsGuide.Project {
    ProductTournamentSettingsGuide.Project(
      id: UUID(),
      displayName: name,
      hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled,
      recommendsHostXcode: recommendsHostXcode,
      isSelected: isSelected
    )
  }
}
