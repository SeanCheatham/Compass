import Foundation

enum RustEngineCommand: String, Sendable, CaseIterable {
  case ping
  case workspaceOutline = "workspace-outline"
  case cargoCheck = "cargo-check"
  case clippyLint = "clippy-lint"
  case cargoTest = "cargo-test"
  case indexRust = "index-rust"
}

enum RustCargoServiceError: LocalizedError, Equatable {
  case engineNotFound
  case processFailed(exitCode: Int32, stderr: String)
  case emptyOutput

  var errorDescription: String? {
    switch self {
    case .engineNotFound:
      return "Could not locate compass-engine. Build it with `./scripts/build-compass-engine.sh` or install it in /usr/local/bin."
    case .processFailed(let exitCode, let stderr):
      return "compass-engine failed with exit \(exitCode): \(stderr)"
    case .emptyOutput:
      return "compass-engine produced no JSON output."
    }
  }
}

protocol RustCargoServicing: Sendable {
  func run(
    command: RustEngineCommand,
    repoURL: URL,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> Data
}

struct RustCargoService: RustCargoServicing {
  var engineURL: URL?
  var pathPrefix: String?
  var runner: any RustEngineProcessRunning

  init(
    engineURL: URL? = nil,
    pathPrefix: String? = nil,
    runner: any RustEngineProcessRunning = RustEngineProcessRunner()
  ) {
    self.engineURL = engineURL
    self.pathPrefix = pathPrefix
    self.runner = runner
  }

  func run(
    command: RustEngineCommand,
    repoURL: URL,
    arguments: [String] = [],
    timeout: TimeInterval = 30
  ) async throws -> Data {
    guard let engineURL = engineURL ?? RustEngineLocator.locateEngineBinary() else {
      throw RustCargoServiceError.engineNotFound
    }
    let invocation = RustEngineInvocation(
      executableURL: engineURL,
      command: command,
      repoURL: repoURL.standardizedFileURL,
      arguments: arguments,
      pathPrefix: pathPrefix
    )
    let result = try await runner.run(invocation, timeout: timeout)
    guard result.exitCode == 0 else {
      throw RustCargoServiceError.processFailed(
        exitCode: result.exitCode,
        stderr: (result.stderr + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else { throw RustCargoServiceError.emptyOutput }
    return Data(output.utf8)
  }

  func decode<T: Codable & Equatable>(
    _ type: T.Type,
    from data: Data
  ) throws -> RustEngineResponse<T> {
    try JSONDecoder().decode(RustEngineResponse<T>.self, from: data)
  }
}
