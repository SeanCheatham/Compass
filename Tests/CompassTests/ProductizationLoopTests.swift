import Foundation
import Testing

@testable import Compass

struct ProductizationLoopTests {
  @Test func decisionTransitionValidatorAllowsDocumentedProductizationPath() throws {
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .notRun,
      to: .keepGoing,
      summary: ""
    )
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .keepGoing,
      to: .narrow,
      summary: ""
    )
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .narrow,
      to: .promote,
      summary: "Evidence and Verify support promotion."
    )
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .promote,
      to: .promoted,
      summary: "The promoted experiment has landed."
    )
  }

  @Test func decisionTransitionValidatorRejectsUndocumentedProductizationPath() throws {
    do {
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: "experiment-one",
        from: .pivot,
        to: .promote,
        summary: "Too large a leap."
      )
      Issue.record("Expected pivot -> promote to be rejected.")
    } catch let error as ProductizationDecisionTransitionError {
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
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: "experiment-one",
        from: .keepGoing,
        to: .kill,
        summary: "  "
      )
      Issue.record("Expected kill without summary to be rejected.")
    } catch let error as ProductizationDecisionTransitionError {
      try #require(error == .missingSummary(experimentID: "experiment-one", decision: .kill))
    }
  }

  @Test func reflectDecisionApplierUpdatesExperimentAndDecisionTrail() throws {
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let experiment = config.experiments[0]
    let update = ProductizationReflectDecisionUpdate(
      experimentID: experiment.id,
      decision: .keepGoing,
      summary: "The deterministic run exposed one clear missing capability.",
      evidenceRunIDs: ["run-one"],
      decidedBy: "Reflect"
    )

    let next = try ProductizationReflectDecisionApplier.applying(
      [update],
      to: config,
      now: Date(timeIntervalSince1970: 20)
    )
    let savedExperiment = try #require(next.experiments.first { $0.id == experiment.id })
    let savedDecision = try #require(next.decisions.last)

    try #require(savedExperiment.decision == .keepGoing)
    try #require(savedExperiment.evidenceSummary.contains("missing capability"))
    try #require(savedExperiment.updatedAt == 20)
    try #require(savedDecision.experimentID == experiment.id)
    try #require(savedDecision.decision == .keepGoing)
    try #require(savedDecision.evidenceRunIDs == ["run-one"])
    try #require(savedDecision.decidedBy == "Reflect")
  }

  @Test func pmfDecisionAdvisorProposesValidatedProductTransitions() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[1].decision = .keepGoing
    let badExperiment = ProductExperiment(
      id: "factory-bad-bet",
      solutionID: config.solutionHypotheses[0].id,
      title: "Factory bad bet",
      branchName: "codex/factory-bad-bet",
      worktreeID: "factory-bad-bet",
      baseSha: "base-sha",
      currentSha: "bad-sha",
      prototypeScope: "Try a product shape that may not beat the current workflow.",
      evidenceSummary: "No evidence recorded yet.",
      decision: .keepGoing,
      createdAt: 10
    )
    config.experiments.append(badExperiment)

    let strongScores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let narrowScores = ProductizationEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 3,
      switchingReadiness: 3,
      continuedUsePull: 4
    )
    let weakScores = ProductizationEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductizationEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "promote-a",
          experiment: config.experiments[0],
          config: config,
          personaID: "operator",
          mode: .personaModel,
          endedAt: 300,
          verdict: .strongPull,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "promote-b",
          experiment: config.experiments[0],
          config: config,
          personaID: "buyer",
          mode: .personaModel,
          endedAt: 200,
          verdict: .strongPull,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "promote-c",
          experiment: config.experiments[0],
          config: config,
          personaID: "operator",
          endedAt: 100,
          verdict: .promising,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "narrow-a",
          experiment: config.experiments[1],
          config: config,
          personaID: "operator",
          endedAt: 280,
          verdict: .promising,
          scores: narrowScores,
          missingCapabilities: ["csv_import"]
        ),
        makeDecisionAdvisorRecord(
          id: "narrow-b",
          experiment: config.experiments[1],
          config: config,
          personaID: "buyer",
          endedAt: 270,
          verdict: .unclear,
          scores: narrowScores,
          missingCapabilities: ["csv_import"]
        ),
        makeDecisionAdvisorRecord(
          id: "kill-a",
          experiment: badExperiment,
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
          experiment: badExperiment,
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

    let proposals = ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    )
    let candidates = ProductFactoryDecisionCandidateAdvisor.candidates(
      config: config,
      evidenceIndex: index
    )
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )
    let promote = try #require(proposals.first { $0.experimentID == config.experiments[0].id })
    let narrow = try #require(proposals.first { $0.experimentID == config.experiments[1].id })
    let kill = try #require(proposals.first { $0.experimentID == badExperiment.id })

    try #require(promote.update.decision == .promote)
    try #require(promote.update.evidenceRunIDs.first == "promote-a")
    try #require(promote.update.summary.contains("PMF readiness"))
    try #require(promote.update.summary.contains("current-alternative proof from 2"))
    try #require(narrow.update.decision == .narrow)
    try #require(narrow.update.summary.contains("csv_import"))
    try #require(kill.update.decision == .kill)
    try #require(kill.update.decidedBy == "PMF Decision Advisor")
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
    try #require(digest.contains("Product-factory decision candidates"))
    try #require(digest.contains("action apply_decision"))
    try #require(digest.contains("target_decision promote"))
    try #require(digest.contains("pressure lift"))
    try #require(digest.contains("target_decision kill"))
    try #require(digest.contains("pressure cut"))
    try #require(digest.contains("evidence promote-a"))
    try #require(digest.contains("evidence kill-a"))
  }

  @Test func pmfDecisionAdvisorDefersPromotionWhenEvidenceIsSplit() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let buyerScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == buyerID }
    )
    let operatorScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == operatorID }
    )
    let strongScores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let rejectedScores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let tension = try #require(
      ProductFactoryEvidenceTensionAdvisor.tension(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .promote)
    try #require(readiness.proofDebt.isClear)
    try #require(tension.label == "resolve split PMF evidence")
    try #require(tension.positiveEvidenceRunIDs.first == "split-promote-a")
    try #require(tension.negativeEvidenceRunIDs == ["split-reject-a"])
    try #require(tension.targetPersonaID == buyerID)
    try #require(tension.targetPersonaName == "Budget owner")
    try #require(tension.targetScenarioID == buyerScenario.id)
    try #require(tension.targetCohortID == config.scenarioCohorts[0].id)
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(ProductFactoryDecisionCandidateAdvisor.candidates(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Resolve split PMF evidence")
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetPersonaID == buyerID)
    try #require(action.targetPersonaName == "Budget owner")
    try #require(action.targetScenarioID == buyerScenario.id)
    try #require(action.detail.contains("pull signal"))
    try #require(action.detail.contains("rejection signal"))
    try #require(action.detail.contains(buyerScenario.id))
    try #require(digest.contains("Product-factory evidence tensions"))
    try #require(digest.contains("action resolve_signal_split"))
    try #require(digest.contains("pull split-promote-a"))
    try #require(digest.contains("reject split-reject-a"))
    try #require(digest.contains("target_scenario \(buyerScenario.id)"))
    try #require(digest.contains("target_name Budget owner"))

    do {
      _ = try ProductMarketFitDecisionAdvisor.applyingRecommendedDecision(
        experimentID: experiment.id,
        to: config,
        evidenceIndex: index
      )
      #expect(Bool(false), "Expected split evidence to block automatic PMF promotion.")
    } catch let error as ProductMarketFitDecisionAdvisorError {
      try #require(error == .noProposal(experiment.id))
    }

    let stalledAudit = ProductFactoryCycleAudit(
      id: "factory-cycle-split-stalled",
      startedAt: 700,
      endedAt: 710,
      executedStepIDs: [ProductFactoryCycleFailureAdvisor.stepID(for: action)],
      experimentIDs: [experiment.id],
      messages: ["AI-user target ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
      maxSteps: 3,
      evidenceRunStepCount: 1,
      evidenceRunIDs: ["split-resolution-repeat"],
      completedEvidenceRunCount: 1,
      failedEvidenceRunCount: 0,
      skippedScenarioCount: 0,
      evidenceTensionSummaries: [tension.auditSummary],
      stopReason: .noExecutableStep,
      stopDetail: "Stopped because no executable product-factory step remains.",
      userMessage: "Factory cycle ran 1 step(s). Evidence tensions remained split."
    )
    let stalledConfig = config.recordingFactoryCycleAudit(stalledAudit)
    let learningAudit = try #require(
      ProductFactoryCycleLearningAdvisor.stalledEvidenceTensionAudit(
        for: action,
        experiment: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let stalledAction = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: stalledConfig,
        evidenceIndex: index
      ))
    let blockedStep = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: stalledConfig,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(learningAudit.id == stalledAudit.id)
    try #require(stalledAction.kind == .refineBet)
    try #require(stalledAction.title == "Retarget split PMF evidence")
    try #require(stalledAction.detail.contains(stalledAudit.id))
    try #require(stalledAction.detail.contains("still split") || stalledAction.detail.contains("contradiction"))
    try #require(stalledAction.targetScenarioID == buyerScenario.id)
    try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: stalledConfig,
      evidenceIndex: index,
      isPersonaModelAvailable: true
    ) == nil)
    try #require(!blockedStep.canExecute)
    try #require(blockedStep.action.kind == .refineBet)
    try #require(blockedStep.blockedReason?.contains(stalledAudit.id) == true)
    try #require(blockedStep.blockedReason?.contains("split-evidence") == true)
  }

  @Test func pmfDecisionAdvisorDefersKillWhenEvidenceIsSplit() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let operatorScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == operatorID }
    )
    let buyerScenario = try #require(
      config.scenarios.first { $0.experimentID == experiment.id && $0.segmentID == buyerID }
    )
    let strongScores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let weakScores = ProductizationEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let tension = try #require(
      ProductFactoryEvidenceTensionAdvisor.tension(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.recommendation == .kill)
    try #require(tension.positiveEvidenceRunIDs == ["split-kill-pull"])
    try #require(tension.negativeEvidenceRunIDs == ["split-kill-weak", "split-kill-reject"])
    try #require(tension.targetPersonaID == operatorID)
    try #require(tension.targetScenarioID == operatorScenario.id)
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.title == "Resolve split PMF evidence")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetScenarioID == operatorScenario.id)
  }

  @Test func pmfDecisionAdvisorRequiresAIUserEvidenceBeforeKill() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductizationEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.aiUserCompletedRunCount == 0)
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run AI-user rejection check")
    try #require(action.detail.contains("before stopping the experiment"))
    try #require(action.requiredSimulationMode == .personaModel)
  }

  @Test func pmfDecisionAdvisorRequiresAIUserPersonaBreadthBeforeKill() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductizationEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.aiUserCompletedRunCount == 1)
    try #require(readiness.aiUserDistinctPersonaCount == 1)
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(readiness.rationale.contains { $0.contains("at least 2 personas") })
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run AI-user rejection check")
    try #require(action.detail.contains("requires at least 2"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
  }

  @Test func pmfDecisionAdvisorRequiresCurrentAlternativeProofBeforeKill() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let operatorID = try #require(config.userSegments.first?.id)
    let buyerID = try #require(config.userSegments.dropFirst().first?.id)
    let weakScores = ProductizationEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.aiUserCompletedRunCount == 2)
    try #require(readiness.aiUserDistinctPersonaCount == 2)
    try #require(readiness.aiUserCurrentAlternativePersonaCount == 0)
    try #require(readiness.recommendation == .gatherEvidence)
    try #require(readiness.rationale.contains { $0.contains("current-alternative proof") })
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run AI-user alternative rejection check")
    try #require(action.detail.contains("current-alternative proof"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
  }

  @Test func pmfDecisionAdvisorRequiresAIUserEvidenceBeforePromotion() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let index = makePMFPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includeAIUserEvidence: false
    )

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.aiUserCompletedRunCount == 0)
    try #require(readiness.modelFreeCompletedRunCount == 3)
    try #require(readiness.recommendation == .keepGoing)
    try #require(readiness.rationale.contains { $0.contains("No AI-user evidence") })
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run AI-user validation cohort")
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
  }

  @Test func pmfDecisionAdvisorRequiresAIUserPersonaBreadthBeforePromotion() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let index = makePMFPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includeAIUserEvidence: true,
      includeAIUserPersonaBreadth: false
    )

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.aiUserCompletedRunCount == 1)
    try #require(readiness.aiUserDistinctPersonaCount == 1)
    try #require(readiness.recommendation == .keepGoing)
    try #require(readiness.rationale.contains { $0.contains("at least 2 personas") })
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run AI-user validation cohort")
    try #require(action.detail.contains("requires at least 2"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
  }

  @Test func pmfDecisionAdvisorRequiresCurrentAlternativeProofBeforePromotion() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let index = makePMFPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includeAIUserEvidence: true,
      includeAIUserPersonaBreadth: true,
      includeCurrentAlternativeProof: false
    )

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    try #require(readiness.aiUserCompletedRunCount == 2)
    try #require(readiness.aiUserDistinctPersonaCount == 2)
    try #require(readiness.aiUserCurrentAlternativePersonaCount == 0)
    try #require(readiness.recommendation == .keepGoing)
    try #require(readiness.rationale.contains { $0.contains("current-alternative proof") })
    try #require(ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    ).isEmpty)
    try #require(action.kind == .runCohort)
    try #require(action.title == "Run AI-user alternative challenge")
    try #require(action.detail.contains("current-alternative proof"))
    try #require(action.detail.contains("persona-model scenario"))
    try #require(action.requiredSimulationMode == .personaModel)
  }

  @Test func pmfNextActionRunsTargetedAIUserRationaleSignalProof() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
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
    let scores = ProductizationEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 4
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let signal = try #require(
      ProductFactoryRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let revisionBrief = try #require(
      ProductFactoryRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .keepGoing)
    try #require(signal.rationale.contains("needed proof against the manual workflow"))
    try #require(signal.targetPersonaID == buyer.id)
    try #require(signal.targetScenarioID == buyerScenario.id)
    try #require(signal.targetCohortID == config.scenarioCohorts[0].id)
    try #require(signal.auditSummary.contains("resolve AI-user rationale signal"))
    try #require(signal.auditSummary.contains("target Budget owner"))
    try #require(signal.auditSummary.contains("scenario \(buyerScenario.id)"))
    try #require(signal.auditSummary.contains("runs rationale-buyer"))
    try #require(action.kind == .runCohort)
    try #require(action.title == "Resolve AI-user rationale signal")
    try #require(action.requiredSimulationMode == .personaModel)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetScenarioID == buyerScenario.id)
    try #require(action.detail.contains("Repeated AI-user rationale"))
    try #require(action.detail.contains("before lift/cut"))
    try #require(step.canExecute)
    try #require(step.action.title == "Resolve AI-user rationale signal")
    try #require(revisionBrief.title == "Revise prototype for AI-user rationale")
    try #require(revisionBrief.targetPersonaID == buyer.id)
    try #require(revisionBrief.targetScenarioID == buyerScenario.id)
    try #require(revisionBrief.prototypeChange.contains("proof artifact"))
    try #require(revisionBrief.scenarioChange.contains("Budget owner"))
    try #require(revisionBrief.proofPlan.contains("current alternative"))
    try #require(digest.contains("Product-factory rationale signals"))
    try #require(digest.contains("Product-factory revision briefs"))
    try #require(digest.contains("action revise_product_bet"))
    try #require(digest.contains("prototype"))
    try #require(digest.contains("resolve_rationale_signal"))
    try #require(digest.contains("rationale-buyer"))
  }

  @Test func pmfNextActionRetargetsStalledRationaleSignalAfterCycleAudit() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let experiment = config.experiments[0]
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
    let scores = ProductizationEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 4
    )
    let index = ProductizationEvidenceIndex.build(
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

    let signal = try #require(
      ProductFactoryRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-stalled-rationale",
        startedAt: 350,
        endedAt: 360,
        executedStepIDs: [step.id],
        experimentIDs: [experiment.id],
        messages: ["AI-user rationale target ran 1 scenario(s): 1 completed, 0 needing review."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["rationale-buyer-rerun"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        personaRationaleSignalSummaries: [signal.auditSummary],
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable product-factory step remains.",
        userMessage: "Factory cycle ran 1 step(s). AI-user rationale signal still present."
      )
    )

    let audit = try #require(
      ProductFactoryCycleLearningAdvisor.stalledRationaleSignalAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: index
      ))
    let retarget = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let blockedStep = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))
    let revisionBrief = try #require(
      ProductFactoryRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(audit.id == "factory-cycle-stalled-rationale")
    try #require(retarget.kind == .refineBet)
    try #require(retarget.title == "Retarget AI-user rationale signal")
    try #require(retarget.detail.contains("factory-cycle-stalled-rationale"))
    try #require(retarget.detail.contains("same AI-user rationale target"))
    try #require(retarget.targetPersonaID == buyer.id)
    try #require(retarget.targetScenarioID == buyerScenario.id)
    try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: index,
      isPersonaModelAvailable: true
    ) == nil)
    try #require(blockedStep.kind == .blocked)
    try #require(blockedStep.blockedReason?.contains("same AI-user rationale target") == true)
    try #require(revisionBrief.title == "Retarget product revision for AI-user rationale")
    try #require(revisionBrief.prototypeChange.contains("same rationale survived"))
    try #require(revisionBrief.proofPlan.contains("current alternative"))
    try #require(digest.contains("Retarget AI-user rationale signal"))
    try #require(digest.contains("Retarget product revision for AI-user rationale"))
    try #require(digest.contains("factory-cycle-stalled-rationale"))
    try #require(digest.contains("rationale signals"))
  }

  @Test func revisionBriefDoesNotCompeteWithReadyPMFDecision() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let index = makePMFPromotionEvidenceIndex(
      config: config,
      personaActionRationales: [
        "turn 1 choose valid action compare_current_alternative: Needed proof against the manual workflow before switching."
      ]
    )

    let signal = try #require(
      ProductFactoryRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(signal.count == 3)
    try #require(action.kind == .applyDecision)
    try #require(action.title == "Apply PMF decision")
    try #require(ProductFactoryRevisionBriefAdvisor.brief(
      for: experiment,
      config: config,
      evidenceIndex: index
    ) == nil)
    try #require(!digest.contains("Product-factory revision briefs"))
  }

  @Test func pmfNextActionRefinesRepeatedRationaleSignalBeforeGenericNarrowing() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .narrow
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
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
    let scores = ProductizationEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 3,
      switchingReadiness: 3,
      continuedUsePull: 3
    )
    let index = ProductizationEvidenceIndex.build(
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

    let readiness = try #require(index.currentPMFReadiness(for: experiment))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let signal = ProductFactoryExperimentRanker.signal(
      for: experiment,
      config: config,
      evidenceIndex: index
    )

    try #require(readiness.recommendation == .narrow)
    try #require(action.kind == .refineBet)
    try #require(action.title == "Resolve AI-user rationale signal")
    try #require(action.cohortID == nil)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetScenarioID == buyerScenario.id)
    try #require(action.detail.contains("needed csv import proof"))
    try #require(action.detail.contains("Update the prototype or scenario"))
    try #require(signal.nextActionTitle == "Resolve AI-user rationale signal")
    try #require(signal.pressure == .reshape)
  }

  @Test func pmfNextActionNamesMissingAIUserSegmentInSuggestedCohort() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    let workflow = try #require(config.currentWorkflows.first)
    let alternative = try #require(config.alternatives.first { $0.kind == .doNothing })
    let buyerScenarioID = "\(experiment.id)-buyer-ai-user-check"
    config.scenarios.append(
      ProductScenario(
        id: buyerScenarioID,
        experimentID: experiment.id,
        segmentID: buyer.id,
        currentWorkflowID: workflow.id,
        alternativeID: alternative.id,
        title: "Buyer AI-user check",
        task: "Use the prototype to decide whether the evidence is good enough to sponsor.",
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
    let scores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let index = ProductizationEvidenceIndex.build(
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
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(action.title == "Run AI-user validation cohort")
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetPersonaName == buyer.name)
    try #require(action.targetScenarioID == buyerScenarioID)
    try #require(action.detail.contains("Target AI-user segment: \(buyer.name)"))
    try #require(action.detail.contains("via scenario `\(buyerScenarioID)`"))
    try #require(step.targetScenarioID == buyerScenarioID)
    try #require(step.cohortReadiness?.enabledScenarioCount == 1)
    try #require(step.id.contains(buyerScenarioID))
    try #require(step.detail.contains("targeting \(buyer.name)"))
  }

  @Test func pmfNextActionRedirectsMissingAIUserSegmentToRunnableCohort() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let experiment = config.experiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    config.scenarios.removeAll { $0.experimentID == experiment.id && $0.segmentID == buyer.id }
    for index in config.scenarioCohorts.indices
      where config.scenarioCohorts[index].experimentID == experiment.id
    {
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
    let buyerScenarioID = "\(experiment.id)-buyer-ai-user-check"
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
        title: "Buyer AI-user check",
        task: "Use the prototype to decide whether the evidence is good enough to sponsor.",
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
    let buyerCohortID = "\(experiment.id)-buyer-ai-user-cohort"
    config.scenarioCohorts.append(
      ProductScenarioCohort(
        id: buyerCohortID,
        title: "Buyer AI-user cohort",
        experimentID: experiment.id,
        scenarioIDs: [buyerScenarioID],
        enabled: true,
        tags: ["ai-user"]
      )
    )
    let index = makePMFPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includeAIUserEvidence: true,
      includeAIUserPersonaBreadth: false
    )
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-stalled-broad-ai-user",
        startedAt: 340,
        endedAt: 350,
        executedStepIDs: ["\(experiment.id):run_cohort:\(buyerCohortID)"],
        experimentIDs: [experiment.id],
        messages: ["AI-user cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["broad-ai-user-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 4,
        endingProofDebtCount: 4,
        startingProofDebtSummary:
          "\(experiment.id): 3 completed run(s), 2 persona(s), 1 AI-user persona(s), 1 AI-user current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 3 completed run(s), 2 persona(s), 1 AI-user persona(s), 1 AI-user current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable product-factory step remains.",
        userMessage: "Factory cycle ran 1 step(s). Proof debt held steady (4 -> 4)."
      )
    )

    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
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
    try #require(ProductFactoryCycleLearningAdvisor.stalledProofDebtAudit(
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

  @Test func pmfNextActionBlocksAIUserCohortWhenMissingSegmentHasNoScenario() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let experiment = config.experiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    config.scenarios.removeAll { $0.experimentID == experiment.id && $0.segmentID == buyer.id }
    for index in config.scenarioCohorts.indices
      where config.scenarioCohorts[index].experimentID == experiment.id
    {
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
    let index = makePMFPromotionEvidenceIndex(
      experiment: experiment,
      config: config,
      includeAIUserEvidence: true,
      includeAIUserPersonaBreadth: false
    )

    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(action.kind == .refineBet)
    try #require(action.cohortID == nil)
    try #require(action.targetScenarioID == nil)
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.detail.contains("does not cover a runnable AI-user target"))
    try #require(action.detail.contains("add an enabled scenario"))
    try #require(!step.canExecute)
    try #require(step.kind == .blocked)
    try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: index,
      isPersonaModelAvailable: true
    ) == nil)
  }

  @Test func productFactoryAutopilotBlocksRequiredAIUserCohortWhenUnavailable() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let index = makePMFPromotionEvidenceIndex(
      config: config,
      includeAIUserEvidence: false
    )

    let blocked = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: false
      ))
    let executable = ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: index,
      isPersonaModelAvailable: false
    )
    let available = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index,
        isPersonaModelAvailable: true
      ))

    try #require(executable == nil)
    try #require(!blocked.canExecute)
    try #require(blocked.action.requiredSimulationMode == .personaModel)
    try #require(blocked.blockedReason?.contains("Foundation Models") == true)
    try #require(available.canExecute)
    try #require(available.action.requiredSimulationMode == .personaModel)
  }

  @Test func productFactoryRankerPrioritizesActionablePMFPressure() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    try #require(config.experiments.count >= 2)
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    config.experiments[1].decision = .keepGoing
    config.experiments[1].baseSha = "base-sha"
    config.experiments[1].currentSha = "head-sha"
    let index = makePMFPromotionEvidenceIndex(config: config)

    let ranked = ProductFactoryExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: index
    )
    let firstSignal = ProductFactoryExperimentRanker.signal(
      for: config.experiments[0],
      config: config,
      evidenceIndex: index
    )
    let secondSignal = ProductFactoryExperimentRanker.signal(
      for: config.experiments[1],
      config: config,
      evidenceIndex: index
    )

    try #require(ranked.first?.id == config.experiments[0].id)
    try #require(firstSignal.nextActionKind == .applyDecision)
    try #require(firstSignal.readinessRecommendation == .promote)
    try #require(firstSignal.pressure == .lift)
    try #require(firstSignal.pressureLabel == "Lift pressure")
    try #require(firstSignal.pmfLabel.contains("Promote"))
    try #require(firstSignal.urgencyScore > secondSignal.urgencyScore)
    try #require(secondSignal.nextActionKind == .runCohort)
    try #require(secondSignal.pressure == .learn)
    try #require(secondSignal.pmfLabel == "No current PMF evidence")
  }

  @Test func productFactoryRankerSurfacesPMFProofDebt() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let index = makePMFPromotionEvidenceIndex(
      config: config,
      includeAIUserEvidence: false
    )

    let signal = ProductFactoryExperimentRanker.signal(
      for: config.experiments[0],
      config: config,
      evidenceIndex: index
    )
    let readiness = try #require(index.currentPMFReadiness(for: config.experiments[0]))

    try #require(!readiness.proofDebt.isClear)
    try #require(readiness.proofDebt.aiUserPersonaDeficit == 2)
    try #require(readiness.proofDebt.aiUserCurrentAlternativeDeficit == 2)
    try #require(readiness.rationale.contains { $0.contains("Proof debt") })
    try #require(signal.proofDebtCount == readiness.proofDebt.blockingDebtCount)
    try #require(signal.proofDebtSummary?.contains("AI-user persona") == true)
    try #require(signal.nextActionKind == .runCohort)
    try #require(signal.pressure == .learn)
  }

  @Test func productFactoryAutopilotChoosesExecutablePMFDecision() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let index = makePMFPromotionEvidenceIndex(config: config)

    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))

    try #require(step.canExecute)
    try #require(step.kind == .applyDecision)
    try #require(step.action.kind == .applyDecision)
    try #require(step.experimentID == config.experiments[0].id)
    try #require(step.detail.contains(config.experiments[0].title))
  }

  @Test func productFactoryAutopilotRunsRunnableCohortWhenEvidenceIsMissing() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"

    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    try #require(step.canExecute)
    try #require(step.kind == .runCohort)
    try #require(step.action.kind == .runCohort)
    try #require(step.cohortID == config.scenarioCohorts[0].id)
    try #require(step.cohortReadiness?.canRun == true)
  }

  @Test func productFactoryAutopilotSelectsAIUserCohortsWhenAvailable() throws {
    try #require(
      ProductFactoryAutopilotPlanner.cohortSimulationMode(isPersonaModelAvailable: true)
        == .personaModel
    )
    try #require(
      ProductFactoryAutopilotPlanner.cohortSimulationMode(isPersonaModelAvailable: false)
        == .modelFree
    )
    try #require(ProductizationSimulationMode.personaModel.productFactoryLabel == "AI-user")
    try #require(ProductizationSimulationMode.modelFree.productFactoryLabel == "Model-free")
  }

  @Test func productFactoryAutopilotBlocksRecentlyFailedStep() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let runnable = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-failed-step",
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
          "Factory cycle ran no steps. Stopped because Run evidence cohort failed: contract missing."
      )
    )

    let step = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: .empty
      ))
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: config.experiments[0],
        config: config,
        evidenceIndex: .empty
      ))
    let plan = ProductFactoryAutopilotPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty
    )
    let signal = ProductFactoryExperimentRanker.signal(
      for: config.experiments[0],
      config: config,
      evidenceIndex: .empty
    )

    try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: .empty
    ) == nil)
    try #require(!step.canExecute)
    try #require(step.action.kind == .repairFailures)
    try #require(action.kind == .repairFailures)
    try #require(action.title == "Repair factory cycle failure")
    try #require(action.detail.contains("factory-cycle-failed-step"))
    try #require(action.detail.contains("contract missing"))
    try #require(step.blockedReason?.contains("factory-cycle-failed-step") == true)
    try #require(step.blockedReason?.contains("contract missing") == true)
    try #require(signal.pressure == .repair)
    try #require(signal.nextActionKind == .repairFailures)
    try #require(!plan.canRun)
    try #require(plan.nextBlockedStep?.action.kind == .repairFailures)
  }

  @Test func productFactoryAutopilotClearsFailureBlockAfterCompletedEvidence() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let runnable = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-failed-step",
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
          "Factory cycle ran no steps. Stopped because Run evidence cohort failed: contract missing."
      )
    )
    let evidenceIndex = ProductizationEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "repair-run",
          experiment: config.experiments[0],
          config: config,
          personaID: "operator",
          endedAt: 120,
          verdict: .promising,
          scores: ProductizationEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])

    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))

    try #require(step.id == runnable.id)
    try #require(step.canExecute)
    try #require(step.blockedReason == nil)
  }

  @Test func productFactoryAutopilotRetargetsBroadCohortWhenProofDebtStalls() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let experiment = config.experiments[0]
    let evidenceIndex = ProductizationEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "first-pass",
          experiment: experiment,
          config: config,
          personaID: config.userSegments[0].id,
          endedAt: 30,
          verdict: .promising,
          scores: ProductizationEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])
    let broadStep = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    try #require(broadStep.action.kind == .runCohort)
    try #require(broadStep.action.targetScenarioID == nil)
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-stalled-proof",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [broadStep.id],
        experimentIDs: [experiment.id],
        messages: ["Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["first-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 6,
        endingProofDebtCount: 6,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 AI-user persona(s), 0 AI-user current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 AI-user persona(s), 0 AI-user current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable product-factory step remains.",
        userMessage: "Factory cycle ran 1 step(s). Proof debt held steady (6 -> 6)."
      )
    )

    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let audit = try #require(
      ProductFactoryCycleLearningAdvisor.stalledProofDebtAudit(
        for: broadStep.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ))
    let proofTarget = try #require(
      ProductFactoryProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )

    try #require(audit.id == "factory-cycle-stalled-proof")
    try #require(action.kind == .runCohort)
    try #require(action.title == "Retarget AI-user proof debt")
    try #require(action.detail.contains("factory-cycle-stalled-proof"))
    try #require(action.detail.contains("without reducing proof debt"))
    try #require(action.detail.contains("targeted persona-model scenario"))
    try #require(action.detail.contains("Remaining proof debt"))
    try #require(action.requiredSimulationMode == .personaModel)
    let targetScenarioID = try #require(action.targetScenarioID)
    try #require(proofTarget.label == "run targeted AI-user persona proof")
    try #require(proofTarget.displayTitle == "run targeted AI-user persona proof")
    try #require(proofTarget.displaySubtitle.contains("score 48/100"))
    try #require(proofTarget.displaySubtitle.contains("target Budget owner"))
    try #require(proofTarget.displayDetail.contains("Debt:"))
    try #require(proofTarget.displayDetail.contains("Next: Retarget AI-user proof debt"))
    try #require(proofTarget.nextActionTitle == "Retarget AI-user proof debt")
    try #require(proofTarget.targetScenarioID == targetScenarioID)
    try #require(proofTarget.targetPersonaName == "Budget owner")
    try #require(proofTarget.requiredSimulationMode == .personaModel)
    let executable = try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: true
    ))
    try #require(executable.canExecute)
    try #require(step.canExecute)
    try #require(step.kind == .runCohort)
    try #require(step.action.kind == .runCohort)
    try #require(step.targetScenarioID == targetScenarioID)
    try #require(digest.contains("Product-factory proof targets"))
    try #require(digest.contains("target run targeted AI-user persona proof"))
    try #require(digest.contains("Retarget AI-user proof debt"))
    try #require(digest.contains("factory-cycle-stalled-proof"))
    try #require(digest.contains("target_scenario \(targetScenarioID)"))
    try #require(digest.contains("target_name Budget owner"))
    try #require(digest.contains("required_mode persona_model"))
    try #require(digest.contains("proof debt 6 -> 6 (0)"))

    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-stalled-target",
        startedAt: 120,
        endedAt: 130,
        executedStepIDs: [step.id],
        experimentIDs: [experiment.id],
        messages: ["AI-user target ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["buyer-ai-user-stalled"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 6,
        endingProofDebtCount: 6,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 AI-user persona(s), 0 AI-user current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 0 AI-user persona(s), 0 AI-user current-alternative proof(s)",
        proofTargetSummaries: [proofTarget.auditSummary],
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable product-factory step remains.",
        userMessage: "Factory cycle ran 1 step(s). Proof debt held steady (6 -> 6)."
      )
    )

    let stalledTargetAudit = try #require(
      ProductFactoryCycleLearningAdvisor.stalledProofTargetAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let blockedStep = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: true
      ))

    try #require(stalledTargetAudit.id == "factory-cycle-stalled-target")
    try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: true
    ) == nil)
    try #require(!blockedStep.canExecute)
    try #require(blockedStep.targetScenarioID == targetScenarioID)
    try #require(blockedStep.blockedReason?.contains("already attempted this proof target") == true)
    try #require(blockedStep.blockedReason?.contains("change the scenario") == true)
  }

  @Test func productFactoryAutopilotFallsBackWhenStalledProofDebtHasNoAIUserTarget() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    for index in config.experiments.indices.dropFirst() {
      config.experiments[index].decision = .promoted
    }
    let experiment = config.experiments[0]
    let operatorID = config.userSegments[0].id
    let buyer = try #require(config.userSegments.dropFirst().first)
    config.scenarios.removeAll {
      $0.experimentID == experiment.id && $0.segmentID != operatorID
    }
    for index in config.scenarioCohorts.indices
      where config.scenarioCohorts[index].experimentID == experiment.id
    {
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
    let evidenceIndex = ProductizationEvidenceIndex.build(
      records: [
        makeDecisionAdvisorRecord(
          id: "operator-ai-user-pass",
          experiment: experiment,
          config: config,
          personaID: operatorID,
          mode: .personaModel,
          endedAt: 30,
          verdict: .promising,
          scores: ProductizationEvidenceScores(
            painRecognition: 4,
            workflowImprovement: 4,
            alternativeAdvantage: 3,
            switchingReadiness: 3,
            continuedUsePull: 3
          )
        )
      ])
    let broadStep = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-stalled-no-target",
        startedAt: 100,
        endedAt: 110,
        executedStepIDs: [broadStep.id],
        experimentIDs: [experiment.id],
        messages: ["AI-user cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["operator-ai-user-pass"],
        completedEvidenceRunCount: 1,
        failedEvidenceRunCount: 0,
        skippedScenarioCount: 0,
        startingProofDebtCount: 4,
        endingProofDebtCount: 4,
        startingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 1 AI-user persona(s), 1 AI-user current-alternative proof(s)",
        endingProofDebtSummary:
          "\(experiment.id): 1 completed run(s), 1 persona(s), 1 AI-user persona(s), 1 AI-user current-alternative proof(s)",
        stopReason: .noExecutableStep,
        stopDetail: "Stopped because no executable product-factory step remains.",
        userMessage: "Factory cycle ran 1 step(s). Proof debt held steady (4 -> 4)."
      )
    )

    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let proofTarget = try #require(
      ProductFactoryProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ))
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: evidenceIndex
    )

    try #require(action.kind == .refineBet)
    try #require(action.title == "Retarget AI-user proof debt")
    try #require(action.targetPersonaID == buyer.id)
    try #require(action.targetScenarioID == nil)
    try #require(action.detail.contains("factory-cycle-stalled-no-target"))
    try #require(action.detail.contains("does not cover a runnable AI-user target"))
    try #require(action.detail.contains("add an enabled scenario"))
    try #require(proofTarget.label == "add or enable runnable AI-user proof")
    try #require(proofTarget.displayTitle == "add or enable runnable AI-user proof")
    try #require(proofTarget.displaySubtitle.contains("target Budget owner"))
    try #require(proofTarget.displayDetail.contains("Persona: Budget owner"))
    try #require(proofTarget.nextActionTitle == "Retarget AI-user proof debt")
    try #require(proofTarget.targetPersonaID == buyer.id)
    try #require(proofTarget.targetPersonaName == "Budget owner")
    try #require(proofTarget.targetScenarioID == nil)
    try #require(proofTarget.requiredSimulationMode == .personaModel)
    try #require(ProductFactoryAutopilotPlanner.nextExecutableStep(
      config: config,
      evidenceIndex: evidenceIndex
    ) == nil)
    try #require(step.kind == .blocked)
    try #require(step.action.kind == .refineBet)
    try #require(digest.contains("Product-factory proof targets"))
    try #require(digest.contains("target add or enable runnable AI-user proof"))
    try #require(digest.contains("target_persona \(buyer.id)"))
    try #require(digest.contains("target_name Budget owner"))
    try #require(digest.contains("required_mode persona_model"))
  }

  @Test func productFactoryAutopilotCyclePlanCapsExecutableSteps() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    for index in config.experiments.indices {
      config.experiments[index].decision = .keepGoing
      config.experiments[index].baseSha = "base-\(index)"
      config.experiments[index].currentSha = "head-\(index)"
    }

    let plan = ProductFactoryAutopilotPlanner.cyclePlan(
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

  @Test func productFactoryAutopilotCyclePlanReportsBlockedStep() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing

    let plan = ProductFactoryAutopilotPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty
    )

    try #require(!plan.canRun)
    try #require(plan.executableSteps.isEmpty)
    let blocked = try #require(plan.nextBlockedStep)
    try #require(blocked.kind == .runCohort)
    try #require(blocked.blockedReason?.contains("target commit") == true)
    try #require(plan.summary.contains("No executable factory steps"))
    try #require(plan.queueSummary.contains("Blocked:"))
    try #require(plan.queueSummary.contains("target commit"))
  }

  @Test func productFactoryAutopilotCycleOutcomeReportsRepeatStop() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    let outcome = ProductFactoryAutopilotCycleOutcome(
      executedSteps: [step],
      messages: ["Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
      maxSteps: 3,
      stopReason: .repeatedStep(stepID: step.id, title: step.title)
    )

    try #require(outcome.userMessage.contains("Factory cycle ran 1 step(s)."))
    try #require(outcome.userMessage.contains("0 PMF decision(s) applied"))
    try #require(outcome.userMessage.contains("1 evidence step(s)"))
    try #require(outcome.userMessage.contains("Model-free cohort ran 1 scenario(s)"))
    try #require(outcome.userMessage.contains("Stopped before repeating Run evidence cohort."))
  }

  @Test func productFactoryAutopilotCycleOutcomeCountsLiftAndCutDecisions() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let index = makePMFPromotionEvidenceIndex(config: config)
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: index
      ))
    let candidate = try #require(
      ProductFactoryDecisionCandidateAdvisor.candidates(
        config: config,
        evidenceIndex: index
      ).first { $0.experimentID == step.experimentID }
    )

    let outcome = ProductFactoryAutopilotCycleOutcome(
      executedSteps: [step],
      messages: ["Applied PMF advice for \(step.experimentTitle)."],
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
    try #require(outcome.userMessage.contains("1 PMF decision(s) applied (1 promote, 0 kill)"))
    try #require(outcome.userMessage.contains("Decision candidates:"))
    try #require(outcome.userMessage.contains("continue -> promote"))
    try #require(outcome.userMessage.contains("AI-user rationale signals:"))
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
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: config.recordingFactoryCycleAudit(audit),
      evidenceIndex: index
    )
    try #require(digest.contains("Recent product-factory cycle audits"))
    try #require(digest.contains("decision candidates"))
    try #require(digest.contains("pressure lift"))
    try #require(digest.contains("continue -> promote"))
    try #require(digest.contains("rationale signals"))
    try #require(digest.contains("needed import proof before switching"))
  }

  @Test func productFactoryAutopilotCycleOutcomeReportsFailureStop() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    let outcome = ProductFactoryAutopilotCycleOutcome(
      executedSteps: [],
      messages: [],
      maxSteps: 3,
      stopReason: .executionFailed(
        stepID: step.id,
        title: step.title,
        message: "Command timed out while simulating the buyer."
      )
    )

    try #require(outcome.userMessage.contains("Factory cycle ran no steps."))
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

  @Test func productFactoryAutopilotCycleOutcomeBuildsDurableAudit() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let step = try #require(
      ProductFactoryAutopilotPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))
    let outcome = ProductFactoryAutopilotCycleOutcome(
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
      evidenceTensionSummaries: [
        "\(step.experimentID): resolve split PMF evidence; score 82/100; strong_pull vs rejected; target Budget owner"
      ],
      proofTargetSummaries: [
        "\(step.experimentID): broaden completed persona coverage; debt 2 completed run(s), 2 persona(s)"
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
    try #require(audit.evidenceTensionSummaries[0].contains("resolve split PMF evidence"))
    try #require(audit.proofTargetSummaries.count == 1)
    try #require(audit.proofTargetSummaries[0].contains("broaden completed persona coverage"))
    try #require(audit.stopReason == .noExecutableStep)
    try #require(audit.userMessage.contains("Factory cycle ran 1 step(s)."))
    try #require(audit.userMessage.contains("evidence runs 1 completed, 0 needing review"))
    try #require(audit.userMessage.contains("Evidence tensions:"))
    try #require(audit.userMessage.contains("Proof targets:"))
    try #require(audit.userMessage.contains("Proof debt improved by 2"))
    try #require(audit.summary.contains("runs run-one"))
    try #require(audit.summary.contains("proof debt 8 -> 6 (-2)"))
    try #require(audit.summary.contains("tensions"))
    try #require(audit.summary.contains("resolve split PMF evidence"))
    try #require(audit.summary.contains("targets"))
    try #require(audit.summary.contains("broaden completed persona coverage"))
    try #require(audit.userMessage.contains("Stopped because no executable product-factory step remains."))
  }

  @Test func pmfDecisionAdvisorAppliesRecommendedDecisionThroughReflectRules() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let index = makePMFPromotionEvidenceIndex(config: config)
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: index
      ))

    let next = try ProductMarketFitDecisionAdvisor.applyingRecommendedDecision(
      experimentID: experiment.id,
      to: config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 400)
    )
    let savedExperiment = try #require(next.experiments.first { $0.id == experiment.id })
    let decision = try #require(next.decisions.last)

    try #require(action.kind == .applyDecision)
    try #require(action.title == "Apply PMF decision")
    try #require(action.detail.contains("continue -> promote"))
    try #require(action.targetDecision == .promote)
    try #require(action.cohortID == nil)
    try #require(savedExperiment.decision == .promote)
    try #require(savedExperiment.evidenceSummary.contains("PMF readiness"))
    try #require(savedExperiment.evidenceSummary.contains("current-alternative proof"))
    try #require(decision.decision == .promote)
    try #require(decision.evidenceRunIDs == ["promote-a", "promote-b", "promote-c"])
    try #require(decision.decidedBy == "PMF Decision Advisor")
    try #require(decision.beforeSha == experiment.currentSha)
    try #require(decision.afterSha == experiment.currentSha)
  }

  @Test func pmfDecisionAdvisorDoesNotPromoteFromStaleEvidence() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    var staleExperiment = config.experiments[0]
    staleExperiment.currentSha = "old-sha"
    let index = makePMFPromotionEvidenceIndex(experiment: staleExperiment, config: config)

    let proposals = ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: index
    )
    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: config.experiments[0],
        config: config,
        evidenceIndex: index
      ))

    try #require(proposals.isEmpty)
    try #require(action.kind == .rerunCohort)
    try #require(action.title == "Rerun current evidence")
    try #require(action.detail.contains("stale run"))
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    do {
      _ = try ProductMarketFitDecisionAdvisor.applyingRecommendedDecision(
        experimentID: config.experiments[0].id,
        to: config,
        evidenceIndex: index
      )
      #expect(Bool(false), "Expected stale evidence to produce no PMF proposal.")
    } catch let error as ProductMarketFitDecisionAdvisorError {
      try #require(error == .noProposal(config.experiments[0].id))
    }
  }

  @Test func pmfNextActionTargetsRunnableCohortBeforeEvidenceExists() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]

    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: .empty
      ))

    try #require(action.kind == .runCohort)
    try #require(action.title == "Run productization cohort")
    try #require(action.cohortID == config.scenarioCohorts[0].id)
    try #require(action.detail.contains(config.scenarioCohorts[0].id))

    let readiness = try #require(
      ProductMarketFitNextActionAdvisor.cohortRunReadiness(
        for: action,
        experiment: experiment,
        config: config
      ))
    try #require(readiness.canRun)
    try #require(readiness.cohortID == config.scenarioCohorts[0].id)
    try #require(readiness.enabledScenarioCount == 2)
    try #require(readiness.missingTargetCommitCount == 0)
  }

  @Test func pmfNextActionAsksForEvidenceCohortWhenNoneIsRunnable() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
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
      ProductMarketFitNextActionAdvisor.nextAction(
        for: config.experiments[0],
        config: config,
        evidenceIndex: .empty
      ))

    try #require(action.kind == .refineBet)
    try #require(action.title == "Define evidence cohort")
    try #require(action.cohortID == nil)
  }

  @Test func pmfSuggestedCohortReadinessBlocksMissingTargetCommit() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    let experiment = config.experiments[0]

    let action = try #require(
      ProductMarketFitNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: .empty
      ))
    let readiness = try #require(
      ProductMarketFitNextActionAdvisor.cohortRunReadiness(
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

  @Test func rolloutWorkflowPromotesExperimentWithBranchCommitAndEvidenceTrail() throws {
    let config = makeRolloutConfig(decision: .keepGoing)
    let experiment = config.experiments[0]
    let evidenceIndex = makeRolloutEvidenceIndex(config: config)

    try #require(ProductExperimentRolloutWorkflow.canApply(.promoteOrConfirm, to: experiment))

    let marked = try ProductExperimentRolloutWorkflow.applying(
      .promoteOrConfirm,
      experimentID: experiment.id,
      to: config,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 50),
      decidedBy: "Workbench"
    )
    let readyExperiment = try #require(marked.experiments.first { $0.id == experiment.id })
    let readyDecision = try #require(marked.decisions.last)

    try #require(readyExperiment.decision == .promote)
    try #require(readyDecision.decision == .promote)
    try #require(readyDecision.branchName == experiment.branchName)
    try #require(readyDecision.beforeSha == experiment.currentSha)
    try #require(readyDecision.afterSha == experiment.currentSha)
    try #require(readyDecision.evidenceRunIDs == ["rollout-run"])
    try #require(readyDecision.decidedBy == "Workbench")

    let promoted = try ProductExperimentRolloutWorkflow.applying(
      .promoteOrConfirm,
      experimentID: experiment.id,
      to: marked,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 60),
      decidedBy: "Workbench"
    )
    let promotedExperiment = try #require(promoted.experiments.first { $0.id == experiment.id })
    let promotedSolution = try #require(
      promoted.solutionHypotheses.first { $0.id == experiment.solutionID }
    )
    let promotedDecision = try #require(promoted.decisions.last)

    try #require(promotedExperiment.decision == .promoted)
    try #require(promotedSolution.status == .promoted)
    try #require(promotedDecision.decision == .promoted)
    try #require(promotedDecision.evidenceRunIDs == ["rollout-run"])
  }

  @Test func rolloutWorkflowKillsThenArchivesWithoutDeletingExperimentLineage() throws {
    let config = makeRolloutConfig(decision: .keepGoing)
    let experiment = config.experiments[0]
    let evidenceIndex = makeRolloutEvidenceIndex(config: config)

    try #require(ProductExperimentRolloutWorkflow.canApply(.killOrArchive, to: experiment))

    let killed = try ProductExperimentRolloutWorkflow.applying(
      .killOrArchive,
      experimentID: experiment.id,
      to: config,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 70),
      decidedBy: "Workbench"
    )
    let killedExperiment = try #require(killed.experiments.first { $0.id == experiment.id })
    let rejectedSolution = try #require(
      killed.solutionHypotheses.first { $0.id == experiment.solutionID }
    )

    try #require(killedExperiment.decision == .kill)
    try #require(killedExperiment.branchName == experiment.branchName)
    try #require(killedExperiment.worktreeID == experiment.worktreeID)
    try #require(rejectedSolution.status == .rejected)

    let archived = try ProductExperimentRolloutWorkflow.applying(
      .killOrArchive,
      experimentID: experiment.id,
      to: killed,
      evidenceIndex: evidenceIndex,
      now: Date(timeIntervalSince1970: 80),
      decidedBy: "Workbench"
    )
    let archivedExperiment = try #require(archived.experiments.first { $0.id == experiment.id })
    let parkedSolution = try #require(
      archived.solutionHypotheses.first { $0.id == experiment.solutionID }
    )
    let archiveDecision = try #require(archived.decisions.last)

    try #require(archivedExperiment.decision == .archived)
    try #require(archivedExperiment.branchName == experiment.branchName)
    try #require(archivedExperiment.worktreeID == experiment.worktreeID)
    try #require(parkedSolution.status == .parked)
    try #require(archiveDecision.decision == .archived)
    try #require(archiveDecision.branchName == experiment.branchName)
    try #require(archiveDecision.beforeSha == experiment.currentSha)
    try #require(archiveDecision.afterSha == experiment.currentSha)
  }
}

private func makeRolloutConfig(decision: ProductExperimentDecision) -> ProductizationConfig {
  var config = ProductizationConfig.seedDefaults(
    projectTitle: "Factory",
    rawPain: "Factory users need better product bet evidence.",
    now: Date(timeIntervalSince1970: 10)
  )
  config.experiments[0].decision = decision
  config.experiments[0].baseSha = "base-sha"
  config.experiments[0].currentSha = "head-sha"
  return config
}

private func makeRolloutEvidenceIndex(config: ProductizationConfig) -> ProductizationEvidenceIndex {
  let record = ProductizationEvidenceRecord(
    id: "rollout-run",
    experimentID: config.experiments[0].id,
    solutionID: config.solutionHypotheses[0].id,
    painID: config.painHypotheses[0].id,
    branchName: config.experiments[0].branchName,
    commitSha: config.experiments[0].currentSha ?? "head-sha",
    scenarioID: "scenario-one",
    personaID: config.userSegments[0].id,
    mode: .modelFree,
    status: .completed,
    startedAt: 20,
    endedAt: 30,
    traceHash: "trace-rollout",
    model: "model-free",
    scores: ProductizationEvidenceScores(
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
  return ProductizationEvidenceIndex.build(records: [record])
}

private func makePMFPromotionEvidenceIndex(
  experiment: ProductExperiment? = nil,
  config: ProductizationConfig,
  includeAIUserEvidence: Bool = true,
  includeAIUserPersonaBreadth: Bool = true,
  includeCurrentAlternativeProof: Bool = true,
  personaActionRationales: [String] = []
) -> ProductizationEvidenceIndex {
  let scores = ProductizationEvidenceScores(
    painRecognition: 5,
    workflowImprovement: 5,
    alternativeAdvantage: 5,
    switchingReadiness: 5,
    continuedUsePull: 5
  )
  let experiment = experiment ?? config.experiments[0]
  let operatorID = config.userSegments.first?.id ?? "operator"
  let buyerID = config.userSegments.dropFirst().first?.id ?? "buyer"
  let comparison = includeCurrentAlternativeProof ? "Compared against the current workflow." : ""
  return ProductizationEvidenceIndex.build(
    records: [
      makeDecisionAdvisorRecord(
        id: "promote-a",
        experiment: experiment,
        config: config,
        personaID: operatorID,
        mode: includeAIUserEvidence ? .personaModel : .modelFree,
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
        mode: includeAIUserEvidence && includeAIUserPersonaBreadth ? .personaModel : .modelFree,
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
  experiment: ProductExperiment,
  config: ProductizationConfig,
  personaID: String,
  mode: ProductizationSimulationMode = .modelFree,
  endedAt: Double,
  verdict: ProductizationEvidenceVerdict,
  scores: ProductizationEvidenceScores,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  currentAlternativeComparison: String = "Compared against the current workflow.",
  scenarioID: String? = nil,
  personaActionRationales: [String] = []
) -> ProductizationEvidenceRecord {
  let solution = config.solutionHypotheses.first { $0.id == experiment.solutionID }
  return ProductizationEvidenceRecord(
    id: id,
    experimentID: experiment.id,
    solutionID: experiment.solutionID,
    painID: solution?.painID ?? config.painHypotheses.first?.id ?? "pain",
    branchName: experiment.branchName,
    commitSha: experiment.currentSha ?? experiment.baseSha ?? "head-sha",
    scenarioID: scenarioID ?? "\(experiment.id)-scenario",
    personaID: personaID,
    mode: mode,
    status: .completed,
    startedAt: endedAt - 10,
    endedAt: endedAt,
    traceHash: "trace-\(id)",
    model: mode == .modelFree ? "model-free" : "gpt-test",
    scores: scores,
    objections: objections,
    missingCapabilities: missingCapabilities,
    currentAlternativeComparison: currentAlternativeComparison,
    personaActionRationales: personaActionRationales,
    verdict: verdict,
    summary: "Evidence summary for \(id)."
  )
}
