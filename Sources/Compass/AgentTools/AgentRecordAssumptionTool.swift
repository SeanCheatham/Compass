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
      draft = try JSONDecoder().decode(AssumptionDraft.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
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
