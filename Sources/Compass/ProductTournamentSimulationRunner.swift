import CryptoKit
import Foundation

struct ProductTournamentSimulationRequest {
  var projectID: UUID?
  var projectTitle: String
  var pain: PainHypothesis
  var segment: UserSegment
  var currentWorkflow: CurrentWorkflow
  var alternatives: [Alternative]
  var solution: SolutionHypothesis
  var experiment: ProductExperiment
  var scenarioID: String
  var scenarioTask: String
  var scenarioSuccessSignal: String
  var commitSha: String
  var generatedAppWorkingDirectory: URL
  var launchPlan: AgentExecutionLaunchPlan
  var settings: AgentRuntimeSettings
  var mode: ProductTournamentSimulationMode
  var decisionIntent: ProductTournamentSimulationDecisionIntent?
  var maxTurns: Int
  var fixtureActions: [ProductTournamentExperienceAction]
  var appCommandTimeout: TimeInterval?

  init(
    projectID: UUID? = nil,
    projectTitle: String,
    pain: PainHypothesis,
    segment: UserSegment,
    currentWorkflow: CurrentWorkflow,
    alternatives: [Alternative],
    solution: SolutionHypothesis,
    experiment: ProductExperiment,
    scenarioID: String,
    scenarioTask: String = "",
    scenarioSuccessSignal: String = "",
    commitSha: String? = nil,
    generatedAppWorkingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    mode: ProductTournamentSimulationMode = .modelFree,
    targetDecision: ProductExperimentDecision? = nil,
    decisionIntent: ProductTournamentSimulationDecisionIntent? = nil,
    maxTurns: Int = 8,
    fixtureActions: [ProductTournamentExperienceAction]? = nil,
    appCommandTimeout: TimeInterval? = 120
  ) {
    self.projectID = projectID
    self.projectTitle = StringUtils.boundedText(projectTitle, limit: 160)
    self.pain = pain
    self.segment = segment
    self.currentWorkflow = currentWorkflow
    self.alternatives = alternatives
    self.solution = solution
    self.experiment = experiment
    self.scenarioID = ProductTournamentModelText.identifier(scenarioID, fallback: "scenario")
    self.scenarioTask = ProductTournamentModelText.cleanedText(scenarioTask, limit: 800)
    self.scenarioSuccessSignal = ProductTournamentModelText.cleanedText(
      scenarioSuccessSignal,
      limit: 500
    )
    let commit = StringUtils.boundedText(
      commitSha ?? experiment.currentSha ?? experiment.baseSha ?? "unknown",
      limit: 80
    )
    self.commitSha = commit.isEmpty ? "unknown" : commit
    self.generatedAppWorkingDirectory = generatedAppWorkingDirectory.standardizedFileURL
    self.launchPlan = launchPlan
    self.settings = settings
    self.mode = mode
    self.decisionIntent =
      decisionIntent
      ?? targetDecision.map {
        ProductTournamentSimulationDecisionIntent(
          currentDecision: experiment.decision,
          targetDecision: $0
        )
      }
    self.maxTurns = max(1, maxTurns)
    self.fixtureActions = fixtureActions ?? Self.defaultFixtureActions
    self.appCommandTimeout = appCommandTimeout
  }

  static let defaultFixtureActions: [ProductTournamentExperienceAction] = [
    ProductTournamentExperienceAction(id: "inspect_pain"),
    ProductTournamentExperienceAction(id: "compare_current_alternative"),
    ProductTournamentExperienceAction(id: "reduce_switching_objection"),
    ProductTournamentExperienceAction(id: "start_solution_workflow"),
    ProductTournamentExperienceAction(id: "provide_requested_input"),
  ]

  func experienceInput(actions: [ProductTournamentExperienceAction]) -> ProductTournamentExperienceInput {
    ProductTournamentExperienceInput(
      schemaVersion: 1,
      pain: ProductTournamentExperiencePain(
        id: pain.id,
        summary: pain.rawPain,
        impact: pain.costOfInaction
      ),
      solution: ProductTournamentExperienceSolution(
        id: solution.id,
        title: solution.title,
        promise: solution.promise
      ),
      experiment: ProductTournamentExperienceExperiment(
        id: experiment.id,
        branchName: experiment.branchName,
        successSignal: scenarioSuccessSignal.isEmpty
          ? (solution.requiredProof.first ?? experiment.prototypeScope)
          : scenarioSuccessSignal
      ),
      scenario: ProductTournamentExperienceScenario(
        seed: scenarioID,
        personaSummary: [
          segment.name,
          segment.role,
          segment.context,
          "Skepticism: \(segment.skepticism)",
        ].filter { !$0.isEmpty }.joined(separator: ". "),
        task: [
          scenarioTask,
          scenarioSuccessSignal.isEmpty ? "" : "Success signal: \(scenarioSuccessSignal)",
          experiment.prototypeScope,
          "Desired pain relief: \(solution.promise)",
          "Decision criteria: \(segment.decisionCriteria.joined(separator: "; "))",
        ].filter { !$0.isEmpty }.joined(separator: ". ")
      ),
      currentWorkflow: ProductTournamentExperienceCurrentWorkflow(
        summary: [
          currentWorkflow.title,
          currentWorkflow.steps.joined(separator: " -> "),
          currentWorkflow.estimatedCost,
        ].filter { !$0.isEmpty }.joined(separator: ". "),
        frictionPoints: (currentWorkflow.failureModes + currentWorkflow.handoffs
          + currentWorkflow.workarounds).isEmpty
          ? currentWorkflow.steps
          : (currentWorkflow.failureModes + currentWorkflow.handoffs + currentWorkflow.workarounds)
      ),
      alternatives: alternatives.map {
        ProductTournamentExperienceAlternative(
          id: $0.id,
          name: $0.title,
          description: ($0.strengths + $0.weaknesses).joined(separator: "; "),
          switchingObjection: $0.switchingCost
        )
      },
      decisionIntent: decisionIntent.map(ProductTournamentExperienceDecisionIntent.init),
      actions: actions
    )
  }
}

struct ProductTournamentSimulationDecisionIntent: Codable, Equatable, Sendable {
  var currentDecision: ProductExperimentDecision
  var targetDecision: ProductExperimentDecision
  var directive: String
  var scorecardFocus: [String]

  init(
    currentDecision: ProductExperimentDecision,
    targetDecision: ProductExperimentDecision,
    directive: String? = nil,
    scorecardFocus: [String]? = nil
  ) {
    self.currentDecision = currentDecision
    self.targetDecision = targetDecision
    self.directive = ProductTournamentModelText.cleanedText(
      directive ?? Self.directive(for: targetDecision),
      fallback: Self.directive(for: targetDecision),
      limit: 700
    )
    self.scorecardFocus = ProductTournamentModelText.cleanedList(
      scorecardFocus ?? Self.scorecardFocus(for: targetDecision),
      limit: 120
    )
  }

  private static func directive(
    for targetDecision: ProductExperimentDecision
  ) -> String {
    switch targetDecision {
    case .promote, .promoted:
      return
        "Stress-test promotion. Try to disprove broad rollout by forcing proof of current-alternative advantage, switching readiness, and continued-use pull before giving positive evidence."
    case .kill, .archived:
      return
        "Stress-test whether this bet should be killed. Expose absent pain recognition, current-alternative dominance, missing capability, or refusal to switch while still giving real relief a fair chance."
    case .narrow:
      return
        "Stress-test narrowing. Find the smallest persona, workflow moment, or capability scope where the bet might earn pull instead of averaging vague feedback across broad users."
    case .pivot:
      return
        "Stress-test a pivot. Separate evidence that the pain is real from evidence that the current product shape fails to create enough pull."
    case .keepGoing:
      return
        "Stress-test continuing. Look for the next proof that would make the factory continue, narrow, pivot, kill, or promote with less uncertainty."
    case .notRun:
      return
        "Stress-test first evidence. Verify whether the pain, workflow, and current alternative are real before treating the prototype as a product bet."
    }
  }

  private static func scorecardFocus(
    for targetDecision: ProductExperimentDecision
  ) -> [String] {
    switch targetDecision {
    case .promote, .promoted:
      return ["alternative advantage", "switching readiness", "continued-use pull"]
    case .kill, .archived:
      return ["pain recognition", "current alternative dominance", "refusal to switch"]
    case .narrow:
      return ["missing capabilities", "persona specificity", "workflow scope"]
    case .pivot:
      return ["pain recognition", "product-shape mismatch", "unresolved objections"]
    case .keepGoing:
      return ["next proof", "uncertainty reduction", "decision criteria"]
    case .notRun:
      return ["pain reality", "workflow reality", "current alternative"]
    }
  }
}

struct ProductTournamentRunResult: Codable, Equatable, Sendable {
  var projectID: UUID?
  var projectTitle: String
  var experimentID: String
  var solutionID: String
  var painID: String
  var branchName: String
  var commitSha: String
  var scenarioID: String
  var personaID: String
  var mode: ProductTournamentSimulationMode
  var decisionIntent: ProductTournamentSimulationDecisionIntent?
  var routeIdentifier: String
  var modelProvider: String
  var model: String
  var status: ProductTournamentRunStatus
  var actions: [ProductTournamentExperienceAction]
  var rawPersonaActionTranscript: [ProductTournamentPersonaActionTranscriptEntry]
  var experienceTraceJSON: String?
  var experienceTraceHash: String?
  var tournamentTrace: ProductTournamentExperienceTrace?
  var failure: ProductTournamentRunFailure?

  var isSuccess: Bool {
    status == .completed
  }
}

struct ProductTournamentPersonaActionTranscriptEntry: Codable, Equatable, Sendable {
  enum Phase: String, Codable, Equatable, Sendable {
    case modelFree = "model_free"
    case choose
    case repair
  }

  var turnIndex: Int
  var phase: Phase
  var promptVersionID: String
  var chosenActionID: String
  var wasValid: Bool
  var allowedActionIDs: [String]
  var rationale: String
  var rawResponse: String

  init(
    turnIndex: Int,
    phase: Phase,
    promptVersionID: String = "product_tournament.persona_action.v1",
    chosenActionID: String,
    wasValid: Bool,
    allowedActionIDs: [String],
    rationale: String = "",
    rawResponse: String = ""
  ) {
    self.turnIndex = turnIndex
    self.phase = phase
    self.promptVersionID = promptVersionID
    self.chosenActionID = chosenActionID
    self.wasValid = wasValid
    self.allowedActionIDs = allowedActionIDs
    self.rationale = StringUtils.boundedText(rationale, limit: 1_200)
    self.rawResponse = StringUtils.boundedText(rawResponse, limit: 4_000)
  }
}

struct ProductTournamentPersonaActionChoice: Equatable, Sendable {
  var promptVersionID: String
  var action: ProductTournamentExperienceAction
  var rationale: String
  var rawResponse: String

  init(
    promptVersionID: String = "product_tournament.persona_action.v1",
    action: ProductTournamentExperienceAction,
    rationale: String = "",
    rawResponse: String = ""
  ) {
    self.promptVersionID = promptVersionID
    self.action = action
    self.rationale = rationale
    self.rawResponse = rawResponse
  }
}

struct ProductTournamentPersonaActionContext: Equatable, Sendable {
  var request: ProductTournamentSimulationRequestContext
  var turnIndex: Int
  var trace: ProductTournamentExperienceTrace
  var allowedActions: [ProductTournamentExperienceAllowedAction]
  var actionPrefix: [ProductTournamentExperienceAction]
}

struct ProductTournamentPersonaActionRepairContext: Equatable, Sendable {
  var actionContext: ProductTournamentPersonaActionContext
  var invalidChoice: ProductTournamentPersonaActionChoice
  var allowedActionIDs: [String]
}

struct ProductTournamentSimulationRequestContext: Equatable, Sendable {
  var projectTitle: String
  var pain: PainHypothesis
  var segment: UserSegment
  var currentWorkflow: CurrentWorkflow
  var alternatives: [Alternative]
  var solution: SolutionHypothesis
  var experiment: ProductExperiment
  var scenarioID: String
  var scenarioTask: String
  var scenarioSuccessSignal: String
  var commitSha: String
  var decisionIntent: ProductTournamentSimulationDecisionIntent?
  var settings: AgentRuntimeSettings
}

protocol ProductTournamentPersonaActionSelecting {
  func chooseAction(
    context: ProductTournamentPersonaActionContext
  ) async throws -> ProductTournamentPersonaActionChoice
  func repairAction(
    context: ProductTournamentPersonaActionRepairContext
  ) async throws -> ProductTournamentPersonaActionChoice
}

enum ProductTournamentPersonaActionModelError: LocalizedError, Equatable {
  case unavailable
  case emptyResponse
  case invalidJSON(String)
  case missingActionID

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Foundation Models is unavailable for persona action selection."
    case .emptyResponse:
      return "Persona action model returned an empty response."
    case .invalidJSON(let response):
      return
        "Persona action model did not return a JSON object: \(StringUtils.boundedText(response, limit: 500))"
    case .missingActionID:
      return "Persona action model response did not include an actionID."
    }
  }
}

struct ProductTournamentFoundationModelsPersonaSelector: ProductTournamentPersonaActionSelecting {
  var streamText: @Sendable (_ prompt: String) async -> String?

  private static let defaultStreamText: @Sendable (_ prompt: String) async -> String? = { prompt in
    guard FoundationModelsAvailability.isAvailable else { return nil }
    if #available(macOS 26.0, *) {
      return await FoundationModelsAvailability._streamText(prompt: prompt)
    }
    return nil
  }

  init(
    streamText: @escaping @Sendable (_ prompt: String) async -> String? = Self.defaultStreamText
  ) {
    self.streamText = streamText
  }

  func chooseAction(
    context: ProductTournamentPersonaActionContext
  ) async throws -> ProductTournamentPersonaActionChoice {
    try await selectAction(
      prompt: Self.choicePrompt(context: context),
      promptVersionID: "product_tournament.persona_action.foundation_models.v3"
    )
  }

  func repairAction(
    context: ProductTournamentPersonaActionRepairContext
  ) async throws -> ProductTournamentPersonaActionChoice {
    try await selectAction(
      prompt: Self.repairPrompt(context: context),
      promptVersionID: "product_tournament.persona_action_repair.foundation_models.v3"
    )
  }

  private func selectAction(
    prompt: String,
    promptVersionID: String
  ) async throws -> ProductTournamentPersonaActionChoice {
    guard let response = await streamText(prompt) else {
      throw ProductTournamentPersonaActionModelError.emptyResponse
    }
    return try Self.parseChoice(
      response,
      promptVersionID: promptVersionID
    )
  }

  static func parseChoice(
    _ response: String,
    promptVersionID: String = "product_tournament.persona_action.foundation_models.v3"
  ) throws -> ProductTournamentPersonaActionChoice {
    guard let json = firstJSONObject(in: response) else {
      throw ProductTournamentPersonaActionModelError.invalidJSON(response)
    }
    guard let data = json.data(using: .utf8) else {
      throw ProductTournamentPersonaActionModelError.invalidJSON(response)
    }
    let decoded: PersonaActionModelResponse
    do {
      decoded = try JSONDecoder().decode(PersonaActionModelResponse.self, from: data)
    } catch {
      throw ProductTournamentPersonaActionModelError.invalidJSON(response)
    }
    guard !decoded.actionID.isEmpty else {
      throw ProductTournamentPersonaActionModelError.missingActionID
    }
    return ProductTournamentPersonaActionChoice(
      promptVersionID: promptVersionID,
      action: ProductTournamentExperienceAction(id: decoded.actionID, params: decoded.params),
      rationale: decoded.rationale,
      rawResponse: response
    )
  }

  private static func choicePrompt(context: ProductTournamentPersonaActionContext) -> String {
    prompt(
      title: "Choose the next simulated-user action.",
      request: context.request,
      turnIndex: context.turnIndex,
      trace: context.trace,
      allowedActions: context.allowedActions,
      actionPrefix: context.actionPrefix,
      repairNote: nil
    )
  }

  private static func repairPrompt(context: ProductTournamentPersonaActionRepairContext) -> String {
    let invalid = context.invalidChoice.action.id
    let allowed = context.allowedActionIDs.joined(separator: ", ")
    return prompt(
      title: "Repair the simulated-user action.",
      request: context.actionContext.request,
      turnIndex: context.actionContext.turnIndex,
      trace: context.actionContext.trace,
      allowedActions: context.actionContext.allowedActions,
      actionPrefix: context.actionContext.actionPrefix,
      repairNote:
        "The previous action `\(invalid)` was invalid. Choose exactly one allowed action ID from: \(allowed)."
    )
  }

  private static func prompt(
    title: String,
    request: ProductTournamentSimulationRequestContext,
    turnIndex: Int,
    trace: ProductTournamentExperienceTrace,
    allowedActions: [ProductTournamentExperienceAllowedAction],
    actionPrefix: [ProductTournamentExperienceAction],
    repairNote: String?
  ) -> String {
    let allowed = allowedActions.map {
      "- \($0.id): \(bounded($0.label, 80)) — \(bounded($0.description, 180))"
    }.joined(separator: "\n")
    let priorActions =
      actionPrefix.isEmpty
      ? "none"
      : actionPrefix.map(\.id).joined(separator: " -> ")
    let observations = trace.initialState.observations.prefix(4).joined(separator: "; ")
    let alternatives = request.alternatives.prefix(4).map { alternative in
      let strengths = alternative.strengths.prefix(2).joined(separator: "; ")
      let weaknesses = alternative.weaknesses.prefix(2).joined(separator: "; ")
      return [
        "\(alternative.title) [\(alternative.kind.rawValue)]",
        alternative.switchingCost.isEmpty ? "" : "switching \(alternative.switchingCost)",
        strengths.isEmpty ? "" : "strengths \(strengths)",
        weaknesses.isEmpty ? "" : "weaknesses \(weaknesses)",
      ].filter { !$0.isEmpty }.joined(separator: "; ")
    }
    .joined(separator: "; ")
    let workflowFailureModes =
      (request.currentWorkflow.failureModes
      + request.currentWorkflow.handoffs
      + request.currentWorkflow.workarounds).prefix(6).joined(separator: "; ")
    let decisionCriteria = request.segment.decisionCriteria.prefix(6).joined(separator: "; ")
    let constraints = request.segment.constraints.prefix(6).joined(separator: "; ")
    let requiredProof = request.solution.requiredProof.prefix(6).joined(separator: "; ")
    let decisionIntent =
      request.decisionIntent.map { intent in
        let focus = intent.scorecardFocus.joined(separator: ", ")
        return
          "Product decision intent: current `\(intent.currentDecision.rawValue)`, target `\(intent.targetDecision.rawValue)`. \(intent.directive) Scorecard focus: \(focus)."
      } ?? "Product decision intent: discover the next PMF decision."
    return """
      \(title)

      You are simulating a skeptical target user, not helping the product team.
      Pick the next action the persona would actually take while evaluating
      whether this prototype beats the current workflow.
      Do not advance toward success just because an action is available; prefer
      actions that expose switching objections, missing capability proof, or
      reasons the user would keep the current alternative.

      Persona: \(bounded(request.segment.name, 120)) - \(bounded(request.segment.role, 180)).
      Skepticism: \(bounded(request.segment.skepticism, 320)).
      Persona constraints: \(bounded(constraints, 500)).
      Decision criteria: \(bounded(decisionCriteria, 500)).
      Pain: \(bounded(request.pain.rawPain, 500)).
      Current workflow: \(bounded(request.currentWorkflow.title, 160)); \(bounded(request.currentWorkflow.estimatedCost, 240)).
      Current workflow failure modes: \(bounded(workflowFailureModes, 500)).
      Alternatives: \(bounded(alternatives, 500)).
      Solution promise: \(bounded(request.solution.promise, 500)).
      Required proof: \(bounded(requiredProof, 500)).
      Prototype scope: \(bounded(request.experiment.prototypeScope, 500)).
      \(bounded(decisionIntent, 700)).
      Scenario task: \(bounded(request.scenarioTask, 500)).
      Scenario success signal: \(bounded(request.scenarioSuccessSignal, 400)).
      Scenario: \(request.scenarioID), commit \(request.commitSha), turn \(turnIndex).
      Prior actions: \(priorActions).
      Current screen: \(bounded(trace.initialState.headline, 120)) - \(bounded(trace.initialState.body, 500)).
      Observations: \(bounded(observations, 500)).
      PMF scorecard to stress-test: pain recognition, workflow improvement,
      alternative advantage, switching readiness, continued-use pull.
      A good simulated user action should increase evidence for one of those
      dimensions or reveal why the prototype fails it.
      \(repairNote ?? "")

      Allowed actions:
      \(allowed)

      Return exactly one JSON object and no prose:
      {"actionID":"<one allowed action id>","rationale":"<short persona-grounded reason>"}
      """
  }

  private static func firstJSONObject(in text: String) -> String? {
    let characters = Array(text)
    guard let start = characters.firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var escaped = false
    for index in start..<characters.count {
      let character = characters[index]
      if inString {
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          inString = false
        }
        continue
      }
      if character == "\"" {
        inString = true
      } else if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        if depth == 0 {
          return String(characters[start...index])
        }
      }
    }
    return nil
  }

  private static func bounded(_ value: String, _ limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}

private struct PersonaActionModelResponse: Decodable {
  var actionID: String
  var rationale: String
  var params: ProductTournamentJSONValue

  enum CodingKeys: String, CodingKey {
    case actionID
    case actionIDSnake = "action_id"
    case id
    case rationale
    case reason
    case params
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    actionID =
      try container.decodeIfPresent(String.self, forKey: .actionID)
      ?? container.decodeIfPresent(String.self, forKey: .actionIDSnake)
      ?? container.decodeIfPresent(String.self, forKey: .id)
      ?? ""
    rationale =
      try container.decodeIfPresent(String.self, forKey: .rationale)
      ?? container.decodeIfPresent(String.self, forKey: .reason)
      ?? ""
    params =
      try container.decodeIfPresent(ProductTournamentJSONValue.self, forKey: .params)
      ?? .object([:])
  }
}

protocol ProductTournamentExperienceAppRunning {
  func productTournamentExperienceContractAvailable(workingDirectory: URL) async -> Bool

  func runProductTournamentExperience(
    input: ProductTournamentExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult
}

struct ProductTournamentExperienceCLIAppRunner: ProductTournamentExperienceAppRunning {
  var processRunner: ProcessRunner.InvocationRunner?

  init(processRunner: ProcessRunner.InvocationRunner? = nil) {
    self.processRunner = processRunner
  }

  func productTournamentExperienceContractAvailable(workingDirectory: URL) async -> Bool {
    let fm = FileManager.default
    let requiredRelativePaths = [
      "Cargo.toml",
      "crates/app-cli/Cargo.toml",
      "crates/app-core/Cargo.toml",
      "schemas/product-tournament-experience-input.schema.json",
      "schemas/product-tournament-experience-trace.schema.json",
    ]
    return requiredRelativePaths.allSatisfy {
      fm.fileExists(atPath: workingDirectory.appending(path: $0).path)
    }
  }

  func runProductTournamentExperience(
    input: ProductTournamentExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    let inputJSON = try Self.inputJSONString(input)
    let command = Self.productTournamentExperienceCommand(inputJSON: inputJSON)
    return try await ProcessRunner.runShell(
      command,
      workingDirectory: workingDirectory,
      timeout: timeout,
      launchPlan: launchPlan,
      runner: processRunner
    )
  }

  static func productTournamentExperienceCommand(inputJSON: String) -> String {
    RustVerifyCommands.cargo([
      "run", "-p", "app-cli", "--", "product-tournament-experience", "--input", inputJSON,
    ])
  }

  static func inputJSONString(_ input: ProductTournamentExperienceInput) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    return String(decoding: data, as: UTF8.self)
  }
}

struct ProductTournamentSimulationRunner {
  var appRunner: ProductTournamentExperienceAppRunning
  var personaSelector: ProductTournamentPersonaActionSelecting?

  init(
    appRunner: ProductTournamentExperienceAppRunning = ProductTournamentExperienceCLIAppRunner(),
    personaSelector: ProductTournamentPersonaActionSelecting? = nil
  ) {
    self.appRunner = appRunner
    self.personaSelector = personaSelector
  }

  func run(_ request: ProductTournamentSimulationRequest) async -> ProductTournamentRunResult {
    guard
      await appRunner.productTournamentExperienceContractAvailable(
        workingDirectory: request.generatedAppWorkingDirectory
      )
    else {
      return makeResult(
        request: request,
        status: .appContractMissing,
        actions: [],
        transcript: [],
        traceJSON: nil,
        traceHash: nil,
        trace: nil,
        failure: ProductTournamentRunFailure(
          status: .appContractMissing,
          message: "The generated app is missing the product tournament experience CLI contract."
        )
      )
    }

    var actions: [ProductTournamentExperienceAction] = []
    var transcript: [ProductTournamentPersonaActionTranscriptEntry] = []

    for turnIndex in 0..<request.maxTurns {
      let traceOutcome = await loadTrace(request: request, actions: actions)
      switch traceOutcome {
      case .failure(let failure, let traceJSON):
        return makeResult(
          request: request,
          status: failure.status,
          actions: actions,
          transcript: transcript,
          traceJSON: traceJSON,
          traceHash: nil,
          trace: nil,
          failure: failure
        )
      case .success(let trace, let traceJSON):
        if trace.terminalStatus != .inProgress {
          return await deterministicResult(
            request: request,
            status: .completed,
            actions: actions,
            transcript: transcript,
            fallbackTraceJSON: traceJSON
          )
        }

        let allowedActions = trace.allowedNextActions
        guard !allowedActions.isEmpty else {
          return makeResult(
            request: request,
            status: .noAllowedActions,
            actions: actions,
            transcript: transcript,
            traceJSON: traceJSON,
            traceHash: nil,
            trace: trace,
            failure: ProductTournamentRunFailure(
              status: .noAllowedActions,
              message:
                "The product tournament trace is still in progress but returned no allowed actions."
            )
          )
        }

        switch request.mode {
        case .modelFree:
          guard request.fixtureActions.indices.contains(turnIndex) else {
            return await deterministicResult(
              request: request,
              status: .maxTurnsReached,
              actions: actions,
              transcript: transcript,
              fallbackTraceJSON: traceJSON,
              failure: ProductTournamentRunFailure(
                status: .maxTurnsReached,
                message: "Model-free fixture actions ended before a terminal app state."
              )
            )
          }
          let action = request.fixtureActions[turnIndex]
          if isValid(action, allowedActions: allowedActions) {
            transcript.append(
              transcriptEntry(
                turnIndex: turnIndex,
                phase: .modelFree,
                choice: ProductTournamentPersonaActionChoice(
                  action: action,
                  rationale: "Deterministic model-free fixture action."
                ),
                wasValid: true,
                allowedActions: allowedActions
              ))
            actions.append(action)
            continue
          }
          transcript.append(
            transcriptEntry(
              turnIndex: turnIndex,
              phase: .modelFree,
              choice: ProductTournamentPersonaActionChoice(action: action),
              wasValid: false,
              allowedActions: allowedActions
            ))
          return makeResult(
            request: request,
            status: .invalidPersonaAction,
            actions: actions,
            transcript: transcript,
            traceJSON: traceJSON,
            traceHash: nil,
            trace: trace,
            failure: ProductTournamentRunFailure(
              status: .invalidPersonaAction,
              message:
                "Model-free fixture selected invalid action `\(action.id)`. Allowed actions: \(allowedActions.map(\.id).joined(separator: ", "))."
            )
          )

        case .personaModel:
          guard let personaSelector else {
            return makeResult(
              request: request,
              status: .personaCallFailed,
              actions: actions,
              transcript: transcript,
              traceJSON: traceJSON,
              traceHash: nil,
              trace: trace,
              failure: ProductTournamentRunFailure(
                status: .personaCallFailed,
                message: "Persona-model mode requires a persona action selector."
              )
            )
          }
          let context = personaContext(
            request: request,
            turnIndex: turnIndex,
            trace: trace,
            allowedActions: allowedActions,
            actionPrefix: actions
          )
          let choice: ProductTournamentPersonaActionChoice
          do {
            choice = try await personaSelector.chooseAction(context: context)
          } catch {
            return makeResult(
              request: request,
              status: .personaCallFailed,
              actions: actions,
              transcript: transcript,
              traceJSON: traceJSON,
              traceHash: nil,
              trace: trace,
              failure: ProductTournamentRunFailure(
                status: .personaCallFailed,
                message: "Persona action selection failed: \(error.localizedDescription)"
              )
            )
          }

          if isValid(choice.action, allowedActions: allowedActions) {
            transcript.append(
              transcriptEntry(
                turnIndex: turnIndex,
                phase: .choose,
                choice: choice,
                wasValid: true,
                allowedActions: allowedActions
              ))
            actions.append(choice.action)
            continue
          }

          transcript.append(
            transcriptEntry(
              turnIndex: turnIndex,
              phase: .choose,
              choice: choice,
              wasValid: false,
              allowedActions: allowedActions
            ))

          let repairChoice: ProductTournamentPersonaActionChoice
          do {
            repairChoice = try await personaSelector.repairAction(
              context: ProductTournamentPersonaActionRepairContext(
                actionContext: context,
                invalidChoice: choice,
                allowedActionIDs: allowedActions.map(\.id)
              ))
          } catch {
            return makeResult(
              request: request,
              status: .personaCallFailed,
              actions: actions,
              transcript: transcript,
              traceJSON: traceJSON,
              traceHash: nil,
              trace: trace,
              failure: ProductTournamentRunFailure(
                status: .personaCallFailed,
                message: "Persona action repair failed: \(error.localizedDescription)"
              )
            )
          }

          if isValid(repairChoice.action, allowedActions: allowedActions) {
            transcript.append(
              transcriptEntry(
                turnIndex: turnIndex,
                phase: .repair,
                choice: repairChoice,
                wasValid: true,
                allowedActions: allowedActions
              ))
            actions.append(repairChoice.action)
            continue
          }

          transcript.append(
            transcriptEntry(
              turnIndex: turnIndex,
              phase: .repair,
              choice: repairChoice,
              wasValid: false,
              allowedActions: allowedActions
            ))
          return makeResult(
            request: request,
            status: .invalidPersonaAction,
            actions: actions,
            transcript: transcript,
            traceJSON: traceJSON,
            traceHash: nil,
            trace: trace,
            failure: ProductTournamentRunFailure(
              status: .invalidPersonaAction,
              message:
                "Persona selected invalid action `\(repairChoice.action.id)`. Allowed actions: \(allowedActions.map(\.id).joined(separator: ", "))."
            )
          )
        }
      }
    }

    let finalTraceOutcome = await loadTrace(request: request, actions: actions)
    switch finalTraceOutcome {
    case .failure(let failure, let traceJSON):
      return makeResult(
        request: request,
        status: failure.status,
        actions: actions,
        transcript: transcript,
        traceJSON: traceJSON,
        traceHash: nil,
        trace: nil,
        failure: failure
      )
    case .success(let trace, let traceJSON):
      if trace.terminalStatus != .inProgress {
        return await deterministicResult(
          request: request,
          status: .completed,
          actions: actions,
          transcript: transcript,
          fallbackTraceJSON: traceJSON
        )
      }
      return await deterministicResult(
        request: request,
        status: .maxTurnsReached,
        actions: actions,
        transcript: transcript,
        fallbackTraceJSON: traceJSON,
        failure: ProductTournamentRunFailure(
          status: .maxTurnsReached,
          message: "The run reached the maximum turn budget before a terminal app state."
        )
      )
    }
  }

  private func deterministicResult(
    request: ProductTournamentSimulationRequest,
    status: ProductTournamentRunStatus,
    actions: [ProductTournamentExperienceAction],
    transcript: [ProductTournamentPersonaActionTranscriptEntry],
    fallbackTraceJSON: String,
    failure: ProductTournamentRunFailure? = nil
  ) async -> ProductTournamentRunResult {
    let first = await loadTrace(request: request, actions: actions)
    let second = await loadTrace(request: request, actions: actions)
    switch (first, second) {
    case (.failure(let firstFailure, let traceJSON), _):
      return makeResult(
        request: request,
        status: firstFailure.status,
        actions: actions,
        transcript: transcript,
        traceJSON: traceJSON ?? fallbackTraceJSON,
        traceHash: nil,
        trace: nil,
        failure: firstFailure
      )
    case (_, .failure(let secondFailure, let traceJSON)):
      return makeResult(
        request: request,
        status: secondFailure.status,
        actions: actions,
        transcript: transcript,
        traceJSON: traceJSON ?? fallbackTraceJSON,
        traceHash: nil,
        trace: nil,
        failure: secondFailure
      )
    case (.success(let trace, let firstJSON), .success(_, let secondJSON)):
      do {
        let firstNormalized = try ProductTournamentJSONCanonicalizer.canonicalJSON(firstJSON)
        let secondNormalized = try ProductTournamentJSONCanonicalizer.canonicalJSON(secondJSON)
        let firstHash = Self.sha256Hex(firstNormalized)
        let secondHash = Self.sha256Hex(secondNormalized)
        guard firstHash == secondHash else {
          return makeResult(
            request: request,
            status: .nondeterministicExperienceTrace,
            actions: actions,
            transcript: transcript,
            traceJSON: firstNormalized,
            traceHash: firstHash,
            trace: trace,
            failure: ProductTournamentRunFailure(
              status: .nondeterministicExperienceTrace,
              message:
                "The generated app returned different normalized trace hashes for the same action prefix: \(firstHash) != \(secondHash)."
            )
          )
        }
        return makeResult(
          request: request,
          status: status,
          actions: actions,
          transcript: transcript,
          traceJSON: firstNormalized,
          traceHash: firstHash,
          trace: trace,
          failure: failure
        )
      } catch {
        return makeResult(
          request: request,
          status: .appOutputNotJSON,
          actions: actions,
          transcript: transcript,
          traceJSON: fallbackTraceJSON,
          traceHash: nil,
          trace: nil,
          failure: ProductTournamentRunFailure(
            status: .appOutputNotJSON,
            message:
              "Final product tournament trace could not be normalized: \(error.localizedDescription)"
          )
        )
      }
    }
  }

  private func loadTrace(
    request: ProductTournamentSimulationRequest,
    actions: [ProductTournamentExperienceAction]
  ) async -> ProductTournamentTraceLoadOutcome {
    let input = request.experienceInput(actions: actions)
    let result: ProcessResult
    do {
      result = try await appRunner.runProductTournamentExperience(
        input: input,
        workingDirectory: request.generatedAppWorkingDirectory,
        launchPlan: request.launchPlan,
        timeout: request.appCommandTimeout
      )
    } catch {
      return .failure(
        ProductTournamentRunFailure(
          status: .appCommandFailed,
          message: "Product tournament experience CLI command failed: \(error.localizedDescription)"
        ),
        traceJSON: nil
      )
    }

    guard result.exitCode == 0 else {
      return .failure(
        ProductTournamentRunFailure(
          status: .appCommandFailed,
          message: "Product tournament experience CLI exited with code \(result.exitCode).",
          stdout: result.stdout,
          stderr: result.stderr
        ),
        traceJSON: result.stdout
      )
    }

    guard let data = result.stdout.data(using: .utf8) else {
      return .failure(
        ProductTournamentRunFailure(
          status: .appOutputNotJSON,
          message: "Product tournament experience CLI stdout was not UTF-8."
        ),
        traceJSON: result.stdout
      )
    }

    do {
      let trace = try JSONDecoder().decode(ProductTournamentExperienceTrace.self, from: data)
      return .success(trace, traceJSON: result.stdout)
    } catch {
      return .failure(
        ProductTournamentRunFailure(
          status: .appOutputNotJSON,
          message:
            "Product tournament experience CLI stdout was not a valid product tournament trace: \(error.localizedDescription).",
          stdout: result.stdout,
          stderr: result.stderr
        ),
        traceJSON: result.stdout
      )
    }
  }

  private func personaContext(
    request: ProductTournamentSimulationRequest,
    turnIndex: Int,
    trace: ProductTournamentExperienceTrace,
    allowedActions: [ProductTournamentExperienceAllowedAction],
    actionPrefix: [ProductTournamentExperienceAction]
  ) -> ProductTournamentPersonaActionContext {
    ProductTournamentPersonaActionContext(
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
      turnIndex: turnIndex,
      trace: trace,
      allowedActions: allowedActions,
      actionPrefix: actionPrefix
    )
  }

  private func isValid(
    _ action: ProductTournamentExperienceAction,
    allowedActions: [ProductTournamentExperienceAllowedAction]
  ) -> Bool {
    allowedActions.contains { $0.id == action.id }
  }

  private func transcriptEntry(
    turnIndex: Int,
    phase: ProductTournamentPersonaActionTranscriptEntry.Phase,
    choice: ProductTournamentPersonaActionChoice,
    wasValid: Bool,
    allowedActions: [ProductTournamentExperienceAllowedAction]
  ) -> ProductTournamentPersonaActionTranscriptEntry {
    ProductTournamentPersonaActionTranscriptEntry(
      turnIndex: turnIndex,
      phase: phase,
      promptVersionID: choice.promptVersionID,
      chosenActionID: choice.action.id,
      wasValid: wasValid,
      allowedActionIDs: allowedActions.map(\.id),
      rationale: choice.rationale,
      rawResponse: choice.rawResponse
    )
  }

  private func makeResult(
    request: ProductTournamentSimulationRequest,
    status: ProductTournamentRunStatus,
    actions: [ProductTournamentExperienceAction],
    transcript: [ProductTournamentPersonaActionTranscriptEntry],
    traceJSON: String?,
    traceHash: String?,
    trace: ProductTournamentExperienceTrace?,
    failure: ProductTournamentRunFailure?
  ) -> ProductTournamentRunResult {
    ProductTournamentRunResult(
      projectID: request.projectID,
      projectTitle: request.projectTitle,
      experimentID: request.experiment.id,
      solutionID: request.solution.id,
      painID: request.pain.id,
      branchName: request.experiment.branchName,
      commitSha: request.commitSha,
      scenarioID: request.scenarioID,
      personaID: request.segment.id,
      mode: request.mode,
      decisionIntent: request.decisionIntent,
      routeIdentifier: request.launchPlan.effectiveRouteIdentifier,
      modelProvider: request.settings.textProvider.rawValue,
      model: request.settings.model,
      status: status,
      actions: actions,
      rawPersonaActionTranscript: transcript,
      experienceTraceJSON: traceJSON,
      experienceTraceHash: traceHash,
      tournamentTrace: trace,
      failure: failure
    )
  }

  private static func sha256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

private enum ProductTournamentTraceLoadOutcome {
  case success(ProductTournamentExperienceTrace, traceJSON: String)
  case failure(ProductTournamentRunFailure, traceJSON: String?)
}

struct ProductTournamentExperienceInput: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var pain: ProductTournamentExperiencePain
  var solution: ProductTournamentExperienceSolution
  var experiment: ProductTournamentExperienceExperiment
  var scenario: ProductTournamentExperienceScenario
  var currentWorkflow: ProductTournamentExperienceCurrentWorkflow
  var alternatives: [ProductTournamentExperienceAlternative]
  var decisionIntent: ProductTournamentExperienceDecisionIntent?
  var actions: [ProductTournamentExperienceAction]
}

struct ProductTournamentExperiencePain: Codable, Equatable, Sendable {
  var id: String
  var summary: String
  var impact: String
}

struct ProductTournamentExperienceSolution: Codable, Equatable, Sendable {
  var id: String
  var title: String
  var promise: String
}

struct ProductTournamentExperienceExperiment: Codable, Equatable, Sendable {
  var id: String
  var branchName: String
  var successSignal: String
}

struct ProductTournamentExperienceScenario: Codable, Equatable, Sendable {
  var seed: String
  var personaSummary: String
  var task: String
}

struct ProductTournamentExperienceCurrentWorkflow: Codable, Equatable, Sendable {
  var summary: String
  var frictionPoints: [String]
}

struct ProductTournamentExperienceAlternative: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var description: String
  var switchingObjection: String
}

struct ProductTournamentExperienceDecisionIntent: Codable, Equatable, Sendable {
  var currentDecision: ProductExperimentDecision
  var targetDecision: ProductExperimentDecision
  var directive: String
  var scorecardFocus: [String]

  init(_ intent: ProductTournamentSimulationDecisionIntent) {
    self.currentDecision = intent.currentDecision
    self.targetDecision = intent.targetDecision
    self.directive = intent.directive
    self.scorecardFocus = intent.scorecardFocus
  }
}

struct ProductTournamentExperienceAction: Codable, Equatable, Sendable {
  var id: String
  var params: ProductTournamentJSONValue

  init(id: String, params: ProductTournamentJSONValue = .object([:])) {
    self.id = id
    self.params = params
  }

  enum CodingKeys: String, CodingKey {
    case id
    case params
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    params =
      try container.decodeIfPresent(ProductTournamentJSONValue.self, forKey: .params) ?? .object([:])
  }
}

struct ProductTournamentExperienceTrace: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var painID: String
  var solutionID: String
  var experimentID: String
  var initialState: ProductTournamentExperienceState
  var turns: [ProductTournamentExperienceTurn]
  var allowedNextActions: [ProductTournamentExperienceAllowedAction]
  var terminalStatus: ProductTournamentExperienceTerminalStatus
  var eventLog: [String]
  var painReliefSignals: ProductTournamentPainReliefSignals
}

struct ProductTournamentExperienceState: Codable, Equatable, Sendable {
  var id: String
  var headline: String
  var body: String
  var semanticNodes: [ProductTournamentExperienceNode]
  var observations: [String]
  var terminal: Bool
}

struct ProductTournamentExperienceNode: Codable, Equatable, Sendable {
  var id: String
  var role: String
  var text: String
}

struct ProductTournamentExperienceTurn: Codable, Equatable, Sendable {
  var index: Int
  var action: ProductTournamentExperienceAction
  var state: ProductTournamentExperienceState
  var allowedNextActions: [ProductTournamentExperienceAllowedAction]
  var eventLog: [String]
}

struct ProductTournamentExperienceAllowedAction: Codable, Equatable, Sendable {
  var id: String
  var label: String
  var description: String
  var paramsSchema: ProductTournamentJSONValue
}

struct ProductTournamentPainReliefSignals: Codable, Equatable, Sendable {
  var painRecognized: Bool
  var workflowAdvanced: Bool
  var currentAlternativeAddressed: Bool
  var currentAlternativeComparison: String
  var switchingObjectionReduced: Bool
  var willingnessToPayScore: Int?
  var sponsorshipIntent: String
  var missingCapabilityIDs: [String]
  var evidenceSummary: String

  enum CodingKeys: String, CodingKey {
    case painRecognized
    case workflowAdvanced
    case currentAlternativeAddressed
    case currentAlternativeComparison
    case switchingObjectionReduced
    case willingnessToPayScore
    case sponsorshipIntent
    case missingCapabilityIDs
    case missingCapabilityIds
    case evidenceSummary
  }

  init(
    painRecognized: Bool,
    workflowAdvanced: Bool,
    currentAlternativeAddressed: Bool,
    currentAlternativeComparison: String = "",
    switchingObjectionReduced: Bool,
    willingnessToPayScore: Int? = nil,
    sponsorshipIntent: String = "",
    missingCapabilityIDs: [String],
    evidenceSummary: String
  ) {
    self.painRecognized = painRecognized
    self.workflowAdvanced = workflowAdvanced
    self.currentAlternativeAddressed = currentAlternativeAddressed
    self.currentAlternativeComparison = StringUtils.boundedText(
      currentAlternativeComparison,
      limit: 1_000
    )
    self.switchingObjectionReduced = switchingObjectionReduced
    self.willingnessToPayScore = Self.clampedScore(willingnessToPayScore)
    self.sponsorshipIntent = StringUtils.boundedText(sponsorshipIntent, limit: 700)
    self.missingCapabilityIDs = missingCapabilityIDs
    self.evidenceSummary = evidenceSummary
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    painRecognized = try container.decode(Bool.self, forKey: .painRecognized)
    workflowAdvanced = try container.decode(Bool.self, forKey: .workflowAdvanced)
    currentAlternativeAddressed = try container.decode(
      Bool.self,
      forKey: .currentAlternativeAddressed
    )
    currentAlternativeComparison =
      try container.decodeIfPresent(
        String.self,
        forKey: .currentAlternativeComparison
      ) ?? ""
    switchingObjectionReduced = try container.decode(
      Bool.self,
      forKey: .switchingObjectionReduced
    )
    willingnessToPayScore = Self.clampedScore(
      try container.decodeIfPresent(Int.self, forKey: .willingnessToPayScore)
    )
    sponsorshipIntent =
      try container.decodeIfPresent(String.self, forKey: .sponsorshipIntent) ?? ""
    missingCapabilityIDs =
      try container.decodeIfPresent([String].self, forKey: .missingCapabilityIDs)
      ?? container.decodeIfPresent([String].self, forKey: .missingCapabilityIds)
      ?? []
    evidenceSummary = try container.decode(String.self, forKey: .evidenceSummary)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(painRecognized, forKey: .painRecognized)
    try container.encode(workflowAdvanced, forKey: .workflowAdvanced)
    try container.encode(currentAlternativeAddressed, forKey: .currentAlternativeAddressed)
    try container.encode(currentAlternativeComparison, forKey: .currentAlternativeComparison)
    try container.encode(switchingObjectionReduced, forKey: .switchingObjectionReduced)
    try container.encodeIfPresent(willingnessToPayScore, forKey: .willingnessToPayScore)
    try container.encode(sponsorshipIntent, forKey: .sponsorshipIntent)
    try container.encode(missingCapabilityIDs, forKey: .missingCapabilityIDs)
    try container.encode(evidenceSummary, forKey: .evidenceSummary)
  }

  private static func clampedScore(_ value: Int?) -> Int? {
    value.map { min(5, max(1, $0)) }
  }
}

enum ProductTournamentExperienceTerminalStatus: String, Codable, Equatable, Sendable {
  case inProgress = "in_progress"
  case completed
  case abandoned
  case invalidAction = "invalid_action"
}
