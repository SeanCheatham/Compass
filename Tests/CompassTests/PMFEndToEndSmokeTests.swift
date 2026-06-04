import Foundation
import Testing

@testable import Compass

struct PMFEndToEndSmokeTests {
  @Test @MainActor func modelFreePMFSmokePersistsLoadsAndReachesPlanContext() async throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try FileManager.default.createDirectory(
      at: repoURL.appending(path: ".git"),
      withIntermediateDirectories: true
    )

    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()
    let config = PMFConfig.seedDefaults(
      projectTitle: "PMF Smoke",
      vision: "Prove that PMF evidence reaches planning without a live model.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try workspace.writePMFConfig(config)

    let hypothesis = try #require(config.hypotheses.first)
    let persona = try #require(config.personas.first)
    let task = try #require(config.tasks.first)
    let scenario = try #require(config.scenarios.first)

    let runner = PMFSimulationRunner(
      appRunner: SmokeExperienceAppRunner(),
      personaSelector: SmokePersonaSelector()
    )
    let result = await runner.run(
      PMFSimulationRequest(
        projectTitle: "PMF Smoke",
        hypothesis: hypothesis,
        persona: persona,
        task: task,
        scenario: scenario,
        generatedAppWorkingDirectory: repoURL,
        maxTurns: 4,
        appCommandTimeout: 5
      )
    )

    try #require(result.status == .completed)
    try #require(result.experienceTraceJSON != nil)
    try #require(result.experienceTraceHash != nil)

    let feedback = PMFFeedbackRecord(
      promptVersionID: Prompts.pmfFeedbackPromptVersionID,
      valueScore: 4,
      clarityScore: 3,
      trustScore: 3,
      switchLikelihood: 3,
      payLikelihood: 2,
      taskOutcome: .succeeded,
      topObjection: "The smoke persona still wants stronger proof of ROI.",
      missingCapability: "A concrete import or ROI example.",
      verdict: .somePull,
      summary: "The model-free smoke proves the product evidence path without live calls."
    )
    let record = PMFEvidenceRecord(
      runResult: result,
      id: "pmf-e2e-smoke",
      commitSHA: "abc123",
      startedAt: 1_700_000_010,
      endedAt: 1_700_000_020,
      feedback: feedback
    )
    let rawTranscript = try encodeJSON(result.rawPersonaActionTranscript)
    let stored = try workspace.writePMFEvidenceRecord(
      record,
      experienceTraceJSON: result.experienceTraceJSON,
      rawTranscriptJSON: rawTranscript
    )

    try #require(stored.artifacts.map(\.kind) == [.experienceTrace, .rawTranscript])
    let storedRecord = try workspace.readPMFEvidenceRecord(id: "pmf-e2e-smoke")
    try #require(storedRecord.feedback?.verdict == .somePull)

    let project = CompassProject(repoURL: repoURL)
    try await project.refreshFromWorkspace(requireStorageRoot: false)
    try #require(project.pmfConfig == config)
    try #require(project.pmfEvidenceIndex.summaries.map(\.runID) == ["pmf-e2e-smoke"])
    _ = PMFEvidenceTab(project: project).body

    let planPrompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: project.vision,
      focus: .feature,
      pmfConfig: project.pmfConfig,
      pmfEvidenceIndex: project.pmfEvidenceIndex
    )
    try #require(planPrompt.contains("## PMF Evidence"))
    try #require(planPrompt.contains("pmf-e2e-smoke"))
    try #require(planPrompt.contains("stronger proof of ROI"))
    try #require(!planPrompt.contains("rawResponse"))
  }
}

private final class SmokeExperienceAppRunner: PMFExperienceAppRunning {
  func experienceContractAvailable(workingDirectory: URL) async -> Bool {
    true
  }

  func runExperience(
    input: PMFExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    ProcessResult(exitCode: 0, stdout: try encodeJSON(smokeTrace(for: input)), stderr: "")
  }
}

private final class SmokePersonaSelector: PMFPersonaActionSelecting {
  private let preference = [
    "inspect_value_prop",
    "start_core_workflow",
    "provide_requested_input",
    "abandon_task",
  ]

  func chooseAction(context: PMFPersonaActionContext) async throws -> PMFPersonaActionChoice {
    let allowed = context.allowedActions.map(\.id)
    guard let selected = preference.first(where: { allowed.contains($0) }) ?? allowed.first else {
      throw SmokePersonaSelectorError.noAllowedChooseAction
    }
    return PMFPersonaActionChoice(
      action: PMFExperienceAction(id: selected),
      rationale: "Model-free smoke chooses the first useful allowed action.",
      rawResponse: #"{"actionId":"smoke"}"#
    )
  }

  func repairAction(context: PMFPersonaActionRepairContext) async throws -> PMFPersonaActionChoice {
    guard let selected = context.allowedActionIDs.first else {
      throw SmokePersonaSelectorError.noAllowedRepairAction
    }
    return PMFPersonaActionChoice(action: PMFExperienceAction(id: selected))
  }
}

private enum SmokePersonaSelectorError: Error {
  case noAllowedChooseAction
  case noAllowedRepairAction
}

private func smokeTrace(for input: PMFExperienceInput) -> PMFExperienceTrace {
  let lastActionID = input.actions.last?.id
  let stateID: String
  let terminalStatus: PMFExperienceTerminalStatus
  let allowedIDs: [String]

  switch lastActionID {
  case nil:
    stateID = "initial"
    terminalStatus = .inProgress
    allowedIDs = ["inspect_value_prop", "abandon_task"]
  case "inspect_value_prop":
    stateID = "value_prop_inspected"
    terminalStatus = .inProgress
    allowedIDs = ["start_core_workflow", "abandon_task"]
  case "start_core_workflow":
    stateID = "workflow_started"
    terminalStatus = .inProgress
    allowedIDs = ["provide_requested_input", "abandon_task"]
  case "provide_requested_input":
    stateID = "workflow_completed"
    terminalStatus = .completed
    allowedIDs = []
  case "abandon_task":
    stateID = "abandoned"
    terminalStatus = .abandoned
    allowedIDs = []
  default:
    stateID = "invalid_action"
    terminalStatus = .invalidAction
    allowedIDs = []
  }

  return PMFExperienceTrace(
    schemaVersion: 1,
    scenario: input.scenario,
    initialState: smokeState(id: "initial"),
    turns: input.actions.enumerated().map { index, action in
      PMFExperienceTurn(
        index: index,
        action: action,
        state: smokeState(id: "turn-\(index)-\(action.id)"),
        allowedNextActions: [],
        eventLog: ["turn:\(index):\(action.id)"]
      )
    },
    allowedNextActions: allowedIDs.map(smokeAllowedAction),
    terminalStatus: terminalStatus,
    eventLog: ["state:\(stateID)"]
  )
}

private func smokeState(id: String) -> PMFExperienceState {
  PMFExperienceState(
    id: id,
    headline: "PMF smoke \(id)",
    body: "Semantic body for \(id)",
    semanticNodes: [
      PMFExperienceNode(id: "headline", role: "heading", text: "PMF smoke \(id)")
    ],
    observations: ["observation:\(id)"],
    terminal: id == "workflow_completed" || id == "abandoned" || id == "invalid_action"
  )
}

private func smokeAllowedAction(_ id: String) -> PMFExperienceAllowedAction {
  PMFExperienceAllowedAction(
    id: id,
    label: id.replacingOccurrences(of: "_", with: " "),
    description: "Allowed smoke action \(id)",
    paramsSchema: .object(["type": .string("object")])
  )
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "PMFEndToEndSmokeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}
