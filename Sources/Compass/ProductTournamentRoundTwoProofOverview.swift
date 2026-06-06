import Foundation

struct ProductTournamentRoundTwoProofOverviewItem: Equatable, Sendable, Identifiable {
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
  var coreTechnologyProof: String
  var acceptanceSignals: [String]
  var riskFocus: String
  var recommendation: ProductTournamentRoundEvidenceRecommendation
  var readinessScore: Double
  var averageScore: Double
  var runCount: Int
  var completedRunCount: Int
  var distinctPersonaCount: Int
  var experienceUseProofCount: Int
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
    let acceptance =
      acceptanceSignals.isEmpty
      ? "no acceptance signals"
      : acceptanceSignals.prefix(4).joined(separator: "; ")
    return
      "- round_2_proof contender \(contenderID) [round \(roundID), experiment \(experimentID), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, average \(Self.format(averageScore))/5, completed \(completedRunCount)/\(runCount), personas \(distinctPersonaCount), experience_use_proofs \(experienceUseProofCount), missing_capabilities \(missingCapabilityCount), \(evidence)]: core_technology_proof \(Self.bounded(coreTechnologyProof, limit: 220)); next \(Self.bounded(detail, limit: 220)); acceptance \(Self.bounded(acceptance, limit: 180)); risk \(Self.bounded(riskFocus, limit: 120))."
  }

  var displaySubtitle: String {
    "\(recommendation.title) - readiness \(scoreLabel)/100 - \(completedRunCount)/\(runCount) runs"
  }

  var displayDetail: String {
    "\(detail) Proof: \(coreTechnologyProof)"
  }

  var displaySystemImage: String {
    switch recommendation {
    case .advanceToProductImplementation:
      return "arrow.up.forward.circle"
    case .reviseCoreTechnology:
      return "hammer"
    case .eliminate:
      return "xmark.octagon"
    case .gatherEvidence:
      return "target"
    }
  }

  var workbenchAccessibilityID: String {
    "round-2-proof-overview-\(id)"
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
      "\(experienceUseProofCount) experience-use proof(s)",
      "Core technology proof: \(coreTechnologyProof)",
    ]
    if !evidenceRunIDs.isEmpty {
      parts.append("Evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))")
    }
    if !acceptanceSignals.isEmpty {
      parts.append("Acceptance: \(acceptanceSignals.prefix(4).joined(separator: "; "))")
    }
    parts.append("Risk: \(riskFocus)")
    return parts.joined(separator: "\n")
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }

  private static func format(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

enum ProductTournamentRoundTwoProofOverview {
  static func items(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 4
  ) -> [ProductTournamentRoundTwoProofOverviewItem] {
    guard limit > 0 else { return [] }
    var proposalsByRoundAndContender: [String: ProductTournamentRoundEvidenceTransitionProposal] =
      [:]
    for proposal in ProductTournamentRoundEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      proposalsByRoundAndContender[
        key(roundID: proposal.roundID, contenderID: proposal.contenderID),
        default: proposal
      ] = proposal
    }

    return ProductTournamentFeasibilityAdvisor.handoffs(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .compactMap { handoff in
      guard
        let proposal = proposalsByRoundAndContender[
          key(roundID: handoff.roundID, contenderID: handoff.contenderID)
        ]
      else { return nil }
      return ProductTournamentRoundTwoProofOverviewItem(
        tournamentID: handoff.tournamentID,
        roundID: handoff.roundID,
        roundTitle: handoff.roundTitle,
        contenderID: handoff.contenderID,
        contenderTitle: handoff.contenderTitle,
        experimentID: handoff.experimentID,
        experimentTitle: handoff.experimentTitle,
        branchName: handoff.branchName,
        worktreeID: handoff.worktreeID,
        coreTechnologyProof: handoff.coreTechnologyProof,
        acceptanceSignals: handoff.acceptanceSignals,
        riskFocus: handoff.riskFocus,
        recommendation: proposal.recommendation,
        readinessScore: proposal.readinessScore,
        averageScore: proposal.averageScore,
        runCount: proposal.runCount,
        completedRunCount: proposal.completedRunCount,
        distinctPersonaCount: proposal.distinctPersonaCount,
        experienceUseProofCount: proposal.experienceUseProofCount,
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
    return ["Round 2 core-technology proof overview:"]
      + items.map(\.contextLine)
  }

  private static func key(roundID: String, contenderID: String) -> String {
    "\(roundID)|\(contenderID)"
  }
}
