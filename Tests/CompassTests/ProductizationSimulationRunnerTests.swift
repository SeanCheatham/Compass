import Foundation
import Testing

@testable import Compass

struct ProductizationSimulationRunnerTests {
  @Test func modelFreeRunnerCompletesFixtureAndValidatesDeterminism() async throws {
    let appRunner = MockProductizationExperienceAppRunner()
    let runner = ProductizationSimulationRunner(appRunner: appRunner)

    let result = await runner.run(makeProductizationRequest(maxTurns: 6))

    try #require(result.status == .completed)
    try #require(result.isSuccess)
    try #require(result.mode == .modelFree)
    try #require(
      result.actions.map(\.id) == [
        "inspect_pain",
        "compare_current_alternative",
        "reduce_switching_objection",
        "start_solution_workflow",
        "provide_requested_input",
      ])
    try #require(result.experienceTraceHash != nil)
    try #require(result.productizationTrace?.painReliefSignals.currentAlternativeAddressed == true)
    try #require(appRunner.inputs.filter { $0.actions.count == 5 }.count == 3)

    let record = ProductizationEvidenceRecord(
      runResult: result,
      id: "runner-score",
      startedAt: 10,
      endedAt: 20
    )
    try #require(record.verdict == .promising)
    try #require(record.scores.painRecognition == 4)
    try #require(record.scores.workflowImprovement == 4)
    try #require(record.scores.alternativeAdvantage == 4)
    try #require(record.scores.switchingReadiness == 4)
    try #require(record.scores.continuedUsePull == 4)
    try #require(record.currentAlternativeComparison.contains("Shared spreadsheet"))
  }

  @Test func painReliefSignalsDecodeLegacyTraceWithoutComparison() throws {
    let json = """
      {
        "painRecognized": true,
        "workflowAdvanced": true,
        "currentAlternativeAddressed": true,
        "switchingObjectionReduced": false,
        "missingCapabilityIDs": [],
        "evidenceSummary": "Legacy trace."
      }
      """

    let signals = try JSONDecoder().decode(
      ProductizationPainReliefSignals.self,
      from: Data(json.utf8)
    )

    try #require(signals.currentAlternativeAddressed)
    try #require(signals.currentAlternativeComparison.isEmpty)
  }

  @Test func personaModelRejectsInventedActionsAndAllowsOneRepair() async throws {
    let appRunner = MockProductizationExperienceAppRunner()
    let selector = ScriptedProductizationPersonaSelector(
      choices: [
        .init(action: ProductizationExperienceAction(id: "invent_new_button"))
      ],
      repairs: [
        .init(action: ProductizationExperienceAction(id: "inspect_pain"))
      ]
    )
    let runner = ProductizationSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeProductizationRequest(mode: .personaModel, maxTurns: 1))

    try #require(result.status == .maxTurnsReached)
    try #require(result.actions.map(\.id) == ["inspect_pain"])
    try #require(result.rawPersonaActionTranscript.map(\.wasValid) == [false, true])
    try #require(result.rawPersonaActionTranscript.map(\.phase) == [.choose, .repair])
    let appActionIDs = appRunner.inputs.flatMap { $0.actions.map(\.id) }
    try #require(!appActionIDs.contains("invent_new_button"))
    try #require(selector.repairContexts.first?.allowedActionIDs.contains("inspect_pain") == true)
  }

  @Test func personaModelFailsWhenRepairStillInventsAction() async throws {
    let appRunner = MockProductizationExperienceAppRunner()
    let selector = ScriptedProductizationPersonaSelector(
      choices: [.init(action: ProductizationExperienceAction(id: "invent_new_button"))],
      repairs: [.init(action: ProductizationExperienceAction(id: "still_bad"))]
    )
    let runner = ProductizationSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeProductizationRequest(mode: .personaModel, maxTurns: 3))

    try #require(result.status == .invalidPersonaAction)
    try #require(result.actions.isEmpty)
    try #require(result.failure?.status == .invalidPersonaAction)
  }

  @Test func cliRunnerUsesProductizationContractPathsAndCommand() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeProductizationExperienceContractMarkers(to: root)

    var capturedInvocation: AgentExecutionInvocation?
    let appRunner = ProductizationExperienceCLIAppRunner { invocation, input, timeout, _, _ in
      capturedInvocation = invocation
      try #require(input == nil)
      try #require(timeout == 99)
      return ProcessResult(
        exitCode: 0, stdout: try encodeTrace(defaultProductizationTrace()), stderr: "")
    }

    try #require(await appRunner.productizationExperienceContractAvailable(workingDirectory: root))
    _ = try await appRunner.runProductizationExperience(
      input: makeProductizationRequest().experienceInput(actions: []),
      workingDirectory: root,
      launchPlan: .host(),
      timeout: 99
    )

    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    let shell = try #require(invocation.arguments.last)
    try #require(shell.contains("cargo run -p app-cli -- productization-experience --input"))
    try #require(shell.contains("weekly-reporting-takes-too-long-pain"))
  }

  @Test func runnerExecutesGeneratedScaffoldWhenRequested() async throws {
    guard
      ProcessInfo.processInfo.environment["COMPASS_RUN_GENERATED_RUST_PRODUCTIZATION_RUNNER"] == "1"
    else {
      return
    }

    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try RustProjectScaffold.write(
      to: root,
      options: RustProjectScaffold.Options(projectName: "Productization Runner Fixture")
    )

    let runner = ProductizationSimulationRunner(appRunner: ProductizationExperienceCLIAppRunner())
    let result = await runner.run(
      makeProductizationRequest(
        generatedAppWorkingDirectory: root,
        maxTurns: 6,
        appCommandTimeout: 20 * 60
      )
    )

    try #require(result.status == .completed)
    try #require(result.experienceTraceHash != nil)
  }

  @Test func foundationModelsPersonaSelectorParsesFencedJSONAliasesAndParams() throws {
    let choice = try ProductizationFoundationModelsPersonaSelector.parseChoice(
      """
      ```json
      {"action_id":"inspect_pain","reason":"The user needs to see if this matches the pain.","params":{"depth":"quick"}}
      ```
      """,
      promptVersionID: "test.persona"
    )

    try #require(choice.promptVersionID == "test.persona")
    try #require(choice.action.id == "inspect_pain")
    try #require(choice.rationale.contains("matches the pain"))
    try #require(choice.action.params == .object(["depth": .string("quick")]))
  }

  @Test func foundationModelsPersonaSelectorBuildsChoiceAndRepairPrompts() async throws {
    let stream = PersonaTextStream(
      responses: [
        #"{"actionID":"inspect_pain","rationale":"First verify the pain is real."}"#,
        #"{"actionID":"compare_current_alternative","rationale":"Now compare against the spreadsheet."}"#,
      ]
    )
    let selector = ProductizationFoundationModelsPersonaSelector(
      streamText: { prompt in await stream.stream(prompt) }
    )
    let context = makePersonaActionContext()

    let choice = try await selector.chooseAction(context: context)
    try #require(choice.action.id == "inspect_pain")
    try #require(choice.promptVersionID == "productization.persona_action.foundation_models.v3")
    try #require(stream.prompts[0].contains("skeptical target user"))
    try #require(stream.prompts[0].contains("PMF scorecard to stress-test"))
    try #require(stream.prompts[0].contains("switching readiness"))
    try #require(stream.prompts[0].contains("reasons the user would keep the current alternative"))
    try #require(stream.prompts[0].contains("Persona constraints"))
    try #require(stream.prompts[0].contains("Decision criteria"))
    try #require(stream.prompts[0].contains("Current workflow failure modes"))
    try #require(stream.prompts[0].contains("Required proof"))
    try #require(stream.prompts[0].contains("Prototype scope"))
    try #require(stream.prompts[0].contains("Scenario task"))
    try #require(stream.prompts[0].contains("Scenario success signal"))
    try #require(stream.prompts[0].contains("Reporting is reusable in the weekly review"))
    try #require(stream.prompts[0].contains("manual export"))
    try #require(stream.prompts[0].contains("Allowed actions"))
    try #require(stream.prompts[0].contains("Weekly reporting takes too long."))

    let repair = try await selector.repairAction(
      context: ProductizationPersonaActionRepairContext(
        actionContext: context,
        invalidChoice: ProductizationPersonaActionChoice(
          action: ProductizationExperienceAction(id: "invent_new_button")
        ),
        allowedActionIDs: context.allowedActions.map(\.id)
      )
    )
    try #require(repair.action.id == "compare_current_alternative")
    try #require(repair.promptVersionID == "productization.persona_action_repair.foundation_models.v3")
    try #require(stream.prompts[1].contains("previous action `invent_new_button` was invalid"))
  }
}

private final class MockProductizationExperienceAppRunner: ProductizationExperienceAppRunning {
  typealias Handler = (ProductizationExperienceInput, Int) async throws -> ProcessResult

  var contractAvailable = true
  var inputs: [ProductizationExperienceInput] = []
  private let handler: Handler

  init(
    handler: @escaping Handler = { input, _ in
      ProcessResult(
        exitCode: 0,
        stdout: try encodeTrace(defaultProductizationTrace(for: input)),
        stderr: ""
      )
    }
  ) {
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
    return try await handler(input, inputs.count)
  }
}

private final class PersonaTextStream: @unchecked Sendable {
  var prompts: [String] = []
  private var responses: [String]

  init(responses: [String]) {
    self.responses = responses
  }

  func stream(_ prompt: String) async -> String? {
    prompts.append(prompt)
    return responses.isEmpty ? nil : responses.removeFirst()
  }
}

private final class ScriptedProductizationPersonaSelector: ProductizationPersonaActionSelecting {
  var choices: [ProductizationPersonaActionChoice]
  var repairs: [ProductizationPersonaActionChoice]
  var repairContexts: [ProductizationPersonaActionRepairContext] = []

  init(
    choices: [ProductizationPersonaActionChoice],
    repairs: [ProductizationPersonaActionChoice] = []
  ) {
    self.choices = choices
    self.repairs = repairs
  }

  func chooseAction(
    context: ProductizationPersonaActionContext
  ) async throws -> ProductizationPersonaActionChoice {
    choices.isEmpty
      ? ProductizationPersonaActionChoice(
        action: ProductizationExperienceAction(id: "abandon_task"))
      : choices.removeFirst()
  }

  func repairAction(
    context: ProductizationPersonaActionRepairContext
  ) async throws -> ProductizationPersonaActionChoice {
    repairContexts.append(context)
    return repairs.isEmpty
      ? ProductizationPersonaActionChoice(
        action: ProductizationExperienceAction(id: "abandon_task"))
      : repairs.removeFirst()
  }
}

private func makeProductizationRequest(
  generatedAppWorkingDirectory: URL = URL(fileURLWithPath: "/tmp/productization-runner-fixture"),
  mode: ProductizationSimulationMode = .modelFree,
  maxTurns: Int = 6,
  appCommandTimeout: TimeInterval? = 120
) -> ProductizationSimulationRequest {
  let config = ProductizationConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Weekly reporting takes too long.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let pain = config.painHypotheses[0]
  let solution = config.solutionHypotheses[0]
  var experiment = config.experiments[0]
  experiment.currentSha = "abc123"
  let segment = config.userSegments[0]
  let workflow = config.currentWorkflows[0]
  return ProductizationSimulationRequest(
    projectTitle: "Reporting Helper",
    pain: pain,
    segment: segment,
    currentWorkflow: workflow,
    alternatives: config.alternatives,
    solution: solution,
    experiment: experiment,
    scenarioID: "scenario-reporting",
    scenarioTask: "Try the reporting helper against the weekly manual export.",
    scenarioSuccessSignal: "Reporting is reusable in the weekly review.",
    generatedAppWorkingDirectory: generatedAppWorkingDirectory,
    mode: mode,
    maxTurns: maxTurns,
    appCommandTimeout: appCommandTimeout
  )
}

private func makePersonaActionContext() -> ProductizationPersonaActionContext {
  let request = makeProductizationRequest(mode: .personaModel)
  let trace = defaultProductizationTrace(for: request.experienceInput(actions: []))
  return ProductizationPersonaActionContext(
    request: ProductizationSimulationRequestContext(
      projectTitle: request.projectTitle,
      pain: request.pain,
      segment: request.segment,
      currentWorkflow: request.currentWorkflow,
      alternatives: request.alternatives,
      solution: request.solution,
      experiment: request.experiment,
      scenarioID: request.scenarioID,
      scenarioTask: request.scenarioTask,
      scenarioSuccessSignal: request.scenarioSuccessSignal,
      commitSha: request.commitSha,
      settings: request.settings
    ),
    turnIndex: 0,
    trace: trace,
    allowedActions: trace.allowedNextActions,
    actionPrefix: []
  )
}

private func defaultProductizationTrace(
  for input: ProductizationExperienceInput = makeProductizationRequest().experienceInput(actions: []
  )
) -> ProductizationExperienceTrace {
  let lastActionID = input.actions.last?.id
  let terminalStatus: ProductizationExperienceTerminalStatus
  let allowedIDs: [String]

  switch lastActionID {
  case nil:
    terminalStatus = .inProgress
    allowedIDs = [
      "inspect_pain",
      "compare_current_alternative",
      "start_solution_workflow",
      "ask_for_help",
      "abandon_task",
    ]
  case "inspect_pain":
    terminalStatus = .inProgress
    allowedIDs = [
      "compare_current_alternative",
      "start_solution_workflow",
      "ask_for_help",
      "abandon_task",
    ]
  case "compare_current_alternative":
    terminalStatus = .inProgress
    allowedIDs = [
      "reduce_switching_objection",
      "start_solution_workflow",
      "ask_for_help",
      "abandon_task",
    ]
  case "reduce_switching_objection":
    terminalStatus = .inProgress
    allowedIDs = ["start_solution_workflow", "ask_for_help", "abandon_task"]
  case "start_solution_workflow":
    terminalStatus = .inProgress
    allowedIDs = ["provide_requested_input", "ask_for_help", "abandon_task"]
  case "provide_requested_input":
    terminalStatus = .completed
    allowedIDs = []
  case "abandon_task":
    terminalStatus = .abandoned
    allowedIDs = []
  default:
    terminalStatus = .invalidAction
    allowedIDs = []
  }

  let actionIDs = Set(input.actions.map(\.id))
  return ProductizationExperienceTrace(
    schemaVersion: 1,
    painID: input.pain.id,
    solutionID: input.solution.id,
    experimentID: input.experiment.id,
    initialState: productizationState(id: "initial"),
    turns: input.actions.enumerated().map { index, action in
      ProductizationExperienceTurn(
        index: index,
        action: action,
        state: productizationState(id: "turn-\(index)-\(action.id)"),
        allowedNextActions: [],
        eventLog: ["turn:\(index):\(action.id)"]
      )
    },
    allowedNextActions: allowedIDs.map(productizationAllowedAction),
    terminalStatus: terminalStatus,
    eventLog: ["last:\(lastActionID ?? "initial")"],
    painReliefSignals: ProductizationPainReliefSignals(
      painRecognized: actionIDs.contains("inspect_pain"),
      workflowAdvanced: actionIDs.contains("start_solution_workflow")
        || actionIDs.contains("provide_requested_input"),
      currentAlternativeAddressed: actionIDs.contains("compare_current_alternative")
        || actionIDs.contains("reduce_switching_objection"),
      currentAlternativeComparison: actionIDs.contains("compare_current_alternative")
        ? "Compared Reporting Helper against Shared spreadsheet and the team's spreadsheet habit."
        : "",
      switchingObjectionReduced: actionIDs.contains("reduce_switching_objection"),
      missingCapabilityIDs: actionIDs.contains("provide_requested_input")
        ? [] : ["workflow_completion"],
      evidenceSummary: actionIDs.contains("provide_requested_input")
        ? "The prototype completed the workflow and addressed the current alternative."
        : "The prototype has not completed the workflow yet."
    )
  )
}

private func productizationState(id: String) -> ProductizationExperienceState {
  ProductizationExperienceState(
    id: id,
    headline: "Headline \(id)",
    body: "Body \(id)",
    semanticNodes: [
      ProductizationExperienceNode(id: "screen.headline", role: "heading", text: "Headline \(id)")
    ],
    observations: ["observation:\(id)"],
    terminal: false
  )
}

private func productizationAllowedAction(_ id: String) -> ProductizationExperienceAllowedAction {
  ProductizationExperienceAllowedAction(
    id: id,
    label: id.replacingOccurrences(of: "_", with: " "),
    description: "Allowed action \(id)",
    paramsSchema: .object(["type": .string("object")])
  )
}

private func encodeTrace(_ trace: ProductizationExperienceTrace) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(trace), as: UTF8.self)
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(
      path: "ProductizationSimulationRunnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}

private func writeProductizationExperienceContractMarkers(to root: URL) throws {
  let paths = [
    "Cargo.toml",
    "crates/app-cli/Cargo.toml",
    "crates/app-core/Cargo.toml",
    "schemas/productization-experience-input.schema.json",
    "schemas/productization-experience-trace.schema.json",
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
