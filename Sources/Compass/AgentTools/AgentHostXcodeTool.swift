import Foundation

struct AgentHostXcodeTool: AgentTool {
  static let toolName = "host_xcode"
  static let defaultTimeoutMs = 120_000
  static let maxTimeoutMs = 1_800_000

  struct Arguments: Codable {
    let action: String
    let arguments: [String]?
    let timeoutMs: Int?
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["action"],
      "properties": [
        "action": [
          "type": "string",
          "enum": ["status", "build", "test"],
          "description":
            "Host Xcode operation. Only build/test xcodebuild operations are supported.",
        ],
        "arguments": [
          "type": "array",
          "items": ["type": "string"],
          "description":
            "xcodebuild flags only. Do not include build/test actions; the selected action supplies them.",
        ],
        "timeoutMs": [
          "type": "integer",
          "minimum": 1,
          "maximum": Self.maxTimeoutMs,
          "description":
            "Hard timeout in milliseconds. Default 120000 (2 minutes), max 1800000 (30 minutes).",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Run restricted host-side Xcode build/test checks against a temporary host mirror of the Shared VM workspace. Supports status, build, and test only; no Simulator management, app launch, or arbitrary host shell.",
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
    guard let service = context.hostXcodeService else {
      return .failure(
        "Host Xcode build/test is not enabled for this project.",
        kind: .invalidArguments
      )
    }

    let action = args.action.trimmingCharacters(in: .whitespacesAndNewlines)
    if action == "status" {
      let status = await service.status()
      if status.isReady {
        return .ok(
          """
          Host Xcode ready.
          Developer dir: \(status.developerDir ?? "unknown")
          xcodebuild: \(status.xcodebuildPath ?? "unknown")
          Version:
          \(status.version ?? "unknown")
          """)
      }
      return .failure(status.unavailableReason ?? "Host Xcode is not ready.", kind: .bashFailure)
    }

    guard let hostAction = HostXcodeAction(rawValue: action) else {
      return .failure(.invalidArguments("action must be status, build, or test"))
    }
    let timeoutMs =
      args.timeoutMs.map { min(max($0, 1), Self.maxTimeoutMs) } ?? Self.defaultTimeoutMs
    do {
      let result = try await service.run(
        action: hostAction,
        arguments: args.arguments ?? [],
        timeout: TimeInterval(timeoutMs) / 1_000
      )
      return .ok(formatOutput(result, timeoutMs: timeoutMs))
    } catch let error as HostXcodeError {
      return .failure(error.localizedDescription, kind: .bashFailure)
    } catch {
      return .failure(
        "Host Xcode command failed: \(error.localizedDescription)", kind: .bashFailure)
    }
  }

  private func formatOutput(_ result: ProcessResult, timeoutMs: Int) -> String {
    var sections: [String] = []
    let stdout = AgentBashTool().truncateOutput(result.stdout, label: "stdout")
    let stderr = AgentBashTool().truncateOutput(result.stderr, label: "stderr")
    if !stdout.isEmpty {
      sections.append("[stdout]\n\(stdout)")
    }
    if !stderr.isEmpty {
      sections.append("[stderr]\n\(stderr)")
    }
    sections.append("[exit \(result.exitCode)]")
    sections.append("[host_xcode timeout budget \(timeoutMs)ms]")
    return sections.joined(separator: "\n\n")
  }
}
