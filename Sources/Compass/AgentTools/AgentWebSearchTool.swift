import Foundation

struct AgentWebSearchTool: AgentTool {
  static let toolName = "web_search"

  struct Arguments: Decodable {
    let query: String

    enum CodingKeys: String, CodingKey {
      case query
      case q
      case searchQuery = "searchQuery"
      case searchQuerySnake = "search_query"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      query = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .query,
        aliases: [.q, .searchQuery, .searchQuerySnake],
        fieldName: "query"
      )
    }
  }

  let spec: AgentToolSpec
  let assignment: CapabilityAssignment
  let searcher: AgentWebSearcher

  init(
    assignment: CapabilityAssignment,
    searcher: AgentWebSearcher = DefaultAgentWebSearcher()
  ) {
    self.assignment = assignment
    self.searcher = searcher
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["query"],
      "properties": [
        "query": [
          "type": "string",
          "description":
            "Search query for current or external web information. Prefer concise 3-8 word queries and include dates for time-sensitive topics.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Search the web using the configured Web Search provider (\(assignment.provider.displayName)) and return structured search results with links and snippets.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return .failure(.invalidArguments("query is empty"))
    }
    guard !assignment.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.invalidArguments("Web Search provider API key is missing"))
    }

    do {
      let result = try await searcher.search(query: query, assignment: assignment)
      return .ok(result)
    } catch let error as AgentExternalServiceError {
      return .failure(.ioFailure(error.errorDescription ?? "web search failed"))
    } catch {
      return .failure(.ioFailure("web search failed: \(error.localizedDescription)"))
    }
  }
}
