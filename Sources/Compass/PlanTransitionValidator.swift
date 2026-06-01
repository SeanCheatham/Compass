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
  var rejectedAcceptanceChecks: [String]
  var vagueAcceptanceChecks: [String]

  init(
    message: String,
    reason: Reason = .unknown,
    missingLabels: [String] = [],
    rejectedVerify: String? = nil,
    rejectedAcceptanceChecks: [String] = [],
    vagueAcceptanceChecks: [String] = []
  ) {
    self.message = message
    self.reason = reason
    self.missingLabels = missingLabels
    self.rejectedVerify = rejectedVerify
    self.rejectedAcceptanceChecks = rejectedAcceptanceChecks
    self.vagueAcceptanceChecks = vagueAcceptanceChecks
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
    guard let verify = PlanVerifyCommandPolicy.normalizedCommand(immediate.verify) else {
      throw PlanTransitionValidationError(
        message:
          "Plan returned an empty verify command. Refusing to overwrite state.json.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: nil
      )
    }
    if PlanVerifyCommandPolicy.isPlaceholder(verify) {
      throw PlanTransitionValidationError(
        message:
          "Plan returned placeholder verify command `\(verify)`. Refusing to overwrite state.json.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: verify
      )
    }
    if let coverageError = ForgeVerifyValidator.coverageViolation(
      verify: verify,
      profile: forgeProfile
    ) {
      throw PlanTransitionValidationError(
        message: coverageError,
        reason: .coverageRequirement,
        missingLabels: ["Coverage-ready verify command"],
        rejectedVerify: verify
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
      let rejectedAcceptanceChecks = handoffDigest.commandOnlyAcceptanceChecks
      let vagueAcceptanceChecks = handoffDigest.vagueAcceptanceChecks
      let acceptanceRepairDetail = acceptanceRepairDetail(
        missingLabels: requiredMissing,
        commandOnlyChecks: rejectedAcceptanceChecks,
        vagueChecks: vagueAcceptanceChecks
      )
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff that is not executable enough for Develop. Missing \(missing).\(acceptanceRepairDetail) Write `immediate.plan` with short Markdown sections named Outcome and Acceptance checks; include Why it matters when it helps the non-engineer owner. The acceptance checks should state observable finish-line behavior Develop can verify.",
        reason: .weakHandoff,
        missingLabels: requiredMissing,
        rejectedAcceptanceChecks: rejectedAcceptanceChecks,
        vagueAcceptanceChecks: vagueAcceptanceChecks
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

  private static func formattedRejectedChecks(_ checks: [String]) -> String {
    checks.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
  }

  private static func acceptanceRepairDetail(
    missingLabels: [String],
    commandOnlyChecks: [String],
    vagueChecks: [String]
  ) -> String {
    guard missingLabels.contains("Acceptance checks") else { return "" }

    var details: [String] = []
    if !commandOnlyChecks.isEmpty {
      details.append(
        "Acceptance checks cannot be only verify commands (\(formattedRejectedChecks(commandOnlyChecks))). Put shell commands in `state.immediate.verify`, and describe observable behavior or UI state in `state.immediate.plan`."
      )
    }
    if !vagueChecks.isEmpty {
      details.append(
        "Acceptance checks are too vague (\(formattedRejectedChecks(vagueChecks))). Replace them with specific behavior, UI state, or test-proven signals Develop can verify."
      )
    }

    guard !details.isEmpty else { return "" }
    return " " + details.joined(separator: " ")
  }
}
