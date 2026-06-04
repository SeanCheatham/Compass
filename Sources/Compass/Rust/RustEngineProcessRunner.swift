import Foundation

struct RustEngineInvocation: Sendable, Equatable {
  var executableURL: URL
  var command: RustEngineCommand
  var repoURL: URL
  var arguments: [String]
  var pathPrefix: String?

  var processArguments: [String] {
    var values = [command.rawValue, "--repo", repoURL.path, "--format", "json"]
    values.append(contentsOf: arguments)
    return values
  }
}

protocol RustEngineProcessRunning: Sendable {
  func run(_ invocation: RustEngineInvocation, timeout: TimeInterval) async throws -> ProcessResult
}

struct RustEngineProcessRunner: RustEngineProcessRunning {
  func run(_ invocation: RustEngineInvocation, timeout: TimeInterval) async throws -> ProcessResult {
    let executable = invocation.executableURL.path
    if let pathPrefix = invocation.pathPrefix, !pathPrefix.isEmpty {
      return try await ProcessRunner.run(
        executable: "/usr/bin/env",
        arguments: ["PATH=\(pathPrefix):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", executable]
          + invocation.processArguments,
        workingDirectory: invocation.repoURL,
        timeout: timeout
      )
    }
    return try await ProcessRunner.run(
      executable: executable,
      arguments: invocation.processArguments,
      workingDirectory: invocation.repoURL,
      timeout: timeout
    )
  }
}
