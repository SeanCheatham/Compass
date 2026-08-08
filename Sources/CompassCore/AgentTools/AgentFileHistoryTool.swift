import Foundation

/// Recent revisions that touched a path in the host workspace history.
public struct AgentFileHistoryTool: AgentTool {
  public static let toolName = "file_history"

  public struct Arguments: Decodable {
    public let path: String
    public let limit: Int?

    public enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case limit
      case count
      case max
      case maxResults
      case maxResultsSnake = "max_results"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file],
        fieldName: "path"
      )
      limit = try FlexibleModelDecoder.decodeIntIfPresent(
        from: container,
        preferredKey: .limit,
        aliases: [.count, .max, .maxResults, .maxResultsSnake]
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["path"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "File path relative to the workspace (or under /workspace when using the VM path space).",
        ],
        "limit": [
          "type": "integer",
          "minimum": 1,
          "maximum": RepoHistoryProvider.maxHistoryLimit,
          "description":
            "Maximum revisions to return. Default \(RepoHistoryProvider.defaultHistoryLimit), max \(RepoHistoryProvider.maxHistoryLimit).",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Read recent version-history revisions that touched a file in this workspace (host-side). Use for provenance and change context. Guest bash has no VCS metadata — prefer this tool over git in the VM.",
      parameters: schema
    )
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let url: URL
    do {
      url = try context.resolvePath(args.path)
    } catch let error as AgentToolError {
      return .failure(error)
    }

    let relative = context.relativize(url)
    let display = context.displayPath(for: url)
    do {
      let revisions = try await RepoHistoryProvider.fileHistory(
        repoRoot: context.workingDirectory,
        relativePath: relative,
        limit: args.limit ?? RepoHistoryProvider.defaultHistoryLimit
      )
      return .ok(
        context.sanitizeHostPaths(
          in: RepoHistoryProvider.formatHistory(revisions, displayPath: display)
        )
      )
    } catch let error as RepoHistoryError {
      return .ok(error.localizedDescription)
    } catch {
      return .failure(.ioFailure(error.localizedDescription))
    }
  }
}
