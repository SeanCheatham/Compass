import Foundation
import Testing

@testable import Compass

struct ProductTournamentEvidenceStoreTests {
  @Test func storeWritesRunDirectoryArtifactsAndIndex() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    let record = makeEvidenceRecord(
      id: "run-one",
      personaActionRationales: [
        "turn 0 choose valid action inspect_pain: Wanted to confirm the weekly reporting pain."
      ]
    )
    let stored = try workspace.writeProductTournamentEvidenceRecord(
      record,
      traceJSON: #"{"trace":true}"#,
      feedbackJSON: #"{"feedback":true}"#,
      transcriptJSONL: #"{"turn":0}"#,
      summaryMarkdown: "summary"
    )

    try #require(stored.traceArtifactPath == "product-tournament/runs/run-one/trace.json")
    try #require(stored.feedbackArtifactPath == "product-tournament/runs/run-one/feedback.json")
    try #require(
      stored.transcriptArtifactPath == "product-tournament/runs/run-one/transcript.jsonl")
    try #require(stored.summaryArtifactPath == "product-tournament/runs/run-one/summary.md")
    try #require(
      FileManager.default.fileExists(
        atPath: workspace.productTournamentURL.appending(path: "evidence-index.json").path))
    let read = try workspace.readProductTournamentEvidenceRecord(id: "run-one")
    try #require(read == stored)
    let summaries = workspace.readProductTournamentEvidenceIndex().summaries
    try #require(summaries.map(\.runID) == ["run-one"])
    try #require(
      summaries.first?.personaActionRationales.first?.contains("inspect_pain") == true)
  }

  @Test func storeWritesPlanEvaluationArtifactsAndIndex() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    let record = ProductTournamentPlanEvaluationRecord(
      id: "plan-eval-one",
      tournamentID: "tournament-reporting",
      roundID: "round-reporting-plans",
      contenderID: "contender-reporting-desk",
      solutionID: "solution-reporting-desk",
      experimentID: "experiment-reporting-desk",
      painID: "pain-reporting",
      personaID: "segment-operator",
      personaName: "Operations lead",
      currentWorkflowID: "workflow-spreadsheet",
      alternativeID: "alternative-spreadsheet",
      startedAt: 10,
      endedAt: 11,
      scores: ProductTournamentEvidenceScores(
        painRecognition: 4,
        workflowImprovement: 4,
        alternativeAdvantage: 3,
        switchingReadiness: 3,
        continuedUsePull: 4
      ),
      willingnessToPayScore: 4,
      estimatedMonthlyPriceCents: 9900,
      objections: ["Spreadsheet is already familiar"],
      currentAlternativeComparison: "The plan is clearer than the spreadsheet for review.",
      verdict: .promising,
      summary: "The plan earned buyer interest.",
      rationale: ["Plan-only simulated user evaluation."],
      planStrengths: ["Clear workflow relief"],
      planRisks: ["Needs feasibility proof"],
      promptVersions: ["test.plan"]
    )

    let stored = try workspace.writeProductTournamentPlanEvaluationRecord(record)

    try #require(
      stored.summaryArtifactPath
        == "product-tournament/plan-evaluations/plan-eval-one/summary.md")
    let read = try workspace.readProductTournamentPlanEvaluationRecord(id: "plan-eval-one")
    try #require(read == stored)
    let index = workspace.readProductTournamentEvidenceIndex()
    try #require(index.summaries.isEmpty)
    try #require(index.planEvaluationSummaries.map(\.evaluationID) == ["plan-eval-one"])
    try #require(
      index.aggregate.latestPlanEvaluationByContender["contender-reporting-desk"] == "plan-eval-one"
    )
    let readiness = try #require(index.aggregate.planReadinessByContender.first)
    try #require(readiness.contenderID == "contender-reporting-desk")
    try #require(readiness.averageWillingnessToPayScore == 4)
    let markdown = ProductTournamentEvidenceMarkdownExporter.markdown(planEvaluation: stored)
    try #require(markdown.contains("Willingness To Pay: 4/5"))
    try #require(markdown.contains("$99/month"))
  }

  @Test func storePreservesDecisionIntentAcrossRecordIndexMarkdownAndDigest() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need targeted tournament evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].currentSha = "abc123"
    let experiment = config.experiments[0]
    let intent = ProductTournamentSimulationDecisionIntent(
      currentDecision: .keepGoing,
      targetDecision: .promote
    )
    let scores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 5
    )
    let record = makeEvidenceRecord(
      id: "intent-run",
      experimentID: experiment.id,
      solutionID: experiment.solutionID,
      painID: config.solutionHypotheses[0].painID,
      branchName: experiment.branchName,
      commitSha: "abc123",
      scenarioID: config.scenarios[0].id,
      personaID: config.userSegments[0].id,
      mode: .personaModel,
      decisionIntent: intent,
      scores: scores
    )

    let index = ProductTournamentEvidenceIndex.build(records: [record])
    let summary = try #require(index.summaries.first)
    let outcome = try #require(index.aggregate.decisionIntentOutcomes.first)
    let markdown = ProductTournamentEvidenceMarkdownExporter.markdown(record: record)
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(record.decisionIntent?.targetDecision == .promote)
    try #require(record.decisionIntentEvaluation?.outcome == .supportsTarget)
    try #require(summary.decisionIntent?.targetDecision == .promote)
    try #require(summary.decisionIntentEvaluation?.outcome == .supportsTarget)
    try #require(outcome.targetDecision == .promote)
    try #require(outcome.outcome == .supportsTarget)
    try #require(outcome.runIDs == ["intent-run"])
    try #require(markdown.contains("target_decision promote"))
    try #require(markdown.contains("supports_target"))
    try #require(markdown.contains("alternative advantage"))
    try #require(digest.contains("intent-run"))
    try #require(digest.contains("target_decision promote"))
    try #require(digest.contains("intent_outcome supports_target"))
    try #require(digest.contains("Targeted tournament proof outcomes"))
    try #require(digest.contains("intent_focus alternative advantage"))
  }

  @Test func decisionIntentEvaluationClassifiesLiftAndCutProof() throws {
    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 5
    )
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 1,
      switchingReadiness: 1,
      continuedUsePull: 1
    )
    let promoteIntent = ProductTournamentSimulationDecisionIntent(
      currentDecision: .keepGoing,
      targetDecision: .promote
    )
    let killIntent = ProductTournamentSimulationDecisionIntent(
      currentDecision: .keepGoing,
      targetDecision: .kill
    )

    let promoted = makeEvidenceRecord(
      id: "promote-support",
      mode: .personaModel,
      decisionIntent: promoteIntent,
      verdict: .strongPull,
      scores: strongScores
    )
    let promotionRejected = makeEvidenceRecord(
      id: "promote-contradict",
      mode: .personaModel,
      decisionIntent: promoteIntent,
      verdict: .rejected,
      comparison: "The spreadsheet remained better.",
      scores: weakScores
    )
    let killed = makeEvidenceRecord(
      id: "kill-support",
      mode: .personaModel,
      decisionIntent: killIntent,
      verdict: .weak,
      scores: weakScores
    )
    let killContradicted = makeEvidenceRecord(
      id: "kill-contradict",
      mode: .personaModel,
      decisionIntent: killIntent,
      verdict: .promising,
      scores: strongScores
    )

    try #require(promoted.decisionIntentEvaluation?.outcome == .supportsTarget)
    try #require(promotionRejected.decisionIntentEvaluation?.outcome == .contradictsTarget)
    try #require(killed.decisionIntentEvaluation?.outcome == .supportsTarget)
    try #require(killContradicted.decisionIntentEvaluation?.outcome == .contradictsTarget)
  }

  @Test func indexAggregatesExperimentEvidenceSignals() throws {
    let first = makeEvidenceRecord(
      id: "first",
      endedAt: 100,
      verdict: .weak,
      objections: ["Spreadsheet is already familiar", "Spreadsheet is already familiar"],
      missingCapabilities: ["import_csv"],
      comparison: "Lost to the current spreadsheet.",
      personaActionRationales: [
        "turn 0 choose valid action compare_current_alternative: Needed CSV proof before switching."
      ]
    )
    let second = makeEvidenceRecord(
      id: "second",
      endedAt: 200,
      verdict: .promising,
      objections: ["Spreadsheet is already familiar"],
      missingCapabilities: ["import_csv", "permissions"],
      comparison: "Beat the spreadsheet for review speed.",
      personaActionRationales: [
        "turn 2 choose valid action reduce_switching_objection: Needed CSV proof before switching."
      ]
    )
    let failure = makeEvidenceRecord(
      id: "failure",
      experimentID: "experiment-two",
      status: .appCommandFailed,
      endedAt: 150,
      verdict: .rejected,
      missingCapabilities: ["runtime"],
      failure: ProductTournamentRunFailure(
        status: .appCommandFailed,
        message: "cargo failed"
      )
    )

    let index = ProductTournamentEvidenceIndex.build(records: [first, second, failure])

    try #require(index.aggregate.latestRunByExperiment["experiment-one"] == "second")
    try #require(
      index.aggregate.repeatedObjections.first?.objection == "spreadsheet is already familiar")
    try #require(index.aggregate.missingCapabilityFrequency.first?.capabilityID == "import_csv")
    try #require(index.aggregate.verdictCounts["promising"] == 1)
    try #require(index.aggregate.failuresByKind["appCommandFailed"] == 1)
    try #require(
      index.aggregate.personaRationaleSignals.first?.rationale
        == "needed csv proof before switching.")
    try #require(index.aggregate.personaRationaleSignals.first?.count == 2)
    try #require(index.aggregate.personaRationaleSignals.first?.runIDs.contains("first") == true)
    try #require(index.aggregate.personaRationaleSignals.first?.runIDs.contains("second") == true)
    try #require(
      index.aggregate.currentAlternativeComparisons.contains {
        $0.comparison.contains("Beat the spreadsheet")
      })
  }

  @Test func indexBuildsProductTournamentReadinessRecommendations() throws {
    let strongScores = ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 4,
      switchingReadiness: 5,
      continuedUsePull: 5
    )
    let weakScores = ProductTournamentEvidenceScores(
      painRecognition: 2,
      workflowImprovement: 1,
      alternativeAdvantage: 2,
      switchingReadiness: 1,
      continuedUsePull: 2
    )
    let narrowScores = ProductTournamentEvidenceScores(
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

    let readiness = ProductTournamentEvidenceIndex.build(records: records)
      .aggregate.tournamentReadinessByExperiment
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
    try #require(good.rationale.contains { $0.contains("Average tournament score") })

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
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let strongScores = ProductTournamentEvidenceScores(
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

    let index = ProductTournamentEvidenceIndex.build(records: records)
    let readiness = try #require(index.currentTournamentReadiness(for: experiment))

    try #require(index.staleSummaryCount(for: experiment) == 2)
    try #require(index.summaries(for: experiment).map(\.runID) == ["current-a"])
    try #require(readiness.runCount == 1)
    try #require(readiness.evidenceRunIDs == ["current-a"])
    try #require(
      index.aggregate.tournamentReadinessByExperiment.first { $0.experimentID == experiment.id }?
        .evidenceRunIDs.first == "old-a")
  }

  @Test func planningDigestIncludesBoundedProductTournamentEvidence() throws {
    var config = ProductTournamentConfig.seedDefaults(
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
        messages: [
          "Model-free cohort ran 1 scenario(s): 0 completed, 1 needing review, 0 skipped."
        ],
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
        evidenceTensionSummaries: [
          "\(config.experiments[0].id): resolve split tournament evidence; score 82/100; strong_pull vs rejected; target Budget owner"
        ],
        proofTargetSummaries: [
          "\(config.experiments[0].id): run targeted AI-user persona proof; target Budget owner; debt 2 AI-user persona(s)"
        ],
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
      comparison: "Beat the spreadsheet on review speed.",
      personaActionRationales: [
        "turn 1 choose valid action compare_current_alternative: Wanted proof against the spreadsheet before switching."
      ]
    )
    let index = ProductTournamentEvidenceIndex.build(records: [record])

    let text = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(text.contains("Top current-commit evidence signals and objections"))
    try #require(text.contains("Current-commit product tournament readiness"))
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
    try #require(text.contains("evidence tensions"))
    try #require(text.contains("resolve split tournament evidence"))
    try #require(text.contains("targets"))
    try #require(text.contains("proof targets"))
    try #require(text.contains("run targeted AI-user persona proof"))
    try #require(text.contains("Budget owner"))
    try #require(text.contains("1 needing review"))
    try #require(text.contains("execution_failed"))
    try #require(text.contains("contract missing"))
    try #require(text.contains("Next product-factory actions"))
    try #require(text.contains("kind run_cohort"))
    try #require(text.contains("cohort \(config.scenarioCohorts[0].id)"))
    try #require(text.contains("mode model_free"))
    try #require(text.contains("digest-run"))
    try #require(text.contains("persona_rationale"))
    try #require(text.contains("Wanted proof against the spreadsheet"))
    try #require(text.contains("csv_import"))
    try #require(text.contains("Beat the spreadsheet"))
    try #require(!text.contains("transcript.jsonl"))
  }

  @Test func planningDigestIncludesRepeatedAIUserRationaleSignals() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let records = [
      makeEvidenceRecord(
        id: "rationale-one",
        experimentID: config.experiments[0].id,
        solutionID: config.solutionHypotheses[0].id,
        painID: config.painHypotheses[0].id,
        branchName: config.experiments[0].branchName,
        personaID: "operator",
        mode: .personaModel,
        personaActionRationales: [
          "turn 1 choose valid action compare_current_alternative: Needed CSV proof before switching."
        ]
      ),
      makeEvidenceRecord(
        id: "rationale-two",
        experimentID: config.experiments[0].id,
        solutionID: config.solutionHypotheses[0].id,
        painID: config.painHypotheses[0].id,
        branchName: config.experiments[0].branchName,
        personaID: "buyer",
        mode: .personaModel,
        endedAt: 30,
        personaActionRationales: [
          "turn 3 choose valid action reduce_switching_objection: Needed CSV proof before switching."
        ]
      ),
    ]
    let text = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: ProductTournamentEvidenceIndex.build(records: records)
    )

    try #require(text.contains("AI-user rationale signals"))
    try #require(text.contains("needed csv proof before switching"))
    try #require(text.contains("rationale-one"))
    try #require(text.contains("rationale-two"))
  }

  @Test func planningDigestBlocksAutopilotAfterRecentCycleFailure() throws {
    var config = ProductTournamentConfig.seedDefaults(
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

    let text = ProductTournamentPlanningDigestFormatter.promptText(
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

  @Test func planAndReflectPromptsIncludeProductTournamentContextWithoutTranscripts() throws {
    let config = ProductTournamentConfig.seedDefaults(
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
      comparison: "Still needs import proof before switching.",
      personaActionRationales: [
        "turn 2 choose valid action reduce_switching_objection: Needed import proof before trusting a switch."
      ]
    )
    let index = ProductTournamentEvidenceIndex.build(records: [first, second])

    let plan = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productTournamentConfig: config,
      productTournamentEvidenceIndex: index
    )
    let reflect = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1,
      productTournamentConfig: config,
      productTournamentEvidenceIndex: index
    )

    for prompt in [plan, reflect] {
      try #require(prompt.contains("## Product Tournament Context"))
      try #require(prompt.contains(config.experiments[0].branchName))
      try #require(prompt.contains("Factory autopilot step"))
      try #require(prompt.contains("executable false"))
      try #require(prompt.contains("cycle executable 0"))
      try #require(prompt.contains("cycle queue Blocked"))
      try #require(prompt.contains("kind run_cohort"))
      try #require(prompt.contains("cohort \(config.scenarioCohorts[0].id)"))
      try #require(prompt.contains("mode model_free"))
      try #require(prompt.contains("prompt-run-two"))
      try #require(prompt.contains("persona_rationale"))
      try #require(prompt.contains("Needed import proof before trusting a switch"))
      try #require(prompt.contains("Repeated objections"))
      try #require(prompt.contains("the spreadsheet is already trusted (2x)"))
      try #require(prompt.contains("csv_import (2x)"))
      try #require(prompt.contains("Beat the spreadsheet"))
      try #require(!prompt.contains("transcript.jsonl"))
      try #require(!prompt.contains(#""turn":0"#))
    }
  }

  @MainActor
  @Test func productTournamentSmokeConnectsWorkspaceWorkbenchPromptAndRollout() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.experiments[0].decision = .keepGoing
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    try workspace.writeProductTournamentConfig(config)

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
    _ = try workspace.writeProductTournamentEvidenceRecord(
      record,
      traceJSON: #"{"trace":true}"#,
      transcriptJSONL: #"{"raw":"persona transcript should stay out of prompts"}"#
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.first)
    let planEvaluation = ProductTournamentPlanEvaluationRecord(
      id: "smoke-plan-eval",
      tournamentID: tournament.id,
      roundID: planRound.id,
      contenderID: contender.id,
      solutionID: contender.solutionID,
      experimentID: contender.experimentID,
      painID: config.painHypotheses[0].id,
      personaID: config.userSegments[0].id,
      personaName: config.userSegments[0].name,
      currentWorkflowID: config.currentWorkflows[0].id,
      alternativeID: config.alternatives[0].id,
      startedAt: 12,
      endedAt: 13,
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
      objections: ["The buyer needs feasibility proof before sponsorship."],
      currentAlternativeComparison: "The plan beats the spreadsheet if the core import works.",
      verdict: .promising,
      summary: "The plan evaluation found willingness to sponsor after feasibility proof.",
      rationale: ["The plan directly attacks the weekly reporting pain."],
      planStrengths: ["Clear buyer pain and workflow relief"],
      planRisks: ["Import feasibility remains unproven"],
      promptVersions: ["test.plan"]
    )
    let storedPlanEvaluation = try workspace.writeProductTournamentPlanEvaluationRecord(
      planEvaluation
    )

    let project = CompassProject(repoURL: root)
    await project.refresh()

    try #require(project.productTournamentConfig.experiments[0].decision == .keepGoing)
    try #require(project.productTournamentEvidenceIndex.summaries.map(\.runID) == ["smoke-run"])
    try #require(
      project.productTournamentEvidenceIndex.planEvaluationSummaries.map(\.evaluationID)
        == ["smoke-plan-eval"])
    try #require(
      try project.readProductTournamentPlanEvaluationRecord(id: "smoke-plan-eval")
        == storedPlanEvaluation)
    let workbenchBody = String(reflecting: ProductTournamentWorkbenchTab(project: project).body)

    try #require(WorkspaceTab.allCases.contains(.productTournament))
    try #require(WorkspaceTab.productTournament.rawValue == "productTournament")
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productTournamentConfig: project.productTournamentConfig,
      productTournamentEvidenceIndex: project.productTournamentEvidenceIndex
    )

    try #require(workbenchBody.contains("Checking tournament experience contract"))
    try #require(prompt.contains("smoke-run"))
    try #require(prompt.contains(config.experiments[0].branchName))
    try #require(prompt.contains("csv_import"))
    try #require(!prompt.contains("persona transcript should stay out of prompts"))

    await project.applyProductExperimentRolloutAction(
      .promoteOrConfirm,
      experimentID: config.experiments[0].id
    )

    let saved = try workspace.readProductTournamentConfig()
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
  mode: ProductTournamentSimulationMode = .modelFree,
  decisionIntent: ProductTournamentSimulationDecisionIntent? = nil,
  status: ProductTournamentRunStatus = .completed,
  startedAt: Double = 10,
  endedAt: Double = 20,
  verdict: ProductTournamentEvidenceVerdict = .promising,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  comparison: String = "Compared with the current alternative.",
  personaActionRationales: [String] = [],
  scores: ProductTournamentEvidenceScores = ProductTournamentEvidenceScores(
    painRecognition: 4,
    workflowImprovement: 3,
    alternativeAdvantage: 3,
    switchingReadiness: 2,
    continuedUsePull: 3
  ),
  failure: ProductTournamentRunFailure? = nil
) -> ProductTournamentEvidenceRecord {
  ProductTournamentEvidenceRecord(
    id: id,
    experimentID: experimentID,
    solutionID: solutionID,
    painID: painID,
    branchName: branchName,
    commitSha: commitSha,
    scenarioID: scenarioID,
    personaID: personaID,
    mode: mode,
    decisionIntent: decisionIntent,
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    traceHash: "trace-\(id)",
    promptVersions: ["product_tournament.persona_action.v1"],
    model: mode == .modelFree ? "model-free" : "gpt-test",
    scores: scores,
    objections: objections,
    missingCapabilities: missingCapabilities,
    currentAlternativeComparison: comparison,
    personaActionRationales: personaActionRationales,
    verdict: verdict,
    summary: "Evidence summary for \(id).",
    failure: failure
  )
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(
      path: "ProductTournamentEvidenceStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}
