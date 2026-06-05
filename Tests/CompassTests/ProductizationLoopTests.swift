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
          endedAt: 300,
          verdict: .strongPull,
          scores: strongScores
        ),
        makeDecisionAdvisorRecord(
          id: "promote-b",
          experiment: config.experiments[0],
          config: config,
          personaID: "buyer",
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
    let promote = try #require(proposals.first { $0.experimentID == config.experiments[0].id })
    let narrow = try #require(proposals.first { $0.experimentID == config.experiments[1].id })
    let kill = try #require(proposals.first { $0.experimentID == badExperiment.id })

    try #require(promote.update.decision == .promote)
    try #require(promote.update.evidenceRunIDs.first == "promote-a")
    try #require(promote.update.summary.contains("PMF readiness"))
    try #require(narrow.update.decision == .narrow)
    try #require(narrow.update.summary.contains("csv_import"))
    try #require(kill.update.decision == .kill)
    try #require(kill.update.decidedBy == "PMF Decision Advisor")
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
    try #require(firstSignal.pmfLabel.contains("Promote"))
    try #require(firstSignal.urgencyScore > secondSignal.urgencyScore)
    try #require(secondSignal.nextActionKind == .runCohort)
    try #require(secondSignal.pmfLabel == "No current PMF evidence")
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
    try #require(outcome.userMessage.contains("Model-free cohort ran 1 scenario(s)"))
    try #require(outcome.userMessage.contains("Stopped before repeating Run evidence cohort."))
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
    try #require(action.cohortID == nil)
    try #require(savedExperiment.decision == .promote)
    try #require(savedExperiment.evidenceSummary.contains("PMF readiness"))
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
    try #require(readiness.enabledScenarioCount == 1)
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
    try #require(readiness.enabledScenarioCount == 1)
    try #require(readiness.missingTargetCommitCount == 1)
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
  config: ProductizationConfig
) -> ProductizationEvidenceIndex {
  let scores = ProductizationEvidenceScores(
    painRecognition: 5,
    workflowImprovement: 5,
    alternativeAdvantage: 5,
    switchingReadiness: 5,
    continuedUsePull: 5
  )
  let experiment = experiment ?? config.experiments[0]
  return ProductizationEvidenceIndex.build(
    records: [
      makeDecisionAdvisorRecord(
        id: "promote-a",
        experiment: experiment,
        config: config,
        personaID: "operator",
        endedAt: 300,
        verdict: .strongPull,
        scores: scores
      ),
      makeDecisionAdvisorRecord(
        id: "promote-b",
        experiment: experiment,
        config: config,
        personaID: "buyer",
        endedAt: 200,
        verdict: .strongPull,
        scores: scores
      ),
      makeDecisionAdvisorRecord(
        id: "promote-c",
        experiment: experiment,
        config: config,
        personaID: "operator",
        endedAt: 100,
        verdict: .promising,
        scores: scores
      ),
    ]
  )
}

private func makeDecisionAdvisorRecord(
  id: String,
  experiment: ProductExperiment,
  config: ProductizationConfig,
  personaID: String,
  endedAt: Double,
  verdict: ProductizationEvidenceVerdict,
  scores: ProductizationEvidenceScores,
  objections: [String] = [],
  missingCapabilities: [String] = []
) -> ProductizationEvidenceRecord {
  let solution = config.solutionHypotheses.first { $0.id == experiment.solutionID }
  return ProductizationEvidenceRecord(
    id: id,
    experimentID: experiment.id,
    solutionID: experiment.solutionID,
    painID: solution?.painID ?? config.painHypotheses.first?.id ?? "pain",
    branchName: experiment.branchName,
    commitSha: experiment.currentSha ?? experiment.baseSha ?? "head-sha",
    scenarioID: "\(experiment.id)-scenario",
    personaID: personaID,
    mode: .modelFree,
    status: .completed,
    startedAt: endedAt - 10,
    endedAt: endedAt,
    traceHash: "trace-\(id)",
    model: "model-free",
    scores: scores,
    objections: objections,
    missingCapabilities: missingCapabilities,
    currentAlternativeComparison: "Compared against the current workflow.",
    verdict: verdict,
    summary: "Evidence summary for \(id)."
  )
}
