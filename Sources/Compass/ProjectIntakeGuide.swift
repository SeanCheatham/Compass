import Foundation

struct ProjectIntakeGuide: Equatable, Sendable {
  static let detailLimit = 260
  static let stepDetailLimit = 190
  static let handoffLimit = 2_800
  static let identifierLimit = 1_200

  struct Step: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
    var isPrimary: Bool
  }

  struct Signal: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var systemImage: String
  }

  var projectCount: Int
  var title: String
  var statusLabel: String
  var detail: String
  var actionLabel: String
  var systemImageName: String
  var steps: [Step]
  var signals: [Signal]
  var narrationIdentifier: String

  var allowsNarration: Bool {
    !narrationIdentifier.isEmpty
  }

  init(projectCount rawProjectCount: Int) {
    projectCount = max(0, rawProjectCount)

    if projectCount == 0 {
      title = "Add Your First Project"
      statusLabel = "No projects yet"
      detail =
        "Choose any Git repository you want Compass to improve. It can be an app, a package, or a fresh idea repo as long as Git can identify its root."
      actionLabel = "Add Project"
      systemImageName = "folder.badge.plus"
      steps = [
        Step(
          id: "choose-git-folder",
          title: "Choose a Git folder",
          detail:
            "Pick the repository root or any folder inside it; Compass resolves the Git root before saving the project.",
          systemImage: "folder.badge.plus",
          isPrimary: true
        ),
        Step(
          id: "capture-project-vision",
          title: "Capture the vision",
          detail:
            "After adding the repo, sketch who it helps, what pain it removes, how success should look, and any must-have guardrails in Project Vision.",
          systemImage: "scope",
          isPrimary: false
        ),
        Step(
          id: "write-first-draft",
          title: "Write a first draft",
          detail:
            "Use Drafts for plain-language requests like \"make onboarding clearer\" or \"add a weekly export\".",
          systemImage: "text.bubble",
          isPrimary: false
        ),
        Step(
          id: "let-compass-verify",
          title: "Let Compass verify",
          detail:
            "Compass turns the goal into a plan, develops in the private workspace, and checks the result before the work is treated as done.",
          systemImage: "checkmark.seal",
          isPrimary: false
        ),
      ]
    } else {
      title = "Choose a Project"
      statusLabel = projectCount == 1 ? "1 project available" : "\(projectCount) projects available"
      detail =
        "Select a repository in the sidebar to open its live run controls, drafts, world map, and verification history."
      actionLabel = "Add Missing Repo"
      systemImageName = "sidebar.left"
      steps = [
        Step(
          id: "select-sidebar-row",
          title: "Select a sidebar row",
          detail:
            "Each project keeps its own drafts, runs, sessions, and storage state so work stays separated.",
          systemImage: "sidebar.left",
          isPrimary: true
        ),
        Step(
          id: "add-missing-repo",
          title: "Add missing repos",
          detail:
            "Use Add Project when the repository you want is not listed yet.",
          systemImage: "folder.badge.plus",
          isPrimary: false
        ),
        Step(
          id: "check-sandbox",
          title: "Check the Sandbox",
          detail:
            "Open Sandbox when Compass reports that the private VM needs attention before agent work can continue.",
          systemImage: "shippingbox",
          isPrimary: false
        ),
      ]
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    steps = steps.map { step in
      Step(
        id: step.id,
        title: StringUtils.boundedText(step.title, limit: 72),
        detail: StringUtils.boundedText(step.detail, limit: Self.stepDetailLimit),
        systemImage: step.systemImage,
        isPrimary: step.isPrimary
      )
    }
    signals = Self.projectSignals()
    narrationIdentifier = Self.narrationIdentifier(
      projectCount: projectCount,
      title: title,
      statusLabel: statusLabel,
      detail: detail,
      actionLabel: actionLabel,
      steps: steps,
      signals: signals
    )
  }

  private static func projectSignals() -> [Signal] {
    [
      Signal(
        id: "git",
        label: "Git history",
        detail: "Compass needs a repository so it can inspect changes and keep factory state nearby.",
        systemImage: "point.3.connected.trianglepath.dotted"
      ),
      Signal(
        id: "verification",
        label: "A way to verify",
        detail:
          "Tests, build commands, or a clear manual check help the agent prove the change works.",
        systemImage: "checklist.checked"
      ),
      Signal(
        id: "project-vision",
        label: "Project vision",
        detail:
          "Short audience, problem, success, and guardrail notes give Plan and Reflect a stable north star.",
        systemImage: "scope"
      ),
      Signal(
        id: "plain-language-goal",
        label: "Plain-language goal",
        detail:
          "The user does not need a technical spec; Compass can refine rough requests into better drafts.",
        systemImage: "quote.bubble"
      ),
    ]
  }

  private static func narrationIdentifier(
    projectCount: Int,
    title: String,
    statusLabel: String,
    detail: String,
    actionLabel: String,
    steps: [Step],
    signals: [Signal]
  ) -> String {
    let raw = [
      "count:\(projectCount)",
      "title:\(title)",
      "status:\(statusLabel)",
      "detail:\(detail)",
      "action:\(actionLabel)",
      "steps:\(steps.map { "\($0.id):\($0.title):\($0.detail)" }.joined(separator: "|"))",
      "signals:\(signals.map { "\($0.id):\($0.label):\($0.detail)" }.joined(separator: "|"))",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

struct ProjectIntakeClipboardPayload: Equatable, Sendable {
  var text: String

  init(guide: ProjectIntakeGuide) {
    var sections: [String] = [
      "Compass Project Intake Handoff",
      "",
      "Recipient instructions:",
      "- Help the user add or select a real Git repository. Do not invent a repo path.",
      "- Keep guidance plain-language and product-focused; the user may not know build tooling.",
      "- After a project is selected, capture Project Vision notes, use Drafts for goals, and let Compass plan, develop, and verify.",
      "",
      "Status: \(guide.statusLabel)",
      "Recommended action: \(guide.actionLabel)",
      "Summary: \(guide.detail)",
      "Project count: \(guide.projectCount)",
      "",
      "Next steps:",
    ]

    sections += guide.steps.map { step in
      "- \(step.title): \(step.detail)"
    }

    sections += [
      "",
      "Good project signals:",
    ]

    sections += guide.signals.map { signal in
      "- \(signal.label): \(signal.detail)"
    }

    text = ProjectIntakeClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: ProjectIntakeGuide.handoffLimit
    )
  }
}

private enum ProjectIntakeClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
