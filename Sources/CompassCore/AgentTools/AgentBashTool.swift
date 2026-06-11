import Foundation

/// Run a shell command via `/bin/zsh -lc`. Available to every phase:
/// Develop uses it to apply changes; Plan and Critic get it for
/// probing only (build, test, git inspection) and must not mutate tracked
/// files — enforcement of that intent lives in the system prompt.
struct AgentBashTool: AgentTool {
  static let toolName = "bash"
  static let defaultTimeoutMs = 120_000
  static let maxTimeoutMs = 1_800_000
  static let maxOutputBytes = 100_000

  struct Arguments: Decodable {
    let command: String
    let timeoutMs: Int?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
      case command
      case cmd
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

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      command = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .command,
        aliases: [.cmd, .shellCommand, .shellCommandSnake, .script],
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

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["command"],
      "properties": [
        "command": [
          "type": "string",
          "description": "Shell command. Executed by `/bin/zsh -lc`.",
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
            "Optional working directory for the command. Must resolve inside the agent's working directory. Defaults to it.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Execute a shell command via /bin/zsh -lc. Stdout, stderr, and exit code are returned. Output capped at 100 KB; commands killed at the timeout.",
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

    return .ok(
      formatOutput(
        command: command,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        timedOut: timedOut,
        timeoutMs: timeoutMs
      ))
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

  private func successfulVerificationGuidance(for command: String) -> String? {
    let normalized = command
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    guard normalized == "pnpm verify"
      || normalized == "pnpm run verify"
      || normalized.contains(" pnpm verify")
      || normalized.contains(" pnpm run verify")
      || normalized.hasSuffix(" pnpm verify")
      || normalized.hasSuffix(" pnpm run verify")
    else {
      return nil
    }

    return
      "[next]\n`\(command)` exited 0. If the requested implementation and tests are complete, do not keep editing, do not rerun the same verify command, and submit status=succeeded now with feedback that names this verified command. Continue only if a specific acceptance requirement is still missing."
  }

  func truncateOutput(_ text: String, label: String) -> String {
    let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    guard stripped.utf8.count > Self.maxOutputBytes else { return stripped }
    let truncatedBytes = Data(stripped.utf8.prefix(Self.maxOutputBytes))
    let truncated = String(decoding: truncatedBytes, as: UTF8.self)
    return truncated + "\n... [\(label) truncated at \(Self.maxOutputBytes) bytes]"
  }
}
