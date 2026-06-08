import Foundation

struct ProductTournamentRoundThreeProductImplementationOverviewItem: Equatable, Sendable,
  Identifiable
{
  var id: String { "\(roundID)-\(contenderID)" }

  var tournamentID: String
  var roundID: String
  var roundTitle: String
  var contenderID: String
  var contenderTitle: String
  var experimentID: String
  var experimentTitle: String
  var branchName: String
  var worktreeID: String
  var implementationScope: String
  var recommendation: ProductTournamentProductImplementationEvidenceRecommendation
  var readinessScore: Double
  var averageScore: Double
  var willingnessToPayScore: Double
  var willingnessToPayProofCount: Int
  var runCount: Int
  var completedRunCount: Int
  var distinctPersonaCount: Int
  var currentAlternativeProofCount: Int
  var implementationUseProofCount: Int
  var missingCapabilityCount: Int
  var evidenceRunIDs: [String]
  var detail: String
  var proofGaps: [String]
  var nextValidationTarget: String
  var implementationRevisionValidation:
    ProductTournamentRoundThreeImplementationRevisionValidationResult?

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  var contextLine: String {
    let evidence =
      evidenceRunIDs.isEmpty
      ? "no scoped evidence"
      : "evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))"
    let gaps =
      proofGaps.isEmpty
      ? "none"
      : proofGaps.prefix(4).joined(separator: "; ")
    return
      "- round_3_product_implementation_proof contender \(contenderID) [round \(roundID), experiment \(experimentID), branch \(branchName), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, average \(Self.format(averageScore))/5, willingness_to_pay \(Self.format(willingnessToPayScore))/5, willingness_to_pay_proofs \(willingnessToPayProofCount), completed \(completedRunCount)/\(runCount), personas \(distinctPersonaCount), current_alternative_proofs \(currentAlternativeProofCount), implementation_use_proofs \(implementationUseProofCount), missing_capabilities \(missingCapabilityCount), \(evidence), proof_gaps \(Self.bounded(gaps, limit: 260))]: implementation_scope \(Self.bounded(implementationScope, limit: 220)); next \(Self.bounded(detail, limit: 220)); next_validation \(Self.bounded(nextValidationTarget, limit: 220))."
  }

  var displaySubtitle: String {
    "\(recommendation.title) - readiness \(scoreLabel)/100 - pay \(Self.format(willingnessToPayScore))/5"
  }

  var displayDetail: String {
    "\(detail) Next validation: \(nextValidationTarget) Product implementation: \(implementationScope)"
  }

  var implementationRevisionValidationSummary: String? {
    implementationRevisionValidation?.displaySummary
  }

  var implementationRevisionValidationDetail: String? {
    implementationRevisionValidation?.displayDetail
  }

  var displaySystemImage: String {
    switch recommendation {
    case .selectWinner:
      return "crown"
    case .reviseImplementation:
      return "hammer"
    case .eliminate:
      return "xmark.octagon"
    case .gatherEvidence:
      return "target"
    }
  }

  var workbenchAccessibilityID: String {
    "round-3-proof-overview-\(id)"
  }

  var helpSummary: String {
    var parts = [
      contenderTitle,
      "Tournament \(tournamentID)",
      "Round \(roundID)",
      "Experiment \(experimentID)",
      "Branch \(branchName)",
      "Worktree \(worktreeID)",
      displaySubtitle,
      "Implementation scope: \(implementationScope)",
    ]
    if !evidenceRunIDs.isEmpty {
      parts.append("Evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))")
    }
    parts.append("\(currentAlternativeProofCount) current-alternative proof(s)")
    parts.append("\(implementationUseProofCount) implementation-use proof(s)")
    parts.append("\(willingnessToPayProofCount) willingness-to-pay proof(s)")
    parts.append("\(missingCapabilityCount) missing capability signal(s)")
    if !proofGaps.isEmpty {
      parts.append("Proof gaps: \(proofGaps.prefix(4).joined(separator: "; "))")
    }
    if let implementationRevisionValidation {
      parts.append(
        "Implementation revision validation: \(implementationRevisionValidation.displaySummary)"
      )
      parts.append(implementationRevisionValidation.displayDetail)
    }
    parts.append("Next validation: \(nextValidationTarget)")
    return parts.joined(separator: "\n")
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }

  private static func format(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

enum ProductTournamentRoundThreeProductImplementationOverview {
  static func items(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 4
  ) -> [ProductTournamentRoundThreeProductImplementationOverviewItem] {
    guard limit > 0 else { return [] }
    let readModel = ProductTournamentReadModel(config: config)
    var validationResultsByRoundAndContender:
      [String: ProductTournamentRoundThreeImplementationRevisionValidationResult] = [:]
    for result in ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.results(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: max(limit, 4)
    ) {
      let resultKey = key(roundID: result.roundID, contenderID: result.contenderID)
      if validationResultsByRoundAndContender[resultKey] == nil {
        validationResultsByRoundAndContender[resultKey] = result
      }
    }

    return ProductTournamentProductImplementationEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .compactMap { proposal in
      guard
        let contender = readModel.contender(id: proposal.contenderID),
        contender.tournamentID == proposal.tournamentID,
        let experiment = readModel.experiment(for: contender)
      else { return nil }
      return ProductTournamentRoundThreeProductImplementationOverviewItem(
        tournamentID: proposal.tournamentID,
        roundID: proposal.roundID,
        roundTitle: proposal.roundTitle,
        contenderID: proposal.contenderID,
        contenderTitle: proposal.contenderTitle,
        experimentID: experiment.id,
        experimentTitle: experiment.title,
        branchName: experiment.branchName,
        worktreeID: experiment.worktreeID,
        implementationScope: experiment.implementationScope,
        recommendation: proposal.recommendation,
        readinessScore: proposal.readinessScore,
        averageScore: proposal.averageScore,
        willingnessToPayScore: proposal.willingnessToPayScore,
        willingnessToPayProofCount: proposal.willingnessToPayProofCount,
        runCount: proposal.runCount,
        completedRunCount: proposal.completedRunCount,
        distinctPersonaCount: proposal.distinctPersonaCount,
        currentAlternativeProofCount: proposal.currentAlternativeProofCount,
        implementationUseProofCount: proposal.implementationUseProofCount,
        missingCapabilityCount: proposal.missingCapabilityCount,
        evidenceRunIDs: proposal.evidenceRunIDs,
        detail: proposal.detail,
        proofGaps: proposal.proofGaps,
        nextValidationTarget: proposal.nextValidationTarget,
        implementationRevisionValidation: validationResultsByRoundAndContender[
          key(roundID: proposal.roundID, contenderID: proposal.contenderID)
        ]
      )
    }
    .prefix(limit)
    .map { $0 }
  }

  static func contextLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 3
  ) -> [String] {
    let items = items(config: config, evidenceIndex: evidenceIndex, limit: limit)
    guard !items.isEmpty else { return [] }
    return ["Round 3 product implementation proof overview:"]
      + items.map(\.contextLine)
  }

  private static func key(roundID: String, contenderID: String) -> String {
    "\(roundID)|\(contenderID)"
  }
}
