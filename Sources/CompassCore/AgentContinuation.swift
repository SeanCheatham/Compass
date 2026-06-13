import Foundation

package enum AgentContinuationPhase: String, Equatable, Sendable, CaseIterable {
  case plan
  case develop
  case critic
  case delegate

  package init(agentPhase: AgentPhase) {
    switch agentPhase {
    case .plan:
      self = .plan
    case .develop:
      self = .develop
    case .critic:
      self = .critic
    }
  }

  package var continueKind: String { "\(rawValue)_continue" }
  package var submitKind: String { "\(rawValue)_submit" }
}

package struct AgentContinuation: Equatable, Sendable {
  package enum Action: Equatable, Sendable {
    case continueTool(toolName: String, arguments: Data, reason: String?, note: String?)
    case submit(payload: Data)
  }

  package var kind: String
  package var phase: AgentContinuationPhase
  package var action: Action
}

package enum AgentContinuationParseError: LocalizedError, Equatable {
  case malformedJSON(String)
  case topLevelNotObject
  case missingKind
  case wrongPhaseKind(expected: [String], actual: String)
  case missingTool
  case unknownTool(String)
  case argumentsNotObject
  case noteNotString
  case missingPayload
  case payloadNotObject
  case invalidJSONObject

  package var errorDescription: String? {
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
    case .noteNotString:
      return "Continue envelope field `note` must be a string when present."
    case .missingPayload:
      return "Submit envelope is missing object field `payload`."
    case .payloadNotObject:
      return "Submit envelope field `payload` must be a JSON object."
    case .invalidJSONObject:
      return "Continuation contains a value that cannot be serialized back to JSON."
    }
  }
}

package enum AgentContinuationParser {
  package static let noteCharacterLimit = 800

  package static func parse(
    _ text: String,
    phase: AgentContinuationPhase,
    availableToolNames: Set<String>
  ) throws -> AgentContinuation {
    let jsonText = try normalizedJSONObjectText(from: text)
    let data = Data(jsonText.utf8)
    let raw: Any
    do {
      raw = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw AgentContinuationParseError.malformedJSON(
        malformedJSONDetail(for: jsonText, underlying: error.localizedDescription)
      )
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
      let note = try sanitizedNote(from: object)
      return AgentContinuation(
        kind: kind,
        phase: phase,
        action: .continueTool(
          toolName: toolName,
          arguments: try encodeJSONObject(arguments),
          reason: reason?.isEmpty == true ? nil : reason,
          note: note
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

  private static func sanitizedNote(from object: [String: Any]) throws -> String? {
    guard object.keys.contains("note") else { return nil }
    guard let raw = object["note"] as? String else {
      throw AgentContinuationParseError.noteNotString
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(noteCharacterLimit))
  }

  private static func normalizedJSONObjectText(from text: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
      return trimmed
    }
    if let fenced = singleFencedJSONObjectText(from: trimmed) {
      return fenced
    }
    throw AgentContinuationParseError.malformedJSON(
      "The response must be exactly one JSON object. Compass can unwrap one JSON code fence, but it cannot accept prose or multiple objects."
    )
  }

  private static func singleFencedJSONObjectText(from text: String) -> String? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count >= 3 else { return nil }
    let first = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let last = lines[lines.count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard first.hasPrefix("```"), last == "```" else { return nil }

    let infoString = String(first.dropFirst(3))
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard infoString.isEmpty || infoString == "json" else { return nil }

    let body = lines.dropFirst().dropLast().joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard body.hasPrefix("{"), body.hasSuffix("}") else { return nil }
    return body
  }

  private static func malformedJSONDetail(for text: String, underlying: String) -> String {
    var detail = underlying
    if containsBacktickStringSyntax(in: text) {
      detail +=
        " JSON strings must use double quotes; JavaScript backtick/template-literal strings are invalid here. For multiline edit_file content, pass replacementLines as an array with one source line per string or use a normal JSON string with \\n escapes. Do not wrap content in backticks."
    }
    return detail
  }

  private static func containsBacktickStringSyntax(in text: String) -> Bool {
    text.range(of: #":\s*`"#, options: .regularExpression) != nil
      || text.range(of: #"\[\s*`"#, options: .regularExpression) != nil
      || text.range(of: #",\s*`"#, options: .regularExpression) != nil
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
