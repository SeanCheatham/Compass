import Foundation

extension Prompts {
  static let pmfPersonaActionPromptVersionID = "pmf.persona_action.v1"
  static let pmfFeedbackPromptVersionID = "pmf.feedback.v1"

  static func pmfPersonaActionPrompt(
    context: PMFPersonaActionPromptContext
  ) throws -> String {
    let contextJSON = try encodePromptJSON(PMFPersonaActionPromptDigest(context: context))
    return """
      You are acting as a skeptical product-market-fit persona inside Compass.
      Prompt version: \(pmfPersonaActionPromptVersionID).

      Choose exactly one semantic action from the app's `allowedActions`. Judge
      only the product claim and generated app state shown in the context. Do not
      invent hidden features, screens, data, integrations, or actions.

      Persona guardrails:
      - Do not be polite.
      - Do not assume hidden features.
      - Judge only the experience and product claim shown.
      - Prefer concrete objections over generic praise.
      - Distinguish "I understand it" from "I would use or pay for it."
      - Name the current alternative when relevant.

      Return only JSON. Use this exact top-level shape:
      {
        "actionId": "inspect_value_prop",
        "params": {},
        "rationale": "I need to understand whether this solves my reporting pain.",
        "expectation": "I expect to see a concrete workflow or outcome.",
        "confusion": null
      }

      Validation rules:
      - `actionId` is required and must exactly match one id in `allowedActions`.
      - `params` is required and must be a JSON object.
      - `rationale` is required and non-empty.
      - `expectation` is required and non-empty.
      - `confusion` is required; use null only when nothing is confusing.
      - Unknown top-level fields are rejected.

      Schema:
      ```json
      \(pmfPersonaActionSchema)
      ```

      Context:
      ```json
      \(contextJSON)
      ```
      """
  }

  static func pmfPersonaActionRepairPrompt(
    validationError: PMFPromptValidationError,
    context: PMFPersonaActionPromptContext
  ) throws -> String {
    let allowed = context.allowedActions.map(\.id).joined(separator: ", ")
    let contextJSON = try encodePromptJSON(PMFPersonaActionPromptDigest(context: context))
    return """
      Repair your previous PMF persona action response.
      Prompt version: \(pmfPersonaActionPromptVersionID).

      Validation error:
      \(validationError.localizedDescription)

      Allowed action ids:
      \(allowed)

      Return only valid JSON with exactly these keys:
      `actionId`, `params`, `rationale`, `expectation`, `confusion`.
      Do not invent actions. Do not add unknown fields. `params` must be a JSON
      object. Reuse the same state below.

      Context:
      ```json
      \(contextJSON)
      ```
      """
  }

  static func pmfFeedbackPrompt(
    context: PMFFeedbackPromptContext
  ) throws -> String {
    let contextJSON = try encodePromptJSON(PMFFeedbackPromptDigest(context: context))
    return """
      You are the same skeptical PMF persona after completing a generated app
      experience. Prompt version: \(pmfFeedbackPromptVersionID).

      Give subjective product feedback. Judge only the deterministic trace,
      visible product claim, and persona task in the context. Do not assume
      hidden capabilities. Do not be polite. Prefer concrete objections.
      Distinguish "I understand it" from "I would use or pay for it."

      Scores use a strict 1 to 5 scale:
      1 = very weak, 2 = weak, 3 = mixed, 4 = strong, 5 = very strong.

      `taskOutcome` must be one of:
      `succeeded`, `partial`, `failed`, `abandoned`.

      `verdict` must be one of:
      `strong_pull`, `some_pull`, `not_yet`, `wrong_user`.

      Return only JSON. Use this exact top-level shape:
      {
        "valueScore": 3,
        "clarityScore": 2,
        "trustScore": 3,
        "switchLikelihood": 2,
        "payLikelihood": 1,
        "taskOutcome": "partial",
        "topObjection": "I still cannot tell how this replaces my current spreadsheet.",
        "missingCapability": "A concrete import or reporting example.",
        "momentOfDelight": null,
        "momentOfConfusion": "The first screen says ready but not ready for what.",
        "verdict": "not_yet",
        "summary": "The promise is plausible, but the experience does not prove value quickly."
      }

      Validation rules:
      - Scores are required integers from 1 through 5.
      - Enums must match the listed values exactly.
      - `topObjection`, `missingCapability`, and `summary` are required and non-empty.
      - Unknown top-level fields are rejected.

      Schema:
      ```json
      \(pmfFeedbackSchema)
      ```

      Context:
      ```json
      \(contextJSON)
      ```
      """
  }

  static func pmfFeedbackRepairPrompt(
    validationError: PMFPromptValidationError,
    context: PMFFeedbackPromptContext
  ) throws -> String {
    let contextJSON = try encodePromptJSON(PMFFeedbackPromptDigest(context: context))
    return """
      Repair your previous PMF feedback response.
      Prompt version: \(pmfFeedbackPromptVersionID).

      Validation error:
      \(validationError.localizedDescription)

      Return only valid JSON with exactly the feedback keys from
      \(pmfFeedbackPromptVersionID). Scores must be integers from 1 through 5.
      `taskOutcome` and `verdict` must match the allowed enums exactly. Do not
      add unknown fields. Reuse the same trace context below.

      Context:
      ```json
      \(contextJSON)
      ```
      """
  }

  static func decodePMFPersonaActionResponse(
    _ json: String,
    allowedActions: [PMFExperienceAllowedAction]
  ) throws -> PMFPersonaActionPromptOutput {
    let object = try PMFPromptJSON.topLevelObject(json)
    try PMFPromptJSON.rejectUnknownKeys(
      in: object,
      allowed: PMFPersonaActionPromptPayload.allowedKeys
    )
    try PMFPromptJSON.requireKeys(PMFPersonaActionPromptPayload.requiredKeys, in: object)

    let data = Data(json.utf8)
    let payload: PMFPersonaActionPromptPayload
    do {
      payload = try JSONDecoder().decode(PMFPersonaActionPromptPayload.self, from: data)
    } catch {
      throw PMFPromptValidationError.invalidJSON(error.localizedDescription)
    }

    guard case .object = payload.params else {
      throw PMFPromptValidationError.paramsMustBeObject
    }
    guard !payload.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PMFPromptValidationError.emptyField("rationale")
    }
    guard !payload.expectation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PMFPromptValidationError.emptyField("expectation")
    }

    let allowedIDs = allowedActions.map(\.id)
    guard allowedIDs.contains(payload.actionId) else {
      throw PMFPromptValidationError.actionNotAllowed(
        actionID: payload.actionId,
        allowedActionIDs: allowedIDs
      )
    }

    return PMFPersonaActionPromptOutput(
      promptVersionID: pmfPersonaActionPromptVersionID,
      action: PMFExperienceAction(id: payload.actionId, params: payload.params),
      rationale: payload.rationale,
      expectation: payload.expectation,
      confusion: payload.confusion
    )
  }

  static func decodePMFFeedbackResponse(_ json: String) throws -> PMFFeedbackPromptOutput {
    let object = try PMFPromptJSON.topLevelObject(json)
    try PMFPromptJSON.rejectUnknownKeys(
      in: object,
      allowed: PMFFeedbackPromptPayload.allowedKeys
    )
    try PMFPromptJSON.requireKeys(PMFFeedbackPromptPayload.requiredKeys, in: object)

    for field in PMFFeedbackPromptPayload.scoreKeys {
      if let value = object[field] as? Int, !(1...5).contains(value) {
        throw PMFPromptValidationError.scoreOutOfRange(field: field, value: value)
      }
    }
    try PMFPromptJSON.requireEnum(
      field: "taskOutcome",
      in: object,
      allowed: PMFTaskOutcome.allCases.map(\.rawValue)
    )
    try PMFPromptJSON.requireEnum(
      field: "verdict",
      in: object,
      allowed: PMFPersonaVerdict.allCases.map(\.rawValue)
    )

    let data = Data(json.utf8)
    let payload: PMFFeedbackPromptPayload
    do {
      payload = try JSONDecoder().decode(PMFFeedbackPromptPayload.self, from: data)
    } catch {
      throw PMFPromptValidationError.invalidJSON(error.localizedDescription)
    }

    for (field, score) in [
      ("valueScore", payload.valueScore),
      ("clarityScore", payload.clarityScore),
      ("trustScore", payload.trustScore),
      ("switchLikelihood", payload.switchLikelihood),
      ("payLikelihood", payload.payLikelihood),
    ] where !(1...5).contains(score) {
      throw PMFPromptValidationError.scoreOutOfRange(field: field, value: score)
    }

    for (field, text) in [
      ("topObjection", payload.topObjection),
      ("missingCapability", payload.missingCapability),
      ("summary", payload.summary),
    ] where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw PMFPromptValidationError.emptyField(field)
    }

    return PMFFeedbackPromptOutput(
      promptVersionID: pmfFeedbackPromptVersionID,
      valueScore: payload.valueScore,
      clarityScore: payload.clarityScore,
      trustScore: payload.trustScore,
      switchLikelihood: payload.switchLikelihood,
      payLikelihood: payload.payLikelihood,
      taskOutcome: payload.taskOutcome,
      topObjection: payload.topObjection,
      missingCapability: payload.missingCapability,
      momentOfDelight: payload.momentOfDelight,
      momentOfConfusion: payload.momentOfConfusion,
      verdict: payload.verdict,
      summary: payload.summary
    )
  }

  private static func encodePromptJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
  }
}

struct PMFPersonaActionPromptContext: Equatable, Sendable {
  var request: PMFSimulationRequestContext
  var turnIndex: Int
  var maxTurns: Int
  var trace: PMFExperienceTrace
  var allowedActions: [PMFExperienceAllowedAction]
  var priorTranscript: [PMFPersonaActionTranscriptEntry]

  init(
    request: PMFSimulationRequestContext,
    turnIndex: Int,
    maxTurns: Int,
    trace: PMFExperienceTrace,
    allowedActions: [PMFExperienceAllowedAction],
    priorTranscript: [PMFPersonaActionTranscriptEntry] = []
  ) {
    self.request = request
    self.turnIndex = turnIndex
    self.maxTurns = max(1, maxTurns)
    self.trace = trace
    self.allowedActions = allowedActions
    self.priorTranscript = priorTranscript
  }
}

struct PMFFeedbackPromptContext: Equatable, Sendable {
  var request: PMFSimulationRequestContext
  var trace: PMFExperienceTrace
  var actionTranscript: [PMFPersonaActionTranscriptEntry]

  init(
    request: PMFSimulationRequestContext,
    trace: PMFExperienceTrace,
    actionTranscript: [PMFPersonaActionTranscriptEntry]
  ) {
    self.request = request
    self.trace = trace
    self.actionTranscript = actionTranscript
  }
}

struct PMFPersonaActionPromptOutput: Codable, Equatable, Sendable {
  var promptVersionID: String
  var action: PMFExperienceAction
  var rationale: String
  var expectation: String
  var confusion: String?

  var choice: PMFPersonaActionChoice {
    PMFPersonaActionChoice(
      promptVersionID: promptVersionID,
      action: action,
      rationale: rationale,
      rawResponse: ""
    )
  }
}

struct PMFFeedbackPromptOutput: Codable, Equatable, Sendable {
  var promptVersionID: String
  var valueScore: Int
  var clarityScore: Int
  var trustScore: Int
  var switchLikelihood: Int
  var payLikelihood: Int
  var taskOutcome: PMFTaskOutcome
  var topObjection: String
  var missingCapability: String
  var momentOfDelight: String?
  var momentOfConfusion: String?
  var verdict: PMFPersonaVerdict
  var summary: String
}

enum PMFTaskOutcome: String, Codable, CaseIterable, Equatable, Sendable {
  case succeeded
  case partial
  case failed
  case abandoned
}

enum PMFPersonaVerdict: String, Codable, CaseIterable, Equatable, Sendable {
  case strongPull = "strong_pull"
  case somePull = "some_pull"
  case notYet = "not_yet"
  case wrongUser = "wrong_user"
}

enum PMFPromptValidationError: LocalizedError, Equatable {
  case invalidJSON(String)
  case unknownFields([String])
  case missingField(String)
  case emptyField(String)
  case actionNotAllowed(actionID: String, allowedActionIDs: [String])
  case paramsMustBeObject
  case scoreOutOfRange(field: String, value: Int)
  case invalidEnum(field: String, value: String, allowedValues: [String])

  var errorDescription: String? {
    switch self {
    case .invalidJSON(let detail):
      return "Response is not valid JSON for this prompt contract: \(detail)"
    case .unknownFields(let fields):
      return "Unknown top-level field(s): \(fields.sorted().joined(separator: ", "))."
    case .missingField(let field):
      return "Missing required field `\(field)`."
    case .emptyField(let field):
      return "Field `\(field)` must be non-empty."
    case .actionNotAllowed(let actionID, let allowedActionIDs):
      return
        "Action `\(actionID)` is not allowed. Allowed actions: \(allowedActionIDs.joined(separator: ", "))."
    case .paramsMustBeObject:
      return "`params` must be a JSON object."
    case .scoreOutOfRange(let field, let value):
      return "Score `\(field)` must be an integer from 1 through 5, got \(value)."
    case .invalidEnum(let field, let value, let allowedValues):
      return
        "`\(field)` must be one of \(allowedValues.joined(separator: ", ")), got `\(value)`."
    }
  }
}

private struct PMFPersonaActionPromptPayload: Decodable {
  static let allowedKeys: Set<String> = ["actionId", "params", "rationale", "expectation", "confusion"]
  static let requiredKeys: Set<String> = allowedKeys

  var actionId: String
  var params: PMFJSONValue
  var rationale: String
  var expectation: String
  var confusion: String?
}

private struct PMFFeedbackPromptPayload: Decodable {
  static let scoreKeys: Set<String> = [
    "valueScore",
    "clarityScore",
    "trustScore",
    "switchLikelihood",
    "payLikelihood",
  ]
  static let allowedKeys: Set<String> = scoreKeys.union([
    "taskOutcome",
    "topObjection",
    "missingCapability",
    "momentOfDelight",
    "momentOfConfusion",
    "verdict",
    "summary",
  ])
  static let requiredKeys: Set<String> = allowedKeys

  var valueScore: Int
  var clarityScore: Int
  var trustScore: Int
  var switchLikelihood: Int
  var payLikelihood: Int
  var taskOutcome: PMFTaskOutcome
  var topObjection: String
  var missingCapability: String
  var momentOfDelight: String?
  var momentOfConfusion: String?
  var verdict: PMFPersonaVerdict
  var summary: String
}

private enum PMFPromptJSON {
  static func topLevelObject(_ json: String) throws -> [String: Any] {
    let data = Data(json.utf8)
    let parsed: Any
    do {
      parsed = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw PMFPromptValidationError.invalidJSON(error.localizedDescription)
    }
    guard let object = parsed as? [String: Any] else {
      throw PMFPromptValidationError.invalidJSON("Top-level response must be a JSON object.")
    }
    return object
  }

  static func rejectUnknownKeys(in object: [String: Any], allowed: Set<String>) throws {
    let unknown = Set(object.keys).subtracting(allowed)
    guard unknown.isEmpty else {
      throw PMFPromptValidationError.unknownFields(Array(unknown))
    }
  }

  static func requireKeys(_ required: Set<String>, in object: [String: Any]) throws {
    for field in required.sorted() where object[field] == nil {
      throw PMFPromptValidationError.missingField(field)
    }
  }

  static func requireEnum(
    field: String,
    in object: [String: Any],
    allowed: [String]
  ) throws {
    guard let value = object[field] as? String else { return }
    guard allowed.contains(value) else {
      throw PMFPromptValidationError.invalidEnum(
        field: field,
        value: value,
        allowedValues: allowed
      )
    }
  }
}

private struct PMFPersonaActionPromptDigest: Encodable {
  var promptVersionID: String
  var productHypothesis: ProductHypothesis
  var persona: PMFPersona
  var task: PMFTask
  var scenario: PMFScenario
  var turnIndex: Int
  var maxTurns: Int
  var currentState: PMFExperienceState
  var visibleSemanticNodes: [PMFExperienceNode]
  var allowedActions: [PMFExperienceAllowedAction]
  var priorActionTranscript: [PMFPersonaActionTranscriptEntry]

  init(context: PMFPersonaActionPromptContext) {
    let currentState = context.trace.turns.last?.state ?? context.trace.initialState
    self.promptVersionID = Prompts.pmfPersonaActionPromptVersionID
    productHypothesis = context.request.hypothesis
    persona = context.request.persona
    task = context.request.task
    scenario = context.request.scenario
    turnIndex = context.turnIndex
    maxTurns = context.maxTurns
    self.currentState = currentState
    visibleSemanticNodes = currentState.semanticNodes
    allowedActions = context.allowedActions
    priorActionTranscript = context.priorTranscript
  }
}

private struct PMFFeedbackPromptDigest: Encodable {
  struct TurnSummary: Encodable {
    var index: Int
    var actionID: String
    var stateID: String
    var headline: String
    var observations: [String]
  }

  var promptVersionID: String
  var productHypothesis: ProductHypothesis
  var persona: PMFPersona
  var task: PMFTask
  var scenario: PMFScenario
  var terminalStatus: PMFExperienceTerminalStatus
  var terminalState: PMFExperienceState
  var turns: [TurnSummary]
  var eventLog: [String]
  var actionTranscript: [PMFPersonaActionTranscriptEntry]

  init(context: PMFFeedbackPromptContext) {
    let terminalState = context.trace.turns.last?.state ?? context.trace.initialState
    promptVersionID = Prompts.pmfFeedbackPromptVersionID
    productHypothesis = context.request.hypothesis
    persona = context.request.persona
    task = context.request.task
    scenario = context.request.scenario
    terminalStatus = context.trace.terminalStatus
    self.terminalState = terminalState
    turns = context.trace.turns.map {
      TurnSummary(
        index: $0.index,
        actionID: $0.action.id,
        stateID: $0.state.id,
        headline: $0.state.headline,
        observations: $0.state.observations
      )
    }
    eventLog = context.trace.eventLog
    actionTranscript = context.actionTranscript
  }
}
