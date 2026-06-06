import Foundation
import Testing

@testable import Compass

struct ProductTournamentLoopTests {
  @Test func decisionTransitionValidatorAllowsDocumentedTournamentPath() throws {
    try ProductTournamentDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .notRun,
      to: .keepGoing,
      summary: ""
    )
    try ProductTournamentDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .keepGoing,
      to: .narrow,
      summary: ""
    )
    try ProductTournamentDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .narrow,
      to: .promote,
      summary: "Evidence and Verify support promotion."
    )
    try ProductTournamentDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .promote,
      to: .promoted,
      summary: "The promoted experiment has landed."
    )
  }

  @Test func decisionTransitionValidatorRejectsUndocumentedTournamentPath() throws {
    do {
      try ProductTournamentDecisionTransitionValidator.validate(
        experimentID: "experiment-one",
        from: .pivot,
        to: .promote,
        summary: "Too large a leap."
      )
      Issue.record("Expected pivot -> promote to be rejected.")
    } catch let error as ProductTournamentDecisionTransitionError {
      try #require(
        error
          == .invalidTransition(
            experimentID: "experiment-one",
            from: .pivot,
            to: .promote
          )
      )
    }
  }

  @Test func decisionTransitionValidatorRequiresSummaryForKillAndPromote() throws {
    do {
      try ProductTournamentDecisionTransitionValidator.validate(
        experimentID: "experiment-one",
        from: .keepGoing,
        to: .kill,
        summary: "  "
      )
      Issue.record("Expected kill without summary to be rejected.")
    } catch let error as ProductTournamentDecisionTransitionError {
      try #require(error == .missingSummary(experimentID: "experiment-one", decision: .kill))
    }
  }

  @Test func reflectDecisionApplierUpdatesExperimentAndDecisionTrail() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let experiment = config.tournamentExperiments[0]
    let update = ProductTournamentReflectDecisionUpdate(
      experimentID: experiment.id,
      decision: .keepGoing,
      summary: "The deterministic run exposed one clear missing capability.",
      evidenceRunIDs: ["run-one"],
      decidedBy: "Reflect"
    )

    let next = try ProductTournamentReflectDecisionApplier.applying(
      [update],
      to: config,
      now: Date(timeIntervalSince1970: 20)
    )
    let savedExperiment = try #require(next.tournamentExperiments.first { $0.id == experiment.id })
    let savedDecision = try #require(next.decisions.last)

    try #require(savedExperiment.decision == .keepGoing)
    try #require(savedExperiment.evidenceSummary.contains("missing capability"))
    try #require(savedExperiment.updatedAt == 20)
    try #require(savedDecision.experimentID == experiment.id)
    try #require(savedDecision.decision == .keepGoing)
    try #require(savedDecision.evidenceRunIDs == ["run-one"])
    try #require(savedDecision.decidedBy == "Reflect")

    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: next,
      evidenceIndex: .empty
    )
    try #require(digest.contains("Latest tournament decisions:"))
    try #require(!digest.contains("Latest product decisions:"))
  }

  @Test func tournamentDecisionAdvisorProposesValidatedProductTransitions() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[1].decision = .keepGoing
    let weakExperiment = ProductTournamentExperiment(
      id: "reporting-weak-contender",
      contenderPlanID: config.contenderPlans[0].id,
      title: "Reporting weak contender",
      branchName: "codex/reporting-weak-contender",
      worktreeID: "reporting-weak-contender",
      baseSha: "base-sha",
      currentSha: "weak-sha",
      implementationScope: "Try a product shape that may not beat the current workflow.",
      evidenceSummary: "No evidence recorded yet.",
      decision: .keepGoing,
      createdAt: 10
    )
    config.tournamentExperiments.append(weakExperiment)

    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let narrowScores = ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 3,
      switchingReadiness: 3,
      continuedUsePull: 4
    )
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "promote-a",
          experiment: config.tournamentExperiments[0],
          config: config,
          personaID: "operator",
          mode: .personaModel,
          endedAt: 300,
          verdict: .strongPull,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "promote-b",
          experiment: config.tournamentExperiments[0],
          config: config,
          personaID: "buyer",
          mode: .personaModel,
          endedAt: 200,
          verdict: .strongPull,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "promote-c",
          experiment: config.tournamentExperiments[0],
          config: config,
          personaID: "operator",
          endedAt: 100,
          verdict: .promising,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "narrow-a",
          experiment: config.tournamentExperiments[1],
          config: config,
          personaID: "operator",
          endedAt: 280,
          verdict: .promising,
          scores: narrowScores,
          missingCapabilities: ["csv_import"]
        ),
        makeDecisionAdvisorRecord(
          id: "narrow-b",
          experiment: config.tournamentExperiments[1],
          config: config,
          personaID: "buyer",
          endedAt: 270,
          verdict: .unclear,
          scores: narrowScores,
          missingCapabilities: ["csv_import"]
        ),
        makeDecisionAdvisorRecord(
          id: "kill-a",
          experiment: weakExperiment,
          config: config,
          personaID: "operator",
          mode: .personaModel,
          endedAt: 260,
          verdict: .weak,
          scores: weakScores,
          objections: ["No reason to switch"]
        ),
        makeDecisionAdvisorRecord(
          id: "kill-b",
          experiment: weakExperiment,
          config: config,
          personaID: "buyer",
          mode: .personaModel,
          endedAt: 250,
          verdict: .rejected,
          scores: weakScores,
          objections: ["No reason to switch"]
        ),
      ]
    )

    let proposals = ProductTournamentDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    )
    let candidates = TournamentAutomationDecisionCandidateAdvisor.candidates(
      config: config,
      evidenceIndex: index
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )
    let promote = try #require(
      proposals.first { $0.experimentID == config.tournamentExperiments[0].id })
    let narrow = try #require(
      proposals.first { $0.experimentID == config.tournamentExperiments[1].id })
    let kill = try #require(proposals.first { $0.experimentID == weakExperiment.id })

    try #require(promote.update.decision == .promote)
    try #require(promote.update.evidenceRunIDs.first == "promote-a")
    try #require(promote.update.summary.contains("Tournament readiness"))
    try #require(promote.update.summary.contains("current-alternative proof from 2"))
    try #require(narrow.update.decision == .narrow)
    try #require(narrow.update.summary.contains("csv_import"))
    try #require(kill.update.decision == .kill)
    try #require(kill.update.decidedBy == "Product Tournament Decision Advisor")
    try #require(kill.update.summary.contains("current-alternative proof from 2"))
    try #require(candidates.count == 3)
    let liftCandidate = try #require(candidates.first { $0.experimentID == promote.experimentID })
    let cutCandidate = try #require(candidates.first { $0.experimentID == kill.experimentID })
    try #require(liftCandidate.pressure == .lift)
    try #require(liftCandidate.displayTitle == "continue -> promote")
    try #require(liftCandidate.displaySubtitle.contains("Lift"))
    try #require(Array(liftCandidate.evidenceRunIDs.prefix(2)) == ["promote-a", "promote-b"])
    try #require(cutCandidate.pressure == .cut)
    try #require(cutCandidate.displayTitle == "continue -> kill")
    try #require(cutCandidate.displaySubtitle.contains("Cut"))
    try #require(cutCandidate.displayDetail.contains("kill-a"))
    try #require(digest.contains("Tournament automation decision candidates"))
    try #require(digest.contains("action apply_decision"))
    try #require(digest.contains("target_decision promote"))
    try #require(digest.contains("pressure lift"))
    try #require(digest.contains("target_decision kill"))
    try #require(digest.contains("pressure cut"))
    try #require(digest.contains("evidence promote-a"))
    try #require(digest.contains("evidence kill-a"))
  }

  @Test func tournamentDecisionAdvisorDefersPromotionWhenEvidenceIsSplit() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let buyerScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == buyerID }
    )
    let operatorScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == operatorID }
    )
    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let rejectedScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "split-promote-a",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 600,
          verdict: .strongPull,
          scores: strongScores,
          scenarioID: operatorScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-promote-b",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          mode: .personaModel,
          endedAt: 590,
          verdict: .strongPull,
          scores: strongScores,
          scenarioID: buyerScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-promote-c",
          experiment: experiment,
          config: config,
          personaID: "operations-lead",
          endedAt: 580,
          verdict: .strongPull,
          scores: strongScores,
          scenarioID: operatorScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-promote-d",
          experiment: experiment,
          config: config,
          personaID: "finance-lead",
          endedAt: 570,
          verdict: .strongPull,
          scores: strongScores,
          scenarioID: operatorScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-promote-e",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          endedAt: 560,
          verdict: .promising,
          scores: strongScores,
          scenarioID: operatorScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-reject-a",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          mode: .personaModel,
          endedAt: 550,
          verdict: .rejected,
          scores: rejectedScores,
          objections: ["Too risky to switch budget workflows"],
          scenarioID: buyerScenario.id
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let tension = try #require(
      TournamentAutomationEvidenceTensionAdvisor.tension(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .promote)
    try #require(readiness.proofDebt.isClear)
    try #require(tension.label == "resolve split tournament evidence")
    try #require(tension.positiveEvidenceRunIDs.first == "split-promote-a")
    try #require(tension.negativeEvidenceRunIDs == ["split-reject-a"])
    try #require(tension.targetPersonaID == buyerID)
    try #require(tension.targetPersonaName == "Budget owner")
    try #require(tension.targetScenarioID == buyerScenario.id)
    try #require(tension.targetCohortID == config.scenarioCohorts[0].id)
    try #require(tension.targetDecision == .promote)
    try #require(tension.displaySubtitle.contains("decision promote"))
    try #require(tension.auditSummary.contains("target_decision promote"))
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(
      TournamentAutomationDecisionCandidateAdvisor.candidates(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Resolve split tournament evidence")
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetPersonaID == buyerID)
    try #require(action.targetPersonaName == "Budget owner")
    try #require(action.targetScenarioID == buyerScenario.id)
    try #require(action.targetDecision == .promote)
    try #require(action.detail.contains("pull signal"))
    try #require(action.detail.contains("rejection signal"))
    try #require(action.detail.contains(buyerScenario.id))
    try #require(digest.contains("Tournament automation evidence tensions"))
    try #require(digest.contains("action resolve_signal_split"))
    try #require(digest.contains("pull split-promote-a"))
    try #require(digest.contains("reject split-reject-a"))
    try #require(digest.contains("target_scenario \(buyerScenario.id)"))
    try #require(digest.contains("target_name Budget owner"))
    try #require(digest.contains("target_decision promote"))

    do {
      _ = try ProductTournamentDecisionAdvisor.applyingRecommendedDecision(
        experimentID: experiment.id,
        to: config,
        evidenceIndex: index
      )
      #expect(Bool(false), "Expected split evidence to block automatic tournament promotion.")
    } catch let error as ProductTournamentDecisionAdvisorError {
      try #require(error == .noProposal(experiment.id))
    }

    let stalledAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-split-stalled",
      startedAt: 700,
      endedAt: 710,
      executedStepIDs: [TournamentAutomationCycleFailureAdvisor.stepID(for: action)],
      experimentIDs: [experiment.id],
      messages: ["persona-model target ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["split-resolution-repeat"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      evidenceTensionSummaries: [tension.auditSummary],
      stopReason: .noExecutableStep,
      stopDetail: "Stopped because no executable tournament automation step remains.",
      userMessage: "Tournament automation cycle ran 1 step(s). Evidence tensions remained split."
    )
    let stalledConfig = config.recordingTournamentAutomationCycleAudit(stalledAudit)
    let mismatchedDecisionAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-split-wrong-decision",
      startedAt: 720,
      endedAt: 730,
      executedStepIDs: [TournamentAutomationCycleFailureAdvisor.stepID(for: action)],
      experimentIDs: [experiment.id],
      messages: ["persona-model target ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["split-resolution-kill-repeat"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      evidenceTensionSummaries: [
        tension.auditSummary.replacingOccurrences(
          of: "target_decision promote",
          with: "target_decision kill"
        )
      ],
      stopReason: .noExecutableStep,
      stopDetail: "Stopped because no executable tournament automation step remains.",
      userMessage: "Tournament automation cycle ran 1 step(s). Evidence tensions remained split."
    )
    let mismatchedDecisionConfig = config.recordingTournamentAutomationCycleAudit(
      mismatchedDecisionAudit)
    try #require(
      TournamentAutomationCycleLearningAdvisor.stalledEvidenceTensionAudit(
        for: action,
        experiment: experiment,
        config: mismatchedDecisionConfig,
        evidenceIndex: index
      ) == nil)
    let learningAudit = try #require(
      TournamentAutomationCycleLearningAdvisor.stalledEvidenceTensionAudit(
        for: action,
        experiment: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let stalledAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let blockedStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: stalledConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(learningAudit.id == stalledAudit.id)
    try #require(stalledAction.kind == .refineContender)
    try #require(stalledAction.title == "Retarget split tournament evidence")
    try #require(stalledAction.detail.contains(stalledAudit.id))
    try #require(
      stalledAction.detail.contains("still split") || stalledAction.detail.contains("contradiction")
    )
    try #require(stalledAction.targetScenarioID == buyerScenario.id)
    try #require(stalledAction.targetDecision == .promote)
    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: stalledConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ) == nil)
    try #require(!blockedStep.canExecute)
    try #require(blockedStep.action.kind == .refineContender)
    try #require(blockedStep.action.targetDecision == .promote)
    try #require(blockedStep.blockedReason?.contains(stalledAudit.id) == true)
    try #require(blockedStep.blockedReason?.contains("split-evidence") == true)
    let stalledDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: stalledConfig,
      evidenceIndex: index
    )
    try #require(stalledDigest.contains("Retarget split tournament evidence"))
    try #require(stalledDigest.contains("target_decision promote"))
  }

  @Test func tournamentDecisionAdvisorDefersKillWhenEvidenceIsSplit() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let operatorScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == operatorID }
    )
    let buyerScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == buyerID }
    )
    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "split-kill-pull",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 300,
          verdict: .strongPull,
          scores: strongScores,
          scenarioID: operatorScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-kill-weak",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 200,
          verdict: .weak,
          scores: weakScores,
          scenarioID: operatorScenario.id
        ),
        makeDecisionAdvisorRecord(
          id: "split-kill-reject",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          mode: .personaModel,
          endedAt: 100,
          verdict: .rejected,
          scores: weakScores,
          scenarioID: buyerScenario.id
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let tension = try #require(
      TournamentAutomationEvidenceTensionAdvisor.tension(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .kill)
    try #require(tension.positiveEvidenceRunIDs == ["split-kill-pull"])
    try #require(tension.negativeEvidenceRunIDs == ["split-kill-weak", "split-kill-reject"])
    try #require(tension.targetPersonaID == operatorID)
    try #require(tension.targetScenarioID == operatorScenario.id)
    try #require(tension.targetDecision == .kill)
    try #require(tension.auditSummary.contains("target_decision kill"))
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.title == "Resolve split tournament evidence")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetScenarioID == operatorScenario.id)
    try #require(action.targetDecision == .kill)
    try #require(digest.contains("target_decision kill"))
  }

  @Test func tournamentDecisionAdvisorRequiresPersonaModelEvidenceBeforeKill() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "weak-a",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          endedAt: 300,
          verdict: .weak,
          scores: weakScores,
          objections: ["No reason to switch"]
        ),
        makeDecisionAdvisorRecord(
          id: "weak-b",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          endedAt: 200,
          verdict: .rejected,
          scores: weakScores,
          objections: ["No reason to switch"]
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let signal = TournamentAutomationExperimentRanker.signal(
      for: experiment,
      config: config,
      evidenceIndex: index
    )
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.personaModelCompletedRunCount == 0)
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(
      readiness.rationale.contains {
        $0.contains("stopping requires simulated-user rejection")
      })
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run persona-model rejection check")
    try #require(action.detail.contains("before stopping the experiment"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == .kill)
    try #require(signal.pressure == .cut)
    try #require(signal.targetDecision == .kill)
    try #require(proofTarget.label == "run targeted persona-model rejection proof")
    try #require(proofTarget.displayTitle == "run targeted persona-model rejection proof")
    try #require(proofTarget.targetDecision == .kill)
    try #require(proofTarget.displaySubtitle.contains("decision kill"))
    try #require(proofTarget.auditSummary.contains("target_decision kill"))
    try #require(digest.contains("Tournament automation proof targets"))
    try #require(digest.contains("target_decision kill"))
  }

  @Test func tournamentAutomationProofTargetsIncludeRoundOneFocusedPlanProof() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context.",
      now: Date(timeIntervalSince1970: 10)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.first)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == contender.experimentID })
    let emptyIndex = ProductTournamentEvidenceIndex.build(records: [])

    let initialTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: emptyIndex
      ))
    let initialDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: emptyIndex
    )
    let initialSteps = TournamentAutomationPlanner.steps(
      config: config,
      evidenceIndex: emptyIndex
    )
    let initialStep = try #require(initialSteps.first { $0.contenderID == contender.id })
    let initialCyclePlan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: emptyIndex
    )

    try #require(initialTarget.label == "Run Plan Proof")
    try #require(initialTarget.nextActionTitle == "Run Plan Proof")
    try #require(initialTarget.tournamentID == tournament.id)
    try #require(initialTarget.contenderID == contender.id)
    try #require(initialTarget.roundID == planRound.id)
    try #require(initialTarget.tournamentPositionSummary?.contains("Product plans contender") == true)
    try #require(initialTarget.tournamentPositionSummary?.contains("of 2 active contender(s)") == true)
    try #require(initialTarget.tournamentPositionSummary?.contains("1 rival product") == true)
    try #require(initialTarget.displaySubtitle.contains("contender \(contender.id)"))
    try #require(initialTarget.displayDetail.contains("Tournament position"))
    try #require(initialTarget.displayDetail.contains("1 rival product"))
    try #require(initialTarget.displayDetail.contains("Tournament: \(tournament.id)"))
    try #require(initialTarget.displayDetail.contains("Round: \(planRound.id)"))
    try #require(initialTarget.auditSummary.contains("position Product plans contender"))
    try #require(initialTarget.auditSummary.contains("tournament \(tournament.id)"))
    try #require(initialTarget.auditSummary.contains("contender \(contender.id)"))
    try #require(initialStep.kind == .runPlanProof)
    try #require(initialStep.action.kind == .runPlanProof)
    try #require(initialStep.action.title == "Run Plan Proof")
    try #require(initialStep.tournamentID == tournament.id)
    try #require(initialStep.contenderID == contender.id)
    try #require(initialStep.roundID == planRound.id)
    try #require(initialStep.id.contains("run_plan_proof"))
    try #require(initialStep.id.contains(contender.id))
    try #require(initialCyclePlan.executableSteps.contains(initialStep))
    let startingProofDebtSnapshot = try #require(
      TournamentAutomationProofDebtSnapshotter.snapshot(
        experimentIDs: [experiment.id],
        config: config,
        evidenceIndex: emptyIndex,
        preferredSteps: [experiment.id: initialStep]
      ))
    try #require(startingProofDebtSnapshot.count == 6)
    try #require(startingProofDebtSnapshot.summary.contains("Round 1 plan proof"))
    try #require(startingProofDebtSnapshot.summary.contains("2 plan evaluation(s)"))
    try #require(startingProofDebtSnapshot.summary.contains("buyer/sponsor signal"))
    try #require(startingProofDebtSnapshot.summary.contains("willingness to pay"))
    try #require(startingProofDebtSnapshot.personaModelPlanEvaluationCount == 0)
    try #require(startingProofDebtSnapshot.modelFreePlanEvaluationCount == 0)
    try #require(initialDigest.contains("Tournament automation proof targets"))
    try #require(initialDigest.contains("plan_modes persona_model 0 model_free 0"))
    try #require(initialDigest.contains("target Run Plan Proof"))
    try #require(initialDigest.contains("position Product plans contender"))
    try #require(initialDigest.contains("1 rival product"))
    try #require(initialDigest.contains("kind run_plan_proof"))
    try #require(initialDigest.contains("mode model_free_plan"))
    try #require(initialDigest.contains("tournament \(tournament.id)"))
    try #require(initialDigest.contains("contender \(contender.id)"))
    try #require(initialDigest.contains("round \(planRound.id)"))

    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try workspace.writeProductTournamentConfig(config)
    let executionOutcome = try TournamentAutomationPlanProofStepExecutor.run(
      initialStep,
      in: workspace,
      now: Date(timeIntervalSince1970: 20)
    )
    let executedIndex = workspace.readProductTournamentEvidenceIndex()

    try #require(executionOutcome.focusedContenderID == contender.id)
    try #require(executionOutcome.focusedProofTargetSummary?.contains("economic-buyer") == true)
    try #require(executionOutcome.records.allSatisfy { $0.contenderID == contender.id })
    try #require(executionOutcome.completedEvaluationCount == executionOutcome.records.count)
    try #require(executedIndex.planEvaluationSummaries.count == executionOutcome.records.count)
    try #require(
      executedIndex.aggregate.planReadinessByContender.map(\.contenderID) == [contender.id])
    let endingProofDebtSnapshot = try #require(
      TournamentAutomationProofDebtSnapshotter.snapshot(
        experimentIDs: [experiment.id],
        config: config,
        evidenceIndex: executedIndex,
        preferredSteps: [experiment.id: initialStep]
      ))
    try #require(endingProofDebtSnapshot.count < startingProofDebtSnapshot.count)
    try #require(endingProofDebtSnapshot.count == 0)
    try #require(endingProofDebtSnapshot.summary.contains("Round 1 plan proof"))
    try #require(endingProofDebtSnapshot.summary.contains("plan proof complete"))
    try #require(endingProofDebtSnapshot.personaModelPlanEvaluationCount == 0)
    try #require(
      endingProofDebtSnapshot.modelFreePlanEvaluationCount
        == executionOutcome.completedEvaluationCount)
    let planProofAudit = TournamentAutomationCycleOutcome(
      executedSteps: [initialStep],
      messages: [executionOutcome.userMessage],
      maxSteps: 1,
      stopReason: .reachedStepLimit,
      evidenceRunIDs: executionOutcome.records.map(\.id),
      completedEvidenceRunCount: executionOutcome.completedEvaluationCount,
      failedEvidenceRunCount: executionOutcome.records.count
        - executionOutcome.completedEvaluationCount,
      skippedScenarioCount: executionOutcome.skippedContenderIDs.count,
      startingProofDebtCount: startingProofDebtSnapshot.count,
      endingProofDebtCount: endingProofDebtSnapshot.count,
      startingProofDebtSummary: startingProofDebtSnapshot.summary,
      endingProofDebtSummary: endingProofDebtSnapshot.summary,
      startingPersonaModelPlanEvaluationCount: startingProofDebtSnapshot
        .personaModelPlanEvaluationCount,
      endingPersonaModelPlanEvaluationCount: endingProofDebtSnapshot
        .personaModelPlanEvaluationCount,
      startingModelFreePlanEvaluationCount: startingProofDebtSnapshot
        .modelFreePlanEvaluationCount,
      endingModelFreePlanEvaluationCount: endingProofDebtSnapshot.modelFreePlanEvaluationCount
    ).audit(
      startedAt: Date(timeIntervalSince1970: 20),
      endedAt: Date(timeIntervalSince1970: 30)
    )
    try #require(planProofAudit.proofDebtDelta == -6)
    try #require(planProofAudit.startingProofDebtSummary?.contains("Round 1 plan proof") == true)
    try #require(planProofAudit.endingProofDebtSummary?.contains("plan proof complete") == true)
    try #require(planProofAudit.startingPersonaModelPlanEvaluationCount == 0)
    try #require(planProofAudit.endingPersonaModelPlanEvaluationCount == 0)
    try #require(planProofAudit.startingModelFreePlanEvaluationCount == 0)
    try #require(
      planProofAudit.endingModelFreePlanEvaluationCount
        == executionOutcome.completedEvaluationCount)
    try #require(
      planProofAudit.planEvaluationModeContext?
        .contains("plan_modes start_persona_model 0 start_model_free 0") == true)
    try #require(
      planProofAudit.planEvaluationModeContext?
        .contains("end_persona_model 0 end_model_free 2") == true)
    try #require(planProofAudit.userMessage.contains("Proof debt improved by 6"))
    try #require(
      planProofAudit.userMessage.contains(
        "Plan evidence modes: persona-model 0 -> 0, model-free 0 -> 2."))
    try #require(
      planProofAudit.summary.contains("plan modes persona-model 0 -> 0, model-free 0 -> 2"))
    let auditedPlanProofConfig = config.recordingTournamentAutomationCycleAudit(planProofAudit)
    let latestPlanProofDelta = try #require(
      TournamentAutomationPlanProofAuditDeltaFinder.latest(
        for: contender,
        in: auditedPlanProofConfig
      ))
    try #require(
      latestPlanProofDelta.contextSummary.contains(
        "latest_plan_proof_delta proof_debt 6 -> 0 (-6)"))
    try #require(
      latestPlanProofDelta.contextSummary.contains(
        "plan_modes start_persona_model 0 start_model_free 0 end_persona_model 0 end_model_free 2"
      ))
    try #require(latestPlanProofDelta.contextSummary.contains("audit \(planProofAudit.id)"))
    try #require(latestPlanProofDelta.displaySummary == "Proof debt cleared 6 (6 -> 0)")
    try #require(latestPlanProofDelta.displaySystemImage == "checkmark.seal")
    try #require(
      latestPlanProofDelta.helpSummary.contains(
        "Starting: \(experiment.id): contender \(contender.id)"))
    try #require(
      latestPlanProofDelta.helpSummary.contains(
        "Ending: \(experiment.id): contender \(contender.id)"))
    let proofDeltaOverview = TournamentPlanProofDeltaOverview.items(
      config: auditedPlanProofConfig,
      evidenceIndex: executedIndex
    )
    try #require(proofDeltaOverview.count == 2)
    let focusedOverview = try #require(
      proofDeltaOverview.first { $0.contenderID == contender.id })
    let siblingOverview = try #require(
      proofDeltaOverview.first { $0.contenderID != contender.id })
    try #require(focusedOverview.displaySubtitle == "Proof debt cleared 6 (6 -> 0)")
    try #require(focusedOverview.displaySystemImage == "checkmark.seal")
    try #require(focusedOverview.contextLine.contains("focused_action Proof Complete"))
    try #require(
      focusedOverview.contextLine.contains("latest_plan_proof_delta proof_debt 6 -> 0 (-6)"))
    try #require(siblingOverview.displaySubtitle == "No proof delta yet")
    try #require(siblingOverview.contextLine.contains("latest_plan_proof_delta none"))
    let proofDeltaOverviewLines = TournamentPlanProofDeltaOverview.contextLines(
      config: auditedPlanProofConfig,
      evidenceIndex: executedIndex
    )
    try #require(proofDeltaOverviewLines.contains("Round 1 plan-proof contender overview:"))
    try #require(proofDeltaOverviewLines.joined(separator: "\n").contains(contender.id))
    let planProofDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: auditedPlanProofConfig,
      evidenceIndex: executedIndex
    )
    try #require(planProofDigest.contains("Round 1 plan-proof automation deltas"))
    try #require(planProofDigest.contains("proof_debt 6 -> 0 (-6)"))
    try #require(planProofDigest.contains("starting_plan_proof_debt"))
    try #require(planProofDigest.contains("2 plan evaluation(s)"))
    try #require(planProofDigest.contains("ending_plan_proof_debt"))
    try #require(planProofDigest.contains("plan proof complete"))
    try #require(
      planProofDigest.contains(
        "plan_modes start_persona_model 0 start_model_free 0 end_persona_model 0 end_model_free 2"
      ))
    try #require(planProofDigest.contains(initialStep.id))
    try #require(planProofDigest.contains(executionOutcome.records[0].id))
    try #require(planProofDigest.contains("Round 1 plan-proof contender overview"))
    try #require(planProofDigest.contains("focused_action Proof Complete"))
    try #require(planProofDigest.contains("latest_plan_proof_delta none"))
    let planProofContenderLine = try #require(
      planProofDigest.split(separator: "\n").map(String.init).first {
        $0.contains("Contender \(contender.id)")
      })
    try #require(
      planProofContenderLine.contains("latest_plan_proof_delta proof_debt 6 -> 0 (-6)"))
    try #require(planProofContenderLine.contains("audit \(planProofAudit.id)"))
    try #require(
      planProofContenderLine.contains("starting \(experiment.id): contender \(contender.id)"))
    try #require(
      planProofContenderLine.contains("ending \(experiment.id): contender \(contender.id)"))
    let roundTwoOutcome = try ProductTournamentPlanTransitioner.applyBestProposal(
      tournamentID: tournament.id,
      roundID: planRound.id,
      to: auditedPlanProofConfig,
      evidenceIndex: executedIndex,
      now: Date(timeIntervalSince1970: 40)
    )
    let roundTwoConfig = roundTwoOutcome.config
    let activeRoundTwo = try #require(
      roundTwoConfig.tournamentRounds.first { $0.id == roundTwoOutcome.toRoundID })
    let postTransitionOverview = TournamentPlanProofDeltaOverview.items(
      config: roundTwoConfig,
      evidenceIndex: executedIndex
    )
    let postTransitionDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: roundTwoConfig,
      evidenceIndex: executedIndex
    )
    try #require(roundTwoOutcome.proposal.recommendation == .advanceToFeasibility)
    try #require(activeRoundTwo.kind == .coreTechnology)
    try #require(activeRoundTwo.status == .active)
    try #require(postTransitionOverview.isEmpty)
    try #require(postTransitionDigest.contains("Round 1 plan-proof automation deltas"))
    try #require(!postTransitionDigest.contains("Round 1 plan-proof contender overview"))

    let operatorSegment = try #require(
      config.userSegments.first { $0.id == contender.targetSegmentIDs.first })
    let operatorOnlyIndex = ProductTournamentEvidenceIndex.build(
      records: [],
      planEvaluationRecords: [
        try makePlanProofRecord(
          id: "operator-only-plan-proof",
          tournament: tournament,
          round: planRound,
          contender: contender,
          config: config,
          segment: operatorSegment
        )
      ]
    )
    let followUpTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: operatorOnlyIndex
      ))

    try #require(followUpTarget.label == "Run Buyer Proof")
    try #require(followUpTarget.nextActionTitle == "Run Buyer Proof")
    try #require(followUpTarget.debtSummary.contains("buyer/sponsor signal"))
    try #require(followUpTarget.tournamentID == tournament.id)
    try #require(followUpTarget.contenderID == contender.id)
    try #require(followUpTarget.roundID == planRound.id)
  }

  @Test func tournamentAutomationRunsPersonaPlanProofBeforeRoundOneTransitionWhenAvailable()
    async throws
  {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    try workspace.writeProductTournamentConfig(config)
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let initialStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty,
        isPersonaModelAvailable: true
      ))

    try #require(initialStep.kind == .runPlanProof)
    try #require(initialStep.action.requiredSimulationMode == nil)
    _ = try TournamentAutomationPlanProofStepExecutor.run(
      initialStep,
      in: workspace,
      now: Date(timeIntervalSince1970: 20)
    )
    let modelFreeIndex = workspace.readProductTournamentEvidenceIndex()
    let modelFreeConfig = try workspace.readProductTournamentConfig()
    let readiness = try #require(modelFreeIndex.aggregate.planReadinessByContender.first)

    try #require(readiness.modelFreeEvaluationCount == 2)
    try #require(readiness.personaModelEvaluationCount == 0)
    let noFoundationStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: modelFreeConfig,
        evidenceIndex: modelFreeIndex,
        isPersonaModelAvailable: false
      ))
    try #require(noFoundationStep.kind == .applyRoundTransition)
    try #require(noFoundationStep.title == "Apply Round 1 transition")

    let modelFreeExperiment = try #require(
      modelFreeConfig.tournamentExperiments.first { $0.id == initialStep.experimentID })
    let personaTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: modelFreeExperiment,
        config: modelFreeConfig,
        evidenceIndex: modelFreeIndex,
        isPersonaModelAvailable: true
      ))
    try #require(personaTarget.label == "Run Persona Plan Proof")
    try #require(personaTarget.requiredSimulationMode == .personaModel)
    try #require(personaTarget.debtSummary.contains("persona-model plan proof missing"))
    try #require(personaTarget.auditSummary.contains("required_mode persona_model"))

    let personaStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: modelFreeConfig,
        evidenceIndex: modelFreeIndex,
        isPersonaModelAvailable: true
      ))
    try #require(personaStep.kind == .runPlanProof)
    try #require(personaStep.action.kind == .runPlanProof)
    try #require(personaStep.action.requiredSimulationMode == .personaModel)
    try #require(personaStep.title == "Run Persona Plan Proof")
    try #require(personaStep.detail.contains("persona-model simulated-user plan proof"))
    try #require(personaStep.tournamentID == tournament.id)
    try #require(personaStep.roundID == planRound.id)
    do {
      _ = try TournamentAutomationPlanProofStepExecutor.run(
        personaStep,
        in: workspace,
        now: Date(timeIntervalSince1970: 30)
      )
      Issue.record("Expected synchronous plan-proof executor to reject persona-model proof.")
    } catch let error as TournamentAutomationPlanProofStepError {
      try #require(error == .personaModelRequiresAsync(personaStep.id))
    }
    let stream = TournamentAutomationPlanEvaluationModelStream(
      response: """
        {
          "painRecognition": 5,
          "workflowImprovement": 5,
          "alternativeAdvantage": 5,
          "switchingReadiness": 4,
          "continuedUsePull": 5,
          "willingnessToPayScore": 5,
          "estimatedMonthlyPriceCents": 9900,
          "commercialProofSummary": "The buyer would sponsor a feasibility proof.",
          "currentAlternativeComparison": "The plan beats the spreadsheet status quo.",
          "verdict": "strong_pull",
          "summary": "Persona-model plan proof supports feasibility.",
          "objections": ["Needs core import proof."],
          "missingCapabilities": ["core_import_proof"],
          "rationale": ["The persona sees budget value."],
          "planStrengths": ["Clear buyer value."],
          "planRisks": ["Import feasibility remains unproven."]
        }
        """
    )
    let personaOutcome = try await TournamentAutomationPlanProofStepExecutor.runAutomation(
      personaStep,
      in: workspace,
      now: Date(timeIntervalSince1970: 30),
      streamText: { prompt in await stream.respond(prompt) }
    )
    let personaIndex = workspace.readProductTournamentEvidenceIndex()
    let personaContenderID = try #require(personaStep.contenderID)
    let updatedReadiness = try #require(
      personaIndex.aggregate.planReadinessByContender.first {
        $0.contenderID == personaContenderID
      })
    let prompts = await stream.recordedPrompts()
    let postPersonaStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: try workspace.readProductTournamentConfig(),
        evidenceIndex: personaIndex,
        isPersonaModelAvailable: true
      ))

    try #require(personaOutcome.personaModelEvaluationCount == 2)
    try #require(personaOutcome.records.allSatisfy { $0.mode == .personaModel })
    try #require(prompts.count == 2)
    try #require(updatedReadiness.modelFreeEvaluationCount == 2)
    try #require(updatedReadiness.personaModelEvaluationCount == 2)
    try #require(postPersonaStep.kind == .applyRoundTransition)
    try #require(postPersonaStep.title == "Apply Round 1 transition")
  }

  @Test func tournamentAutomationStalledProofTargetRequiresMatchingDecisionIntent() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "weak-a",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 300,
          verdict: .weak,
          scores: weakScores,
          objections: ["No reason to switch"],
          currentAlternativeComparison: ""
        ),
        makeDecisionAdvisorRecord(
          id: "weak-b",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          mode: .personaModel,
          endedAt: 200,
          verdict: .rejected,
          scores: weakScores,
          objections: ["No reason to switch"],
          currentAlternativeComparison: ""
        ),
      ]
    )
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let stepID = TournamentAutomationCycleFailureAdvisor.stepID(for: action)

    func stalledAudit(id: String, proofTargetSummary: String) -> TournamentAutomationCycleAudit {
      TournamentAutomationCycleAudit(
        id: id,
        startedAt: 500,
        endedAt: 510,
        executedStepIDs: [stepID],
        experimentIDs: [experiment.id],
        messages: ["persona-model rejection target ran 1 scenario(s): 1 completed."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["kill-proof-run"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 4,
        endingProofDebtCount: 4,
        proofTargetSummaries: [proofTargetSummary],
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (4 -> 4)."
      )
    }

    let mismatchedSummary = proofTarget.auditSummary.replacingOccurrences(
      of: "target_decision kill",
      with: "target_decision promote"
    )
    let mismatchedConfig = config.recordingTournamentAutomationCycleAudit(
      stalledAudit(
        id: "tournament-cycle-wrong-decision-target",
        proofTargetSummary: mismatchedSummary
      )
    )
    let matchedAudit = stalledAudit(
      id: "tournament-cycle-matching-decision-target",
      proofTargetSummary: proofTarget.auditSummary
    )
    let matchedConfig = config.recordingTournamentAutomationCycleAudit(
      matchedAudit
    )
    let matchedConfigTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: matchedConfig,
        evidenceIndex: index
      ))
    let mismatchedStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: mismatchedConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let matchedStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: matchedConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let matchedDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: matchedConfig,
      evidenceIndex: index
    )

    try #require(action.targetDecision == .kill)
    let targetScenarioID = try #require(action.targetScenarioID)
    try #require(action.title == "Run persona-model alternative rejection check")
    try #require(matchedAudit.proofDebtDelta == 0)
    try #require(matchedAudit.proofTargetSummaries[0].contains("target_decision kill"))
    try #require(matchedAudit.proofTargetSummaries[0].contains(targetScenarioID))
    try #require(proofTarget.auditSummary.contains("target_decision kill"))
    try #require(proofTarget.auditSummary.contains(targetScenarioID))
    try #require(matchedConfigTarget.label == proofTarget.label)
    if let targetPersonaName = action.targetPersonaName {
      try #require(proofTarget.auditSummary.localizedCaseInsensitiveContains(targetPersonaName))
      try #require(
        matchedAudit.proofTargetSummaries[0].localizedCaseInsensitiveContains(targetPersonaName))
    }
    try #require(mismatchedSummary.contains("target_decision promote"))
    try #require(
      TournamentAutomationCycleLearningAdvisor.stalledProofTargetAudit(
        for: action,
        experiment: experiment,
        config: mismatchedConfig,
        evidenceIndex: index
      ) == nil)
    try #require(
      TournamentAutomationCycleLearningAdvisor.stalledProofTargetAudit(
        for: action,
        experiment: experiment,
        config: matchedConfig,
        evidenceIndex: index
      )?.id == "tournament-cycle-matching-decision-target")
    try #require(matchedDigest.contains("target_decision kill"))
    try #require(matchedDigest.contains(targetScenarioID))
    try #require(mismatchedStep.canExecute)
    try #require(!matchedStep.canExecute)
    try #require(matchedStep.blockedReason != nil)
  }

  @Test func tournamentAutomationFailureBlockRequiresMatchingDecisionIntent() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let scenarioID = "\(experiment.id)-buyer-starter-scenario"
    let promoteAction = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .runCohort,
      title: "Run persona-model validation cohort",
      detail: "Run promote proof.",
      priority: 78,
      cohortID: "\(experiment.id)-cohort",
      requiredSimulationMode: .personaModel,
      targetPersonaID: "buyer",
      targetPersonaName: "Budget owner",
      targetScenarioID: scenarioID,
      targetDecision: .promote
    )
    let killAction = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .runCohort,
      title: "Run persona-model rejection check",
      detail: "Run kill proof.",
      priority: 82,
      cohortID: "\(experiment.id)-cohort",
      requiredSimulationMode: .personaModel,
      targetPersonaID: "buyer",
      targetPersonaName: "Budget owner",
      targetScenarioID: scenarioID,
      targetDecision: .kill
    )
    let promoteStepID = TournamentAutomationCycleFailureAdvisor.stepID(for: promoteAction)
    let killStepID = TournamentAutomationCycleFailureAdvisor.stepID(for: killAction)
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-promote-proof-failed",
        startedAt: 500,
        endedAt: 505,
        executedStepIDs: [],
        experimentIDs: [experiment.id],
        messages: [],
        maxSteps: 3,
        stopReason: .executionFailed,
        stopStepID: promoteStepID,
        stopStepTitle: "Run persona-model validation cohort",
        stopDetail: "Stopped because promote proof failed: runner crashed.",
        userMessage: "Tournament automation cycle ran no steps."
      )
    )

    try #require(promoteStepID.contains("target_decision:promote"))
    try #require(killStepID.contains("target_decision:kill"))
    try #require(promoteStepID != killStepID)
    try #require(
      TournamentAutomationCycleFailureAdvisor.blockingAudit(
        forStepID: promoteStepID,
        experiment: experiment,
        config: config,
        evidenceIndex: .empty
      )?.id == "tournament-cycle-promote-proof-failed")
    try #require(
      TournamentAutomationCycleFailureAdvisor.blockingAudit(
        forStepID: killStepID,
        experiment: experiment,
        config: config,
        evidenceIndex: .empty
      ) == nil)
  }

  @Test func tournamentDecisionAdvisorRequiresPersonaModelUserBreadthBeforeKill() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "weak-a",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 300,
          verdict: .weak,
          scores: weakScores,
          objections: ["No reason to switch"]
        ),
        makeDecisionAdvisorRecord(
          id: "weak-b",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          endedAt: 200,
          verdict: .rejected,
          scores: weakScores,
          objections: ["No reason to switch"]
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.personaModelCompletedRunCount == 1)
    try #require(readiness.personaModelDistinctPersonaCount == 1)
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(
      readiness.rationale.contains {
        $0.contains("persona-model rejection evidence across at least 2 simulated users")
      })
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run persona-model rejection check")
    try #require(action.detail.contains("requires at least 2"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == .kill)
  }

  @Test func tournamentDecisionAdvisorRequiresCurrentAlternativeProofBeforeKill() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "weak-a",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 300,
          verdict: .weak,
          scores: weakScores,
          objections: ["No reason to switch"],
          currentAlternativeComparison: ""
        ),
        makeDecisionAdvisorRecord(
          id: "weak-b",
          experiment: experiment,
          config: config,
          personaID: buyerID,
          mode: .personaModel,
          endedAt: 200,
          verdict: .rejected,
          scores: weakScores,
          objections: ["No reason to switch"],
          currentAlternativeComparison: ""
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.personaModelCompletedRunCount == 2)
    try #require(readiness.personaModelDistinctPersonaCount == 2)
    try #require(readiness.personaModelCurrentAlternativePersonaCount == 0)
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(
      readiness.rationale.contains {
        $0.contains("current-alternative rejection proof")
      })
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run persona-model alternative rejection check")
    try #require(action.detail.contains("current-alternative proof"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == .kill)
    try #require(proofTarget.label == "run persona-model alternative rejection proof")
    try #require(proofTarget.targetDecision == .kill)
    try #require(digest.contains("target run persona-model alternative rejection proof"))
  }

  @Test func tournamentDecisionAdvisorRequiresPersonaModelEvidenceBeforePromotion() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let index = makeTournamentPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includePersonaModelEvidence: false
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let signal = TournamentAutomationExperimentRanker.signal(
      for: experiment,
      config: config,
      evidenceIndex: index
    )
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.personaModelCompletedRunCount == 0)
    try #require(readiness.modelFreeCompletedRunCount == 3)
    try #require(readiness.recommendation == .keepGoing)
    try #require(readiness.rationale.contains { $0.contains("No persona-model evidence") })
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run persona-model validation cohort")
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == .promote)
    try #require(signal.pressure == .lift)
    try #require(signal.targetDecision == .promote)
    try #require(proofTarget.label == "run targeted persona-model validation proof")
    try #require(proofTarget.displayTitle == "run targeted persona-model validation proof")
    try #require(proofTarget.targetDecision == .promote)
    try #require(proofTarget.displaySubtitle.contains("decision promote"))
    try #require(proofTarget.auditSummary.contains("target_decision promote"))
    try #require(digest.contains("Tournament automation proof targets"))
    try #require(digest.contains("target_decision promote"))
  }

  @Test func tournamentDecisionAdvisorRequiresPersonaModelUserBreadthBeforePromotion() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let index = makeTournamentPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includePersonaModelEvidence: true,
      includePersonaModelUserBreadth: false
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.personaModelCompletedRunCount == 1)
    try #require(readiness.personaModelDistinctPersonaCount == 1)
    try #require(readiness.recommendation == .keepGoing)
    try #require(readiness.rationale.contains { $0.contains("at least 2 simulated users") })
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run persona-model validation cohort")
    try #require(action.detail.contains("requires at least 2"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == .promote)
  }

  @Test func tournamentDecisionAdvisorRequiresCurrentAlternativeProofBeforePromotion() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let index = makeTournamentPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includePersonaModelEvidence: true,
      includePersonaModelUserBreadth: true,
      includeCurrentAlternativeProof: false
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.personaModelCompletedRunCount == 2)
    try #require(readiness.personaModelDistinctPersonaCount == 2)
    try #require(readiness.personaModelCurrentAlternativePersonaCount == 0)
    try #require(readiness.recommendation == .keepGoing)
    try #require(readiness.rationale.contains { $0.contains("current-alternative proof") })
    try #require(
      ProductTournamentDecisionAdvisor.proposals(
        config: config,
        evidenceIndex: index
      ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run persona-model alternative challenge")
    try #require(action.detail.contains("current-alternative proof"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == .promote)
  }

  @Test func tournamentNextActionRunsTargetedPersonaModelRationaleSignalProof() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorSegment = config.userSegments[0]
    let buyer = config.userSegments[1]
    let operatorScenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == operatorSegment.id
      })
    let buyerScenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == buyer.id
      })
    let scores = ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 4
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "rationale-operator",
          experiment: experiment,
          config: config,
          personaID: operatorSegment.id,
          mode: .personaModel,
          endedAt: 200,
          verdict: .promising,
          scores: scores,
          currentAlternativeComparison: "Compared against the current workflow.",
          scenarioID: operatorScenario.id,
          personaActionRationales: [
            "turn 1 choose valid action compare_current_alternative: Needed proof against the manual workflow before switching."
          ]
        ),
        makeDecisionAdvisorRecord(
          id: "rationale-buyer",
          experiment: experiment,
          config: config,
          personaID: buyer.id,
          mode: .personaModel,
          endedAt: 300,
          verdict: .promising,
          scores: scores,
          currentAlternativeComparison: "Compared against the current workflow.",
          scenarioID: buyerScenario.id,
          personaActionRationales: [
            "turn 2 choose valid action reduce_switching_objection: Needed proof against the manual workflow before switching."
          ]
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let signal = try #require(
      TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .keepGoing)
    try #require(signal.rationale.contains("needed proof against the manual workflow"))
    try #require(signal.targetPersonaID == buyer.id)
    try #require(signal.targetScenarioID == buyerScenario.id)
    try #require(signal.targetCohortID == config.scenarioCohorts[0].id)
    try #require(signal.auditSummary.contains("resolve simulated-user rationale signal"))
    try #require(signal.auditSummary.contains("target Budget owner"))
    try #require(signal.auditSummary.contains("scenario \(buyerScenario.id)"))
    try #require(signal.auditSummary.contains("runs rationale-buyer"))
    try #require(action.kind == .runCohort)
    try #require(action.title == "Resolve simulated-user rationale signal")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetScenarioID == buyerScenario.id)
    try #require(action.detail.contains("Repeated simulated-user rationale"))
    try #require(action.detail.contains("before lift/cut"))
    try #require(step.canExecute)
    try #require(step.action.title == "Resolve simulated-user rationale signal")
    try #require(revisionBrief.title == "Revise product implementation for simulated-user rationale")
    try #require(revisionBrief.targetPersonaID == buyer.id)
    try #require(revisionBrief.targetScenarioID == buyerScenario.id)
    try #require(revisionBrief.implementationChange.contains("proof artifact"))
    try #require(revisionBrief.scenarioChange.contains("Budget owner"))
    try #require(revisionBrief.proofPlan.contains("current alternative"))
    try #require(digest.contains("Tournament automation rationale signals"))
    try #require(digest.contains("Tournament automation revision briefs"))
    try #require(digest.contains("action revise_product_contender"))
    try #require(digest.contains("implementation"))
    try #require(digest.contains("resolve_rationale_signal"))
    try #require(digest.contains("rationale-buyer"))
  }

  @Test func tournamentNextActionRetargetsStalledRationaleSignalAfterCycleAudit() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let experiment = config.tournamentExperiments[0]
    let operatorSegment = config.userSegments[0]
    let buyer = config.userSegments[1]
    let operatorScenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == operatorSegment.id
      })
    let buyerScenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == buyer.id
      })
    let scores = ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 4
    )
    let rationaleRecords = [
      makeDecisionAdvisorRecord(
        id: "rationale-operator",
        experiment: experiment,
        config: config,
        personaID: operatorSegment.id,
        mode: .personaModel,
        endedAt: 200,
        verdict: .promising,
        scores: scores,
        currentAlternativeComparison: "Compared against the current workflow.",
        scenarioID: operatorScenario.id,
        personaActionRationales: [
          "turn 1 choose valid action compare_current_alternative: Needed proof against the manual workflow before switching."
        ]
      ),
      makeDecisionAdvisorRecord(
        id: "rationale-buyer",
        experiment: experiment,
        config: config,
        personaID: buyer.id,
        mode: .personaModel,
        endedAt: 300,
        verdict: .promising,
        scores: scores,
        currentAlternativeComparison: "Compared against the current workflow.",
        scenarioID: buyerScenario.id,
        personaActionRationales: [
          "turn 2 choose valid action reduce_switching_objection: Needed proof against the manual workflow before switching."
        ]
      ),
    ]
    let index = ProductTournamentEvidenceIndex.build(records: rationaleRecords)

    let signal = try #require(
      TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-rationale",
        startedAt: 350,
        endedAt: 360,
        executedStepIDs: [step.id],
        experimentIDs: [experiment.id],
        messages: ["simulated-user rationale target ran 1 scenario(s): 1 completed, 0 needing review."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["rationale-buyer-rerun"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        personaRationaleSignalSummaries: [signal.auditSummary],
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage:
          "Tournament automation cycle ran 1 step(s). simulated-user rationale signal still present."
      )
    )

    let audit = try #require(
      TournamentAutomationCycleLearningAdvisor.stalledRationaleSignalAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: index
      ))
    let retarget = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let revisionStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(audit.id == "tournament-cycle-stalled-rationale")
    try #require(retarget.kind == .refineContender)
    try #require(retarget.title == "Retarget simulated-user rationale signal")
    try #require(retarget.detail.contains("tournament-cycle-stalled-rationale"))
    try #require(retarget.detail.contains("same simulated-user rationale target"))
    try #require(retarget.targetPersonaID == buyer.id)
    try #require(retarget.targetScenarioID == buyerScenario.id)
    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      )?.kind == .applyRevision)
    try #require(revisionStep.kind == .applyRevision)
    try #require(revisionStep.canExecute)
    try #require(revisionStep.id.contains("apply_revision"))
    try #require(revisionStep.targetScenarioID == buyerScenario.id)
    try #require(revisionBrief.title == "Retarget contender revision for simulated-user rationale")
    try #require(revisionBrief.implementationChange.contains("same rationale survived"))
    try #require(revisionBrief.proofPlan.contains("current alternative"))
    let revisionAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-applied-revision",
      startedAt: 370,
      endedAt: 380,
      executedStepIDs: [revisionStep.id],
      experimentIDs: [experiment.id],
      messages: ["Applied contender revision for \(experiment.title)."],
      maxSteps: 3,
      revisionBriefSummaries: [revisionBrief.auditSummary],
      stopReason: .repeatedStep,
      stopStepID: revisionStep.id,
      stopStepTitle: revisionStep.title,
      stopDetail: "Stopped before repeating Apply contender revision.",
      userMessage: "Tournament automation cycle ran 1 step(s). Contender revision applied."
    )
    let revisedConfig = config.recordingTournamentAutomationCycleAudit(revisionAudit)
    let appliedAudit = try #require(
      TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
        for: revisionBrief,
        experiment: experiment,
        config: revisedConfig,
        evidenceIndex: index
      ))
    let validationAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: revisedConfig,
        evidenceIndex: index
      ))
    let validationStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: revisedConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(appliedAudit.id == revisionAudit.id)
    try #require(validationAction.kind == .rerunCohort)
    try #require(validationAction.title == "Validate contender revision")
    try #require(validationAction.detail.contains(revisionAudit.id))
    try #require(validationAction.detail.contains("rerun the targeted persona-model scenario"))
    try #require(validationAction.targetPersonaID == buyer.id)
    try #require(validationAction.targetScenarioID == buyerScenario.id)
    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: revisedConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      )?.kind == .runCohort)
    try #require(validationStep.kind == .runCohort)
    try #require(validationStep.canExecute)
    try #require(validationStep.targetScenarioID == buyerScenario.id)
    let validationRecord = makeDecisionAdvisorRecord(
      id: "revision-validation-rerun",
      experiment: experiment,
      config: config,
      personaID: buyer.id,
      mode: .personaModel,
      endedAt: 390,
      verdict: .promising,
      scores: scores,
      currentAlternativeComparison: "Compared against the current workflow.",
      scenarioID: buyerScenario.id,
      personaActionRationales: [
        "Needed proof against the manual workflow before switching."
      ]
    )
    let validationIndex = ProductTournamentEvidenceIndex.build(
      records: rationaleRecords + [validationRecord]
    )
    let validationSignal = try #require(
      TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: revisedConfig,
        evidenceIndex: validationIndex
      ))
    let validationAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-validation-rationale",
      startedAt: 400,
      endedAt: 410,
      executedStepIDs: [validationStep.id],
      experimentIDs: [experiment.id],
      messages: ["Revision validation ran 1 scenario(s): 1 completed, 0 needing review."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["revision-validation-rerun"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      personaRationaleSignalSummaries: [validationSignal.auditSummary],
      stopReason: .noExecutableStep,
      stopDetail: "Stopped because no executable tournament automation step remains.",
      userMessage:
        "Tournament automation cycle ran 1 step(s). Contender revision validation still showed the rationale."
    )
    let validationConfig = revisedConfig.recordingTournamentAutomationCycleAudit(validationAudit)
    let postValidationAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: validationConfig,
        evidenceIndex: validationIndex
      ))
    let postValidationStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: validationConfig,
        evidenceIndex: validationIndex,
        isPersonaModelAvailable: true
      ))

    try #require(postValidationAction.kind == .refineContender)
    try #require(postValidationAction.title == "Retarget simulated-user rationale signal")
    try #require(postValidationAction.detail.contains(validationAudit.id))
    try #require(postValidationAction.targetScenarioID == buyerScenario.id)
    try #require(postValidationStep.kind == .applyRevision)
    try #require(postValidationStep.targetScenarioID == buyerScenario.id)
    let secondRevisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: validationConfig,
        evidenceIndex: validationIndex
      ))
    let secondRevisionAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-second-applied-revision",
      startedAt: 420,
      endedAt: 430,
      executedStepIDs: [postValidationStep.id],
      experimentIDs: [experiment.id],
      messages: ["Applied second contender revision for \(experiment.title)."],
      maxSteps: 3,
      revisionBriefSummaries: [secondRevisionBrief.auditSummary],
      stopReason: .repeatedStep,
      stopStepID: postValidationStep.id,
      stopStepTitle: postValidationStep.title,
      stopDetail: "Stopped before repeating Apply contender revision.",
      userMessage: "Tournament automation cycle ran 1 step(s). Second contender revision applied."
    )
    let secondRevisedConfig = validationConfig.recordingTournamentAutomationCycleAudit(
      secondRevisionAudit)
    let secondValidationAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: secondRevisedConfig,
        evidenceIndex: validationIndex
      ))
    let secondValidationStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: secondRevisedConfig,
        evidenceIndex: validationIndex,
        isPersonaModelAvailable: true
      ))

    try #require(secondValidationAction.kind == .rerunCohort)
    try #require(secondValidationAction.title == "Validate contender revision")
    try #require(secondValidationAction.detail.contains(secondRevisionAudit.id))
    try #require(secondValidationStep.kind == .runCohort)
    try #require(secondValidationStep.canExecute)
    try #require(secondValidationStep.targetScenarioID == buyerScenario.id)
    let secondValidationRecord = makeDecisionAdvisorRecord(
      id: "revision-validation-rerun-2",
      experiment: experiment,
      config: config,
      personaID: buyer.id,
      mode: .personaModel,
      endedAt: 440,
      verdict: .promising,
      scores: scores,
      currentAlternativeComparison: "Compared against the current workflow.",
      scenarioID: buyerScenario.id,
      personaActionRationales: [
        "Needed proof against the manual workflow before switching."
      ]
    )
    let secondValidationIndex = ProductTournamentEvidenceIndex.build(
      records: rationaleRecords + [validationRecord, secondValidationRecord]
    )
    let secondValidationSignal = try #require(
      TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: secondRevisedConfig,
        evidenceIndex: secondValidationIndex
      ))
    let secondValidationAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-second-validation-rationale",
      startedAt: 450,
      endedAt: 460,
      executedStepIDs: [secondValidationStep.id],
      experimentIDs: [experiment.id],
      messages: ["Second revision validation ran 1 scenario(s): 1 completed, 0 needing review."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["revision-validation-rerun-2"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      personaRationaleSignalSummaries: [secondValidationSignal.auditSummary],
      stopReason: .noExecutableStep,
      stopDetail: "Stopped because no executable tournament automation step remains.",
      userMessage:
        "Tournament automation cycle ran 1 step(s). Second contender revision validation still showed the rationale."
    )
    let fatiguedConfig = secondRevisedConfig.recordingTournamentAutomationCycleAudit(
      secondValidationAudit)
    let fatigueAudit = try #require(
      TournamentAutomationCycleLearningAdvisor.revisionFatigueAudit(
        for: action,
        experiment: experiment,
        config: fatiguedConfig,
        evidenceIndex: secondValidationIndex
      ))
    let fatigueAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: fatiguedConfig,
        evidenceIndex: secondValidationIndex
      ))
    let fatigueStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: fatiguedConfig,
        evidenceIndex: secondValidationIndex,
        isPersonaModelAvailable: true
      ))
    let fatigueSignal = TournamentAutomationExperimentRanker.signal(
      for: experiment,
      config: fatiguedConfig,
      evidenceIndex: secondValidationIndex
    )
    let fatigueDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: fatiguedConfig,
      evidenceIndex: secondValidationIndex
    )

    try #require(fatigueAudit.id == secondValidationAudit.id)
    try #require(fatigueAction.kind == .reviewDecision)
    try #require(fatigueAction.title == "Review revision fatigue")
    try #require(fatigueAction.detail.contains(secondValidationAudit.id))
    try #require(fatigueAction.detail.contains("same simulated-user rationale still survived"))
    try #require(fatigueAction.targetScenarioID == buyerScenario.id)
    try #require(fatigueAction.targetDecision == .narrow)
    try #require(fatigueStep.kind == .blocked)
    try #require(!fatigueStep.canExecute)
    try #require(fatigueStep.action.targetDecision == .narrow)
    try #require(
      fatigueStep.blockedReason
        == "Review the decision path before Tournament Automation changes state.")
    try #require(fatigueSignal.pressure == .reshape)
    try #require(fatigueSignal.targetDecision == .narrow)
    try #require(fatigueDigest.contains("Review revision fatigue"))
    try #require(fatigueDigest.contains("target_decision narrow"))
    try #require(digest.contains("Retarget simulated-user rationale signal"))
    try #require(digest.contains("Retarget contender revision for simulated-user rationale"))
    try #require(digest.contains("tournament-cycle-stalled-rationale"))
    try #require(digest.contains("rationale signals"))
  }

  @Test func revisionBriefDoesNotCompeteWithReadyTournamentDecision() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let index = makeTournamentPromotionEvidenceIndex(
      config: config,
      personaActionRationales: [
        "turn 1 choose valid action compare_current_alternative: Needed proof against the manual workflow before switching."
      ]
    )

    let signal = try #require(
      TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(signal.count == 3)
    try #require(action.kind == .applyDecision)
    try #require(action.title == "Apply tournament decision")
    try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ) == nil)
    try #require(!digest.contains("Tournament automation revision briefs"))
  }

  @Test func tournamentNextActionRefinesRepeatedRationaleSignalBeforeGenericNarrowing() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .narrow
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let operatorSegment = config.userSegments[0]
    let buyer = config.userSegments[1]
    let operatorScenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == operatorSegment.id
      })
    let buyerScenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == buyer.id
      })
    let scores = ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 3,
      switchingReadiness: 3,
      continuedUsePull: 3
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "csv-operator",
          experiment: experiment,
          config: config,
          personaID: operatorSegment.id,
          mode: .personaModel,
          endedAt: 200,
          verdict: .unclear,
          scores: scores,
          missingCapabilities: ["csv_import"],
          currentAlternativeComparison: "Compared against the current workflow.",
          scenarioID: operatorScenario.id,
          personaActionRationales: [
            "turn 1 choose valid action compare_current_alternative: Needed CSV import proof before trusting a switch."
          ]
        ),
        makeDecisionAdvisorRecord(
          id: "csv-buyer",
          experiment: experiment,
          config: config,
          personaID: buyer.id,
          mode: .personaModel,
          endedAt: 300,
          verdict: .unclear,
          scores: scores,
          missingCapabilities: ["csv_import"],
          currentAlternativeComparison: "Compared against the current workflow.",
          scenarioID: buyerScenario.id,
          personaActionRationales: [
            "turn 2 choose valid action reduce_switching_objection: Needed CSV import proof before trusting a switch."
          ]
        ),
      ]
    )

    let readiness = try #require(index.currentTournamentReadiness(for: experiment))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let rationaleSignal = try #require(
      TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let signal = TournamentAutomationExperimentRanker.signal(
      for: experiment,
      config: config,
      evidenceIndex: index
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .narrow)
    try #require(rationaleSignal.targetDecision == .narrow)
    try #require(rationaleSignal.auditSummary.contains("target_decision narrow"))
    try #require(action.kind == .refineContender)
    try #require(action.title == "Resolve simulated-user rationale signal")
    try #require(action.cohortID == nil)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetScenarioID == buyerScenario.id)
    try #require(action.targetDecision == .narrow)
    try #require(action.detail.contains("needed csv import proof"))
    try #require(action.detail.contains("Update the product implementation or scenario"))
    try #require(revisionBrief.targetDecision == .narrow)
    try #require(revisionBrief.auditSummary.contains("target_decision narrow"))
    try #require(signal.nextActionTitle == "Resolve simulated-user rationale signal")
    try #require(signal.targetDecision == .narrow)
    try #require(signal.pressure == .reshape)
    try #require(digest.contains("target_decision narrow"))
  }

  @Test func tournamentNextActionNamesMissingPersonaModelSegmentInSuggestedCohort() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    let workflow = try #require(config.currentWorkflows.first)
    let alternative = try #require(config.alternatives.first { $0.kind == .doNothing })
    let buyerScenarioID = "\(experiment.id)-buyer-persona-model-check"
    config.scenarios.append(
      ProductScenario(
        id: buyerScenarioID,
        experimentID: experiment.id,
        segmentID: buyer.id,
        currentWorkflowID: workflow.id,
        alternativeID: alternative.id,
        title: "Buyer persona-model check",
        task:
          "Use the product implementation to decide whether the evidence is good enough to sponsor.",
        successSignal: "The buyer can make a clear continue or stop decision.",
        targetCommitSha: "head-sha",
        createdAt: 20
      )
    )
    let cohort = config.scenarioCohorts[0]
    config.scenarioCohorts[0] = ProductScenarioCohort(
      id: cohort.id,
      title: cohort.title,
      experimentID: cohort.experimentID,
      scenarioIDs: cohort.scenarioIDs + [buyerScenarioID],
      enabled: cohort.enabled,
      tags: cohort.tags
    )
    let operatorScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID != buyer.id }
    )
    let scores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "operator-ai",
          experiment: experiment,
          config: config,
          personaID: operatorScenario.segmentID,
          mode: .personaModel,
          endedAt: 300,
          verdict: .strongPull,
          scores: scores
        ),
        makeDecisionAdvisorRecord(
          id: "buyer-model-free",
          experiment: experiment,
          config: config,
          personaID: buyer.id,
          endedAt: 200,
          verdict: .strongPull,
          scores: scores
        ),
        makeDecisionAdvisorRecord(
          id: "operator-model-free",
          experiment: experiment,
          config: config,
          personaID: operatorScenario.segmentID,
          endedAt: 100,
          verdict: .promising,
          scores: scores
        ),
      ]
    )

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(action.title == "Run persona-model validation cohort")
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetPersonaName == buyer.name)
    try #require(action.targetScenarioID == buyerScenarioID)
    try #require(action.targetDecision == .promote)
    try #require(action.detail.contains("Target simulated-user segment: \(buyer.name)"))
    try #require(action.detail.contains("via scenario `\(buyerScenarioID)`"))
    try #require(step.targetScenarioID == buyerScenarioID)
    try #require(step.cohortReadiness?.enabledScenarioCount == 1)
    try #require(step.id.contains(buyerScenarioID))
    try #require(step.detail.contains("targeting \(buyer.name)"))
  }

  @Test func tournamentNextActionRedirectsMissingPersonaModelSegmentToRunnableCohort() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let experiment = config.tournamentExperiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    config.scenarios.removeAll { $0.experimentID == experiment.id && $0.segmentID == buyer.id }
    for index in config.scenarioCohorts.indices
    where config.scenarioCohorts[index].experimentID == experiment.id {
      let cohort = config.scenarioCohorts[index]
      config.scenarioCohorts[index] = ProductScenarioCohort(
        id: cohort.id,
        title: cohort.title,
        experimentID: cohort.experimentID,
        scenarioIDs: cohort.scenarioIDs.filter { scenarioID in
          config.scenarios.contains { $0.id == scenarioID }
        },
        enabled: cohort.enabled,
        tags: cohort.tags
      )
    }
    let operatorScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID != buyer.id }
    )
    let buyerScenarioID = "\(experiment.id)-buyer-persona-model-check"
    let overflowOperatorScenarioID = "\(experiment.id)-operator-extra-check"
    config.scenarios.append(
      ProductScenario(
        id: overflowOperatorScenarioID,
        experimentID: experiment.id,
        segmentID: operatorScenario.segmentID,
        currentWorkflowID: operatorScenario.currentWorkflowID,
        alternativeID: operatorScenario.alternativeID,
        title: "Operator extra check",
        task: operatorScenario.task,
        successSignal: operatorScenario.successSignal,
        targetCommitSha: "head-sha",
        createdAt: 20
      )
    )
    config.scenarios.append(
      ProductScenario(
        id: buyerScenarioID,
        experimentID: experiment.id,
        segmentID: buyer.id,
        currentWorkflowID: operatorScenario.currentWorkflowID,
        alternativeID: config.alternatives.first { $0.kind == .doNothing }?.id,
        title: "Buyer persona-model check",
        task:
          "Use the product implementation to decide whether the evidence is good enough to sponsor.",
        successSignal: "The buyer can make a clear continue or stop decision.",
        targetCommitSha: "head-sha",
        createdAt: 21
      )
    )
    let selectedCohort = config.scenarioCohorts[0]
    config.scenarioCohorts[0] = ProductScenarioCohort(
      id: selectedCohort.id,
      title: selectedCohort.title,
      experimentID: selectedCohort.experimentID,
      scenarioIDs: selectedCohort.scenarioIDs + [overflowOperatorScenarioID],
      enabled: selectedCohort.enabled,
      tags: selectedCohort.tags
    )
    let buyerCohortID = "\(experiment.id)-buyer-persona-model-cohort"
    config.scenarioCohorts.append(
      ProductScenarioCohort(
        id: buyerCohortID,
        title: "Buyer persona-model cohort",
        experimentID: experiment.id,
        scenarioIDs: [buyerScenarioID],
        enabled: true,
        tags: ["persona-model"]
      )
    )
    let index = makeTournamentPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includePersonaModelEvidence: true,
      includePersonaModelUserBreadth: false
    )
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-broad-persona-model",
        startedAt: 340,
        endedAt: 350,
        executedStepIDs: ["\(experiment.id):run_cohort:\(buyerCohortID)"],
        experimentIDs: [experiment.id],
        messages: ["persona-model cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["broad-persona-model-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 4,
        endingProofDebtCount: 4,
        startingProofDebtSummary:
          "\(experiment.id): 3 completed run(s), 2 persona(s), 1 persona-model simulated user(s), 1 persona-model current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 3 completed run(s), 2 persona(s), 1 persona-model simulated user(s), 1 persona-model current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (4 -> 4)."
      )
    )

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(action.kind == .runCohort)
    try #require(action.cohortID == buyerCohortID)
    try #require(action.targetScenarioID == buyerScenarioID)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.detail.contains("cohort `\(buyerCohortID)`"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(
      TournamentAutomationCycleLearningAdvisor.stalledProofDebtAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: index
      ) == nil)
    try #require(step.canExecute)
    try #require(step.cohortID == buyerCohortID)
    try #require(step.targetScenarioID == buyerScenarioID)
    try #require(step.id.contains(buyerScenarioID))
  }

  @Test func tournamentNextActionBlocksPersonaModelCohortWhenMissingSegmentHasNoScenario() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let experiment = config.tournamentExperiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    config.scenarios.removeAll { $0.experimentID == experiment.id && $0.segmentID == buyer.id }
    for index in config.scenarioCohorts.indices
    where config.scenarioCohorts[index].experimentID == experiment.id {
      let cohort = config.scenarioCohorts[index]
      config.scenarioCohorts[index] = ProductScenarioCohort(
        id: cohort.id,
        title: cohort.title,
        experimentID: cohort.experimentID,
        scenarioIDs: cohort.scenarioIDs.filter { scenarioID in
          config.scenarios.contains { $0.id == scenarioID }
        },
        enabled: cohort.enabled,
        tags: cohort.tags
      )
    }
    let index = makeTournamentPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includePersonaModelEvidence: true,
      includePersonaModelUserBreadth: false
    )

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(action.kind == .refineContender)
    try #require(action.cohortID == nil)
    try #require(action.targetScenarioID == nil)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetDecision == .promote)
    try #require(action.detail.contains("does not cover a runnable simulated-user target"))
    try #require(action.detail.contains("add an enabled scenario"))
    try #require(proofTarget.label == "add or enable persona-model validation proof")
    try #require(proofTarget.targetDecision == .promote)
    try #require(digest.contains("target add or enable persona-model validation proof"))
    try #require(!step.canExecute)
    try #require(step.kind == .blocked)
    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ) == nil)
  }

  @Test func tournamentAutomationBlocksRequiredPersonaModelCohortWhenUnavailable() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let index = makeTournamentPromotionEvidenceIndex(
      config: config,
      includePersonaModelEvidence: false
    )

    let blocked = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: false
      ))
    let blockedPlan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: index,
      isPersonaModelAvailable: false
    )
    let executable = TournamentAutomationPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: index,
      isPersonaModelAvailable: false
    )
    let available = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let availablePlan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: index,
      isPersonaModelAvailable: true
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(executable == nil)
    try #require(!blocked.canExecute)
    try #require(blocked.action.requiredSimulationMode == .personaModel)
    try #require(blocked.decisionIntentSummary == "decision target promote")
    try #require(blocked.queueTitle.contains("decision target promote"))
    try #require(blocked.blockedReason?.contains("Foundation Models") == true)
    try #require(blockedPlan.queueSummary.contains("Blocked:"))
    try #require(blockedPlan.queueSummary.contains("decision target promote"))
    try #require(available.canExecute)
    try #require(available.action.requiredSimulationMode == .personaModel)
    try #require(available.decisionIntentSummary == "decision target promote")
    try #require(availablePlan.queueSummary.contains("decision target promote"))
    try #require(digest.contains("decision target promote"))
  }

  @Test func tournamentAutomationProofTargetsFollowRoundTwoImplementationTarget() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    try #require(config.tournamentExperiments.indices.contains(1))
    for index in config.tournamentExperiments.indices.prefix(2) {
      config.tournamentExperiments[index].decision = .keepGoing
      config.tournamentExperiments[index].baseSha = "base-\(index)"
      config.tournamentExperiments[index].currentSha = "head-\(index)"
    }
    let implementationTarget = try activateRoundTwoImplementationTarget(in: &config)
    let targetExperiment = try #require(
      config.tournamentExperiments.first { $0.id == implementationTarget.experimentID }
    )
    let siblingExperiment = config.tournamentExperiments[1]
    let evidenceIndex = makeProofDebtEvidenceIndex(
      tournamentExperiments: [targetExperiment, siblingExperiment],
      config: config
    )

    let targets = TournamentAutomationProofTargetAdvisor.targets(
      config: config,
      evidenceIndex: evidenceIndex
    )
    let target = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: targetExperiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    )

    try #require(target.experimentID == targetExperiment.id)
    try #require(targets.map(\.experimentID) == [targetExperiment.id])
    try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: siblingExperiment,
        config: config,
        evidenceIndex: evidenceIndex
      ) == nil
    )
  }

  @Test func tournamentAutomationOmitsSiblingEvidenceDuringRoundTwoTarget() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    try #require(config.tournamentExperiments.indices.contains(1))
    for index in config.tournamentExperiments.indices.prefix(2) {
      config.tournamentExperiments[index].decision = .keepGoing
      config.tournamentExperiments[index].baseSha = "base-\(index)"
      config.tournamentExperiments[index].currentSha = "head-\(index)"
    }
    let implementationTarget = try activateRoundTwoImplementationTarget(in: &config)
    let siblingExperiment = config.tournamentExperiments[1]

    let steps = TournamentAutomationPlanner.steps(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: true
    )
    let nextStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty,
        isPersonaModelAvailable: true
      )
    )
    let plan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: true
    )

    try #require(steps.map(\.experimentID) == [implementationTarget.experimentID])
    try #require(!steps.contains { $0.experimentID == siblingExperiment.id })
    try #require(nextStep.experimentID == implementationTarget.experimentID)
    try #require(nextStep.kind == .runCohort)
    try #require(plan.executableSteps.map(\.experimentID) == [implementationTarget.experimentID])
    try #require(plan.blockedSteps.isEmpty)
  }

  @Test func tournamentAutomationRankerPrioritizesActionableTournamentPressure() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    try #require(config.tournamentExperiments.count >= 2)
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    config.tournamentExperiments[1].decision = .keepGoing
    config.tournamentExperiments[1].baseSha = "base-sha"
    config.tournamentExperiments[1].currentSha = "head-sha"
    let index = makeTournamentPromotionEvidenceIndex(config: config)

    let ranked = TournamentAutomationExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: index
    )
    let firstSignal = TournamentAutomationExperimentRanker.signal(
      for: config.tournamentExperiments[0],
      config: config,
      evidenceIndex: index
    )
    let secondSignal = TournamentAutomationExperimentRanker.signal(
      for: config.tournamentExperiments[1],
      config: config,
      evidenceIndex: index
    )

    try #require(ranked.first?.id == config.tournamentExperiments[0].id)
    try #require(firstSignal.nextActionKind == .applyDecision)
    try #require(firstSignal.readinessRecommendation == .promote)
    try #require(firstSignal.pressure == .lift)
    try #require(firstSignal.pressureLabel == "Lift pressure")
    try #require(firstSignal.readinessLabel.contains("Promote"))
    try #require(firstSignal.urgencyScore > secondSignal.urgencyScore)
    try #require(secondSignal.nextActionKind == .runCohort)
    try #require(secondSignal.pressure == .learn)
    try #require(secondSignal.readinessLabel == "No current tournament evidence")
  }

  @Test func tournamentAutomationRankerSurfacesTournamentProofDebt() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let index = makeTournamentPromotionEvidenceIndex(
      config: config,
      includePersonaModelEvidence: false
    )

    let signal = TournamentAutomationExperimentRanker.signal(
      for: config.tournamentExperiments[0],
      config: config,
      evidenceIndex: index
    )
    let readiness = try #require(
      index.currentTournamentReadiness(for: config.tournamentExperiments[0]))

    try #require(!readiness.proofDebt.isClear)
    try #require(readiness.proofDebt.personaModelSimulatedUserDeficit == 2)
    try #require(readiness.proofDebt.personaModelCurrentAlternativeDeficit == 2)
    try #require(readiness.rationale.contains { $0.contains("Proof debt") })
    try #require(signal.proofDebtCount == readiness.proofDebt.blockingDebtCount)
    try #require(signal.proofDebtSummary?.contains("persona-model simulated user") == true)
    try #require(signal.nextActionKind == .runCohort)
    try #require(signal.pressure == .lift)
    try #require(signal.targetDecision == .promote)
  }

  @Test func tournamentAutomationChoosesExecutableTournamentDecision() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let index = makeTournamentPromotionEvidenceIndex(config: config)

    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))

    try #require(step.canExecute)
    try #require(step.kind == .applyDecision)
    try #require(step.action.kind == .applyDecision)
    try #require(step.experimentID == config.tournamentExperiments[0].id)
    try #require(step.detail.contains(config.tournamentExperiments[0].title))
  }

  @Test func tournamentAutomationRunsRunnableCohortWhenEvidenceIsMissing() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    try completePlanOnlyRound(in: &config)

    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    try #require(step.canExecute)
    try #require(step.kind == .runCohort)
    try #require(step.action.kind == .runCohort)
    try #require(step.cohortID == config.scenarioCohorts[0].id)
    try #require(step.cohortReadiness?.canRun == true)
  }

  @Test func tournamentAutomationSelectsPersonaModelCohortsWhenAvailable() throws {
    try #require(
      TournamentAutomationPlanner.cohortSimulationMode(isPersonaModelAvailable: true)
        == .personaModel
    )
    try #require(
      TournamentAutomationPlanner.cohortSimulationMode(isPersonaModelAvailable: false)
        == .modelFree
    )
    try #require(
      ProductTournamentSimulationMode.personaModel.tournamentAutomationLabel == "Persona-model")
    try #require(
      ProductTournamentSimulationMode.modelFree.tournamentAutomationLabel == "Model-free")
  }

  @Test func tournamentAutomationBlocksRecentlyFailedStep() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    try completePlanOnlyRound(in: &config)
    let runnable = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-failed-step",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [],
        experimentIDs: [runnable.experimentID],
        messages: [],
        maxSteps: 3,
        stopReason: .executionFailed,
        stopStepID: runnable.id,
        stopStepTitle: runnable.title,
        stopDetail: "Stopped because Run evidence cohort failed: contract missing.",
        userMessage:
          "Tournament automation cycle ran no steps. Stopped because Run evidence cohort failed: contract missing."
      )
    )

    let step = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: .empty
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: config.tournamentExperiments[0],
        config: config,
        evidenceIndex: .empty
      ))
    let plan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty
    )
    let signal = TournamentAutomationExperimentRanker.signal(
      for: config.tournamentExperiments[0],
      config: config,
      evidenceIndex: .empty
    )

    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ) == nil)
    try #require(!step.canExecute)
    try #require(step.action.kind == .repairFailures)
    try #require(action.kind == .repairFailures)
    try #require(action.title == "Repair tournament automation failure")
    try #require(action.detail.contains("tournament-cycle-failed-step"))
    try #require(action.detail.contains("contract missing"))
    try #require(step.blockedReason?.contains("tournament-cycle-failed-step") == true)
    try #require(step.blockedReason?.contains("contract missing") == true)
    try #require(signal.pressure == .repair)
    try #require(signal.nextActionKind == .repairFailures)
    try #require(!plan.canRun)
    try #require(plan.nextBlockedStep?.action.kind == .repairFailures)
  }

  @Test func tournamentAutomationClearsFailureBlockAfterCompletedEvidence() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    try completePlanOnlyRound(in: &config)
    let runnable = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-failed-step",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [],
        experimentIDs: [runnable.experimentID],
        messages: [],
        maxSteps: 3,
        stopReason: .executionFailed,
        stopStepID: runnable.id,
        stopStepTitle: runnable.title,
        stopDetail: "Stopped because Run evidence cohort failed: contract missing.",
        userMessage:
          "Tournament automation cycle ran no steps. Stopped because Run evidence cohort failed: contract missing."
      )
    )
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "repair-run",
          experiment: config.tournamentExperiments[0],
          config: config,
          personaID: "operator",
          endedAt: 120,
          verdict: .promising,
          scores: ProductTournamentEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])

    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))

    try #require(step.id == runnable.id)
    try #require(step.canExecute)
    try #require(step.blockedReason == nil)
  }

  @Test func tournamentAutomationRetargetsBroadCohortWhenProofDebtStalls() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let experiment = config.tournamentExperiments[0]
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "first-pass",
          experiment: experiment,
          config: config,
          personaID: config.userSegments[0].id,
          endedAt: 30,
          verdict: .promising,
          scores: ProductTournamentEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])
    let broadStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    try #require(broadStep.action.kind == .runCohort)
    try #require(broadStep.action.targetScenarioID == nil)
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-proof",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [broadStep.id],
        experimentIDs: [experiment.id],
        messages: [
          "Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."
        ],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["first-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 6,
        endingProofDebtCount: 6,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (6 -> 6)."
      )
    )

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let audit = try #require(
      TournamentAutomationCycleLearningAdvisor.stalledProofDebtAudit(
        for: broadStep.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ))
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )

    try #require(audit.id == "tournament-cycle-stalled-proof")
    try #require(action.kind == .runCohort)
    try #require(action.title == "Retarget persona-model proof debt")
    try #require(action.detail.contains("tournament-cycle-stalled-proof"))
    try #require(action.detail.contains("without reducing proof debt"))
    try #require(action.detail.contains("targeted persona-model scenario"))
    try #require(action.detail.contains("Remaining proof debt"))
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetDecision == nil)
    let targetScenarioID = try #require(action.targetScenarioID)
    try #require(proofTarget.label == "run targeted persona-model simulated-user proof")
    try #require(proofTarget.displayTitle == "run targeted persona-model simulated-user proof")
    try #require(proofTarget.displaySubtitle.contains("score 48/100"))
    try #require(proofTarget.displaySubtitle.contains("target Budget owner"))
    try #require(proofTarget.displayDetail.contains("Debt:"))
    try #require(proofTarget.displayDetail.contains("Next: Retarget persona-model proof debt"))
    try #require(proofTarget.nextActionTitle == "Retarget persona-model proof debt")
    try #require(proofTarget.targetDecision == nil)
    try #require(proofTarget.targetScenarioID == targetScenarioID)
    try #require(proofTarget.targetPersonaName == "Budget owner")
    try #require(proofTarget.requiredSimulationMode == .personaModel)
    let executable = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ))
    try #require(executable.canExecute)
    try #require(step.canExecute)
    try #require(step.kind == .runCohort)
    try #require(step.action.kind == .runCohort)
    try #require(step.action.targetDecision == nil)
    try #require(step.targetScenarioID == targetScenarioID)
    try #require(digest.contains("Tournament automation proof targets"))
    try #require(digest.contains("target run targeted persona-model simulated-user proof"))
    try #require(digest.contains("Retarget persona-model proof debt"))
    try #require(digest.contains("tournament-cycle-stalled-proof"))
    try #require(digest.contains("target_scenario \(targetScenarioID)"))
    try #require(digest.contains("target_name Budget owner"))
    try #require(digest.contains("required_mode persona_model"))
    try #require(digest.contains("proof debt 6 -> 6 (0)"))

    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-target",
        startedAt: 120,
        endedAt: 130,
        executedStepIDs: [step.id],
        experimentIDs: [experiment.id],
        messages: ["persona-model target ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["buyer-persona-model-stalled"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 6,
        endingProofDebtCount: 6,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        proofTargetSummaries: [proofTarget.auditSummary],
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (6 -> 6)."
      )
    )

    let stalledTargetAudit = try #require(
      TournamentAutomationCycleLearningAdvisor.stalledProofTargetAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let blockedStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ))

    try #require(stalledTargetAudit.id == "tournament-cycle-stalled-target")
    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ) == nil)
    try #require(!blockedStep.canExecute)
    try #require(blockedStep.targetScenarioID == targetScenarioID)
    try #require(blockedStep.blockedReason?.contains("already attempted this proof target") == true)
    try #require(blockedStep.blockedReason?.contains("change the scenario") == true)
  }

  @Test func tournamentAutomationRetargetsStalledActedProofGroup() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let experiment = config.tournamentExperiments[0]
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "first-pass",
          experiment: experiment,
          config: config,
          personaID: config.userSegments[0].id,
          endedAt: 30,
          verdict: .promising,
          scores: ProductTournamentEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])
    let broadStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-broad-proof",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [broadStep.id],
        experimentIDs: [experiment.id],
        messages: [
          "Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."
        ],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["first-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 6,
        endingProofDebtCount: 6,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (6 -> 6)."
      )
    )

    let proofRunAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let targetScenarioID = try #require(proofRunAction.targetScenarioID)
    let scoreboardItem = try #require(
      TournamentAutomationProofTargetScoreboard.items(
        config: config,
        evidenceIndex: evidenceIndex,
        limit: Int.max,
        isPersonaModelAvailable: true
      )
      .first { item in
        item.rows.contains { $0.targetScenarioID == targetScenarioID }
      })
    let row = try #require(
      scoreboardItem.rows.first { $0.targetScenarioID == targetScenarioID })
    let group = try #require(
      scoreboardItem.readinessGroup(containingRowSelectionID: row.selectionID))

    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-acted-group",
        startedAt: 120,
        endedAt: 130,
        executedStepIDs: [
          "\(experiment.id):\(ProductTournamentNextActionKind.runCohort.rawValue):\(targetScenarioID)"
        ],
        experimentIDs: [experiment.id],
        messages: ["persona-model proof group ran 1 scenario and left proof debt unchanged."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["buyer-persona-model-stalled"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 6,
        endingProofDebtCount: 6,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 persona-model simulated user(s), 0 persona-model current-alternative proof(s)",
        proofTargetSummaries: [proofTarget.auditSummary],
        actedProofPressureGroupSummaries: [
          group.actionAuditSummary(anchorRow: row)
        ],
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (6 -> 6)."
      )
    )

    let stalledGroup = try #require(
      TournamentAutomationCycleLearningAdvisor.stalledActedPressureGroupAudit(
        for: proofRunAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let retarget = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let nextStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )

    try #require(stalledGroup.audit.id == "tournament-cycle-stalled-acted-group")
    try #require(stalledGroup.outcome.isStalledProofRun)
    try #require(stalledGroup.outcome.summary.contains("stalled in Proof runs"))
    try #require(retarget.kind == .refineContender)
    try #require(retarget.title == "Retarget stalled proof group")
    try #require(retarget.detail.contains("tournament-cycle-stalled-acted-group"))
    try #require(retarget.detail.contains("stalled in Proof runs"))
    try #require(retarget.targetScenarioID == targetScenarioID)
    try #require(nextStep.action.title == "Retarget stalled proof group")
    try #require(nextStep.action.kind == .refineContender)
    try #require(digest.contains("acted group outcomes"))
    try #require(digest.contains("stalled in Proof runs"))
  }

  @Test func tournamentAutomationFallsBackWhenStalledProofDebtHasNoPersonaModelTarget() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    for index in config.tournamentExperiments.indices.dropFirst() {
      config.tournamentExperiments[index].decision = .promoted
    }
    let experiment = config.tournamentExperiments[0]
    let operatorID = config.userSegments[0].id
    let buyer = try #require(config.userSegments.dropFirst().first)
    config.scenarios.removeAll {
      $0.experimentID == experiment.id && $0.segmentID != operatorID
    }
    for index in config.scenarioCohorts.indices
    where config.scenarioCohorts[index].experimentID == experiment.id {
      let cohort = config.scenarioCohorts[index]
      config.scenarioCohorts[index] = ProductScenarioCohort(
        id: cohort.id,
        title: cohort.title,
        experimentID: cohort.experimentID,
        scenarioIDs: cohort.scenarioIDs.filter { scenarioID in
          config.scenarios.contains { $0.id == scenarioID }
        },
        enabled: cohort.enabled,
        tags: cohort.tags
      )
    }
    let evidenceIndex = ProductTournamentEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "operator-persona-model-pass",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 30,
          verdict: .promising,
          scores: ProductTournamentEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])
    let broadStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    config = config.recordingTournamentAutomationCycleAudit(
      TournamentAutomationCycleAudit(
        id: "tournament-cycle-stalled-no-target",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [broadStep.id],
        experimentIDs: [experiment.id],
        messages: ["persona-model cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["operator-persona-model-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 4,
        endingProofDebtCount: 4,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 1 persona-model simulated user(s), 1 persona-model current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 1 persona-model simulated user(s), 1 persona-model current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable tournament automation step remains.",
        userMessage: "Tournament automation cycle ran 1 step(s). Proof debt held steady (4 -> 4)."
      )
    )

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let proofTarget = try #require(
      TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )

    try #require(action.kind == .refineContender)
    try #require(action.title == "Retarget persona-model proof debt")
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetScenarioID == nil)
    try #require(action.targetDecision == nil)
    try #require(action.detail.contains("tournament-cycle-stalled-no-target"))
    try #require(action.detail.contains("does not cover a runnable simulated-user target"))
    try #require(action.detail.contains("add an enabled scenario"))
    try #require(proofTarget.label == "add or enable runnable persona-model proof")
    try #require(proofTarget.displayTitle == "add or enable runnable persona-model proof")
    try #require(proofTarget.displaySubtitle.contains("target Budget owner"))
    try #require(proofTarget.displayDetail.contains("Persona: Budget owner"))
    try #require(proofTarget.nextActionTitle == "Retarget persona-model proof debt")
    try #require(proofTarget.targetDecision == nil)
    try #require(proofTarget.targetPersonaID == buyer.id)
    try #require(proofTarget.targetPersonaName == "Budget owner")
    try #require(proofTarget.targetScenarioID == nil)
    try #require(proofTarget.requiredSimulationMode == .personaModel)
    try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ) == nil)
    try #require(step.kind == .blocked)
    try #require(step.action.kind == .refineContender)
    try #require(step.action.targetDecision == nil)
    try #require(digest.contains("Tournament automation proof targets"))
    try #require(digest.contains("target add or enable runnable persona-model proof"))
    try #require(digest.contains("target_persona \(buyer.id)"))
    try #require(digest.contains("target_name Budget owner"))
    try #require(digest.contains("required_mode persona_model"))
  }

  @Test func tournamentAutomationCyclePlanCapsExecutableSteps() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    for index in config.tournamentExperiments.indices {
      config.tournamentExperiments[index].decision = .keepGoing
      config.tournamentExperiments[index].baseSha = "base-\(index)"
      config.tournamentExperiments[index].currentSha = "head-\(index)"
    }
    try completePlanOnlyRound(in: &config)

    let plan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty,
      maxSteps: 1
    )

    try #require(plan.canRun)
    try #require(plan.executableSteps.count == 1)
    try #require(plan.capped)
    try #require(plan.summary.contains("capped at 1"))
    try #require(plan.executableSteps[0].kind == .runCohort)
    try #require(plan.queueSummary.contains(plan.executableSteps[0].experimentTitle))
    try #require(plan.queueSummary.contains("Run evidence cohort"))
    try #require(plan.queueSummary.contains("plus more queued"))
  }

  @Test func tournamentAutomationCyclePlanReportsBlockedStep() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    try completePlanOnlyRound(in: &config)

    let plan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty
    )

    try #require(!plan.canRun)
    try #require(plan.executableSteps.isEmpty)
    let blocked = try #require(plan.nextBlockedStep)
    try #require(blocked.kind == .runCohort)
    try #require(blocked.blockedReason?.contains("target commit") == true)
    try #require(plan.summary.contains("No executable tournament automation steps"))
    try #require(plan.queueSummary.contains("Blocked:"))
    try #require(plan.queueSummary.contains("target commit"))
  }

  @Test func tournamentAutomationCycleOutcomeReportsRepeatStop() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    try completePlanOnlyRound(in: &config)
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      messages: ["Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
      maxSteps: 3,
      stopReason: .repeatedStep(stepID: step.id, title: step.title)
    )

    try #require(outcome.userMessage.contains("Tournament automation cycle ran 1 step(s)."))
    try #require(outcome.userMessage.contains("0 tournament decision(s) applied"))
    try #require(outcome.userMessage.contains("1 evidence step(s)"))
    try #require(outcome.userMessage.contains("Model-free cohort ran 1 scenario(s)"))
    try #require(outcome.userMessage.contains("Stopped before repeating Run evidence cohort."))
  }

  @Test func tournamentAutomationCycleOutcomeSeparatesTargetedProofFromAppliedDecisions()
    throws
  {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let index = makeTournamentPromotionEvidenceIndex(
      config: config,
      includePersonaModelEvidence: false
    )
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      messages: ["persona-model validation cohort ran 1 scenario(s): 1 completed."],
      maxSteps: 3,
      stopReason: .noExecutableStep,
      evidenceRunIDs: ["ai-validation-run"],
      completedEvidenceRunCount: 1,
      actedProofPressureGroupSummaries: [
        "pressure_group Proof runs; anchor round-1:\(step.experimentID):buyer; contender Continue; status More proof; next Ready: Run Plan Proof"
      ]
    )
    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 330),
      endedAt: Date(timeIntervalSince1970: 335)
    )

    try #require(step.action.kind == .runCohort)
    try #require(step.action.targetDecision == .promote)
    try #require(outcome.appliedDecisionCount == 0)
    try #require(outcome.promotedDecisionCount == 0)
    try #require(outcome.killedDecisionCount == 0)
    try #require(outcome.targetedPromoteProofCount == 1)
    try #require(outcome.targetedKillProofCount == 0)
    try #require(outcome.evidenceRunStepCount == 1)
    try #require(
      outcome.userMessage.contains("0 tournament decision(s) applied (0 promote, 0 kill)"))
    try #require(outcome.userMessage.contains("targeted proof 1 promote, 0 kill"))
    try #require(outcome.userMessage.contains("1 evidence step(s)"))
    try #require(outcome.userMessage.contains("Acted pressure groups:"))
    try #require(outcome.userMessage.contains("pressure_group Proof runs"))
    try #require(audit.appliedDecisionCount == 0)
    try #require(audit.promotedDecisionCount == 0)
    try #require(audit.killedDecisionCount == 0)
    try #require(audit.targetedPromoteProofCount == 1)
    try #require(audit.targetedKillProofCount == 0)
    try #require(audit.evidenceRunStepCount == 1)
    try #require(audit.actedProofPressureGroupSummaries.count == 1)
    try #require(audit.actedProofPressureGroupSummaries[0].contains("pressure_group Proof runs"))
    try #require(audit.userMessage.contains("targeted proof 1 promote, 0 kill"))
    try #require(audit.userMessage.contains("Acted pressure groups:"))
    try #require(audit.summary.contains("targeted proof 1 promote, 0 kill"))
    try #require(audit.summary.contains("pressure groups"))
    try #require(audit.summary.contains("pressure_group Proof runs"))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config.recordingTournamentAutomationCycleAudit(audit),
      evidenceIndex: index
    )
    try #require(digest.contains("targeted proof 1 promote, 0 kill"))
    try #require(digest.contains("acted pressure groups"))
    try #require(digest.contains("pressure_group Proof runs"))
    try #require(digest.contains("acted group outcomes"))
    try #require(digest.contains("cleared from proof scoreboard"))
  }

  @Test func tournamentAutomationCycleOutcomeCountsPrepareWorktreeSeparatelyFromEvidence() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    try completePlanOnlyRound(in: &config)
    let experiment = config.tournamentExperiments[0]
    let cohortIndex = try #require(
      config.scenarioCohorts.firstIndex { $0.experimentID == experiment.id }
    )
    let cohort = config.scenarioCohorts[cohortIndex]
    config.scenarioCohorts[cohortIndex] = ProductScenarioCohort(
      id: cohort.id,
      title: cohort.title,
      experimentID: cohort.experimentID,
      scenarioIDs: cohort.scenarioIDs,
      enabled: cohort.enabled,
      tags: ["discover", "candidate-implementation-track"]
    )
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      messages: [
        "Prepared implementation worktree for \(step.experimentTitle) at head-sha on \(experiment.branchName)."
      ],
      maxSteps: 3,
      stopReason: .reachedStepLimit
    )
    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 340),
      endedAt: Date(timeIntervalSince1970: 345)
    )

    try #require(step.kind == .prepareWorktree)
    try #require(outcome.prepareWorktreeStepCount == 1)
    try #require(outcome.evidenceRunStepCount == 0)
    try #require(outcome.userMessage.contains("1 worktree prepare step(s)"))
    try #require(outcome.userMessage.contains("0 evidence step(s)"))
    try #require(audit.prepareWorktreeStepCount == 1)
    try #require(audit.evidenceRunStepCount == 0)
    try #require(audit.summary.contains("worktree prep 1 step(s)"))
    try #require(audit.summary.contains("evidence 0 step(s)"))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config.recordingTournamentAutomationCycleAudit(audit),
      evidenceIndex: .empty
    )
    try #require(digest.contains("worktree prep 1 step(s)"))
    try #require(digest.contains("evidence 0 step(s)"))
    try #require(digest.contains("Recent tournament automation worktree preparation"))
    try #require(digest.contains("prepare_worktree_steps 1"))
    try #require(digest.contains("current_evidence_runs 0"))
  }

  @Test func tournamentAutomationWorkbenchFactsSeparatePrepareAndEvidenceHistory() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    try completePlanOnlyRound(in: &config)
    let experiment = config.tournamentExperiments[0]
    let prepareAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-prepare",
      startedAt: 340,
      endedAt: 345,
      executedStepIDs: [
        "\(experiment.id):\(TournamentAutomationStepKind.prepareWorktree.rawValue):\(experiment.branchName)"
      ],
      experimentIDs: [experiment.id],
      messages: [
        "Prepared implementation worktree for \(experiment.title) at head-sha on \(experiment.branchName)."
      ],
      maxSteps: 3,
      prepareWorktreeStepCount: 1,
      stopReason: .reachedStepLimit,
      stopStepTitle: "Prepare implementation worktree",
      stopDetail: "Prepared branch before simulated-user evidence.",
      userMessage: "Tournament automation cycle ran 1 step(s)."
    )
    var preparedState = config
    preparedState.tournamentExperiments[0].currentSha = "head-sha"
    for index in preparedState.scenarios.indices
      where preparedState.scenarios[index].experimentID == experiment.id
    {
      preparedState.scenarios[index].targetCommitSha = "head-sha"
    }
    let preparedConfig = preparedState.recordingTournamentAutomationCycleAudit(prepareAudit)
    let queuedEvidenceStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: preparedConfig,
        evidenceIndex: .empty
      ))
    let preparedFacts = try #require(
      TournamentAutomationCycleWorkbenchFacts.latest(
        config: preparedConfig,
        evidenceIndex: .empty,
        currentStep: queuedEvidenceStep,
        isPersonaModelAvailable: false
      ))

    try #require(queuedEvidenceStep.kind == .runCohort)
    let queuedCohortID = try #require(queuedEvidenceStep.cohortID)
    try #require(preparedFacts.latestCycleSummary.contains("worktree prep 1 step(s)"))
    try #require(
      preparedFacts.latestPreparationSummary
        == "1 prepare step(s), experiments \(experiment.id), current evidence runs 0")
    try #require(preparedFacts.latestEvidenceSummary == "none recorded")
    try #require(
      preparedFacts.latestPreparationHelp?.contains(
        "Prepared branch before simulated-user evidence.") == true)
    try #require(
      preparedFacts.postPreparationEvidenceSummary
        == "first model-free simulated-user cohort `\(queuedCohortID)`; 2 enabled scenario(s)")
    try #require(
      preparedFacts.postPreparationEvidenceHelp?.contains(
        "current queue is Run evidence cohort") == true)

    let evidenceAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-evidence",
      startedAt: 350,
      endedAt: 355,
      executedStepIDs: [
        "\(experiment.id):\(TournamentAutomationStepKind.runCohort.rawValue):cohort"
      ],
      experimentIDs: [experiment.id],
      messages: ["Persona-model cohort ran 1 scenario(s): 1 completed."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["promote-a"],
      completedEvidenceRunCount: 1,
      actedProofPressureGroupSummaries: [
        "pressure_group Proof runs; anchor round-1:\(experiment.id):buyer; contender Continue; status More proof; next Ready: Run Plan Proof"
      ],
      stopReason: .noExecutableStep,
      stopDetail: "No executable tournament automation step remains.",
      userMessage: "Tournament automation cycle ran 1 step(s)."
    )
    let evidenceIndex = makeTournamentPromotionEvidenceIndex(config: preparedState)
    let evidenceFacts = try #require(
      TournamentAutomationCycleWorkbenchFacts.latest(
        config: preparedConfig.recordingTournamentAutomationCycleAudit(evidenceAudit),
        evidenceIndex: evidenceIndex,
        currentStep: queuedEvidenceStep,
        isPersonaModelAvailable: false
      ))

    try #require(evidenceFacts.latestCycleSummary.contains("evidence 1 step(s)"))
    try #require(
      evidenceFacts.latestPreparationSummary
        == "1 prepare step(s), experiments \(experiment.id), current evidence runs 3")
    try #require(
      evidenceFacts.latestEvidenceSummary
        == "1 evidence step(s), 1 completed, 0 needing review, 0 skipped; runs promote-a")
    try #require(
      evidenceFacts.latestEvidenceHelp?.contains(
        "No executable tournament automation step remains.") == true)
    try #require(
      evidenceFacts.latestActedPressureGroupSummary
        == "Proof runs; Continue; More proof; next Ready: Run Plan Proof")
    try #require(
      evidenceFacts.latestActedPressureGroupHelp?.contains("audit tournament-cycle-evidence")
        == true)
    try #require(
      evidenceFacts.latestActedPressureGroupHelp?.contains("anchor round-1:\(experiment.id):buyer")
        == true)
    try #require(
      evidenceFacts.latestActedPressureGroupOutcomeSummary
        == "cleared from proof scoreboard")
    try #require(
      evidenceFacts.latestActedPressureGroupOutcomeHelp?.contains(
        "outcome cleared from proof scoreboard") == true)
    try #require(evidenceFacts.postPreparationEvidenceSummary == nil)
  }

  @Test func tournamentAutomationCycleOutcomeCountsLiftAndCutDecisions() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let index = makeTournamentPromotionEvidenceIndex(config: config)
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))
    let candidate = try #require(
      TournamentAutomationDecisionCandidateAdvisor.candidates(
        config: config,
        evidenceIndex: index
      ).first { $0.experimentID == step.experimentID }
    )

    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      messages: ["Applied tournament advice for \(step.experimentTitle)."],
      maxSteps: 3,
      stopReason: .noExecutableStep,
      decisionCandidateSummaries: [candidate.auditSummary],
      personaRationaleSignalSummaries: [
        "needed import proof before switching; count 2; experiments \(step.experimentID); runs promote-a, promote-b"
      ]
    )
    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 300),
      endedAt: Date(timeIntervalSince1970: 305)
    )

    try #require(step.action.targetDecision == .promote)
    try #require(outcome.appliedDecisionCount == 1)
    try #require(outcome.promotedDecisionCount == 1)
    try #require(outcome.killedDecisionCount == 0)
    try #require(outcome.evidenceRunStepCount == 0)
    try #require(
      outcome.userMessage.contains("1 tournament decision(s) applied (1 promote, 0 kill)"))
    try #require(outcome.userMessage.contains("Decision candidates:"))
    try #require(outcome.userMessage.contains("continue -> promote"))
    try #require(outcome.userMessage.contains("simulated-user rationale signals:"))
    try #require(outcome.userMessage.contains("needed import proof before switching"))
    try #require(audit.appliedDecisionCount == 1)
    try #require(audit.promotedDecisionCount == 1)
    try #require(audit.killedDecisionCount == 0)
    try #require(audit.decisionCandidateSummaries.count == 1)
    try #require(audit.decisionCandidateSummaries[0].contains("continue -> promote"))
    try #require(audit.decisionCandidateSummaries[0].contains("pressure lift"))
    try #require(audit.personaRationaleSignalSummaries.count == 1)
    try #require(
      audit.personaRationaleSignalSummaries[0].contains("needed import proof before switching"))
    try #require(audit.evidenceRunStepCount == 0)
    try #require(audit.evidenceRunIDs.isEmpty)
    try #require(audit.completedEvidenceRunCount == 0)
    try #require(audit.failedEvidenceRunCount == 0)
    try #require(audit.skippedScenarioCount == 0)
    try #require(audit.startingProofDebtCount == nil)
    try #require(audit.endingProofDebtCount == nil)
    try #require(audit.proofDebtDelta == nil)
    try #require(audit.summary.contains("candidates"))
    try #require(audit.summary.contains("continue -> promote"))
    try #require(audit.summary.contains("rationale signals"))
    try #require(audit.summary.contains("decisions 1 (1 promote, 0 kill); evidence 0"))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config.recordingTournamentAutomationCycleAudit(audit),
      evidenceIndex: index
    )
    try #require(digest.contains("Recent tournament automation cycle audits"))
    try #require(digest.contains("decision candidates"))
    try #require(digest.contains("pressure lift"))
    try #require(digest.contains("continue -> promote"))
    try #require(digest.contains("rationale signals"))
    try #require(digest.contains("needed import proof before switching"))
  }

  @Test func tournamentAutomationCycleOutcomeCountsRoundTransitions() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let experiment = try #require(config.tournamentExperiments.first)
    let tournament = try #require(config.tournaments.first)
    let round = try #require(config.tournamentRounds.first { $0.kind == .productImplementation })
    let contender = try #require(
      config.tournamentContenders.first { $0.experimentID == experiment.id })
    let step = TournamentAutomationStep(
      experiment: experiment,
      action: ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .applyRoundTransition,
        title: "Apply Round 3 transition",
        detail: "Select the winner from product implementation evidence.",
        priority: 10_000,
        tournamentID: tournament.id,
        roundID: round.id,
        contenderID: contender.id
      ),
      cohortReadiness: nil
    )
    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      messages: ["Selected \(contender.title) as the product tournament winner."],
      maxSteps: 3,
      stopReason: .noExecutableStep
    )
    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 360),
      endedAt: Date(timeIntervalSince1970: 365)
    )

    try #require(outcome.appliedDecisionCount == 0)
    try #require(outcome.appliedRoundTransitionCount == 1)
    try #require(outcome.evidenceRunStepCount == 0)
    try #require(outcome.userMessage.contains("1 round transition(s) applied"))
    try #require(audit.appliedDecisionCount == 0)
    try #require(audit.appliedRoundTransitionCount == 1)
    try #require(audit.evidenceRunStepCount == 0)
    try #require(audit.summary.contains("round transitions 1"))

    let legacyJSON = """
      {
        "id": "legacy-cycle",
        "startedAt": 1,
        "endedAt": 2,
        "executedStepIDs": [],
        "experimentIDs": [],
        "messages": [],
        "maxSteps": 1,
        "stopReason": "no_executable_step",
        "stopDetail": "Stopped.",
        "userMessage": "Stopped."
      }
      """
    let legacyAudit = try JSONDecoder().decode(
      TournamentAutomationCycleAudit.self,
      from: Data(legacyJSON.utf8)
    )
    try #require(legacyAudit.appliedRoundTransitionCount == 0)
    try #require(legacyAudit.prepareWorktreeStepCount == 0)
    try #require(legacyAudit.startingPersonaModelPlanEvaluationCount == nil)
    try #require(legacyAudit.endingPersonaModelPlanEvaluationCount == nil)
    try #require(legacyAudit.startingModelFreePlanEvaluationCount == nil)
    try #require(legacyAudit.endingModelFreePlanEvaluationCount == nil)
  }

  @Test func targetedProofOutcomeContradictionQueuesContenderRevision() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let scenario = try #require(config.scenarios.first { $0.experimentID == experiment.id })
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let record = makeDecisionAdvisorRecord(
      id: "contradicted-promote",
      experiment: experiment,
      config: config,
      personaID: scenario.segmentID,
      mode: .personaModel,
      endedAt: 200,
      verdict: .rejected,
      scores: weakScores,
      currentAlternativeComparison: "The spreadsheet remained better.",
      scenarioID: scenario.id,
      decisionIntent: ProductTournamentSimulationDecisionIntent(
        currentDecision: .keepGoing,
        targetDecision: .promote
      )
    )
    let index = ProductTournamentEvidenceIndex.build(records: [record])

    let signal = try #require(
      TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let brief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(signal.targetDecision == .promote)
    try #require(signal.outcome == .contradictsTarget)
    try #require(signal.recommendedDecision == .narrow)
    try #require(signal.runIDs == ["contradicted-promote"])
    try #require(signal.targetScenarioID == scenario.id)
    try #require(action.kind == .refineContender)
    try #require(action.title == "Revise contradicted promotion proof")
    try #require(action.priority == 89)
    try #require(action.targetDecision == .narrow)
    try #require(action.targetScenarioID == scenario.id)
    try #require(brief.source == .targetedProofOutcome)
    try #require(brief.title == "Revise contradicted promotion proof")
    try #require(brief.targetDecision == .narrow)
    try #require(step.kind == .applyRevision)
    try #require(step.canExecute)
    try #require(step.action.targetDecision == .narrow)
    try #require(digest.contains("Tournament automation targeted proof outcomes"))
    try #require(digest.contains("outcome contradicts_target"))
    try #require(digest.contains("recommended_decision narrow"))
  }

  @Test func targetedProofOutcomeContradictedKillQueuesLiftProofRerun() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let scenario = try #require(config.scenarios.first { $0.experimentID == experiment.id })
    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 5
    )
    let record = makeDecisionAdvisorRecord(
      id: "contradicted-kill",
      experiment: experiment,
      config: config,
      personaID: scenario.segmentID,
      mode: .personaModel,
      endedAt: 200,
      verdict: .strongPull,
      scores: strongScores,
      currentAlternativeComparison: "The product implementation beat the spreadsheet.",
      scenarioID: scenario.id,
      decisionIntent: ProductTournamentSimulationDecisionIntent(
        currentDecision: .keepGoing,
        targetDecision: .kill
      )
    )
    let index = ProductTournamentEvidenceIndex.build(records: [record])

    let signal = try #require(
      TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(signal.targetDecision == .kill)
    try #require(signal.outcome == .contradictsTarget)
    try #require(signal.recommendedDecision == .promote)
    try #require(signal.actionKind == .runCohort)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Recheck contradicted stop proof")
    try #require(action.targetDecision == .promote)
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetScenarioID == scenario.id)
    try #require(step.kind == .runCohort)
    try #require(step.canExecute)
    try #require(step.action.targetDecision == .promote)
  }

  @Test func targetedProofOutcomeStallQueuesRetargetedRevision() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let scenario = try #require(config.scenarios.first { $0.experimentID == experiment.id })
    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 5
    )
    let record = makeDecisionAdvisorRecord(
      id: "contradicted-kill",
      experiment: experiment,
      config: config,
      personaID: scenario.segmentID,
      mode: .personaModel,
      endedAt: 200,
      verdict: .strongPull,
      scores: strongScores,
      currentAlternativeComparison: "The product implementation beat the spreadsheet.",
      scenarioID: scenario.id,
      decisionIntent: ProductTournamentSimulationDecisionIntent(
        currentDecision: .keepGoing,
        targetDecision: .kill
      )
    )
    let index = ProductTournamentEvidenceIndex.build(records: [record])
    let signal = try #require(
      TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let stalledAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-stalled-targeted-proof",
      startedAt: 220,
      endedAt: 230,
      executedStepIDs: [TournamentAutomationCycleFailureAdvisor.stepID(for: action)],
      experimentIDs: [experiment.id],
      messages: ["Targeted kill contradiction proof reran 1 scenario."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["contradicted-kill-rerun"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      targetedProofOutcomeSummaries: [signal.auditSummary],
      stopReason: .noExecutableStep,
      stopDetail: "Stopped because no executable tournament automation step remains.",
      userMessage: "Tournament automation cycle ran 1 step(s). Targeted proof outcome persisted."
    )
    let stalledConfig = config.recordingTournamentAutomationCycleAudit(stalledAudit)

    let learningAudit = try #require(
      TournamentAutomationCycleLearningAdvisor.stalledTargetedProofOutcomeAudit(
        for: action,
        experiment: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let retarget = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let revisionStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: stalledConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: stalledConfig,
      evidenceIndex: index
    )

    try #require(learningAudit.id == stalledAudit.id)
    try #require(retarget.kind == .refineContender)
    try #require(retarget.title == "Retarget tournament proof outcome")
    try #require(retarget.detail.contains(stalledAudit.id))
    try #require(retarget.targetDecision == .promote)
    try #require(revisionBrief.source == .targetedProofOutcome)
    try #require(revisionBrief.title == "Revise contradicted stop proof")
    try #require(revisionBrief.targetDecision == .promote)
    try #require(revisionStep.kind == .applyRevision)
    try #require(revisionStep.canExecute)
    try #require(revisionStep.targetScenarioID == scenario.id)
    try #require(digest.contains("targeted proof outcomes"))
    try #require(digest.contains("tournament-cycle-stalled-targeted-proof"))
  }

  @Test func targetedProofOutcomeAppliedRevisionQueuesValidationRerun() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let scenario = try #require(config.scenarios.first { $0.experimentID == experiment.id })
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let record = makeDecisionAdvisorRecord(
      id: "contradicted-promote",
      experiment: experiment,
      config: config,
      personaID: scenario.segmentID,
      mode: .personaModel,
      endedAt: 200,
      verdict: .rejected,
      scores: weakScores,
      currentAlternativeComparison: "The spreadsheet remained better.",
      scenarioID: scenario.id,
      decisionIntent: ProductTournamentSimulationDecisionIntent(
        currentDecision: .keepGoing,
        targetDecision: .promote
      )
    )
    let index = ProductTournamentEvidenceIndex.build(records: [record])
    let signal = try #require(
      TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let revisionStep = try #require(
      TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let revisionAudit = TournamentAutomationCycleAudit(
      id: "tournament-cycle-targeted-proof-revision",
      startedAt: 220,
      endedAt: 230,
      executedStepIDs: [revisionStep.id],
      experimentIDs: [experiment.id],
      messages: ["Applied targeted proof revision."],
      maxSteps: 3,
      targetedProofOutcomeSummaries: [signal.auditSummary],
      revisionBriefSummaries: [revisionBrief.auditSummary],
      stopReason: .reachedStepLimit,
      stopStepID: revisionStep.id,
      stopStepTitle: revisionStep.title,
      stopDetail: "Contender revision checkpoint recorded.",
      userMessage: "Applied targeted proof revision; validate next."
    )
    let revisedConfig = config.recordingTournamentAutomationCycleAudit(revisionAudit)

    let appliedAudit = try #require(
      TournamentAutomationCycleLearningAdvisor.appliedTargetedProofOutcomeRevisionAudit(
        for: action,
        experiment: experiment,
        config: revisedConfig,
        evidenceIndex: index
      ))
    let validationAction = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: revisedConfig,
        evidenceIndex: index
      ))
    let validationStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: revisedConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(appliedAudit.id == revisionAudit.id)
    try #require(validationAction.kind == .rerunCohort)
    try #require(validationAction.title == "Validate targeted tournament proof revision")
    try #require(validationAction.detail.contains(revisionAudit.id))
    try #require(validationAction.cohortID == signal.targetCohortID)
    try #require(validationAction.targetScenarioID == scenario.id)
    try #require(validationAction.targetDecision == .narrow)
    try #require(validationStep.kind == .runCohort)
    try #require(validationStep.canExecute)
    try #require(validationStep.targetScenarioID == scenario.id)
  }

  @Test func tournamentAutomationCycleOutcomeReportsFailureStop() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    try completePlanOnlyRound(in: &config)
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [],
      messages: [],
      maxSteps: 3,
      stopReason: .executionFailed(
        stepID: step.id,
        title: step.title,
        message: "Command timed out while simulating the buyer."
      )
    )

    try #require(outcome.userMessage.contains("Tournament automation cycle ran no steps."))
    try #require(
      outcome.userMessage.contains(
        "Stopped because Run evidence cohort failed: Command timed out while simulating the buyer."
      ))
    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 200),
      endedAt: Date(timeIntervalSince1970: 210)
    )
    try #require(audit.stopReason == .executionFailed)
    try #require(audit.stopStepID == step.id)
    try #require(audit.stopStepTitle == step.title)
  }

  @Test func tournamentAutomationCycleOutcomeCanStampGeneratedRevisionScenarioStepID() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    let generatedRevisionStepID =
      "\(step.experimentID):\(TournamentAutomationStepKind.applyRevision.rawValue):generated-revision-scenario"

    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      executedStepIDs: [generatedRevisionStepID],
      messages: ["Applied a generated revision scenario."],
      maxSteps: 1,
      stopReason: .reachedStepLimit
    )
    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 240),
      endedAt: Date(timeIntervalSince1970: 245)
    )

    try #require(audit.executedStepIDs == [generatedRevisionStepID])
    try #require(audit.executedStepCount == 1)
    try #require(audit.summary.contains("1 step(s)"))
  }

  @Test func tournamentAutomationCycleOutcomeBuildsDurableAudit() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    let longScenarioID =
      "\(step.experimentID)-budget-owner-current-alternative-switching-proof-scenario"
    let tensionSummary =
      "\(step.experimentID): resolve split tournament evidence; score 82/100; strong_pull vs rejected; target_decision promote; target Budget owner; scenario \(longScenarioID); evidence split-a, split-b; Current tournament evidence is split."
    let proofTargetSummary =
      "\(step.experimentID): run targeted persona-model validation proof; target_decision promote; target Budget owner; scenario \(longScenarioID); debt 2 completed run(s), 2 persona(s), 1 persona-model current-alternative proof(s)"
    let targetedProofOutcomeSummary =
      "\(step.experimentID): targeted tournament proof outcome; target_decision kill; outcome contradicts_target; count 2; action run_cohort; recommended_decision promote; target Budget owner; scenario \(longScenarioID); runs stop-a, stop-b"
    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: [step],
      messages: ["Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
      maxSteps: 3,
      stopReason: .noExecutableStep,
      evidenceRunIDs: ["run-one"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      startingProofDebtCount: 8,
      endingProofDebtCount: 6,
      startingProofDebtSummary: "\(step.experimentID): 2 completed run(s), 2 persona(s)",
      endingProofDebtSummary: "\(step.experimentID): 1 completed run(s), 1 persona(s)",
      evidenceTensionSummaries: [tensionSummary],
      proofTargetSummaries: [proofTargetSummary],
      targetedProofOutcomeSummaries: [targetedProofOutcomeSummary],
      revisionBriefSummaries: [
        "\(step.experimentID): Retarget contender revision for simulated-user rationale; source persona_model_rationale; priority 88; target Budget owner"
      ]
    )

    let audit = outcome.audit(
      startedAt: Date(timeIntervalSince1970: 100),
      endedAt: Date(timeIntervalSince1970: 105)
    )

    try #require(audit.startedAt == 100)
    try #require(audit.endedAt == 105)
    try #require(audit.executedStepIDs == [step.id])
    try #require(audit.experimentIDs == [step.experimentID])
    try #require(audit.appliedDecisionCount == 0)
    try #require(audit.evidenceRunStepCount == 1)
    try #require(audit.evidenceRunIDs == ["run-one"])
    try #require(audit.completedEvidenceRunCount == 1)
    try #require(audit.failedEvidenceRunCount == 0)
    try #require(audit.skippedScenarioCount == 0)
    try #require(audit.startingProofDebtCount == 8)
    try #require(audit.endingProofDebtCount == 6)
    try #require(audit.proofDebtDelta == -2)
    try #require(audit.startingProofDebtSummary?.contains("2 completed run") == true)
    try #require(audit.endingProofDebtSummary?.contains("1 completed run") == true)
    try #require(audit.evidenceTensionSummaries.count == 1)
    try #require(audit.evidenceTensionSummaries[0].contains("resolve split tournament evidence"))
    try #require(audit.evidenceTensionSummaries[0].contains("target_decision promote"))
    try #require(audit.evidenceTensionSummaries[0].contains(longScenarioID))
    try #require(audit.proofTargetSummaries.count == 1)
    try #require(audit.proofTargetSummaries[0].contains("targeted persona-model validation proof"))
    try #require(audit.proofTargetSummaries[0].contains("target_decision promote"))
    try #require(audit.proofTargetSummaries[0].contains(longScenarioID))
    try #require(audit.targetedProofOutcomeSummaries.count == 1)
    try #require(
      audit.targetedProofOutcomeSummaries[0].contains("targeted tournament proof outcome"))
    try #require(audit.targetedProofOutcomeSummaries[0].contains("outcome contradicts_target"))
    try #require(audit.targetedProofOutcomeSummaries[0].contains("recommended_decision promote"))
    try #require(audit.revisionBriefSummaries.count == 1)
    try #require(audit.revisionBriefSummaries[0].contains("Retarget contender revision"))
    try #require(audit.stopReason == .noExecutableStep)
    try #require(audit.userMessage.contains("Tournament automation cycle ran 1 step(s)."))
    try #require(audit.userMessage.contains("evidence runs 1 completed, 0 needing review"))
    try #require(audit.userMessage.contains("Evidence tensions:"))
    try #require(audit.userMessage.contains("Proof targets:"))
    try #require(audit.userMessage.contains("Targeted proof outcomes:"))
    try #require(audit.userMessage.contains("Contender revisions:"))
    try #require(audit.userMessage.contains("Proof debt improved by 2"))
    try #require(audit.summary.contains("runs run-one"))
    try #require(audit.summary.contains("proof debt 8 -> 6 (-2)"))
    try #require(audit.summary.contains("tensions"))
    try #require(audit.summary.contains("resolve split tournament evidence"))
    try #require(audit.summary.contains("targets"))
    try #require(audit.summary.contains("targeted persona-model validation proof"))
    try #require(audit.summary.contains("target_decision promote"))
    try #require(audit.summary.contains(longScenarioID))
    try #require(audit.summary.contains("targeted outcomes"))
    try #require(audit.summary.contains("outcome contradicts_target"))
    try #require(audit.summary.contains("revisions"))
    try #require(audit.summary.contains("Retarget contender revision"))
    try #require(
      audit.userMessage.contains(
        "Stopped because no executable tournament automation step remains."))
  }

  @Test func tournamentDecisionAdvisorAppliesRecommendedDecisionThroughReflectRules() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let index = makeTournamentPromotionEvidenceIndex(config: config)
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    let next = try ProductTournamentDecisionAdvisor.applyingRecommendedDecision(
      experimentID: experiment.id,
      to: config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 400)
    )
    let savedExperiment = try #require(next.tournamentExperiments.first { $0.id == experiment.id })
    let decision = try #require(next.decisions.last)

    try #require(action.kind == .applyDecision)
    try #require(action.title == "Apply tournament decision")
    try #require(action.detail.contains("continue -> promote"))
    try #require(action.targetDecision == .promote)
    try #require(action.cohortID == nil)
    try #require(savedExperiment.decision == .promote)
    try #require(savedExperiment.evidenceSummary.contains("Tournament readiness"))
    try #require(savedExperiment.evidenceSummary.contains("current-alternative proof"))
    try #require(decision.decision == .promote)
    try #require(decision.evidenceRunIDs == ["promote-a", "promote-b", "promote-c"])
    try #require(decision.decidedBy == "Product Tournament Decision Advisor")
    try #require(decision.beforeSha == experiment.currentSha)
    try #require(decision.afterSha == experiment.currentSha)
  }

  @Test func tournamentAutomationAppliesRoundOnePlanTransition() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })

    let workspace = CompassWorkspace(repoURL: try makeTempDir())
    defer { try? FileManager.default.removeItem(at: workspace.repoURL) }
    try workspace.initialize()
    try workspace.writeProductTournamentConfig(config)
    let planProofStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    let contenderID = try #require(planProofStep.contenderID)
    let contender = try #require(config.tournamentContenders.first { $0.id == contenderID })
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == contender.experimentID })
    _ = try TournamentAutomationPlanProofStepExecutor.run(
      planProofStep,
      in: workspace,
      now: Date(timeIntervalSince1970: 40)
    )
    let index = workspace.readProductTournamentEvidenceIndex()
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))

    try #require(step.kind == .applyRoundTransition)
    try #require(step.action.kind == .applyRoundTransition)
    try #require(step.title == "Apply Round 1 transition")
    try #require(step.experimentID == experiment.id)
    try #require(step.tournamentID == tournament.id)
    try #require(step.roundID == planRound.id)
    try #require(step.contenderID == contender.id)

    let outcome = try TournamentAutomationRoundTransitionStepExecutor.run(
      step,
      in: workspace,
      now: Date(timeIntervalSince1970: 50)
    )
    let saved = try workspace.readProductTournamentConfig()
    let toRoundID = try #require(outcome.toRoundID)
    let activeRound = try #require(
      saved.tournamentRounds.first { $0.id == toRoundID })

    try #require(outcome.roundKind == .productPlans)
    try #require(outcome.userMessage.contains("Round 2"))
    try #require(activeRound.kind == .coreTechnology)
    try #require(activeRound.status == .active)
    try #require(saved.tournaments[0].currentRoundID == activeRound.id)
  }

  @Test func tournamentAutomationAppliesRoundTwoEvidenceTransition() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let target = try activateRoundTwoImplementationTarget(in: &config)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == target.experimentID })
    let records = scopedTournamentEvidenceRecords(
      prefix: "automation-round-2",
      experiment: experiment,
      config: config,
      target: target,
      count: 2,
      completedUseProof: true
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))

    try #require(step.kind == .applyRoundTransition)
    try #require(step.action.kind == .applyRoundTransition)
    try #require(step.title == "Apply Round 2 transition")
    try #require(step.experimentID == experiment.id)
    try #require(step.tournamentID == target.tournamentID)
    try #require(step.roundID == target.roundID)
    try #require(step.contenderID == target.contenderID)

    let workspace = CompassWorkspace(repoURL: try makeTempDir())
    defer { try? FileManager.default.removeItem(at: workspace.repoURL) }
    try workspace.initialize()
    try workspace.writeProductTournamentConfig(config)
    for record in records {
      _ = try workspace.writeProductTournamentEvidenceRecord(record)
    }
    let outcome = try TournamentAutomationRoundTransitionStepExecutor.run(
      step,
      in: workspace,
      now: Date(timeIntervalSince1970: 60)
    )
    let saved = try workspace.readProductTournamentConfig()
    let toRoundID = try #require(outcome.toRoundID)
    let activeRound = try #require(
      saved.tournamentRounds.first { $0.id == toRoundID })

    try #require(outcome.roundKind == .coreTechnology)
    try #require(outcome.userMessage.contains("Round 3"))
    try #require(activeRound.kind == .productImplementation)
    try #require(activeRound.status == .active)
    try #require(saved.tournaments[0].currentRoundID == activeRound.id)
  }

  @Test func tournamentAutomationAppliesRoundThreeWinnerTransition() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let target = try activateRoundThreeProductImplementationTarget(in: &config)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == target.experimentID })
    let records = scopedTournamentEvidenceRecords(
      prefix: "automation-round-3",
      experiment: experiment,
      config: config,
      target: target,
      count: 3,
      completedUseProof: true,
      willingnessToPay: 5
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))

    try #require(step.kind == .applyRoundTransition)
    try #require(step.action.kind == .applyRoundTransition)
    try #require(step.title == "Apply Round 3 transition")
    try #require(step.experimentID == experiment.id)
    try #require(step.tournamentID == target.tournamentID)
    try #require(step.roundID == target.roundID)
    try #require(step.contenderID == target.contenderID)

    let workspace = CompassWorkspace(repoURL: try makeTempDir())
    defer { try? FileManager.default.removeItem(at: workspace.repoURL) }
    try workspace.initialize()
    try workspace.writeProductTournamentConfig(config)
    for record in records {
      _ = try workspace.writeProductTournamentEvidenceRecord(record)
    }
    let outcome = try TournamentAutomationRoundTransitionStepExecutor.run(
      step,
      in: workspace,
      now: Date(timeIntervalSince1970: 70)
    )
    let saved = try workspace.readProductTournamentConfig()
    let savedTournament = try #require(saved.tournaments.first { $0.id == target.tournamentID })
    let savedContender = try #require(
      saved.tournamentContenders.first { $0.id == target.contenderID })
    let savedExperiment = try #require(
      saved.tournamentExperiments.first { $0.id == target.experimentID })

    try #require(outcome.roundKind == .productImplementation)
    try #require(outcome.userMessage.contains("winner"))
    try #require(savedTournament.status == .completed)
    try #require(savedContender.status == .winner)
    try #require(savedExperiment.decision == .promote)
  }

  @Test func tournamentAutomationQueuesRoundThreeImplementationRevisionBrief() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let target = try activateRoundThreeProductImplementationTarget(in: &config)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == target.experimentID })
    let records = scopedTournamentEvidenceRecords(
      prefix: "automation-round-3-revision",
      experiment: experiment,
      config: config,
      target: target,
      count: 3,
      completedUseProof: true,
      willingnessToPay: 2,
      mode: .personaModel
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: target.tournamentID,
        roundID: target.roundID,
        config: config,
        evidenceIndex: index
      ).first)
    let revisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let explicitRevisionBrief = try #require(
      TournamentAutomationRevisionBriefAdvisor.roundThreeImplementationRevisionBrief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(proposal.recommendation == .reviseImplementation)
    try #require(
      proposal.proofGaps.contains { $0.contains("willingness to pay 2.0/5") })
    try #require(revisionBrief == explicitRevisionBrief)
    try #require(revisionBrief.source == .roundThreeImplementationRevision)
    try #require(revisionBrief.title == "Revise Round 3 product implementation proof gaps")
    try #require(revisionBrief.implementationChange.contains("low-medium fidelity"))
    try #require(revisionBrief.implementationChange.contains("willingness to pay"))
    try #require(revisionBrief.scenarioChange.contains("Round 3 validation"))
    try #require(revisionBrief.proofPlan == proposal.nextValidationTarget)
    try #require(revisionBrief.targetDecision == .narrow)
    try #require(revisionBrief.targetPersonaID != nil)
    try #require(revisionBrief.targetScenarioID != nil)
    try #require(revisionBrief.auditSummary.contains("source round_3_implementation_revision"))
    try #require(step.kind == .applyRevision)
    try #require(step.canExecute)
    try #require(step.action.kind == .refineContender)
    try #require(step.action.title == revisionBrief.title)
    try #require(step.action.detail.contains("Proof"))
    try #require(step.action.targetPersonaID == revisionBrief.targetPersonaID)
    try #require(step.action.targetScenarioID == revisionBrief.targetScenarioID)
    try #require(step.action.targetDecision == .narrow)
    try #require(step.title != "Apply Round 3 transition")
    try #require(digest.contains("Tournament automation revision briefs"))
    try #require(digest.contains("source round_3_implementation_revision"))
    try #require(digest.contains("low-medium fidelity"))
  }

  @Test func tournamentNextActionTargetsRoundThreePayProofBeforeGenericPromotion() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let target = try activateRoundThreeProductImplementationTarget(in: &config)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == target.experimentID })
    let records = scopedTournamentEvidenceRecords(
      prefix: "round-3-pay-gap",
      experiment: experiment,
      config: config,
      target: target,
      count: 3,
      completedUseProof: true,
      mode: .personaModel
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let genericDecision = try #require(
      ProductTournamentDecisionAdvisor.proposal(
        experimentID: experiment.id,
        config: config,
        evidenceIndex: index
      ))
    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: target.tournamentID,
        roundID: target.roundID,
        config: config,
        evidenceIndex: index
      ).first)
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let readiness = try #require(
      ProductTournamentNextActionAdvisor.cohortRunReadiness(
        for: action,
        experiment: experiment,
        config: config
      ))
    let signal = TournamentAutomationExperimentRanker.signal(
      for: experiment,
      config: config,
      evidenceIndex: index
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(genericDecision.update.decision == .promote)
    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.proofGaps.contains { $0.contains("explicit willingness-to-pay") })
    try #require(action.kind == .rerunCohort)
    try #require(action.title == "Run Round 3 pay proof")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.tournamentID == target.tournamentID)
    try #require(action.roundID == target.roundID)
    try #require(action.contenderID == target.contenderID)
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    try #require(action.targetScenarioID != nil)
    try #require(action.targetDecision == .promote)
    try #require(action.detail.contains("explicit willingness-to-pay"))
    try #require(action.detail.contains("before winner selection"))
    try #require(readiness.canRun)
    try #require(readiness.targetScenarioID == action.targetScenarioID)
    try #require(signal.nextActionKind == .rerunCohort)
    try #require(signal.nextActionTitle == "Run Round 3 pay proof")
    try #require(digest.contains("Next tournament automation actions"))
    try #require(digest.contains("Run Round 3 pay proof"))
  }

  @Test func tournamentNextActionTargetsRoundThreeImplementationUseProofFirst() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let target = try activateRoundThreeProductImplementationTarget(in: &config)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == target.experimentID })
    let records = scopedTournamentEvidenceRecords(
      prefix: "round-3-use-gap",
      experiment: experiment,
      config: config,
      target: target,
      count: 3,
      completedUseProof: false,
      willingnessToPay: 5,
      mode: .personaModel
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: target.tournamentID,
        roundID: target.roundID,
        config: config,
        evidenceIndex: index
      ).first)
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.proofGaps.contains { $0.contains("implementation-use") })
    try #require(action.kind == .rerunCohort)
    try #require(action.title == "Run Round 3 implementation-use proof")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetScenarioID != nil)
    try #require(action.detail.contains("implementation-use trace"))
  }

  @Test func tournamentNextActionTargetsRoundThreeCurrentAlternativeProof() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let target = try activateRoundThreeProductImplementationTarget(in: &config)
    let experiment = try #require(
      config.tournamentExperiments.first { $0.id == target.experimentID })
    let records = scopedTournamentEvidenceRecords(
      prefix: "round-3-alternative-gap",
      experiment: experiment,
      config: config,
      target: target,
      count: 3,
      completedUseProof: true,
      willingnessToPay: 5,
      mode: .personaModel,
      currentAlternativeComparison: "No current-alternative comparison was captured."
    )
    let index = ProductTournamentEvidenceIndex.build(records: records)

    let proposal = try #require(
      ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: target.tournamentID,
        roundID: target.roundID,
        config: config,
        evidenceIndex: index
      ).first)
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(proposal.recommendation == .gatherEvidence)
    try #require(proposal.proofGaps.contains { $0.contains("current-alternative") })
    try #require(action.kind == .rerunCohort)
    try #require(action.title == "Run Round 3 alternative proof")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetScenarioID != nil)
    try #require(action.detail.contains("current-alternative comparison"))
  }

  @Test func tournamentDecisionAdvisorDoesNotPromoteFromStaleEvidence() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    var staleExperiment = config.tournamentExperiments[0]
    staleExperiment.currentSha = "old-sha"
    let index = makeTournamentPromotionEvidenceIndex(experiment: staleExperiment, config: config)

    let proposals = ProductTournamentDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    )
    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: config.tournamentExperiments[0],
        config: config,
        evidenceIndex: index
      ))

    try #require(proposals.isEmpty)
    try #require(action.kind == .rerunCohort)
    try #require(action.title == "Rerun current evidence")
    try #require(action.detail.contains("stale run"))
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    do {
      _ = try ProductTournamentDecisionAdvisor.applyingRecommendedDecision(
        experimentID: config.tournamentExperiments[0].id,
        to: config,
        evidenceIndex: index
      )
      #expect(Bool(false), "Expected stale evidence to produce no tournament proposal.")
    } catch let error as ProductTournamentDecisionAdvisorError {
      try #require(error == .noProposal(config.tournamentExperiments[0].id))
    }
  }

  @Test func tournamentNextActionTargetsRunnableCohortBeforeEvidenceExists() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: .empty
      ))

    try #require(action.kind == .runCohort)
    try #require(action.title == "Run product tournament cohort")
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    try #require(action.detail.contains(config.scenarioCohorts[0].id))

    let readiness = try #require(
      ProductTournamentNextActionAdvisor.cohortRunReadiness(
        for: action,
        experiment: experiment,
        config: config
      ))
    try #require(readiness.canRun)
    try #require(readiness.cohortID == config.scenarioCohorts[0].id)
    try #require(readiness.enabledScenarioCount == 2)
    try #require(readiness.missingTargetCommitCount == 0)
  }

  @Test func tournamentNextActionAsksForEvidenceCohortWhenNoneIsRunnable() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    config.tournamentExperiments[0].baseSha = "base-sha"
    config.tournamentExperiments[0].currentSha = "head-sha"
    config.scenarioCohorts = config.scenarioCohorts.map {
      ProductScenarioCohort(
        id: $0.id,
        title: $0.title,
        experimentID: $0.experimentID,
        scenarioIDs: $0.scenarioIDs,
        enabled: false,
        tags: $0.tags
      )
    }

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: config.tournamentExperiments[0],
        config: config,
        evidenceIndex: .empty
      ))

    try #require(action.kind == .refineContender)
    try #require(action.title == "Define evidence cohort")
    try #require(action.cohortID == nil)
  }

  @Test func tournamentSuggestedCohortReadinessBlocksMissingTargetCommit() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    let experiment = config.tournamentExperiments[0]

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: .empty
      ))
    let readiness = try #require(
      ProductTournamentNextActionAdvisor.cohortRunReadiness(
        for: action,
        experiment: experiment,
        config: config
      ))

    try #require(action.kind == .runCohort)
    try #require(!readiness.canRun)
    try #require(readiness.enabledScenarioCount == 2)
    try #require(readiness.missingTargetCommitCount == 2)
    try #require(readiness.blockedReason?.contains("target commit") == true)
  }

  @Test func tournamentAutomationPreparesCandidateWorktreeWhenStarterCohortNeedsCommit() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Reporting work needs evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].decision = .keepGoing
    try completePlanOnlyRound(in: &config)
    let experiment = config.tournamentExperiments[0]
    let cohortIndex = try #require(
      config.scenarioCohorts.firstIndex { $0.experimentID == experiment.id }
    )
    let cohort = config.scenarioCohorts[cohortIndex]
    config.scenarioCohorts[cohortIndex] = ProductScenarioCohort(
      id: cohort.id,
      title: cohort.title,
      experimentID: cohort.experimentID,
      scenarioIDs: cohort.scenarioIDs,
      enabled: cohort.enabled,
      tags: ["discover", "candidate-implementation-track"]
    )

    let action = try #require(
      ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: .empty
      ))
    let step = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    let plan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty
    )
    let singleStepPlan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty,
      maxSteps: 1
    )

    try #require(action.kind == .prepareWorktree)
    try #require(action.title == "Prepare implementation worktree")
    try #require(action.cohortID == cohort.id)
    try #require(action.detail.contains(experiment.branchName))
    try #require(action.detail.contains(experiment.worktreeID))
    try #require(step.kind == .prepareWorktree)
    try #require(step.canExecute)
    try #require(step.id.contains("prepare_worktree"))
    try #require(plan.canRun)
    try #require(plan.executableSteps.map(\.kind) == [.prepareWorktree])
    try #require(plan.refreshesQueueAfterStateChange)
    try #require(plan.summary.contains("Queue refreshes after state-changing steps"))
    try #require(plan.queueSummary.contains("Prepare implementation worktree"))
    try #require(plan.queueSummary.contains("refresh queue for newly unblocked evidence"))
    try #require(!singleStepPlan.refreshesQueueAfterStateChange)
    try #require(!singleStepPlan.queueSummary.contains("refresh queue"))
  }

  @Test func rolloutWorkflowPromotesExperimentWithBranchCommitAndEvidenceTrail() throws {
    let config = makeRolloutConfig(decision: .keepGoing)
    let experiment = config.tournamentExperiments[0]
    let evidenceIndex = makeRolloutEvidenceIndex(config: config)

    try #require(
      ProductTournamentExperimentRolloutWorkflow.canApply(.promoteOrConfirm, to: experiment))

    let marked = try ProductTournamentExperimentRolloutWorkflow.applying(
      .promoteOrConfirm,
      experimentID: experiment.id,
      to: config,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 50),
      decidedBy: "Workbench"
    )
    let readyExperiment = try #require(
      marked.tournamentExperiments.first { $0.id == experiment.id })
    let readyDecision = try #require(marked.decisions.last)

    try #require(readyExperiment.decision == .promote)
    try #require(readyDecision.decision == .promote)
    try #require(readyDecision.branchName == experiment.branchName)
    try #require(readyDecision.beforeSha == experiment.currentSha)
    try #require(readyDecision.afterSha == experiment.currentSha)
    try #require(readyDecision.evidenceRunIDs == ["rollout-run"])
    try #require(readyDecision.decidedBy == "Workbench")

    let promoted = try ProductTournamentExperimentRolloutWorkflow.applying(
      .promoteOrConfirm,
      experimentID: experiment.id,
      to: marked,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 60),
      decidedBy: "Workbench"
    )
    let promotedExperiment = try #require(
      promoted.tournamentExperiments.first { $0.id == experiment.id })
    let promotedProductTournamentContenderPlan = try #require(
      promoted.contenderPlans.first { $0.id == experiment.contenderPlanID }
    )
    let promotedDecision = try #require(promoted.decisions.last)

    try #require(promotedExperiment.decision == .promoted)
    try #require(promotedProductTournamentContenderPlan.status == .promoted)
    try #require(promotedDecision.decision == .promoted)
    try #require(promotedDecision.evidenceRunIDs == ["rollout-run"])
  }

  @Test func rolloutWorkflowKillsThenArchivesWithoutDeletingExperimentLineage() throws {
    let config = makeRolloutConfig(decision: .keepGoing)
    let experiment = config.tournamentExperiments[0]
    let evidenceIndex = makeRolloutEvidenceIndex(config: config)

    try #require(
      ProductTournamentExperimentRolloutWorkflow.canApply(.killOrArchive, to: experiment))

    let killed = try ProductTournamentExperimentRolloutWorkflow.applying(
      .killOrArchive,
      experimentID: experiment.id,
      to: config,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 70),
      decidedBy: "Workbench"
    )
    let killedExperiment = try #require(
      killed.tournamentExperiments.first { $0.id == experiment.id })
    let rejectedProductTournamentContenderPlan = try #require(
      killed.contenderPlans.first { $0.id == experiment.contenderPlanID }
    )

    try #require(killedExperiment.decision == .kill)
    try #require(killedExperiment.branchName == experiment.branchName)
    try #require(killedExperiment.worktreeID == experiment.worktreeID)
    try #require(rejectedProductTournamentContenderPlan.status == .rejected)

    let archived = try ProductTournamentExperimentRolloutWorkflow.applying(
      .killOrArchive,
      experimentID: experiment.id,
      to: killed,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 80),
      decidedBy: "Workbench"
    )
    let archivedExperiment = try #require(
      archived.tournamentExperiments.first { $0.id == experiment.id })
    let parkedProductTournamentContenderPlan = try #require(
      archived.contenderPlans.first { $0.id == experiment.contenderPlanID }
    )
    let archiveDecision = try #require(archived.decisions.last)

    try #require(archivedExperiment.decision == .archived)
    try #require(archivedExperiment.branchName == experiment.branchName)
    try #require(archivedExperiment.worktreeID == experiment.worktreeID)
    try #require(parkedProductTournamentContenderPlan.status == .parked)
    try #require(archiveDecision.decision == .archived)
    try #require(archiveDecision.branchName == experiment.branchName)
    try #require(archiveDecision.beforeSha == experiment.currentSha)
    try #require(archiveDecision.afterSha == experiment.currentSha)
  }
}

private func makeRolloutConfig(decision: ProductTournamentExperimentDecision)
  -> ProductTournamentConfig
{
  var config = ProductTournamentConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Reporting work needs evidence.",
    now: Date(timeIntervalSince1970: 10)
  )
  config.tournamentExperiments[0].decision = decision
  config.tournamentExperiments[0].baseSha = "base-sha"
  config.tournamentExperiments[0].currentSha = "head-sha"
  return config
}

private func activateRoundTwoImplementationTarget(
  in config: inout ProductTournamentConfig
) throws -> ProductTournamentRoundImplementationTarget {
  let experimentID = config.tournamentExperiments[0].id
  let contenderIndex = try #require(
    config.tournamentContenders.firstIndex { $0.experimentID == experimentID })
  let tournamentIndex = try #require(
    config.tournaments.firstIndex {
      $0.id == config.tournamentContenders[contenderIndex].tournamentID
    }
  )
  let planRoundIndex = try #require(
    config.tournamentRounds.firstIndex {
      $0.tournamentID == config.tournaments[tournamentIndex].id && $0.kind == .productPlans
    })
  let feasibilityRoundIndex = try #require(
    config.tournamentRounds.firstIndex {
      $0.tournamentID == config.tournaments[tournamentIndex].id && $0.kind == .coreTechnology
    })
  let contenderID = config.tournamentContenders[contenderIndex].id

  config.tournamentContenders[contenderIndex].status = .narrowed
  config.tournamentRounds[planRoundIndex].status = .completed
  config.tournamentRounds[feasibilityRoundIndex].status = .active
  config.tournamentRounds[feasibilityRoundIndex].contenderIDs = [contenderID]
  config.tournaments[tournamentIndex].currentRoundID =
    config.tournamentRounds[feasibilityRoundIndex].id

  return ProductTournamentRoundImplementationTarget(
    tournamentID: config.tournaments[tournamentIndex].id,
    roundID: config.tournamentRounds[feasibilityRoundIndex].id,
    contenderID: contenderID,
    experimentID: experimentID
  )
}

private func activateRoundThreeProductImplementationTarget(
  in config: inout ProductTournamentConfig
) throws -> ProductTournamentRoundImplementationTarget {
  let roundTwoTarget = try activateRoundTwoImplementationTarget(in: &config)
  let productImplementationRoundIndex = try #require(
    config.tournamentRounds.firstIndex {
      $0.tournamentID == roundTwoTarget.tournamentID && $0.kind == .productImplementation
    })
  let coreRoundIndex = try #require(
    config.tournamentRounds.firstIndex { $0.id == roundTwoTarget.roundID })
  let tournamentIndex = try #require(
    config.tournaments.firstIndex { $0.id == roundTwoTarget.tournamentID })

  config.tournamentRounds[coreRoundIndex].status = .completed
  config.tournamentRounds[productImplementationRoundIndex].status = .active
  config.tournamentRounds[productImplementationRoundIndex].contenderIDs = [roundTwoTarget.contenderID]
  config.tournaments[tournamentIndex].currentRoundID =
    config.tournamentRounds[productImplementationRoundIndex].id

  return ProductTournamentRoundImplementationTarget(
    tournamentID: roundTwoTarget.tournamentID,
    roundID: config.tournamentRounds[productImplementationRoundIndex].id,
    contenderID: roundTwoTarget.contenderID,
    experimentID: roundTwoTarget.experimentID
  )
}

private func completePlanOnlyRound(in config: inout ProductTournamentConfig) throws {
  let tournamentIndex = try #require(config.tournaments.indices.first)
  let tournamentID = config.tournaments[tournamentIndex].id
  let planRoundIndex = try #require(
    config.tournamentRounds.firstIndex {
      $0.tournamentID == tournamentID && $0.kind == .productPlans
    })
  config.tournamentRounds[planRoundIndex].status = .completed
}

private func makeProofDebtEvidenceIndex(
  tournamentExperiments: [ProductTournamentExperiment],
  config: ProductTournamentConfig
) -> ProductTournamentEvidenceIndex {
  let scores = ProductTournamentEvidenceScores(
    painRecognition: 5,
    workflowImprovement: 5,
    alternativeAdvantage: 5,
    switchingReadiness: 5,
    continuedUsePull: 5
  )
  let personaIDs = config.userSegments.map(\.id)
  let firstPersonaID = personaIDs.first ?? "operator"
  let secondPersonaID = personaIDs.dropFirst().first ?? firstPersonaID
  let records = tournamentExperiments.flatMap { experiment in
    [
      makeDecisionAdvisorRecord(
        id: "\(experiment.id)-proof-a",
        experiment: experiment,
        config: config,
        personaID: firstPersonaID,
        endedAt: 300,
        verdict: .strongPull,
        scores: scores
      ),
      makeDecisionAdvisorRecord(
        id: "\(experiment.id)-proof-b",
        experiment: experiment,
        config: config,
        personaID: secondPersonaID,
        endedAt: 200,
        verdict: .strongPull,
        scores: scores
      ),
    ]
  }
  return ProductTournamentEvidenceIndex.build(records: records)
}

private func makePlanProofRecord(
  id: String,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  contender: ProductTournamentContender,
  config: ProductTournamentConfig,
  segment: UserSegment
) throws -> ProductTournamentPlanEvaluationRecord {
  let contenderPlan = try #require(
    config.contenderPlans.first { $0.id == contender.contenderPlanID })
  return ProductTournamentPlanEvaluationRecord(
    id: id,
    tournamentID: tournament.id,
    roundID: round.id,
    contenderID: contender.id,
    contenderPlanID: contender.contenderPlanID,
    experimentID: contender.experimentID,
    painID: contenderPlan.painID,
    personaID: segment.id,
    personaName: segment.name,
    currentWorkflowID: segment.currentWorkflowIDs.first,
    alternativeID: segment.alternativeIDs.first,
    startedAt: 1,
    endedAt: 2,
    scores: ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5,
      willingnessToPay: 5
    ),
    willingnessToPayScore: 5,
    estimatedMonthlyPriceCents: 9900,
    commercialProofSummary: "priced at $99/month with operator value proof",
    currentAlternativeComparison: "The plan beats the current spreadsheet workaround.",
    verdict: .strongPull,
    summary: "\(segment.name) strongly liked the plan."
  )
}

private actor TournamentAutomationPlanEvaluationModelStream {
  private let response: String?
  private var prompts: [String] = []

  init(response: String?) {
    self.response = response
  }

  func respond(_ prompt: String) -> String? {
    prompts.append(prompt)
    return response
  }

  func recordedPrompts() -> [String] {
    prompts
  }
}

private func makeRolloutEvidenceIndex(config: ProductTournamentConfig)
  -> ProductTournamentEvidenceIndex
{
  let record = ProductTournamentEvidenceRecord(
    id: "rollout-run",
    experimentID: config.tournamentExperiments[0].id,
    contenderPlanID: config.contenderPlans[0].id,
    painID: config.painHypotheses[0].id,
    branchName: config.tournamentExperiments[0].branchName,
    commitSha: config.tournamentExperiments[0].currentSha ?? "head-sha",
    scenarioID: "scenario-one",
    personaID: config.userSegments[0].id,
    mode: .modelFree,
    status: .completed,
    startedAt: 20,
    endedAt: 30,
    traceHash: "trace-rollout",
    model: "model-free",
    scores: ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 4
    ),
    objections: [],
    missingCapabilities: [],
    currentAlternativeComparison: "Beat the spreadsheet alternative.",
    verdict: .strongPull,
    summary: "Evidence supports the rollout decision."
  )
  return ProductTournamentEvidenceIndex.build(records: [record])
}

private func scopedTournamentEvidenceRecords(
  prefix: String,
  experiment: ProductTournamentExperiment,
  config: ProductTournamentConfig,
  target: ProductTournamentRoundImplementationTarget,
  count: Int,
  completedUseProof: Bool,
  willingnessToPay: Int? = nil,
  mode: ProductTournamentSimulationMode = .modelFree,
  currentAlternativeComparison: String = "The contender beat the current spreadsheet workflow."
) -> [ProductTournamentEvidenceRecord] {
  let scores = ProductTournamentEvidenceScores(
    painRecognition: 5,
    workflowImprovement: 5,
    alternativeAdvantage: 5,
    switchingReadiness: 5,
    continuedUsePull: 5,
    willingnessToPay: willingnessToPay
  )
  let segments = Array(config.userSegments)
  return (0..<count).map { index in
    let segment = segments[index % max(1, segments.count)]
    return makeDecisionAdvisorRecord(
      id: "\(prefix)-\(index)",
      experiment: experiment,
      config: config,
      personaID: segment.id,
      mode: mode,
      endedAt: Double(200 + index),
      verdict: .strongPull,
      scores: scores,
      currentAlternativeComparison: currentAlternativeComparison,
      tournamentID: target.tournamentID,
      roundID: target.roundID,
      contenderID: target.contenderID,
      completedUseProof: completedUseProof,
      willingnessToPayScore: willingnessToPay,
      sponsorshipIntent: willingnessToPay.map {
        $0 >= 4
          ? "The simulated user would pay for or sponsor this contender."
          : "The simulated user is not ready to sponsor this contender."
      } ?? ""
    )
  }
}

private func makeTournamentPromotionEvidenceIndex(
  experiment: ProductTournamentExperiment? = nil,
  config: ProductTournamentConfig,
  includePersonaModelEvidence: Bool = true,
  includePersonaModelUserBreadth: Bool = true,
  includeCurrentAlternativeProof: Bool = true,
  personaActionRationales: [String] = []
) -> ProductTournamentEvidenceIndex {
  let scores = ProductTournamentEvidenceScores(
    painRecognition: 5,
    workflowImprovement: 5,
    alternativeAdvantage: 5,
    switchingReadiness: 5,
    continuedUsePull: 5
  )
  let experiment = experiment ?? config.tournamentExperiments[0]
  let operatorID = config.userSegments.first?.id ?? "operator"
  let buyerID = config.userSegments.dropFirst().first?.id ?? "buyer"
  let comparison = includeCurrentAlternativeProof ? "Compared against the current workflow." : ""
  return ProductTournamentEvidenceIndex.build(
    records: [
      makeDecisionAdvisorRecord(
        id: "promote-a",
        experiment: experiment,
        config: config,
        personaID: operatorID,
        mode: includePersonaModelEvidence ? .personaModel : .modelFree,
        endedAt: 300,
        verdict: .strongPull,
        scores: scores,
        currentAlternativeComparison: comparison,
        personaActionRationales: personaActionRationales
      ),
      makeDecisionAdvisorRecord(
        id: "promote-b",
        experiment: experiment,
        config: config,
        personaID: buyerID,
        mode: includePersonaModelEvidence && includePersonaModelUserBreadth ? .personaModel : .modelFree,
        endedAt: 200,
        verdict: .strongPull,
        scores: scores,
        currentAlternativeComparison: comparison,
        personaActionRationales: personaActionRationales
      ),
      makeDecisionAdvisorRecord(
        id: "promote-c",
        experiment: experiment,
        config: config,
        personaID: operatorID,
        endedAt: 100,
        verdict: .promising,
        scores: scores,
        currentAlternativeComparison: comparison,
        personaActionRationales: personaActionRationales
      ),
    ]
  )
}

private func makeDecisionAdvisorRecord(
  id: String,
  experiment: ProductTournamentExperiment,
  config: ProductTournamentConfig,
  personaID: String,
  mode: ProductTournamentSimulationMode = .modelFree,
  endedAt: Double,
  verdict: ProductTournamentEvidenceVerdict,
  scores: ProductTournamentEvidenceScores,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  currentAlternativeComparison: String = "Compared against the current workflow.",
  scenarioID: String? = nil,
  personaActionRationales: [String] = [],
  decisionIntent: ProductTournamentSimulationDecisionIntent? = nil,
  tournamentID: String? = nil,
  roundID: String? = nil,
  contenderID: String? = nil,
  completedUseProof: Bool = false,
  willingnessToPayScore: Int? = nil,
  sponsorshipIntent: String = ""
) -> ProductTournamentEvidenceRecord {
  let contenderPlan = config.contenderPlans.first { $0.id == experiment.contenderPlanID }
  return ProductTournamentEvidenceRecord(
    id: id,
    experimentID: experiment.id,
    contenderPlanID: experiment.contenderPlanID,
    painID: contenderPlan?.painID ?? config.painHypotheses.first?.id ?? "pain",
    tournamentID: tournamentID,
    roundID: roundID,
    contenderID: contenderID,
    branchName: experiment.branchName,
    commitSha: experiment.currentSha ?? experiment.baseSha ?? "head-sha",
    scenarioID: scenarioID ?? "\(experiment.id)-scenario",
    personaID: personaID,
    mode: mode,
    decisionIntent: decisionIntent,
    status: .completed,
    startedAt: endedAt - 10,
    endedAt: endedAt,
    traceHash: "trace-\(id)",
    completedUseProof: completedUseProof,
    model: mode == .modelFree ? "model-free" : "gpt-test",
    scores: scores,
    objections: objections,
    missingCapabilities: missingCapabilities,
    currentAlternativeComparison: currentAlternativeComparison,
    willingnessToPayScore: willingnessToPayScore,
    sponsorshipIntent: sponsorshipIntent,
    personaActionRationales: personaActionRationales,
    verdict: verdict,
    summary: "Evidence summary for \(id)."
  )
}
