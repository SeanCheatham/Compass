import Darwin
import Foundation

public enum CompassCLI {
  public static func main(
    arguments: [String] = Array(CommandLine.arguments.dropFirst())
  ) async {
    let code = await run(arguments: arguments)
    exit(Int32(code))
  }

  public static func run(arguments: [String]) async -> Int {
    _ = DotEnvLoader.loadIntoEnvironment(
      from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
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
      case .help(let format):
        CompassCLIOutput(format: format).emit(
          HeadlessCompassEvent(
            kind: "help",
            level: "info",
            status: "completed",
            message: "Compass headless CLI usage.",
            detail: CompassCLI.usageText
          )
        )
        return 0

      case .doctor(let repo, let checkCloud, _):
        let ok = await runner.doctor(repoURL: repo, checkCloud: checkCloud, onEvent: emit)
        return ok ? 0 : 1

      case .scaffoldRust(let path, let name, let products, _):
        try runner.scaffoldRust(
          at: path,
          name: name,
          products: products,
          initializeGit: true,
          onEvent: emit
        )
        return 0

      case .verify(let repo, let verifyCommand, _):
        let ok = try await runner.verify(
          options: HeadlessVerifyOptions(repoURL: repo, command: verifyCommand),
          onEvent: emit
        )
        return ok ? 0 : 1

      case .run(let options, _):
        let ok = try await runner.runSessions(options: options, onEvent: emit)
        return ok ? 0 : 1

      case .replay(
        let repo, let session, let mode, let fixture, let promptLog, let maxIterations, _):
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
      let format = CompassCLIParser.requestedOutputFormat(in: arguments)
      CompassCLIOutput(format: format).emit(
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

public enum CompassCLIOutputFormat: String, Equatable {
  case json
  case text
}

public enum CompassCLICommand: Equatable {
  case help(format: CompassCLIOutputFormat)
  case doctor(repo: URL, checkCloud: Bool, format: CompassCLIOutputFormat)
  case scaffoldRust(
    path: URL, name: String?, products: [GeneratedProduct], format: CompassCLIOutputFormat)
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

  public var format: CompassCLIOutputFormat {
    switch self {
    case .help(let format),
      .doctor(_, _, let format),
      .scaffoldRust(_, _, _, let format),
      .run(_, let format),
      .replay(_, _, _, _, _, _, let format),
      .verify(_, _, let format):
      return format
    }
  }

  public static func parse(_ arguments: [String]) throws -> CompassCLICommand {
    if let first = arguments.first, ["help", "--help", "-h"].contains(first) {
      var helpParser = CompassCLIParser(Array(arguments.dropFirst()))
      let format = try helpParser.outputFormat()
      try helpParser.rejectRemaining()
      return .help(format: format)
    }
    var parser = CompassCLIParser(arguments)
    let command = try parser.requireCommand()
    switch command {
    case "doctor":
      let repo = try parser.requireURLOption("--repo")
      let checkCloud = parser.consumeFlag("--check-cloud")
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .doctor(repo: repo, checkCloud: checkCloud, format: format)

    case "scaffold":
      let kind = try parser.requireCommand()
      guard kind == "rust" else {
        throw CompassCLIError.usage("Only `scaffold rust` is supported.")
      }
      let path = try parser.requirePositionalURL("path")
      let name = try parser.optionalValue("--name")
      let productValues = try parser.consumeAllValues("--product")
      let products =
        productValues.isEmpty
        ? GeneratedProducts.default
        : try GeneratedProducts.parse(productValues)
      let format = try parser.outputFormat()
      try parser.rejectRemaining()
      return .scaffoldRust(path: path, name: name, products: products, format: format)

    case "run":
      let repo = try parser.requireURLOption("--repo")
      let briefRaw = try parser.requireValue("--brief")
      let brief = try parser.briefText(from: briefRaw)
      let mode = try parser.modelMode()
      let fixture = try parser.optionalURLOption("--fixture")
      let promptLog = try parser.optionalURLOption("--prompt-log")
      let maxIterations = try parser.optionalInt("--max-iterations") ?? 24
      let maxDevelopAttempts = try parser.optionalInt("--max-develop-attempts") ?? 2
      let maxVerifyRepairAttempts =
        try parser.optionalInt("--max-verify-repairs", allowingZero: true) ?? 1
      let sessionCount = try parser.optionalInt("--sessions") ?? 1
      let runCritic = parser.consumeFlag("--critic")
      let commitIterations = parser.consumeFlag("--commit")
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
          maxDevelopAttempts: maxDevelopAttempts,
          maxVerifyRepairAttempts: maxVerifyRepairAttempts,
          sessionCount: sessionCount,
          runCritic: runCritic,
          commitIterations: commitIterations
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

public struct CompassCLIParser {
  private var arguments: [String]

  public init(_ arguments: [String]) {
    self.arguments = arguments
  }

  public mutating func requireCommand() throws -> String {
    guard !arguments.isEmpty else {
      throw CompassCLIError.usage("Missing command.")
    }
    let value = arguments.removeFirst()
    guard !value.hasPrefix("--") else {
      throw CompassCLIError.usage("Missing command before option `\(value)`.")
    }
    return value
  }

  public mutating func requireValue(_ name: String) throws -> String {
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

  public mutating func optionalValue(_ name: String) throws -> String? {
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

  public mutating func consumeAllValues(_ name: String) throws -> [String] {
    var values: [String] = []
    while let value = try optionalValue(name) {
      values.append(value)
    }
    return values
  }

  public mutating func requireURLOption(_ name: String) throws -> URL {
    try normalizeURL(requireValue(name))
  }

  public mutating func optionalURLOption(_ name: String) throws -> URL? {
    try optionalValue(name).map(normalizeURL)
  }

  public mutating func requirePositionalURL(_ label: String) throws -> URL {
    guard let index = arguments.firstIndex(where: { !$0.hasPrefix("--") }) else {
      throw CompassCLIError.usage("Missing \(label).")
    }
    let value = arguments.remove(at: index)
    return try normalizeURL(value)
  }

  public mutating func requireInt(_ name: String) throws -> Int {
    guard let value = Int(try requireValue(name)), value > 0 else {
      throw CompassCLIError.usage("\(name) must be a positive integer.")
    }
    return value
  }

  public mutating func optionalInt(_ name: String, allowingZero: Bool = false) throws -> Int? {
    guard let raw = try optionalValue(name) else { return nil }
    let isValid: (Int) -> Bool = allowingZero ? { $0 >= 0 } : { $0 > 0 }
    guard let value = Int(raw), isValid(value) else {
      let requirement = allowingZero ? "a non-negative integer" : "a positive integer"
      throw CompassCLIError.usage("\(name) must be \(requirement).")
    }
    return value
  }

  public mutating func consumeFlag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
  }

  public mutating func outputFormat() throws -> CompassCLIOutputFormat {
    guard let raw = try optionalValue("--format") else { return .json }
    guard let format = CompassCLIOutputFormat(rawValue: raw) else {
      throw CompassCLIError.usage("--format must be json or text.")
    }
    return format
  }

  public mutating func modelMode() throws -> HeadlessModelMode {
    guard let raw = try optionalValue("--mode") else { return .auto }
    guard let mode = HeadlessModelMode(rawValue: raw) else {
      throw CompassCLIError.usage("--mode must be auto, fixture, mlx, or cloud.")
    }
    return mode
  }

  public func briefText(from raw: String) throws -> String {
    let url = try normalizeURL(raw)
    if FileManager.default.fileExists(atPath: url.path) {
      return try String(contentsOf: url, encoding: .utf8)
    }
    return raw
  }

  public func rejectRemaining() throws {
    guard arguments.isEmpty else {
      throw CompassCLIError.usage("Unexpected argument(s): \(arguments.joined(separator: " ")).")
    }
  }

  public static func requestedOutputFormat(in arguments: [String]) -> CompassCLIOutputFormat {
    guard let index = arguments.firstIndex(of: "--format") else { return .json }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else { return .json }
    return CompassCLIOutputFormat(rawValue: arguments[valueIndex]) ?? .json
  }

  private func normalizeURL(_ path: String) throws -> URL {
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CompassCLIError.usage("Path cannot be empty.")
    }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
  }
}

public struct CompassCLIOutput: Sendable {
  public var format: CompassCLIOutputFormat

  public func emit(_ event: HeadlessCompassEvent) {
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

public enum CompassCLIError: LocalizedError, Equatable {
  case usage(String)

  public var errorDescription: String? {
    switch self {
    case .usage(let message): return message
    }
  }

  public var usage: String {
    """
    \(CompassCLI.usageText)

    \(localizedDescription)
    """
  }

  public var exitCode: Int { 64 }
}

public extension CompassCLI {
  static let usageText = """
    Usage:
      compass-cli help [--format json|text]
      compass-cli doctor --repo <path> [--check-cloud] [--format json|text]
      compass-cli scaffold rust <path> [--name <name>] [--product cli|macos]... [--format json|text]
      compass-cli run --repo <path> --brief <file-or-inline> [--mode auto|fixture|mlx|cloud] [--fixture <jsonl>] [--sessions <n>] [--max-iterations <n>] [--max-develop-attempts <n>] [--max-verify-repairs <n>] [--prompt-log <dir>] [--critic] [--commit] [--format json|text]
      compass-cli replay --repo <path> --session <number> [--mode auto|fixture|mlx|cloud] [--fixture <jsonl>] [--max-iterations <n>] [--prompt-log <dir>] [--format json|text]
      compass-cli verify --repo <path> [--command <cmd>] [--format json|text]
    """
}

public extension String {
  fileprivate var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
