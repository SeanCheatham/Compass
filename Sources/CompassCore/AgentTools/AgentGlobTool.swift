import Foundation

/// Find files under the working directory whose path matches a glob.
/// Supports `**` (any number of path components), `*` (any chars within a
/// component), and `?` (single char within a component). Results are
/// returned newest-first by modification time.
public struct AgentGlobTool: AgentTool {
  public static let toolName = "glob"
  public static let maxResults = 200
  public static let walkCap = 10_000

  public struct Arguments: Decodable {
    public let pattern: String
    public let path: String?

    public enum CodingKeys: String, CodingKey {
      case pattern
      case glob
      case query
      case path
      case directory
      case dir
      case root
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      pattern = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .pattern,
        aliases: [.glob, .query],
        fieldName: "pattern"
      )
      path = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .path,
        aliases: [.directory, .dir, .root]
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["pattern"],
      "properties": [
        "pattern": [
          "type": "string",
          "description":
            "Glob pattern, relative to the search root. Supports `**`, `*`, and `?`. Example: `**/*.swift`.",
        ],
        "path": [
          "type": "string",
          "description":
            "Subdirectory under the working directory to scope the search to. Defaults to the working directory.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Find files by glob pattern under the working directory (or a subdirectory). Use for pattern discovery like `**/*.swift`. Prefer `ls` for a single directory listing, and `list_files` for the codemap source inventory with language tags. Results newest-first, capped at 200.",
      parameters: schema
    )
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    let pattern = args.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pattern.isEmpty else {
      return .failure(.invalidArguments("pattern is empty"))
    }

    let root: URL
    if let raw = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      do {
        root = try context.resolvePath(raw)
      } catch let error as AgentToolError {
        return .failure(error)
      } catch {
        return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
      }
    } else {
      root = context.workingDirectory
    }

    let matches: [GlobMatch]
    do {
      matches = try await context.filesystem.glob(
        pattern: pattern,
        under: root,
        walkCap: Self.walkCap
      )
    } catch let error as AgentFilesystemError {
      switch error {
      case .notDirectory:
        return .failure(.notDirectory(args.path ?? "."))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "glob failed"))
      }
    } catch {
      return .failure(.ioFailure("glob failed: \(error.localizedDescription)"))
    }

    let sorted = matches.sorted { lhs, rhs in
      let lMtime = lhs.modificationDate ?? .distantPast
      let rMtime = rhs.modificationDate ?? .distantPast
      if lMtime == rMtime { return lhs.url.path < rhs.url.path }
      return lMtime > rMtime
    }
    let displayed = sorted.prefix(Self.maxResults).map { context.relativize($0.url) }
    var body = displayed.joined(separator: "\n")
    if sorted.count > Self.maxResults {
      body += "\n... \(sorted.count - Self.maxResults) more matches"
    }
    if body.isEmpty {
      body = "(no matches)"
    }
    return .ok(body)
  }
}
