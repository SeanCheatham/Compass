import Foundation

struct PlanTransitionValidationError: LocalizedError, Equatable {
  enum Reason: Equatable, Sendable {
    case unknown
    case invalidStateMutation
    case noImmediateWork
    case placeholderVerify
    case coverageRequirement
    case weakHandoff
  }

  var message: String
  var reason: Reason
  var missingLabels: [String]
  var rejectedVerify: String?

  init(
    message: String,
    reason: Reason = .unknown,
    missingLabels: [String] = [],
    rejectedVerify: String? = nil
  ) {
    self.message = message
    self.reason = reason
    self.missingLabels = missingLabels
    self.rejectedVerify = rejectedVerify
  }

  var errorDescription: String? {
    message
  }
}

enum PlanTransitionValidator {
  static func validate(
    from current: PlanState, to next: PlanState, forgeProfile: ForgeProfile? = nil
  )
    throws
  {
    if !current.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && next.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && next.completed.count == current.completed.count
    {
      throw PlanTransitionValidationError(
        message:
          "Plan tried to clear a non-empty midTerm queue without recording a completion. Refusing to overwrite state.json.",
        reason: .invalidStateMutation
      )
    }

    guard let immediate = next.immediate else {
      let remainingFields =
        remainingPlanFields(in: current, label: "current")
        + remainingPlanFields(in: next, label: "proposed")
      guard remainingFields.isEmpty else {
        throw PlanTransitionValidationError(
          message:
            "Plan returned no immediate work while \(formattedFields(remainingFields)) still contains work. Choose one commit-sized Immediate Plan instead; `immediate: null` is only valid when the project had no remaining midTerm or longTerm work before this pass and still has none.",
          reason: .noImmediateWork
        )
      }
      return
    }
    let verify = immediate.verify.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let rejectedVerifyCommands = Set([
      "true",
      "not-running-tests",
      "not running tests",
      "none",
      "n/a",
    ])
    if rejectedVerifyCommands.contains(verify) {
      throw PlanTransitionValidationError(
        message:
          "Plan returned placeholder verify command `\(immediate.verify)`. Refusing to overwrite state.json.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: immediate.verify
      )
    }
    if let coverageError = ForgeVerifyValidator.coverageViolation(
      verify: immediate.verify,
      profile: forgeProfile
    ) {
      throw PlanTransitionValidationError(
        message: coverageError,
        reason: .coverageRequirement,
        missingLabels: ["Coverage-ready verify command"],
        rejectedVerify: immediate.verify
      )
    }

    let handoffDigest = PlanHandoffDigest(plan: immediate.plan)
    guard handoffDigest.status == .ready else {
      let requiredMissing = handoffDigest.missingPieces
        .filter { $0.isRequired }
        .map(\.label)
      let missing =
        requiredMissing.isEmpty
        ? "a concrete Outcome and Acceptance checks"
        : requiredMissing.joined(separator: " and ")
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff that is not executable enough for Develop. Missing \(missing). Write `immediate.plan` with short Markdown sections named Outcome and Acceptance checks; include Why it matters when it helps the non-engineer owner. The acceptance checks should state observable finish-line behavior Develop can verify.",
        reason: .weakHandoff,
        missingLabels: requiredMissing
      )
    }
  }

  private static func remainingPlanFields(in state: PlanState, label: String) -> [String] {
    var fields: [String] = []
    if !state.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fields.append("\(label) midTerm")
    }
    if !state.longTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      fields.append("\(label) longTerm")
    }
    return fields
  }

  private static func formattedFields(_ fields: [String]) -> String {
    let uniqueFields = Array(Set(fields)).sorted()
    switch uniqueFields.count {
    case 0:
      return "planning state"
    case 1:
      return uniqueFields[0]
    case 2:
      return "\(uniqueFields[0]) and \(uniqueFields[1])"
    default:
      return uniqueFields.dropLast().joined(separator: ", ")
        + ", and \(uniqueFields.last ?? "planning state")"
    }
  }
}
