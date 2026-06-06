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
    try #require(proofOverviewItem.willingnessToPayProofCount == 3)
    try #require(proofOverviewItem.evidenceRunIDs.contains("\(fixture.contender.id)-round-3-0"))
    try #require(proposal.proofGaps.isEmpty)
    try #require(proposal.nextValidationTarget.contains("Select the tournament winner"))
    try #require(proofOverviewItem.contextLine.contains("round_3_product_implementation_proof contender"))
    try #require(proofOverviewItem.contextLine.contains("recommendation select_winner"))
    try #require(proofOverviewItem.contextLine.contains("willingness_to_pay 5.0/5"))
    try #require(proofOverviewItem.contextLine.contains("willingness_to_pay_proofs 3"))
    try #require(proofOverviewItem.contextLine.contains("implementation_use_proofs 3"))
    try #require(proofOverviewItem.contextLine.contains("proof_gaps none"))
    try #require(proofOverviewItem.contextLine.contains("next_validation"))
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
    try #require(digest.contains("proof_gaps none"))
    try #require(digest.contains("next_validation"))
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
    try #require(outcome.proposal.proofGaps.contains { $0.contains("sponsor_export") })
    try #require(
      outcome.proposal.proofGaps.contains { $0.contains("willingness to pay 2.0/5") })
    try #require(outcome.proposal.nextValidationTarget.contains("Revise the low-medium fidelity"))
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.productImplementationRound.id)
    try #require(updatedProductImplementationRound.status == .active)
    try #require(updatedContender.status == .needsRevision)
    try #require(updatedExperiment.decision == .narrow)
    try #require(followUpScope?.roundID == fixture.productImplementationRound.id)
    try #require(outcome.userMessage.contains("revision"))
  }

  @Test func roundThreeImplementationRevisionValidationScopesFreshEvidenceBeforeWinnerSelection()
    throws
  {
    let fixture = try roundThreeFixture()
    let revisionScenarioID = "\(fixture.experiment.id)-round-3-validation-operator"
    let siblingScenarioID = "\(fixture.experiment.id)-round-3-validation-buyer"
    let firstSegment = try #require(fixture.config.userSegments.first)
    let secondSegment = try #require(fixture.config.userSegments.dropFirst().first)
    let workflow = try #require(fixture.config.currentWorkflows.first)
    var config = fixture.config
    if let experimentIndex = config.tournamentExperiments.firstIndex(where: {
      $0.id == fixture.experiment.id
    }) {
      config.tournamentExperiments[experimentIndex].baseSha = "base-sha"
      config.tournamentExperiments[experimentIndex].currentSha = "def456"
    }
    config.scenarios.append(
      ProductScenario(
        id: revisionScenarioID,
        experimentID: fixture.experiment.id,
        segmentID: firstSegment.id,
        currentWorkflowID: workflow.id,
        title: "Round 3 validation operator",
        task: "Validate the revised low-medium fidelity implementation as the first user.",
        successSignal:
          "The revised implementation is exercised, beats the spreadsheet, and earns sponsor intent.",
        targetCommitSha: "def456",
        createdAt: 100
      ))
    config.scenarios.append(
      ProductScenario(
        id: siblingScenarioID,
        experimentID: fixture.experiment.id,
        segmentID: secondSegment.id,
        currentWorkflowID: workflow.id,
        title: "Round 3 validation buyer",
        task: "Validate the revised low-medium fidelity implementation as the second user.",
        successSignal:
          "The revised implementation earns explicit willingness-to-pay from another persona.",
        targetCommitSha: "def456",
        createdAt: 100
      ))
    config.scenarioCohorts.append(
      ProductScenarioCohort(
        id: "\(fixture.experiment.id)-round-3-validation-cohort",
        title: "Round 3 validation cohort",
        experimentID: fixture.experiment.id,
        scenarioIDs: [revisionScenarioID, siblingScenarioID],
        enabled: true,
        tags: ["round-3-validation"]
      ))
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == fixture.experiment.id }
    )
    let preRevisionRecords = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 3,
      willingnessToPay: 2,
      verdict: .unclear,
      objections: ["The sponsor proof needs clearer export and audit context."],
      missingCapabilities: ["sponsor_export"],
      summary: "The original product implementation needs one more fidelity pass."
    )
    let preRevisionIndex = ProductTournamentEvidenceIndex.build(records: preRevisionRecords)
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.roundThreeImplementationRevisionBrief(
        for: experiment,
        config: config,
        evidenceIndex: preRevisionIndex
      ))
    let revisionAudit = roundThreeImplementationRevisionAudit(
      fixture: fixture,
      brief: revisionBrief,
      scenarioID: revisionScenarioID,
      endedAt: 100
    )
    let olderRevisionAudit = roundThreeImplementationRevisionAudit(
      fixture: fixture,
      brief: revisionBrief,
      scenarioID: revisionScenarioID,
      endedAt: 80
    )
    let revisionAuditedConfig = config
      .recordingTournamentAutomationCycleAudit(olderRevisionAudit)
      .recordingTournamentAutomationCycleAudit(revisionAudit)
    let recognizedAudit = TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
      for: revisionBrief,
      experiment: experiment,
      config: revisionAuditedConfig,
      evidenceIndex: preRevisionIndex
    )
    let pendingAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: revisionAuditedConfig,
        evidenceIndex: preRevisionIndex
      ))
    let pendingResult = try #require(
      ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.results(
        config: revisionAuditedConfig,
        evidenceIndex: preRevisionIndex
      ).first
    )
    let firstValidationRecord = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 1,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The first validation run found sponsor pull after the revision.",
      scenarioID: revisionScenarioID,
      mode: .personaModel,
      startedAt: 120,
      idPrefix: "\(fixture.contender.id)-round-3-validation-operator"
    )[0]
    let siblingValidationRecord = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 2,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The second validation persona would sponsor the revised implementation.",
      scenarioID: siblingScenarioID,
      mode: .personaModel,
      startedAt: 130,
      idPrefix: "\(fixture.contender.id)-round-3-validation-buyer"
    )[1]
    let thirdValidationRecord = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "A third validation run confirmed the revised implementation is ready.",
      scenarioID: revisionScenarioID,
      mode: .personaModel,
      startedAt: 140,
      idPrefix: "\(fixture.contender.id)-round-3-validation-repeat"
    )[2]
    let partialIndex = ProductTournamentEvidenceIndex.build(
      records: preRevisionRecords + [firstValidationRecord]
    )
    let partialProposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: revisionAuditedConfig,
        evidenceIndex: partialIndex
      ).first
    )
    let partialResult = try #require(
      ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.results(
        config: revisionAuditedConfig,
        evidenceIndex: partialIndex
      ).first
    )
    let partialAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: revisionAuditedConfig,
        evidenceIndex: partialIndex
      ))
    let partialDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: revisionAuditedConfig,
      evidenceIndex: partialIndex
    )
    let validationIndex = ProductTournamentEvidenceIndex.build(
      records: preRevisionRecords + [
        firstValidationRecord, siblingValidationRecord, thirdValidationRecord,
      ]
    )
    let validationProposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: revisionAuditedConfig,
        evidenceIndex: validationIndex
      )
    )
    let validationResult = try #require(
      ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.results(
        config: revisionAuditedConfig,
        evidenceIndex: validationIndex
      ).first
    )
    let validationDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: revisionAuditedConfig,
      evidenceIndex: validationIndex
    )
    let validationTransitionStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: revisionAuditedConfig,
        evidenceIndex: validationIndex,
        isPersonaModelAvailable: true
      ))
    let validationOverviewItem = try #require(
      ProductTournamentRoundThreeProductImplementationOverview.items(
        config: revisionAuditedConfig,
        evidenceIndex: validationIndex
      ).first
    )
    let validationCycleFacts = try #require(
      TournamentAutomationCycleWorkbenchFacts.latest(
        config: revisionAuditedConfig,
        evidenceIndex: validationIndex,
        currentStep: validationTransitionStep
      ))

    try #require(revisionBrief.source == .roundThreeImplementationRevision)
    try #require(recognizedAudit?.id == revisionAudit.id)
    try #require(pendingAction.title == "Validate Round 3 implementation revision")
    try #require(pendingAction.kind == .rerunCohort)
    try #require(pendingAction.detail.contains(revisionAudit.id))
    try #require(pendingAction.targetScenarioID == revisionScenarioID)
    try #require(pendingAction.targetDecision == .promote)
    try #require(pendingAction.requiredSimulationMode == .personaModel)
    try #require(pendingResult.outcome == .pendingValidation)
    try #require(pendingResult.revisionAuditID == revisionAudit.id)
    try #require(pendingResult.validationRunIDs.isEmpty)
    try #require(
      pendingResult.persistedProofGaps.contains {
        $0.contains("sponsor_export") || $0.contains("willingness to pay")
      })
    try #require(partialProposal.recommendation == .gatherEvidence)
    try #require(partialProposal.completedRunCount == 1)
    try #require(
      partialProposal.evidenceRunIDs.allSatisfy {
        $0.contains("\(fixture.contender.id)-round-3-validation-operator")
      })
    try #require(partialResult.outcome == .partialValidation)
    try #require(partialResult.validationRunIDs == [firstValidationRecord.id])
    try #require(partialAction.kind == .rerunCohort)
    try #require(partialAction.title == "Complete Round 3 implementation validation")
    try #require(partialAction.targetPersonaID == secondSegment.id)
    try #require(partialAction.targetPersonaName == secondSegment.name)
    try #require(partialAction.targetScenarioID == siblingScenarioID)
    try #require(partialAction.targetDecision == .promote)
    try #require(partialDigest.contains("Round 3 implementation revision validation"))
    try #require(partialDigest.contains("outcome partial_validation"))
    try #require(validationProposal.recommendation == .selectWinner)
    try #require(validationProposal.proofGaps.isEmpty)
    try #require(
      validationProposal.evidenceRunIDs.allSatisfy {
        $0.contains("\(fixture.contender.id)-round-3-validation")
      })
    try #require(validationResult.outcome == .resolved)
    try #require(validationResult.recommendation == .selectWinner)
    try #require(validationResult.validationRunCount == 3)
    try #require(validationResult.completedValidationRunCount == 3)
    try #require(validationResult.persistedProofGaps.isEmpty)
    try #require(
      validationResult.resolvedProofGaps.contains {
        $0.contains("sponsor_export") || $0.contains("willingness to pay")
      })
    try #require(validationResult.contextLine.contains("outcome resolved"))
    try #require(validationDigest.contains("Round 3 implementation revision validation"))
    try #require(validationDigest.contains("outcome resolved"))
    try #require(validationTransitionStep.kind == .applyRoundTransition)
    try #require(validationTransitionStep.title == "Apply Round 3 transition")
    try #require(validationOverviewItem.implementationRevisionValidation?.outcome == .resolved)
    try #require(
      validationOverviewItem.implementationRevisionValidation?.revisionAuditID == revisionAudit.id)
    try #require(
      validationOverviewItem.implementationRevisionValidation?.revisionAuditID != olderRevisionAudit.id)
    try #require(
      validationOverviewItem.implementationRevisionValidationSummary?
        .contains("Resolved") == true)
    try #require(
      validationOverviewItem.implementationRevisionValidationSummary?
        .contains("3/3 validation") == true)
    try #require(
      validationOverviewItem.implementationRevisionValidationDetail?
        .contains(revisionAudit.id) == true)
    try #require(
      validationOverviewItem.implementationRevisionValidationDetail?
        .contains(olderRevisionAudit.id) == false)
    try #require(
      validationOverviewItem.helpSummary.contains(
        "Implementation revision validation: Resolved"))
    try #require(
      validationCycleFacts.latestRoundThreeImplementationRevisionValidationSummary?
        .contains("Resolved") == true)
    try #require(
      validationCycleFacts.latestRoundThreeImplementationRevisionValidationSummary?
        .contains(revisionAudit.id) == true)
    try #require(
      validationCycleFacts.latestRoundThreeImplementationRevisionValidationSummary?
        .contains(olderRevisionAudit.id) == false)
    try #require(
      validationCycleFacts.latestRoundThreeImplementationRevisionValidationHelp?
        .contains("round_3_implementation_revision_validation") == true)
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
    try #require(outcome.proposal.proofGaps.contains { $0.contains("workflow_advantage") })
    try #require(outcome.proposal.proofGaps.contains { $0.contains("weak or rejected") })
    try #require(outcome.proposal.nextValidationTarget.contains("Stop this contender"))
    try #require(updatedTournament.status == .active)
    try #require(updatedTournament.currentRoundID == fixture.productImplementationRound.id)
    try #require(updatedContender.status == .eliminated)
    try #require(updatedExperiment.decision == .kill)
    try #require(updatedProductTournamentContenderPlan.status == .rejected)
    try #require(outcome.userMessage.contains("Eliminated"))
  }

  @Test func roundThreeImplementationRevisionValidationOverviewCoversEveryOutcomeState() throws {
    let cases: [ProductTournamentRoundThreeImplementationRevisionValidationOutcome] = [
      .pendingValidation,
      .partialValidation,
      .resolved,
      .persisted,
      .eliminated,
    ]

    for expectedOutcome in cases {
      let validationFixture = try roundThreeRevisionValidationFixture()
      let records = roundThreeValidationRecords(
        fixture: validationFixture.fixture,
        scenarioID: validationFixture.revisionScenarioID,
        outcome: expectedOutcome
      )
      let index = ProductTournamentEvidenceIndex.build(
        records: validationFixture.preRevisionRecords + records
      )
      let validationItem = try #require(
        ProductTournamentRoundThreeImplementationRevisionValidationOverview.items(
          config: validationFixture.config,
          evidenceIndex: index,
          isPersonaModelAvailable: true
        ).first
      )
      let proofItem = try #require(
        ProductTournamentRoundThreeProductImplementationOverview.items(
          config: validationFixture.config,
          evidenceIndex: index
        ).first
      )
      let facts = try #require(
        TournamentAutomationCycleWorkbenchFacts.latest(
          config: validationFixture.config,
          evidenceIndex: index
        ))

      try #require(validationItem.outcome == expectedOutcome)
      try #require(validationItem.contenderID == validationFixture.fixture.contender.id)
      try #require(validationItem.experimentID == validationFixture.fixture.experiment.id)
      try #require(validationItem.revisionAuditID == validationFixture.revisionAudit.id)
      try #require(validationItem.revisionScenarioID == validationFixture.revisionScenarioID)
      try #require(validationItem.displaySubtitle.contains(expectedOutcome.title))
      try #require(validationItem.validationSummary.contains(expectedOutcome.title))
      try #require(validationItem.displayDetail.contains(validationFixture.revisionAudit.id))
      try #require(validationItem.helpSummary.contains("Persisted gaps"))
      try #require(validationItem.helpSummary.contains("Resolved gaps"))
      try #require(validationItem.helpSummary.contains("Next step"))
      try #require(validationItem.nextStepSummary != "No automation step queued")
      try #require(
        validationItem.workbenchAccessibilityID.contains(
          "round-3-implementation-validation"))
      try #require(proofItem.implementationRevisionValidation?.outcome == expectedOutcome)
      try #require(
        facts.latestRoundThreeImplementationRevisionValidationSummary?
          .contains(expectedOutcome.title) == true)
      try #require(
        facts.latestRoundThreeImplementationRevisionValidationSummary?
          .contains(validationFixture.revisionAudit.id) == true)

      switch expectedOutcome {
      case .pendingValidation:
        try #require(validationItem.result.validationRunCount == 0)
        try #require(validationItem.displaySystemImage == "clock")
        try #require(validationItem.persistedGapSummary != "none")
        try #require(validationItem.nextStep?.kind == .runCohort)
        try #require(
          validationItem.nextStep?.action.title == "Validate Round 3 implementation revision")
        try #require(validationItem.nextStep?.canExecute == true)
        try #require(validationItem.nextStep?.targetScenarioID == validationFixture.revisionScenarioID)
        try #require(validationItem.nextStepSystemImage == "play.rectangle.on.rectangle")
      case .partialValidation:
        try #require(validationItem.result.validationRunCount == 1)
        try #require(validationItem.displaySystemImage == "hourglass")
        try #require(validationItem.persistedGapSummary.contains("needs"))
        try #require(validationItem.nextStep?.kind == .runCohort)
        try #require(
          validationItem.nextStep?.action.title == "Complete Round 3 implementation validation")
        try #require(validationItem.nextStep?.canExecute == true)
        try #require(validationItem.nextStep?.action.targetDecision == .promote)
        try #require(validationItem.nextStepSystemImage == "play.rectangle.on.rectangle")
      case .resolved:
        try #require(validationItem.result.validationRunCount == 3)
        try #require(validationItem.displaySystemImage == "checkmark.seal")
        try #require(validationItem.persistedGapSummary == "none")
        try #require(validationItem.resolvedGapSummary != "none")
        try #require(validationItem.nextStep?.kind == .applyRoundTransition)
        try #require(validationItem.nextStep?.action.title == "Apply Round 3 transition")
        try #require(validationItem.nextStep?.canExecute == true)
        try #require(validationItem.nextStepSystemImage == "arrow.turn.down.right")
      case .persisted:
        try #require(validationItem.result.validationRunCount == 3)
        try #require(validationItem.displaySystemImage == "exclamationmark.triangle")
        try #require(validationItem.persistedGapSummary != "none")
        try #require(validationItem.nextStep?.kind == .applyRevision)
        try #require(validationItem.nextStep?.canExecute == true)
        try #require(validationItem.nextStepSystemImage == "wand.and.stars")
      case .eliminated:
        try #require(validationItem.result.validationRunCount == 2)
        try #require(validationItem.displaySystemImage == "xmark.octagon")
        try #require(validationItem.persistedGapSummary != "none")
        try #require(validationItem.nextStep?.kind == .applyRoundTransition)
        try #require(validationItem.nextStep?.action.title == "Apply Round 3 transition")
        try #require(validationItem.nextStep?.canExecute == true)
        try #require(validationItem.nextStepSystemImage == "arrow.turn.down.right")
      }
    }
  }

  @Test func roundThreeImplementationRevisionValidationOverviewQueuesWorktreePreparation()
    throws
  {
    let validationFixture = try roundThreeRevisionValidationFixture(
      hasPreparedValidationTarget: false
    )
    let index = ProductTournamentEvidenceIndex.build(records: validationFixture.preRevisionRecords)
    let validationItem = try #require(
      ProductTournamentRoundThreeImplementationRevisionValidationOverview.items(
        config: validationFixture.config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ).first
    )
    let nextStep = try #require(validationItem.nextStep)
    let cohortID = "\(validationFixture.fixture.experiment.id)-round-3-validation-cohort"

    try #require(validationItem.outcome == .pendingValidation)
    try #require(nextStep.kind == .prepareWorktree)
    try #require(nextStep.action.kind == .prepareWorktree)
    try #require(nextStep.action.title == "Prepare implementation worktree")
    try #require(nextStep.action.cohortID == cohortID)
    try #require(nextStep.canExecute)
    try #require(validationItem.nextStepSummary == "Ready: Prepare implementation worktree")
    try #require(validationItem.nextStepSystemImage == "hammer")
    try #require(validationItem.nextStepDetail.contains(validationFixture.fixture.experiment.title))
    try #require(validationItem.nextStepDetail.contains("Prepare implementation worktree"))
    try #require(
      nextStep.action.detail.contains(
        "Round 3 implementation revision validation scenario needs"
      ))
    try #require(nextStep.action.detail.contains("target commit"))
    try #require(nextStep.action.detail.contains(cohortID))
    try #require(
      validationItem.helpSummary.contains("Next step: Ready: Prepare implementation worktree"))
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
    try #require(proposal.proofGaps.contains { $0.contains("needs 1 more completed") })
    try #require(proposal.proofGaps.contains { $0.contains("needs 1 implementation-use") })
    try #require(proposal.nextValidationTarget.contains("Run scoped Round 3"))
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
    try #require(proposal.proofGaps.contains { $0.contains("needs 3 implementation-use") })
    try #require(proposal.nextValidationTarget.contains("implementation-use"))
    try #require(proposal.digestLine.contains("implementation_use_proofs 0"))
    try #require(proposal.digestLine.contains("proof_gaps"))
    try #require(proposal.digestLine.contains("next_validation"))
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
    try #require(proposal.proofGaps.contains { $0.contains("needs 3 implementation-use") })
    try #require(proposal.detail.contains("0 implementation-use proof"))
  }

  @Test func strongProductImplementationScoresWithoutExplicitPayProofOnlyGatherEvidence() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: nil,
      verdict: .strongPull,
      summary: "The implementation looks useful, but no price or sponsorship intent was captured."
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
    try #require(proposal.willingnessToPayProofCount == 0)
    try #require(proposal.proofGaps.contains { $0.contains("explicit willingness-to-pay") })
    try #require(proposal.digestLine.contains("willingness_to_pay_proofs 0"))
    try #require(proposal.nextValidationTarget.contains("willingness-to-pay"))
    try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func derivedSponsorshipIntentDoesNotCountAsExplicitPayProof() throws {
    let fixture = try roundThreeFixture()
    let records = productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The implementation looks useful, but only the derived sponsor sentence was present.",
      sponsorshipIntent:
        "The simulated user shows strong willingness to pay for or sponsor this contender."
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
    try #require(proposal.willingnessToPayProofCount == 0)
    try #require(proposal.proofGaps.contains { $0.contains("explicit willingness-to-pay") })
    try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
        tournamentID: fixture.tournament.id,
        roundID: fixture.productImplementationRound.id,
        config: fixture.config,
        evidenceIndex: index
      ) == nil
    )
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
    try #require(item.willingnessToPayProofCount == 0)
    try #require(item.proofGaps.contains { $0.contains("no scoped Round 3") })
    try #require(item.nextValidationTarget.contains("Run scoped Round 3"))
    try #require(item.displaySubtitle.contains("Gather Evidence"))
    try #require(item.contextLine.contains("no scoped evidence"))
    try #require(item.contextLine.contains("implementation_scope"))
    try #require(item.contextLine.contains("proof_gaps"))
    try #require(item.contextLine.contains("next_validation"))
    try #require(item.contextLine.contains(fixture.experiment.id))
    try #require(item.helpSummary.contains("Proof gaps"))
    try #require(item.helpSummary.contains("Next validation"))
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

private struct RoundThreeRevisionValidationFixture {
  var fixture: RoundThreeFixture
  var config: ProductTournamentConfig
  var preRevisionRecords: [ProductTournamentEvidenceRecord]
  var revisionAudit: TournamentAutomationCycleAudit
  var revisionScenarioID: String
  var siblingScenarioID: String
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

private func roundThreeRevisionValidationFixture(
  hasPreparedValidationTarget: Bool = true
) throws -> RoundThreeRevisionValidationFixture {
  let fixture = try roundThreeFixture()
  let revisionScenarioID = "\(fixture.experiment.id)-round-3-validation-operator"
  let siblingScenarioID = "\(fixture.experiment.id)-round-3-validation-buyer"
  let firstSegment = try #require(fixture.config.userSegments.first)
  let secondSegment = try #require(fixture.config.userSegments.dropFirst().first)
  let workflow = try #require(fixture.config.currentWorkflows.first)
  var config = fixture.config
  let targetCommitSha = hasPreparedValidationTarget ? "def456" : nil
  if let experimentIndex = config.tournamentExperiments.firstIndex(where: {
    $0.id == fixture.experiment.id
  }) {
    config.tournamentExperiments[experimentIndex].baseSha =
      hasPreparedValidationTarget ? "base-sha" : nil
    config.tournamentExperiments[experimentIndex].currentSha = targetCommitSha
  }
  config.scenarios.append(
    ProductScenario(
      id: revisionScenarioID,
      experimentID: fixture.experiment.id,
      segmentID: firstSegment.id,
      currentWorkflowID: workflow.id,
      title: "Round 3 validation operator",
      task: "Validate the revised low-medium fidelity implementation as the first user.",
      successSignal:
        "The revised implementation is exercised, beats the spreadsheet, and earns sponsor intent.",
      targetCommitSha: targetCommitSha,
      createdAt: 100
    ))
  config.scenarios.append(
    ProductScenario(
      id: siblingScenarioID,
      experimentID: fixture.experiment.id,
      segmentID: secondSegment.id,
      currentWorkflowID: workflow.id,
      title: "Round 3 validation buyer",
      task: "Validate the revised low-medium fidelity implementation as the second user.",
      successSignal:
        "The revised implementation earns explicit willingness-to-pay from another persona.",
      targetCommitSha: targetCommitSha,
      createdAt: 100
    ))
  config.scenarioCohorts.append(
    ProductScenarioCohort(
      id: "\(fixture.experiment.id)-round-3-validation-cohort",
      title: "Round 3 validation cohort",
      experimentID: fixture.experiment.id,
      scenarioIDs: [revisionScenarioID, siblingScenarioID],
      enabled: true,
      tags: ["round-3-validation"]
    ))
  let experiment = try #require(
    config.tournamentExperiments.first { $0.id == fixture.experiment.id }
  )
  let preRevisionRecords = productImplementationEvidenceRecords(
    fixture: fixture,
    count: 3,
    score: 3,
    willingnessToPay: 2,
    verdict: .unclear,
    objections: ["The sponsor proof needs clearer export and audit context."],
    missingCapabilities: ["sponsor_export"],
    summary: "The original product implementation needs one more fidelity pass."
  )
  let preRevisionIndex = ProductTournamentEvidenceIndex.build(records: preRevisionRecords)
  let revisionBrief = try #require(
    TournamentAutomationRevisionBriefAdvisor.roundThreeImplementationRevisionBrief(
      for: experiment,
      config: config,
      evidenceIndex: preRevisionIndex
    ))
  let revisionAudit = roundThreeImplementationRevisionAudit(
    fixture: fixture,
    brief: revisionBrief,
    scenarioID: revisionScenarioID,
    endedAt: 100
  )
  return RoundThreeRevisionValidationFixture(
    fixture: fixture,
    config: config.recordingTournamentAutomationCycleAudit(revisionAudit),
    preRevisionRecords: preRevisionRecords,
    revisionAudit: revisionAudit,
    revisionScenarioID: revisionScenarioID,
    siblingScenarioID: siblingScenarioID
  )
}

private func productImplementationEvidenceRecords(
  fixture: RoundThreeFixture,
  count: Int,
  score: Int,
  willingnessToPay: Int?,
  verdict: ProductTournamentEvidenceVerdict,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  summary: String,
  sponsorshipIntent: String? = nil,
  includeImplementationUseProof: Bool = true,
  completedUseProof: Bool? = nil,
  scenarioID: String? = nil,
  mode: ProductTournamentSimulationMode = .modelFree,
  startedAt: Double = 0,
  idPrefix: String? = nil
) -> [ProductTournamentEvidenceRecord] {
  let completedUseProof = completedUseProof ?? includeImplementationUseProof
  let segments = Array(fixture.config.userSegments)
  return (0..<count).map { index in
    let segment = segments[index % max(1, segments.count)]
    let recordID = "\(idPrefix ?? "\(fixture.contender.id)-round-3")-\(index)"
    return ProductTournamentEvidenceRecord(
      id: recordID,
      experimentID: fixture.experiment.id,
      contenderPlanID: fixture.contender.contenderPlanID,
      painID: fixture.contenderPlan.painID,
      tournamentID: fixture.tournament.id,
      roundID: fixture.productImplementationRound.id,
      contenderID: fixture.contender.id,
      branchName: fixture.experiment.branchName,
      commitSha: "def456",
      scenarioID: scenarioID ?? "product-implementation-scenario-\(index)",
      personaID: segment.id,
      mode: mode,
      status: .completed,
      startedAt: startedAt + Double(index),
      endedAt: startedAt + Double(index + 1),
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
      sponsorshipIntent: sponsorshipIntent
        ?? willingnessToPay.map {
          $0 >= 4
            ? "The simulated user would pay for or sponsor this product implementation."
            : "The simulated user is not ready to sponsor this product implementation."
        } ?? "",
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

private func roundThreeValidationRecords(
  fixture: RoundThreeFixture,
  scenarioID: String,
  outcome: ProductTournamentRoundThreeImplementationRevisionValidationOutcome
) -> [ProductTournamentEvidenceRecord] {
  switch outcome {
  case .pendingValidation:
    return []
  case .partialValidation:
    return productImplementationEvidenceRecords(
      fixture: fixture,
      count: 1,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "The first validation run found sponsor pull after the revision.",
      scenarioID: scenarioID,
      mode: .personaModel,
      startedAt: 120,
      idPrefix: "\(fixture.contender.id)-round-3-validation-partial"
    )
  case .resolved:
    return productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 5,
      willingnessToPay: 5,
      verdict: .strongPull,
      summary: "Validation confirmed the revised implementation is ready.",
      scenarioID: scenarioID,
      mode: .personaModel,
      startedAt: 120,
      idPrefix: "\(fixture.contender.id)-round-3-validation-resolved"
    )
  case .persisted:
    return productImplementationEvidenceRecords(
      fixture: fixture,
      count: 3,
      score: 3,
      willingnessToPay: 2,
      verdict: .unclear,
      objections: ["The sponsor export is still not persuasive enough."],
      missingCapabilities: ["sponsor_export"],
      summary: "Validation still shows the revised implementation has commercial gaps.",
      scenarioID: scenarioID,
      mode: .personaModel,
      startedAt: 120,
      idPrefix: "\(fixture.contender.id)-round-3-validation-persisted"
    )
  case .eliminated:
    return productImplementationEvidenceRecords(
      fixture: fixture,
      count: 2,
      score: 1,
      willingnessToPay: 1,
      verdict: .weak,
      objections: ["The revised implementation still does not beat the spreadsheet."],
      missingCapabilities: ["workflow_advantage"],
      summary: "Validation shows the contender should stop after the revision.",
      scenarioID: scenarioID,
      mode: .personaModel,
      startedAt: 120,
      idPrefix: "\(fixture.contender.id)-round-3-validation-eliminated"
    )
  }
}

private func roundThreeImplementationRevisionAudit(
  fixture: RoundThreeFixture,
  brief: TournamentAutomationRevisionBrief,
  scenarioID: String,
  endedAt: Double
) -> TournamentAutomationCycleAudit {
  let stepID =
    "\(fixture.experiment.id):\(TournamentAutomationStepKind.applyRevision.rawValue):\(scenarioID)"
  return TournamentAutomationCycleAudit(
    id: "round-3-implementation-revision-\(fixture.experiment.id)-\(Int(endedAt))",
    startedAt: endedAt - 10,
    endedAt: endedAt,
    executedStepIDs: [stepID],
    experimentIDs: [fixture.experiment.id],
    messages: [
      "Applied Round 3 implementation revision \(brief.title) to scenario \(scenarioID)."
    ],
    maxSteps: 1,
    revisionBriefSummaries: [brief.auditSummary],
    stopReason: .reachedStepLimit,
    stopStepID: stepID,
    stopStepTitle: "Apply contender revision",
    stopDetail: "Round 3 implementation revision applied; run validation evidence next.",
    userMessage:
      "Applied Round 3 implementation revision for \(fixture.experiment.id). Run validation evidence next."
  )
}
