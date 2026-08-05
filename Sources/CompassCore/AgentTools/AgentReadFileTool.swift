import Foundation

/// Read a UTF-8 text file from the working directory with optional line
/// offset/limit. Mirrors the line-numbered output the model is used to from
/// other agent Read tools so prompt fragments stay consistent across runtimes.
public struct AgentReadFileTool: AgentTool {
  public static let toolName = "read_file"
  public static let defaultLineCount = 2_000
  public static let maxLineLength = 2_000

  public struct Arguments: Decodable {
    public let path: String
    public let offset: Int?
    public let limit: Int?

    public enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case offset
      case start
      case startLine
      case startLineSnake = "start_line"
      case line
      case limit
      case lineCount
      case lineCountSnake = "line_count"
      case maxLines
      case maxLinesSnake = "max_lines"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file],
        fieldName: "path"
      )
      offset = Self.decodeInt(
        from: container,
        preferredKey: .offset,
        aliases: [.start, .startLine, .startLineSnake, .line]
      )
      limit = Self.decodeInt(
        from: container,
        preferredKey: .limit,
        aliases: [.lineCount, .lineCountSnake, .maxLines, .maxLinesSnake]
      )
    }

    private static func decodeInt(
      from container: KeyedDecodingContainer<CodingKeys>,
      preferredKey: CodingKeys,
      aliases: [CodingKeys]
    ) -> Int? {
      for key in [preferredKey] + aliases {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
          return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
          return Int(value)
        }
        if let rawValue = try? container.decodeIfPresent(String.self, forKey: key) {
          let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
          if let value = Int(trimmed) {
            return value
          }
          if let value = Double(trimmed) {
            return Int(value)
          }
        }
      }
      return nil
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
            "Path to the file to read. May be absolute (must resolve inside the working directory) or relative to it.",
        ],
        "offset": [
          "type": "integer",
          "minimum": 1,
          "description": "1-indexed line to start reading from. Defaults to 1.",
        ],
        "limit": [
          "type": "integer",
          "minimum": 1,
          "description": "Maximum number of lines to return. Defaults to 2000.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Read a UTF-8 text file from the working directory. Returns 1-indexed line-numbered content (`NNNNNN\\tline text`). Use those line numbers with edit_file startLine/endLine. Optional offset and limit narrow the slice. Refuses binary files.",
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

    let url: URL
    do {
      url = try context.resolvePath(args.path)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    let data: Data
    do {
      data = try await context.filesystem.readFile(at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notFound:
        return .failure(
          await missingFileMessage(requestedPath: args.path, resolvedURL: url, context: context),
          kind: .fileNotFound
        )
      case .notRegularFile:
        return .failure(.notRegularFile(args.path))
      case .transportFailure(let detail):
        return .failure(.rpcFailure(detail))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "I/O failure"))
      }
    } catch {
      return .failure(.ioFailure("read failed: \(error.localizedDescription)"))
    }

    let text: String
    switch AgentTextFile.decodeUTF8(data, path: args.path) {
    case .success(let decoded):
      text = decoded
    case .failure(let error):
      return .failure(error)
    }
    let allLines = text.components(separatedBy: "\n")
    let totalLines = allLines.count

    let offset = max(args.offset ?? 1, 1)
    let startIndex = offset - 1
    guard startIndex < totalLines else {
      return .ok("(file has \(totalLines) lines; offset \(offset) is past the end)")
    }

    let limit = max(args.limit ?? Self.defaultLineCount, 1)
    let endIndex = min(totalLines, startIndex + limit)
    let slice = allLines[startIndex..<endIndex]

    let rendered = slice.enumerated().map { idx, line in
      let lineNumber = idx + offset
      let truncatedLine: String
      if line.count > Self.maxLineLength {
        truncatedLine = String(line.prefix(Self.maxLineLength)) + "  ... [line truncated]"
      } else {
        truncatedLine = line
      }
      return String(format: "%6d\t", lineNumber) + truncatedLine
    }.joined(separator: "\n")

    var output = "Lines are 1-indexed. Use these numbers with edit_file startLine/endLine.\n"
    output += rendered
    if endIndex < totalLines {
      output += "\n... \(totalLines - endIndex) more lines"
    }
    output += "\n(total \(totalLines) lines)"
    await context.readTracker.markRead(url, lineCount: totalLines)
    return .ok(output)
  }

  private func missingFileMessage(
    requestedPath: String,
    resolvedURL: URL,
    context: AgentToolContext
  ) async -> String {
    var message = "File not found: \(requestedPath)"
    guard
      let nearest = await context.nearestExistingDirectory(
        from: resolvedURL,
        isUsefulEntry: Self.isUsefulDirectoryEntry
      )
    else {
      return message
        + "\nUse list_files or glob to discover the current repo paths before creating a new file."
    }

    let relativeDirectory = context.relativize(nearest.url)
    message += "\nNearest existing directory: \(relativeDirectory)"
    if !nearest.entries.isEmpty {
      message += "\nExisting entries there:"
      message += AgentToolMessageFormat.directoryEntriesPreview(nearest.entries)
    }
    let sameFilenameMatches = await sameFilenameMatches(for: requestedPath, context: context)
    if !sameFilenameMatches.isEmpty {
      message += "\nSame filename exists at:"
      message += sameFilenameMatches.map { "\n- \($0)" }.joined()
    }
    message +=
      "\nUse read_file with one of these paths or same-filename matches. Use list_files/glob before creating a new file. Use write_file only when the plan truly requires a new file."
    return message
  }

  private func sameFilenameMatches(
    for requestedPath: String,
    context: AgentToolContext,
    limit: Int = 4
  ) async -> [String] {
    let basename = URL(fileURLWithPath: requestedPath).lastPathComponent
    guard !basename.isEmpty else { return [] }
    let matches = (try? await context.filesystem.glob(
      pattern: "**/*",
      under: context.workingDirectory,
      walkCap: 20_000
    )) ?? []
    let usefulMatches = matches
      .map(\.url)
      .filter { $0.lastPathComponent == basename }
      .map(context.relativize)
      .filter { $0 != requestedPath }
      .filter(Self.isUsefulSameFilenameMatch)
      .sorted()

    if let packageRoot = Self.packageRootPrefix(for: requestedPath) {
      return usefulMatches
        .filter { $0.hasPrefix(packageRoot + "/") }
        .prefix(limit)
        .map { $0 }
    }

    return usefulMatches
      .prefix(limit)
      .map { $0 }
  }

  private static func packageRootPrefix(for path: String) -> String? {
    let components = path.split(separator: "/").map(String.init)
    guard components.count >= 2, components[0] == "packages" else { return nil }
    return "packages/\(components[1])"
  }

  private static func isUsefulDirectoryEntry(_ entry: String) -> Bool {
    isUsefulSameFilenameMatch(entry.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }

  private static func isUsefulSameFilenameMatch(_ path: String) -> Bool {
    let skippedComponents: Set<String> = [
      ".build",
      ".compass",
      ".git",
      ".pnpm-store",
      ".turbo",
      "build",
      "coverage",
      "dist",
      "node_modules",
    ]
    return !path.split(separator: "/").contains { skippedComponents.contains(String($0)) }
  }
}
