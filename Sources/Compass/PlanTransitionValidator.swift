import Foundation

struct PlanTransitionValidationError: LocalizedError, Equatable {
  enum Reason: Equatable, Sendable {
    case unknown
    case invalidStateMutation
    case noImmediateWork
    case placeholderVerify
    case coverageRequirement
    case weakHandoff
    case multiExperimentImmediate
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
    from current: PlanState,
    to next: PlanState,
    forgeProfile: ForgeProfile? = nil,
    productTournamentConfig: ProductTournamentConfig? = nil
  )
    throws
  {
    if !current.actionableCandidates.isEmpty
      && next.actionableCandidates.isEmpty
      && next.completed.count == current.completed.count
    {
      throw PlanTransitionValidationError(
        message:
          "Plan tried to clear all actionable candidates without recording a completion. Refusing to overwrite state.json.",
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
            "Plan returned no immediate work while \(formattedFields(remainingFields)) still contains actionable candidates. Choose one commit-sized Immediate Plan instead; `immediate: null` is only valid when there are no available or active candidates and no useful repo-originated slice.",
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
    if PlanVerifyCommandPolicy.masksFailures(verify) {
      throw PlanTransitionValidationError(
        message:
          "Plan returned failure-masking verify command `\(verify)`. Verify commands must fail when the check fails; remove fallback no-op clauses such as \(PlanVerifyCommandPolicy.failureMaskingExamples). Refusing to overwrite state.json.",
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
    if immediate.selectedBecause?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff without `selectedBecause`. Explain why this slice is the right next step so the user can audit planning choice quality.",
        reason: .weakHandoff,
        missingLabels: ["Selection rationale"]
      )
    }
    if immediate.source == nil {
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff without `source`. Set `source` to draft, feedback, candidate, focus, repository, or repair so Compass can explain why this work was selected.",
        reason: .weakHandoff,
        missingLabels: ["Selection source"]
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

    try validateProductTournamentScope(
      immediate: immediate,
      productTournamentConfig: productTournamentConfig
    )
  }

  private static func remainingPlanFields(in state: PlanState, label: String) -> [String] {
    var fields: [String] = []
    if !state.actionableCandidates.isEmpty {
      fields.append("\(label) candidates")
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

  private static func validateProductTournamentScope(
    immediate: PlanNext,
    productTournamentConfig: ProductTournamentConfig?
  ) throws {
    guard let productTournamentConfig, productTournamentConfig.experiments.count > 1 else { return }
    let handoffText = [
      immediate.plan,
      immediate.selectedBecause,
      immediate.candidateID,
      immediate.verify,
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
    guard !isSharedProductTournamentInfrastructureScope(handoffText) else { return }

    let mentioned = mentionedExperimentIDs(
      in: handoffText,
      productTournamentConfig: productTournamentConfig
    )
    guard mentioned.count <= 1 else {
      throw PlanTransitionValidationError(
        message:
          "Plan immediate handoff mentions multiple tournament experiments (\(mentioned.joined(separator: ", "))). Choose one experiment for the next commit-sized slice, or explicitly scope the handoff to shared tournament experiment infrastructure.",
        reason: .multiExperimentImmediate,
        missingLabels: ["Single experiment scope"]
      )
    }
  }

  private static func mentionedExperimentIDs(
    in text: String,
    productTournamentConfig: ProductTournamentConfig
  ) -> [String] {
    let normalizedText = normalizedForProductTournamentMatch(text)
    guard !normalizedText.isEmpty else { return [] }

    var matches: [String] = []
    for experiment in productTournamentConfig.experiments {
      let tokens = [
        experiment.id,
        experiment.branchName,
        experiment.worktreeID,
        experiment.title,
      ]
      .map(normalizedForProductTournamentMatch)
      .filter { $0.count >= 3 }

      if tokens.contains(where: { normalizedText.contains($0) }) {
        matches.append(experiment.id)
      }
    }
    return Array(Set(matches)).sorted()
  }

  private static func isSharedProductTournamentInfrastructureScope(_ text: String) -> Bool {
    let normalized = normalizedForProductTournamentMatch(text)
    let sharedSignals = [
      "shared experiment infrastructure",
      "shared product tournament infrastructure",
      "cross experiment infrastructure",
      "cross experiment",
      "common experiment infrastructure",
      "common product tournament infrastructure",
      "shared simulation harness",
      "common simulation harness",
    ]
    return sharedSignals.contains { normalized.contains($0) }
  }

  private static func normalizedForProductTournamentMatch(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9/._-]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
