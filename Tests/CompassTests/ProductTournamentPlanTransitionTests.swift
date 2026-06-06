import Foundation
import Testing

@testable import Compass

struct ProductTournamentPlanTransitionTests {
  @Test func strongPlanReadinessAdvancesContenderToFeasibilityRound() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let feasibilityRound = try #require(
      config.tournamentRounds.first { $0.kind == .coreTechnology })
    let contender = try #require(config.tournamentContenders.first)
    let records = try strongRecords(
      for: contender, tournament: tournament, round: planRound, config: config)
    let index = ProductTournamentEvidenceIndex.build(records: [], planEvaluationRecords: records)

    let proposal = try #require(
      ProductTournamentPlanTransitioner.bestProposal(
        tournamentID: tournament.id,
        roundID: planRound.id,
        config: config,
        evidenceIndex: index
      )
    )
    let outcome = try ProductTournamentPlanTransitioner.apply(
      proposal: proposal,
      to: config,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == tournament.id })
    let updatedPlanRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == planRound.id })
    let updatedFeasibilityRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == feasibilityRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == contender.id })
    let updatedSolution = try #require(
      outcome.config.productHypotheses.first { $0.id == contender.productHypothesisID })

    try #require(proposal.recommendation == .advanceToFeasibility)
    try #require(updatedTournament.currentRoundID == feasibilityRound.id)
    try #require(updatedPlanRound.status == .completed)
    try #require(updatedFeasibilityRound.status == .active)
    try #require(updatedFeasibilityRound.contenderIDs == [contender.id])
    try #require(updatedContender.status == .narrowed)
    try #require(updatedSolution.status == .active)
    try #require(outcome.toRoundID == feasibilityRound.id)
    try #require(outcome.userMessage.contains("Advanced"))
    try #require(
      ProductTournamentPlanTransitioner.bestProposal(
        config: outcome.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func weakPlanReadinessEliminatesContenderFromFutureRounds() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.last)
    let records = try weakRecords(
      for: contender, tournament: tournament, round: planRound, config: config)
    let index = ProductTournamentEvidenceIndex.build(records: [], planEvaluationRecords: records)

    let outcome = try ProductTournamentPlanTransitioner.applyBestProposal(
      tournamentID: tournament.id,
      roundID: planRound.id,
      to: config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == contender.id })
    let futureRounds = outcome.config.tournamentRounds.filter {
      $0.tournamentID == tournament.id && $0.ordinal > planRound.ordinal
    }
    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == tournament.id })

    try #require(outcome.proposal.recommendation == .eliminate)
    try #require(updatedContender.status == .eliminated)
    try #require(futureRounds.allSatisfy { !$0.contenderIDs.contains(contender.id) })
    try #require(updatedTournament.currentRoundID == planRound.id)
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("Eliminated"))
  }

  @Test func mixedPlanReadinessMarksContenderForRevision() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.first)
    let records = try revisionRecords(
      for: contender, tournament: tournament, round: planRound, config: config)
    let index = ProductTournamentEvidenceIndex.build(records: [], planEvaluationRecords: records)
    let readiness = try #require(index.aggregate.planReadinessByContender.first)

    let outcome = try ProductTournamentPlanTransitioner.applyBestProposal(
      tournamentID: tournament.id,
      roundID: planRound.id,
      to: config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == contender.id })
    let updatedPlanRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == planRound.id })
    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == tournament.id })

    try #require(outcome.proposal.recommendation == .revisePlan)
    try #require(readiness.planProofDebt.focusedActionTitle == "Run Price/ROI Proof")
    try #require(outcome.proposal.detail.contains("Commercial proof"))
    try #require(outcome.proposal.detail.contains("stronger price and ROI proof"))
    try #require(updatedContender.status == .needsRevision)
    try #require(updatedPlanRound.status == .active)
    try #require(updatedTournament.currentRoundID == planRound.id)
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("revision"))
  }

  @Test func strongPlanReadinessWithoutBuyerSignalGathersEvidence() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.first)
    let records = try strongNonBuyerRecords(
      for: contender,
      tournament: tournament,
      round: planRound,
      config: config
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], planEvaluationRecords: records)
    let readiness = try #require(index.aggregate.planReadinessByContender.first)
    let proposal = try #require(
      ProductTournamentPlanTransitioner.proposals(
        tournamentID: tournament.id,
        roundID: planRound.id,
        config: config,
        evidenceIndex: index
      ).first
    )

    try #require(readiness.completedEvaluationCount == 2)
    try #require(readiness.distinctPersonaCount == 2)
    try #require(readiness.buyerOrSponsorPersonaCount == 0)
    try #require(readiness.planProofDebt.summary.contains("buyer/sponsor signal"))
    try #require(readiness.commercialProofSummary.contains("buyer/sponsor price and ROI"))
    try #require(readiness.nextProofTargetSummary.contains("economic-buyer"))
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(!proposal.isActionable)
    try #require(proposal.detail.contains("buyer/sponsor signal"))
    try #require(proposal.detail.contains("Commercial proof"))
    try #require(proposal.detail.contains("Next proof target"))
    try #require(proposal.detail.contains("economic-buyer"))
    try #require(
      ProductTournamentPlanTransitioner.bestProposal(
        tournamentID: tournament.id,
        roundID: planRound.id,
        config: config,
        evidenceIndex: index
      ) == nil
    )
  }
}

private func strongRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductTournamentConfig
) throws -> [ProductTournamentPlanEvaluationRecord] {
  try records(
    for: contender,
    tournament: tournament,
    round: round,
    config: config,
    score: 5,
    willingnessToPay: 4,
    verdict: .strongPull,
    summary: "The plan clearly beats the reporting workaround."
  )
}

private func strongNonBuyerRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductTournamentConfig
) throws -> [ProductTournamentPlanEvaluationRecord] {
  let hypothesis = try #require(config.productHypotheses.first { $0.id == contender.productHypothesisID })
  return [
    ProductTournamentPlanEvaluationRecord(
      id: "\(contender.id)-operator-a",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      productHypothesisID: contender.productHypothesisID,
      experimentID: contender.experimentID,
      painID: hypothesis.painID,
      personaID: "operator-a",
      personaName: "Operations lead",
      startedAt: 0,
      endedAt: 1,
      scores: ProductTournamentEvidenceScores(
        painRecognition: 5,
        workflowImprovement: 5,
        alternativeAdvantage: 5,
        switchingReadiness: 5,
        continuedUsePull: 5,
        willingnessToPay: 5
      ),
      willingnessToPayScore: 5,
      estimatedMonthlyPriceCents: 9900,
      currentAlternativeComparison: "The plan clearly beats the current reporting workaround.",
      verdict: .strongPull,
      summary: "The operator would use the plan."
    ),
    ProductTournamentPlanEvaluationRecord(
      id: "\(contender.id)-operator-b",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      productHypothesisID: contender.productHypothesisID,
      experimentID: contender.experimentID,
      painID: hypothesis.painID,
      personaID: "operator-b",
      personaName: "Reporting coordinator",
      startedAt: 2,
      endedAt: 3,
      scores: ProductTournamentEvidenceScores(
        painRecognition: 5,
        workflowImprovement: 5,
        alternativeAdvantage: 5,
        switchingReadiness: 5,
        continuedUsePull: 5,
        willingnessToPay: 5
      ),
      willingnessToPayScore: 5,
      estimatedMonthlyPriceCents: 9900,
      currentAlternativeComparison: "The plan clearly beats the current reporting workaround.",
      verdict: .strongPull,
      summary: "Another operator would use the plan."
    ),
  ]
}

private func weakRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductTournamentConfig
) throws -> [ProductTournamentPlanEvaluationRecord] {
  try records(
    for: contender,
    tournament: tournament,
    round: round,
    config: config,
    score: 1,
    willingnessToPay: 1,
    verdict: .weak,
    objections: ["The plan does not beat the current spreadsheet."],
    missingCapabilities: ["current_alternative_advantage"],
    summary: "The plan is too weak to justify implementation."
  )
}

private func revisionRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductTournamentConfig
) throws -> [ProductTournamentPlanEvaluationRecord] {
  try records(
    for: contender,
    tournament: tournament,
    round: round,
    config: config,
    score: 3,
    willingnessToPay: 2,
    verdict: .unclear,
    objections: ["The plan needs a sharper switching moment."],
    summary: "The plan has some pull but needs revision before implementation."
  )
}

private func records(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductTournamentConfig,
  score: Int,
  willingnessToPay: Int,
  verdict: ProductTournamentEvidenceVerdict,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  summary: String
) throws -> [ProductTournamentPlanEvaluationRecord] {
  let hypothesis = try #require(config.productHypotheses.first { $0.id == contender.productHypothesisID })
  let segments = config.userSegments.prefix(2)
  return segments.enumerated().map { index, segment in
    ProductTournamentPlanEvaluationRecord(
      id: "\(contender.id)-transition-\(index)",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      productHypothesisID: contender.productHypothesisID,
      experimentID: contender.experimentID,
      painID: hypothesis.painID,
      personaID: segment.id,
      personaName: segment.name,
      startedAt: Double(index),
      endedAt: Double(index + 1),
      scores: ProductTournamentEvidenceScores(
        painRecognition: score,
        workflowImprovement: score,
        alternativeAdvantage: score,
        switchingReadiness: score,
        continuedUsePull: score
      ),
      willingnessToPayScore: willingnessToPay,
      estimatedMonthlyPriceCents: willingnessToPay >= 3 ? 9900 : nil,
      objections: objections,
      missingCapabilities: missingCapabilities,
      currentAlternativeComparison: "Compared against the current workaround.",
      verdict: verdict,
      summary: summary,
      rationale: ["Transition test record."]
    )
  }
}
