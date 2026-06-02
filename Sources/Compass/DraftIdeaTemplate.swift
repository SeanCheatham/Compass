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
      firstRunIdea,
      feedbackIdea,
      languageIdea(for: profile.primaryLanguage),
    ]
  }

  private static let firstRunIdea = DraftIdeaTemplate(
    id: "first-run",
    title: "First Run",
    systemImage: "figure.walk.circle",
    text: """
      Change: make the first-run path easier to understand
      Because: new users need to know the next safe action without developer vocabulary
      Done when: the main screen shows the next action clearly and existing tests pass
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
        id: "swift-native-polish",
        title: "Native Polish",
        systemImage: "macwindow",
        text: """
          Change: add a native macOS polish pass to the main workflow
          Because: Compass should feel like a focused desktop app instead of a generic tool
          Done when: the affected view uses clear controls, accessible labels, and existing Swift tests pass
          """
      )
    case .typeScriptJavaScript:
      return DraftIdeaTemplate(
        id: "web-state-clarity",
        title: "State Clarity",
        systemImage: "rectangle.3.group",
        text: """
          Change: make the primary UI state easier to scan
          Because: users need to compare statuses and decide what to do next quickly
          Done when: the active view shows ready, blocked, and in-progress states clearly
          """
      )
    case .rust:
      return DraftIdeaTemplate(
        id: "rust-cli-feedback",
        title: "CLI Feedback",
        systemImage: "terminal",
        text: """
          Change: make command-line feedback easier to act on
          Because: users need clear success and failure messages without reading implementation details
          Done when: the relevant command shows the outcome, the blocker, and the next step
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
