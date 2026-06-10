import Foundation

struct ProjectRecoveryGuide: Equatable {
  static let detailLimit = 180
  static let identifierLimit = 1_200

  var title: String
  var steps: [Step]
  var narrationIdentifier: String

  var isEmpty: Bool {
    steps.isEmpty
  }

  var allowsNarration: Bool {
    !isEmpty
  }

  init(status: ProjectReliabilityStatus) {
    guard let kind = status.primaryKind else {
      title = ""
      steps = []
      narrationIdentifier = ""
      return
    }

    switch kind {
    case .rejectedPlan:
      let recovery = Self.rejectedPlanRecovery(for: status.detail)
      title = "Repair the Plan output"
      steps = [
        Step(
          title: "Read the rejection",
          detail: status.detail
        ),
        Step(
          title: recovery.title,
          detail: recovery.detail
        ),
        Step(
          title: status.actionLabel,
          detail: recovery.retryDetail
        ),
      ]
    case .developBlocked:
      title = "Give Develop the missing input"
      steps = [
        Step(title: "Read the blocker", detail: status.detail),
        Step(
          title: "Add the missing context",
          detail: "Provide the credential, fixture, file, or decision named by the blocker."
        ),
        Step(
          title: status.actionLabel,
          detail: "Retry once the missing input is available."
        ),
      ]
    case .developFailed:
      let insight = DevelopFailureInsight(detail: status.detail)
      title = insight.guideTitle
      steps = [
        Step(title: insight.inspectTitle, detail: insight.inspectDetail),
        Step(
          title: insight.repairTitle,
          detail: insight.repairDetail
        ),
        Step(title: status.actionLabel, detail: insight.retryDetail),
      ]
    case .failedVerify:
      let insight = VerifyFailureInsight(detail: status.detail, metadata: status.metadata)
      let retryDetail = Self.failedVerifyRetryDetail(
        actionLabel: status.actionLabel,
        insight: insight
      )
      title = "Fix the failing check"
      steps = [
        Step(title: insight.inspectTitle, detail: insight.inspectDetail),
        Step(
          title: insight.repairTitle,
          detail: insight.repairDetail
        ),
        Step(
          title: status.actionLabel,
          detail: retryDetail
        ),
      ]
    case .dirtyWorktree:
      title = "Finish the pending files"
      steps = [
        Step(
          title: "Review pending file changes",
          detail: status.metadata ?? "Check the files that changed."),
        Step(
          title: "Choose what belongs",
          detail:
            "Commit intended edits, add expected generated files to the ignore list, or remove accidental leftovers."
        ),
        Step(title: status.actionLabel, detail: "Retry when no pending file changes remain."),
      ]
    case .promotionFailed:
      title = "Resolve the promotion"
      steps = [
        Step(
          title: "Check the sandbox branch", detail: status.metadata ?? "Inspect promotion output."),
        Step(
          title: "Reconcile branch state",
          detail: "Fast-forward, rebase, or choose the correct promoted commit before retrying."
        ),
        Step(title: status.actionLabel, detail: "Promote only after the branch is unambiguous."),
      ]
    case .resumeDevelop:
      title = "Continue the selected build"
      steps = [
        Step(title: "Review the ready slice", detail: status.detail),
        Step(
          title: status.actionLabel, detail: "Start Develop when the plan still matches the goal."),
      ]
    }

    steps = steps.map { step in
      Step(
        title: Self.bounded(step.title, limit: 80),
        detail: Self.bounded(step.detail, limit: Self.detailLimit)
      )
    }
    narrationIdentifier = Self.narrationIdentifier(title: title, steps: steps)
  }

  struct Step: Identifiable, Equatable {
    var title: String
    var detail: String

    var id: String {
      "\(title)\n\(detail)"
    }
  }

  private struct RejectedPlanRecovery: Equatable {
    var title: String
    var detail: String
    var retryDetail: String
  }

  private static func rejectedPlanRecovery(for detail: String) -> RejectedPlanRecovery {
    let normalized = detail.lowercased()
    let retryDetail = "Let Plan resubmit one smaller executable slice before Develop starts."

    if normalized.contains("placeholder verify command")
      || normalized.contains("failure-masking verify command")
    {
      return RejectedPlanRecovery(
        title: "Replace the verify command",
        detail:
          "Use a real command Compass can run; do not use no-op commands or fallback clauses such as "
          + "true, exit 0, echo no tests, none, n/a, not-running-tests, || true, or ; true.",
        retryDetail: retryDetail
      )
    }

    if normalized.contains("plan should replace the verify command")
      || normalized.contains("planned command is wrong or out of scope")
      || normalized.contains("verify was skipped because develop reported")
    {
      return RejectedPlanRecovery(
        title: "Replace the verify command",
        detail:
          "Choose a verify command that matches the current slice before asking Develop to run again.",
        retryDetail: retryDetail
      )
    }

    if normalized.contains("must collect test coverage")
      || normalized.contains("enable-code-coverage")
      || normalized.contains("-coverprofile")
      || normalized.contains("coverage.reporter")
    {
      return RejectedPlanRecovery(
        title: "Use coverage-ready verify",
        detail:
          "Include the coverage flag or artifact named in the rejection instead of switching to a build-only check.",
        retryDetail: retryDetail
      )
    }

    if normalized.contains("returned no immediate work") {
      return RejectedPlanRecovery(
        title: "Choose one immediate slice",
        detail:
          "Keep the remaining runway and select the smallest next item instead of returning empty Immediate Work.",
        retryDetail: retryDetail
      )
    }

    if normalized.contains("acceptance checks are too vague")
      || normalized.contains("vague acceptance checks")
    {
      return RejectedPlanRecovery(
        title: "Replace vague acceptance checks",
        detail:
          "Name the specific behavior, UI state, or test-proven signal Develop should make true.",
        retryDetail: retryDetail
      )
    }

    if normalized.contains("not executable enough for develop")
      || normalized.contains("missing acceptance checks")
      || normalized.contains("missing outcome")
    {
      return RejectedPlanRecovery(
        title: "Add the missing handoff fields",
        detail:
          "Include Outcome and Acceptance checks; add Why it matters when it helps the owner understand the value.",
        retryDetail: retryDetail
      )
    }

    if normalized.contains("clear a non-empty")
      || normalized.contains("shrink completed")
      || normalized.contains("overwrite state.json")
    {
      return RejectedPlanRecovery(
        title: "Preserve the existing runway",
        detail:
          "Do not clear completed history, candidates, strategic context, or open questions unless the previous slice really shipped or stale work is explicitly retired.",
        retryDetail: retryDetail
      )
    }

    return RejectedPlanRecovery(
      title: "Return executable Immediate Work",
      detail:
        "Include Outcome, Acceptance checks, and a real verify command; add Why it matters when useful.",
      retryDetail: retryDetail
    )
  }

  private static func failedVerifyRetryDetail(
    actionLabel: String,
    insight: VerifyFailureInsight
  ) -> String {
    let normalizedAction = actionLabel.lowercased()
    if normalizedAction.contains("plan") {
      return
        "Ask Plan to create one repair slice from the captured verify output before Develop runs again."
    }

    return insight.retryDetail
  }

  private static func narrationIdentifier(title: String, steps: [Step]) -> String {
    let raw = [
      "title:\(title)",
      "steps:\(steps.map { "\($0.title):\($0.detail)" }.joined(separator: "|"))",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }

  private static func bounded(_ text: String, limit: Int) -> String {
    let normalized = StringUtils.boundedText(text, limit: Int.max)
    guard limit > 0 else { return "" }
    guard normalized.count > limit else { return normalized }
    guard limit > 3 else { return String(normalized.prefix(limit)) }

    return normalized.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct ProjectRecoveryClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_000

  var text: String

  init(status: ProjectReliabilityStatus, guide: ProjectRecoveryGuide) {
    guard !status.isEmpty, !guide.isEmpty else {
      text = ""
      return
    }

    var sections: [String] = [
      "Compass Recovery Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded recovery context. Do not invent files, commands, "
        + "credentials, outcomes, or extra scope.",
      "- Follow the recovery steps in order. If a step asks Plan to retry, return one "
        + "executable Immediate Work handoff before Develop.",
      "- If credentials, files, or decisions are missing, ask for that input instead of "
        + "pretending it exists.",
      "",
      "Status: \(status.primaryCue)",
      "Action: \(status.actionLabel)",
      "Cue count: \(status.countLabel)",
    ]

    if let metadata = status.metadata {
      sections.append("Metadata: \(metadata)")
    }

    sections.append("")
    sections.append("Failure detail:")
    sections.append(status.detail.isEmpty ? "No failure detail captured." : status.detail)
    sections.append("")
    sections.append("Recovery plan: \(guide.title)")

    for (index, step) in guide.steps.enumerated() {
      sections.append("\(index + 1). \(step.title): \(step.detail)")
    }

    text = ProjectRecoveryClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum ProjectRecoveryClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
