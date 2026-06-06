import Foundation
import Testing

@testable import Compass

struct ProductTournamentProductImplementationEvidenceTransitionTests {
  @Test func strongProductImplementationEvidenceSelectsTournamentWinner() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The product implementation beats the current workaround and creates sponsor pull."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      )
    )
    let outcome = try ProductTournamentProductImplementationEvidenceTransitioner.apply(
      proposal: proposal,
      to: fixture.config,
      now: Date(timeIntervalSince1970: 2_500)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedProductImplementationRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.productImplementationRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let losingContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.losingContender.id })
    let updatedExperiment = try #require(
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let updatedProductTournamentContenderPlan = try #require(
      outcome.config.contenderPlans.first { $0.id == fixture.contender.contenderPlanID })
    let losingProductTournamentContenderPlan = try #require(
      outcome.config.contenderPlans.first {
        $0.id == fixture.losingContender.contenderPlanID
      })
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )
    let proofOverview = ProductTournamentRoundThreeProductImplementationOverview.items(
      config: fixture.config,
      evidenceIndex: index
    )
    let proofOverviewItem = try #require(proofOverview.first)
    let postWinnerProofOverview = ProductTournamentRoundThreeProductImplementationOverview.items(
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
    try #require(proofOverviewItem.implementationUseProofCount == 3)
    try #require(proofOverviewItem.evidenceRunIDs.contains("\(fixture.contender.id)-round-3-0"))
    try #require(proofOverviewItem.contextLine.contains("round_3_product_implementation_proof contender"))
    try #require(proofOverviewItem.contextLine.contains("recommendation select_winner"))
    try #require(proofOverviewItem.contextLine.contains("willingness_to_pay 5.0/5"))
    try #require(proofOverviewItem.contextLine.contains("implementation_use_proofs 3"))
    try #require(updatedTournament.status == .completed)
    try #require(updatedTournament.currentRoundID == fixture.productImplementationRound.id)
    try #require(updatedProductImplementationRound.status == .completed)
    try #require(updatedProductImplementationRound.contenderIDs == [fixture.contender.id])
    try #require(updatedContender.status == .winner)
    try #require(losingContender.status == .eliminated)
    try #require(updatedExperiment.decision == .promote)
    try #require(updatedProductTournamentContenderPlan.status == .promoted)
    try #require(losingProductTournamentContenderPlan.status == .rejected)
    try #require(
      Set(outcome.affectedContenderIDs) == [fixture.contender.id, fixture.losingContender.id])
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("winner"))
    try #require(digest.contains("Round 3 product implementation proof overview"))
    try #require(digest.contains("round_3_product_implementation_proof contender \(fixture.contender.id)"))
    try #require(digest.contains("recommendation select_winner"))
    try #require(digest.contains("willingness_to_pay 5.0/5"))
    try #require(digest.contains("Round 3 product implementation transition"))
    try #require(digest.contains("recommendation select_winner"))
    try #require(postWinnerProofOverview.isEmpty)
    try #require(!postWinnerDigest.contains("Round 3 product implementation proof overview"))
  }

  @Test func mixedProductImplementationEvidenceMarksContenderForRevision() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 3,
      willingnessToPay: 2,
      verdict: .unclear,
      objections: ["The sponsor proof needs clearer export and audit context."],
      missingCapabilities: ["sponsor_export"],
      summary: "The product implementation needs one more fidelity pass."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let outcome = try ProductTournamentProductImplementationEvidenceTransitioner.applyBestProposal(
      tournamentID: fixture.tournament.id,
      roundID: fixture.productImplementationRound.id,
      to: fixture.config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_500)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedProductImplementationRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.productImplementationRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let updatedExperiment = try #require(
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let followUpScope = ProductTournamentEvidenceScopeResolver.scope(
      experimentID: fixture.experiment.id,
      in: outcome.config
    )

    try #require(outcome.proposal.recommendation == .reviseImplementation)
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.productImplementationRound.id)
    try #require(updatedProductImplementationRound.status == .active)
    try #require(updatedContender.status == .needsRevision)
    try #require(updatedExperiment.decision == .narrow)
    try #require(followUpScope?.roundID == fixture.productImplementationRound.id)
    try #require(outcome.userMessage.contains("revision"))
  }

  @Test func weakProductImplementationEvidenceEliminatesContender() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 2,
      score: 1,
      willingnessToPay: 1,
      verdict: .weak,
      objections: ["The product implementation does not beat the spreadsheet."],
      missingCapabilities: ["workflow_advantage"],
      summary: "The product implementation does not create enough pull."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let outcome = try ProductTournamentProductImplementationEvidenceTransitioner.applyBestProposal(
      tournamentID: fixture.tournament.id,
      roundID: fixture.productImplementationRound.id,
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
    let updatedProductTournamentContenderPlan = try #require(
      outcome.config.contenderPlans.first { $0.id == fixture.contender.contenderPlanID })

    try #require(outcome.proposal.recommendation == .eliminate)
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.productImplementationRound.id)
    try #require(updatedContender.status == .eliminated)
    try #require(updatedExperiment.decision == .kill)
    try #require(updatedProductTournamentContenderPlan.status == .rejected)
    try #require(outcome.userMessage.contains("Eliminated"))
  }

  @Test func twoStrongProductImplementationRunsOnlyGatherMoreEvidence() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 2,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "Two strong product implementation runs are promising."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(!proposal.isActionable)
    try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func strongProductImplementationScoresWithoutUseProofOnlyGatherEvidence() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The scorecard is strong but no trace proves the product implementation was exercised.",
      includeImplementationUseProof: false
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.implementationUseProofCount == 0)
    try #require(proposal.digestLine.contains("implementation_use_proofs 0"))
    try #require(proposal.detail.contains("0 implementation-use proof"))
    try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func traceHashAndRationaleWithoutCompletedUseProofDoNotSelectWinner() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The product implementation has trace artifacts, but no completed-use proof was derived.",
      includeImplementationUseProof: true,
      completedUseProof: false
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(records.allSatisfy { $0.traceHash?.isEmpty == false })
    try #require(records.allSatisfy { !$0.personaActionRationales.isEmpty })
    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.implementationUseProofCount == 0)
    try #require(proposal.detail.contains("0 implementation-use proof"))
  }

  @Test func roundThreeProductImplementationOverviewShowsActiveWinnerProofBeforeEvidence() throws {
    let fixture = try roundThreeFixture()
    let index = ProductTournamentEvidenceIndex.build(records: [])

    let overview = ProductTournamentRoundThreeProductImplementationOverview.items(
      config: fixture.config,
      evidenceIndex: index
    )
    let item = try #require(overview.first)
    let contextLines = ProductTournamentRoundThreeProductImplementationOverview.contextLines(
      config: fixture.config,
      evidenceIndex: index
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )

    try #require(overview.count == 1)
    try #require(item.tournamentID == fixture.tournament.id)
    try #require(item.roundID == fixture.productImplementationRound.id)
    try #require(item.contenderID == fixture.contender.id)
    try #require(item.experimentID == fixture.experiment.id)
    try #require(item.recommendation == .gatherEvidence)
    try #require(item.completedRunCount == 0)
    try #require(item.runCount == 0)
    try #require(item.currentAlternativeProofCount == 0)
    try #require(item.displaySubtitle.contains("Gather Evidence"))
    try #require(item.contextLine.contains("no scoped evidence"))
    try #require(item.contextLine.contains("implementation_scope"))
    try #require(item.contextLine.contains(fixture.experiment.id))
    try #require(item.helpSummary.contains(fixture.experiment.branchName))
    try #require(contextLines.first == "Round 3 product implementation proof overview:")
    try #require(contextLines.joined(separator: "\n").contains("recommendation gather_evidence"))
    try #require(digest.contains("Round 3 product implementation proof overview"))
    try #require(digest.contains("round_3_product_implementation_proof contender \(fixture.contender.id)"))
    try #require(digest.contains("recommendation gather_evidence"))
    try #require(digest.contains("no scoped evidence"))
  }
}

private struct RoundThreeFixture {
  var config: ProductTournamentConfig
  var tournament: ProductTournament
  var productImplementationRound: ProductTournamentRound
  var contender: ProductTournamentContender
  var losingContender: ProductTournamentContender
  var experiment: ProductTournamentExperiment
  var contenderPlan: ProductTournamentContenderPlan
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
  let productImplementationRound = try #require(config.tournamentRounds.first { $0.kind == .productImplementation })
  let contender = try #require(config.tournamentContenders.first)
  let losingContender = try #require(config.tournamentContenders.dropFirst().first)
  let experimentID = try #require(contender.experimentID)
  let experiment = try #require(config.tournamentExperiments.first { $0.id == experimentID })
  let contenderPlan = try #require(
    config.contenderPlans.first { $0.id == contender.contenderPlanID })

  config.tournaments[0].currentRoundID = productImplementationRound.id
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == planRound.id }) {
    config.tournamentRounds[index].status = .completed
  }
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == coreRound.id }) {
    config.tournamentRounds[index].status = .completed
    config.tournamentRounds[index].contenderIDs = [contender.id]
  }
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == productImplementationRound.id }) {
    config.tournamentRounds[index].status = .active
    config.tournamentRounds[index].contenderIDs = [contender.id]
  }
  if let index = config.tournamentContenders.firstIndex(where: { $0.id == contender.id }) {
    config.tournamentContenders[index].status = .narrowed
  }

  return RoundThreeFixture(
    config: config,
    tournament: tournament,
    productImplementationRound: productImplementationRound,
    contender: contender,
    losingContender: losingContender,
    experiment: experiment,
    contenderPlan: contenderPlan
  )
}

private func productImplementationEvidenceRecords(
  fixture: RoundThreeFixture,
  count: Int,
  score: Int,
  willingnessToPay: Int,
  verdict: ProductTournamentEvidenceVerdict,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  summary: String,
  includeImplementationUseProof: Bool = true,
  completedUseProof: Bool? = nil
) -> [ProductTournamentEvidenceRecord] {
  let completedUseProof = completedUseProof ?? includeImplementationUseProof
  let segments = Array(fixture.config.userSegments)
  return (0..<count).map { index in
    let segment = segments[index % max(1, segments.count)]
    return ProductTournamentEvidenceRecord(
      id: "\(fixture.contender.id)-round-3-\(index)",
      experimentID: fixture.experiment.id,
      contenderPlanID: fixture.contender.contenderPlanID,
      painID: fixture.contenderPlan.painID,
      tournamentID: fixture.tournament.id,
      roundID: fixture.productImplementationRound.id,
      contenderID: fixture.contender.id,
      branchName: fixture.experiment.branchName,
      commitSha: "def456",
      scenarioID: "product-implementation-scenario-\(index)",
      personaID: segment.id,
      mode: .modelFree,
      status: .completed,
      startedAt: Double(index),
      endedAt: Double(index + 1),
      traceHash: includeImplementationUseProof ? "round-3-trace-\(index)" : nil,
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
      currentAlternativeComparison: "The product implementation beat the current spreadsheet workaround.",
      willingnessToPayScore: willingnessToPay,
      sponsorshipIntent: willingnessToPay >= 4
        ? "The simulated user would pay for or sponsor this product implementation."
        : "The simulated user is not ready to sponsor this product implementation.",
      personaActionRationales: includeImplementationUseProof
        ? [
          "The simulated user exercised the low-medium fidelity product implementation before judging sponsorship."
        ]
        : [],
      verdict: verdict,
      summary: summary
    )
  }
}
