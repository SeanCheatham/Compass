import Foundation
import Testing

@testable import Compass

struct ProductTournamentPrototypeEvidenceTransitionTests {
  @Test func strongPrototypeEvidenceSelectsTournamentWinner() throws {
    let fixture = try roundThreeFixture()
    let records = prototypeEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The prototype beats the current workaround and creates sponsor pull."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentPrototypeEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.prototypeRound.id,
        config: fixture.config,
        evidenceIndex: index
      )
    )
    let outcome = try ProductTournamentPrototypeEvidenceTransitioner.apply(
      proposal: proposal,
      to: fixture.config,
      now: Date(timeIntervalSince1970: 2_500)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedPrototypeRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.prototypeRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let losingContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.losingContender.id })
    let updatedExperiment = try #require(
      outcome.config.experiments.first { $0.id == fixture.experiment.id })
    let updatedSolution = try #require(
      outcome.config.solutionHypotheses.first { $0.id == fixture.contender.solutionID })
    let losingSolution = try #require(
      outcome.config.solutionHypotheses.first { $0.id == fixture.losingContender.solutionID })
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )

    try #require(proposal.recommendation == .selectWinner)
    try #require(updatedTournament.status == .completed)
    try #require(updatedTournament.currentRoundID == fixture.prototypeRound.id)
    try #require(updatedPrototypeRound.status == .completed)
    try #require(updatedPrototypeRound.contenderIDs == [fixture.contender.id])
    try #require(updatedContender.status == .winner)
    try #require(losingContender.status == .eliminated)
    try #require(updatedExperiment.decision == .promote)
    try #require(updatedSolution.status == .promoted)
    try #require(losingSolution.status == .rejected)
    try #require(
      Set(outcome.affectedContenderIDs) == [fixture.contender.id, fixture.losingContender.id])
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("winner"))
    try #require(digest.contains("Round 3 prototype transition"))
    try #require(digest.contains("recommendation select_winner"))
  }

  @Test func mixedPrototypeEvidenceMarksContenderForRevision() throws {
    let fixture = try roundThreeFixture()
    let records = prototypeEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 3,
      willingnessToPay: 2,
      verdict: .unclear,
      objections: ["The sponsor proof needs clearer export and audit context."],
      missingCapabilities: ["sponsor_export"],
      summary: "The prototype needs one more fidelity pass."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let outcome = try ProductTournamentPrototypeEvidenceTransitioner.applyBestProposal(
      tournamentID: fixture.tournament.id,
      roundID: fixture.prototypeRound.id,
      to: fixture.config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_500)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedPrototypeRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.prototypeRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let updatedExperiment = try #require(
      outcome.config.experiments.first { $0.id == fixture.experiment.id })
    let followUpScope = ProductTournamentEvidenceScopeResolver.scope(
      experimentID: fixture.experiment.id,
      in: outcome.config
    )

    try #require(outcome.proposal.recommendation == .revisePrototype)
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.prototypeRound.id)
    try #require(updatedPrototypeRound.status == .active)
    try #require(updatedContender.status == .needsRevision)
    try #require(updatedExperiment.decision == .narrow)
    try #require(followUpScope?.roundID == fixture.prototypeRound.id)
    try #require(outcome.userMessage.contains("revision"))
  }

  @Test func weakPrototypeEvidenceEliminatesContender() throws {
    let fixture = try roundThreeFixture()
    let records = prototypeEvidenceRecords(
      fixture: fixture,
      count: 2,
      score: 1,
      willingnessToPay: 1,
      verdict: .weak,
      objections: ["The prototype does not beat the spreadsheet."],
      missingCapabilities: ["workflow_advantage"],
      summary: "The prototype does not create enough pull."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let outcome = try ProductTournamentPrototypeEvidenceTransitioner.applyBestProposal(
      tournamentID: fixture.tournament.id,
      roundID: fixture.prototypeRound.id,
      to: fixture.config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_500)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let updatedExperiment = try #require(
      outcome.config.experiments.first { $0.id == fixture.experiment.id })
    let updatedSolution = try #require(
      outcome.config.solutionHypotheses.first { $0.id == fixture.contender.solutionID })

    try #require(outcome.proposal.recommendation == .eliminate)
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.prototypeRound.id)
    try #require(updatedContender.status == .eliminated)
    try #require(updatedExperiment.decision == .kill)
    try #require(updatedSolution.status == .rejected)
    try #require(outcome.userMessage.contains("Eliminated"))
  }

  @Test func twoStrongPrototypeRunsOnlyGatherMoreEvidence() throws {
    let fixture = try roundThreeFixture()
    let records = prototypeEvidenceRecords(
      fixture: fixture,
      count: 2,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "Two strong prototype runs are promising."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentPrototypeEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.prototypeRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(!proposal.isActionable)
    try #require(
      ProductTournamentPrototypeEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.prototypeRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }
}

private struct RoundThreeFixture {
  var config: ProductizationConfig
  var tournament: ProductTournament
  var prototypeRound: ProductTournamentRound
  var contender: ProductTournamentContender
  var losingContender: ProductTournamentContender
  var experiment: ProductExperiment
  var solution: SolutionHypothesis
}

private func roundThreeFixture() throws -> RoundThreeFixture {
  var config = ProductizationConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Weekly reporting takes too long.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let tournament = try #require(config.tournaments.first)
  let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
  let coreRound = try #require(config.tournamentRounds.first { $0.kind == .coreTechnology })
  let prototypeRound = try #require(config.tournamentRounds.first { $0.kind == .prototype })
  let contender = try #require(config.tournamentContenders.first)
  let losingContender = try #require(config.tournamentContenders.dropFirst().first)
  let experimentID = try #require(contender.experimentID)
  let experiment = try #require(config.experiments.first { $0.id == experimentID })
  let solution = try #require(config.solutionHypotheses.first { $0.id == contender.solutionID })

  config.tournaments[0].currentRoundID = prototypeRound.id
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == planRound.id }) {
    config.tournamentRounds[index].status = .completed
  }
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == coreRound.id }) {
    config.tournamentRounds[index].status = .completed
    config.tournamentRounds[index].contenderIDs = [contender.id]
  }
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == prototypeRound.id }) {
    config.tournamentRounds[index].status = .active
    config.tournamentRounds[index].contenderIDs = [contender.id]
  }
  if let index = config.tournamentContenders.firstIndex(where: { $0.id == contender.id }) {
    config.tournamentContenders[index].status = .narrowed
  }

  return RoundThreeFixture(
    config: config,
    tournament: tournament,
    prototypeRound: prototypeRound,
    contender: contender,
    losingContender: losingContender,
    experiment: experiment,
    solution: solution
  )
}

private func prototypeEvidenceRecords(
  fixture: RoundThreeFixture,
  count: Int,
  score: Int,
  willingnessToPay: Int,
  verdict: ProductTournamentEvidenceVerdict,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  summary: String
) -> [ProductTournamentEvidenceRecord] {
  let segments = Array(fixture.config.userSegments)
  return (0..<count).map { index in
    let segment = segments[index % max(1, segments.count)]
    return ProductTournamentEvidenceRecord(
      id: "\(fixture.contender.id)-round-3-\(index)",
      experimentID: fixture.experiment.id,
      solutionID: fixture.contender.solutionID,
      painID: fixture.solution.painID,
      tournamentID: fixture.tournament.id,
      roundID: fixture.prototypeRound.id,
      contenderID: fixture.contender.id,
      branchName: fixture.experiment.branchName,
      commitSha: "def456",
      scenarioID: "prototype-scenario-\(index)",
      personaID: segment.id,
      mode: .modelFree,
      status: .completed,
      startedAt: Double(index),
      endedAt: Double(index + 1),
      scores: ProductTournamentEvidenceScores(
        painRecognition: score,
        workflowImprovement: score,
        alternativeAdvantage: score,
        switchingReadiness: score,
        continuedUsePull: score,
        willingnessToPay: willingnessToPay
      ),
      objections: objections,
      missingCapabilities: missingCapabilities,
      currentAlternativeComparison: "The prototype beat the current spreadsheet workaround.",
      willingnessToPayScore: willingnessToPay,
      sponsorshipIntent: willingnessToPay >= 4
        ? "The simulated user would pay for or sponsor this prototype."
        : "The simulated user is not ready to sponsor this prototype.",
      verdict: verdict,
      summary: summary
    )
  }
}
