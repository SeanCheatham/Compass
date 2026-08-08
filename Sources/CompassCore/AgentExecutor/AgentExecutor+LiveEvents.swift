import Foundation

/// Decodes the string-replacement `edit_file` shape used by
/// `AgentEditFileTextTool` (whose own Arguments type is private).
struct StringReplaceEditArguments: Decodable {
  struct Edit: Decodable {
    let oldString: String
    let newString: String
    let replaceAll: Bool?

    enum CodingKeys: String, CodingKey {
      case oldString = "old_string"
      case oldStringCamel = "oldString"
      case newString = "new_string"
      case newStringCamel = "newString"
      case replaceAll = "replace_all"
      case replaceAllCamel = "replaceAll"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      oldString = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .oldString,
        aliases: [.oldStringCamel],
        fieldName: "old_string"
      )
      newString = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .newString,
        aliases: [.newStringCamel],
        fieldName: "new_string"
      )
      replaceAll =
        (try? container.decodeIfPresent(Bool.self, forKey: .replaceAll))
        ?? (try? container.decodeIfPresent(Bool.self, forKey: .replaceAllCamel))
        ?? nil
    }
  }

  let path: String
  let edits: [Edit]

  enum CodingKeys: String, CodingKey {
    case path
    case filePath
    case filePathSnake = "file_path"
    case file
    case edits
    case changes
    case operations
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .path,
      aliases: [.filePath, .filePathSnake, .file],
      fieldName: "path"
    )
    for key in [CodingKeys.edits, .changes, .operations] where container.contains(key) {
      if let edits = try? container.decode([Edit].self, forKey: key) {
        self.edits = edits
        return
      }
    }
    edits = try container.decode([Edit].self, forKey: .edits)
  }
}

extension AgentExecutor {
  // MARK: - LiveEvent mapping

  public func emit(
    level: LiveLine.Level = .info,
    text: String,
    detail: String? = nil,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none,
    correlationID: String? = nil,
    metadata: [String: String]? = nil,
    payload: LiveToolPayload? = nil
  ) {
    onEvent(
      LiveEvent(
        level: level, text: text, detail: detail, kind: kind, status: status,
        correlationID: correlationID, metadata: metadata, payload: payload))
  }

  public func emitToolStart(name: String, arguments: String, correlationID: String) {
    let kind = liveKind(forTool: name)
    let level: LiveLine.Level = kind == .command ? .raw : .info
    let detail = previewString(arguments)
    let descriptor = toolDescriptor(name: name, arguments: arguments)
    emit(
      level: level, text: toolTitle(name: name, arguments: arguments), detail: detail,
      kind: kind,
      status: .running, correlationID: correlationID,
      metadata: toolMetadata(
        name: name,
        descriptor: descriptor,
        argumentsPreview: detail,
        isError: nil
      ),
      payload: toolPayload(name: name, arguments: arguments, result: nil)
    )
  }

  public func emitToolEnd(
    name: String, arguments: String, result: AgentToolInvocationResult, correlationID: String
  ) {
    let kind = liveKind(forTool: name)
    let status: LiveLine.Status = result.isError ? .failed : .completed
    let level: LiveLine.Level = result.isError ? .error : (kind == .command ? .success : .info)
    let descriptor = toolDescriptor(name: name, arguments: arguments)
    emit(
      level: level, text: toolTitle(name: name, arguments: arguments),
      detail: previewString(result.content), kind: kind, status: status,
      correlationID: correlationID,
      metadata: toolMetadata(
        name: name,
        descriptor: descriptor,
        argumentsPreview: previewString(arguments),
        isError: result.isError
      ),
      payload: toolPayload(name: name, arguments: arguments, result: result)
    )
  }

  private func toolMetadata(
    name: String,
    descriptor: String?,
    argumentsPreview: String,
    isError: Bool?
  ) -> [String: String] {
    var metadata = [
      "tool": name,
      "argumentsPreview": argumentsPreview,
    ]
    if let descriptor {
      metadata["descriptor"] = descriptor
    }
    if let isError {
      metadata["isError"] = isError ? "true" : "false"
    }
    return metadata
  }

  private func liveKind(forTool name: String) -> LiveLine.Kind {
    switch name {
    case AgentBashTool.toolName: return .command
    case AgentWriteFileTool.toolName, AgentEditFileTool.toolName: return .fileChange
    default: return .lifecycle
    }
  }

  /// Build a one-line title that names the tool *and* the most relevant argument
  /// (bash command, file path, search pattern, ...) so the live log reads as
  /// "what is the agent doing" instead of just "which tool was called".
  private func toolTitle(name: String, arguments: String) -> String {
    if let descriptor = toolDescriptor(name: name, arguments: arguments) {
      return "\(name) · \(descriptor)"
    }
    return "Tool \(name)"
  }

  private func toolDescriptor(name: String, arguments: String) -> String? {
    guard let data = arguments.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    func string(_ keys: String...) -> String? {
      for key in keys {
        guard let raw = json[key] as? String else { continue }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
        }
      }
      return nil
    }

    switch name {
    case AgentBashTool.toolName:
      return string("command", "cmd", "shellCommand", "shell_command", "script").map {
        truncateOneLine($0, limit: 100)
      }
    case AgentReadFileTool.toolName,
      AgentWriteFileTool.toolName,
      AgentEditFileTool.toolName:
      return string("path", "filePath", "file_path", "file")
    case AgentLsTool.toolName:
      return string("path", "directory", "dir", "root") ?? "."
    case AgentGrepTool.toolName:
      guard let pattern = string("pattern", "query", "regex", "search") else {
        return nil
      }
      if let path = string("path", "filePath", "file_path", "file", "directory", "dir", "root") {
        return "\(pattern) in \(path)"
      }
      return pattern
    case AgentGlobTool.toolName:
      guard let pattern = string("pattern", "glob", "query") else { return nil }
      if let path = string("path", "directory", "dir", "root") {
        return "\(pattern) in \(path)"
      }
      return pattern
    case AgentOutlineTool.toolName,
      AgentSummaryTool.toolName,
      AgentImportersOfTool.toolName:
      return string("path", "filePath", "file_path", "file", "relativePath", "relative_path")
    case AgentFindSymbolTool.toolName:
      guard let name = string("name", "symbol", "symbolName", "symbol_name", "query") else {
        return nil
      }
      if let kind = string("kind", "symbolKind", "symbol_kind", "type") {
        return "\(name) (\(kind))"
      }
      return name
    case AgentListFilesTool.toolName:
      return string("filter", "query", "search", "path", "directory", "dir") ?? "(all)"
    case AgentDelegateTool.toolName:
      return string("task", "prompt", "instructions", "instruction", "question", "subtask").map {
        truncateOneLine($0, limit: 100)
      }
    case AgentPlanHistoryTool.toolName:
      if let offset = string("offset", "start", "skip") {
        return "offset \(offset)"
      }
      return "latest"
    default:
      return nil
    }
  }

  private func truncateOneLine(_ s: String, limit: Int) -> String {
    let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
    if firstLine.count <= limit { return firstLine }
    return String(firstLine.prefix(limit)) + "…"
  }

  public func previewString(_ s: String, limit: Int = 280) -> String {
    let stripped = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if stripped.count <= limit { return stripped }
    return String(stripped.prefix(limit)) + " ..."
  }

  // MARK: - Studio payload capture

  public static let payloadMaxEditorBytes = 200_000
  public static let payloadMaxTerminalBytes = 50_000

  /// Decode a tool call into a structured payload for the Studio view.
  /// `result` is nil on tool start. Returns nil for tools the Studio view
  /// does not render, or when arguments fail to decode.
  public func toolPayload(
    name: String,
    arguments: String,
    result: AgentToolInvocationResult?
  ) -> LiveToolPayload? {
    guard let data = arguments.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    switch name {
    case AgentBashTool.toolName:
      guard let args = try? decoder.decode(AgentBashTool.Arguments.self, from: data) else {
        return nil
      }
      return .bash(
        command: args.command,
        cwd: args.cwd,
        output: result.map { Self.capTail($0.content, bytes: Self.payloadMaxTerminalBytes) },
        isError: result?.isError
      )
    case AgentReadFileTool.toolName:
      guard let args = try? decoder.decode(AgentReadFileTool.Arguments.self, from: data) else {
        return nil
      }
      let content: String?
      if let result, !result.isError {
        content = Self.capHead(result.content, bytes: Self.payloadMaxEditorBytes)
      } else {
        content = nil
      }
      return .readFile(path: args.path, offset: args.offset, limit: args.limit, content: content)
    case AgentWriteFileTool.toolName:
      guard let args = try? decoder.decode(AgentWriteFileTool.Arguments.self, from: data) else {
        return nil
      }
      return .writeFile(
        path: args.path,
        content: Self.capHead(args.content, bytes: Self.payloadMaxEditorBytes)
      )
    case AgentWriteGeneratedTestTool.toolName:
      guard let args = try? decoder.decode(AgentWriteGeneratedTestTool.Arguments.self, from: data)
      else {
        return nil
      }
      let fileName = ChamberPaths.normalizeGeneratedTestFileName(args.path)
      let relative = "\(ChamberPaths.generatedTestsDirectory)/\(fileName)"
      return .writeFile(
        path: relative,
        content: Self.capHead(args.content, bytes: Self.payloadMaxEditorBytes)
      )
    case AgentEditFileTool.toolName:
      if let args = try? decoder.decode(AgentEditFileTool.Arguments.self, from: data) {
        return .editFileLineRange(
          path: args.path,
          edits: args.edits.map {
            LiveLineRangeEdit(
              startLine: $0.startLine,
              endLine: $0.endLine,
              replacementLines: $0.replacementLines.map {
                Self.capHead($0, bytes: Self.payloadMaxEditorBytes)
              }
            )
          }
        )
      }
      if let args = try? decoder.decode(StringReplaceEditArguments.self, from: data) {
        return .editFileStringReplace(
          path: args.path,
          edits: args.edits.map {
            LiveStringReplaceEdit(
              oldString: Self.capHead($0.oldString, bytes: Self.payloadMaxEditorBytes),
              newString: Self.capHead($0.newString, bytes: Self.payloadMaxEditorBytes),
              replaceAll: $0.replaceAll ?? false
            )
          }
        )
      }
      return nil
    default:
      return nil
    }
  }

  public static func capHead(_ s: String, bytes: Int) -> String {
    guard s.utf8.count > bytes else { return s }
    return String(decoding: Data(s.utf8.prefix(bytes)), as: UTF8.self)
      + "\n... [truncated for display]"
  }

  public static func capTail(_ s: String, bytes: Int) -> String {
    guard s.utf8.count > bytes else { return s }
    return "... [truncated for display]\n"
      + String(decoding: Data(s.utf8.suffix(bytes)), as: UTF8.self)
  }
}
