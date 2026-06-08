import Foundation

enum ProductSignalTone: String, Equatable, Sendable {
  case strong
  case progressing
  case missing
  case blocked
  case risk
  case neutral
}

enum ProductIconRole: String, Equatable, Sendable {
  case pain
  case contender
  case alternative
  case evidence
  case payIntent
  case useProof
  case revision
  case advance
  case eliminate
  case audit
  case workflow
  case switching
  case winner
}

enum ProductDisclosureLayer: String, Equatable, Sendable {
  case primary
  case rationale
  case audit
}

struct ProductProofDebtCopy: Equatable, Sendable {
  var shortLabel: String
  var detail: String
  var nextTargetLabel: String
  var tone: ProductSignalTone
}

enum ProductPresentationLanguage {
  static func roundLabel(kind: ProductTournamentRoundKind, ordinal: Int) -> String {
    switch kind {
    case .productPlans:
      return "Round \(ordinal): Plan proof"
    case .coreTechnology:
      return "Round \(ordinal): Core technology"
    case .productImplementation:
      return "Round \(ordinal): Product use"
    }
  }

  static func roundGateLabel(kind: ProductTournamentRoundKind) -> String {
    switch kind {
    case .productPlans:
      return "Plan proof gate"
    case .coreTechnology:
      return "Core workflow gate"
    case .productImplementation:
      return "Product use and pay gate"
    }
  }

  static func contenderStatusLabel(_ status: ProductTournamentContenderStatus) -> String {
    switch status {
    case .competing:
      return "Competing"
    case .narrowed:
      return "Advanced"
    case .needsRevision:
      return "Revision needed"
    case .eliminated:
      return "Eliminated"
    case .winner:
      return "Winner"
    case .archived:
      return "Archived"
    }
  }

  static func tone(for strength: EvidenceStrength) -> ProductSignalTone {
    switch strength {
    case .strong:
      return .strong
    case .progressing:
      return .progressing
    case .missing:
      return .missing
    case .blocked:
      return .blocked
    case .risk:
      return .risk
    case .neutral:
      return .neutral
    }
  }

  static func tone(for proofDebt: ProofDebtSummary) -> ProductSignalTone {
    if proofDebt.readinessState.localizedCaseInsensitiveContains("locked") {
      return .blocked
    }
    if proofDebt.isClear {
      return .strong
    }
    if proofDebt.completedCount > 0 {
      return .progressing
    }
    if proofDebt.missingGates.contains(where: {
      $0.localizedCaseInsensitiveContains("pay")
        || $0.localizedCaseInsensitiveContains("buyer")
    }) {
      return .risk
    }
    return .missing
  }

  static func proofDebtCopy(for proofDebt: ProofDebtSummary) -> ProductProofDebtCopy {
    if proofDebt.isClear {
      return ProductProofDebtCopy(
        shortLabel: "Proof complete",
        detail: "All required proof gates are clear.",
        nextTargetLabel: proofDebt.nextProofTarget,
        tone: .strong
      )
    }
    let firstGate = proofDebt.missingGates.first ?? "Proof missing"
    let countLabel =
      proofDebt.requiredCount > 0
      ? "\(proofDebt.completedCount)/\(proofDebt.requiredCount)"
      : "\(proofDebt.completedCount)"
    return ProductProofDebtCopy(
      shortLabel: "\(countLabel) - \(firstGate)",
      detail: proofDebt.missingGates.prefix(3).joined(separator: ", "),
      nextTargetLabel: proofDebt.nextProofTarget,
      tone: tone(for: proofDebt)
    )
  }

  static func evidenceLabel(for dimension: EvidenceDimension) -> String {
    dimension.label
  }

  static func iconRole(for dimension: EvidenceDimension) -> ProductIconRole {
    switch dimension {
    case .painFit:
      return .pain
    case .workflowLift:
      return .workflow
    case .alternativeAdvantage:
      return .alternative
    case .switchingReadiness:
      return .switching
    case .payIntent:
      return .payIntent
    case .productUseProof:
      return .useProof
    case .personaBreadth:
      return .contender
    }
  }

  static func actionLabel(
    for kind: ProductTournamentNextActionKind,
    targetDecision: ProductTournamentExperimentDecision? = nil
  ) -> String {
    switch kind {
    case .applyDecision:
      return "Apply product decision"
    case .applyRoundTransition:
      return "Apply round decision"
    case .prepareWorktree:
      return "Prepare implementation track"
    case .runPlanProof:
      return "Run plan proof"
    case .runCohort, .rerunCohort:
      switch targetDecision {
      case .promote:
        return "Run validation proof"
      case .kill:
        return "Run rejection proof"
      case .notRun, .keepGoing, .narrow, .pivot, .archived, .promoted, nil:
        return "Run product proof"
      }
    case .repairFailures:
      return "Repair failed proof"
    case .refineContender:
      return "Revise product contender"
    case .reviewDecision:
      return "Review product decision"
    }
  }

  static func actionLabel(for proposal: ProductTournamentPlanTransitionProposal) -> String {
    switch proposal.recommendation {
    case .advanceToFeasibility:
      return "Advance to feasibility"
    case .revisePlan:
      return "Revise product plan"
    case .eliminate:
      return "Eliminate product contender"
    case .gatherEvidence:
      return "Gather more plan proof"
    }
  }

  static func actionLabel(for proposal: ProductTournamentRoundEvidenceTransitionProposal)
    -> String
  {
    switch proposal.recommendation {
    case .advanceToProductImplementation:
      return "Advance to product use"
    case .reviseCoreTechnology:
      return "Revise core workflow"
    case .eliminate:
      return "Eliminate product contender"
    case .gatherEvidence:
      return "Gather more core-technology proof"
    }
  }

  static func actionLabel(
    for proposal: ProductTournamentProductImplementationEvidenceTransitionProposal
  ) -> String {
    switch proposal.recommendation {
    case .selectWinner:
      return "Select winner"
    case .reviseImplementation:
      return "Revise product implementation"
    case .eliminate:
      return "Eliminate product contender"
    case .gatherEvidence:
      return "Gather more product-use proof"
    }
  }

  static func expectedDecisionLabel(
    actionKind: ProductTournamentNextActionKind,
    targetDecision: ProductTournamentExperimentDecision? = nil
  ) -> String {
    if let targetDecision {
      return "Decide whether to \(decisionVerb(targetDecision))"
    }
    switch actionKind {
    case .applyDecision:
      return "Update the product decision"
    case .applyRoundTransition:
      return "Advance, revise, or eliminate"
    case .prepareWorktree:
      return "Unlock product-use proof"
    case .runPlanProof:
      return "Advance to feasibility, revise, or eliminate"
    case .runCohort, .rerunCohort:
      return "Continue, pivot, promote, or stop"
    case .repairFailures:
      return "Restore trust in the evidence"
    case .refineContender:
      return "Retest the revised direction"
    case .reviewDecision:
      return "Choose the next product direction"
    }
  }

  static func disabledReasonLabel(_ rawReason: String?) -> String? {
    guard let rawReason, !rawReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    let lower = rawReason.lowercased()
    if lower.contains("persona") {
      return "Persona-model proof is not available."
    }
    if lower.contains("contract") {
      return "The tournament experience contract is missing."
    }
    if lower.contains("scenario") {
      return "No enabled product-test scenario is ready."
    }
    if lower.contains("locked") {
      return "Core-technology proof is locked to another contender."
    }
    return "The next proof is not executable yet."
  }

  static func disclosureLayer(for referenceKind: AuditReferenceKind) -> ProductDisclosureLayer {
    switch referenceKind {
    case .pain, .tournament, .round, .contender, .contenderPlan, .experiment, .scenario, .cohort,
      .evidenceRun, .planEvaluation, .automationAudit, .branch, .commit, .model, .promptVersion:
      return .audit
    }
  }

  static func primaryTextContainsAuditReference(
    _ text: String,
    auditReferences: [AuditReference]
  ) -> Bool {
    let primary = text.lowercased()
    return auditReferences.contains { reference in
      let value = reference.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard value.count >= 6 else { return false }
      return primary.contains(value.lowercased())
    }
  }

  static func auditText(for references: [AuditReference]) -> String {
    references
      .sorted {
        if $0.kind.rawValue == $1.kind.rawValue { return $0.value < $1.value }
        return $0.kind.rawValue < $1.kind.rawValue
      }
      .map { "\($0.label): \($0.value)" }
      .joined(separator: "\n")
  }

  private static func decisionVerb(_ decision: ProductTournamentExperimentDecision) -> String {
    switch decision {
    case .notRun:
      return "start proof"
    case .keepGoing:
      return "continue"
    case .narrow:
      return "narrow"
    case .pivot:
      return "pivot"
    case .kill:
      return "eliminate"
    case .promote:
      return "promote"
    case .archived:
      return "archive"
    case .promoted:
      return "mark promoted"
    }
  }
}
