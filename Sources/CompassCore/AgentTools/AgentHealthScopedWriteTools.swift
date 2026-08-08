import Foundation

/// Gates `write_file` / `edit_file` behind `HealthWritePolicy` for a health focus.
public struct AgentHealthScopedWriteFileTool: AgentTool {
  public static let toolName = AgentWriteFileTool.toolName

  private let focus: HealthFocus
  private let inner = AgentWriteFileTool()

  public var spec: AgentToolSpec { inner.spec }

  public init(focus: HealthFocus) {
    self.focus = focus
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    if let refusal = try refuseIfNeeded(arguments: arguments, context: context, pathKeys: ["path", "filePath", "file_path", "file"]) {
      return refusal
    }
    return try await inner.invoke(arguments: arguments, context: context)
  }

  private func refuseIfNeeded(
    arguments: Data,
    context: AgentToolContext,
    pathKeys: [String]
  ) throws -> AgentToolInvocationResult? {
    guard let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any] else {
      return nil
    }
    var rawPath: String?
    for key in pathKeys {
      if let value = object[key] as? String, !value.isEmpty {
        rawPath = value
        break
      }
    }
    guard let rawPath else { return nil }
    let url = try context.resolvePath(rawPath)
    let relative = relativePath(of: url, under: context.workingDirectory)
    guard HealthWritePolicy.allows(relativePath: relative, focus: focus) else {
      return .failure(
        .invalidArguments(HealthWritePolicy.rejectionMessage(relativePath: relative, focus: focus))
      )
    }
    return nil
  }

  private func relativePath(of url: URL, under root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path == rootPath { return "" }
    if path.hasPrefix(rootPath + "/") {
      return String(path.dropFirst(rootPath.count + 1))
    }
    return url.lastPathComponent
  }
}

public struct AgentHealthScopedEditFileTool: AgentTool {
  public static let toolName = "edit_file"

  private let focus: HealthFocus
  private let inner: any AgentTool

  public var spec: AgentToolSpec { inner.spec }

  public init(focus: HealthFocus, promptMode: AgentPromptMode) {
    self.focus = focus
    self.inner =
      promptMode == .nativeTools
      ? AgentEditFileTextTool()
      : AgentEditFileTool()
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    if let refusal = try refuseIfNeeded(arguments: arguments, context: context) {
      return refusal
    }
    return try await inner.invoke(arguments: arguments, context: context)
  }

  private func refuseIfNeeded(
    arguments: Data,
    context: AgentToolContext
  ) throws -> AgentToolInvocationResult? {
    guard let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any] else {
      return nil
    }
    var rawPath: String?
    for key in ["path", "filePath", "file_path", "file"] {
      if let value = object[key] as? String, !value.isEmpty {
        rawPath = value
        break
      }
    }
    guard let rawPath else { return nil }
    let url = try context.resolvePath(rawPath)
    let relative = relativePath(of: url, under: context.workingDirectory)
    guard HealthWritePolicy.allows(relativePath: relative, focus: focus) else {
      return .failure(
        .invalidArguments(HealthWritePolicy.rejectionMessage(relativePath: relative, focus: focus))
      )
    }
    return nil
  }

  private func relativePath(of url: URL, under root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path == rootPath { return "" }
    if path.hasPrefix(rootPath + "/") {
      return String(path.dropFirst(rootPath.count + 1))
    }
    return url.lastPathComponent
  }
}
