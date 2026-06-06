import Foundation

struct TournamentAutomationPlanProofAuditDelta: Equatable, Sendable, Identifiable {
  var id: String { auditID }

  var auditID: String
  var endedAt: Double
  var experimentIDs: [String]
  var executedStepIDs: [String]
  var evidenceRunIDs: [String]
  var startingProofDebtCount: Int?
  var endingProofDebtCount: Int?
  var proofDebtDelta: Int?
  var startingProofDebtSummary: String?
  var endingProofDebtSummary: String?
  var stopReason: TournamentAutomationCycleAuditStopReason
  var userMessage: String

  init(audit: TournamentAutomationCycleAudit) {
    self.auditID = audit.id
    self.endedAt = audit.endedAt
    self.experimentIDs = audit.experimentIDs
    self.executedStepIDs = audit.executedStepIDs
    self.evidenceRunIDs = audit.evidenceRunIDs
    self.startingProofDebtCount = audit.startingProofDebtCount
    self.endingProofDebtCount = audit.endingProofDebtCount
    self.proofDebtDelta = audit.proofDebtDelta
    self.startingProofDebtSummary = audit.startingProofDebtSummary
    self.endingProofDebtSummary = audit.endingProofDebtSummary
    self.stopReason = audit.stopReason
    self.userMessage = audit.userMessage
  }

  var auditLine: String {
    let experiments =
      experimentIDs.isEmpty
      ? "no experiments"
      : "experiments \(experimentIDs.joined(separator: ", "))"
    let steps =
      executedStepIDs.isEmpty
      ? "no steps"
      : "steps \(executedStepIDs.prefix(3).joined(separator: ", "))"
    let startingSummary =
      startingProofDebtSummary.map {
        "; starting_plan_proof_debt \(Self.bounded($0, limit: 260))"
      } ?? ""
    let endingSummary =
      endingProofDebtSummary.map {
        "; ending_plan_proof_debt \(Self.bounded($0, limit: 260))"
      } ?? ""
    let runIDs =
      evidenceRunIDs.isEmpty
      ? ""
      : "; evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))"
    return
      "- \(Self.bounded(auditID, limit: 100)): \(experiments); \(steps); \(proofDebtChangeSummary)\(startingSummary)\(endingSummary)\(runIDs); stop \(stopReason.rawValue); \(Self.bounded(userMessage, limit: 220))."
  }

  var contextSummary: String {
    var metadata = ["latest_plan_proof_delta \(proofDebtChangeSummary)"]
    metadata.append("audit \(Self.bounded(auditID, limit: 80))")
    if !evidenceRunIDs.isEmpty {
      metadata.append("evidence \(evidenceRunIDs.prefix(3).joined(separator: ", "))")
    }
    if let startingProofDebtSummary {
      metadata.append("starting \(Self.bounded(startingProofDebtSummary, limit: 160))")
    }
    if let endingProofDebtSummary {
      metadata.append("ending \(Self.bounded(endingProofDebtSummary, limit: 160))")
    }
    return metadata.joined(separator: ", ")
  }

  var displaySummary: String {
    guard
      let startingProofDebtCount,
      let endingProofDebtCount,
      let proofDebtDelta
    else {
      return "Proof debt delta unavailable"
    }

    if proofDebtDelta < 0 {
      return
        "Proof debt cleared \(abs(proofDebtDelta)) (\(startingProofDebtCount) -> \(endingProofDebtCount))"
    }
    if proofDebtDelta > 0 {
      return
        "Proof debt added \(proofDebtDelta) (\(startingProofDebtCount) -> \(endingProofDebtCount))"
    }
    return "Proof debt unchanged (\(startingProofDebtCount) -> \(endingProofDebtCount))"
  }

  var displaySystemImage: String {
    guard let proofDebtDelta else { return "questionmark.circle" }
    if proofDebtDelta < 0 { return "checkmark.seal" }
    if proofDebtDelta > 0 { return "exclamationmark.triangle" }
    return "minus.circle"
  }

  var helpSummary: String {
    var parts = [
      displaySummary,
      "Audit \(auditID)",
    ]
    if !evidenceRunIDs.isEmpty {
      parts.append("Evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))")
    }
    if let startingProofDebtSummary {
      parts.append("Starting: \(Self.bounded(startingProofDebtSummary, limit: 260))")
    }
    if let endingProofDebtSummary {
      parts.append("Ending: \(Self.bounded(endingProofDebtSummary, limit: 260))")
    }
    return parts.joined(separator: "\n")
  }

  private var proofDebtChangeSummary: String {
    guard
      let startingProofDebtCount,
      let endingProofDebtCount,
      let proofDebtDelta
    else {
      return "proof_debt unavailable"
    }
    let sign = proofDebtDelta > 0 ? "+" : ""
    return
      "proof_debt \(startingProofDebtCount) -> \(endingProofDebtCount) (\(sign)\(proofDebtDelta))"
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}

enum TournamentAutomationPlanProofAuditDeltaFinder {
  static func recent(
    in config: ProductTournamentConfig,
    limit: Int = 3
  ) -> [TournamentAutomationPlanProofAuditDelta] {
    guard limit > 0 else { return [] }
    return config.tournamentAutomationCycleAudits
      .sorted(by: recentAuditSort)
      .filter(isPlanProofAutomationAudit)
      .prefix(limit)
      .map(TournamentAutomationPlanProofAuditDelta.init(audit:))
  }

  static func latest(
    for contender: ProductTournamentContender,
    in config: ProductTournamentConfig
  ) -> TournamentAutomationPlanProofAuditDelta? {
    config.tournamentAutomationCycleAudits
      .sorted(by: recentAuditSort)
      .first(where: { matchesPlanProofAudit($0, contender: contender) })
      .map(TournamentAutomationPlanProofAuditDelta.init(audit:))
  }

  private static func isPlanProofAutomationAudit(
    _ audit: TournamentAutomationCycleAudit
  ) -> Bool {
    audit.executedStepIDs.contains {
      $0.contains(ProductTournamentNextActionKind.runPlanProof.rawValue)
    }
      || audit.startingProofDebtSummary?.localizedCaseInsensitiveContains("plan proof") == true
      || audit.endingProofDebtSummary?.localizedCaseInsensitiveContains("plan proof") == true
  }

  private static func matchesPlanProofAudit(
    _ audit: TournamentAutomationCycleAudit,
    contender: ProductTournamentContender
  ) -> Bool {
    guard isPlanProofAutomationAudit(audit) else { return false }
    let stepMatches = audit.executedStepIDs.contains {
      $0.contains(ProductTournamentNextActionKind.runPlanProof.rawValue)
        && $0.contains(contender.id)
    }
    let summaryMatches =
      audit.startingProofDebtSummary?.contains("contender \(contender.id)") == true
      || audit.endingProofDebtSummary?.contains("contender \(contender.id)") == true
    guard stepMatches || summaryMatches else { return false }

    guard let experimentID = contender.experimentID else { return true }
    return audit.experimentIDs.contains(experimentID)
      || audit.executedStepIDs.contains { $0.hasPrefix("\(experimentID):") }
      || audit.startingProofDebtSummary?.contains(experimentID) == true
      || audit.endingProofDebtSummary?.contains(experimentID) == true
  }

  private static func recentAuditSort(
    lhs: TournamentAutomationCycleAudit,
    rhs: TournamentAutomationCycleAudit
  ) -> Bool {
    if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
    return lhs.endedAt > rhs.endedAt
  }
}
