import Foundation

package struct DraftIdeaTemplate: Identifiable, Equatable, Sendable {
  package var id: String
  package var title: String
  package var systemImage: String
  package var text: String
}

package enum DraftIdeaLibrary {
  package static func ideas(for profile: RepositoryLanguageProfile) -> [DraftIdeaTemplate] {
    [
      tesseraFactoryIdea,
      feedbackIdea,
      languageIdea(for: profile.primaryLanguage),
    ]
  }

  private static let tesseraFactoryIdea = DraftIdeaTemplate(
    id: "tessera-factory-output",
    title: "Tessera Factory",
    systemImage: "curlybraces.square",
    text: """
      Change: create or improve the Tessera app output path
      Because: generated projects should verify deterministically through Tessera manifests, sources, contexts, and tests
      Done when: `tessera verify . --json` passes and the workspace has `tessera.json`, `src/`, `contexts/`, and `tests/`
      """
  )

  private static let feedbackIdea = DraftIdeaTemplate(
    id: "plain-feedback",
    title: "Validation Signal",
    systemImage: "text.bubble",
    text: """
      Change: collect clearer simulated-user validation signals for the active contender
      Because: tournament decisions should explain pain recognition, switching objections, and willingness to pay
      Done when: the Workbench shows the next proof target and the latest evidence summary for that contender
      """
  )

  private static func languageIdea(for language: RepositoryLanguage) -> DraftIdeaTemplate {
    switch language {
    case .swift:
      return DraftIdeaTemplate(
        id: "legacy-swift-polish",
        title: "Legacy Swift",
        systemImage: "macwindow",
        text: """
          Change: polish the imported Swift repo without creating new generated Swift output
          Because: legacy Swift work is still inspectable, while new Compass-generated projects should be Tessera
          Done when: the affected view uses clear controls, accessible labels, and existing Swift tests pass
          """
      )
    case .markdown:
      return DraftIdeaTemplate(
        id: "docs-setup-guide",
        title: "Setup Guide",
        systemImage: "book.pages",
        text: """
          Change: make the setup guide clearer for first-time users
          Because: people should be able to start without asking a developer for missing context
          Done when: the docs explain prerequisites, the happy path, and what to do if setup fails
          """
      )
    case .other, .unknown:
      return DraftIdeaTemplate(
        id: "project-tour",
        title: "Factory Brief",
        systemImage: "scope",
        text: """
          Change: clarify the next software task before building
          Because: tiny models need a narrow brief with explicit constraints and acceptance signals
          Done when: Project Brief names the user, outcome, constraints, and verification command
          """
      )
    }
  }
}
