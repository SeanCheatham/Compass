import Foundation

struct AgentCargoCheckTool: AgentTool {
  static let toolName = "cargo_check"

  let spec = RustCargoToolSpec.make(
    name: Self.toolName,
    description:
      "Run `cargo check` through compass-engine and return structured Rust diagnostics. Prefer this over raw bash cargo check for compile probes."
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    try await RustCargoToolInvoker.invokeDiagnostics(
      command: .cargoCheck,
      arguments: arguments,
      context: context
    )
  }
}

struct AgentClippyLintTool: AgentTool {
  static let toolName = "clippy_lint"

  let spec = RustCargoToolSpec.make(
    name: Self.toolName,
    description:
      "Run `cargo clippy --workspace --all-targets -- -D warnings` through compass-engine and return structured lint diagnostics."
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    try await RustCargoToolInvoker.invokeDiagnostics(
      command: .clippyLint,
      arguments: arguments,
      context: context
    )
  }
}

struct AgentCargoTestTool: AgentTool {
  static let toolName = "cargo_test"

  struct Arguments: Decodable {
    var package: String?
    var test: String?
    var filter: String?
    var allFeatures: Bool?
    var timeoutMs: Int?

    enum CodingKeys: String, CodingKey {
      case package
      case test
      case filter
      case allFeatures
      case allFeaturesSnake = "all_features"
      case timeoutMs
      case timeoutMsSnake = "timeout_ms"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      package = try container.decodeIfPresent(String.self, forKey: .package)
      test = try container.decodeIfPresent(String.self, forKey: .test)
      filter = try container.decodeIfPresent(String.self, forKey: .filter)
      allFeatures =
        (try? container.decodeIfPresent(Bool.self, forKey: .allFeatures))
        ?? (try? container.decodeIfPresent(Bool.self, forKey: .allFeaturesSnake))
      timeoutMs =
        (try? container.decodeIfPresent(Int.self, forKey: .timeoutMs))
        ?? (try? container.decodeIfPresent(Int.self, forKey: .timeoutMsSnake))
    }
  }

  let spec = AgentToolSpec(
    name: Self.toolName,
    description:
      "Run `cargo test` through compass-engine and return structured pass/fail counts. Prefer scoped package/filter runs while iterating.",
    parameters: RustCargoToolSpec.testParameters
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    guard let service = context.rustCargoService else {
      return .failure("Rust cargo tools are not enabled for this project.", kind: .invalidArguments)
    }
    do {
      let data = try await service.run(
        command: .cargoTest,
        repoURL: context.workingDirectory,
        arguments: RustCargoToolInvoker.testArguments(args),
        timeout: TimeInterval(args.timeoutMs ?? RustCargoToolInvoker.defaultTimeoutMs) / 1_000
      )
      let response = try JSONDecoder().decode(RustEngineResponse<CargoTestData>.self, from: data)
      guard response.ok, let payload = response.data else {
        return .failure(response.errors.joined(separator: "\n"), kind: .bashFailure)
      }
      return .ok(RustCargoToolInvoker.formatTest(payload))
    } catch {
      return .failure(error.localizedDescription, kind: .bashFailure)
    }
  }
}

private enum RustCargoToolSpec {
  static let diagnosticParameters = AgentToolParametersSchema(literal: [
    "type": "object",
    "additionalProperties": false,
    "properties": [
      "package": ["type": "string", "description": "Optional Cargo package name to scope the run."],
      "allFeatures": ["type": "boolean", "description": "Pass --all-features."],
      "timeoutMs": [
        "type": "integer",
        "minimum": 1,
        "maximum": RustCargoToolInvoker.maxTimeoutMs,
        "description": "Timeout in milliseconds. Default 120000.",
      ],
    ],
  ])

  static let testParameters = AgentToolParametersSchema(literal: [
    "type": "object",
    "additionalProperties": false,
    "properties": [
      "package": ["type": "string", "description": "Optional Cargo package name to scope the run."],
      "test": ["type": "string", "description": "Optional integration test binary name."],
      "filter": ["type": "string", "description": "Optional libtest filter pattern."],
      "allFeatures": ["type": "boolean", "description": "Pass --all-features."],
      "timeoutMs": [
        "type": "integer",
        "minimum": 1,
        "maximum": RustCargoToolInvoker.maxTimeoutMs,
        "description": "Timeout in milliseconds. Default 120000.",
      ],
    ],
  ])

  static func make(name: String, description: String) -> AgentToolSpec {
    AgentToolSpec(name: name, description: description, parameters: diagnosticParameters)
  }
}

private enum RustCargoToolInvoker {
  static let defaultTimeoutMs = 120_000
  static let maxTimeoutMs = 1_800_000
  static let maxDiagnostics = 20

  struct DiagnosticArguments: Decodable {
    var package: String?
    var allFeatures: Bool?
    var timeoutMs: Int?

    enum CodingKeys: String, CodingKey {
      case package
      case allFeatures
      case allFeaturesSnake = "all_features"
      case timeoutMs
      case timeoutMsSnake = "timeout_ms"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      package = try container.decodeIfPresent(String.self, forKey: .package)
      allFeatures =
        (try? container.decodeIfPresent(Bool.self, forKey: .allFeatures))
        ?? (try? container.decodeIfPresent(Bool.self, forKey: .allFeaturesSnake))
      timeoutMs =
        (try? container.decodeIfPresent(Int.self, forKey: .timeoutMs))
        ?? (try? container.decodeIfPresent(Int.self, forKey: .timeoutMsSnake))
    }
  }

  static func invokeDiagnostics(
    command: RustEngineCommand,
    arguments: Data,
    context: AgentToolContext
  ) async throws -> AgentToolInvocationResult {
    let args: DiagnosticArguments
    do {
      args = try JSONDecoder().decode(DiagnosticArguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    guard let service = context.rustCargoService else {
      return .failure("Rust cargo tools are not enabled for this project.", kind: .invalidArguments)
    }
    do {
      let data = try await service.run(
        command: command,
        repoURL: context.workingDirectory,
        arguments: diagnosticArguments(args),
        timeout: TimeInterval(args.timeoutMs ?? defaultTimeoutMs) / 1_000
      )
      let response = try JSONDecoder().decode(RustEngineResponse<CargoCheckData>.self, from: data)
      guard response.ok, let payload = response.data else {
        return .failure(response.errors.joined(separator: "\n"), kind: .bashFailure)
      }
      return .ok(formatDiagnostics(command: command, payload))
    } catch {
      return .failure(error.localizedDescription, kind: .bashFailure)
    }
  }

  static func diagnosticArguments(_ args: DiagnosticArguments) -> [String] {
    var values: [String] = []
    if let package = args.package?.trimmingCharacters(in: .whitespacesAndNewlines), !package.isEmpty {
      values += ["--package", package]
    }
    if args.allFeatures == true {
      values.append("--all-features")
    }
    return values
  }

  static func testArguments(_ args: AgentCargoTestTool.Arguments) -> [String] {
    var values: [String] = []
    if let package = args.package?.trimmingCharacters(in: .whitespacesAndNewlines), !package.isEmpty {
      values += ["--package", package]
    }
    if let test = args.test?.trimmingCharacters(in: .whitespacesAndNewlines), !test.isEmpty {
      values += ["--test", test]
    }
    if let filter = args.filter?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty {
      values += ["--filter", filter]
    }
    if args.allFeatures == true {
      values.append("--all-features")
    }
    return values
  }

  static func formatDiagnostics(command: RustEngineCommand, _ data: CargoCheckData) -> String {
    var lines: [String] = []
    lines.append("\(command.rawValue): exit \(data.exitCode)")
    lines.append("errors: \(data.summary.errors), warnings: \(data.summary.warnings)")
    if !data.summary.cratesAffected.isEmpty {
      lines.append("crates: \(data.summary.cratesAffected.joined(separator: ", "))")
    }
    if data.diagnostics.isEmpty {
      lines.append("(no diagnostics)")
      return lines.joined(separator: "\n")
    }
    for diagnostic in data.diagnostics.prefix(maxDiagnostics) {
      let location = [diagnostic.file, diagnostic.line.map(String.init)]
        .compactMap { $0 }
        .joined(separator: ":")
      let code = diagnostic.code.map { " [\($0)]" } ?? ""
      lines.append("- \(diagnostic.level)\(code) \(location)")
      lines.append("  \(diagnostic.message)")
      if let label = diagnostic.label, !label.isEmpty {
        lines.append("  label: \(label)")
      }
    }
    if data.diagnostics.count > maxDiagnostics {
      lines.append("... \(data.diagnostics.count - maxDiagnostics) more diagnostic(s) omitted")
    }
    return lines.joined(separator: "\n")
  }

  static func formatTest(_ data: CargoTestData) -> String {
    var lines: [String] = []
    lines.append("cargo-test: exit \(data.exitCode)")
    lines.append("passed: \(data.passed), failed: \(data.failed)")
    for failure in data.failures.prefix(maxDiagnostics) {
      let location = [failure.file, failure.line.map(String.init)]
        .compactMap { $0 }
        .joined(separator: ":")
      lines.append("- \(failure.testName)\(location.isEmpty ? "" : " \(location)")")
      lines.append("  \(failure.message)")
    }
    return lines.joined(separator: "\n")
  }
}
