import Foundation

struct ProjectRecoveryGuide: Equatable {
  static let detailLimit = 180

  var title: String
  var steps: [Step]

  var isEmpty: Bool {
    steps.isEmpty
  }

  init(status: ProjectReliabilityStatus) {
    guard let kind = status.primaryKind else {
      title = ""
      steps = []
      return
    }

    switch kind {
    case .rejectedPlan:
      title = "Repair the Plan handoff"
      steps = [
        Step(
          title: "Open Plan",
          detail: "Use the handoff repair guide on the Immediate Work panel."
        ),
        Step(
          title: "Add the missing fields",
          detail: "Include Outcome, Acceptance checks, and a real verify command."
        ),
        Step(
          title: status.actionLabel,
          detail: "Let Plan submit a smaller executable slice before Develop starts."
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
      title = "Retry with the captured failure"
      steps = [
        Step(title: "Keep the failure visible", detail: status.detail),
        Step(
          title: "Ask for a smaller fix",
          detail: "Have Develop address the first concrete error before broadening scope."
        ),
        Step(title: status.actionLabel, detail: "Compass will preserve the current plan context."),
      ]
    case .failedVerify:
      title = "Fix the failing check"
      steps = [
        Step(title: "Inspect verify output", detail: status.detail),
        Step(
          title: "Patch the failing behavior",
          detail: "Have Develop change code or tests only where the failure points."
        ),
        Step(
          title: status.actionLabel,
          detail: "Compass will rerun the planned verification command."
        ),
      ]
    case .dirtyWorktree:
      title = "Finish the pending files"
      steps = [
        Step(
          title: "Review source control", detail: status.metadata ?? "Check the pending changes."),
        Step(
          title: "Keep or discard intentionally",
          detail: "Commit wanted edits, ignore generated files, or remove accidental leftovers."
        ),
        Step(title: status.actionLabel, detail: "Retry when the working tree is clean."),
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
      title = "Continue the queued build"
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
  }

  struct Step: Identifiable, Equatable {
    var title: String
    var detail: String

    var id: String {
      "\(title)\n\(detail)"
    }
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
