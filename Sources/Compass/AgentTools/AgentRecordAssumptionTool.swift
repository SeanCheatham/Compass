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
    case claim
    case statement
    case rationale
    case reason
    case why
    case justification
    case evidence
    case observations
    case sources
    case support
    case supportingFacts
    case supportingFactsSnake = "supporting_facts"
    case impact
    case effect
    case consequence
    case whyItMatters
    case whyItMattersSnake = "why_it_matters"
    case dependsOn
    case dependsOnSnake = "depends_on"
    case invalidation
    case invalidates
    case invalidationCondition
    case invalidationConditionSnake = "invalidation_condition"
    case counterEvidence
    case counterEvidenceSnake = "counter_evidence"
    case falsifier
    case scope
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let text = try Self.firstString(
      in: container,
      keys: [.text, .assumption, .claim, .statement],
      fieldName: "text"
    )
    let rawScope = try Self.optionalString(in: container, keys: [.scope])
    let scope = try Self.scope(
      from: rawScope,
      codingPath: container.codingPath + [CodingKeys.scope]
    )
    draft = AssumptionDraft(
      text: text,
      rationale: try Self.optionalString(
        in: container,
        keys: [.rationale, .reason, .why, .justification]
      ),
      evidence: try Self.optionalEvidence(in: container),
      impact: try Self.optionalString(
        in: container,
        keys: [
          .impact, .effect, .consequence, .whyItMatters, .whyItMattersSnake, .dependsOn,
          .dependsOnSnake,
        ]
      ),
      invalidation: try Self.optionalString(
        in: container,
        keys: [
          .invalidation, .invalidates, .invalidationCondition, .invalidationConditionSnake,
          .counterEvidence, .counterEvidenceSnake, .falsifier,
        ]
      ),
      scope: scope
    )
  }

  private static func firstString(
    in container: KeyedDecodingContainer<CodingKeys>,
    keys: [CodingKeys],
    fieldName: String
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
          "record_assumption requires a non-empty `\(fieldName)` string. `assumption`, `claim`, and `statement` are also accepted as compatibility aliases."
      )
    )
  }

  private static func optionalString(
    in container: KeyedDecodingContainer<CodingKeys>,
    keys: [CodingKeys]
  ) throws -> String? {
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
    return nil
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
    for key in [
      CodingKeys.evidence,
      .observations,
      .sources,
      .support,
      .supportingFacts,
      .supportingFactsSnake,
    ] where container.contains(key) {
      if try container.decodeNil(forKey: key) {
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
          debugDescription:
            "`\(key.stringValue)` must be an array of strings or a single string."
        )
      )
    }
    return nil
  }

  private static func normalizedScope(_ rawValue: String) -> AssumptionRecord.Scope? {
    switch FlexibleModelDecoder.normalizedIdentifier(rawValue) {
    case "project", "repo", "repository", "codebase", "workspace", "project_wide",
      "projectwide":
      return .project
    case "feature", "feature_area", "featurearea", "slice", "workstream", "current_feature":
      return .feature
    case "session", "run", "current_run", "currentrun", "this_session", "thissession":
      return .session
    default:
      return nil
    }
  }

  private static func scope(
    from rawValue: String?,
    codingPath: [CodingKey]
  ) throws -> AssumptionRecord.Scope? {
    guard let rawValue, !rawValue.isEmpty else { return nil }
    if let scope = normalizedScope(rawValue) {
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
