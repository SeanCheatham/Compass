import Foundation

/// Per-line authorship annotations for a file in the host workspace history.
public struct AgentAnnotateTool: AgentTool {
  public static let toolName = "annotate"

  public struct Arguments: Decodable {
    public let path: String
    public let startLine: Int?
    public let endLine: Int?

    public enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case startLine
      case startLineSnake = "start_line"
      case start
      case endLine
      case endLineSnake = "end_line"
      case end
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file],
        fieldName: "path"
      )
      startLine = try FlexibleModelDecoder.decodeIntIfPresent(
        from: container,
        preferredKey: .startLine,
        aliases: [.startLineSnake, .start]
      )
      endLine = try FlexibleModelDecoder.decodeIntIfPresent(
        from: container,
        preferredKey: .endLine,
        aliases: [.endLineSnake, .end]
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
        "startLine": [
          "type": "integer",
          "minimum": 1,
          "description": "First line to annotate (1-based). Defaults to 1.",
        ],
        "endLine": [
          "type": "integer",
          "minimum": 1,
          "description":
            "Last line to annotate (inclusive). Defaults to a bounded window from startLine.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Annotate lines of a file with revision id, date, author, and subject from host version history. Prefer over guest bash for provenance; the VM worktree has no VCS metadata.",
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

    if let start = args.startLine, let end = args.endLine, end < start {
      return .failure(.invalidArguments("endLine must be >= startLine"))
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
      let rows = try await RepoHistoryProvider.annotate(
        repoRoot: context.workingDirectory,
        relativePath: relative,
        startLine: args.startLine,
        endLine: args.endLine
      )
      return .ok(
        context.sanitizeHostPaths(
          in: RepoHistoryProvider.formatAnnotations(rows, displayPath: display)
        )
      )
    } catch let error as RepoHistoryError {
      return .ok(error.localizedDescription)
    } catch {
      return .failure(.ioFailure(error.localizedDescription))
    }
  }
}
