import Foundation

enum AgentContinuationPhase: String, Equatable, Sendable, CaseIterable {
  case plan
  case develop
  case critic
  case delegate

  init(agentPhase: AgentPhase) {
    switch agentPhase {
    case .plan:
      self = .plan
    case .develop:
      self = .develop
    case .critic:
      self = .critic
    }
  }

  var continueKind: String { "\(rawValue)_continue" }
  var submitKind: String { "\(rawValue)_submit" }
}

struct AgentContinuation: Equatable, Sendable {
  enum Action: Equatable, Sendable {
    case continueTool(toolName: String, arguments: Data, reason: String?)
    case submit(payload: Data)
  }

  var kind: String
  var phase: AgentContinuationPhase
  var action: Action
}

enum AgentContinuationParseError: LocalizedError, Equatable {
  case malformedJSON(String)
  case topLevelNotObject
  case missingKind
  case wrongPhaseKind(expected: [String], actual: String)
  case missingTool
  case unknownTool(String)
  case argumentsNotObject
  case missingPayload
  case payloadNotObject
  case invalidJSONObject

  var errorDescription: String? {
    switch self {
    case .malformedJSON(let detail):
      return "Malformed JSON continuation: \(detail)"
    case .topLevelNotObject:
      return "Continuation must be exactly one top-level JSON object."
    case .missingKind:
      return "Continuation is missing string field `kind`."
    case .wrongPhaseKind(let expected, let actual):
      return "Continuation kind `\(actual)` is invalid for this phase. Expected \(expected.joined(separator: " or "))."
    case .missingTool:
      return "Continue envelope is missing string field `tool`."
    case .unknownTool(let tool):
      return "Unknown tool `\(tool)` for this phase."
    case .argumentsNotObject:
      return "Continue envelope field `arguments` must be a JSON object."
    case .missingPayload:
      return "Submit envelope is missing object field `payload`."
    case .payloadNotObject:
      return "Submit envelope field `payload` must be a JSON object."
    case .invalidJSONObject:
      return "Continuation contains a value that cannot be serialized back to JSON."
    }
  }
}

enum AgentContinuationParser {
  static func parse(
    _ text: String,
    phase: AgentContinuationPhase,
    availableToolNames: Set<String>
  ) throws -> AgentContinuation {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
      throw AgentContinuationParseError.malformedJSON(
        "The response must not include prose, Markdown fences, or multiple objects."
      )
    }
    let data = Data(trimmed.utf8)
    let raw: Any
    do {
      raw = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw AgentContinuationParseError.malformedJSON(error.localizedDescription)
    }
    guard let object = raw as? [String: Any] else {
      throw AgentContinuationParseError.topLevelNotObject
    }
    guard let kind = object["kind"] as? String,
      !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AgentContinuationParseError.missingKind
    }

    let expected = [phase.continueKind, phase.submitKind]
    guard expected.contains(kind) else {
      throw AgentContinuationParseError.wrongPhaseKind(expected: expected, actual: kind)
    }

    if kind == phase.continueKind {
      guard let rawTool = object["tool"] as? String,
        !rawTool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw AgentContinuationParseError.missingTool
      }
      guard let toolName = AgentExecutor.canonicalToolName(
        rawTool,
        availableToolNames: availableToolNames
      ) else {
        throw AgentContinuationParseError.unknownTool(rawTool)
      }
      guard let arguments = object["arguments"] as? [String: Any] else {
        throw AgentContinuationParseError.argumentsNotObject
      }
      let reason = (object["reason"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return AgentContinuation(
        kind: kind,
        phase: phase,
        action: .continueTool(
          toolName: toolName,
          arguments: try encodeJSONObject(arguments),
          reason: reason?.isEmpty == true ? nil : reason
        )
      )
    }

    guard object.keys.contains("payload") else {
      throw AgentContinuationParseError.missingPayload
    }
    guard let payload = object["payload"] as? [String: Any] else {
      throw AgentContinuationParseError.payloadNotObject
    }
    return AgentContinuation(
      kind: kind,
      phase: phase,
      action: .submit(payload: try encodeJSONObject(payload))
    )
  }

  private static func encodeJSONObject(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw AgentContinuationParseError.invalidJSONObject
    }
    return try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
  }
}
