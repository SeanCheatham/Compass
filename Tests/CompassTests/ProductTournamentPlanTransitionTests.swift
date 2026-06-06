import Foundation
import Testing

@testable import Compass

struct ProductTournamentPlanTransitionTests {
  @Test func strongPlanReadinessAdvancesContenderToFeasibilityRound() throws {
    let config = ProductizationConfig.seedDefaults(
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
      outcome.config.solutionHypotheses.first { $0.id == contender.solutionID })

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
    let config = ProductizationConfig.seedDefaults(
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
    let config = ProductizationConfig.seedDefaults(
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
    try #require(updatedContender.status == .needsRevision)
    try #require(updatedPlanRound.status == .active)
    try #require(updatedTournament.currentRoundID == planRound.id)
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("revision"))
  }
}

private func strongRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductizationConfig
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

private func weakRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductizationConfig
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
  config: ProductizationConfig
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
  config: ProductizationConfig,
  score: Int,
  willingnessToPay: Int,
  verdict: ProductTournamentEvidenceVerdict,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  summary: String
) throws -> [ProductTournamentPlanEvaluationRecord] {
  let solution = try #require(config.solutionHypotheses.first { $0.id == contender.solutionID })
  let segments = config.userSegments.prefix(2)
  return segments.enumerated().map { index, segment in
    ProductTournamentPlanEvaluationRecord(
      id: "\(contender.id)-transition-\(index)",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      solutionID: contender.solutionID,
      experimentID: contender.experimentID,
      painID: solution.painID,
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
