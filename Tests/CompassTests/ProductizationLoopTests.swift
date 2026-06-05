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
