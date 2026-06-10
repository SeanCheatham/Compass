import Darwin
import Foundation

public enum CompassCLI {
  public static func main(
    arguments: [String] = Array(CommandLine.arguments.dropFirst())
  ) async {
    let code = await run(arguments: arguments)
    exit(Int32(code))
  }

  static func run(arguments: [String]) async -> Int {
    var selectedFormat = CompassCLIOutputFormat.json
    do {
      let command = try CompassCLICommand.parse(arguments)
      selectedFormat = command.format
      let output = CompassCLIOutput(format: command.format)
      let emit: @Sendable (HeadlessCompassEvent) -> Void = { event in
        output.emit(event)
      }
      let runner = HeadlessCompassRunner()
      switch command {
      case .doctor(let repo, _):
        let ok = await runner.doctor(repoURL: repo, onEvent: emit)
        return ok ? 0 : 1

      case .scaffoldTypeScript(let path, let name, _):
        try runner.scaffoldTypeScript(at: path, name: name, onEvent: emit)
        return 0

      case .verify(let repo, let verifyCommand, _):
        let ok = try await runner.verify(
          options: HeadlessVerifyOptions(repoURL: repo, command: verifyCommand),
          onEvent: emit
        )
        return ok ? 0 : 1

      case .run(let options, _):
        let ok = try await runner.run(options: options, onEvent: emit)
        return ok ? 0 : 1

      case .replay(let repo, let session, let mode, let fixture, let promptLog, let maxIterations, _):
        let workspace = CompassWorkspace(repoURL: repo)
        try workspace.initialize()
        let record = workspace.readSessions(includeArchived: true).first { $0.session == session }
        let brief =
          [
            "Replay Compass session #\(session).",
            record?.plan.map { "Previous plan:\n\($0)" },
            record?.feedback.map { "Previous feedback:\n\($0)" },
            workspace.readVision().nilIfBlank.map { "Project context:\n\($0)" },
          ]
          .compactMap { $0 }
          .joined(separator: "\n\n")
        emit(
          HeadlessCompassEvent(
            kind: "replay_start",
            status: "running",
            message: "Replaying session #\(session).",
            metadata: ["session": "\(session)"]
          )
        )
        let ok = try await runner.run(
          options: HeadlessRunOptions(
            repoURL: repo,
            brief: brief,
            mode: mode,
            fixtureURL: fixture,
            promptLogDirectory: promptLog,
            maxIterations: maxIterations
          ),
          onEvent: emit
        )
        return ok ? 0 : 1
      }
    } catch let error as CompassCLIError {
      CompassCLIOutput(format: .json).emit(
        HeadlessCompassEvent(
          kind: "error",
          level: "error",
          status: "failed",
          message: error.localizedDescription,
          detail: error.usage
        )
      )
      return error.exitCode
    } catch {
      CompassCLIOutput(format: selectedFormat).emit(
        HeadlessCompassEvent(
          kind: "fatal_error",
          level: "error",
          status: "failed",
          message: error.localizedDescription
        )
      )
      return 1
    }
  }
}

enum CompassCLIOutputFormat: String, Equatable {
  case json
  case text
}

enum CompassCLICommand: Equatable {
  case doctor(repo: URL, format: CompassCLIOutputFormat)
  case scaffoldTypeScript(path: URL, name: String?, format: CompassCLIOutputFormat)
  case run(options: HeadlessRunOptions, format: CompassCLIOutputFormat)
  case replay(
    repo: URL,
    session: Int,
    mode: HeadlessModelMode,
    fixture: URL?,
    promptLog: URL?,
    maxIterations: Int,
    format: CompassCLIOutputFormat
  )
  case verify(repo: URL, command: String?, format: CompassCLIOutputFormat)

  var format: CompassCLIOutputFormat {
    switch self {
    case .doctor(_, let format),
      .scaffoldTypeScript(_, _, let format),
      .run(_, let format),
      .replay(_, _, _, _, _, _, let format),
      .verify(_, _, let format):
      return format
    }
  }

  static func parse(_ arguments: [String]) throws -> CompassCLICommand {
    var parser = CompassCLIParser(arguments)
    let command = try parser.requireCommand()
    switch command {
    case "doctor":
      let repo = try parser.requireURLOption("--repo")
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .doctor(repo: repo, format: format)

    case "scaffold":
      let kind = try parser.requireCommand()
      guard kind == "typescript" else {
        throw CompassCLIError.usage("Only `scaffold typescript` is supported.")
      }
      let path = try parser.requirePositionalURL("path")
      let name = try parser.optionalValue("--name")
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .scaffoldTypeScript(path: path, name: name, format: format)

    case "run":
      let repo = try parser.requireURLOption("--repo")
      let briefRaw = try parser.requireValue("--brief")
      let brief = try parser.briefText(from: briefRaw)
      let mode = try parser.modelMode()
      let fixture = try parser.optionalURLOption("--fixture")
      let promptLog = try parser.optionalURLOption("--prompt-log")
      let maxIterations = try parser.optionalInt("--max-iterations") ?? 24
      let runCritic = parser.consumeFlag("--critic")
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .run(
        options: HeadlessRunOptions(
          repoURL: repo,
          brief: brief,
          mode: mode,
          fixtureURL: fixture,
          promptLogDirectory: promptLog,
          maxIterations: maxIterations,
          runCritic: runCritic
        ),
        format: format
      )

    case "replay":
      let repo = try parser.requireURLOption("--repo")
      let session = try parser.requireInt("--session")
      let mode = try parser.modelMode()
      let fixture = try parser.optionalURLOption("--fixture")
      let promptLog = try parser.optionalURLOption("--prompt-log")
      let maxIterations = try parser.optionalInt("--max-iterations") ?? 24
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .replay(
        repo: repo,
        session: session,
        mode: mode,
        fixture: fixture,
        promptLog: promptLog,
        maxIterations: maxIterations,
        format: format
      )

    case "verify":
      let repo = try parser.requireURLOption("--repo")
      let command = try parser.optionalValue("--command")
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .verify(repo: repo, command: command, format: format)

    default:
      throw CompassCLIError.usage("Unknown command `\(command)`.")
    }
  }
}

struct CompassCLIParser {
  private var arguments: [String]

  init(_ arguments: [String]) {
    self.arguments = arguments
  }

  mutating func requireCommand() throws -> String {
    guard !arguments.isEmpty else {
      throw CompassCLIError.usage("Missing command.")
    }
    let value = arguments.removeFirst()
    guard !value.hasPrefix("--") else {
      throw CompassCLIError.usage("Missing command before option `\(value)`.")
    }
    return value
  }

  mutating func requireValue(_ name: String) throws -> String {
    guard let index = arguments.firstIndex(of: name) else {
      throw CompassCLIError.usage("Missing required option \(name).")
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
      throw CompassCLIError.usage("Missing value for \(name).")
    }
    let value = arguments[valueIndex]
    guard !value.hasPrefix("--") else {
      throw CompassCLIError.usage("Missing value for \(name).")
    }
    arguments.remove(at: valueIndex)
    arguments.remove(at: index)
    return value
  }

  mutating func optionalValue(_ name: String) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
      throw CompassCLIError.usage("Missing value for \(name).")
    }
    let value = arguments[valueIndex]
    guard !value.hasPrefix("--") else {
      throw CompassCLIError.usage("Missing value for \(name).")
    }
    arguments.remove(at: valueIndex)
    arguments.remove(at: index)
    return value
  }

  mutating func requireURLOption(_ name: String) throws -> URL {
    try normalizeURL(requireValue(name))
  }

  mutating func optionalURLOption(_ name: String) throws -> URL? {
    try optionalValue(name).map(normalizeURL)
  }

  mutating func requirePositionalURL(_ label: String) throws -> URL {
    guard let index = arguments.firstIndex(where: { !$0.hasPrefix("--") }) else {
      throw CompassCLIError.usage("Missing \(label).")
    }
    let value = arguments.remove(at: index)
    return try normalizeURL(value)
  }

  mutating func requireInt(_ name: String) throws -> Int {
    guard let value = Int(try requireValue(name)), value > 0 else {
      throw CompassCLIError.usage("\(name) must be a positive integer.")
    }
    return value
  }

  mutating func optionalInt(_ name: String) throws -> Int? {
    guard let raw = try optionalValue(name) else { return nil }
    guard let value = Int(raw), value > 0 else {
      throw CompassCLIError.usage("\(name) must be a positive integer.")
    }
    return value
  }

  mutating func consumeFlag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
  }

  mutating func outputFormat() throws -> CompassCLIOutputFormat {
    guard let raw = try optionalValue("--format") else { return .json }
    guard let format = CompassCLIOutputFormat(rawValue: raw) else {
      throw CompassCLIError.usage("--format must be json or text.")
    }
    return format
  }

  mutating func modelMode() throws -> HeadlessModelMode {
    guard let raw = try optionalValue("--mode") else { return .auto }
    guard let mode = HeadlessModelMode(rawValue: raw) else {
      throw CompassCLIError.usage("--mode must be fixture or mlx.")
    }
    return mode
  }

  func briefText(from raw: String) throws -> String {
    let url = try normalizeURL(raw)
    if FileManager.default.fileExists(atPath: url.path) {
      return try String(contentsOf: url, encoding: .utf8)
    }
    return raw
  }

  func rejectRemaining() throws {
    guard arguments.isEmpty else {
      throw CompassCLIError.usage("Unexpected argument(s): \(arguments.joined(separator: " ")).")
    }
  }

  private func normalizeURL(_ path: String) throws -> URL {
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CompassCLIError.usage("Path cannot be empty.")
    }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
  }
}

struct CompassCLIOutput: Sendable {
  var format: CompassCLIOutputFormat

  func emit(_ event: HeadlessCompassEvent) {
    switch format {
    case .json:
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      if let data = try? encoder.encode(event) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
      }
    case .text:
      var line = "[\(event.level)] \(event.kind)"
      if let status = event.status {
        line += " \(status)"
      }
      if let phase = event.phase {
        line += " (\(phase))"
      }
      line += ": \(event.message)"
      if let detail = event.detail, !detail.isEmpty {
        line += "\n\(detail)"
      }
      FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
  }
}

enum CompassCLIError: LocalizedError, Equatable {
  case usage(String)

  var errorDescription: String? {
    switch self {
    case .usage(let message): return message
    }
  }

  var usage: String {
    """
    Usage:
      compass-cli doctor --repo <path> [--format json|text]
      compass-cli scaffold typescript <path> [--name <name>] [--format json|text]
      compass-cli run --repo <path> --brief <file-or-inline> [--mode fixture|mlx] [--fixture <jsonl>] [--max-iterations <n>] [--prompt-log <dir>] [--critic] [--format json|text]
      compass-cli replay --repo <path> --session <number> [--mode fixture|mlx] [--fixture <jsonl>] [--max-iterations <n>] [--prompt-log <dir>] [--format json|text]
      compass-cli verify --repo <path> [--command <cmd>] [--format json|text]

    \(localizedDescription)
    """
  }

  var exitCode: Int { 64 }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
