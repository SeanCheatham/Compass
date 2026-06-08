import Foundation
import OpenAI

extension AgentExecutor {
  // MARK: - LiveEvent mapping

  func emit(
    level: LiveLine.Level = .info,
    text: String,
    detail: String? = nil,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none,
    correlationID: String? = nil,
    metadata: [String: String]? = nil
  ) {
    onEvent(
      LiveEvent(
        level: level, text: text, detail: detail, kind: kind, status: status,
        correlationID: correlationID, metadata: metadata))
  }

  func emitToolStart(name: String, arguments: String, correlationID: String) {
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
      )
    )
  }

  func emitToolEnd(
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
      )
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
    case AgentGenerateImageTool.toolName:
      return string(
        "output_path", "outputPath", "path", "filePath", "file_path", "output", "destination"
      )
        ?? string("prompt", "description", "imagePrompt", "image_prompt").map {
          truncateOneLine($0, limit: 80)
        }
    case AgentDelegateTool.toolName:
      return string("task", "prompt", "instructions", "instruction", "question", "subtask").map {
        truncateOneLine($0, limit: 100)
      }
    case AgentHostXcodeTool.toolName:
      return string("action", "operation", "command")
    case AgentInstallToolchainTool.toolName:
      return string("id", "toolchain", "toolchainID", "toolchain_id", "name")
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

  func previewString(_ s: String, limit: Int = 280) -> String {
    let stripped = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if stripped.count <= limit { return stripped }
    return String(stripped.prefix(limit)) + " ..."
  }
}
