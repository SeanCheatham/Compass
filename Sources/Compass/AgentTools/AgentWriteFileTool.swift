import Foundation

/// Create or overwrite a UTF-8 text file. Intermediate directories are
/// created automatically. The model uses this for net-new files; in-place
/// edits should go through `AgentEditFileTool`, which preserves the rest of
/// the file and forces a contextual `oldString` match.
struct AgentWriteFileTool: AgentTool {
  static let toolName = "write_file"

  struct Arguments: Codable {
    let path: String
    let content: String
  }

  let spec: AgentToolSpec

  init() {
    let schema = try! AgentToolParametersSchema([
      "type": "object",
      "additionalProperties": false,
      "required": ["path", "content"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "Destination path. May be absolute (must resolve inside the working directory) or relative to it. Intermediate directories are created automatically.",
        ],
        "content": [
          "type": "string",
          "description": "UTF-8 contents to write. Existing files are overwritten.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Create or overwrite a UTF-8 text file at the given path. Intermediate directories are created. Use `edit_file` for in-place edits.",
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

    let url: URL
    do {
      url = try context.resolvePath(args.path)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    let existing: FileMetadata?
    do {
      existing = try await context.filesystem.metadata(of: url)
    } catch let error as AgentFilesystemError {
      return .failure(.ioFailure(error.errorDescription ?? "stat failed"))
    } catch {
      return .failure(.ioFailure("stat failed: \(error.localizedDescription)"))
    }
    if let existing, existing.isRegularFile,
      await !context.readTracker.wasRead(url)
    {
      return .failure(
        .readNotTracked(
          "write_file would overwrite \(context.relativize(url)) but it has not been read in this session. Call read_file first to confirm its current contents before replacing them."
        ))
    }

    let data = Data(args.content.utf8)
    do {
      try await context.filesystem.writeFile(data, at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notRegularFile:
        return .failure(.notRegularFile(args.path))
      case .transportFailure(let detail):
        return .failure(.rpcFailure(detail))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "I/O failure"))
      }
    } catch {
      return .failure(.ioFailure("write failed: \(error.localizedDescription)"))
    }

    await context.readTracker.markRead(url)
    let relative = context.relativize(url)
    return .ok("wrote \(data.count) bytes to \(relative)")
  }
}
