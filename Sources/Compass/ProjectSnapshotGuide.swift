import Foundation

struct ProjectSnapshotClipboardPayload: Equatable, Sendable {
  static let textLimit = 5_000
  private static let rowLimit = 7
  private static let draftHighlightLimit = 3

  var text: String

  init(
    projectName: String,
    runGuide: ProjectRunControlGuide,
    draftGuide: DraftIntakeGuide,
    assumptionGuide: AssumptionReviewGuide,
    settingsGuide: AgentSettingsGuide
  ) {
    var sections: [String] = [
      "Compass Project Snapshot",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded project state. Do not invent repository state, "
        + "credentials, hidden drafts, completed work, verification results, or model output.",
      "- Use Run readiness and Primary action before starting work; disabled run modes stay "
        + "disabled until the named blocker changes.",
      "- Use Draft queue and Assumption memory as guidance, not new scope. Ready drafts can "
        + "feed Plan; tentative assumptions still need review.",
      "- Runtime credential values are intentionally omitted. Never ask the user to paste API "
        + "keys into chat.",
      "",
      "Project: \(Self.projectNameLabel(projectName))",
      "Snapshot focus: \(Self.snapshotFocus(runGuide: runGuide, draftGuide: draftGuide))",
      "",
      "Run readiness:",
      "- Status: \(runGuide.readiness.title) - \(runGuide.readiness.detail)",
      "- Run signal: \(runGuide.decisionBadge.label) - \(runGuide.decisionBadge.detail)",
      "- Primary action: \(Self.actionLine(runGuide.primaryOption))",
      "- Primary help: \(runGuide.primaryHelp)",
      "",
      "Run modes:",
    ]

    for option in runGuide.options {
      sections.append("- \(Self.actionLine(option))")
    }

    sections.append("")
    sections.append("Next run preview:")
    if runGuide.previewSteps.isEmpty {
      sections.append("- No preview steps are available.")
    } else {
      for step in runGuide.previewSteps {
        sections.append("- \(step.title): \(step.detail)")
      }
    }

    Self.appendDraftQueue(guide: draftGuide, to: &sections)
    Self.appendAssumptionMemory(guide: assumptionGuide, to: &sections)
    Self.appendRuntime(guide: settingsGuide, to: &sections)

    text = ProjectSnapshotClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func appendDraftQueue(
    guide: DraftIntakeGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Draft queue:")
    sections.append("- Status: \(guide.title)")
    sections.append("- Score: \(guide.scoreLabel)")
    sections.append("- Detail: \(guide.detail)")
    sections.append("- Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)")
    sections.append("- Plan scope: \(guide.planScope.summary)")
    sections.append("- Plan scope detail: \(guide.planScope.detail)")

    if guide.isCapped {
      sections.append("- Queue visibility: first \(guide.entries.count) of \(guide.totalEntryCount) checked; \(guide.hiddenCountSentence) in the raw draft list.")
    }

    guard !guide.entries.isEmpty else { return }

    sections.append("Draft highlights:")
    for entry in guide.entries.prefix(draftHighlightLimit) {
      sections.append(
        "- Draft #\(entry.number): \(entry.readiness.title) (\(entry.readiness.scoreLabel)) - \(Self.singleLine(entry.draft, limit: 180))"
      )
      sections.append("  Missing signals: \(entry.missingSignalText)")
    }

    let hiddenHighlightCount = guide.entries.count - min(guide.entries.count, draftHighlightLimit)
    if hiddenHighlightCount > 0 {
      sections.append("- ...\(hiddenHighlightCount) more visible draft highlights not shown")
    }
  }

  private static func appendAssumptionMemory(
    guide: AssumptionReviewGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Assumption memory:")
    sections.append("- Status: \(guide.title) - \(guide.detail)")
    sections.append("- Prompt effect: \(guide.promptEffect)")
    sections.append("- Prompt lane: \(guide.promptLane.label) - \(guide.promptLane.detail)")
    sections.append("- Review progress: \(guide.reviewProgress.label) - \(guide.reviewProgress.detail)")

    guard !guide.queue.isEmpty else { return }

    sections.append("Assumptions needing review:")
    for item in guide.queue {
      sections.append("- \(Self.singleLine(item.label, limit: 220))")
      sections.append("  Context: \(Self.singleLine(item.detail, limit: 240))")
    }
  }

  private static func appendRuntime(
    guide: AgentSettingsGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Runtime readiness:")
    sections.append("- Status: \(guide.title) (\(guide.tone.rawValue))")
    sections.append("- Action: \(guide.actionLabel)")
    sections.append("- Detail: \(guide.detail)")
    sections.append("- Runtime coverage: \(guide.runtimeCoverage.label) - \(guide.runtimeCoverage.detail)")

    guard !guide.rows.isEmpty else { return }

    sections.append("Runtime rows:")
    for row in guide.rows.prefix(rowLimit) {
      sections.append("- [\(row.status.rawValue)] \(row.label): \(row.detail)")
    }
  }

  private static func snapshotFocus(
    runGuide: ProjectRunControlGuide,
    draftGuide: DraftIntakeGuide
  ) -> String {
    if runGuide.primaryOption.isEnabled {
      return "\(runGuide.primaryOption.title) - \(runGuide.primaryOption.detail)"
    }

    if !draftGuide.isEmpty {
      return "\(draftGuide.nextAction.title) - \(draftGuide.nextAction.detail)"
    }

    return "\(runGuide.readiness.title) - \(runGuide.readiness.detail)"
  }

  private static func actionLine(_ option: ProjectRunControlGuide.Option) -> String {
    "\(option.title) (\(kindLabel(option.kind)), \(enabledLabel(option))) - \(option.detail)"
  }

  private static func kindLabel(_ kind: ProjectRunControlGuide.Kind) -> String {
    switch kind {
    case .loop:
      return "loop"
    case .planOnly:
      return "plan-only"
    case .developOnly:
      return "develop-only"
    }
  }

  private static func enabledLabel(_ option: ProjectRunControlGuide.Option) -> String {
    option.isEnabled ? "enabled" : "disabled"
  }

  private static func projectNameLabel(_ projectName: String) -> String {
    let name = singleLine(projectName, limit: 180)
    return name.isEmpty ? "Untitled project" : name
  }

  private static func singleLine(_ value: String, limit: Int) -> String {
    let normalized = value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return StringUtils.boundedText(normalized, limit: limit)
  }
}

private enum ProjectSnapshotClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
