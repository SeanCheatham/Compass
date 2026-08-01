import Foundation

/// Run a shell command via `/bin/zsh -lc`. Available to every phase:
/// Develop uses it to apply changes; Plan and Critic get it for
/// probing only (build, test, git inspection) and must not mutate tracked
/// files — enforcement of that intent lives in the system prompt.
public struct AgentBashTool: AgentTool {
  public static let toolName = "bash"
  public static let defaultTimeoutMs = 120_000
  public static let maxTimeoutMs = 1_800_000
  public static let maxOutputBytes = 100_000

  public struct Arguments: Decodable {
    public let command: String
    public let timeoutMs: Int?
    public let cwd: String?

    public enum CodingKeys: String, CodingKey {
      case command
      case cmd
      case commands
      case shellCommand
      case shellCommandSnake = "shell_command"
      case script
      case timeoutMs
      case timeoutMsSnake = "timeout_ms"
      case timeoutMillis
      case timeoutMillisSnake = "timeout_millis"
      case cwd
      case workingDirectory
      case workingDirectorySnake = "working_directory"
      case directory
      case dir
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      command = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .command,
        aliases: [.cmd, .commands, .shellCommand, .shellCommandSnake, .script],
        fieldName: "command"
      )
      timeoutMs = try FlexibleModelDecoder.decodeIntIfPresent(
        from: container,
        preferredKey: .timeoutMs,
        aliases: [.timeoutMsSnake, .timeoutMillis, .timeoutMillisSnake]
      )
      cwd = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .cwd,
        aliases: [.workingDirectory, .workingDirectorySnake, .directory, .dir]
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["command"],
      "properties": [
        "command": [
          "type": "string",
          "description":
            "Shell command for the agent's configured execution environment.",
        ],
        "timeoutMs": [
          "type": "integer",
          "minimum": 1,
          "maximum": AgentBashTool.maxTimeoutMs,
          "description":
            "Hard timeout in milliseconds. Default 120000 (2 minutes), max 1800000 (30 minutes).",
        ],
        "cwd": [
          "type": "string",
          "description":
            "Optional working directory for the command. Must resolve inside the agent's working directory. Prefer relative paths or `/workspace/...` during containerized Linux factory phases. Defaults to the working directory.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Execute a shell command in the agent's configured execution environment. Factory phases use the containerized Linux shell with the repo at `/workspace`; preflight commit uses the native macOS host shell. Stdout, stderr, and exit code are returned. Output capped at 100 KB; commands killed at the timeout.",
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
    let command = args.command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else {
      return .failure(.invalidArguments("command is empty"))
    }

    let cwd: URL
    if let raw = args.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      do {
        cwd = try context.resolvePath(raw)
      } catch let error as AgentToolError {
        return .failure(error)
      } catch {
        return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
      }
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        return .failure(.notDirectory(raw))
      }
    } else {
      cwd = context.workingDirectory
    }

    let timeoutMs =
      args.timeoutMs.map { min(max($0, 1), Self.maxTimeoutMs) } ?? Self.defaultTimeoutMs
    let timeoutSeconds = TimeInterval(timeoutMs) / 1_000

    let startedAt = Date()
    let result: ProcessResult
    do {
      result = try await context.bashRunner.run(
        command: command,
        workingDirectory: cwd,
        timeout: timeoutSeconds
      )
    } catch {
      return .failure(.bashFailure("launch failed: \(error.localizedDescription)"))
    }
    let elapsed = Date().timeIntervalSince(startedAt)
    let timedOut = elapsed >= timeoutSeconds - 0.1 && result.exitCode != 0

    let output = formatOutput(
      command: command,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      timedOut: timedOut,
      timeoutMs: timeoutMs
    )
    guard result.exitCode == 0, !timedOut else {
      return .failure(output, kind: .bashFailure)
    }
    return .ok(output)
  }

  private func formatOutput(
    command: String,
    stdout: String,
    stderr: String,
    exitCode: Int32,
    timedOut: Bool,
    timeoutMs: Int
  ) -> String {
    var sections: [String] = []
    let trimmedStdout = truncateOutput(stdout, label: "stdout")
    if !trimmedStdout.isEmpty {
      sections.append("[stdout]\n\(trimmedStdout)")
    }
    let trimmedStderr = truncateOutput(stderr, label: "stderr")
    if !trimmedStderr.isEmpty {
      sections.append("[stderr]\n\(trimmedStderr)")
    }
    if timedOut {
      sections.append("[timed out after \(timeoutMs) ms]")
    }
    sections.append("[exit \(exitCode)]")
    if exitCode == 0, !timedOut, let guidance = successfulVerificationGuidance(for: command) {
      sections.append(guidance)
    }
    return sections.joined(separator: "\n\n")
  }

  public static func isVerifyCommand(_ command: String) -> Bool {
    let normalized = command
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let standard = GeneratedProjectQuality.standardVerifyCommand.lowercased()
    if normalized == standard || normalized.contains(standard) {
      return true
    }
    if normalized.contains("cargo test")
      && (normalized.contains("clippy") || normalized.contains("llvm-cov"))
    {
      return true
    }
    return normalized == "cargo test --workspace"
      || normalized.contains("cargo llvm-cov")
      || (normalized.contains("cargo fmt") && normalized.contains("clippy")
        && normalized.contains("cargo test"))
  }

  private func successfulVerificationGuidance(for command: String) -> String? {
    guard Self.isVerifyCommand(command) else {
      return nil
    }

    return
      "[next]\n`\(command)` exited 0. If the requested implementation and tests are complete, do not keep editing, do not rerun the same verify command, and submit status=succeeded now with feedback that names this verified command. Continue only if a specific acceptance requirement is still missing."
  }

  public func truncateOutput(_ text: String, label: String) -> String {
    let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    guard stripped.utf8.count > Self.maxOutputBytes else { return stripped }
    let truncatedBytes = Data(stripped.utf8.prefix(Self.maxOutputBytes))
    let truncated = String(decoding: truncatedBytes, as: UTF8.self)
    return truncated + "\n... [\(label) truncated at \(Self.maxOutputBytes) bytes]"
  }
}
