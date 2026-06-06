import Foundation
import Testing

@testable import Compass

struct ProductTournamentSimulationRunnerTests {
  @Test func modelFreeRunnerCompletesFixtureAndValidatesDeterminism() async throws {
    let appRunner = MockProductTournamentExperienceAppRunner()
    let runner = ProductTournamentSimulationRunner(appRunner: appRunner)

    let result = await runner.run(makeTournamentRequest(maxTurns: 6))

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
    try #require(result.tournamentTrace?.painReliefSignals.currentAlternativeAddressed == true)
    try #require(appRunner.inputs.filter { $0.actions.count == 5 }.count == 3)

    let record = ProductTournamentEvidenceRecord(
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
    try #require(record.scores.willingnessToPay == 4)
    try #require(record.willingnessToPayScore == 4)
    try #require(record.sponsorshipIntent.contains("sponsor"))
    try #require(record.currentAlternativeComparison.contains("Shared spreadsheet"))
    try #require(
      record.personaActionRationales.contains {
        $0.contains("model_free") && $0.contains("inspect_pain")
      })
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
    try #require(signals.willingnessToPayScore == nil)
    try #require(signals.sponsorshipIntent.isEmpty)
  }

  @Test func personaModelRejectsInventedActionsAndAllowsOneRepair() async throws {
    let appRunner = MockProductTournamentExperienceAppRunner()
    let selector = ScriptedProductTournamentPersonaSelector(
      choices: [
        .init(action: ProductTournamentExperienceAction(id: "invent_new_button"))
      ],
      repairs: [
        .init(action: ProductTournamentExperienceAction(id: "inspect_pain"))
      ]
    )
    let runner = ProductTournamentSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeTournamentRequest(mode: .personaModel, maxTurns: 1))

    try #require(result.status == .maxTurnsReached)
    try #require(result.actions.map(\.id) == ["inspect_pain"])
    try #require(result.rawPersonaActionTranscript.map(\.wasValid) == [false, true])
    try #require(result.rawPersonaActionTranscript.map(\.phase) == [.choose, .repair])
    let appActionIDs = appRunner.inputs.flatMap { $0.actions.map(\.id) }
    try #require(!appActionIDs.contains("invent_new_button"))
    try #require(selector.repairContexts.first?.allowedActionIDs.contains("inspect_pain") == true)
  }

  @Test func personaModelRunnerPassesDecisionIntentToInputAndSelector() async throws {
    let appRunner = MockProductTournamentExperienceAppRunner()
    let selector = ScriptedProductTournamentPersonaSelector(
      choices: [
        .init(action: ProductTournamentExperienceAction(id: "inspect_pain"))
      ]
    )
    let runner = ProductTournamentSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(
      makeTournamentRequest(mode: .personaModel, targetDecision: .kill, maxTurns: 1)
    )

    let inputIntent = try #require(appRunner.inputs.first?.decisionIntent)
    let contextIntent = try #require(selector.chooseContexts.first?.request.decisionIntent)
    try #require(result.status == .maxTurnsReached)
    try #require(result.decisionIntent?.currentDecision == .keepGoing)
    try #require(result.decisionIntent?.targetDecision == .kill)
    try #require(inputIntent.currentDecision == .keepGoing)
    try #require(inputIntent.targetDecision == .kill)
    try #require(inputIntent.directive.contains("should be killed"))
    try #require(inputIntent.scorecardFocus.contains("refusal to switch"))
    try #require(contextIntent.currentDecision == .keepGoing)
    try #require(contextIntent.targetDecision == .kill)
    try #require(contextIntent.scorecardFocus.contains("current alternative dominance"))
  }

  @Test func personaModelFailsWhenRepairStillInventsAction() async throws {
    let appRunner = MockProductTournamentExperienceAppRunner()
    let selector = ScriptedProductTournamentPersonaSelector(
      choices: [.init(action: ProductTournamentExperienceAction(id: "invent_new_button"))],
      repairs: [.init(action: ProductTournamentExperienceAction(id: "still_bad"))]
    )
    let runner = ProductTournamentSimulationRunner(appRunner: appRunner, personaSelector: selector)

    let result = await runner.run(makeTournamentRequest(mode: .personaModel, maxTurns: 3))

    try #require(result.status == .invalidPersonaAction)
    try #require(result.actions.isEmpty)
    try #require(result.failure?.status == .invalidPersonaAction)
  }

  @Test func cliRunnerUsesProductTournamentContractPathsAndCommand() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeProductTournamentExperienceContractMarkers(to: root)

    var capturedInvocation: AgentExecutionInvocation?
    let appRunner = ProductTournamentExperienceCLIAppRunner { invocation, input, timeout, _, _ in
      capturedInvocation = invocation
      try #require(input == nil)
      try #require(timeout == 99)
      return ProcessResult(
        exitCode: 0, stdout: try encodeTrace(defaultTournamentTrace()), stderr: "")
    }

    try #require(await appRunner.productTournamentExperienceContractAvailable(workingDirectory: root))
    _ = try await appRunner.runProductTournamentExperience(
      input: makeTournamentRequest().experienceInput(actions: []),
      workingDirectory: root,
      launchPlan: .host(),
      timeout: 99
    )

    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    let shell = try #require(invocation.arguments.last)
    try #require(shell.contains("cargo run -p app-cli -- product-tournament-experience --input"))
    try #require(shell.contains("weekly-reporting-takes-too-long-pain"))
  }

  @Test func runnerExecutesGeneratedScaffoldWhenRequested() async throws {
    guard
      ProcessInfo.processInfo.environment["COMPASS_RUN_GENERATED_RUST_PRODUCT_TOURNAMENT_RUNNER"] == "1"
    else {
      return
    }

    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try RustProjectScaffold.write(
      to: root,
      options: RustProjectScaffold.Options(projectName: "Product Tournament Runner Fixture")
    )

    let runner = ProductTournamentSimulationRunner(appRunner: ProductTournamentExperienceCLIAppRunner())
    let result = await runner.run(
      makeTournamentRequest(
        generatedAppWorkingDirectory: root,
        maxTurns: 6,
        appCommandTimeout: 20 * 60
      )
    )

    try #require(result.status == .completed)
    try #require(result.experienceTraceHash != nil)
  }

  @Test func foundationModelsPersonaSelectorParsesFencedJSONAliasesAndParams() throws {
    let choice = try ProductTournamentFoundationModelsPersonaSelector.parseChoice(
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
    let selector = ProductTournamentFoundationModelsPersonaSelector(
      streamText: { prompt in await stream.stream(prompt) }
    )
    let context = makePersonaActionContext()

    let choice = try await selector.chooseAction(context: context)
    try #require(choice.action.id == "inspect_pain")
    try #require(choice.promptVersionID == "product_tournament.persona_action.foundation_models.v3")
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
    try #require(stream.prompts[0].contains("Product decision intent"))
    try #require(stream.prompts[0].contains("target `promote`"))
    try #require(stream.prompts[0].contains("Stress-test promotion"))
    try #require(stream.prompts[0].contains("alternative advantage"))
    try #require(stream.prompts[0].contains("Reporting is reusable in the weekly review"))
    try #require(stream.prompts[0].contains("manual export"))
    try #require(stream.prompts[0].contains("Allowed actions"))
    try #require(stream.prompts[0].contains("Weekly reporting takes too long."))

    let repair = try await selector.repairAction(
      context: ProductTournamentPersonaActionRepairContext(
        actionContext: context,
        invalidChoice: ProductTournamentPersonaActionChoice(
          action: ProductTournamentExperienceAction(id: "invent_new_button")
        ),
        allowedActionIDs: context.allowedActions.map(\.id)
      )
    )
    try #require(repair.action.id == "compare_current_alternative")
    try #require(
      repair.promptVersionID == "product_tournament.persona_action_repair.foundation_models.v3")
    try #require(stream.prompts[1].contains("previous action `invent_new_button` was invalid"))
  }
}

private final class MockProductTournamentExperienceAppRunner: ProductTournamentExperienceAppRunning {
  typealias Handler = (ProductTournamentExperienceInput, Int) async throws -> ProcessResult

  var contractAvailable = true
  var inputs: [ProductTournamentExperienceInput] = []
  private let handler: Handler

  init(
    handler: @escaping Handler = { input, _ in
      ProcessResult(
        exitCode: 0,
        stdout: try encodeTrace(defaultTournamentTrace(for: input)),
        stderr: ""
      )
    }
  ) {
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

private final class ScriptedProductTournamentPersonaSelector: ProductTournamentPersonaActionSelecting {
  var choices: [ProductTournamentPersonaActionChoice]
  var repairs: [ProductTournamentPersonaActionChoice]
  var chooseContexts: [ProductTournamentPersonaActionContext] = []
  var repairContexts: [ProductTournamentPersonaActionRepairContext] = []

  init(
    choices: [ProductTournamentPersonaActionChoice],
    repairs: [ProductTournamentPersonaActionChoice] = []
  ) {
    self.choices = choices
    self.repairs = repairs
  }

  func chooseAction(
    context: ProductTournamentPersonaActionContext
  ) async throws -> ProductTournamentPersonaActionChoice {
    chooseContexts.append(context)
    return choices.isEmpty
      ? ProductTournamentPersonaActionChoice(
        action: ProductTournamentExperienceAction(id: "abandon_task"))
      : choices.removeFirst()
  }

  func repairAction(
    context: ProductTournamentPersonaActionRepairContext
  ) async throws -> ProductTournamentPersonaActionChoice {
    repairContexts.append(context)
    return repairs.isEmpty
      ? ProductTournamentPersonaActionChoice(
        action: ProductTournamentExperienceAction(id: "abandon_task"))
      : repairs.removeFirst()
  }
}

private func makeTournamentRequest(
  generatedAppWorkingDirectory: URL = URL(fileURLWithPath: "/tmp/product-tournament-runner-fixture"),
  mode: ProductTournamentSimulationMode = .modelFree,
  targetDecision: ProductExperimentDecision? = nil,
  maxTurns: Int = 6,
  appCommandTimeout: TimeInterval? = 120
) -> ProductTournamentSimulationRequest {
  let config = ProductizationConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Weekly reporting takes too long.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let pain = config.painHypotheses[0]
  let solution = config.solutionHypotheses[0]
  var experiment = config.experiments[0]
  experiment.currentSha = "abc123"
  if targetDecision != nil {
    experiment.decision = .keepGoing
  }
  let segment = config.userSegments[0]
  let workflow = config.currentWorkflows[0]
  return ProductTournamentSimulationRequest(
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
    targetDecision: targetDecision,
    maxTurns: maxTurns,
    appCommandTimeout: appCommandTimeout
  )
}

private func makePersonaActionContext() -> ProductTournamentPersonaActionContext {
  let request = makeTournamentRequest(mode: .personaModel, targetDecision: .promote)
  let trace = defaultTournamentTrace(for: request.experienceInput(actions: []))
  return ProductTournamentPersonaActionContext(
    request: ProductTournamentSimulationRequestContext(
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
      decisionIntent: request.decisionIntent,
      settings: request.settings
    ),
    turnIndex: 0,
    trace: trace,
    allowedActions: trace.allowedNextActions,
    actionPrefix: []
  )
}

private func defaultTournamentTrace(
  for input: ProductTournamentExperienceInput = makeTournamentRequest().experienceInput(actions: []
  )
) -> ProductTournamentExperienceTrace {
  let lastActionID = input.actions.last?.id
  let terminalStatus: ProductTournamentExperienceTerminalStatus
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
  return ProductTournamentExperienceTrace(
    schemaVersion: 1,
    painID: input.pain.id,
    solutionID: input.solution.id,
    experimentID: input.experiment.id,
    initialState: tournamentState(id: "initial"),
    turns: input.actions.enumerated().map { index, action in
      ProductTournamentExperienceTurn(
        index: index,
        action: action,
        state: tournamentState(id: "turn-\(index)-\(action.id)"),
        allowedNextActions: [],
        eventLog: ["turn:\(index):\(action.id)"]
      )
    },
    allowedNextActions: allowedIDs.map(tournamentAllowedAction),
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
      willingnessToPayScore: actionIDs.contains("provide_requested_input") ? 4 : 2,
      sponsorshipIntent: actionIDs.contains("provide_requested_input")
        ? "The simulated user would sponsor the Reporting Helper prototype."
        : "The simulated user needs more proof before sponsorship.",
      missingCapabilityIDs: actionIDs.contains("provide_requested_input")
        ? [] : ["workflow_completion"],
      evidenceSummary: actionIDs.contains("provide_requested_input")
        ? "The prototype completed the workflow and addressed the current alternative."
        : "The prototype has not completed the workflow yet."
    )
  )
}

private func tournamentState(id: String) -> ProductTournamentExperienceState {
  ProductTournamentExperienceState(
    id: id,
    headline: "Headline \(id)",
    body: "Body \(id)",
    semanticNodes: [
      ProductTournamentExperienceNode(id: "screen.headline", role: "heading", text: "Headline \(id)")
    ],
    observations: ["observation:\(id)"],
    terminal: false
  )
}

private func tournamentAllowedAction(_ id: String) -> ProductTournamentExperienceAllowedAction {
  ProductTournamentExperienceAllowedAction(
    id: id,
    label: id.replacingOccurrences(of: "_", with: " "),
    description: "Allowed action \(id)",
    paramsSchema: .object(["type": .string("object")])
  )
}

private func encodeTrace(_ trace: ProductTournamentExperienceTrace) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(trace), as: UTF8.self)
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(
      path: "ProductTournamentSimulationRunnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}

private func writeProductTournamentExperienceContractMarkers(to root: URL) throws {
  let paths = [
    "Cargo.toml",
    "crates/app-cli/Cargo.toml",
    "crates/app-core/Cargo.toml",
    "schemas/product-tournament-experience-input.schema.json",
    "schemas/product-tournament-experience-trace.schema.json",
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
