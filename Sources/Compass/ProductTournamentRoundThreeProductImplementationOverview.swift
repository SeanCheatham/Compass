import Foundation

struct ProductTournamentRoundThreeProductImplementationOverviewItem: Equatable, Sendable, Identifiable {
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
  var runCount: Int
  var completedRunCount: Int
  var distinctPersonaCount: Int
  var currentAlternativeProofCount: Int
  var implementationUseProofCount: Int
  var missingCapabilityCount: Int
  var evidenceRunIDs: [String]
  var detail: String

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  var contextLine: String {
    let evidence =
      evidenceRunIDs.isEmpty
      ? "no scoped evidence"
      : "evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))"
    return
      "- round_3_product_implementation_proof contender \(contenderID) [round \(roundID), experiment \(experimentID), branch \(branchName), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, average \(Self.format(averageScore))/5, willingness_to_pay \(Self.format(willingnessToPayScore))/5, completed \(completedRunCount)/\(runCount), personas \(distinctPersonaCount), current_alternative_proofs \(currentAlternativeProofCount), implementation_use_proofs \(implementationUseProofCount), missing_capabilities \(missingCapabilityCount), \(evidence)]: implementation_scope \(Self.bounded(implementationScope, limit: 220)); next \(Self.bounded(detail, limit: 220))."
  }

  var displaySubtitle: String {
    "\(recommendation.title) - readiness \(scoreLabel)/100 - pay \(Self.format(willingnessToPayScore))/5"
  }

  var displayDetail: String {
    "\(detail) Product implementation: \(implementationScope)"
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
    parts.append("\(missingCapabilityCount) missing capability signal(s)")
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
    return ProductTournamentProductImplementationEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .compactMap { proposal in
      guard
        let contender = config.tournamentContenders.first(where: {
          $0.id == proposal.contenderID && $0.tournamentID == proposal.tournamentID
        }),
        let experimentID = contender.experimentID,
        let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID })
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
        runCount: proposal.runCount,
        completedRunCount: proposal.completedRunCount,
        distinctPersonaCount: proposal.distinctPersonaCount,
        currentAlternativeProofCount: proposal.currentAlternativeProofCount,
        implementationUseProofCount: proposal.implementationUseProofCount,
        missingCapabilityCount: proposal.missingCapabilityCount,
        evidenceRunIDs: proposal.evidenceRunIDs,
        detail: proposal.detail
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
}
