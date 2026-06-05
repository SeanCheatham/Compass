import Foundation
import Testing

@testable import Compass

struct ProductizationEvidenceStoreTests {
  @Test func storeWritesRunDirectoryArtifactsAndIndex() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    let record = makeEvidenceRecord(id: "run-one")
    let stored = try workspace.writeProductizationEvidenceRecord(
      record,
      traceJSON: #"{"trace":true}"#,
      feedbackJSON: #"{"feedback":true}"#,
      transcriptJSONL: #"{"turn":0}"#,
      summaryMarkdown: "summary"
    )

    try #require(stored.traceArtifactPath == "productization/runs/run-one/trace.json")
    try #require(stored.feedbackArtifactPath == "productization/runs/run-one/feedback.json")
    try #require(stored.transcriptArtifactPath == "productization/runs/run-one/transcript.jsonl")
    try #require(stored.summaryArtifactPath == "productization/runs/run-one/summary.md")
    try #require(
      FileManager.default.fileExists(
        atPath: workspace.productizationURL.appending(path: "evidence-index.json").path))
    let read = try workspace.readProductizationEvidenceRecord(id: "run-one")
    try #require(read == stored)
    try #require(workspace.readProductizationEvidenceIndex().summaries.map(\.runID) == ["run-one"])
  }

  @Test func indexAggregatesExperimentEvidenceSignals() throws {
    let first = makeEvidenceRecord(
      id: "first",
      endedAt: 100,
      verdict: .weak,
      objections: ["Spreadsheet is already familiar", "Spreadsheet is already familiar"],
      missingCapabilities: ["import_csv"],
      comparison: "Lost to the current spreadsheet."
    )
    let second = makeEvidenceRecord(
      id: "second",
      endedAt: 200,
      verdict: .promising,
      objections: ["Spreadsheet is already familiar"],
      missingCapabilities: ["import_csv", "permissions"],
      comparison: "Beat the spreadsheet for review speed."
    )
    let failure = makeEvidenceRecord(
      id: "failure",
      experimentID: "experiment-two",
      status: .appCommandFailed,
      endedAt: 150,
      verdict: .rejected,
      missingCapabilities: ["runtime"],
      failure: ProductizationRunFailure(
        status: .appCommandFailed,
        message: "cargo failed"
      )
    )

    let index = ProductizationEvidenceIndex.build(records: [first, second, failure])

    try #require(index.aggregate.latestRunByExperiment["experiment-one"] == "second")
    try #require(
      index.aggregate.repeatedObjections.first?.objection == "spreadsheet is already familiar")
    try #require(index.aggregate.missingCapabilityFrequency.first?.capabilityID == "import_csv")
    try #require(index.aggregate.verdictCounts["promising"] == 1)
    try #require(index.aggregate.failuresByKind["appCommandFailed"] == 1)
    try #require(
      index.aggregate.currentAlternativeComparisons.contains {
        $0.comparison.contains("Beat the spreadsheet")
      })
  }

  @Test func indexBuildsProductMarketFitReadinessRecommendations() throws {
    let strongScores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let weakScores = ProductizationEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let narrowScores = ProductizationEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 3,
      switchingReadiness: 3,
      continuedUsePull: 4
    )
    let records = [
      makeEvidenceRecord(
        id: "strong-a",
        experimentID: "good-experiment",
        personaID: "operator",
        mode: .personaModel,
        endedAt: 300,
        verdict: .strongPull,
        scores: strongScores
      ),
      makeEvidenceRecord(
        id: "strong-b",
        experimentID: "good-experiment",
        personaID: "buyer",
        mode: .personaModel,
        endedAt: 200,
        verdict: .strongPull,
        scores: strongScores
      ),
      makeEvidenceRecord(
        id: "strong-c",
        experimentID: "good-experiment",
        personaID: "operator",
        endedAt: 100,
        verdict: .promising,
        scores: strongScores
      ),
      makeEvidenceRecord(
        id: "weak-a",
        experimentID: "bad-experiment",
        personaID: "operator",
        mode: .personaModel,
        endedAt: 220,
        verdict: .weak,
        objections: ["No reason to switch"],
        comparison: "Lost to the current workflow.",
        scores: weakScores
      ),
      makeEvidenceRecord(
        id: "weak-b",
        experimentID: "bad-experiment",
        personaID: "buyer",
        mode: .personaModel,
        endedAt: 210,
        verdict: .rejected,
        objections: ["No reason to switch"],
        comparison: "Buyer rejected the bet.",
        scores: weakScores
      ),
      makeEvidenceRecord(
        id: "narrow-a",
        experimentID: "narrow-experiment",
        personaID: "operator",
        endedAt: 180,
        verdict: .promising,
        missingCapabilities: ["csv_import"],
        scores: narrowScores
      ),
      makeEvidenceRecord(
        id: "narrow-b",
        experimentID: "narrow-experiment",
        personaID: "buyer",
        endedAt: 170,
        verdict: .unclear,
        missingCapabilities: ["csv_import"],
        scores: narrowScores
      ),
    ]

    let readiness = ProductizationEvidenceIndex.build(records: records)
      .aggregate.pmfReadinessByExperiment
    let good = try #require(readiness.first { $0.experimentID == "good-experiment" })
    let bad = try #require(readiness.first { $0.experimentID == "bad-experiment" })
    let narrow = try #require(readiness.first { $0.experimentID == "narrow-experiment" })

    try #require(good.recommendation == .promote)
    try #require(good.readinessScore >= 76)
    try #require(good.aiUserCompletedRunCount == 2)
    try #require(good.aiUserDistinctPersonaCount == 2)
    try #require(good.currentAlternativeComparisonCount == 3)
    try #require(good.aiUserCurrentAlternativePersonaCount == 2)
    try #require(good.modelFreeCompletedRunCount == 1)
    try #require(good.distinctPersonaCount == 2)
    try #require(good.evidenceRunIDs.first == "strong-a")
    try #require(good.proofDebt.isClear)
    try #require(good.proofDebt.summary == "proof complete")
    try #require(good.rationale.contains { $0.contains("2 AI-user run(s) across 2 persona(s)") })
    try #require(good.rationale.contains { $0.contains("Average PMF score") })

    try #require(bad.recommendation == .kill)
    try #require(bad.aiUserCompletedRunCount == 2)
    try #require(bad.aiUserDistinctPersonaCount == 2)
    try #require(bad.aiUserCurrentAlternativePersonaCount == 2)
    try #require(bad.proofDebt.isClear)
    try #require(bad.readinessScore <= 30)
    try #require(bad.rationale.contains { $0.contains("Repeated objections") })

    try #require(narrow.recommendation == .narrow)
    try #require(narrow.proofDebt.aiUserPersonaDeficit == 2)
    try #require(narrow.proofDebt.aiUserCurrentAlternativeDeficit == 2)
    try #require(narrow.proofDebt.summary.contains("AI-user persona"))
    try #require(narrow.rationale.contains { $0.contains("Missing capabilities") })
    try #require(narrow.rationale.contains { $0.contains("Proof debt") })
  }

  @Test func currentCommitReadinessIgnoresStaleExperimentEvidence() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let strongScores = ProductizationEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let records = [
      makeEvidenceRecord(
        id: "old-a",
        experimentID: experiment.id,
        commitSha: "old-sha",
        personaID: "operator",
        endedAt: 300,
        verdict: .strongPull,
        scores: strongScores
      ),
      makeEvidenceRecord(
        id: "old-b",
        experimentID: experiment.id,
        commitSha: "old-sha",
        personaID: "buyer",
        endedAt: 200,
        verdict: .strongPull,
        scores: strongScores
      ),
      makeEvidenceRecord(
        id: "current-a",
        experimentID: experiment.id,
        commitSha: "head-sha",
        personaID: "operator",
        endedAt: 100,
        verdict: .promising,
        scores: strongScores
      ),
    ]

    let index = ProductizationEvidenceIndex.build(records: records)
    let readiness = try #require(index.currentPMFReadiness(for: experiment))

    try #require(index.staleSummaryCount(for: experiment) == 2)
    try #require(index.summaries(for: experiment).map(\.runID) == ["current-a"])
    try #require(readiness.runCount == 1)
    try #require(readiness.evidenceRunIDs == ["current-a"])
    try #require(
      index.aggregate.pmfReadinessByExperiment.first { $0.experimentID == experiment.id }?
        .evidenceRunIDs.first == "old-a")
  }

  @Test func planningDigestIncludesBoundedProductizationEvidence() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config = config.recordingFactoryCycleAudit(
      ProductFactoryCycleAudit(
        id: "factory-cycle-digest",
        startedAt: 40,
        endedAt: 45,
        executedStepIDs: ["step-run-cohort"],
        experimentIDs: [config.experiments[0].id],
        messages: ["Model-free cohort ran 1 scenario(s): 0 completed, 1 needing review, 0 skipped."],
        maxSteps: 3,
        evidenceRunStepCount: 1,
        evidenceRunIDs: ["digest-run"],
        completedEvidenceRunCount: 0,
        failedEvidenceRunCount: 1,
        skippedScenarioCount: 0,
        startingProofDebtCount: 8,
        endingProofDebtCount: 7,
        startingProofDebtSummary:
          "\(config.experiments[0].id): 2 completed run(s), 2 persona(s), 2 AI-user persona(s), 2 AI-user current-alternative proof(s)",
        endingProofDebtSummary:
          "\(config.experiments[0].id): 1 completed run(s), 2 persona(s), 2 AI-user persona(s), 2 AI-user current-alternative proof(s)",
        stopReason: .executionFailed,
        stopDetail: "Stopped because Run evidence cohort failed: contract missing.",
        userMessage:
          "Factory cycle ran 1 step(s). Model-free cohort ran 1 scenario(s): 0 completed, 1 needing review, 0 skipped. Stopped because Run evidence cohort failed: contract missing."
      )
    )
    let record = makeEvidenceRecord(
      id: "digest-run",
      experimentID: config.experiments[0].id,
      solutionID: config.solutionHypotheses[0].id,
      painID: config.painHypotheses[0].id,
      branchName: config.experiments[0].branchName,
      verdict: .promising,
      objections: ["Still needs CSV import"],
      missingCapabilities: ["csv_import"],
      comparison: "Beat the spreadsheet on review speed."
    )
    let index = ProductizationEvidenceIndex.build(records: [record])

    let text = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(text.contains("Top current-commit evidence signals and objections"))
    try #require(text.contains("Current-commit product-market-fit readiness"))
    try #require(text.contains("proof-debt"))
    try #require(text.contains("2 AI-user persona(s)"))
    try #require(text.contains("ai-user 0"))
    try #require(text.contains("model-free 1"))
    try #require(text.contains("Factory autopilot step"))
    try #require(text.contains("Product-factory portfolio pressure"))
    try #require(text.contains("pressure learn"))
    try #require(text.contains("executable false"))
    try #require(text.contains("cycle executable 0"))
    try #require(text.contains("cycle queue Blocked"))
    try #require(text.contains("Recent product-factory cycle audits"))
    try #require(text.contains("factory-cycle-digest"))
    try #require(text.contains("decisions 0"))
    try #require(text.contains("evidence 1"))
    try #require(text.contains("runs digest-run"))
    try #require(text.contains("proof debt 8 -> 7 (-1)"))
    try #require(text.contains("1 needing review"))
    try #require(text.contains("execution_failed"))
    try #require(text.contains("contract missing"))
    try #require(text.contains("Next product-factory actions"))
    try #require(text.contains("kind run_cohort"))
    try #require(text.contains("cohort \(config.scenarioCohorts[0].id)"))
    try #require(text.contains("mode model_free"))
    try #require(text.contains("digest-run"))
    try #require(text.contains("csv_import"))
    try #require(text.contains("Beat the spreadsheet"))
    try #require(!text.contains("transcript.jsonl"))
  }

  @Test func planningDigestBlocksAutopilotAfterRecentCycleFailure() throws {
    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
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
        startedAt: 50,
        endedAt: 55,
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

    let text = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: .empty
    )

    try #require(text.contains("Factory autopilot step"))
    try #require(text.contains("Product-factory portfolio pressure"))
    try #require(text.contains("pressure repair"))
    try #require(text.contains("executable false"))
    try #require(text.contains("cycle executable 0"))
    try #require(text.contains("factory-cycle-failed-step"))
    try #require(text.contains("Recent factory cycle"))
    try #require(text.contains("kind repair_failures"))
    try #require(text.contains("Repair factory cycle failure"))
    try #require(text.contains("contract missing"))
  }

  @Test func planAndReflectPromptsIncludeProductizationEvidenceWithoutTranscripts() throws {
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let first = makeEvidenceRecord(
      id: "prompt-run-one",
      experimentID: config.experiments[0].id,
      solutionID: config.solutionHypotheses[0].id,
      painID: config.painHypotheses[0].id,
      branchName: config.experiments[0].branchName,
      objections: ["The spreadsheet is already trusted"],
      missingCapabilities: ["csv_import"],
      comparison: "Beat the spreadsheet on review speed."
    )
    let second = makeEvidenceRecord(
      id: "prompt-run-two",
      experimentID: config.experiments[0].id,
      solutionID: config.solutionHypotheses[0].id,
      painID: config.painHypotheses[0].id,
      branchName: config.experiments[0].branchName,
      endedAt: 30,
      objections: ["The spreadsheet is already trusted"],
      missingCapabilities: ["csv_import"],
      comparison: "Still needs import proof before switching."
    )
    let index = ProductizationEvidenceIndex.build(records: [first, second])

    let plan = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productizationConfig: config,
      productizationEvidenceIndex: index
    )
    let reflect = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1,
      productizationConfig: config,
      productizationEvidenceIndex: index
    )

    for prompt in [plan, reflect] {
      try #require(prompt.contains("## Productization Context"))
      try #require(prompt.contains(config.experiments[0].branchName))
      try #require(prompt.contains("Factory autopilot step"))
      try #require(prompt.contains("executable false"))
      try #require(prompt.contains("cycle executable 0"))
      try #require(prompt.contains("cycle queue Blocked"))
      try #require(prompt.contains("kind run_cohort"))
      try #require(prompt.contains("cohort \(config.scenarioCohorts[0].id)"))
      try #require(prompt.contains("mode model_free"))
      try #require(prompt.contains("prompt-run-two"))
      try #require(prompt.contains("Repeated objections"))
      try #require(prompt.contains("the spreadsheet is already trusted (2x)"))
      try #require(prompt.contains("csv_import (2x)"))
      try #require(prompt.contains("Beat the spreadsheet"))
      try #require(!prompt.contains("transcript.jsonl"))
      try #require(!prompt.contains(#""turn":0"#))
    }
  }

  @MainActor
  @Test func productizationSmokeConnectsWorkspaceWorkbenchPromptAndRollout() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    var config = ProductizationConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    try workspace.writeProductizationConfig(config)

    let record = makeEvidenceRecord(
      id: "smoke-run",
      experimentID: config.experiments[0].id,
      solutionID: config.solutionHypotheses[0].id,
      painID: config.painHypotheses[0].id,
      branchName: config.experiments[0].branchName,
      commitSha: "head-sha",
      objections: ["Spreadsheet is already trusted"],
      missingCapabilities: ["csv_import"],
      comparison: "The prototype beats the spreadsheet for review speed."
    )
    _ = try workspace.writeProductizationEvidenceRecord(
      record,
      traceJSON: #"{"trace":true}"#,
      transcriptJSONL: #"{"raw":"persona transcript should stay out of prompts"}"#
    )

    let project = CompassProject(repoURL: root)
    await project.refresh()

    try #require(project.productizationConfig.experiments[0].decision == .keepGoing)
    try #require(project.productizationEvidenceIndex.summaries.map(\.runID) == ["smoke-run"])
    _ = ProductizationWorkbenchTab(project: project).body

    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productizationConfig: project.productizationConfig,
      productizationEvidenceIndex: project.productizationEvidenceIndex
    )

    try #require(prompt.contains("smoke-run"))
    try #require(prompt.contains(config.experiments[0].branchName))
    try #require(prompt.contains("csv_import"))
    try #require(!prompt.contains("persona transcript should stay out of prompts"))

    await project.applyProductExperimentRolloutAction(
      .promoteOrConfirm,
      experimentID: config.experiments[0].id
    )

    let saved = try workspace.readProductizationConfig()
    let savedExperiment = try #require(
      saved.experiments.first { $0.id == config.experiments[0].id })
    let savedDecision = try #require(saved.decisions.last)
    try #require(project.errorMessage == nil)
    try #require(savedExperiment.decision == .promote)
    try #require(savedDecision.decision == .promote)
    try #require(savedDecision.branchName == config.experiments[0].branchName)
    try #require(savedDecision.beforeSha == "head-sha")
    try #require(savedDecision.evidenceRunIDs == ["smoke-run"])
  }
}

private func makeEvidenceRecord(
  id: String,
  experimentID: String = "experiment-one",
  solutionID: String = "solution-one",
  painID: String = "pain-one",
  branchName: String = "codex/experiment-one",
  commitSha: String = "abc123",
  scenarioID: String = "scenario-one",
  personaID: String = "segment-one",
  mode: ProductizationSimulationMode = .modelFree,
  status: ProductizationRunStatus = .completed,
  startedAt: Double = 10,
  endedAt: Double = 20,
  verdict: ProductizationEvidenceVerdict = .promising,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  comparison: String = "Compared with the current alternative.",
  scores: ProductizationEvidenceScores = ProductizationEvidenceScores(
    painRecognition: 4,
    workflowImprovement: 3,
    alternativeAdvantage: 3,
    switchingReadiness: 2,
    continuedUsePull: 3
  ),
  failure: ProductizationRunFailure? = nil
) -> ProductizationEvidenceRecord {
  ProductizationEvidenceRecord(
    id: id,
    experimentID: experimentID,
    solutionID: solutionID,
    painID: painID,
    branchName: branchName,
    commitSha: commitSha,
    scenarioID: scenarioID,
    personaID: personaID,
    mode: mode,
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    traceHash: "trace-\(id)",
    promptVersions: ["productization.persona_action.v1"],
    model: mode == .modelFree ? "model-free" : "gpt-test",
    scores: scores,
    objections: objections,
    missingCapabilities: missingCapabilities,
    currentAlternativeComparison: comparison,
    verdict: verdict,
    summary: "Evidence summary for \(id).",
    failure: failure
  )
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(
      path: "ProductizationEvidenceStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}
