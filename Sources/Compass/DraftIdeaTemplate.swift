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
      rustDesktopIdea,
      feedbackIdea,
      languageIdea(for: profile.primaryLanguage),
    ]
  }

  private static let rustDesktopIdea = DraftIdeaTemplate(
    id: "rust-desktop-output",
    title: "Rust Desktop",
    systemImage: "macwindow.badge.plus",
    text: """
      Change: create or improve the Rust desktop output path
      Because: generated projects should build, run, and screenshot inside the Shared VM without Host Xcode
      Done when: the Cargo workspace shows a deterministic desktop UI and Rust verification commands pass visibly
      """
  )

  private static let feedbackIdea = DraftIdeaTemplate(
    id: "plain-feedback",
    title: "Plain Feedback",
    systemImage: "text.bubble",
    text: """
      Change: surface progress and failures in plain language
      Because: users need confidence while Compass works in the background
      Done when: the UI shows what happened, what is blocked, and what to try next
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
    case .typeScriptJavaScript:
      return DraftIdeaTemplate(
        id: "legacy-web-state-clarity",
        title: "Legacy Web",
        systemImage: "rectangle.3.group",
        text: """
          Change: repair or clarify the imported TS/JS repo without creating new generated web output
          Because: legacy web repos are still inspectable, while new Compass-generated projects should be Rust
          Done when: the active view shows ready, blocked, and in-progress states clearly
          """
      )
    case .rust:
      return DraftIdeaTemplate(
        id: "rust-xtask-verification",
        title: "Rust Verify",
        systemImage: "checkmark.seal",
        text: """
          Change: strengthen Rust workspace verification
          Because: generated projects should have fmt, clippy, tests, build, run, and visual verification available in Cargo
          Done when: `cargo run -p xtask -- verify` passes and desktop visual verification shows a screenshot
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
        title: "Project Tour",
        systemImage: "map",
        text: """
          Change: make the project easier for a new user to inspect
          Because: users need a quick way to understand what matters before requesting work
          Done when: Compass shows the important areas and a clear next action
          """
      )
    }
  }
}
