import Foundation

package struct AgentTesseraTool: AgentTool {
  package static let toolName = "tessera"

  private let allowsMutation: Bool
  package let spec: AgentToolSpec

  package init(allowsMutation: Bool = true) {
    self.allowsMutation = allowsMutation
    let actions = allowsMutation ? Self.mutableActions : Self.readOnlyActions
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Run embedded Tessera project operations and edit Tessera project resources without shelling out to the tessera CLI.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": false,
        "required": ["action"],
        "properties": [
          "action": [
            "type": "string",
            "enum": actions,
            "description": "Tessera operation to run.",
          ],
          "root": [
            "type": "string",
            "description": "Project root relative to the working directory. Defaults to '.'.",
          ],
          "entrypoint": [
            "type": "string",
            "description": "Manifest entrypoint name. Required for run_entrypoint.",
          ],
          "path": [
            "type": "string",
            "description": "Tessera resource path. Allowed paths: tessera.json, src/**/*.tes, tests/**/*.json, contexts/**/*.json.",
          ],
          "test_path": [
            "type": "string",
            "description": "Test JSON path for run_test, for example tests/display-name.json.",
          ],
          "input": [
            "description": "Optional JSON object used as an entrypoint or source-check input override.",
          ],
          "content": [
            "type": "string",
            "description": "Complete UTF-8 content for write_resource.",
          ],
          "edits": [
            "description": "Line-range edits for edit_resource, using edit_file-compatible startLine/endLine/replacement lines.",
          ],
          "offset": [
            "type": "integer",
            "minimum": 1,
            "description": "1-indexed line offset for read_resource.",
          ],
          "limit": [
            "type": "integer",
            "minimum": 1,
            "description": "Maximum line count for read_resource.",
          ],
        ],
      ])
    )
  }

  private static let readOnlyActions = [
    "verify",
    "inspect_project",
    "run_entrypoint",
    "run_test",
    "parse_source",
    "check_source",
    "read_resource",
    "list_resources",
  ]

  private static let mutableActions = readOnlyActions + [
    "write_resource",
    "edit_resource",
    "format_source",
  ]

  package func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    let object: [String: Any]
    do {
      guard let decoded = try JSONSerialization.jsonObject(with: arguments) as? [String: Any] else {
        return .failure(.invalidArguments("arguments must be a JSON object"))
      }
      object = decoded
    } catch {
      return .failure(.invalidArguments("invalid JSON arguments: \(error.localizedDescription)"))
    }

    guard let action = object["action"] as? String else {
      return .failure(.invalidArguments("action is required"))
    }
    if Self.mutatingActions.contains(action), !allowsMutation {
      return .failure(
        .invalidArguments(
          "tessera action \(action) is not available in this phase; use read-only Tessera inspection or submit the phase."
        ))
    }
    let root: URL
    do {
      root = try context.resolvePath((object["root"] as? String) ?? ".")
    } catch let error as AgentToolError {
      return .failure(error)
    }
    do {
      guard let metadata = try await context.filesystem.metadata(of: root), metadata.isDirectory else {
        return .failure(.notDirectory(context.relativize(root)))
      }
    } catch let error as AgentFilesystemError {
      return .failure(.ioFailure(error.errorDescription ?? "stat failed"))
    } catch {
      return .failure(.ioFailure("stat failed: \(error.localizedDescription)"))
    }

    switch action {
    case "verify":
      let result = try await CompassEngineProcess.verifyProject(root: root)
      return format(result: result, successNext: verifySuccessGuidance())
    case "inspect_project":
      let result = try await CompassEngineProcess.inspectProject(root: root)
      return format(result: result, successNext: nil)
    case "run_entrypoint":
      guard let entrypoint = object["entrypoint"] as? String,
        !entrypoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("entrypoint is required for run_entrypoint"))
      }
      let input = try inputData(from: object["input"])
      let result = try await CompassEngineProcess.runEntrypoint(
        root: root,
        entrypoint: entrypoint,
        input: input
      )
      return format(result: result, successNext: nil)
    case "run_test":
      guard let testPath = object["test_path"] as? String,
        !testPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("test_path is required for run_test"))
      }
      let result = try await CompassEngineProcess.runTest(root: root, testPath: testPath)
      return format(result: result, successNext: nil)
    case "parse_source":
      guard let path = object["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("path is required for parse_source"))
      }
      let result = try await CompassEngineProcess.parseSource(root: root, path: path)
      return format(result: result, successNext: nil)
    case "check_source":
      guard let path = object["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("path is required for check_source"))
      }
      let input = try inputData(from: object["input"])
      let result = try await CompassEngineProcess.checkSource(root: root, path: path, input: input)
      return format(result: result, successNext: nil)
    case "format_source":
      guard let path = object["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("path is required for format_source"))
      }
      if let issue = validateResourcePath(path, expectedKind: .source) {
        return .failure(.invalidArguments(issue))
      }
      let result = try await CompassEngineProcess.formatSource(root: root, path: path)
      return format(result: result, successNext: nil)
    case "read_resource":
      guard let path = object["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("path is required for read_resource"))
      }
      if let issue = validateResourcePath(path) {
        return .failure(.invalidArguments(issue))
      }
      return try await readResource(object: object, root: root, context: context)
    case "list_resources":
      return try await listResources(root: root, context: context)
    case "write_resource":
      guard let path = object["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("path is required for write_resource"))
      }
      if let issue = validateResourcePath(path) {
        return .failure(.invalidArguments(issue))
      }
      return try await writeResource(object: object, root: root, context: context)
    case "edit_resource":
      guard let path = object["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return .failure(.invalidArguments("path is required for edit_resource"))
      }
      if let issue = validateResourcePath(path) {
        return .failure(.invalidArguments(issue))
      }
      return try await editResource(object: object, root: root, context: context)
    default:
      return .failure(.invalidArguments("unsupported action: \(action)"))
    }
  }

  package static let mutatingActions: Set<String> = [
    "write_resource",
    "edit_resource",
    "format_source",
  ]

  package static func isMutatingAction(arguments: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any],
      let action = object["action"] as? String
    else { return false }
    return mutatingActions.contains(action)
  }

  package static func verifyActionLabel(arguments: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any],
      let action = object["action"] as? String,
      action == "verify"
    else { return nil }
    return "tessera verify"
  }

  private func inputData(from value: Any?) throws -> Data? {
    guard let value else { return nil }
    guard JSONSerialization.isValidJSONObject(value) else {
      throw AgentToolError.invalidArguments("input must be a JSON object or array")
    }
    return try JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
  }

  private func format(result: ProcessResult, successNext: String?) -> AgentToolInvocationResult {
    var sections: [String] = []
    let stdout = result.stdout.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    if !stdout.isEmpty {
      sections.append("[stdout]\n\(stdout)")
    }
    let stderr = result.stderr.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    if !stderr.isEmpty {
      sections.append("[stderr]\n\(stderr)")
    }
    if let note = CompassEngineProcess.resultNote(stdout: stdout) {
      sections.append("[tessera]\n\(note)")
    }
    sections.append("[exit \(result.exitCode)]")
    if result.exitCode == 0, let successNext {
      sections.append(successNext)
    }
    let output = sections.joined(separator: "\n\n")
    guard result.exitCode == 0 else {
      return .failure(output, kind: .tesseraFailure)
    }
    return .ok(output)
  }

  private enum ResourceKind {
    case manifest
    case source
    case test
    case context

    var label: String {
      switch self {
      case .manifest: return "manifest"
      case .source: return "source"
      case .test: return "test"
      case .context: return "context"
      }
    }
  }

  private func validateResourcePath(_ path: String, expectedKind: ResourceKind? = nil) -> String? {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "path is empty" }
    guard !trimmed.hasPrefix("/") else {
      return "Tessera resource paths must be relative to the project root."
    }
    guard !trimmed.contains("\0") else {
      return "Tessera resource paths cannot contain NUL bytes."
    }
    let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      return "Tessera resource paths cannot contain empty, '.', or '..' components."
    }
    let hiddenOrBuildComponents: Set<String> = [".compass", ".git", ".build", "build", "target"]
    guard !components.contains(where: hiddenOrBuildComponents.contains) else {
      return "Tessera resource paths cannot point at Compass, Git, build, or target directories."
    }

    let kind: ResourceKind?
    if trimmed == "tessera.json" {
      kind = .manifest
    } else if trimmed.hasPrefix("src/"), trimmed.hasSuffix(".tes") {
      kind = .source
    } else if trimmed.hasPrefix("tests/"), trimmed.hasSuffix(".json") {
      kind = .test
    } else if trimmed.hasPrefix("contexts/"), trimmed.hasSuffix(".json") {
      kind = .context
    } else {
      kind = nil
    }
    guard let kind else {
      return
        "Unsupported Tessera resource path \(trimmed). Allowed paths are tessera.json, src/**/*.tes, tests/**/*.json, and contexts/**/*.json."
    }
    if let expectedKind, kind != expectedKind {
      return "Expected a Tessera \(expectedKind.label) resource, got \(trimmed)."
    }
    return nil
  }

  private func resourceURL(path: String, root: URL) -> URL {
    root.appending(path: path, directoryHint: .notDirectory).standardizedFileURL
  }

  private func resourcePathRelativeToWorkingDirectory(
    path: String,
    root: URL,
    context: AgentToolContext
  ) -> String {
    context.relativize(resourceURL(path: path, root: root))
  }

  private func readResource(
    object: [String: Any],
    root: URL,
    context: AgentToolContext
  ) async throws -> AgentToolInvocationResult {
    guard let path = object["path"] as? String else {
      return .failure(.invalidArguments("path is required for read_resource"))
    }
    var arguments: [String: Any] = [
      "path": resourcePathRelativeToWorkingDirectory(path: path, root: root, context: context)
    ]
    if let offset = jsonInt(object["offset"]) {
      arguments["offset"] = offset
    }
    if let limit = jsonInt(object["limit"]) {
      arguments["limit"] = limit
    }
    return try await AgentReadFileTool().invoke(
      arguments: try JSONSerialization.data(withJSONObject: arguments, options: [.withoutEscapingSlashes]),
      context: context
    )
  }

  private func listResources(
    root: URL,
    context: AgentToolContext
  ) async throws -> AgentToolInvocationResult {
    var resources: [String] = []
    let manifest = root.appending(path: "tessera.json", directoryHint: .notDirectory)
    if let metadata = try? await context.filesystem.metadata(of: manifest), metadata.isRegularFile {
      resources.append("tessera.json")
    }
    for pattern in ["src/**/*.tes", "tests/**/*.json", "contexts/**/*.json"] {
      let matches = (try? await context.filesystem.glob(pattern: pattern, under: root, walkCap: 20_000)) ?? []
      resources += matches.map { context.relativize($0.url) }
    }
    resources = Array(Set(resources)).sorted()
    guard !resources.isEmpty else {
      return .ok("(no Tessera resources found)")
    }
    return .ok(resources.map { "- \($0)" }.joined(separator: "\n"))
  }

  private func writeResource(
    object: [String: Any],
    root: URL,
    context: AgentToolContext
  ) async throws -> AgentToolInvocationResult {
    guard let path = object["path"] as? String else {
      return .failure(.invalidArguments("path is required for write_resource"))
    }
    guard let content = object["content"] as? String else {
      return .failure(.invalidArguments("content is required for write_resource"))
    }
    let arguments: [String: Any] = [
      "path": resourcePathRelativeToWorkingDirectory(path: path, root: root, context: context),
      "content": content,
    ]
    let result = try await AgentWriteFileTool().invoke(
      arguments: try JSONSerialization.data(withJSONObject: arguments, options: [.withoutEscapingSlashes]),
      context: context
    )
    return rewriteResourceMutationGuidance(result)
  }

  private func editResource(
    object: [String: Any],
    root: URL,
    context: AgentToolContext
  ) async throws -> AgentToolInvocationResult {
    guard let path = object["path"] as? String else {
      return .failure(.invalidArguments("path is required for edit_resource"))
    }
    guard let edits = object["edits"] else {
      return .failure(.invalidArguments("edits is required for edit_resource"))
    }
    let arguments: [String: Any] = [
      "path": resourcePathRelativeToWorkingDirectory(path: path, root: root, context: context),
      "edits": edits,
    ]
    guard JSONSerialization.isValidJSONObject(arguments) else {
      return .failure(.invalidArguments("edits must be JSON-serializable"))
    }
    let result = try await AgentEditFileTool().invoke(
      arguments: try JSONSerialization.data(withJSONObject: arguments, options: [.withoutEscapingSlashes]),
      context: context
    )
    return rewriteResourceMutationGuidance(result)
  }

  private func verifySuccessGuidance() -> String {
    "[next]\nEmbedded Tessera verification exited 0. If the requested implementation and tests are complete, do not keep editing or rerun the same verification; submit status=succeeded with feedback naming the Tessera verify result."
  }

  private func rewriteResourceMutationGuidance(
    _ result: AgentToolInvocationResult
  ) -> AgentToolInvocationResult {
    let rewritten = result.content
      .replacingOccurrences(of: "read_file", with: "tessera read_resource")
      .replacingOccurrences(of: "write_file", with: "tessera write_resource")
      .replacingOccurrences(of: "edit_file", with: "tessera edit_resource")
    return AgentToolInvocationResult(
      content: rewritten,
      isError: result.isError,
      errorKind: result.errorKind
    )
  }
}

private func jsonInt(_ value: Any?) -> Int? {
  switch value {
  case let int as Int:
    return int
  case let double as Double:
    return Int(double)
  case let string as String:
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(trimmed) ?? Double(trimmed).map(Int.init)
  default:
    return nil
  }
}
