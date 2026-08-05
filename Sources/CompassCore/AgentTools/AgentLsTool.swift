import Foundation

/// List directory entries (one per line). Directories carry a trailing `/`
/// so the model can tell apart entries without a second call.
public struct AgentLsTool: AgentTool {
  public static let toolName = "ls"
  public static let maxEntries = 1_000

  public struct Arguments: Decodable {
    public let path: String?

    public enum CodingKeys: String, CodingKey {
      case path
      case directory
      case dir
      case root
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
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
      "properties": [
        "path": [
          "type": "string",
          "description": "Directory to list. Defaults to the working directory.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "List one directory's immediate entries (names only, directories marked with `/`). Use for browsing a known folder. Prefer `glob` to find files by pattern across the tree, and `list_files` for the codemap source inventory with language tags.",
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
    if let path = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
      do {
        url = try context.resolvePath(path)
      } catch let error as AgentToolError {
        return .failure(error)
      } catch {
        return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
      }
    } else {
      url = context.workingDirectory
    }

    let entries: [DirectoryEntry]
    do {
      entries = try await context.filesystem.listDirectory(at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notFound:
        return .failure(.fileNotFound(args.path ?? "."))
      case .notDirectory:
        return .failure(.notDirectory(args.path ?? "."))
      default:
        return .failure(.ioFailure(error.localizedDescription))
      }
    } catch {
      return .failure(.ioFailure("list failed: \(error.localizedDescription)"))
    }

    let sorted = entries.sorted { $0.name < $1.name }
    let limited = Array(sorted.prefix(Self.maxEntries))

    let lines = limited.map { entry in
      entry.isDirectory ? entry.name + "/" : entry.name
    }

    var output = lines.joined(separator: "\n")
    if sorted.count > Self.maxEntries {
      output += "\n... \(sorted.count - Self.maxEntries) more entries"
    }
    if output.isEmpty {
      output = "(empty directory)"
    }
    return .ok(output)
  }
}
