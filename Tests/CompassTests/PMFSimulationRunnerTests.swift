import Foundation
import Testing

@testable import Compass

struct PMFSimulationRunnerTests {
  @Test func runnerCompletesCannedScenarioAndValidatesDeterminism() async throws {
    let appRunner = MockExperienceAppRunner()
    let selector = ScriptedPersonaSelector(
      choices: [
        .init(action: PMFExperienceAction(id: "inspect_value_prop"), rawResponse: "inspect"),
        .init(action: PMFExperienceAction(id: "start_core_workflow"), rawResponse: "start"),
        .init(action: PMFExperienceAction(id: "provide_requested_input"), rawResponse: "provide"),
      ]
    )
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 4))

    try #require(result.status == .completed)
    try #require(result.isSuccess)
    try #require(result.actions.map(\.id) == [
      "inspect_value_prop",
      "start_core_workflow",
      "provide_requested_input",
    ])
    try #require(result.experienceTraceHash != nil)
    try #require(result.failure == nil)
    try #require(appRunner.inputs.filter { $0.actions.count == 3 }.count == 3)
    try #require(selector.chooseContexts.map(\.turnIndex) == [0, 1, 2])
  }

  @Test func invalidPersonaActionGetsOneRepairAndIsNotPassedToApp() async throws {
    let appRunner = MockExperienceAppRunner()
    let selector = ScriptedPersonaSelector(
      choices: [
        .init(action: PMFExperienceAction(id: "invent_new_button"), rawResponse: "bad")
      ],
      repairs: [
        .init(action: PMFExperienceAction(id: "start_core_workflow"), rawResponse: "fixed")
      ]
    )
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 1))

    try #require(result.status == .maxTurnsReached)
    try #require(result.actions.map(\.id) == ["start_core_workflow"])
    try #require(result.rawPersonaActionTranscript.map(\.wasValid) == [false, true])
    try #require(result.rawPersonaActionTranscript.map(\.phase) == [.choose, .repair])
    let appActionIDs = appRunner.inputs.flatMap { $0.actions.map(\.id) }
    try #require(!appActionIDs.contains("invent_new_button"))
    try #require(
      selector.repairContexts.first?.allowedActionIDs.contains("start_core_workflow") == true)
  }

  @Test func invalidPersonaActionAfterRepairFailsRun() async throws {
    let appRunner = MockExperienceAppRunner()
    let selector = ScriptedPersonaSelector(
      choices: [
        .init(action: PMFExperienceAction(id: "invent_new_button"), rawResponse: "bad")
      ],
      repairs: [
        .init(action: PMFExperienceAction(id: "still_bad"), rawResponse: "still bad")
      ]
    )
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 3))

    try #require(result.status == .invalidPersonaAction)
    try #require(result.actions.isEmpty)
    try #require(result.failure?.status == .invalidPersonaAction)
    let appActionIDs = appRunner.inputs.flatMap { $0.actions.map(\.id) }
    try #require(!appActionIDs.contains("invent_new_button"))
    try #require(!appActionIDs.contains("still_bad"))
  }

  @Test func runnerDetectsNondeterministicFinalTrace() async throws {
    let appRunner = MockExperienceAppRunner { input, callIndex in
      var trace = defaultTrace(for: input)
      if !input.actions.isEmpty {
        trace.eventLog.append("call:\(callIndex)")
      }
      return ProcessResult(exitCode: 0, stdout: try encodeTrace(trace), stderr: "")
    }
    let selector = ScriptedPersonaSelector(
      choices: [.init(action: PMFExperienceAction(id: "inspect_value_prop"))]
    )
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 1))

    try #require(result.status == .nondeterministicExperienceTrace)
    try #require(result.failure?.status == .nondeterministicExperienceTrace)
    try #require(result.experienceTraceHash != nil)
  }

  @Test func noAllowedActionsInInProgressTraceFailsRun() async throws {
    let appRunner = MockExperienceAppRunner { input, _ in
      var trace = defaultTrace(for: input)
      trace.terminalStatus = .inProgress
      trace.allowedNextActions = []
      return ProcessResult(exitCode: 0, stdout: try encodeTrace(trace), stderr: "")
    }
    let selector = ScriptedPersonaSelector(
      choices: [.init(action: PMFExperienceAction(id: "inspect_value_prop"))]
    )
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 2))

    try #require(result.status == .noAllowedActions)
    try #require(result.actions.isEmpty)
    try #require(selector.chooseContexts.isEmpty)
  }

  @Test func appCommandFailureAndInvalidJSONAreRecorded() async throws {
    let failingAppRunner = MockExperienceAppRunner { _, _ in
      ProcessResult(exitCode: 42, stdout: "partial", stderr: "boom")
    }
    let selector = ScriptedPersonaSelector(
      choices: [.init(action: PMFExperienceAction(id: "inspect_value_prop"))]
    )
    var runner = PMFSimulationRunner(appRunner: failingAppRunner, personaSelector: selector)

    var result = await runner.run(makeRequest(maxTurns: 2))
    try #require(result.status == .appCommandFailed)
    try #require(result.failure?.stderr == "boom")

    let invalidJSONRunner = MockExperienceAppRunner { _, _ in
      ProcessResult(exitCode: 0, stdout: "not-json", stderr: "")
    }
    runner = PMFSimulationRunner(appRunner: invalidJSONRunner, personaSelector: selector)
    result = await runner.run(makeRequest(maxTurns: 2))
    try #require(result.status == .appOutputNotJSON)
    try #require(result.failure?.stdout == "not-json")
  }

  @Test func missingExperienceContractFailsBeforeCallingPersona() async throws {
    let appRunner = MockExperienceAppRunner()
    appRunner.contractAvailable = false
    let selector = ScriptedPersonaSelector(
      choices: [.init(action: PMFExperienceAction(id: "inspect_value_prop"))]
    )
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 2))

    try #require(result.status == .appContractMissing)
    try #require(appRunner.inputs.isEmpty)
    try #require(selector.chooseContexts.isEmpty)
  }

  @Test func personaSelectionFailureIsRecorded() async throws {
    let appRunner = MockExperienceAppRunner()
    let selector = ScriptedPersonaSelector(choices: [])
    selector.throwOnChoose = true
    let runner = PMFSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeRequest(maxTurns: 2))

    try #require(result.status == .personaCallFailed)
    try #require(result.failure?.status == .personaCallFailed)
  }

  @Test func cliRunnerBuildsExperienceCommandAndPreservesLaunchPlanRoute() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeExperienceContractMarkers(to: root)

    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.44",
      hostWorktreeURL: root,
      guestWorkspacePath: "/Users/compass/worktrees/demo"
    )
    let launchPlan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    var capturedInvocation: AgentExecutionInvocation?
    let appRunner = PMFExperienceCLIAppRunner { invocation, input, timeout, _, _ in
      capturedInvocation = invocation
      try #require(input == nil)
      try #require(timeout == 99)
      return ProcessResult(exitCode: 0, stdout: try encodeTrace(defaultTrace()), stderr: "")
    }

    try #require(await appRunner.experienceContractAvailable(workingDirectory: root))
    _ = try await appRunner.runExperience(
      input: PMFExperienceInput(
        scenario: PMFExperienceScenario(
          seed: "quote's seed",
          personaSummary: "persona",
          task: "task"
        )
      ),
      workingDirectory: root,
      launchPlan: launchPlan,
      timeout: 99
    )

    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    try #require(invocation.workingDirectory == root.standardizedFileURL)
    let shell = try #require(invocation.arguments.last)
    try #require(shell.contains("cargo run -p app-cli -- experience --input"))
    try #require(shell.contains("quote'\\''s seed"))
  }

  @Test func runnerExecutesGeneratedScaffoldWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["COMPASS_RUN_GENERATED_RUST_PMF_RUNNER"] == "1" else {
      return
    }

    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try RustProjectScaffold.write(
      to: root,
      options: RustProjectScaffold.Options(projectName: "PMF Runner Fixture")
    )
    let selector = ScriptedPersonaSelector(
      choices: [
        .init(action: PMFExperienceAction(id: "inspect_value_prop")),
        .init(action: PMFExperienceAction(id: "start_core_workflow")),
        .init(action: PMFExperienceAction(id: "provide_requested_input")),
      ]
    )
    let runner = PMFSimulationRunner(
      appRunner: PMFExperienceCLIAppRunner(),
      personaSelector: selector
    )

    let result = await runner.run(
      makeRequest(generatedAppWorkingDirectory: root, maxTurns: 4, appCommandTimeout: 20 * 60)
    )

    try #require(result.status == .completed)
    try #require(result.experienceTraceHash != nil)
  }
}

private final class MockExperienceAppRunner: PMFExperienceAppRunning {
  typealias Handler = (PMFExperienceInput, Int) async throws -> ProcessResult

  var contractAvailable = true
  var inputs: [PMFExperienceInput] = []
  var launchPlans: [AgentExecutionLaunchPlan] = []
  private let handler: Handler

  init(handler: @escaping Handler = { input, _ in
    ProcessResult(exitCode: 0, stdout: try encodeTrace(defaultTrace(for: input)), stderr: "")
  }) {
    self.handler = handler
  }

  func experienceContractAvailable(workingDirectory: URL) async -> Bool {
    contractAvailable
  }

  func runExperience(
    input: PMFExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    inputs.append(input)
    launchPlans.append(launchPlan)
    return try await handler(input, inputs.count)
  }
}

private final class ScriptedPersonaSelector: PMFPersonaActionSelecting {
  var choices: [PMFPersonaActionChoice]
  var repairs: [PMFPersonaActionChoice]
  var chooseContexts: [PMFPersonaActionContext] = []
  var repairContexts: [PMFPersonaActionRepairContext] = []
  var throwOnChoose = false
  var throwOnRepair = false

  init(
    choices: [PMFPersonaActionChoice],
    repairs: [PMFPersonaActionChoice] = []
  ) {
    self.choices = choices
    self.repairs = repairs
  }

  func chooseAction(context: PMFPersonaActionContext) async throws -> PMFPersonaActionChoice {
    chooseContexts.append(context)
    if throwOnChoose {
      throw PMFSimulationRunnerTestError.personaFailed
    }
    return choices.isEmpty
      ? PMFPersonaActionChoice(action: PMFExperienceAction(id: "abandon_task"))
      : choices.removeFirst()
  }

  func repairAction(context: PMFPersonaActionRepairContext) async throws -> PMFPersonaActionChoice {
    repairContexts.append(context)
    if throwOnRepair {
      throw PMFSimulationRunnerTestError.personaFailed
    }
    return repairs.isEmpty
      ? PMFPersonaActionChoice(action: PMFExperienceAction(id: "abandon_task"))
      : repairs.removeFirst()
  }
}

private enum PMFSimulationRunnerTestError: Error {
  case personaFailed
}

private func makeRequest(
  generatedAppWorkingDirectory: URL = URL(fileURLWithPath: "/tmp/pmf-runner-fixture"),
  maxTurns: Int,
  appCommandTimeout: TimeInterval? = 120
) -> PMFSimulationRequest {
  let config = PMFConfig.seedDefaults(
    projectTitle: "Compass PMF",
    vision: "A tool for proving product fit with generated apps.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let hypothesis = config.hypotheses[0]
  let persona = config.personas[0]
  let task = config.tasks[0]
  let scenario = PMFScenario(
    id: "scenario",
    title: "Scenario",
    hypothesisID: hypothesis.id,
    personaID: persona.id,
    taskID: task.id,
    seed: "scenario-seed"
  )
  return PMFSimulationRequest(
    projectTitle: "Compass PMF",
    hypothesis: hypothesis,
    persona: persona,
    task: task,
    scenario: scenario,
    generatedAppWorkingDirectory: generatedAppWorkingDirectory,
    maxTurns: maxTurns,
    appCommandTimeout: appCommandTimeout
  )
}

private func defaultTrace(
  for input: PMFExperienceInput = PMFExperienceInput(
    scenario: PMFExperienceScenario(seed: "seed", personaSummary: "persona", task: "task")
  )
) -> PMFExperienceTrace {
  let lastActionID = input.actions.last?.id
  let stateID: String
  let terminalStatus: PMFExperienceTerminalStatus
  let allowedIDs: [String]

  switch lastActionID {
  case nil:
    stateID = "initial"
    terminalStatus = .inProgress
    allowedIDs = [
      "inspect_value_prop",
      "start_core_workflow",
      "compare_with_current_alternative",
      "ask_for_help",
      "abandon_task",
    ]
  case "inspect_value_prop":
    stateID = "value_prop_inspected"
    terminalStatus = .inProgress
    allowedIDs = [
      "start_core_workflow",
      "compare_with_current_alternative",
      "ask_for_help",
      "abandon_task",
    ]
  case "start_core_workflow":
    stateID = "workflow_started"
    terminalStatus = .inProgress
    allowedIDs = ["provide_requested_input", "ask_for_help", "abandon_task"]
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

  let currentState = state(id: stateID, terminal: terminalStatus != .inProgress)
  return PMFExperienceTrace(
    schemaVersion: 1,
    scenario: input.scenario,
    initialState: state(id: "initial"),
    turns: input.actions.enumerated().map { index, action in
      PMFExperienceTurn(
        index: index,
        action: action,
        state: state(id: "turn-\(index)-\(action.id)"),
        allowedNextActions: [],
        eventLog: ["turn:\(index):\(action.id)"]
      )
    },
    allowedNextActions: allowedIDs.map(allowedAction),
    terminalStatus: terminalStatus,
    eventLog: ["state:\(currentState.id)"]
  )
}

private func state(id: String, terminal: Bool = false) -> PMFExperienceState {
  PMFExperienceState(
    id: id,
    headline: "Headline \(id)",
    body: "Body \(id)",
    semanticNodes: [
      PMFExperienceNode(id: "screen.headline", role: "heading", text: "Headline \(id)")
    ],
    observations: ["observation:\(id)"],
    terminal: terminal
  )
}

private func allowedAction(_ id: String) -> PMFExperienceAllowedAction {
  PMFExperienceAllowedAction(
    id: id,
    label: id.replacingOccurrences(of: "_", with: " "),
    description: "Allowed action \(id)",
    paramsSchema: .object(["type": .string("object")])
  )
}

private func encodeTrace(_ trace: PMFExperienceTrace) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(trace), as: UTF8.self)
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "PMFSimulationRunnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}

private func writeExperienceContractMarkers(to root: URL) throws {
  let paths = [
    "Cargo.toml",
    "crates/app-cli/Cargo.toml",
    "crates/app-core/Cargo.toml",
    "schemas/experience-input.schema.json",
    "schemas/experience-trace.schema.json",
  ]
  for path in paths {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "".write(to: url, atomically: true, encoding: .utf8)
  }
}
