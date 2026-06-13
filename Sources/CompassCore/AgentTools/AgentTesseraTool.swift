import Foundation

package struct AgentTesseraTool: AgentTool {
  package static let toolName = "tessera"

  package let spec: AgentToolSpec

  package init() {
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Run embedded Tessera project operations without shelling out to the tessera CLI. Supports project verify and manifest entrypoint execution.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": false,
        "required": ["action"],
        "properties": [
          "action": [
            "type": "string",
            "enum": ["verify", "run_entrypoint"],
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
          "input": [
            "description": "Optional JSON object used as an entrypoint input override.",
          ],
        ],
      ])
    )
  }

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
    let root: URL
    do {
      root = try context.resolvePath((object["root"] as? String) ?? ".")
    } catch let error as AgentToolError {
      return .failure(error)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return .failure(.notDirectory(context.relativize(root)))
    }

    switch action {
    case "verify":
      let result = try await CompassEngineProcess.verifyProject(root: root)
      return format(result: result, successNext: verifySuccessGuidance())
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
    default:
      return .failure(.invalidArguments("unsupported action: \(action)"))
    }
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
    sections.append("[exit \(result.exitCode)]")
    if result.exitCode == 0, let successNext {
      sections.append(successNext)
    }
    let output = sections.joined(separator: "\n\n")
    guard result.exitCode == 0 else {
      return .failure(output, kind: .bashFailure)
    }
    return .ok(output)
  }

  private func verifySuccessGuidance() -> String {
    "[next]\nEmbedded Tessera verification exited 0. If the requested implementation and tests are complete, do not keep editing or rerun the same verification; submit status=succeeded with feedback naming the Tessera verify result."
  }
}
