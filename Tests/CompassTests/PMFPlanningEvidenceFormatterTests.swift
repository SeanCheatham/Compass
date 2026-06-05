import Foundation
import Testing

@testable import Compass

struct PMFPlanningEvidenceFormatterTests {
  @Test func emptyContextNamesPMFEvidenceGaps() throws {
    let text = PMFPlanningEvidenceFormatter.promptText(config: .empty, index: .empty)

    try #require(text.contains("advisory product evidence"))
    try #require(text.contains("No PMF hypothesis is configured"))
    try #require(text.contains("No enabled PMF scenarios are configured"))
    try #require(text.contains("No PMF runs have been recorded yet"))
  }

  @Test func successfulEvidenceContextSummarizesLatestScenarioWithoutRawTranscript() throws {
    let config = makePMFPlanningConfig()
    let record = makePlanningEvidenceRecord(
      id: "run-success",
      config: config,
      feedback: makePlanningFeedback(
        valueScore: 4,
        clarityScore: 4,
        trustScore: 3,
        switchLikelihood: 3,
        payLikelihood: 2,
        topObjection: "Needs an import example",
        verdict: .somePull
      )
    )
    let index = PMFEvidenceIndex.build(records: [record])

    let text = PMFPlanningEvidenceFormatter.promptText(config: config, index: index)

    try #require(text.contains("Current hypothesis"))
    try #require(text.contains("Budget owner: Try core workflow"))
    try #require(text.contains("run run-success"))
    try #require(text.contains("verdict some_pull"))
    try #require(text.contains("scores value 4"))
    try #require(text.contains("Needs an import example"))
    try #require(!text.contains("rawResponse"))
    try #require(!text.contains("Raw transcript"))
  }

  @Test func failedPMFRunContextNamesFailureKind() throws {
    let config = makePMFPlanningConfig()
    let record = makePlanningEvidenceRecord(
      id: "run-failed",
      config: config,
      status: .appCommandFailed,
      feedback: nil,
      failure: PMFRunFailure(status: .appCommandFailed, message: "CLI failed")
    )
    let index = PMFEvidenceIndex.build(records: [record])

    let text = PMFPlanningEvidenceFormatter.promptText(config: config, index: index)

    try #require(text.contains("status appCommandFailed"))
    try #require(text.contains("failure appCommandFailed"))
    try #require(text.contains("PMF run failures"))
    try #require(text.contains("appCommandFailed: 1"))
  }

  @Test func repeatedObjectionsAndLowScoreClustersAreBoundedAndDeterministic() throws {
    let config = makePMFPlanningConfig()
    let first = makePlanningEvidenceRecord(
      id: "run-a",
      config: config,
      endedAt: 100,
      feedback: makePlanningFeedback(
        valueScore: 2,
        clarityScore: 2,
        trustScore: 3,
        switchLikelihood: 2,
        payLikelihood: 1,
        topObjection: "Spreadsheet still wins",
        verdict: .notYet
      )
    )
    let second = makePlanningEvidenceRecord(
      id: "run-b",
      config: config,
      endedAt: 200,
      feedback: makePlanningFeedback(
        valueScore: 4,
        clarityScore: 3,
        trustScore: 3,
        switchLikelihood: 3,
        payLikelihood: 2,
        topObjection: "spreadsheet   still wins",
        verdict: .somePull
      )
    )
    let index = PMFEvidenceIndex.build(records: [first, second])

    let text = PMFPlanningEvidenceFormatter.promptText(config: config, index: index)

    try #require(text.contains("Repeated objections"))
    try #require(text.contains("spreadsheet still wins (2x)"))
    try #require(text.contains("Low-score clusters"))
    try #require(text.contains("Budget owner / Try core workflow"))
    try #require(text.contains("pay 1.5"))
    try #require(text.contains("Recent verdict distribution"))
    try #require(text.contains("not_yet: 1"))
    try #require(text.contains("some_pull: 1"))
  }

  @Test func planAndReflectPromptsIncludeProductizationEvidenceDigest() throws {
    let config = makePMFPlanningConfig()
    let productizationConfig = ProductizationConfig.seedDefaults(
      projectTitle: "ROI validation",
      rawPain: "Budget owners cannot tell whether a workflow tool saves enough time to switch.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let index = PMFEvidenceIndex.build(records: [
      makePlanningEvidenceRecord(
        id: "run-prompt",
        config: config,
        feedback: makePlanningFeedback(topObjection: "Missing proof of ROI")
      )
    ])

    let plan = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productizationConfig: productizationConfig,
      pmfConfig: config,
      pmfEvidenceIndex: index
    )
    let reflect = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1,
      productizationConfig: productizationConfig,
      pmfConfig: config,
      pmfEvidenceIndex: index
    )

    try #require(plan.contains("## Productization Context"))
    try #require(plan.contains("advisory product pressure"))
    try #require(plan.contains("Repeated target-persona confusion"))
    try #require(plan.contains("Missing proof of ROI"))
    try #require(reflect.contains("## Productization Context"))
    try #require(reflect.contains("durable product lessons"))
    try #require(reflect.contains("persona-specific objections"))
    try #require(reflect.contains("Missing proof of ROI"))
  }
}

private func makePMFPlanningConfig() -> PMFConfig {
  let hypothesis = ProductHypothesis(
    id: "hypothesis-roi",
    title: "ROI validation hypothesis",
    targetUser: "Budget owners evaluating a workflow tool",
    jobToBeDone: "Decide whether the app saves enough time to sponsor adoption.",
    pain: "Manual reporting hides costly rework.",
    promise: "The app makes ROI visible in the first workflow.",
    knownRisks: ["The buyer may see polish but no proof of value."],
    createdAt: 1_700_000_000
  )
  let persona = PMFPersona(
    id: "budget-owner",
    name: "Budget owner",
    role: "Economic buyer",
    context: "Needs credible ROI before sponsoring adoption.",
    currentWorkflow: "Reviews spreadsheets and asks operators for proof.",
    skepticism: "Treats generic dashboards as insufficient.",
    technicalComfort: "low"
  )
  let task = PMFTask(
    id: "try-core-workflow",
    title: "Try core workflow",
    situation: "The buyer checks whether the app proves the promised value.",
    desiredOutcome: "See a concrete import and ROI proof.",
    startingContext: "Initial app state",
    maxTurns: 6
  )
  let scenario = PMFScenario(
    id: "buyer-core-workflow",
    title: "Budget owner: Try core workflow",
    hypothesisID: hypothesis.id,
    personaID: persona.id,
    taskID: task.id,
    seed: "buyer-core-workflow"
  )
  return PMFConfig(
    hypotheses: [hypothesis],
    personas: [persona],
    tasks: [task],
    scenarios: [scenario]
  )
}

private func makePlanningEvidenceRecord(
  id: String,
  config: PMFConfig,
  status: PMFRunStatus = .completed,
  endedAt: Double = 100,
  feedback: PMFFeedbackRecord? = makePlanningFeedback(),
  failure: PMFRunFailure? = nil
) -> PMFEvidenceRecord {
  PMFEvidenceRecord(
    id: id,
    hypothesisID: config.hypotheses[0].id,
    personaID: config.personas[0].id,
    taskID: config.tasks[0].id,
    scenarioID: config.scenarios[0].id,
    startedAt: endedAt - 10,
    endedAt: endedAt,
    status: status,
    route: "native-macos",
    model: "test-model",
    promptVersions: [Prompts.pmfPersonaActionPromptVersionID],
    actionTranscript: PMFRunTranscript(
      turns: [
        PMFActionTurnRecord(
          turnIndex: 0,
          phase: .choose,
          promptVersionID: Prompts.pmfPersonaActionPromptVersionID,
          actionID: "inspect_roi",
          params: .object([:]),
          wasValid: true,
          allowedActionIDs: ["inspect_roi"],
          rationale: "I need proof before switching.",
          rawResponse: #"{"actionId":"inspect_roi"}"#
        )
      ]
    ),
    feedback: feedback,
    failure: failure
  )
}

private func makePlanningFeedback(
  valueScore: Int = 3,
  clarityScore: Int = 3,
  trustScore: Int = 3,
  switchLikelihood: Int = 2,
  payLikelihood: Int = 2,
  topObjection: String = "Needs stronger ROI proof",
  verdict: PMFPersonaVerdict = .notYet
) -> PMFFeedbackRecord {
  PMFFeedbackRecord(
    promptVersionID: Prompts.pmfFeedbackPromptVersionID,
    valueScore: valueScore,
    clarityScore: clarityScore,
    trustScore: trustScore,
    switchLikelihood: switchLikelihood,
    payLikelihood: payLikelihood,
    taskOutcome: .partial,
    topObjection: topObjection,
    missingCapability: "A concrete ROI import example.",
    verdict: verdict,
    summary: "The buyer sees a possible fit but needs stronger proof."
  )
}
