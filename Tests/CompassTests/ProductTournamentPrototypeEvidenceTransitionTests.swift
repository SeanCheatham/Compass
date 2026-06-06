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
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let updatedProductHypothesis = try #require(
      outcome.config.productHypotheses.first { $0.id == fixture.contender.productHypothesisID })
    let losingProductHypothesis = try #require(
      outcome.config.productHypotheses.first {
        $0.id == fixture.losingContender.productHypothesisID
      })
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )
    let proofOverview = ProductTournamentRoundThreePrototypeOverview.items(
      config: fixture.config,
      evidenceIndex: index
    )
    let proofOverviewItem = try #require(proofOverview.first)
    let postWinnerProofOverview = ProductTournamentRoundThreePrototypeOverview.items(
      config: outcome.config,
      evidenceIndex: index
    )
    let postWinnerDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: outcome.config,
      evidenceIndex: index
    )

    try #require(proposal.recommendation == .selectWinner)
    try #require(proofOverview.count == 1)
    try #require(proofOverviewItem.recommendation == .selectWinner)
    try #require(proofOverviewItem.completedRunCount == 3)
    try #require(proofOverviewItem.currentAlternativeProofCount == 3)
    try #require(proofOverviewItem.prototypeUseProofCount == 3)
    try #require(proofOverviewItem.evidenceRunIDs.contains("\(fixture.contender.id)-round-3-0"))
    try #require(proofOverviewItem.contextLine.contains("round_3_prototype_proof contender"))
    try #require(proofOverviewItem.contextLine.contains("recommendation select_winner"))
    try #require(proofOverviewItem.contextLine.contains("willingness_to_pay 5.0/5"))
    try #require(proofOverviewItem.contextLine.contains("prototype_use_proofs 3"))
    try #require(updatedTournament.status == .completed)
    try #require(updatedTournament.currentRoundID == fixture.prototypeRound.id)
    try #require(updatedPrototypeRound.status == .completed)
    try #require(updatedPrototypeRound.contenderIDs == [fixture.contender.id])
    try #require(updatedContender.status == .winner)
    try #require(losingContender.status == .eliminated)
    try #require(updatedExperiment.decision == .promote)
    try #require(updatedProductHypothesis.status == .promoted)
    try #require(losingProductHypothesis.status == .rejected)
    try #require(
      Set(outcome.affectedContenderIDs) == [fixture.contender.id, fixture.losingContender.id])
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("winner"))
    try #require(digest.contains("Round 3 prototype proof overview"))
    try #require(digest.contains("round_3_prototype_proof contender \(fixture.contender.id)"))
    try #require(digest.contains("recommendation select_winner"))
    try #require(digest.contains("willingness_to_pay 5.0/5"))
    try #require(digest.contains("Round 3 prototype transition"))
    try #require(digest.contains("recommendation select_winner"))
    try #require(postWinnerProofOverview.isEmpty)
    try #require(!postWinnerDigest.contains("Round 3 prototype proof overview"))
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
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
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
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let updatedProductHypothesis = try #require(
      outcome.config.productHypotheses.first { $0.id == fixture.contender.productHypothesisID })

    try #require(outcome.proposal.recommendation == .eliminate)
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.prototypeRound.id)
    try #require(updatedContender.status == .eliminated)
    try #require(updatedExperiment.decision == .kill)
    try #require(updatedProductHypothesis.status == .rejected)
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

  @Test func strongPrototypeScoresWithoutUseProofOnlyGatherEvidence() throws {
    let fixture = try roundThreeFixture()
    let records = prototypeEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The scorecard is strong but no trace proves the prototype was exercised.",
      includePrototypeUseProof: false
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
    try #require(proposal.prototypeUseProofCount == 0)
    try #require(proposal.digestLine.contains("prototype_use_proofs 0"))
    try #require(proposal.detail.contains("0 prototype-use proof"))
    try #require(
      ProductTournamentPrototypeEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.prototypeRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func traceHashAndRationaleWithoutCompletedUseProofDoNotSelectWinner() throws {
    let fixture = try roundThreeFixture()
    let records = prototypeEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The prototype has trace artifacts, but no completed-use proof was derived.",
      includePrototypeUseProof: true,
      completedUseProof: false
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

    try #require(records.allSatisfy { $0.traceHash?.isEmpty == false })
    try #require(records.allSatisfy { !$0.personaActionRationales.isEmpty })
    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.prototypeUseProofCount == 0)
    try #require(proposal.detail.contains("0 prototype-use proof"))
  }

  @Test func roundThreePrototypeOverviewShowsActiveWinnerProofBeforeEvidence() throws {
    let fixture = try roundThreeFixture()
    let index = ProductTournamentEvidenceIndex.build(records: [])

    let overview = ProductTournamentRoundThreePrototypeOverview.items(
      config: fixture.config,
      evidenceIndex: index
    )
    let item = try #require(overview.first)
    let contextLines = ProductTournamentRoundThreePrototypeOverview.contextLines(
      config: fixture.config,
      evidenceIndex: index
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )

    try #require(overview.count == 1)
    try #require(item.tournamentID == fixture.tournament.id)
    try #require(item.roundID == fixture.prototypeRound.id)
    try #require(item.contenderID == fixture.contender.id)
    try #require(item.experimentID == fixture.experiment.id)
    try #require(item.recommendation == .gatherEvidence)
    try #require(item.completedRunCount == 0)
    try #require(item.runCount == 0)
    try #require(item.currentAlternativeProofCount == 0)
    try #require(item.displaySubtitle.contains("Gather Evidence"))
    try #require(item.contextLine.contains("no scoped evidence"))
    try #require(item.contextLine.contains("prototype_scope"))
    try #require(item.contextLine.contains(fixture.experiment.id))
    try #require(item.helpSummary.contains(fixture.experiment.branchName))
    try #require(contextLines.first == "Round 3 prototype proof overview:")
    try #require(contextLines.joined(separator: "\n").contains("recommendation gather_evidence"))
    try #require(digest.contains("Round 3 prototype proof overview"))
    try #require(digest.contains("round_3_prototype_proof contender \(fixture.contender.id)"))
    try #require(digest.contains("recommendation gather_evidence"))
    try #require(digest.contains("no scoped evidence"))
  }
}

private struct RoundThreeFixture {
  var config: ProductTournamentConfig
  var tournament: ProductTournament
  var prototypeRound: ProductTournamentRound
  var contender: ProductTournamentContender
  var losingContender: ProductTournamentContender
  var experiment: ProductTournamentExperiment
  var hypothesis: ProductHypothesis
}

private func roundThreeFixture() throws -> RoundThreeFixture {
  var config = ProductTournamentConfig.seedDefaults(
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
  let experiment = try #require(config.tournamentExperiments.first { $0.id == experimentID })
  let hypothesis = try #require(
    config.productHypotheses.first { $0.id == contender.productHypothesisID })

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
    hypothesis: hypothesis
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
  summary: String,
  includePrototypeUseProof: Bool = true,
  completedUseProof: Bool? = nil
) -> [ProductTournamentEvidenceRecord] {
  let completedUseProof = completedUseProof ?? includePrototypeUseProof
  let segments = Array(fixture.config.userSegments)
  return (0..<count).map { index in
    let segment = segments[index % max(1, segments.count)]
    return ProductTournamentEvidenceRecord(
      id: "\(fixture.contender.id)-round-3-\(index)",
      experimentID: fixture.experiment.id,
      productHypothesisID: fixture.contender.productHypothesisID,
      painID: fixture.hypothesis.painID,
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
      traceHash: includePrototypeUseProof ? "round-3-trace-\(index)" : nil,
      completedUseProof: completedUseProof,
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
      personaActionRationales: includePrototypeUseProof
        ? [
          "The simulated user exercised the low-medium fidelity prototype before judging sponsorship."
        ]
        : [],
      verdict: verdict,
      summary: summary
    )
  }
}
