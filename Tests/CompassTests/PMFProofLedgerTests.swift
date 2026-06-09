import Foundation
import Testing

@testable import Compass

struct PMFProofLedgerTests {
  @Test func emptyConfigBuildsEmptyLedger() throws {
    let ledger = PMFProofLedger.build(config: .empty, evidenceIndex: .empty)

    try #require(ledger.isEmpty)
    try #require(ledger.hypothesis.isEmpty)
    try #require(ledger.nextAction == nil)
    try #require(ledger.promptDigest.contains("No PMF hypothesis"))
  }

  @Test func activePlanProofDebtBecomesBuyerAndPayUnknowns() throws {
    let config = activatedConfig(roundKind: .productPlans)
    let contender = config.tournamentContenders[0]
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [],
      planEvaluationRecords: [
        planEvaluation(
          id: "buyer-proof-low-pay",
          config: config,
          contender: contender,
          personaID: "operator-persona",
          personaName: "Operations lead",
          willingnessToPay: 2,
          endedAt: 20
        )
      ],
      now: Date(timeIntervalSince1970: 25)
    )

    let ledger = PMFProofLedger.build(config: config, evidenceIndex: evidenceIndex)

    try #require(!ledger.isEmpty)
    try #require(ledger.hypothesis.pain.contains("Weekly reporting"))
    try #require(!ledger.hypothesis.promisedOutcome.isEmpty)
    try #require(ledger.unknowns.contains { $0.kind == PMFUnknownKind.buyer })
    try #require(ledger.unknowns.contains { $0.kind == PMFUnknownKind.willingnessToPay })
    try #require(ledger.nextAction?.kind == .runBuyerProof)
    try #require(ledger.evidence.first?.kind == .planEvaluation)
    try #require(ledger.promptDigest.count <= 2_000)
    try #require(ledger.promptDigest.contains("PMF Proof Ledger"))
  }

  @Test func roundTwoActiveStateCreatesFeasibilityAction() throws {
    var config = activatedConfig(roundKind: .coreTechnology)
    config.tournamentContenders[0].status = .narrowed

    let ledger = PMFProofLedger.build(config: config, evidenceIndex: .empty)

    try #require(ledger.unknowns.first?.kind == .feasibility)
    try #require(ledger.nextAction?.kind == .buildFeasibilitySlice)
    try #require(ledger.nextAction?.expectedTokenCostClass == .high)
    try #require(
      ledger.nextAction?.legacyReferences.contains {
        $0.kind == .roundID && $0.value == activeRound(in: config, .coreTechnology).id
      } == true)
  }

  @Test func roundThreeActiveStateCreatesUseAndSwitchingDebt() throws {
    var config = activatedConfig(roundKind: .productImplementation)
    config.tournamentContenders[0].status = .narrowed
    let contender = config.tournamentContenders[0]
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [
        scenarioEvidence(
          id: "one-use-proof",
          config: config,
          contender: contender,
          completedUseProof: true,
          endedAt: 30
        )
      ],
      now: Date(timeIntervalSince1970: 35)
    )

    let ledger = PMFProofLedger.build(config: config, evidenceIndex: evidenceIndex)

    try #require(ledger.unknowns.contains { $0.kind == .usability })
    try #require(ledger.unknowns.contains { $0.kind == .switching })
    try #require(ledger.nextAction?.kind == .runUseProof)
    try #require(ledger.evidence.first?.kind == .implementationUse)
  }

  @Test func winnerIsPreferredActiveHypothesis() throws {
    var config = activatedConfig(roundKind: .productImplementation)
    config.tournamentContenders[0].status = .eliminated
    config.tournamentContenders[1].status = .winner
    let winner = config.tournamentContenders[1]

    let ledger = PMFProofLedger.build(config: config, evidenceIndex: .empty)

    try #require(
      ledger.hypothesis.sourceReferences.contains {
        $0.kind == .contenderID && $0.value == winner.id
      })
    try #require(!ledger.hypothesis.promisedOutcome.isEmpty)
  }
}

private func activatedConfig(
  roundKind: ProductTournamentRoundKind
) -> ProductTournamentConfig {
  var config = ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain:
      "Weekly reporting takes too long for operations teams and managers lose visibility.",
    now: Date(timeIntervalSince1970: 10)
  )
  let roundID = activeRound(in: config, roundKind).id
  config.tournaments[0].currentRoundID = roundID
  for index in config.tournamentRounds.indices {
    config.tournamentRounds[index].status =
      config.tournamentRounds[index].kind == roundKind ? .active : .completed
  }
  return config
}

private func activeRound(
  in config: ProductTournamentConfig,
  _ kind: ProductTournamentRoundKind
) -> ProductTournamentRound {
  config.tournamentRounds.first { $0.kind == kind }!
}

private func planEvaluation(
  id: String,
  config: ProductTournamentConfig,
  contender: ProductTournamentContender,
  personaID: String,
  personaName: String,
  willingnessToPay: Int,
  endedAt: Double
) -> ProductTournamentPlanEvaluationRecord {
  let tournament = config.tournaments[0]
  let round = activeRound(in: config, .productPlans)
  return ProductTournamentPlanEvaluationRecord(
    id: id,
    tournamentID: tournament.id,
    roundID: round.id,
    contenderID: contender.id,
    contenderPlanID: contender.contenderPlanID,
    experimentID: contender.experimentID,
    painID: tournament.painID,
    personaID: personaID,
    personaName: personaName,
    startedAt: endedAt - 2,
    endedAt: endedAt,
    scores: ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 2,
      switchingReadiness: 2,
      continuedUsePull: 2,
      willingnessToPay: willingnessToPay
    ),
    willingnessToPayScore: willingnessToPay,
    estimatedMonthlyPriceCents: 1_900,
    commercialProofSummary: "Operator likes the workflow but cannot sponsor budget.",
    objections: ["Needs manager sponsorship."],
    currentAlternativeComparison: "Compared against the shared spreadsheet.",
    verdict: .unclear,
    summary: "Plan is plausible, but buyer sponsorship and pay intent remain unresolved.",
    rationale: ["Pain is recognized.", "Budget owner is not proven."]
  )
}

private func scenarioEvidence(
  id: String,
  config: ProductTournamentConfig,
  contender: ProductTournamentContender,
  completedUseProof: Bool,
  endedAt: Double
) -> ProductTournamentEvidenceRecord {
  let tournament = config.tournaments[0]
  let round = activeRound(in: config, .productImplementation)
  let experiment = config.tournamentExperiments.first { $0.id == contender.experimentID }!
  let scenario = config.scenarios.first { $0.experimentID == experiment.id }!
  return ProductTournamentEvidenceRecord(
    id: id,
    experimentID: experiment.id,
    contenderPlanID: contender.contenderPlanID,
    painID: tournament.painID,
    tournamentID: tournament.id,
    roundID: round.id,
    contenderID: contender.id,
    branchName: experiment.branchName,
    commitSha: experiment.currentSha ?? experiment.baseSha ?? "abc123",
    scenarioID: scenario.id,
    personaID: "operator-persona",
    mode: .personaModel,
    status: .completed,
    startedAt: endedAt - 4,
    endedAt: endedAt,
    completedUseProof: completedUseProof,
    scores: ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 4,
      alternativeAdvantage: 3,
      switchingReadiness: 2,
      continuedUsePull: 3,
      willingnessToPay: 2
    ),
    objections: ["Still needs a cleaner switch from spreadsheets."],
    currentAlternativeComparison: "",
    willingnessToPayScore: 2,
    sponsorshipIntent: "Not ready to sponsor yet.",
    verdict: .promising,
    summary: "The user completed the core reporting flow, but switching proof remains thin."
  )
}
