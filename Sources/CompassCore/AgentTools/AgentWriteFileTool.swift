import Foundation

/// Create or overwrite a UTF-8 text file. Intermediate directories are
/// created automatically. The model uses this for net-new files; in-place
/// edits should go through `AgentEditFileTool`, which preserves the rest of
/// the file and forces a contextual `oldString` match.
struct AgentWriteFileTool: AgentTool {
  static let toolName = "write_file"

  struct Arguments: Decodable {
    let path: String
    let content: String

    enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case content
      case contents
      case text
      case body
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file],
        fieldName: "path"
      )
      content = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .content,
        aliases: [.contents, .text, .body],
        fieldName: "content"
      )
    }
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
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
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
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
    if existing == nil,
      let conflict = await packageEntryPointConflict(forNewURL: url, context: context)
    {
      return .failure(
        .invalidArguments(
          "write_file refused to create \(context.relativize(url)) because \(conflict.manifestPath) \(conflict.field) already points at existing entry point \(conflict.declaredPath). Edit \(conflict.declaredPath) instead, or update the manifest to point at \(context.relativize(url)) before creating a replacement entry point."
        ))
    }
    let newFileSiblingHint: String?
    if existing == nil {
      newFileSiblingHint = await newFileHint(for: url, context: context)
    } else {
      newFileSiblingHint = nil
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
    var message = "wrote \(data.count) bytes to \(relative)"
    if let newFileSiblingHint {
      message += "\n\(newFileSiblingHint)"
    }
    return .ok(message)
  }

  private struct PackageEntryPointConflict {
    let manifestPath: String
    let declaredPath: String
    let field: String
  }

  private func packageEntryPointConflict(forNewURL url: URL, context: AgentToolContext) async
    -> PackageEntryPointConflict?
  {
    guard isEntryPointAlias(url) else { return nil }
    let workingDirectory = context.workingDirectory.standardizedFileURL
    let workingPath = workingDirectory.path
    var candidate = url.deletingLastPathComponent().standardizedFileURL

    while candidate.path.hasPrefix(workingPath) {
      let manifestURL = candidate.appending(path: "package.json")
      if let data = try? await context.filesystem.readFile(at: manifestURL),
        let entryPoints = packageEntryPoints(from: data)
      {
        for entryPoint in entryPoints {
          let entryURL = candidate.appending(path: entryPoint.path).standardizedFileURL
          guard entryURL.path != url.standardizedFileURL.path,
            let metadata = try? await context.filesystem.metadata(of: entryURL),
            metadata.isRegularFile
          else {
            continue
          }
          return PackageEntryPointConflict(
            manifestPath: context.relativize(manifestURL),
            declaredPath: context.relativize(entryURL),
            field: entryPoint.field
          )
        }
      }

      let parent = candidate.deletingLastPathComponent().standardizedFileURL
      if parent.path == candidate.path { break }
      candidate = parent
    }
    return nil
  }

  private func isEntryPointAlias(_ url: URL) -> Bool {
    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
    return ["app", "cli", "index", "main", "server"].contains(stem)
  }

  private func packageEntryPoints(from data: Data) -> [(field: String, path: String)]? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    var entryPoints: [(field: String, path: String)] = []
    for field in ["main", "module", "browser", "types", "typings"] {
      if let raw = object[field] as? String,
        let normalized = normalizedPackageEntryPoint(raw)
      {
        entryPoints.append((field, normalized))
      }
    }
    if let raw = object["bin"] as? String,
      let normalized = normalizedPackageEntryPoint(raw)
    {
      entryPoints.append(("bin", normalized))
    } else if let bin = object["bin"] as? [String: Any] {
      for key in bin.keys.sorted() {
        if let raw = bin[key] as? String,
          let normalized = normalizedPackageEntryPoint(raw)
        {
          entryPoints.append(("bin.\(key)", normalized))
        }
      }
    }
    return entryPoints
  }

  private func normalizedPackageEntryPoint(_ raw: String) -> String? {
    var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, !path.hasPrefix("#"), !path.contains("://") else { return nil }
    while path.hasPrefix("./") {
      path.removeFirst(2)
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !path.isEmpty, !path.hasPrefix("../") else { return nil }
    return path
  }

  private func newFileHint(for url: URL, context: AgentToolContext) async -> String? {
    let parent = url.deletingLastPathComponent().standardizedFileURL
    guard let entries = try? await context.filesystem.listDirectory(at: parent) else {
      return nil
    }
    let targetName = url.lastPathComponent
    let visibleEntries =
      entries
      .map { entry in entry.isDirectory ? "\(entry.name)/" : entry.name }
      .filter { !$0.hasPrefix(".") && $0 != targetName }
      .sorted()
    guard !visibleEntries.isEmpty else { return nil }

    var message =
      "Created a new file in existing directory \(context.relativize(parent)). Existing entries there before this write:"
    message += visibleEntries.prefix(12).map { "\n- \($0)" }.joined()
    if visibleEntries.count > 12 {
      message += "\n- ... \(visibleEntries.count - 12) more"
    }
    message +=
      "\nIf the plan was to update one of those files, stop using \(context.relativize(url)) and use read_file/edit_file on the existing path instead."
    return message
  }
}
