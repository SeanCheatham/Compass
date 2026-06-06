import Foundation
import Testing

@testable import Compass

@MainActor
struct ProductTournamentRoundProofOverviewTests {
  @Test func activeRoundControlsTheOnlyRoundSpecificProofOverview() async throws {
    let cases = try [
      ProofOverviewCase(
        name: "round-1-plan",
        activeKind: .productPlans,
        config: roundOneConfig(),
        expectedDigestHeading: "Round 1 plan-proof contender overview",
        expectedWorkbenchHeading: "Round 1 Proof Deltas",
        expectedWorkbenchAccessibilityIDPrefix: "round-1-proof-overview-",
        absentDigestHeadings: [
          "Round 2 core-technology proof overview",
          "Round 3 product implementation proof overview",
        ],
        absentWorkbenchHeadings: [
          "Core Technology Proof",
          "Product Implementation Winner Proof",
        ]
      ),
      ProofOverviewCase(
        name: "round-2-core-technology",
        activeKind: .coreTechnology,
        config: roundTwoConfig(),
        expectedDigestHeading: "Round 2 core-technology proof overview",
        expectedWorkbenchHeading: "Core Technology Proof",
        expectedWorkbenchAccessibilityIDPrefix: "round-2-proof-overview-",
        absentDigestHeadings: [
          "Round 1 plan-proof contender overview",
          "Round 3 product implementation proof overview",
        ],
        absentWorkbenchHeadings: [
          "Round 1 Proof Deltas",
          "Product Implementation Winner Proof",
        ]
      ),
      ProofOverviewCase(
        name: "round-3-product-implementation",
        activeKind: .productImplementation,
        config: roundThreeConfig(),
        expectedDigestHeading: "Round 3 product implementation proof overview",
        expectedWorkbenchHeading: "Product Implementation Winner Proof",
        expectedWorkbenchAccessibilityIDPrefix: "round-3-proof-overview-",
        absentDigestHeadings: [
          "Round 1 plan-proof contender overview",
          "Round 2 core-technology proof overview",
        ],
        absentWorkbenchHeadings: [
          "Round 1 Proof Deltas",
          "Core Technology Proof",
        ]
      ),
    ]

    for proofCase in cases {
      let evidenceIndex = ProductTournamentEvidenceIndex.build(records: [])
      let digest = ProductTournamentPlanningDigestFormatter.promptText(
        config: proofCase.config,
        evidenceIndex: evidenceIndex
      )
      let workbenchBody = try await workbenchBody(for: proofCase.config)

      try #require(
        digest.contains(proofCase.expectedDigestHeading),
        "Expected \(proofCase.name) context to include \(proofCase.expectedDigestHeading)."
      )
      try #require(
        workbenchBody.contains(proofCase.expectedWorkbenchHeading),
        "Expected \(proofCase.name) Workbench to include \(proofCase.expectedWorkbenchHeading)."
      )
      try #require(
        workbenchBody.contains("AccessibilityAttachmentModifier"),
        "Expected \(proofCase.name) Workbench proof rows to expose accessibility attachments."
      )
      for snippet in try proofCase.expectedDigestRowSnippets(evidenceIndex: evidenceIndex) {
        try #require(
          digest.contains(snippet),
          "Expected \(proofCase.name) context row to include \(snippet)."
        )
      }
      for accessibilityID in try proofCase.expectedWorkbenchAccessibilityIDs(
        evidenceIndex: evidenceIndex)
      {
        try #require(
          accessibilityID.hasPrefix(proofCase.expectedWorkbenchAccessibilityIDPrefix),
          "Expected \(proofCase.name) Workbench row id to start with \(proofCase.expectedWorkbenchAccessibilityIDPrefix)."
        )
      }
      for absentHeading in proofCase.absentDigestHeadings {
        try #require(
          !digest.contains(absentHeading),
          "Did not expect \(proofCase.name) context to include \(absentHeading)."
        )
      }
      for absentHeading in proofCase.absentWorkbenchHeadings {
        try #require(
          !workbenchBody.contains(absentHeading),
          "Did not expect \(proofCase.name) Workbench to include \(absentHeading)."
        )
      }
    }
  }

  @Test func workbenchProofTargetRowsShowTournamentPosition() async throws {
    let config = try roundOneConfig()
    let evidenceIndex = ProductTournamentEvidenceIndex.build(records: [])
    let target = try #require(
      TournamentAutomationProofTargetAdvisor.targets(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first
    )
    let summary = try #require(target.tournamentPositionSummary)
    let workbenchBody = try await workbenchBody(for: config)
    let includesPositionSummary = workbenchBody.contains(summary)

    try #require(summary.contains("Product plans contender"))
    try #require(summary.contains("active contender"))
    try #require(summary.contains("rival product"))
    try #require(includesPositionSummary)
  }

  @Test func proofTargetScoreboardGroupsRoundTargetsInContextAndWorkbench() async throws {
    let config = try roundOneConfig()
    let evidenceIndex = ProductTournamentEvidenceIndex.build(records: [])
    let item = try #require(
      TournamentAutomationProofTargetScoreboard.items(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first
    )
    let contextLines = TournamentAutomationProofTargetScoreboard.contextLines(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: false
    )
    let context = contextLines.joined(separator: "\n")
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )
    let workbenchBody = try await workbenchBody(for: config)
    let includesAllRivalPositions = item.rows.allSatisfy { row in
      row.tournamentPositionSummary?.contains("rival product") == true
    }
    let displayDetailIncludesRows = item.rows.allSatisfy { row in
      item.displayDetail.contains(row.contenderTitle)
    }
    let topActionRow = try #require(item.topActionRow)
    let topActionStep = try #require(item.topActionStep)
    let plannerStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      )
    )

    try #require(item.contenderCount == 2)
    try #require(item.targetCount == 2)
    try #require(item.displaySubtitle == "2/2 contender proof target(s)")
    try #require(item.workbenchAccessibilityID.hasPrefix("proof-target-scoreboard-"))
    try #require(item.runTopStepAccessibilityID == "\(item.workbenchAccessibilityID)-run-top-step")
    try #require(topActionRow.experimentID == topActionStep.experimentID)
    try #require(topActionRow.selectionID.contains(topActionStep.experimentID))
    try #require(topActionRow.selectionID.contains(item.roundID ?? "unknown-round"))
    try #require(
      topActionRow.workbenchAccessibilityID
        == "proof-target-scoreboard-row-\(topActionRow.selectionID)"
    )
    try #require(
      topActionRow.runSelectedStepAccessibilityID
        == "\(topActionRow.workbenchAccessibilityID)-run-selected-step"
    )
    try #require(topActionStep.id == plannerStep.id)
    try #require(topActionStep.kind == .runPlanProof)
    try #require(topActionStep.canExecute)
    try #require(item.topActionSummary.contains("Ready: Run Plan Proof"))
    try #require(item.topActionButtonTitle == "Run Top Proof")
    try #require(item.topActionStatusLabel == "More proof")
    try #require(item.topActionStatusSystemImage == "text.badge.checkmark")
    try #require(
      item.topActionStatusAccessibilityID
        == "\(item.workbenchAccessibilityID)-top-action-status"
    )
    try #require(item.topActionDetail.contains("Readiness: More proof"))
    try #require(topActionRow.selectedActionButtonTitle == "Run Selected Proof")
    try #require(topActionRow.nextStatusLabel == "More proof")
    try #require(topActionRow.nextStatusSystemImage == "text.badge.checkmark")
    try #require(
      topActionRow.nextStatusAccessibilityID
        == "\(topActionRow.workbenchAccessibilityID)-next-status"
    )
    try #require(topActionRow.postMovementNextStatusLabel == "More proof")
    try #require(topActionRow.postMovementNextStatusSystemImage == "text.badge.checkmark")
    try #require(topActionRow.contextSummary.contains("step ready run_plan_proof"))
    try #require(topActionRow.runPairSummary == "No audited proof run yet -> Ready: Run Plan Proof")
    try #require(topActionRow.contextSummary.contains("run_pair last no audited proof run"))
    try #require(topActionRow.contextSummary.contains("next_status More proof"))
    var transitionRow = topActionRow
    var transitionStep = topActionStep
    transitionStep.kind = .applyRoundTransition
    transitionStep.action.kind = .applyRoundTransition
    transitionRow.nextStep = transitionStep
    try #require(transitionRow.postMovementNextStatusLabel == "Transition ready")
    try #require(transitionRow.postMovementNextStatusSystemImage == "arrow.turn.down.right")
    var promoteRow = topActionRow
    var promoteStep = topActionStep
    promoteStep.kind = .applyDecision
    promoteStep.action.kind = .applyDecision
    promoteStep.action.targetDecision = .promote
    promoteRow.nextStep = promoteStep
    try #require(promoteRow.postMovementNextStatusLabel == "Promotion ready")
    try #require(promoteRow.postMovementNextStatusSystemImage == "arrow.up.circle")
    var killRow = promoteRow
    var killStep = promoteStep
    killStep.action.targetDecision = .kill
    killRow.nextStep = killStep
    try #require(killRow.postMovementNextStatusLabel == "Kill ready")
    try #require(killRow.postMovementNextStatusSystemImage == "xmark.circle")
    var noQueuedRow = topActionRow
    noQueuedRow.nextStep = nil
    try #require(noQueuedRow.postMovementNextStatusLabel == "No queued proof")
    try #require(noQueuedRow.postMovementNextStatusSystemImage == "checkmark.seal")
    try #require(includesAllRivalPositions)
    try #require(displayDetailIncludesRows)
    try #require(contextLines.first == "Tournament automation proof scoreboard:")
    try #require(context.contains("proof_target_scoreboard"))
    try #require(context.contains("top_action"))
    try #require(context.contains("top_action_status More proof"))
    try #require(context.contains("run_pair"))
    try #require(context.contains("Ready: Run Plan Proof"))
    try #require(digest.contains("Tournament automation proof scoreboard:"))
    try #require(digest.contains("proof_target_scoreboard"))
    try #require(digest.contains("top_action"))
    try #require(digest.contains("top_action_status More proof"))
    try #require(digest.contains("run_pair"))
    try #require(workbenchBody.contains("Proof Scoreboard"))
    try #require(workbenchBody.contains("WorkbenchStatusFact"))
    try #require(workbenchBody.contains("AccessibilityAttachmentModifier"))
  }

  @Test func proofTargetScoreboardShowsLatestAuditDebtMovement() async throws {
    var config = try roundOneConfig()
    let evidenceIndex = ProductTournamentEvidenceIndex.build(records: [])
    let target = try #require(
      TournamentAutomationProofTargetAdvisor.targets(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first
    )
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      )
    )
    let contenderID = try #require(step.contenderID)
    let roundID = try #require(step.roundID)
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "scoreboard-proof-delta",
        startedAt: 20,
        endedAt: 25,
        executedStepIDs: [step.id],
        experimentIDs: [step.experimentID],
        messages: ["Scoreboard top proof ran one focused plan proof."],
        maxSteps: 1,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["scoreboard-proof-run"],
        completedEvidenceRunCount: 1,
        startingProofDebtCount: 6,
        endingProofDebtCount: 4,
        startingProofDebtSummary:
          "\(step.experimentID): contender \(contenderID), round \(roundID), Round 1 plan proof had 6 proof debt item(s).",
        endingProofDebtSummary:
          "\(step.experimentID): contender \(contenderID), round \(roundID), Round 1 plan proof had 4 proof debt item(s).",
        proofTargetSummaries: [target.auditSummary],
        stopReason: .reachedStepLimit,
        stopDetail: "Reached one proof scoreboard step.",
        userMessage: "Scoreboard top proof reduced proof debt for \(contenderID)."
      )
    )
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "scoreboard-mismatched-delta",
        startedAt: 30,
        endedAt: 35,
        executedStepIDs: [step.id],
        experimentIDs: [step.experimentID],
        messages: ["A newer scoped audit should not attach to the wrong proof row."],
        maxSteps: 1,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["scoreboard-mismatch-run"],
        completedEvidenceRunCount: 1,
        startingProofDebtCount: 4,
        endingProofDebtCount: 7,
        startingProofDebtSummary:
          "\(step.experimentID): contender other-contender, round later-round, proof had 4 proof debt item(s).",
        endingProofDebtSummary:
          "\(step.experimentID): contender other-contender, round later-round, proof had 7 proof debt item(s).",
        stopReason: .reachedStepLimit,
        stopDetail: "Reached one mismatched proof scoreboard step.",
        userMessage: "This newer audit belongs to another scoped proof target."
      )
    )

    let item = try #require(
      TournamentAutomationProofTargetScoreboard.items(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first
    )
    let row = try #require(item.rows.first { $0.experimentID == step.experimentID })
    let movement = try #require(row.latestDebtMovement)
    let audit = try #require(
      config.tournamentAutomationCycleAudits.first { $0.id == "scoreboard-proof-delta" }
    )
    let focus = try #require(
      TournamentAutomationProofTargetScoreboard.focus(
        after: audit,
        config: config,
        evidenceIndex: evidenceIndex,
        preferredStep: step,
        isPersonaModelAvailable: false
      )
    )
    let context = TournamentAutomationProofTargetScoreboard.contextLines(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: false
    )
    .joined(separator: "\n")
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )
    let workbenchBody = try await workbenchBody(for: config)

    try #require(movement.auditID == "scoreboard-proof-delta")
    try #require(movement.displaySummary == "Latest audit cleared 2 proof debt (6 -> 4)")
    try #require(movement.lastRunSummary == "Last run cleared 2 proof debt")
    try #require(movement.startCountLabel == "6")
    try #require(movement.endCountLabel == "4")
    try #require(movement.deltaLabel == "-2")
    try #require(movement.movementLabel == "Cleared 2")
    try #require(movement.movementDetail == "cleared 2 proof debt")
    try #require(movement.postResultStateSummary == "Proof debt reduced")
    try #require(movement.movementSystemImage == "arrow.down.circle")
    try #require(movement.resultStripSummary == "Proof movement 6 -> 4 (-2); cleared 2 proof debt")
    try #require(row.firstEvidenceRunID == "scoreboard-proof-run")
    try #require(row.proofMovementAccessibilityID == "\(row.workbenchAccessibilityID)-proof-movement")
    try #require(row.postMovementNextSummary == "Proof debt reduced; next Ready: Run Plan Proof")
    try #require(row.postMovementNextStatusLabel == "More proof")
    try #require(row.postMovementNextStatusSystemImage == "text.badge.checkmark")
    try #require(row.postMovementNextDetail.contains(movement.resultStripSummary))
    try #require(row.postMovementNextDetail.contains("Current next step:"))
    try #require(row.postMovementNextDetail.contains(row.nextStepDetail))
    try #require(row.postMovementNextDetail.contains("Readiness: More proof."))
    try #require(focus.auditID == "scoreboard-proof-delta")
    try #require(focus.row.selectionID == row.selectionID)
    try #require(focus.evidenceRunID == nil)
    try #require(focus.planEvaluationID == nil)
    try #require(row.workbenchAccessibilityID.contains(row.selectionID))
    try #require(row.runPairSummary == "Last run cleared 2 proof debt -> Ready: Run Plan Proof")
    try #require(row.displaySummary.contains("Latest audit cleared 2 proof debt"))
    try #require(row.contextSummary.contains("latest_audit scoreboard-proof-delta"))
    try #require(row.contextSummary.contains("run_pair last cleared 2 proof debt"))
    try #require(item.topActionStatusLabel == "More proof")
    try #require(item.topActionStatusSystemImage == "text.badge.checkmark")
    try #require(item.topActionDetail.contains("Latest audit cleared 2 proof debt"))
    try #require(item.topActionDetail.contains("Readiness: More proof"))
    try #require(context.contains("latest_audit scoreboard-proof-delta"))
    try #require(context.contains("proof_debt 6 -> 4 (-2)"))
    try #require(context.contains("run_pair last cleared 2 proof debt"))
    try #require(context.contains("next_status More proof"))
    try #require(context.contains("top_action_status More proof"))
    try #require(digest.contains("latest_audit scoreboard-proof-delta"))
    try #require(digest.contains("proof_debt 6 -> 4 (-2)"))
    try #require(digest.contains("run_pair last cleared 2 proof debt"))
    try #require(digest.contains("top_action_status More proof"))
    try #require(workbenchBody.contains("Proof Scoreboard"))
    try #require(workbenchBody.contains("WorkbenchStatusFact"))
    try #require(workbenchBody.contains("AccessibilityAttachmentModifier"))
  }

  @Test func proofTargetFocusResolvesPlanEvaluationOutcomeIDs() throws {
    var config = try roundOneConfig()
    let tournament = try #require(config.tournaments.first)
    let round = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: ProductTournamentEvidenceIndex.build(records: []),
        isPersonaModelAvailable: false
      )
    )
    let contenderID = try #require(step.contenderID)
    let contender = try #require(
      config.tournamentContenders.first { $0.id == contenderID }
    )
    let contenderPlan = try #require(
      config.contenderPlans.first { $0.id == contender.contenderPlanID }
    )
    let persona = try #require(config.userSegments.first)
    let planEvaluation = ProductTournamentPlanEvaluationRecord(
      id: "scoreboard-plan-evaluation-run",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      contenderPlanID: contender.contenderPlanID,
      experimentID: contender.experimentID,
      painID: contenderPlan.painID,
      personaID: persona.id,
      personaName: persona.name,
      currentWorkflowID: persona.currentWorkflowIDs.first,
      alternativeID: persona.alternativeIDs.first,
      startedAt: 20,
      endedAt: 30,
      scores: ProductTournamentEvidenceScores(
        painRecognition: 4,
        workflowImprovement: 4,
        alternativeAdvantage: 3,
        switchingReadiness: 3,
        continuedUsePull: 4,
        willingnessToPay: 4
      ),
      willingnessToPayScore: 4,
      estimatedMonthlyPriceCents: 4900,
      commercialProofSummary: "Budget owner would sponsor the first plan proof.",
      currentAlternativeComparison: "The plan beats manual reporting for this persona.",
      verdict: .promising,
      summary: "The simulated user sees enough plan value to sponsor a trial."
    )
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [],
      planEvaluationRecords: [planEvaluation]
    )
    let target = try #require(
      TournamentAutomationProofTargetAdvisor.targets(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first { $0.experimentID == step.experimentID }
    )
    let audit = TournamentAutomationCycleAudit(
      id: "scoreboard-plan-evaluation-audit",
      startedAt: 40,
      endedAt: 45,
      executedStepIDs: [step.id],
      experimentIDs: [step.experimentID],
      messages: ["Focused Round 1 plan proof recorded a plan-evaluation outcome."],
      maxSteps: 1,
      evidenceRunStepCount: 1,
      evidenceRunIDs: [planEvaluation.id],
      completedEvidenceRunCount: 1,
      startingProofDebtCount: 5,
      endingProofDebtCount: 3,
      startingProofDebtSummary:
        "\(step.experimentID): contender \(contender.id), round \(round.id), plan proof had 5 proof debt item(s).",
      endingProofDebtSummary:
        "\(step.experimentID): contender \(contender.id), round \(round.id), plan proof had 3 proof debt item(s).",
      proofTargetSummaries: [target.auditSummary],
      stopReason: .reachedStepLimit,
      stopDetail: "Reached one focused plan-proof step.",
      userMessage: "Focused plan proof reduced Round 1 proof debt."
    )
    config = config.recordingTournamentAutomationCycleAudit(audit)

    let focus = try #require(
      TournamentAutomationProofTargetScoreboard.focus(
        after: audit,
        config: config,
        evidenceIndex: evidenceIndex,
        preferredStep: step,
        isPersonaModelAvailable: false
      )
    )

    try #require(focus.row.experimentID == step.experimentID)
    try #require(focus.row.contenderID == contender.id)
    try #require(focus.auditID == audit.id)
    try #require(focus.evidenceRunID == nil)
    try #require(focus.planEvaluationID == planEvaluation.id)
  }
}

private struct ProofOverviewCase {
  var name: String
  var activeKind: ProductTournamentRoundKind
  var config: ProductTournamentConfig
  var expectedDigestHeading: String
  var expectedWorkbenchHeading: String
  var expectedWorkbenchAccessibilityIDPrefix: String
  var absentDigestHeadings: [String]
  var absentWorkbenchHeadings: [String]

  func expectedDigestRowSnippets(
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> [String] {
    switch activeKind {
    case .productPlans:
      let item = try #require(
        TournamentPlanProofDeltaOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [item.contextLine]
    case .coreTechnology:
      let item = try #require(
        ProductTournamentRoundTwoProofOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [item.contextLine]
    case .productImplementation:
      let item = try #require(
        ProductTournamentRoundThreeProductImplementationOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [item.contextLine]
    }
  }

  func expectedWorkbenchAccessibilityIDs(
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> [String] {
    switch activeKind {
    case .productPlans:
      let item = try #require(
        TournamentPlanProofDeltaOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [
        item.workbenchAccessibilityID,
      ]
    case .coreTechnology:
      let item = try #require(
        ProductTournamentRoundTwoProofOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [
        item.workbenchAccessibilityID,
      ]
    case .productImplementation:
      let item = try #require(
        ProductTournamentRoundThreeProductImplementationOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [
        item.workbenchAccessibilityID,
      ]
    }
  }
}

private func roundOneConfig() throws -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Weekly reporting takes too long.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func roundTwoConfig() throws -> ProductTournamentConfig {
  try configWithActiveRound(.coreTechnology)
}

private func roundThreeConfig() throws -> ProductTournamentConfig {
  try configWithActiveRound(.productImplementation)
}

private func configWithActiveRound(
  _ activeKind: ProductTournamentRoundKind
) throws -> ProductTournamentConfig {
  var config = try roundOneConfig()
  let tournament = try #require(config.tournaments.first)
  let contender = try #require(config.tournamentContenders.first)
  let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
  let coreRound = try #require(config.tournamentRounds.first { $0.kind == .coreTechnology })
  let productImplementationRound = try #require(config.tournamentRounds.first { $0.kind == .productImplementation })

  let activeRound: ProductTournamentRound
  switch activeKind {
  case .productPlans:
    activeRound = planRound
  case .coreTechnology:
    activeRound = coreRound
  case .productImplementation:
    activeRound = productImplementationRound
  }

  if let tournamentIndex = config.tournaments.firstIndex(where: { $0.id == tournament.id }) {
    config.tournaments[tournamentIndex].currentRoundID = activeRound.id
  }
  for index in config.tournamentRounds.indices {
    switch config.tournamentRounds[index].kind {
    case .productPlans:
      config.tournamentRounds[index].status =
        activeKind == .productPlans ? .active : .completed
    case .coreTechnology:
      config.tournamentRounds[index].status =
        activeKind == .coreTechnology ? .active : activeKind == .productImplementation ? .completed : .planned
      config.tournamentRounds[index].contenderIDs = [contender.id]
    case .productImplementation:
      config.tournamentRounds[index].status =
        activeKind == .productImplementation ? .active : .planned
      config.tournamentRounds[index].contenderIDs = [contender.id]
    }
  }
  if activeKind != .productPlans,
    let contenderIndex = config.tournamentContenders.firstIndex(where: { $0.id == contender.id })
  {
    config.tournamentContenders[contenderIndex].status = .narrowed
  }
  return config
}

@MainActor
private func workbenchBody(
  for config: ProductTournamentConfig
) async throws -> String {
  let root = try makeTempDir()
  defer { try? FileManager.default.removeItem(at: root) }
  try initGitRepo(at: root)
  let workspace = CompassWorkspace(repoURL: root)
  try workspace.initialize()
  try workspace.writeProductTournamentConfig(config)

  let project = CompassProject(repoURL: root)
  await project.refresh()
  return String(reflecting: ProductTournamentWorkbenchTab(project: project).body)
}
