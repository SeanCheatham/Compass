import Foundation
import Testing

@testable import Compass

struct ProductTournamentScenarioRunTests {
  @Test func scenarioDraftPersistsAndAddsScenarioToExperimentCohort() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Scenario Helper",
      rawPain: "Support teams lose workflow context.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.scenarios = []
    config.scenarioCohorts = []
    let experiment = config.experiments[0]
    let draft = ProductScenarioDraft(
      id: "scenario-support",
      experimentID: experiment.id,
      cohortID: "cohort-support",
      cohortTitle: "Support workflow cohort",
      cohortEnabled: true,
      segmentID: config.userSegments[0].id,
      currentWorkflowID: config.currentWorkflows[0].id,
      alternativeID: config.alternatives[0].id,
      title: "Support workflow proof",
      task: "Complete the support workflow with less context loss.",
      successSignal: "The support lead can name the next action.",
      targetCommitSha: "abc123",
      maxTurns: 6,
      appCommandTimeoutSeconds: 90
    )

    let saved = try ProductTournamentScenarioCoordinator.saving(
      draft: draft,
      to: config,
      now: Date(timeIntervalSince1970: 20)
    )
    let scenario = try #require(saved.scenarios.first { $0.id == "scenario-support" })
    let cohort = try #require(saved.scenarioCohorts.first { $0.experimentID == experiment.id })

    try #require(scenario.task.contains("support workflow"))
    try #require(scenario.successSignal.contains("next action"))
    try #require(scenario.targetCommitSha == "abc123")
    try #require(scenario.maxTurns == 6)
    try #require(scenario.appCommandTimeoutSeconds == 90)
    try #require(cohort.id == "cohort-support")
    try #require(cohort.title == "Support workflow cohort")
    try #require(cohort.enabled)
    try #require(cohort.scenarioIDs == ["scenario-support"])

    let edited = ProductScenarioDraft(
      id: "scenario-support",
      experimentID: experiment.id,
      cohortID: cohort.id,
      cohortTitle: "Edited support cohort",
      cohortEnabled: false,
      segmentID: config.userSegments[0].id,
      currentWorkflowID: config.currentWorkflows[0].id,
      alternativeID: config.alternatives[0].id,
      title: "Support workflow proof",
      task: "Complete the support workflow with less context loss.",
      successSignal: "The support lead can name the next action.",
      targetCommitSha: "abc123",
      maxTurns: 6,
      appCommandTimeoutSeconds: 90
    )
    let editedConfig = try ProductTournamentScenarioCoordinator.saving(
      draft: edited,
      to: saved,
      now: Date(timeIntervalSince1970: 30)
    )
    let editedCohort = try #require(editedConfig.scenarioCohorts.first { $0.id == cohort.id })
    try #require(editedCohort.title == "Edited support cohort")
    try #require(!editedCohort.enabled)
    try #require(editedCohort.scenarioIDs == ["scenario-support"])
  }

  @Test func revisionBriefCreatesTargetedScenarioDraft() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Scenario Helper",
      rawPain: "Support teams lose workflow context.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.experiments[0].baseSha = "base-sha"
    config.experiments[0].currentSha = "head-sha"
    let experiment = config.experiments[0]
    let buyer = try #require(config.userSegments.first { $0.name == "Budget owner" })
    let scenario = try #require(
      config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == buyer.id
      })
    let cohort = try #require(
      config.scenarioCohorts.first {
        $0.experimentID == experiment.id && $0.scenarioIDs.contains(scenario.id)
      })
    let brief = ProductFactoryRevisionBrief(
      experimentID: experiment.id,
      source: .aiUserRationale,
      title: "Revise prototype for AI-user rationale",
      priority: 86,
      triggerSummary:
        "Repeated AI-user rationale appeared in 2 current runs: needed proof before switching.",
      prototypeChange:
        "make the proof artifact inspectable with source context and decision criteria.",
      scenarioChange:
        "Make Budget owner inspect the evidence trail before deciding whether to switch.",
      proofPlan:
        "Rerun targeted AI-user proof against the current alternative.",
      targetPersonaID: buyer.id,
      targetPersonaName: buyer.name,
      targetScenarioID: scenario.id,
      targetCohortID: cohort.id
    )

    let draft = try ProductTournamentScenarioCoordinator.revisionDraft(
      for: brief,
      in: config,
      now: Date(timeIntervalSince1970: 40)
    )
    let saved = try ProductTournamentScenarioCoordinator.saving(
      draft: draft,
      to: config,
      now: Date(timeIntervalSince1970: 50)
    )
    let revisedScenario = try #require(saved.scenarios.first { $0.id == scenario.id })
    let revisedCohort = try #require(saved.scenarioCohorts.first { $0.id == cohort.id })

    try #require(draft.id == scenario.id)
    try #require(draft.experimentID == experiment.id)
    try #require(draft.cohortID == cohort.id)
    try #require(draft.segmentID == buyer.id)
    try #require(draft.targetCommitSha == "head-sha")
    try #require(draft.task.contains("proof artifact inspectable"))
    try #require(draft.task.contains("Budget owner"))
    try #require(draft.successSignal.contains("resolved the original rationale"))
    try #require(draft.successSignal.contains("current alternative"))
    try #require(revisedScenario.task == draft.task)
    try #require(revisedScenario.successSignal == draft.successSignal)
    try #require(revisedScenario.updatedAt == 50)
    try #require(revisedCohort.scenarioIDs.contains(scenario.id))
  }

  @Test func requestConstructionUsesScenarioTaskSuccessSignalAndSelectedAlternative() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let config = try makeScenarioRunConfig(commitSha: head)
    let scenario = config.scenarios[0]

    let request = try await ProductTournamentScenarioCoordinator.request(
      experimentID: config.experiments[0].id,
      scenarioID: scenario.id,
      in: config,
      projectTitle: "Scenario Helper",
      generatedAppWorkingDirectory: root,
      targetDecision: .promote
    )
    let input = request.experienceInput(actions: [])

    try #require(request.commitSha == head)
    try #require(request.decisionIntent?.currentDecision == config.experiments[0].decision)
    try #require(request.decisionIntent?.targetDecision == .promote)
    try #require(request.maxTurns == scenario.maxTurns)
    try #require(request.appCommandTimeout == scenario.appCommandTimeoutSeconds)
    try #require(request.mode == .modelFree)
    try #require(input.decisionIntent?.targetDecision == .promote)
    try #require(input.decisionIntent?.scorecardFocus.contains("continued-use pull") == true)
    try #require(input.scenario.task.contains(scenario.task))
    try #require(input.scenario.task.contains(scenario.successSignal))
    try #require(input.experiment.successSignal == scenario.successSignal)
    try #require(input.alternatives.map(\.id) == [scenario.alternativeID])

    let personaRequest = try await ProductTournamentScenarioCoordinator.request(
      experimentID: config.experiments[0].id,
      scenarioID: scenario.id,
      in: config,
      projectTitle: "Scenario Helper",
      generatedAppWorkingDirectory: root,
      mode: .personaModel
    )
    try #require(personaRequest.mode == .personaModel)
  }

  @Test func requestConstructionRejectsScenarioFromDifferentExperiment() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let config = try makeScenarioRunConfig(commitSha: head)
    try #require(config.experiments.indices.contains(1))
    let selectedExperimentID = config.experiments[1].id
    let scenario = config.scenarios[0]

    do {
      _ = try await ProductTournamentScenarioCoordinator.request(
        experimentID: selectedExperimentID,
        scenarioID: scenario.id,
        in: config,
        projectTitle: "Scenario Helper",
        generatedAppWorkingDirectory: root
      )
      #expect(Bool(false), "Expected scenario experiment mismatch error.")
    } catch let error as ProductTournamentScenarioRunError {
      guard
        case .scenarioExperimentMismatch(
          let scenarioID,
          let selectedExperiment,
          let scenarioExperiment
        ) = error
      else {
        #expect(Bool(false), "Expected scenario experiment mismatch, got \(error).")
        return
      }
      try #require(scenarioID == scenario.id)
      try #require(selectedExperiment == selectedExperimentID)
      try #require(scenarioExperiment == scenario.experimentID)
      try #require(error.localizedDescription.contains("same experiment"))
    }
  }

  @Test func requestConstructionRejectsNonTargetRoundTwoExperiment() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    var config = try makeScenarioRunConfig(commitSha: head)
    try #require(config.experiments.indices.contains(1))
    let selectedExperimentID = config.experiments[1].id
    config.experiments[1].currentSha = head
    let secondDraft = ProductTournamentScenarioCoordinator.defaultDraft(
      for: config.experiments[1],
      in: config,
      now: Date(timeIntervalSince1970: 30)
    )
    config = try ProductTournamentScenarioCoordinator.saving(
      draft: secondDraft,
      to: config,
      now: Date(timeIntervalSince1970: 40)
    )
    let selectedScenario = try #require(
      config.scenarios.first { $0.experimentID == selectedExperimentID }
    )
    let targetScope = try activateRoundTwoTournamentScope(in: &config)
    let expectedExperimentID = config.experiments[0].id

    do {
      _ = try await ProductTournamentScenarioCoordinator.request(
        experimentID: selectedExperimentID,
        scenarioID: selectedScenario.id,
        in: config,
        projectTitle: "Scenario Helper",
        generatedAppWorkingDirectory: root
      )
      #expect(Bool(false), "Expected Round 2 implementation target mismatch error.")
    } catch let error as ProductTournamentScenarioRunError {
      guard
        case .roundTwoImplementationTargetMismatch(
          let selectedExperiment,
          let expectedExperiment,
          let tournamentID,
          let roundID,
          let contenderID
        ) = error
      else {
        #expect(Bool(false), "Expected Round 2 implementation target mismatch, got \(error).")
        return
      }
      try #require(selectedExperiment == selectedExperimentID)
      try #require(expectedExperiment == expectedExperimentID)
      try #require(tournamentID == targetScope.tournamentID)
      try #require(roundID == targetScope.roundID)
      try #require(contenderID == targetScope.contenderID)
      try #require(error.localizedDescription.contains("Round 2 implementation target"))
      try #require(error.localizedDescription.contains("competing contender"))
    }
  }

  @Test func modelFreeRunWritesEvidenceAndRefreshableIndex() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = try makeScenarioRunConfig(commitSha: head)
    try workspace.writeProductTournamentConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)

    let outcome = try await ProductTournamentScenarioCoordinator.runModelFree(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 100)
    )
    let index = workspace.readProductTournamentEvidenceIndex()
    let saved = try workspace.readProductTournamentConfig()

    try #require(outcome.result.status == .completed)
    try #require(outcome.record.scenarioID == config.scenarios[0].id)
    try #require(outcome.record.commitSha == head)
    try #require(outcome.record.verdict == .promising)
    try #require(outcome.record.scores.hasScores)
    try #require(outcome.record.scores.painRecognition == 4)
    try #require(outcome.record.scores.workflowImprovement == 4)
    try #require(outcome.record.scores.alternativeAdvantage == 4)
    try #require(outcome.record.scores.switchingReadiness == 4)
    try #require(outcome.record.scores.continuedUsePull == 4)
    try #require(outcome.record.scores.willingnessToPay == 4)
    try #require(outcome.record.willingnessToPayScore == 4)
    try #require(outcome.record.sponsorshipIntent.contains("sponsor"))
    try #require(index.summaries.map(\.runID) == [outcome.record.id])
    try #require(index.aggregate.pmfReadinessByExperiment.first?.averageScore == 4)
    try #require(saved.experiments[0].evidenceSummary.contains("completed the scenario"))
  }

  @Test func modelFreeRunStampsActiveTournamentRoundScope() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    var config = try makeScenarioRunConfig(commitSha: head)
    let scope = try activateRoundTwoTournamentScope(in: &config)
    try workspace.writeProductTournamentConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)

    let outcome = try await ProductTournamentScenarioCoordinator.runModelFree(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 180)
    )
    let stored = try workspace.readProductTournamentEvidenceRecord(id: outcome.record.id)
    let index = workspace.readProductTournamentEvidenceIndex()
    let summary = try #require(index.summaries.first)
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: try workspace.readProductTournamentConfig(),
      evidenceIndex: index
    )
    let markdown = ProductTournamentEvidenceMarkdownExporter.markdown(record: stored)

    try #require(outcome.record.tournamentID == scope.tournamentID)
    try #require(outcome.record.roundID == scope.roundID)
    try #require(outcome.record.contenderID == scope.contenderID)
    try #require(stored.tournamentID == scope.tournamentID)
    try #require(stored.roundID == scope.roundID)
    try #require(stored.contenderID == scope.contenderID)
    try #require(summary.tournamentID == scope.tournamentID)
    try #require(summary.roundID == scope.roundID)
    try #require(summary.contenderID == scope.contenderID)
    try #require(
      index.evidenceSummaries(for: config.tournaments[0], round: config.tournamentRounds[1]).count
        == 1)
    try #require(markdown.contains("- Tournament: \(scope.tournamentID)"))
    try #require(markdown.contains("- Tournament Round: \(scope.roundID)"))
    try #require(markdown.contains("- Contender: \(scope.contenderID)"))
    try #require(digest.contains("tournament \(scope.tournamentID)"))
    try #require(digest.contains("round \(scope.roundID)"))
    try #require(digest.contains("contender \(scope.contenderID)"))
  }

  @Test func personaModelRunWritesEvidenceTranscriptAndMode() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = try makeScenarioRunConfig(commitSha: head)
    try workspace.writeProductTournamentConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)
    let selector = ScriptedScenarioPersonaSelector(actionIDs: [
      "inspect_pain",
      "compare_current_alternative",
      "reduce_switching_objection",
      "start_solution_workflow",
      "provide_requested_input",
    ])

    let outcome = try await ProductTournamentScenarioCoordinator.runPersonaModel(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      personaSelector: selector,
      targetDecision: .promote,
      now: Date(timeIntervalSince1970: 160)
    )
    let stored = try workspace.readProductTournamentEvidenceRecord(id: outcome.record.id)
    let transcriptPath = try #require(stored.transcriptArtifactPath)
    let transcript = try String(
      contentsOf: workspace.compassURL.appending(path: transcriptPath),
      encoding: .utf8
    )

    try #require(outcome.result.status == .completed)
    try #require(outcome.result.mode == .personaModel)
    try #require(outcome.result.decisionIntent?.targetDecision == .promote)
    try #require(outcome.request.decisionIntent?.targetDecision == .promote)
    try #require(appRunner.inputs.first?.decisionIntent?.targetDecision == .promote)
    try #require(outcome.userMessage.contains("AI-user"))
    try #require(stored.mode == .personaModel)
    try #require(stored.decisionIntent?.targetDecision == .promote)
    try #require(stored.decisionIntentEvaluation?.outcome == .supportsTarget)
    try #require(stored.promptVersions == ["test.persona_action"])
    try #require(
      stored.personaActionRationales.contains {
        $0.contains("inspect_pain") && $0.contains("Scripted target user action")
      })
    try #require(stored.verdict == .promising)
    try #require(transcript.contains(#""phase":"choose""#))
    try #require(transcript.contains(#""chosenActionID":"inspect_pain""#))
    let summary = workspace.readProductTournamentEvidenceIndex().summaries.first
    try #require(summary?.mode == .personaModel)
    try #require(summary?.decisionIntent?.targetDecision == .promote)
    try #require(summary?.decisionIntentEvaluation?.outcome == .supportsTarget)
    try #require(summary?.personaActionRationales.first?.contains("inspect_pain") == true)
  }

  @Test func cohortModelFreeRunRunsEnabledScenariosAndSkipsDisabled() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    var config = try makeScenarioRunConfig(commitSha: head)
    let enabled = config.scenarios[0]
    let disabled = ProductScenario(
      id: "scenario-disabled",
      experimentID: enabled.experimentID,
      segmentID: enabled.segmentID,
      currentWorkflowID: enabled.currentWorkflowID,
      alternativeID: enabled.alternativeID,
      title: "Disabled support proof",
      task: "Do not run this disabled scenario.",
      successSignal: enabled.successSignal,
      targetCommitSha: head,
      maxTurns: enabled.maxTurns,
      appCommandTimeoutSeconds: enabled.appCommandTimeoutSeconds,
      enabled: false,
      createdAt: 21
    )
    config.scenarios.append(disabled)
    let cohort = config.scenarioCohorts[0]
    config.scenarioCohorts[0] = ProductScenarioCohort(
      id: cohort.id,
      title: cohort.title,
      experimentID: cohort.experimentID,
      scenarioIDs: [enabled.id, disabled.id],
      enabled: true,
      tags: cohort.tags
    )
    try workspace.writeProductTournamentConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)

    let outcome = try await ProductTournamentScenarioCoordinator.runCohortModelFree(
      experimentID: config.experiments[0].id,
      cohortID: cohort.id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 180)
    )
    let index = workspace.readProductTournamentEvidenceIndex()

    try #require(outcome.outcomes.count == 1)
    try #require(outcome.completedRunCount == 1)
    try #require(outcome.failedRunCount == 0)
    try #require(outcome.skippedScenarioIDs == [disabled.id])
    try #require(outcome.latestRecordID == outcome.outcomes[0].record.id)
    try #require(outcome.userMessage.contains("1 completed"))
    try #require(index.summaries.map(\.scenarioID) == [enabled.id])
  }

  @Test func modelFreeRunRecordsContractMissingAsUserVisibleFailureEvidence() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = try makeScenarioRunConfig(commitSha: head)
    try workspace.writeProductTournamentConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: false)

    let outcome = try await ProductTournamentScenarioCoordinator.runModelFree(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 120)
    )
    let index = workspace.readProductTournamentEvidenceIndex()

    try #require(outcome.result.status == .appContractMissing)
    try #require(outcome.record.failure?.status == .appContractMissing)
    try #require(outcome.userMessage.contains("contract is missing"))
    try #require(index.aggregate.failuresByKind["appContractMissing"] == 1)
  }

  @Test func requestConstructionReportsStaleScenarioCommit() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    var config = try makeScenarioRunConfig(commitSha: head)
    config.experiments[0].currentSha = "different-commit"

    do {
      _ = try await ProductTournamentScenarioCoordinator.request(
        experimentID: config.experiments[0].id,
        scenarioID: config.scenarios[0].id,
        in: config,
        projectTitle: "Scenario Helper",
        generatedAppWorkingDirectory: root
      )
      #expect(Bool(false), "Expected stale scenario commit error.")
    } catch let error as ProductTournamentScenarioRunError {
      guard case .staleScenarioCommit(let scenarioID, let expected, let actual) = error else {
        #expect(Bool(false), "Expected stale scenario commit, got \(error).")
        return
      }
      try #require(scenarioID == config.scenarios[0].id)
      try #require(expected == head)
      try #require(actual == "different-commit")
      try #require(error.localizedDescription.contains("Refresh or save"))
    }
  }

  @Test func modelFreeRunRecordsAppCommandFailureAsUserVisibleEvidence() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = try makeScenarioRunConfig(commitSha: head)
    try workspace.writeProductTournamentConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true) { _, _, _, _ in
      ProcessResult(exitCode: 2, stdout: "not json", stderr: "scenario command failed")
    }

    let outcome = try await ProductTournamentScenarioCoordinator.runModelFree(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 140)
    )

    try #require(outcome.result.status == .appCommandFailed)
    try #require(outcome.record.failure?.status == .appCommandFailed)
    try #require(outcome.userMessage.contains("exited with code 2"))
    try #require(
      workspace.readProductTournamentEvidenceIndex().aggregate.failuresByKind["appCommandFailed"] == 1)
  }
}

private final class MockScenarioExperienceAppRunner: ProductTournamentExperienceAppRunning {
  typealias Handler = (
    ProductTournamentExperienceInput,
    URL,
    AgentExecutionLaunchPlan,
    TimeInterval?
  ) async throws -> ProcessResult

  var contractAvailable: Bool
  var inputs: [ProductTournamentExperienceInput] = []
  private let handler: Handler

  init(
    contractAvailable: Bool,
    handler: @escaping Handler = { input, _, _, _ in
      ProcessResult(
        exitCode: 0,
        stdout: try encodeScenarioTrace(defaultScenarioTrace(for: input)),
        stderr: ""
      )
    }
  ) {
    self.contractAvailable = contractAvailable
    self.handler = handler
  }

  func productTournamentExperienceContractAvailable(workingDirectory: URL) async -> Bool {
    contractAvailable
  }

  func runProductTournamentExperience(
    input: ProductTournamentExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    inputs.append(input)
    return try await handler(input, workingDirectory, launchPlan, timeout)
  }
}

private final class ScriptedScenarioPersonaSelector: ProductTournamentPersonaActionSelecting {
  private var actionIDs: [String]

  init(actionIDs: [String]) {
    self.actionIDs = actionIDs
  }

  func chooseAction(
    context: ProductTournamentPersonaActionContext
  ) async throws -> ProductTournamentPersonaActionChoice {
    ProductTournamentPersonaActionChoice(
      promptVersionID: "test.persona_action",
      action: ProductTournamentExperienceAction(id: actionIDs.removeFirst()),
      rationale: "Scripted target user action.",
      rawResponse: #"{"actionID":"scripted"}"#
    )
  }

  func repairAction(
    context: ProductTournamentPersonaActionRepairContext
  ) async throws -> ProductTournamentPersonaActionChoice {
    ProductTournamentPersonaActionChoice(
      promptVersionID: "test.persona_repair",
      action: ProductTournamentExperienceAction(id: context.allowedActionIDs[0]),
      rationale: "Scripted repair action.",
      rawResponse: #"{"actionID":"repair"}"#
    )
  }
}

private func makeScenarioRunConfig(commitSha: String) throws -> ProductTournamentConfig {
  var config = ProductTournamentConfig.seedDefaults(
    projectTitle: "Scenario Helper",
    rawPain: "Support teams lose workflow context.",
    now: Date(timeIntervalSince1970: 10)
  )
  config.experiments[0].currentSha = commitSha
  config.scenarios = []
  config.scenarioCohorts = []
  let experiment = config.experiments[0]
  let draft = ProductScenarioDraft(
    id: "scenario-support",
    experimentID: experiment.id,
    segmentID: config.userSegments[0].id,
    currentWorkflowID: config.currentWorkflows[0].id,
    alternativeID: config.alternatives[0].id,
    title: "Support workflow proof",
    task: "Complete the support workflow with less context loss.",
    successSignal: "The support lead can name the next action.",
    targetCommitSha: commitSha,
    maxTurns: 6,
    appCommandTimeoutSeconds: 90
  )
  return try ProductTournamentScenarioCoordinator.saving(
    draft: draft,
    to: config,
    now: Date(timeIntervalSince1970: 20)
  )
}

private func activateRoundTwoTournamentScope(
  in config: inout ProductTournamentConfig
) throws -> ProductTournamentEvidenceScope {
  let experimentID = config.experiments[0].id
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

  return ProductTournamentEvidenceScope(
    tournamentID: config.tournaments[tournamentIndex].id,
    roundID: config.tournamentRounds[feasibilityRoundIndex].id,
    contenderID: contenderID
  )
}

private func setupScenarioRepo(at root: URL) async throws -> String {
  try initGitRepo(at: root)
  try await scenarioGit(["config", "user.email", "t@t"], in: root)
  try await scenarioGit(["config", "user.name", "t"], in: root)
  try writeFile("README.md", contents: "# Scenario repo\n", at: root)
  try await scenarioGit(["add", "README.md"], in: root)
  try await scenarioGit(["commit", "-q", "-m", "Initial"], in: root)
  return try await scenarioGitOutput(["rev-parse", "HEAD"], in: root)
}

private func defaultScenarioTrace(
  for input: ProductTournamentExperienceInput
) -> ProductTournamentExperienceTrace {
  let lastActionID = input.actions.last?.id
  let allowedIDs: [String]
  let terminalStatus: ProductTournamentExperienceTerminalStatus
  switch lastActionID {
  case nil:
    allowedIDs = ["inspect_pain", "compare_current_alternative", "start_solution_workflow"]
    terminalStatus = .inProgress
  case "inspect_pain":
    allowedIDs = ["compare_current_alternative", "start_solution_workflow"]
    terminalStatus = .inProgress
  case "compare_current_alternative":
    allowedIDs = ["reduce_switching_objection", "start_solution_workflow"]
    terminalStatus = .inProgress
  case "reduce_switching_objection":
    allowedIDs = ["start_solution_workflow"]
    terminalStatus = .inProgress
  case "start_solution_workflow":
    allowedIDs = ["provide_requested_input"]
    terminalStatus = .inProgress
  case "provide_requested_input":
    allowedIDs = []
    terminalStatus = .completed
  default:
    allowedIDs = []
    terminalStatus = .invalidAction
  }
  let actionIDs = Set(input.actions.map(\.id))
  return ProductTournamentExperienceTrace(
    schemaVersion: 1,
    painID: input.pain.id,
    solutionID: input.solution.id,
    experimentID: input.experiment.id,
    initialState: scenarioState(id: "initial"),
    turns: input.actions.enumerated().map { index, action in
      ProductTournamentExperienceTurn(
        index: index,
        action: action,
        state: scenarioState(id: "turn-\(index)-\(action.id)"),
        allowedNextActions: [],
        eventLog: ["turn:\(index):\(action.id)"]
      )
    },
    allowedNextActions: allowedIDs.map(scenarioAllowedAction),
    terminalStatus: terminalStatus,
    eventLog: ["last:\(lastActionID ?? "initial")"],
    painReliefSignals: ProductTournamentPainReliefSignals(
      painRecognized: actionIDs.contains("inspect_pain"),
      workflowAdvanced: actionIDs.contains("start_solution_workflow"),
      currentAlternativeAddressed: actionIDs.contains("compare_current_alternative"),
      switchingObjectionReduced: actionIDs.contains("reduce_switching_objection"),
      willingnessToPayScore: actionIDs.contains("provide_requested_input") ? 4 : 2,
      sponsorshipIntent: actionIDs.contains("provide_requested_input")
        ? "The simulated user would sponsor this workflow proof."
        : "The simulated user needs more proof before sponsorship.",
      missingCapabilityIDs: actionIDs.contains("provide_requested_input") ? [] : ["follow_up"],
      evidenceSummary: actionIDs.contains("provide_requested_input")
        ? "The model-free run completed the scenario."
        : "The model-free run is still gathering evidence."
    )
  )
}

private func scenarioState(id: String) -> ProductTournamentExperienceState {
  ProductTournamentExperienceState(
    id: id,
    headline: "Scenario \(id)",
    body: "Scenario body \(id)",
    semanticNodes: [
      ProductTournamentExperienceNode(id: "screen.headline", role: "heading", text: "Scenario \(id)")
    ],
    observations: ["observation:\(id)"],
    terminal: false
  )
}

private func scenarioAllowedAction(_ id: String) -> ProductTournamentExperienceAllowedAction {
  ProductTournamentExperienceAllowedAction(
    id: id,
    label: id.replacingOccurrences(of: "_", with: " "),
    description: "Allowed action \(id)",
    paramsSchema: .object(["type": .string("object")])
  )
}

private func encodeScenarioTrace(_ trace: ProductTournamentExperienceTrace) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(trace), as: UTF8.self)
}

private func scenarioGit(_ arguments: [String], in directory: URL) async throws {
  let result = try await ProcessRunner.runEnv(
    "git",
    arguments,
    workingDirectory: directory,
    timeout: 60
  )
  guard result.exitCode == 0 else {
    throw TestHelperError.gitCommandFailed(status: result.exitCode)
  }
}

private func scenarioGitOutput(_ arguments: [String], in directory: URL) async throws -> String {
  let result = try await ProcessRunner.runEnv(
    "git",
    arguments,
    workingDirectory: directory,
    timeout: 60
  )
  guard result.exitCode == 0 else {
    throw TestHelperError.gitCommandFailed(status: result.exitCode)
  }
  return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}
