import CryptoKit
import Foundation

struct ProductizationSimulationRequest {
  var projectID: UUID?
  var projectTitle: String
  var pain: PainHypothesis
  var segment: UserSegment
  var currentWorkflow: CurrentWorkflow
  var alternatives: [Alternative]
  var solution: SolutionHypothesis
  var experiment: ProductExperiment
  var scenarioID: String
  var commitSha: String
  var generatedAppWorkingDirectory: URL
  var launchPlan: AgentExecutionLaunchPlan
  var settings: AgentRuntimeSettings
  var mode: ProductizationSimulationMode
  var maxTurns: Int
  var fixtureActions: [ProductizationExperienceAction]
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
    commitSha: String? = nil,
    generatedAppWorkingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    mode: ProductizationSimulationMode = .modelFree,
    maxTurns: Int = 8,
    fixtureActions: [ProductizationExperienceAction]? = nil,
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
    self.scenarioID = ProductizationModelText.identifier(scenarioID, fallback: "scenario")
    let commit = StringUtils.boundedText(
      commitSha ?? experiment.currentSha ?? experiment.baseSha ?? "unknown",
      limit: 80
    )
    self.commitSha = commit.isEmpty ? "unknown" : commit
    self.generatedAppWorkingDirectory = generatedAppWorkingDirectory.standardizedFileURL
    self.launchPlan = launchPlan
    self.settings = settings
    self.mode = mode
    self.maxTurns = max(1, maxTurns)
    self.fixtureActions = fixtureActions ?? Self.defaultFixtureActions
    self.appCommandTimeout = appCommandTimeout
  }

  static let defaultFixtureActions: [ProductizationExperienceAction] = [
    ProductizationExperienceAction(id: "inspect_pain"),
    ProductizationExperienceAction(id: "compare_current_alternative"),
    ProductizationExperienceAction(id: "reduce_switching_objection"),
    ProductizationExperienceAction(id: "start_solution_workflow"),
    ProductizationExperienceAction(id: "provide_requested_input"),
  ]

  func experienceInput(actions: [ProductizationExperienceAction]) -> ProductizationExperienceInput {
    ProductizationExperienceInput(
      schemaVersion: 1,
      pain: ProductizationExperiencePain(
        id: pain.id,
        summary: pain.rawPain,
        impact: pain.costOfInaction
      ),
      solution: ProductizationExperienceSolution(
        id: solution.id,
        title: solution.title,
        promise: solution.promise
      ),
      experiment: ProductizationExperienceExperiment(
        id: experiment.id,
        branchName: experiment.branchName,
        successSignal: solution.requiredProof.first ?? experiment.prototypeScope
      ),
      scenario: ProductizationExperienceScenario(
        seed: scenarioID,
        personaSummary: [
          segment.name,
          segment.role,
          segment.context,
          "Skepticism: \(segment.skepticism)",
        ].filter { !$0.isEmpty }.joined(separator: ". "),
        task: [
          experiment.prototypeScope,
          "Desired pain relief: \(solution.promise)",
          "Decision criteria: \(segment.decisionCriteria.joined(separator: "; "))",
        ].filter { !$0.isEmpty }.joined(separator: ". ")
      ),
      currentWorkflow: ProductizationExperienceCurrentWorkflow(
        summary: [
          currentWorkflow.title,
          currentWorkflow.steps.joined(separator: " -> "),
          currentWorkflow.estimatedCost,
        ].filter { !$0.isEmpty }.joined(separator: ". "),
        frictionPoints: (
          currentWorkflow.failureModes + currentWorkflow.handoffs + currentWorkflow.workarounds
        ).isEmpty ? currentWorkflow.steps : (
          currentWorkflow.failureModes + currentWorkflow.handoffs + currentWorkflow.workarounds
        )
      ),
      alternatives: alternatives.map {
        ProductizationExperienceAlternative(
          id: $0.id,
          name: $0.title,
          description: ($0.strengths + $0.weaknesses).joined(separator: "; "),
          switchingObjection: $0.switchingCost
        )
      },
      actions: actions
    )
  }
}

struct ProductizationRunResult: Codable, Equatable, Sendable {
  var projectID: UUID?
  var projectTitle: String
  var experimentID: String
  var solutionID: String
  var painID: String
  var branchName: String
  var commitSha: String
  var scenarioID: String
  var personaID: String
  var mode: ProductizationSimulationMode
  var routeIdentifier: String
  var modelProvider: String
  var model: String
  var status: ProductizationRunStatus
  var actions: [ProductizationExperienceAction]
  var rawPersonaActionTranscript: [ProductizationPersonaActionTranscriptEntry]
  var experienceTraceJSON: String?
  var experienceTraceHash: String?
  var productizationTrace: ProductizationExperienceTrace?
  var failure: ProductizationRunFailure?

  var isSuccess: Bool {
    status == .completed
  }
}

struct ProductizationPersonaActionTranscriptEntry: Codable, Equatable, Sendable {
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
    promptVersionID: String = "productization.persona_action.v1",
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

struct ProductizationPersonaActionChoice: Equatable, Sendable {
  var promptVersionID: String
  var action: ProductizationExperienceAction
  var rationale: String
  var rawResponse: String

  init(
    promptVersionID: String = "productization.persona_action.v1",
    action: ProductizationExperienceAction,
    rationale: String = "",
    rawResponse: String = ""
  ) {
    self.promptVersionID = promptVersionID
    self.action = action
    self.rationale = rationale
    self.rawResponse = rawResponse
  }
}

struct ProductizationPersonaActionContext: Equatable, Sendable {
  var request: ProductizationSimulationRequestContext
  var turnIndex: Int
  var trace: ProductizationExperienceTrace
  var allowedActions: [ProductizationExperienceAllowedAction]
  var actionPrefix: [ProductizationExperienceAction]
}

struct ProductizationPersonaActionRepairContext: Equatable, Sendable {
  var actionContext: ProductizationPersonaActionContext
  var invalidChoice: ProductizationPersonaActionChoice
  var allowedActionIDs: [String]
}

struct ProductizationSimulationRequestContext: Equatable, Sendable {
  var projectTitle: String
  var pain: PainHypothesis
  var segment: UserSegment
  var currentWorkflow: CurrentWorkflow
  var alternatives: [Alternative]
  var solution: SolutionHypothesis
  var experiment: ProductExperiment
  var scenarioID: String
  var commitSha: String
  var settings: AgentRuntimeSettings
}

protocol ProductizationPersonaActionSelecting {
  func chooseAction(
    context: ProductizationPersonaActionContext
  ) async throws -> ProductizationPersonaActionChoice
  func repairAction(
    context: ProductizationPersonaActionRepairContext
  ) async throws -> ProductizationPersonaActionChoice
}

protocol ProductizationExperienceAppRunning {
  func productizationExperienceContractAvailable(workingDirectory: URL) async -> Bool

  func runProductizationExperience(
    input: ProductizationExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult
}

struct ProductizationExperienceCLIAppRunner: ProductizationExperienceAppRunning {
  var processRunner: ProcessRunner.InvocationRunner?

  init(processRunner: ProcessRunner.InvocationRunner? = nil) {
    self.processRunner = processRunner
  }

  func productizationExperienceContractAvailable(workingDirectory: URL) async -> Bool {
    let fm = FileManager.default
    let requiredRelativePaths = [
      "Cargo.toml",
      "crates/app-cli/Cargo.toml",
      "crates/app-core/Cargo.toml",
      "schemas/productization-experience-input.schema.json",
      "schemas/productization-experience-trace.schema.json",
    ]
    return requiredRelativePaths.allSatisfy {
      fm.fileExists(atPath: workingDirectory.appending(path: $0).path)
    }
  }

  func runProductizationExperience(
    input: ProductizationExperienceInput,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeout: TimeInterval?
  ) async throws -> ProcessResult {
    let inputJSON = try Self.inputJSONString(input)
    let command = Self.productizationExperienceCommand(inputJSON: inputJSON)
    return try await ProcessRunner.runShell(
      command,
      workingDirectory: workingDirectory,
      timeout: timeout,
      launchPlan: launchPlan,
      runner: processRunner
    )
  }

  static func productizationExperienceCommand(inputJSON: String) -> String {
    RustVerifyCommands.cargo([
      "run", "-p", "app-cli", "--", "productization-experience", "--input", inputJSON,
    ])
  }

  static func inputJSONString(_ input: ProductizationExperienceInput) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    return String(decoding: data, as: UTF8.self)
  }
}

struct ProductizationSimulationRunner {
  var appRunner: ProductizationExperienceAppRunning
  var personaSelector: ProductizationPersonaActionSelecting?

  init(
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    personaSelector: ProductizationPersonaActionSelecting? = nil
  ) {
    self.appRunner = appRunner
    self.personaSelector = personaSelector
  }

  func run(_ request: ProductizationSimulationRequest) async -> ProductizationRunResult {
    guard await appRunner.productizationExperienceContractAvailable(
      workingDirectory: request.generatedAppWorkingDirectory
    ) else {
      return makeResult(
        request: request,
        status: .appContractMissing,
        actions: [],
        transcript: [],
        traceJSON: nil,
        traceHash: nil,
        trace: nil,
        failure: ProductizationRunFailure(
          status: .appContractMissing,
          message: "The generated app is missing the productization experience CLI contract."
        )
      )
    }

    var actions: [ProductizationExperienceAction] = []
    var transcript: [ProductizationPersonaActionTranscriptEntry] = []

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
            failure: ProductizationRunFailure(
              status: .noAllowedActions,
              message:
                "The productization trace is still in progress but returned no allowed actions."
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
              failure: ProductizationRunFailure(
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
                choice: ProductizationPersonaActionChoice(
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
              choice: ProductizationPersonaActionChoice(action: action),
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
            failure: ProductizationRunFailure(
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
              failure: ProductizationRunFailure(
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
          let choice: ProductizationPersonaActionChoice
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
              failure: ProductizationRunFailure(
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

          let repairChoice: ProductizationPersonaActionChoice
          do {
            repairChoice = try await personaSelector.repairAction(
              context: ProductizationPersonaActionRepairContext(
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
              failure: ProductizationRunFailure(
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
            failure: ProductizationRunFailure(
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
        failure: ProductizationRunFailure(
          status: .maxTurnsReached,
          message: "The run reached the maximum turn budget before a terminal app state."
        )
      )
    }
  }

  private func deterministicResult(
    request: ProductizationSimulationRequest,
    status: ProductizationRunStatus,
    actions: [ProductizationExperienceAction],
    transcript: [ProductizationPersonaActionTranscriptEntry],
    fallbackTraceJSON: String,
    failure: ProductizationRunFailure? = nil
  ) async -> ProductizationRunResult {
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
            trace: trace,
            failure: ProductizationRunFailure(
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
          failure: ProductizationRunFailure(
            status: .appOutputNotJSON,
            message:
              "Final productization trace could not be normalized: \(error.localizedDescription)"
          )
        )
      }
    }
  }

  private func loadTrace(
    request: ProductizationSimulationRequest,
    actions: [ProductizationExperienceAction]
  ) async -> ProductizationTraceLoadOutcome {
    let input = request.experienceInput(actions: actions)
    let result: ProcessResult
    do {
      result = try await appRunner.runProductizationExperience(
        input: input,
        workingDirectory: request.generatedAppWorkingDirectory,
        launchPlan: request.launchPlan,
        timeout: request.appCommandTimeout
      )
    } catch {
      return .failure(
        ProductizationRunFailure(
          status: .appCommandFailed,
          message: "Productization experience CLI command failed: \(error.localizedDescription)"
        ),
        traceJSON: nil
      )
    }

    guard result.exitCode == 0 else {
      return .failure(
        ProductizationRunFailure(
          status: .appCommandFailed,
          message: "Productization experience CLI exited with code \(result.exitCode).",
          stdout: result.stdout,
          stderr: result.stderr
        ),
        traceJSON: result.stdout
      )
    }

    guard let data = result.stdout.data(using: .utf8) else {
      return .failure(
        ProductizationRunFailure(
          status: .appOutputNotJSON,
          message: "Productization experience CLI stdout was not UTF-8."
        ),
        traceJSON: result.stdout
      )
    }

    do {
      let trace = try JSONDecoder().decode(ProductizationExperienceTrace.self, from: data)
      return .success(trace, traceJSON: result.stdout)
    } catch {
      return .failure(
        ProductizationRunFailure(
          status: .appOutputNotJSON,
          message:
            "Productization experience CLI stdout was not a valid productization trace: \(error.localizedDescription).",
          stdout: result.stdout,
          stderr: result.stderr
        ),
        traceJSON: result.stdout
      )
    }
  }

  private func personaContext(
    request: ProductizationSimulationRequest,
    turnIndex: Int,
    trace: ProductizationExperienceTrace,
    allowedActions: [ProductizationExperienceAllowedAction],
    actionPrefix: [ProductizationExperienceAction]
  ) -> ProductizationPersonaActionContext {
    ProductizationPersonaActionContext(
      request: ProductizationSimulationRequestContext(
        projectTitle: request.projectTitle,
        pain: request.pain,
        segment: request.segment,
        currentWorkflow: request.currentWorkflow,
        alternatives: request.alternatives,
        solution: request.solution,
        experiment: request.experiment,
        scenarioID: request.scenarioID,
        commitSha: request.commitSha,
        settings: request.settings
      ),
      turnIndex: turnIndex,
      trace: trace,
      allowedActions: allowedActions,
      actionPrefix: actionPrefix
    )
  }

  private func isValid(
    _ action: ProductizationExperienceAction,
    allowedActions: [ProductizationExperienceAllowedAction]
  ) -> Bool {
    allowedActions.contains { $0.id == action.id }
  }

  private func transcriptEntry(
    turnIndex: Int,
    phase: ProductizationPersonaActionTranscriptEntry.Phase,
    choice: ProductizationPersonaActionChoice,
    wasValid: Bool,
    allowedActions: [ProductizationExperienceAllowedAction]
  ) -> ProductizationPersonaActionTranscriptEntry {
    ProductizationPersonaActionTranscriptEntry(
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
    request: ProductizationSimulationRequest,
    status: ProductizationRunStatus,
    actions: [ProductizationExperienceAction],
    transcript: [ProductizationPersonaActionTranscriptEntry],
    traceJSON: String?,
    traceHash: String?,
    trace: ProductizationExperienceTrace?,
    failure: ProductizationRunFailure?
  ) -> ProductizationRunResult {
    ProductizationRunResult(
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
      routeIdentifier: request.launchPlan.effectiveRouteIdentifier,
      modelProvider: request.settings.textProvider.rawValue,
      model: request.settings.model,
      status: status,
      actions: actions,
      rawPersonaActionTranscript: transcript,
      experienceTraceJSON: traceJSON,
      experienceTraceHash: traceHash,
      productizationTrace: trace,
      failure: failure
    )
  }

  private static func sha256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

private enum ProductizationTraceLoadOutcome {
  case success(ProductizationExperienceTrace, traceJSON: String)
  case failure(ProductizationRunFailure, traceJSON: String?)
}

struct ProductizationExperienceInput: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var pain: ProductizationExperiencePain
  var solution: ProductizationExperienceSolution
  var experiment: ProductizationExperienceExperiment
  var scenario: ProductizationExperienceScenario
  var currentWorkflow: ProductizationExperienceCurrentWorkflow
  var alternatives: [ProductizationExperienceAlternative]
  var actions: [ProductizationExperienceAction]
}

struct ProductizationExperiencePain: Codable, Equatable, Sendable {
  var id: String
  var summary: String
  var impact: String
}

struct ProductizationExperienceSolution: Codable, Equatable, Sendable {
  var id: String
  var title: String
  var promise: String
}

struct ProductizationExperienceExperiment: Codable, Equatable, Sendable {
  var id: String
  var branchName: String
  var successSignal: String
}

struct ProductizationExperienceScenario: Codable, Equatable, Sendable {
  var seed: String
  var personaSummary: String
  var task: String
}

struct ProductizationExperienceCurrentWorkflow: Codable, Equatable, Sendable {
  var summary: String
  var frictionPoints: [String]
}

struct ProductizationExperienceAlternative: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var description: String
  var switchingObjection: String
}

struct ProductizationExperienceAction: Codable, Equatable, Sendable {
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

struct ProductizationExperienceTrace: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var painID: String
  var solutionID: String
  var experimentID: String
  var initialState: ProductizationExperienceState
  var turns: [ProductizationExperienceTurn]
  var allowedNextActions: [ProductizationExperienceAllowedAction]
  var terminalStatus: ProductizationExperienceTerminalStatus
  var eventLog: [String]
  var painReliefSignals: ProductizationPainReliefSignals
}

struct ProductizationExperienceState: Codable, Equatable, Sendable {
  var id: String
  var headline: String
  var body: String
  var semanticNodes: [ProductizationExperienceNode]
  var observations: [String]
  var terminal: Bool
}

struct ProductizationExperienceNode: Codable, Equatable, Sendable {
  var id: String
  var role: String
  var text: String
}

struct ProductizationExperienceTurn: Codable, Equatable, Sendable {
  var index: Int
  var action: ProductizationExperienceAction
  var state: ProductizationExperienceState
  var allowedNextActions: [ProductizationExperienceAllowedAction]
  var eventLog: [String]
}

struct ProductizationExperienceAllowedAction: Codable, Equatable, Sendable {
  var id: String
  var label: String
  var description: String
  var paramsSchema: PMFJSONValue
}

struct ProductizationPainReliefSignals: Codable, Equatable, Sendable {
  var painRecognized: Bool
  var workflowAdvanced: Bool
  var currentAlternativeAddressed: Bool
  var switchingObjectionReduced: Bool
  var missingCapabilityIDs: [String]
  var evidenceSummary: String

  enum CodingKeys: String, CodingKey {
    case painRecognized
    case workflowAdvanced
    case currentAlternativeAddressed
    case switchingObjectionReduced
    case missingCapabilityIDs
    case missingCapabilityIds
    case evidenceSummary
  }

  init(
    painRecognized: Bool,
    workflowAdvanced: Bool,
    currentAlternativeAddressed: Bool,
    switchingObjectionReduced: Bool,
    missingCapabilityIDs: [String],
    evidenceSummary: String
  ) {
    self.painRecognized = painRecognized
    self.workflowAdvanced = workflowAdvanced
    self.currentAlternativeAddressed = currentAlternativeAddressed
    self.switchingObjectionReduced = switchingObjectionReduced
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
    switchingObjectionReduced = try container.decode(
      Bool.self,
      forKey: .switchingObjectionReduced
    )
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
    try container.encode(switchingObjectionReduced, forKey: .switchingObjectionReduced)
    try container.encode(missingCapabilityIDs, forKey: .missingCapabilityIDs)
    try container.encode(evidenceSummary, forKey: .evidenceSummary)
  }
}

enum ProductizationExperienceTerminalStatus: String, Codable, Equatable, Sendable {
  case inProgress = "in_progress"
  case completed
  case abandoned
  case invalidAction = "invalid_action"
}
