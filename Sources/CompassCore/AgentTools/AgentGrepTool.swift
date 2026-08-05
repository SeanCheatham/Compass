import Foundation

/// Search files for a regex pattern. Delegates the actual exec to
/// `AgentFilesystem.grep` (host-side rg / BSD grep). The model does not
/// get a generic shell through this tool — only this narrow filter.
public struct AgentGrepTool: AgentTool {
  public static let toolName = "grep"
  public static let maxBytes = 50_000
  public static let timeoutSeconds: TimeInterval = 30

  public struct Arguments: Decodable {
    public let pattern: String
    public let path: String?
    public let glob: String?
    public let caseInsensitive: Bool?

    public enum CodingKeys: String, CodingKey {
      case pattern
      case query
      case regex
      case search
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case directory
      case dir
      case root
      case glob
      case fileGlob
      case fileGlobSnake = "file_glob"
      case caseInsensitive
      case caseInsensitiveSnake = "case_insensitive"
      case ignoreCase
      case ignoreCaseSnake = "ignore_case"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      pattern = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .pattern,
        aliases: [.query, .regex, .search],
        fieldName: "pattern"
      )
      path = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file, .directory, .dir, .root]
      )
      glob = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .glob,
        aliases: [.fileGlob, .fileGlobSnake]
      )
      caseInsensitive =
        FlexibleModelDecoder.decodeBool(from: container, forKey: .caseInsensitive)
        ?? FlexibleModelDecoder.decodeBool(from: container, forKey: .caseInsensitiveSnake)
        ?? FlexibleModelDecoder.decodeBool(from: container, forKey: .ignoreCase)
        ?? FlexibleModelDecoder.decodeBool(from: container, forKey: .ignoreCaseSnake)
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
          "description": "Regex pattern to search for (extended POSIX regex syntax).",
        ],
        "path": [
          "type": "string",
          "description": "File or directory to search. Defaults to the working directory.",
        ],
        "glob": [
          "type": "string",
          "description": "Optional glob restricting which files are searched (e.g. `*.swift`).",
        ],
        "caseInsensitive": [
          "type": "boolean",
          "description": "Set to true for a case-insensitive match. Defaults to false.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Search files under the working directory for a regex pattern. Uses ripgrep when installed, otherwise BSD grep. Output is capped at 50KB.",
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
    let pattern = args.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pattern.isEmpty else {
      return .failure(.invalidArguments("pattern is empty"))
    }

    let searchURL: URL
    if let path = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
      do {
        searchURL = try context.resolvePath(path)
      } catch let error as AgentToolError {
        return .failure(error)
      } catch {
        return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
      }
    } else {
      searchURL = context.workingDirectory
    }

    let result: ProcessResult
    do {
      result = try await context.filesystem.grep(
        pattern: pattern,
        in: searchURL,
        glob: args.glob?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        caseInsensitive: args.caseInsensitive ?? false,
        timeout: Self.timeoutSeconds
      )
    } catch let error as AgentFilesystemError {
      switch error {
      case .transportFailure:
        return .failure(.rpcFailure(error.localizedDescription))
      default: return .failure(.ioFailure(error.localizedDescription))
      }
    } catch {
      return .failure(.ioFailure("grep launch failed: \(error.localizedDescription)"))
    }

    // Both rg and grep exit 1 to mean "no matches".
    if result.exitCode == 1 && result.stdout.isEmpty {
      return .ok("(no matches)")
    }
    if result.exitCode != 0 && result.exitCode != 1 {
      let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return .failure(.ioFailure("grep exited \(result.exitCode): \(stderr)"))
    }

    var body = result.stdout
    body = stripPrefix(body, prefix: context.workingDirectory.path + "/")
    if body.utf8.count > Self.maxBytes {
      let truncated = Data(body.utf8.prefix(Self.maxBytes))
      body =
        String(decoding: truncated, as: UTF8.self)
        + "\n... [truncated at \(Self.maxBytes) bytes]"
    }
    return .ok(body.isEmpty ? "(no matches)" : body)
  }

  private func stripPrefix(_ text: String, prefix: String) -> String {
    guard !prefix.isEmpty else { return text }
    return
      text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { line -> String in
        line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : String(line)
      }
      .joined(separator: "\n")
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
