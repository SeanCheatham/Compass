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
    try #require(
      item.readinessSummaryAccessibilityID == "\(item.workbenchAccessibilityID)-readiness-summary"
    )
    try #require(item.readinessSummaryParts == ["Proof runs 2"])
    try #require(item.readinessSummary == "Proof runs 2")
    try #require(item.readinessGroups.map(\.displaySummary) == ["Proof runs 2"])
    try #require(item.displayReadinessGroups().map(\.displaySummary) == ["Proof runs 2"])
    let proofRunGroup = try #require(item.readinessGroups.first)
    let proofRunGroupActionRow = try #require(proofRunGroup.primaryActionRow)
    let proofRunGroupActionStep = try #require(proofRunGroup.primaryActionStep)
    try #require(proofRunGroup.accessibilitySuffix == "proof-runs")
    try #require(proofRunGroupActionRow.selectionID == topActionRow.selectionID)
    try #require(proofRunGroupActionStep.id == topActionStep.id)
    try #require(proofRunGroup.actionButtonTitle == "Run Proof")
    try #require(proofRunGroup.actionSystemImage == "text.badge.checkmark")
    try #require(proofRunGroup.actionHelpSummary.contains("Ready: Run Plan Proof"))
    try #require(proofRunGroup.actionContextSummary.contains("Proof runs"))
    let proofRunGroupAuditSummary = proofRunGroup.actionAuditSummary(anchorRow: topActionRow)
    try #require(proofRunGroupAuditSummary.contains("pressure_group Proof runs"))
    try #require(proofRunGroupAuditSummary.contains("anchor \(topActionRow.selectionID)"))
    try #require(proofRunGroupAuditSummary.contains("status More proof"))
    try #require(proofRunGroupAuditSummary.contains("Ready: Run Plan Proof"))
    try #require(proofRunGroup.latestMovement == nil)
    try #require(proofRunGroup.latestMovementSummary == "No group proof movement yet")
    try #require(proofRunGroup.latestMovementStatusLabel == "No movement")
    try #require(proofRunGroup.latestMovementSystemImage == "circle.dashed")
    try #require(proofRunGroup.latestMovementContextSummary == "Proof runs: latest_result none")
    try #require(
      item.readinessGroupActionAccessibilityID(proofRunGroup)
        == "\(item.workbenchAccessibilityID)-group-proof-runs-action"
    )
    try #require(
      item.readinessGroupResultAccessibilityID(proofRunGroup)
        == "\(item.workbenchAccessibilityID)-group-proof-runs-result"
    )
    try #require(
      item.readinessGroupSelectionAccessibilityID(proofRunGroup)
        == "\(item.workbenchAccessibilityID)-group-proof-runs-selection"
    )
    try #require(proofRunGroup.containsRow(selectionID: topActionRow.selectionID))
    try #require(!proofRunGroup.containsRow(selectionID: nil))
    try #require(
      item.readinessGroup(containingRowSelectionID: topActionRow.selectionID)?.bucket
        == "Proof runs"
    )
    try #require(item.readinessGroup(containingRowSelectionID: "missing-row") == nil)
    try #require(item.readinessGroupActionSummary.contains("Proof runs"))
    try #require(item.readinessGroupResultSummary.contains("Proof runs: latest_result none"))
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
    try #require(topActionRow.nextStatusSummaryBucket == "Proof runs")
    try #require(topActionRow.nextStatusSortPriority == 50)
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
    try #require(transitionRow.nextStatusSummaryBucket == "Ready transitions")
    try #require(transitionRow.nextStatusSortPriority == 90)
    var promoteRow = topActionRow
    var promoteStep = topActionStep
    promoteStep.kind = .applyDecision
    promoteStep.action.kind = .applyDecision
    promoteStep.action.targetDecision = .promote
    promoteRow.nextStep = promoteStep
    try #require(promoteRow.postMovementNextStatusLabel == "Promotion ready")
    try #require(promoteRow.postMovementNextStatusSystemImage == "arrow.up.circle")
    try #require(promoteRow.nextStatusSummaryBucket == "Ready decisions")
    try #require(promoteRow.nextStatusSortPriority == 100)
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
    try #require(noQueuedRow.nextStatusSummaryBucket == "No queued proof")
    try #require(noQueuedRow.nextStatusSortPriority == 0)
    let prioritizedStatuses =
      [topActionRow, noQueuedRow, transitionRow, promoteRow]
      .sorted { $0.scoreboardSortsBefore($1) }
      .map(\.nextStatusLabel)
    try #require(
      prioritizedStatuses == [
        "Promotion ready",
        "Transition ready",
        "More proof",
        "No queued proof",
      ]
    )
    var priorityItem = item
    priorityItem.rows = [topActionRow, noQueuedRow, transitionRow, promoteRow]
    try #require(
      priorityItem.readinessSummary
        == "Ready decisions 1, Ready transitions 1, Proof runs 1, No queued proof 1"
    )
    try #require(
      priorityItem.readinessGroups.map(\.displaySummary) == [
        "Ready decisions 1",
        "Ready transitions 1",
        "Proof runs 1",
        "No queued proof 1",
      ]
    )
    try #require(
      priorityItem.displayReadinessGroups(limit: 2).map(\.displaySummary) == [
        "Ready decisions 1",
        "Ready transitions 1",
      ]
    )
    let decisionGroup = try #require(priorityItem.readinessGroups.first)
    let decisionGroupActionRow = try #require(decisionGroup.primaryActionRow)
    let decisionGroupActionStep = try #require(decisionGroup.primaryActionStep)
    let noQueuedGroup = try #require(priorityItem.readinessGroups.last)
    try #require(decisionGroup.accessibilitySuffix == "ready-decisions")
    try #require(decisionGroupActionRow.selectionID == promoteRow.selectionID)
    try #require(decisionGroupActionStep.kind == .applyDecision)
    try #require(decisionGroup.actionButtonTitle == "Apply Decision")
    try #require(decisionGroup.actionSystemImage == "checkmark.circle")
    try #require(decisionGroup.actionContextSummary.contains("Ready decisions"))
    try #require(noQueuedGroup.primaryActionRow == nil)
    try #require(noQueuedGroup.primaryRow?.selectionID == noQueuedRow.selectionID)
    try #require(noQueuedGroup.actionButtonTitle == "Select")
    try #require(noQueuedGroup.actionSystemImage == "scope")
    var refreshedAfterGroupActionItem = item
    refreshedAfterGroupActionItem.rows = [promoteRow]
    let refreshedSelectedGroup = try #require(
      refreshedAfterGroupActionItem.readinessGroup(
        containingRowSelectionID: topActionRow.selectionID
      )
    )
    try #require(refreshedSelectedGroup.bucket == "Ready decisions")
    try #require(refreshedSelectedGroup.containsRow(selectionID: topActionRow.selectionID))
    try #require(
      refreshedAfterGroupActionItem.readinessGroupSelectionAccessibilityID(
        refreshedSelectedGroup
      )
        == "\(item.workbenchAccessibilityID)-group-ready-decisions-selection"
    )
    var secondProofRunRow = topActionRow
    secondProofRunRow.experimentID = "overflow-proof-b"
    secondProofRunRow.contenderTitle = "Overflow proof B"
    secondProofRunRow.urgencyScore = topActionRow.urgencyScore - 1
    var thirdProofRunRow = topActionRow
    thirdProofRunRow.experimentID = "overflow-proof-c"
    thirdProofRunRow.contenderTitle = "Overflow proof C"
    thirdProofRunRow.urgencyScore = topActionRow.urgencyScore - 2
    var proofOverflowItem = item
    proofOverflowItem.rows = [topActionRow, secondProofRunRow, thirdProofRunRow]
    let proofOverflowGroup = try #require(proofOverflowItem.displayReadinessGroups(limit: 2).first)
    try #require(proofOverflowGroup.displaySummary == "Proof runs 3")
    try #require(proofOverflowGroup.rows.count == 2)
    try #require(priorityItem.topActionRow?.nextStatusLabel == "Promotion ready")
    try #require(priorityItem.topActionStep?.kind == .applyDecision)
    try #require(includesAllRivalPositions)
    try #require(displayDetailIncludesRows)
    try #require(contextLines.first == "Tournament automation proof scoreboard:")
    try #require(context.contains("proof_target_scoreboard"))
    try #require(context.contains("pressure Proof runs 2"))
    try #require(context.contains("group_actions Proof runs"))
    try #require(context.contains("group_results Proof runs: latest_result none"))
    try #require(context.contains("top_action"))
    try #require(context.contains("top_action_status More proof"))
    try #require(context.contains("run_pair"))
    try #require(context.contains("Ready: Run Plan Proof"))
    try #require(digest.contains("Tournament automation proof scoreboard:"))
    try #require(digest.contains("proof_target_scoreboard"))
    try #require(digest.contains("pressure Proof runs 2"))
    try #require(digest.contains("group_actions Proof runs"))
    try #require(digest.contains("group_results Proof runs: latest_result none"))
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
    let preAuditItem = try #require(
      TournamentAutomationProofTargetScoreboard.items(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: false
      ).first
    )
    let preAuditRow = try #require(
      preAuditItem.rows.first { $0.experimentID == step.experimentID }
    )
    let preAuditGroup = try #require(
      preAuditItem.readinessGroup(containingRowSelectionID: preAuditRow.selectionID)
    )
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
        actedProofPressureGroupSummaries: [
          preAuditGroup.actionAuditSummary(anchorRow: preAuditRow)
        ],
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
    let proofRunGroup = try #require(item.readinessGroups.first)
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
    let workbenchFacts = try #require(
      TournamentAutomationCycleWorkbenchFacts.latest(
        config: config,
        evidenceIndex: evidenceIndex,
        currentStep: step,
        isPersonaModelAvailable: false
      )
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
    try #require(
      row.proofMovementAccessibilityID == "\(row.workbenchAccessibilityID)-proof-movement")
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
    try #require(row.selectionID == preAuditRow.selectionID)
    try #require(row.displaySummary.contains("Latest audit cleared 2 proof debt"))
    try #require(row.contextSummary.contains("latest_audit scoreboard-proof-delta"))
    try #require(row.contextSummary.contains("run_pair last cleared 2 proof debt"))
    try #require(item.readinessSummary == "Proof runs 2")
    try #require(proofRunGroup.latestMovementRow?.selectionID == row.selectionID)
    try #require(proofRunGroup.latestMovement?.auditID == "scoreboard-proof-delta")
    try #require(
      proofRunGroup.latestMovementSummary
        == "\(row.contenderTitle): Cleared 2 proof debt 6 -> 4"
    )
    try #require(proofRunGroup.latestMovementStatusLabel == "Proof debt reduced")
    try #require(proofRunGroup.latestMovementSystemImage == "arrow.down.circle")
    try #require(proofRunGroup.latestMovementHelpSummary.contains("scoreboard-proof-delta"))
    try #require(proofRunGroup.latestMovementHelpSummary.contains("Current next step:"))
    try #require(proofRunGroup.latestMovementContextSummary.contains("Proof runs"))
    try #require(proofRunGroup.latestMovementContextSummary.contains(row.contenderTitle))
    try #require(
      proofRunGroup.latestMovementContextSummary.contains("latest_result cleared 2 proof debt")
    )
    try #require(
      proofRunGroup.latestMovementContextSummary.contains("audit scoreboard-proof-delta"))
    try #require(proofRunGroup.latestMovementContextSummary.contains("proof_debt 6 -> 4 (-2)"))
    try #require(
      item.readinessGroupResultAccessibilityID(proofRunGroup)
        == "\(item.workbenchAccessibilityID)-group-proof-runs-result"
    )
    try #require(item.readinessGroupResultSummary.contains("scoreboard-proof-delta"))
    try #require(item.topActionStatusLabel == "More proof")
    try #require(item.topActionStatusSystemImage == "text.badge.checkmark")
    try #require(item.topActionDetail.contains("Latest audit cleared 2 proof debt"))
    try #require(item.topActionDetail.contains("Readiness: More proof"))
    try #require(workbenchFacts.latestActedPressureGroupSummary?.contains("Proof runs") == true)
    try #require(
      workbenchFacts.latestActedPressureGroupSummary?.contains(row.contenderTitle) == true)
    try #require(
      workbenchFacts.latestActedPressureGroupOutcomeSummary
        == "reduced but still Proof runs; More proof; next Ready: Run Plan Proof")
    try #require(
      workbenchFacts.latestActedPressureGroupOutcomeHelp?.contains("anchor \(row.selectionID)")
        == true)
    try #require(context.contains("latest_audit scoreboard-proof-delta"))
    try #require(context.contains("proof_debt 6 -> 4 (-2)"))
    try #require(context.contains("pressure Proof runs 2"))
    try #require(context.contains("group_results Proof runs"))
    try #require(context.contains("latest_result cleared 2 proof debt"))
    try #require(context.contains("run_pair last cleared 2 proof debt"))
    try #require(context.contains("next_status More proof"))
    try #require(context.contains("top_action_status More proof"))
    try #require(digest.contains("latest_audit scoreboard-proof-delta"))
    try #require(digest.contains("proof_debt 6 -> 4 (-2)"))
    try #require(digest.contains("pressure Proof runs 2"))
    try #require(digest.contains("group_results Proof runs"))
    try #require(digest.contains("latest_result cleared 2 proof debt"))
    try #require(digest.contains("run_pair last cleared 2 proof debt"))
    try #require(digest.contains("top_action_status More proof"))
    try #require(digest.contains("acted group outcomes"))
    try #require(digest.contains("reduced but still Proof runs"))
    try #require(workbenchBody.contains("Proof Scoreboard"))
    try #require(workbenchBody.contains("Last Group"))
    try #require(workbenchBody.contains("Group Outcome"))
    try #require(workbenchBody.contains("Proof runs; \(row.contenderTitle); More proof"))
    try #require(workbenchBody.contains("reduced but still Proof runs; More proof"))
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
        item.workbenchAccessibilityID
      ]
    case .coreTechnology:
      let item = try #require(
        ProductTournamentRoundTwoProofOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [
        item.workbenchAccessibilityID
      ]
    case .productImplementation:
      let item = try #require(
        ProductTournamentRoundThreeProductImplementationOverview.items(
          config: config,
          evidenceIndex: evidenceIndex
        ).first
      )
      return [
        item.workbenchAccessibilityID
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
  let productImplementationRound = try #require(
    config.tournamentRounds.first { $0.kind == .productImplementation })

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
        activeKind == .coreTechnology
        ? .active : activeKind == .productImplementation ? .completed : .planned
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
