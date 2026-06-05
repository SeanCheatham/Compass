import Foundation
import Testing

@testable import Compass

struct ProductizationScenarioRunTests {
  @Test func scenarioDraftPersistsAndAddsScenarioToExperimentCohort() throws {
    var config = ProductizationConfig.seedDefaults(
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

    let saved = try ProductizationScenarioCoordinator.saving(
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
    let editedConfig = try ProductizationScenarioCoordinator.saving(
      draft: edited,
      to: saved,
      now: Date(timeIntervalSince1970: 30)
    )
    let editedCohort = try #require(editedConfig.scenarioCohorts.first { $0.id == cohort.id })
    try #require(editedCohort.title == "Edited support cohort")
    try #require(!editedCohort.enabled)
    try #require(editedCohort.scenarioIDs == ["scenario-support"])
  }

  @Test func requestConstructionUsesScenarioTaskSuccessSignalAndSelectedAlternative() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let config = try makeScenarioRunConfig(commitSha: head)
    let scenario = config.scenarios[0]

    let request = try await ProductizationScenarioCoordinator.request(
      experimentID: config.experiments[0].id,
      scenarioID: scenario.id,
      in: config,
      projectTitle: "Scenario Helper",
      generatedAppWorkingDirectory: root
    )
    let input = request.experienceInput(actions: [])

    try #require(request.commitSha == head)
    try #require(request.maxTurns == scenario.maxTurns)
    try #require(request.appCommandTimeout == scenario.appCommandTimeoutSeconds)
    try #require(request.mode == .modelFree)
    try #require(input.scenario.task.contains(scenario.task))
    try #require(input.scenario.task.contains(scenario.successSignal))
    try #require(input.experiment.successSignal == scenario.successSignal)
    try #require(input.alternatives.map(\.id) == [scenario.alternativeID])

    let personaRequest = try await ProductizationScenarioCoordinator.request(
      experimentID: config.experiments[0].id,
      scenarioID: scenario.id,
      in: config,
      projectTitle: "Scenario Helper",
      generatedAppWorkingDirectory: root,
      mode: .personaModel
    )
    try #require(personaRequest.mode == .personaModel)
  }

  @Test func modelFreeRunWritesEvidenceAndRefreshableIndex() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = try makeScenarioRunConfig(commitSha: head)
    try workspace.writeProductizationConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)

    let outcome = try await ProductizationScenarioCoordinator.runModelFree(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 100)
    )
    let index = workspace.readProductizationEvidenceIndex()
    let saved = try workspace.readProductizationConfig()

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
    try #require(index.summaries.map(\.runID) == [outcome.record.id])
    try #require(index.aggregate.pmfReadinessByExperiment.first?.averageScore == 4)
    try #require(saved.experiments[0].evidenceSummary.contains("completed the scenario"))
  }

  @Test func personaModelRunWritesEvidenceTranscriptAndMode() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let head = try await setupScenarioRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = try makeScenarioRunConfig(commitSha: head)
    try workspace.writeProductizationConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)
    let selector = ScriptedScenarioPersonaSelector(actionIDs: [
      "inspect_pain",
      "compare_current_alternative",
      "reduce_switching_objection",
      "start_solution_workflow",
      "provide_requested_input",
    ])

    let outcome = try await ProductizationScenarioCoordinator.runPersonaModel(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      personaSelector: selector,
      now: Date(timeIntervalSince1970: 160)
    )
    let stored = try workspace.readProductizationEvidenceRecord(id: outcome.record.id)
    let transcriptPath = try #require(stored.transcriptArtifactPath)
    let transcript = try String(
      contentsOf: workspace.compassURL.appending(path: transcriptPath),
      encoding: .utf8
    )

    try #require(outcome.result.status == .completed)
    try #require(outcome.result.mode == .personaModel)
    try #require(outcome.userMessage.contains("AI-user"))
    try #require(stored.mode == .personaModel)
    try #require(stored.promptVersions == ["test.persona_action"])
    try #require(
      stored.personaActionRationales.contains {
        $0.contains("inspect_pain") && $0.contains("Scripted target user action")
      })
    try #require(stored.verdict == .promising)
    try #require(transcript.contains(#""phase":"choose""#))
    try #require(transcript.contains(#""chosenActionID":"inspect_pain""#))
    let summary = workspace.readProductizationEvidenceIndex().summaries.first
    try #require(summary?.mode == .personaModel)
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
    try workspace.writeProductizationConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true)

    let outcome = try await ProductizationScenarioCoordinator.runCohortModelFree(
      experimentID: config.experiments[0].id,
      cohortID: cohort.id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 180)
    )
    let index = workspace.readProductizationEvidenceIndex()

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
    try workspace.writeProductizationConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: false)

    let outcome = try await ProductizationScenarioCoordinator.runModelFree(
      experimentID: config.experiments[0].id,
      scenarioID: config.scenarios[0].id,
      in: workspace,
      projectTitle: "Scenario Helper",
      appRunner: appRunner,
      now: Date(timeIntervalSince1970: 120)
    )
    let index = workspace.readProductizationEvidenceIndex()

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
      _ = try await ProductizationScenarioCoordinator.request(
        experimentID: config.experiments[0].id,
        scenarioID: config.scenarios[0].id,
        in: config,
        projectTitle: "Scenario Helper",
        generatedAppWorkingDirectory: root
      )
      #expect(Bool(false), "Expected stale scenario commit error.")
    } catch let error as ProductizationScenarioRunError {
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
    try workspace.writeProductizationConfig(config)
    let appRunner = MockScenarioExperienceAppRunner(contractAvailable: true) { _, _, _, _ in
      ProcessResult(exitCode: 2, stdout: "not json", stderr: "scenario command failed")
    }

    let outcome = try await ProductizationScenarioCoordinator.runModelFree(
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
      workspace.readProductizationEvidenceIndex().aggregate.failuresByKind["appCommandFailed"] == 1)
  }
}

private final class MockScenarioExperienceAppRunner: ProductizationExperienceAppRunning {
  typealias Handler = (
    ProductizationExperienceInput,
    URL,
    AgentExecutionLaunchPlan,
    TimeInterval?
  ) async throws -> ProcessResult

  var contractAvailable: Bool
  var inputs: [ProductizationExperienceInput] = []
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

  func productizationExperienceContractAvailable(workingDirectory: URL) async -> Bool {
    contractAvailable
  }

  func runProductizationExperience(
    input: ProductizationExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    inputs.append(input)
    return try await handler(input, workingDirectory, launchPlan, timeout)
  }
}

private final class ScriptedScenarioPersonaSelector: ProductizationPersonaActionSelecting {
  private var actionIDs: [String]

  init(actionIDs: [String]) {
    self.actionIDs = actionIDs
  }

  func chooseAction(
    context: ProductizationPersonaActionContext
  ) async throws -> ProductizationPersonaActionChoice {
    ProductizationPersonaActionChoice(
      promptVersionID: "test.persona_action",
      action: ProductizationExperienceAction(id: actionIDs.removeFirst()),
      rationale: "Scripted target user action.",
      rawResponse: #"{"actionID":"scripted"}"#
    )
  }

  func repairAction(
    context: ProductizationPersonaActionRepairContext
  ) async throws -> ProductizationPersonaActionChoice {
    ProductizationPersonaActionChoice(
      promptVersionID: "test.persona_repair",
      action: ProductizationExperienceAction(id: context.allowedActionIDs[0]),
      rationale: "Scripted repair action.",
      rawResponse: #"{"actionID":"repair"}"#
    )
  }
}

private func makeScenarioRunConfig(commitSha: String) throws -> ProductizationConfig {
  var config = ProductizationConfig.seedDefaults(
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
  return try ProductizationScenarioCoordinator.saving(
    draft: draft,
    to: config,
    now: Date(timeIntervalSince1970: 20)
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
  for input: ProductizationExperienceInput
) -> ProductizationExperienceTrace {
  let lastActionID = input.actions.last?.id
  let allowedIDs: [String]
  let terminalStatus: ProductizationExperienceTerminalStatus
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
  return ProductizationExperienceTrace(
    schemaVersion: 1,
    painID: input.pain.id,
    solutionID: input.solution.id,
    experimentID: input.experiment.id,
    initialState: scenarioState(id: "initial"),
    turns: input.actions.enumerated().map { index, action in
      ProductizationExperienceTurn(
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
    painReliefSignals: ProductizationPainReliefSignals(
      painRecognized: actionIDs.contains("inspect_pain"),
      workflowAdvanced: actionIDs.contains("start_solution_workflow"),
      currentAlternativeAddressed: actionIDs.contains("compare_current_alternative"),
      switchingObjectionReduced: actionIDs.contains("reduce_switching_objection"),
      missingCapabilityIDs: actionIDs.contains("provide_requested_input") ? [] : ["follow_up"],
      evidenceSummary: actionIDs.contains("provide_requested_input")
        ? "The model-free run completed the scenario."
        : "The model-free run is still gathering evidence."
    )
  )
}

private func scenarioState(id: String) -> ProductizationExperienceState {
  ProductizationExperienceState(
    id: id,
    headline: "Scenario \(id)",
    body: "Scenario body \(id)",
    semanticNodes: [
      ProductizationExperienceNode(id: "screen.headline", role: "heading", text: "Scenario \(id)")
    ],
    observations: ["observation:\(id)"],
    terminal: false
  )
}

private func scenarioAllowedAction(_ id: String) -> ProductizationExperienceAllowedAction {
  ProductizationExperienceAllowedAction(
    id: id,
    label: id.replacingOccurrences(of: "_", with: " "),
    description: "Allowed action \(id)",
    paramsSchema: .object(["type": .string("object")])
  )
}

private func encodeScenarioTrace(_ trace: ProductizationExperienceTrace) throws -> String {
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
