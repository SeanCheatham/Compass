import Foundation

/// Find files under the working directory whose path matches a glob.
/// Supports `**` (any number of path components), `*` (any chars within a
/// component), and `?` (single char within a component). Results are
/// returned newest-first by modification time.
struct AgentGlobTool: AgentTool {
  static let toolName = "glob"
  static let maxResults = 200
  static let walkCap = 10_000

  struct Arguments: Codable {
    let pattern: String
    let path: String?
  }

  let spec: AgentToolSpec

  init() {
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
        "Find files matching a glob pattern. Results are sorted newest-first by modification time and capped at 200 matches.",
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
    let pattern = args.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pattern.isEmpty else {
      return .failure(.invalidArguments("pattern is empty"))
    }

    let root: URL
    if let raw = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      do {
        root = try context.resolvePath(raw)
      } catch let error as AgentToolError {
        return .failure(error.errorDescription ?? "path resolution failed")
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
        return .failure(
          AgentToolError.notDirectory(args.path ?? ".").errorDescription ?? "not a directory")
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
