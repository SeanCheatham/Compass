import Foundation

package struct ProjectIntakeGuide: Equatable, Sendable {
  package static let detailLimit = 260
  package static let stepDetailLimit = 190
  package static let handoffLimit = 2_800
  package static let identifierLimit = 1_200

  package struct Step: Identifiable, Equatable, Sendable {
    package var id: String
    package var title: String
    package var detail: String
    package var systemImage: String
    package var isPrimary: Bool
  }

  package struct Signal: Identifiable, Equatable, Sendable {
    package var id: String
    package var label: String
    package var detail: String
    package var systemImage: String
  }

  package var projectCount: Int
  package var title: String
  package var statusLabel: String
  package var detail: String
  package var actionLabel: String
  package var systemImageName: String
  package var steps: [Step]
  package var signals: [Signal]
  package var narrationIdentifier: String

  package var allowsNarration: Bool {
    !narrationIdentifier.isEmpty
  }

  package init(projectCount rawProjectCount: Int) {
    projectCount = max(0, rawProjectCount)

    if projectCount == 0 {
      title = "Add Your First Project"
      statusLabel = "No projects yet"
      detail =
        "Choose a Git repository where Compass can explore a user pain. It can be an app, a package, or a fresh experiment repo as long as Git can identify its root."
      actionLabel = "Add Project"
      systemImageName = "folder.badge.plus"
      steps = [
        Step(
          id: "choose-git-folder",
          title: "Choose a Git folder",
          detail:
            "Pick the project folder or any folder inside it; Compass finds the repository root before saving the project.",
          systemImage: "folder.badge.plus",
          isPrimary: true
        ),
        Step(
          id: "capture-project-vision",
          title: "Describe the pain",
          detail:
            "After adding the repo, answer \"What user pain should Compass explore?\" Include who feels it, what they do today, current alternatives, success signals, and guardrails in Project Vision.",
          systemImage: "scope",
          isPrimary: false
        ),
        Step(
          id: "write-first-draft",
          title: "Seed the proof loop",
          detail:
            "Use Drafts for plain-language pain notes, proof ideas, or validation questions Compass should turn into proof-loop state.",
          systemImage: "checkmark.seal",
          isPrimary: false
        ),
        Step(
          id: "let-compass-verify",
          title: "Let Compass verify",
          detail:
            "Compass turns the goal into a plan, develops in the container runtime, and checks the result before the work is treated as done.",
          systemImage: "checkmark.seal",
          isPrimary: false
        ),
      ]
    } else {
      title = "Choose a Project"
      statusLabel = projectCount == 1 ? "1 project available" : "\(projectCount) projects available"
      detail =
        "Select a repository in the sidebar to open Activity, live run controls, drafts, and verification history."
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
        detail:
          "Compass needs a repository so it can inspect changes and keep factory state nearby.",
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
        label: "Task context",
        detail:
          "Short notes on users, desired outcomes, constraints, acceptance signals, and guardrails give Plan a stable north star.",
        systemImage: "scope"
      ),
      Signal(
        id: "plain-language-goal",
        label: "Task or validation note",
        detail:
          "The user does not need a technical spec; Compass can refine rough pain, proof, and validation notes into proof-loop-ready drafts.",
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

package struct ProjectIntakeClipboardPayload: Equatable, Sendable {
  package var text: String

  package init(guide: ProjectIntakeGuide) {
    var sections: [String] = [
      "Compass Project Intake Handoff",
      "",
      "Recipient instructions:",
      "- Help the user add or select a real Git repository. Do not invent a repo path.",
      "- Keep guidance plain-language and product-focused; the user may not know build tooling.",
      "- After a project is selected, capture the user pain, current workflow, alternatives, success signals, and guardrails in Project Vision; use Drafts for proof ideas or validation questions, and let Compass discover, plan, develop, and verify.",
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
  package static func boundedMultilineText(_ text: String, limit: Int) -> String {
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
