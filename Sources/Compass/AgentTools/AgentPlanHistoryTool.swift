import Foundation

/// Read-only access to Compass-managed completed plan history. The history
/// lives in host-side state and is injected into the tool context — agents
/// cannot mutate it through submit_result.
struct AgentPlanHistoryTool: AgentTool {
  static let toolName = "plan_history"

  struct Arguments: Codable {
    let offset: Int?
    let limit: Int?
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "offset": [
          "type": "integer",
          "minimum": 0,
          "description":
            "Entries to skip from the newest completed iteration. Default 0 returns the most recent page.",
        ],
        "limit": [
          "type": "integer",
          "minimum": 1,
          "maximum": PlanHistoryPage.maxLimit,
          "description":
            "Maximum entries to return. Default \(PlanHistoryPage.defaultLimit), max \(PlanHistoryPage.maxLimit).",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Read paginated completed plan history managed by Compass. Returns newest entries first with one-based iteration numbers. Use when prior shipped work would inform the next increment.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
    }

    let page = PlanHistoryPage.read(
      entries: context.planHistoryEntries,
      offset: args.offset ?? 0,
      limit: args.limit ?? PlanHistoryPage.defaultLimit
    )
    return .ok(page.formatted())
  }
}
