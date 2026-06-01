import Foundation

/// Record an assumption the current agent is relying on. This writes to the
/// host-side Compass assumptions ledger, not the agent worktree, so it works
/// consistently for both host and Shared VM routes.
struct AgentRecordAssumptionTool: AgentTool {
  static let toolName = "record_assumption"

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["text", "rationale", "impact"],
      "properties": [
        "text": [
          "type": "string",
          "description":
            "The concise assumption being relied on. Write it as a durable statement, not a question.",
        ],
        "rationale": [
          "type": "string",
          "description":
            "Why this assumption seems reasonable from the current evidence.",
        ],
        "impact": [
          "type": "string",
          "description":
            "What planning, implementation, or review choice depends on this assumption.",
        ],
        "evidence": [
          "type": "array",
          "description":
            "Short supporting facts, file paths, user statements, or command observations.",
          "items": ["type": "string"],
        ],
        "invalidation": [
          "type": "string",
          "description":
            "What would prove the assumption false or require asking the user.",
        ],
        "scope": [
          "type": "string",
          "enum": AssumptionRecord.Scope.allCases.map(\.rawValue),
          "description": "How broadly the assumption should apply.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Record an assumption you are relying on so Compass can show it to the user. Use this for consequential guesses about product intent, environment, constraints, or user preferences. Existing user-denied assumptions remain denied.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let draft: AssumptionDraft
    do {
      draft = try JSONDecoder().decode(Arguments.self, from: arguments).draft
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    guard let assumptionsURL = context.assumptionsURL else {
      return .failure(
        "Assumption ledger is unavailable for this run.",
        kind: .ioFailure
      )
    }

    do {
      let record = try AssumptionLedgerStore(url: assumptionsURL).record(
        draft: draft,
        phase: context.phase,
        sessionNumber: context.sessionNumber
      )
      let statusNote =
        record.status == .denied
        ? " This assumption is currently denied by the user; do not rely on it."
        : ""
      return .ok(
        "Recorded assumption \(record.id) as \(record.status.displayName.lowercased()).\(statusNote)"
      )
    } catch let error as AssumptionLedgerError {
      return .failure(.invalidArguments(error.localizedDescription))
    } catch {
      return .failure(.ioFailure(error.localizedDescription))
    }
  }
}

private struct Arguments: Decodable {
  var draft: AssumptionDraft

  enum CodingKeys: String, CodingKey {
    case text
    case assumption
    case rationale
    case evidence
    case impact
    case invalidation
    case scope
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let text = try Self.firstString(
      in: container,
      keys: [.text, .assumption]
    )
    let rawScope = try Self.optionalString(in: container, key: .scope)
    let scope = try Self.scope(
      from: rawScope,
      codingPath: container.codingPath + [CodingKeys.scope]
    )
    draft = AssumptionDraft(
      text: text,
      rationale: try Self.optionalString(in: container, key: .rationale),
      evidence: try Self.optionalEvidence(in: container),
      impact: try Self.optionalString(in: container, key: .impact),
      invalidation: try Self.optionalString(in: container, key: .invalidation),
      scope: scope
    )
  }

  private static func firstString(
    in container: KeyedDecodingContainer<CodingKeys>,
    keys: [CodingKeys]
  ) throws -> String {
    var firstError: Error?
    for key in keys where container.contains(key) {
      do {
        if let value = try optionalString(in: container, key: key), !value.isEmpty {
          return value
        }
      } catch {
        firstError = firstError ?? error
      }
    }
    if let firstError {
      throw firstError
    }
    throw DecodingError.keyNotFound(
      CodingKeys.text,
      DecodingError.Context(
        codingPath: container.codingPath,
        debugDescription:
          "record_assumption requires a non-empty `text` string. `assumption` is also accepted as a compatibility alias."
      )
    )
  }

  private static func optionalString(
    in container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) throws -> String? {
    guard container.contains(key), try !container.decodeNil(forKey: key) else {
      return nil
    }
    do {
      return try container.decode(String.self, forKey: key)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw DecodingError.typeMismatch(
        String.self,
        DecodingError.Context(
          codingPath: container.codingPath + [key],
          debugDescription: "`\(key.stringValue)` must be a string."
        )
      )
    }
  }

  private static func optionalEvidence(
    in container: KeyedDecodingContainer<CodingKeys>
  ) throws -> [String]? {
    let key = CodingKeys.evidence
    guard container.contains(key), try !container.decodeNil(forKey: key) else {
      return nil
    }
    if let values = try? container.decode([String].self, forKey: key) {
      return values
    }
    if let value = try? optionalString(in: container, key: key) {
      return value.isEmpty ? [] : [value]
    }
    throw DecodingError.typeMismatch(
      [String].self,
      DecodingError.Context(
        codingPath: container.codingPath + [key],
        debugDescription: "`evidence` must be an array of strings or a single string."
      )
    )
  }

  private static func scope(
    from rawValue: String?,
    codingPath: [CodingKey]
  ) throws -> AssumptionRecord.Scope? {
    guard let rawValue, !rawValue.isEmpty else { return nil }
    if let scope = AssumptionRecord.Scope.allCases.first(where: {
      $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame
    }) {
      return scope
    }
    let supported = AssumptionRecord.Scope.allCases.map(\.rawValue).joined(separator: ", ")
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "`scope` must be one of: \(supported)."
      )
    )
  }
}
