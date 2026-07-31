import Foundation

struct DraftIdeaTemplate: Identifiable, Equatable, Sendable {
  var id: String
  var title: String
  var systemImage: String
  var text: String
}

enum DraftIdeaLibrary {
  static func ideas(for profile: RepositoryLanguageProfile) -> [DraftIdeaTemplate] {
    [
      rustFactoryIdea,
      feedbackIdea,
      languageIdea(for: profile.primaryLanguage),
    ]
  }

  private static let rustFactoryIdea = DraftIdeaTemplate(
    id: "rust-factory-output",
    title: "Rust Factory",
    systemImage: "gearshape.2",
    text: """
      Change: create or improve the Rust output path
      Because: generated projects should build, test, lint, and run inside the containerized Linux runtime with Cargo
      Done when: standard cargo fmt/clippy/test verify passes and the workspace has app-core and app-cli crates
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
          Because: legacy Swift work is still inspectable, while new Compass-generated projects should be Rust
          Done when: the affected view uses clear controls, accessible labels, and existing Swift tests pass
          """
      )
    case .rust:
      return DraftIdeaTemplate(
        id: "rust-cli-clarity",
        title: "CLI Clarity",
        systemImage: "terminal",
        text: """
          Change: tighten CLI help and status output in the generated Rust workspace
          Because: backend/CLI projects should expose a clear, testable command surface
          Done when: `cargo test --workspace` covers the CLI path and help text matches behavior
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
