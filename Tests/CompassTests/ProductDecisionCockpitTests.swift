import Foundation
import Testing

@testable import Compass

struct ProductDecisionCockpitTests {
  @Test func emptyConfigBuildsEmptyCockpit() throws {
    let cockpit = ProductDecisionCockpit.build(
      config: .empty,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    )

    try #require(cockpit.isEmpty)
    try #require(cockpit.activePain == nil)
    try #require(cockpit.activeTournament == nil)
    try #require(cockpit.activeRound == nil)
    try #require(cockpit.contenders.isEmpty)
    try #require(cockpit.evidenceMatrix.isEmpty)
    try #require(cockpit.nextMove == nil)
  }

  @Test func roundOnePlanProofBuildsStableContenderLanesAndNextMove() throws {
    let config = seededConfig()
    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    )

    let tournament = try #require(cockpit.activeTournament)
    let round = try #require(cockpit.activeRound)
    let nextMove = try #require(cockpit.nextMove)
    let firstLane = try #require(cockpit.contenders.first)

    try #require(!cockpit.isEmpty)
    try #require(tournament.title == "LedgerLift product tournament")
    try #require(tournament.contenderCount == 2)
    try #require(round.productTitle == "Round 1: Plan proof")
    try #require(Set(cockpit.contenders.map(\.id)) == Set(config.tournamentContenders.map(\.id)))
    try #require(firstLane.title == nextMove.targetContender)
    try #require(firstLane.proofDebt.readinessState == "Plan proof missing")
    try #require(firstLane.proofDebt.nextProofTarget == "operator and economic-buyer plan evaluations")
    try #require(firstLane.evidenceSignals.map(\.dimension) == EvidenceDimension.defaultOrder)
    try #require(cockpit.evidenceMatrix.dimensions == EvidenceDimension.defaultOrder)
    try #require(cockpit.evidenceMatrix.rows.count == 2)
    try #require(nextMove.actionKind == .runPlanProof)
    try #require(nextMove.actionTitle == "Run plan proof")
    try #require(nextMove.why.contains(firstLane.title))
  }

  @Test func roundTwoLockedImplementationTargetBlocksSiblingInProductTerms() throws {
    let config = roundTwoLockedConfig()
    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    )

    let round = try #require(cockpit.activeRound)
    let target = try #require(
      ProductTournamentRoundImplementationTargetResolver.defaultActiveRoundTwoTarget(in: config)
    )
    let targetLane = try #require(cockpit.contenders.first { $0.id == target.contenderID })
    let blockedLane = try #require(cockpit.contenders.first { $0.id != target.contenderID })

    try #require(round.productTitle == "Round 2: Core technology")
    try #require(targetLane.activeRoundState.state == .active)
    try #require(blockedLane.activeRoundState.state == .blocked)
    try #require(blockedLane.proofDebt.readinessState == "Core-technology proof locked")
    try #require(blockedLane.proofDebt.missingGates[0].contains(targetLane.title))
    try #require(
      blockedLane.proofDebt.auditReferences.contains {
        $0.kind == .experiment && $0.value == target.experimentID
      }
    )
  }

  @Test func roundThreeWinnerReadinessCarriesProductUseProofDebt() throws {
    let config = roundThreeWinnerConfig()
    let winner = config.tournamentContenders[0]
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [
        evidenceRecord(
          id: "product-use-run-one",
          config: config,
          contender: winner,
          personaID: "operator-persona",
          endedAt: 20
        )
      ],
      now: Date(timeIntervalSince1970: 30)
    )
    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: true
    )

    let lane = try #require(cockpit.contenders.first { $0.id == winner.id })
    let useProof = try #require(
      lane.evidenceSignals.first { $0.dimension == .productUseProof }
    )

    try #require(lane.status == .winner)
    try #require(lane.activeRoundState.state == .winner)
    try #require(lane.proofDebt.completedCount == 1)
    try #require(lane.proofDebt.blockingCount > 0)
    try #require(lane.proofDebt.nextProofTarget == "additional completed product-use proof")
    try #require(useProof.countLabel == "1/2")
    try #require(useProof.strength == .progressing)
  }

  @Test func latestProofMovementSummaryComesFromScoreboardAudit() throws {
    var config = seededConfig()
    let evidenceIndex = ProductTournamentEvidenceIndex.empty
    let target = try #require(
      TournamentAutomationProofTargetAdvisor.targets(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first
    )
    config.tournamentAutomationCycleAudits = [
      TournamentAutomationCycleAudit(
        id: "audit-plan-proof-one",
        startedAt: 40,
        endedAt: 41,
        executedStepIDs: ["\(target.experimentID):run_plan_proof:\(target.contenderID ?? "contender")"],
        experimentIDs: [target.experimentID],
        messages: ["Ran focused proof."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["plan-evaluation-one"],
        completedEvidenceRunCount: 1,
        startingProofDebtCount: 4,
        endingProofDebtCount: 2,
        startingProofDebtSummary: "Plan proof missing",
        endingProofDebtSummary: "Buyer proof missing",
        proofTargetSummaries: [target.auditSummary],
        stopReason: .reachedStepLimit,
        stopDetail: "Finished one proof step.",
        userMessage: "Proof debt reduced."
      )
    ]

    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: false
    )
    let movement = try #require(cockpit.latestMovement)

    try #require(movement.beforeCount == 4)
    try #require(movement.afterCount == 2)
    try #require(movement.delta == -2)
    try #require(movement.title.contains("Cleared"))
    try #require(
      movement.auditReferences.contains {
        $0.kind == .automationAudit && $0.value == "audit-plan-proof-one"
      }
    )
  }

  @Test func primaryLabelsHideRawReferencesButAuditRetainsThem() throws {
    let config = seededConfig()
    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    )
    let primary = primaryText(in: cockpit)
    let audit = cockpit.auditReferences.map(\.value).joined(separator: "\n")
    let rawValues = [
      config.tournaments[0].id,
      config.tournamentRounds[0].id,
      config.tournamentContenders[0].id,
      config.tournamentExperiments[0].id,
      config.tournamentExperiments[0].branchName,
    ]

    for rawValue in rawValues {
      try #require(!primary.contains(rawValue), "Primary text leaked \(rawValue).")
      try #require(audit.contains(rawValue), "Audit references should retain \(rawValue).")
    }
  }

  @Test func productDecisionCockpitFileDoesNotImportSwiftUI() throws {
    let source = try String(
      contentsOfFile: "Sources/Compass/ProductDecisionCockpit.swift",
      encoding: .utf8
    )

    try #require(!source.contains("import SwiftUI"))
  }
}

private func seededConfig() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 10)
  )
}

private func roundTwoLockedConfig() -> ProductTournamentConfig {
  var config = seededConfig()
  let roundTwoID = config.tournamentRounds[1].id
  config.tournaments[0].currentRoundID = roundTwoID
  config.tournamentRounds[0].status = .completed
  config.tournamentRounds[1].status = .active
  config.tournamentRounds[2].status = .planned
  config.tournamentContenders[0].status = .narrowed
  config.tournamentContenders[1].status = .competing
  return config
}

private func roundThreeWinnerConfig() -> ProductTournamentConfig {
  var config = seededConfig()
  let roundThreeID = config.tournamentRounds[2].id
  config.tournaments[0].currentRoundID = roundThreeID
  config.tournamentRounds[0].status = .completed
  config.tournamentRounds[1].status = .completed
  config.tournamentRounds[2].status = .active
  config.tournamentContenders[0].status = .winner
  config.tournamentContenders[1].status = .eliminated
  config.tournamentExperiments[0].decision = .promote
  return config
}

private func evidenceRecord(
  id: String,
  config: ProductTournamentConfig,
  contender: ProductTournamentContender,
  personaID: String,
  endedAt: Double
) -> ProductTournamentEvidenceRecord {
  let experiment = config.tournamentExperiments.first { $0.id == contender.experimentID }!
  let scenario = config.scenarios.first { $0.experimentID == experiment.id }!
  return ProductTournamentEvidenceRecord(
    id: id,
    experimentID: experiment.id,
    contenderPlanID: contender.contenderPlanID,
    painID: config.painHypotheses[0].id,
    tournamentID: contender.tournamentID,
    roundID: config.tournamentRounds[2].id,
    contenderID: contender.id,
    branchName: experiment.branchName,
    commitSha: "product-use-sha",
    scenarioID: scenario.id,
    personaID: personaID,
    mode: .personaModel,
    status: .completed,
    startedAt: endedAt - 1,
    endedAt: endedAt,
    completedUseProof: true,
    promptVersions: ["prompt-v1"],
    model: "persona-model",
    scores: ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 3,
      continuedUsePull: 4,
      willingnessToPay: 2
    ),
    currentAlternativeComparison: "The product is clearer than the weekly spreadsheet.",
    willingnessToPayScore: 2,
    sponsorshipIntent: "Needs more proof before sponsorship.",
    verdict: .promising,
    summary: "The product-use proof is promising but not yet broad enough."
  )
}

private func primaryText(in cockpit: ProductDecisionCockpit) -> String {
  var parts: [String] = []
  if let pain = cockpit.activePain {
    parts += [
      pain.title,
      pain.audience,
      pain.currentWorkaround,
      pain.costImpact,
    ] + pain.unknowns
  }
  if let tournament = cockpit.activeTournament {
    parts += [
      tournament.title,
      tournament.premise,
      tournament.statusLabel,
    ]
  }
  if let round = cockpit.activeRound {
    parts += [
      round.productTitle,
      round.gateDescription,
      round.statusLabel,
    ]
  }
  for lane in cockpit.contenders {
    parts += [
      lane.title,
      lane.promise,
      lane.currentAlternative,
      lane.tournamentPosition,
      lane.status.label,
      lane.activeRoundState.title,
      lane.activeRoundState.detail,
      lane.experimentSummary,
      lane.proofDebt.nextProofTarget,
      lane.proofDebt.readinessState,
    ]
    parts += lane.targetSegmentNames
    parts += lane.proofDebt.missingGates
    for signal in lane.evidenceSignals {
      parts += [
        signal.countLabel,
        signal.primaryPhrase,
        signal.supportingPhrase,
      ]
    }
  }
  if let nextMove = cockpit.nextMove {
    parts += [
      nextMove.actionTitle,
      nextMove.why,
      nextMove.expectedDecision,
      nextMove.targetContender ?? "",
      nextMove.targetPersona ?? "",
      nextMove.disabledReason ?? "",
    ]
  }
  if let movement = cockpit.latestMovement {
    parts += [
      movement.title,
      movement.detail,
      movement.postResultState,
    ]
  }
  return parts.joined(separator: "\n")
}
