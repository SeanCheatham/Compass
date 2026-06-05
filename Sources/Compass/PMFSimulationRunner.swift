import CryptoKit
import Foundation

struct PMFSimulationRequest {
  var projectID: UUID?
  var projectTitle: String
  var hypothesis: ProductHypothesis
  var persona: PMFPersona
  var task: PMFTask
  var scenario: PMFScenario
  var generatedAppWorkingDirectory: URL
  var launchPlan: AgentExecutionLaunchPlan
  var settings: AgentRuntimeSettings
  var maxTurns: Int
  var appCommandTimeout: TimeInterval?

  init(
    projectID: UUID? = nil,
    projectTitle: String,
    hypothesis: ProductHypothesis,
    persona: PMFPersona,
    task: PMFTask,
    scenario: PMFScenario,
    generatedAppWorkingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    maxTurns: Int? = nil,
    appCommandTimeout: TimeInterval? = 120
  ) {
    self.projectID = projectID
    self.projectTitle = StringUtils.boundedText(projectTitle, limit: 160)
    self.hypothesis = hypothesis
    self.persona = persona
    self.task = task
    self.scenario = scenario
    self.generatedAppWorkingDirectory = generatedAppWorkingDirectory.standardizedFileURL
    self.launchPlan = launchPlan
    self.settings = settings
    self.maxTurns = max(1, maxTurns ?? task.maxTurns)
    self.appCommandTimeout = appCommandTimeout
  }

  @MainActor
  init(
    project: CompassProject,
    hypothesis: ProductHypothesis,
    persona: PMFPersona,
    task: PMFTask,
    scenario: PMFScenario,
    generatedAppWorkingDirectory: URL? = nil,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    maxTurns: Int? = nil,
    appCommandTimeout: TimeInterval? = 120
  ) {
    self.init(
      projectID: project.id,
      projectTitle: project.repoURL.deletingPathExtension().lastPathComponent,
      hypothesis: hypothesis,
      persona: persona,
      task: task,
      scenario: scenario,
      generatedAppWorkingDirectory: generatedAppWorkingDirectory ?? project.repoURL,
      launchPlan: launchPlan,
      settings: settings,
      maxTurns: maxTurns,
      appCommandTimeout: appCommandTimeout
    )
  }

  var experienceScenario: PMFExperienceScenario {
    PMFExperienceScenario(
      seed: scenario.seed,
      personaSummary: StringUtils.boundedText(
        [
          persona.name,
          persona.role,
          persona.context,
          "Skepticism: \(persona.skepticism)",
        ].filter { !$0.isEmpty }.joined(separator: ". "),
        limit: 900
      ),
      task: StringUtils.boundedText(
        [
          task.title,
          task.situation,
          "Desired outcome: \(task.desiredOutcome)",
          "Hypothesis promise: \(hypothesis.promise)",
        ].filter { !$0.isEmpty }.joined(separator: ". "),
        limit: 900
      )
    )
  }
}

enum PMFRunStatus: String, Codable, Equatable, Sendable {
  case completed
  case appContractMissing
  case appCommandFailed
  case appOutputNotJSON
  case noAllowedActions
  case invalidPersonaAction
  case personaCallFailed
  case maxTurnsReached
  case nondeterministicExperienceTrace
}

struct PMFRunFailure: Codable, Equatable, Sendable {
  var status: PMFRunStatus
  var message: String
  var stdout: String
  var stderr: String

  init(
    status: PMFRunStatus,
    message: String,
    stdout: String = "",
    stderr: String = ""
  ) {
    self.status = status
    self.message = StringUtils.boundedText(message, limit: 2_000)
    self.stdout = StringUtils.boundedText(stdout, limit: 4_000)
    self.stderr = StringUtils.boundedText(stderr, limit: 4_000)
  }
}

struct PMFPersonaActionTranscriptEntry: Codable, Equatable, Sendable {
  enum Phase: String, Codable, Equatable, Sendable {
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
    promptVersionID: String = Prompts.pmfPersonaActionPromptVersionID,
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

struct PMFRunResult: Codable, Equatable, Sendable {
  var projectID: UUID?
  var projectTitle: String
  var hypothesisID: String
  var personaID: String
  var taskID: String
  var scenarioID: String
  var routeIdentifier: String
  var modelProvider: String
  var model: String
  var status: PMFRunStatus
  var actions: [PMFExperienceAction]
  var rawPersonaActionTranscript: [PMFPersonaActionTranscriptEntry]
  var experienceTraceJSON: String?
  var experienceTraceHash: String?
  var failure: PMFRunFailure?

  var isSuccess: Bool {
    status == .completed
  }
}

struct PMFPersonaActionChoice: Equatable, Sendable {
  var promptVersionID: String
  var action: PMFExperienceAction
  var rationale: String
  var rawResponse: String

  init(
    promptVersionID: String = Prompts.pmfPersonaActionPromptVersionID,
    action: PMFExperienceAction,
    rationale: String = "",
    rawResponse: String = ""
  ) {
    self.promptVersionID = promptVersionID
    self.action = action
    self.rationale = rationale
    self.rawResponse = rawResponse
  }
}

struct PMFPersonaActionContext: Equatable, Sendable {
  var request: PMFSimulationRequestContext
  var turnIndex: Int
  var trace: PMFExperienceTrace
  var allowedActions: [PMFExperienceAllowedAction]
  var actionPrefix: [PMFExperienceAction]
}

struct PMFPersonaActionRepairContext: Equatable, Sendable {
  var actionContext: PMFPersonaActionContext
  var invalidChoice: PMFPersonaActionChoice
  var allowedActionIDs: [String]
}

struct PMFSimulationRequestContext: Equatable, Sendable {
  var projectTitle: String
  var hypothesis: ProductHypothesis
  var persona: PMFPersona
  var task: PMFTask
  var scenario: PMFScenario
  var settings: AgentRuntimeSettings
}

protocol PMFPersonaActionSelecting {
  func chooseAction(context: PMFPersonaActionContext) async throws -> PMFPersonaActionChoice
  func repairAction(context: PMFPersonaActionRepairContext) async throws -> PMFPersonaActionChoice
}

protocol PMFExperienceAppRunning {
  func experienceContractAvailable(workingDirectory: URL) async -> Bool

  func runExperience(
    input: PMFExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult
}

struct PMFExperienceCLIAppRunner: PMFExperienceAppRunning {
  var processRunner: ProcessRunner.InvocationRunner?

  init(processRunner: ProcessRunner.InvocationRunner? = nil) {
    self.processRunner = processRunner
  }

  func experienceContractAvailable(workingDirectory: URL) async -> Bool {
    let fm = FileManager.default
    let requiredRelativePaths = [
      "Cargo.toml",
      "crates/app-cli/Cargo.toml",
      "crates/app-core/Cargo.toml",
      "schemas/experience-input.schema.json",
      "schemas/experience-trace.schema.json",
    ]
    return requiredRelativePaths.allSatisfy {
      fm.fileExists(atPath: workingDirectory.appending(path: $0).path)
    }
  }

  func runExperience(
    input: PMFExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    let inputJSON = try Self.inputJSONString(input)
    let command = Self.experienceCommand(inputJSON: inputJSON)
    return try await ProcessRunner.runShell(
      command,
      workingDirectory: workingDirectory,
      timeout: timeout,
      launchPlan: launchPlan,
      runner: processRunner
    )
  }

  static func experienceCommand(inputJSON: String) -> String {
    RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "experience", "--input", inputJSON])
  }

  static func inputJSONString(_ input: PMFExperienceInput) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    return String(decoding: data, as: UTF8.self)
  }
}

struct PMFSimulationRunner {
  var appRunner: PMFExperienceAppRunning
  var personaSelector: PMFPersonaActionSelecting

  init(
    appRunner: PMFExperienceAppRunning = PMFExperienceCLIAppRunner(),
    personaSelector: PMFPersonaActionSelecting
  ) {
    self.appRunner = appRunner
    self.personaSelector = personaSelector
  }

  func run(_ request: PMFSimulationRequest) async -> PMFRunResult {
    guard await appRunner.experienceContractAvailable(
      workingDirectory: request.generatedAppWorkingDirectory
    ) else {
      return makeResult(
        request: request,
        status: .appContractMissing,
        actions: [],
        transcript: [],
        traceJSON: nil,
        traceHash: nil,
        failure: PMFRunFailure(
          status: .appContractMissing,
          message: "The generated app is missing the PMF experience CLI contract."
        )
      )
    }

    var actions: [PMFExperienceAction] = []
    var transcript: [PMFPersonaActionTranscriptEntry] = []

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
            failure: PMFRunFailure(
              status: .noAllowedActions,
              message: "The experience trace is still in progress but returned no allowed actions."
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
        let choice: PMFPersonaActionChoice
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
            failure: PMFRunFailure(
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

        let repairChoice: PMFPersonaActionChoice
        let repairContext = PMFPersonaActionRepairContext(
          actionContext: context,
          invalidChoice: choice,
          allowedActionIDs: allowedActions.map(\.id)
        )
        do {
          repairChoice = try await personaSelector.repairAction(context: repairContext)
        } catch {
          return makeResult(
            request: request,
            status: .personaCallFailed,
            actions: actions,
            transcript: transcript,
            traceJSON: traceJSON,
            traceHash: nil,
            failure: PMFRunFailure(
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
          failure: PMFRunFailure(
            status: .invalidPersonaAction,
            message:
              "Persona selected invalid action `\(repairChoice.action.id)`. Allowed actions: \(allowedActions.map(\.id).joined(separator: ", "))."
          )
        )
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
        failure: PMFRunFailure(
          status: .maxTurnsReached,
          message: "The persona reached the maximum turn budget before a terminal app state."
        )
      )
    }
  }

  private func deterministicResult(
    request: PMFSimulationRequest,
    status: PMFRunStatus,
    actions: [PMFExperienceAction],
    transcript: [PMFPersonaActionTranscriptEntry],
    fallbackTraceJSON: String,
    failure: PMFRunFailure? = nil
  ) async -> PMFRunResult {
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
        failure: secondFailure
      )
    case (.success(_, let firstJSON), .success(_, let secondJSON)):
      do {
        let firstNormalized = try PMFJSONCanonicalizer.canonicalJSON(firstJSON)
        let secondNormalized = try PMFJSONCanonicalizer.canonicalJSON(secondJSON)
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
            failure: PMFRunFailure(
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
          failure: PMFRunFailure(
            status: .appOutputNotJSON,
            message: "Final experience trace could not be normalized: \(error.localizedDescription)"
          )
        )
      }
    }
  }

  private func loadTrace(
    request: PMFSimulationRequest,
    actions: [PMFExperienceAction]
  ) async -> TraceLoadOutcome {
    let input = PMFExperienceInput(
      schemaVersion: 1,
      scenario: request.experienceScenario,
      actions: actions
    )
    let result: ProcessResult
    do {
      result = try await appRunner.runExperience(
        input: input,
        workingDirectory: request.generatedAppWorkingDirectory,
        launchPlan: request.launchPlan,
        timeout: request.appCommandTimeout
      )
    } catch {
      return .failure(
        PMFRunFailure(
          status: .appCommandFailed,
          message: "Experience CLI command failed: \(error.localizedDescription)"
        ),
        traceJSON: nil
      )
    }

    guard result.exitCode == 0 else {
      return .failure(
        PMFRunFailure(
          status: .appCommandFailed,
          message: "Experience CLI exited with code \(result.exitCode).",
          stdout: result.stdout,
          stderr: result.stderr
        ),
        traceJSON: result.stdout
      )
    }

    guard let data = result.stdout.data(using: .utf8) else {
      return .failure(
        PMFRunFailure(
          status: .appOutputNotJSON,
          message: "Experience CLI stdout was not UTF-8."
        ),
        traceJSON: result.stdout
      )
    }

    do {
      let trace = try JSONDecoder().decode(PMFExperienceTrace.self, from: data)
      return .success(trace, traceJSON: result.stdout)
    } catch {
      return .failure(
        PMFRunFailure(
          status: .appOutputNotJSON,
          message:
            "Experience CLI stdout was not a valid PMF experience trace: \(error.localizedDescription).",
          stdout: result.stdout,
          stderr: result.stderr
        ),
        traceJSON: result.stdout
      )
    }
  }

  private func personaContext(
    request: PMFSimulationRequest,
    turnIndex: Int,
    trace: PMFExperienceTrace,
    allowedActions: [PMFExperienceAllowedAction],
    actionPrefix: [PMFExperienceAction]
  ) -> PMFPersonaActionContext {
    PMFPersonaActionContext(
      request: PMFSimulationRequestContext(
        projectTitle: request.projectTitle,
        hypothesis: request.hypothesis,
        persona: request.persona,
        task: request.task,
        scenario: request.scenario,
        settings: request.settings
      ),
      turnIndex: turnIndex,
      trace: trace,
      allowedActions: allowedActions,
      actionPrefix: actionPrefix
    )
  }

  private func isValid(
    _ action: PMFExperienceAction,
    allowedActions: [PMFExperienceAllowedAction]
  ) -> Bool {
    allowedActions.contains { $0.id == action.id }
  }

  private func transcriptEntry(
    turnIndex: Int,
    phase: PMFPersonaActionTranscriptEntry.Phase,
    choice: PMFPersonaActionChoice,
    wasValid: Bool,
    allowedActions: [PMFExperienceAllowedAction]
  ) -> PMFPersonaActionTranscriptEntry {
    PMFPersonaActionTranscriptEntry(
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
    request: PMFSimulationRequest,
    status: PMFRunStatus,
    actions: [PMFExperienceAction],
    transcript: [PMFPersonaActionTranscriptEntry],
    traceJSON: String?,
    traceHash: String?,
    failure: PMFRunFailure?
  ) -> PMFRunResult {
    PMFRunResult(
      projectID: request.projectID,
      projectTitle: request.projectTitle,
      hypothesisID: request.hypothesis.id,
      personaID: request.persona.id,
      taskID: request.task.id,
      scenarioID: request.scenario.id,
      routeIdentifier: request.launchPlan.effectiveRouteIdentifier,
      modelProvider: request.settings.textProvider.rawValue,
      model: request.settings.model,
      status: status,
      actions: actions,
      rawPersonaActionTranscript: transcript,
      experienceTraceJSON: traceJSON,
      experienceTraceHash: traceHash,
      failure: failure
    )
  }

  private static func sha256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

private enum TraceLoadOutcome {
  case success(PMFExperienceTrace, traceJSON: String)
  case failure(PMFRunFailure, traceJSON: String?)
}

struct PMFExperienceInput: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var scenario: PMFExperienceScenario
  var actions: [PMFExperienceAction]

  init(
    schemaVersion: Int = 1,
    scenario: PMFExperienceScenario,
    actions: [PMFExperienceAction] = []
  ) {
    self.schemaVersion = schemaVersion
    self.scenario = scenario
    self.actions = actions
  }
}

struct PMFExperienceScenario: Codable, Equatable, Sendable {
  var seed: String
  var personaSummary: String
  var task: String
}

struct PMFExperienceAction: Codable, Equatable, Sendable {
  var id: String
  var params: PMFJSONValue

  init(id: String, params: PMFJSONValue = .object([:])) {
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
    params = try container.decodeIfPresent(PMFJSONValue.self, forKey: .params) ?? .object([:])
  }
}

struct PMFExperienceTrace: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var scenario: PMFExperienceScenario
  var initialState: PMFExperienceState
  var turns: [PMFExperienceTurn]
  var allowedNextActions: [PMFExperienceAllowedAction]
  var terminalStatus: PMFExperienceTerminalStatus
  var eventLog: [String]
}

struct PMFExperienceState: Codable, Equatable, Sendable {
  var id: String
  var headline: String
  var body: String
  var semanticNodes: [PMFExperienceNode]
  var observations: [String]
  var terminal: Bool
}

struct PMFExperienceNode: Codable, Equatable, Sendable {
  var id: String
  var role: String
  var text: String
}

struct PMFExperienceTurn: Codable, Equatable, Sendable {
  var index: Int
  var action: PMFExperienceAction
  var state: PMFExperienceState
  var allowedNextActions: [PMFExperienceAllowedAction]
  var eventLog: [String]
}

struct PMFExperienceAllowedAction: Codable, Equatable, Sendable {
  var id: String
  var label: String
  var description: String
  var paramsSchema: PMFJSONValue
}

enum PMFExperienceTerminalStatus: String, Codable, Equatable, Sendable {
  case inProgress = "in_progress"
  case completed
  case abandoned
  case invalidAction = "invalid_action"
}

enum PMFJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([PMFJSONValue])
  case object([String: PMFJSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let object = try? container.decode([String: PMFJSONValue].self) {
      self = .object(object)
    } else if let array = try? container.decode([PMFJSONValue].self) {
      self = .array(array)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value."
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .number(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .string(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .array(let values):
      var container = encoder.unkeyedContainer()
      for value in values {
        try container.encode(value)
      }
    case .object(let values):
      var container = encoder.container(keyedBy: PMFJSONCodingKey.self)
      for key in values.keys.sorted() {
        if let value = values[key] {
          try container.encode(value, forKey: PMFJSONCodingKey(stringValue: key))
        }
      }
    }
  }
}

private struct PMFJSONCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

enum PMFJSONCanonicalizer {
  static func canonicalJSON(_ json: String) throws -> String {
    guard let data = json.data(using: .utf8) else {
      throw PMFJSONCanonicalizerError.notUTF8
    }
    let value = try JSONDecoder().decode(PMFJSONValue.self, from: data)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let encoded = try encoder.encode(value)
    return String(decoding: encoded, as: UTF8.self)
  }
}

private enum PMFJSONCanonicalizerError: LocalizedError {
  case notUTF8

  var errorDescription: String? {
    switch self {
    case .notUTF8:
      return "JSON string was not UTF-8."
    }
  }
}
