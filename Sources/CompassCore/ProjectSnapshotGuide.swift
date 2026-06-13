import Foundation

package struct ProjectSnapshotClipboardPayload: Equatable, Sendable {
  package static let textLimit = 6_500
  private static let rowLimit = 7
  private static let draftHighlightLimit = 3

  package var text: String

  package init(
    projectName: String,
    runGuide: ProjectRunControlGuide,
    draftGuide: DraftIntakeGuide,
    settingsGuide: AgentSettingsGuide,
    visionGuide: ProjectVisionGuide? = nil,
    recoveryGuide: ProjectRecoveryGuide? = nil,
    historyGuide: PlanSessionHistoryGuide? = nil
  ) {
    var sections: [String] = [
      "Compass Project Snapshot",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded project state. Do not invent repository state, "
        + "credentials, hidden drafts, completed work, verification results, or model output.",
      "- Use Run readiness and Primary action before starting work; disabled run modes stay "
        + "disabled until the named blocker changes.",
      "- If Project recovery appears, follow it before retrying failed work.",
      "- Use Project vision and visible run history as guidance, not new scope. Keep missing "
        + "signals visible instead of silently filling them in.",
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

    if let recoveryGuide, !recoveryGuide.isEmpty {
      Self.appendProjectRecovery(guide: recoveryGuide, to: &sections)
    }
    if let visionGuide {
      Self.appendProjectVision(guide: visionGuide, to: &sections)
    }
    Self.appendDraftQueue(guide: draftGuide, to: &sections)
    if let historyGuide {
      Self.appendRunHistory(guide: historyGuide, to: &sections)
    }
    Self.appendRuntime(guide: settingsGuide, to: &sections)

    text = ProjectSnapshotClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  package var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func appendProjectRecovery(
    guide: ProjectRecoveryGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Project recovery:")
    sections.append("- Plan: \(guide.title)")

    for step in guide.steps {
      sections.append("- \(step.title): \(singleLine(step.detail, limit: 220))")
    }
  }

  private static func appendProjectVision(
    guide: ProjectVisionGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Project vision:")
    sections.append("- Status: \(guide.title) - \(guide.detail)")
    sections.append("- Score: \(guide.scoreLabel)")
    sections.append("- Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)")
    sections.append("- Signals present: \(guide.satisfiedSignalText)")
    sections.append("- Missing signals: \(guide.missingSignalText)")

    guard !guide.visionPreview.isEmpty else { return }

    sections.append("- Vision preview: \(singleLine(guide.visionPreview, limit: 520))")
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
      sections.append(
        "- Queue visibility: first \(guide.entries.count) of \(guide.totalEntryCount) checked; \(guide.hiddenCountSentence) in the raw draft list."
      )
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

  private static func appendRuntime(
    guide: AgentSettingsGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Runtime readiness:")
    sections.append("- Status: \(guide.title) (\(guide.tone.rawValue))")
    sections.append("- Action: \(guide.actionLabel)")
    sections.append("- Detail: \(guide.detail)")
    sections.append(
      "- Runtime coverage: \(guide.runtimeCoverage.label) - \(guide.runtimeCoverage.detail)")

    guard !guide.rows.isEmpty else { return }

    sections.append("Runtime rows:")
    for row in guide.rows.prefix(rowLimit) {
      sections.append("- [\(row.status.rawValue)] \(row.label): \(row.detail)")
    }
  }

  private static func appendRunHistory(
    guide: PlanSessionHistoryGuide,
    to sections: inout [String]
  ) {
    sections.append("")
    sections.append("Run history:")
    sections.append("- Status: \(guide.title) - \(guide.detail)")
    sections.append("- Visible runs: \(guide.statusLabel)")
    sections.append(
      "- Audit coverage: \(guide.auditCoverage.label) - \(guide.auditCoverage.detail)")

    guard !guide.facts.isEmpty else { return }

    sections.append("History facts:")
    for fact in guide.facts {
      sections.append("- \(fact.label): \(fact.detail)")
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
    let normalized =
      value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return StringUtils.boundedText(normalized, limit: limit)
  }
}

private enum ProjectSnapshotClipboardText {
  package static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
