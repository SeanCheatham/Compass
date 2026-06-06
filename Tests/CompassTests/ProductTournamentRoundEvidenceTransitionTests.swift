import Foundation
import Testing

@testable import Compass

struct ProductTournamentRoundEvidenceTransitionTests {
  @Test func strongFeasibilityEvidenceAdvancesContenderToProductImplementationRound() throws {
    let fixture = try roundTwoFixture()
    let records = try evidenceRecords(
      fixture: fixture,
      score: 5,
      verdict: .strongPull,
      summary: "The core technology works against the current workaround."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentRoundEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.coreRound.id,
        config: fixture.config,
        evidenceIndex: index
      )
    )
    let outcome = try ProductTournamentRoundEvidenceTransitioner.apply(
      proposal: proposal,
      to: fixture.config,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedCoreRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.coreRound.id })
    let updatedProductImplementationRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.productImplementationRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let updatedExperiment = try #require(
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )
    let proofOverview = ProductTournamentRoundTwoProofOverview.items(
      config: fixture.config,
      evidenceIndex: index
    )
    let proofOverviewItem = try #require(proofOverview.first)
    let postTransitionProofOverview = ProductTournamentRoundTwoProofOverview.items(
      config: outcome.config,
      evidenceIndex: index
    )
    let postTransitionDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: outcome.config,
      evidenceIndex: index
    )

    try #require(proposal.recommendation == .advanceToProductImplementation)
    try #require(proofOverview.count == 1)
    try #require(proofOverviewItem.recommendation == .advanceToProductImplementation)
    try #require(proofOverviewItem.completedRunCount == 2)
    try #require(proofOverviewItem.distinctPersonaCount == 2)
    try #require(proofOverviewItem.experienceUseProofCount == 2)
    try #require(proofOverviewItem.evidenceRunIDs.contains("\(fixture.contender.id)-round-2-0"))
    try #require(proofOverviewItem.contextLine.contains("round_2_proof contender"))
    try #require(proofOverviewItem.contextLine.contains("core_technology_proof"))
    try #require(proofOverviewItem.contextLine.contains("recommendation advance_to_product_implementation"))
    try #require(proofOverviewItem.contextLine.contains("experience_use_proofs 2"))
    try #require(updatedTournament.currentRoundID == fixture.productImplementationRound.id)
    try #require(updatedCoreRound.status == .completed)
    try #require(updatedProductImplementationRound.status == .active)
    try #require(updatedProductImplementationRound.contenderIDs == [fixture.contender.id])
    try #require(updatedContender.status == .narrowed)
    try #require(updatedExperiment.decision == .keepGoing)
    try #require(outcome.toRoundID == fixture.productImplementationRound.id)
    try #require(outcome.userMessage.contains("Round 3"))
    try #require(digest.contains("Round 2 core-technology proof overview"))
    try #require(digest.contains("round_2_proof contender \(fixture.contender.id)"))
    try #require(digest.contains("recommendation advance_to_product_implementation"))
    try #require(digest.contains("core_technology_proof"))
    try #require(digest.contains("Round 2 evidence transition"))
    try #require(digest.contains("recommendation advance_to_product_implementation"))
    try #require(postTransitionProofOverview.isEmpty)
    try #require(!postTransitionDigest.contains("Round 2 core-technology proof overview"))
  }

  @Test func weakFeasibilityEvidenceEliminatesContender() throws {
    let fixture = try roundTwoFixture()
    let records = try evidenceRecords(
      fixture: fixture,
      score: 1,
      verdict: .weak,
      objections: ["The core technology does not beat the current workflow."],
      missingCapabilities: ["current_alternative_advantage"],
      summary: "The feasibility proof is too weak."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let outcome = try ProductTournamentRoundEvidenceTransitioner.applyBestProposal(
      tournamentID: fixture.tournament.id,
      roundID: fixture.coreRound.id,
      to: fixture.config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let updatedProductImplementationRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.productImplementationRound.id })
    let updatedExperiment = try #require(
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let updatedProductTournamentContenderPlan = try #require(
      outcome.config.contenderPlans.first { $0.id == fixture.contender.contenderPlanID })

    try #require(outcome.proposal.recommendation == .eliminate)
    try #require(updatedTournament.currentRoundID == fixture.coreRound.id)
    try #require(updatedContender.status == .eliminated)
    try #require(!updatedProductImplementationRound.contenderIDs.contains(fixture.contender.id))
    try #require(updatedExperiment.decision == .kill)
    try #require(updatedProductTournamentContenderPlan.status == .rejected)
    try #require(outcome.toRoundID == nil)
    try #require(outcome.userMessage.contains("Eliminated"))
  }

  @Test func mixedFeasibilityEvidenceMarksCoreTechnologyForRevision() throws {
    let fixture = try roundTwoFixture()
    let records = try evidenceRecords(
      fixture: fixture,
      score: 3,
      verdict: .unclear,
      objections: ["The proof needs a more inspectable source artifact."],
      missingCapabilities: ["inspectable_source_artifact"],
      summary: "The core technology is plausible but needs revision."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let outcome = try ProductTournamentRoundEvidenceTransitioner.applyBestProposal(
      tournamentID: fixture.tournament.id,
      roundID: fixture.coreRound.id,
      to: fixture.config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let updatedTournament = try #require(
      outcome.config.tournaments.first { $0.id == fixture.tournament.id })
    let updatedCoreRound = try #require(
      outcome.config.tournamentRounds.first { $0.id == fixture.coreRound.id })
    let updatedContender = try #require(
      outcome.config.tournamentContenders.first { $0.id == fixture.contender.id })
    let updatedExperiment = try #require(
      outcome.config.tournamentExperiments.first { $0.id == fixture.experiment.id })
    let followUpScope = ProductTournamentEvidenceScopeResolver.scope(
      experimentID: fixture.experiment.id,
      in: outcome.config
    )

    try #require(outcome.proposal.recommendation == .reviseCoreTechnology)
    try #require(updatedTournament.currentRoundID == fixture.coreRound.id)
    try #require(updatedCoreRound.status == .active)
    try #require(updatedContender.status == .needsRevision)
    try #require(updatedExperiment.decision == .narrow)
    try #require(outcome.toRoundID == nil)
    try #require(followUpScope?.roundID == fixture.coreRound.id)
    try #require(outcome.userMessage.contains("revision"))
  }

  @Test func singleFeasibilityRunOnlyRecommendsGatheringMoreEvidence() throws {
    let fixture = try roundTwoFixture()
    let record = try evidenceRecords(
      fixture: fixture,
      score: 5,
      verdict: .strongPull,
      summary: "One strong feasibility run is promising."
    )[0]
    let index = ProductTournamentEvidenceIndex.build(records: [record])

    let proposal = try #require(
      ProductTournamentRoundEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.coreRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(!proposal.isActionable)
    try #require(
      ProductTournamentRoundEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.coreRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func strongFeasibilityScoresWithoutUseProofOnlyGatherEvidence() throws {
    let fixture = try roundTwoFixture()
    let records = try evidenceRecords(
      fixture: fixture,
      score: 5,
      verdict: .strongPull,
      summary: "The scorecard is strong but no trace proves the contender was exercised.",
      includeExperienceUseProof: false
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentRoundEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.coreRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.experienceUseProofCount == 0)
    try #require(proposal.digestLine.contains("experience_use_proofs 0"))
    try #require(proposal.detail.contains("2 completed-use traces"))
    try #require(
      ProductTournamentRoundEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.coreRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func traceHashAndRationaleWithoutCompletedUseProofDoNotAdvanceRoundTwo() throws {
    let fixture = try roundTwoFixture()
    let records = try evidenceRecords(
      fixture: fixture,
      score: 5,
      verdict: .strongPull,
      summary: "The run has trace artifacts, but no completed-use proof was derived.",
      includeExperienceUseProof: true,
      completedUseProof: false
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentRoundEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.coreRound.id,
        config: fixture.config,
        evidenceIndex: index
      ).first
    )

    try #require(records.allSatisfy { $0.traceHash?.isEmpty == false })
    try #require(records.allSatisfy { !$0.personaActionRationales.isEmpty })
    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.experienceUseProofCount == 0)
    try #require(proposal.detail.contains("completed-use trace"))
  }

  @Test func roundTwoProofOverviewShowsActiveCoreTechnologyProofBeforeEvidence() throws {
    let fixture = try roundTwoFixture()
    let index = ProductTournamentEvidenceIndex.build(records: [])

    let overview = ProductTournamentRoundTwoProofOverview.items(
      config: fixture.config,
      evidenceIndex: index
    )
    let item = try #require(overview.first)
    let contextLines = ProductTournamentRoundTwoProofOverview.contextLines(
      config: fixture.config,
      evidenceIndex: index
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fixture.config,
      evidenceIndex: index
    )

    try #require(overview.count == 1)
    try #require(item.tournamentID == fixture.tournament.id)
    try #require(item.roundID == fixture.coreRound.id)
    try #require(item.contenderID == fixture.contender.id)
    try #require(item.experimentID == fixture.experiment.id)
    try #require(item.recommendation == .gatherEvidence)
    try #require(item.completedRunCount == 0)
    try #require(item.runCount == 0)
    try #require(item.distinctPersonaCount == 0)
    try #require(item.displaySubtitle.contains("Gather Evidence"))
    try #require(item.contextLine.contains("no scoped evidence"))
    try #require(item.contextLine.contains("core_technology_proof"))
    try #require(item.contextLine.contains(fixture.experiment.id))
    try #require(item.helpSummary.contains(fixture.experiment.branchName))
    try #require(contextLines.first == "Round 2 core-technology proof overview:")
    try #require(contextLines.joined(separator: "\n").contains("recommendation gather_evidence"))
    try #require(digest.contains("Round 2 core-technology proof overview"))
    try #require(digest.contains("round_2_proof contender \(fixture.contender.id)"))
    try #require(digest.contains("recommendation gather_evidence"))
    try #require(digest.contains("no scoped evidence"))
  }
}

private struct RoundTwoFixture {
  var config: ProductTournamentConfig
  var tournament: ProductTournament
  var coreRound: ProductTournamentRound
  var productImplementationRound: ProductTournamentRound
  var contender: ProductTournamentContender
  var experiment: ProductTournamentExperiment
  var contenderPlan: ProductTournamentContenderPlan
}

private func roundTwoFixture() throws -> RoundTwoFixture {
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
  let experimentID = try #require(contender.experimentID)
  let experiment = try #require(config.tournamentExperiments.first { $0.id == experimentID })
  let contenderPlan = try #require(
    config.contenderPlans.first { $0.id == contender.contenderPlanID })

  config.tournaments[0].currentRoundID = coreRound.id
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == planRound.id }) {
    config.tournamentRounds[index].status = .completed
  }
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == coreRound.id }) {
    config.tournamentRounds[index].status = .active
    config.tournamentRounds[index].contenderIDs = [contender.id]
  }
  if let index = config.tournamentRounds.firstIndex(where: { $0.id == productImplementationRound.id }) {
    config.tournamentRounds[index].status = .planned
  }
  if let index = config.tournamentContenders.firstIndex(where: { $0.id == contender.id }) {
    config.tournamentContenders[index].status = .narrowed
  }

  return RoundTwoFixture(
    config: config,
    tournament: tournament,
    coreRound: coreRound,
    productImplementationRound: productImplementationRound,
    contender: contender,
    experiment: experiment,
    contenderPlan: contenderPlan
  )
}

private func evidenceRecords(
  fixture: RoundTwoFixture,
  score: Int,
  verdict: ProductTournamentEvidenceVerdict,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  summary: String,
  includeExperienceUseProof: Bool = true,
  completedUseProof: Bool? = nil
) throws -> [ProductTournamentEvidenceRecord] {
  let completedUseProof = completedUseProof ?? includeExperienceUseProof
  return fixture.config.userSegments.prefix(2).enumerated().map { index, segment in
    ProductTournamentEvidenceRecord(
      id: "\(fixture.contender.id)-round-2-\(index)",
      experimentID: fixture.experiment.id,
      contenderPlanID: fixture.contender.contenderPlanID,
      painID: fixture.contenderPlan.painID,
      tournamentID: fixture.tournament.id,
      roundID: fixture.coreRound.id,
      contenderID: fixture.contender.id,
      branchName: fixture.experiment.branchName,
      commitSha: "abc123",
      scenarioID: "scenario-\(index)",
      personaID: segment.id,
      mode: .modelFree,
      status: .completed,
      startedAt: Double(index),
      endedAt: Double(index + 1),
      traceHash: includeExperienceUseProof ? "round-2-trace-\(index)" : nil,
      completedUseProof: completedUseProof,
      scores: ProductTournamentEvidenceScores(
        painRecognition: score,
        workflowImprovement: score,
        alternativeAdvantage: score,
        switchingReadiness: score,
        continuedUsePull: score
      ),
      objections: objections,
      missingCapabilities: missingCapabilities,
      currentAlternativeComparison: "The simulated user compared against the current workaround.",
      personaActionRationales: includeExperienceUseProof
        ? ["The simulated user exercised the core technology proof before judging feasibility."]
        : [],
      verdict: verdict,
      summary: summary
    )
  }
}
