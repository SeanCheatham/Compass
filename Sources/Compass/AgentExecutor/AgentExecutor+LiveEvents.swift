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
    correlationID: String? = nil
  ) {
    onEvent(
      LiveEvent(
        level: level, text: text, detail: detail, kind: kind, status: status,
        correlationID: correlationID))
  }

  func emitToolStart(name: String, arguments: String, correlationID: String) {
    let kind = liveKind(forTool: name)
    let level: LiveLine.Level = kind == .command ? .raw : .info
    let detail = previewString(arguments)
    emit(
      level: level, text: toolTitle(name: name, arguments: arguments), detail: detail, kind: kind,
      status: .running, correlationID: correlationID)
  }

  func emitToolEnd(
    name: String, arguments: String, result: AgentToolInvocationResult, correlationID: String
  ) {
    let kind = liveKind(forTool: name)
    let status: LiveLine.Status = result.isError ? .failed : .completed
    let level: LiveLine.Level = result.isError ? .error : (kind == .command ? .success : .info)
    emit(
      level: level, text: toolTitle(name: name, arguments: arguments),
      detail: previewString(result.content), kind: kind, status: status,
      correlationID: correlationID)
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

    func string(_ key: String) -> String? {
      guard let raw = json[key] as? String else { return nil }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    switch name {
    case AgentBashTool.toolName:
      return string("command").map { truncateOneLine($0, limit: 100) }
    case AgentReadFileTool.toolName,
      AgentWriteFileTool.toolName,
      AgentEditFileTool.toolName:
      return string("path")
    case AgentLsTool.toolName:
      return string("path") ?? "."
    case AgentGrepTool.toolName, AgentGlobTool.toolName:
      guard let pattern = string("pattern") else { return nil }
      if let path = string("path") {
        return "\(pattern) in \(path)"
      }
      return pattern
    case AgentOutlineTool.toolName,
      AgentSummaryTool.toolName,
      AgentImportersOfTool.toolName:
      return string("path")
    case AgentFindSymbolTool.toolName:
      guard let name = string("name") else { return nil }
      if let kind = string("kind") { return "\(name) (\(kind))" }
      return name
    case AgentListFilesTool.toolName:
      return string("filter") ?? "(all)"
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
