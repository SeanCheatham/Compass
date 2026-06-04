import Foundation
import Testing

@testable import Compass

struct RustCargoServiceTests {
  @Test func runBuildsPingInvocationAndReturnsJSONBytes() async throws {
    let runner = RustEngineInvocationRecorder(
      result: ProcessResult(
        exitCode: 0,
        stdout:
          #"{"schema_version":1,"command":"ping","ok":true,"data":{"version":"0.1.0","rustc":"rustc 1.80.0","repo":"/tmp/repo"},"errors":[]}"#,
        stderr: ""
      )
    )
    let service = RustCargoService(
      engineURL: URL(fileURLWithPath: "/tmp/compass-engine"),
      runner: runner
    )
    let repo = URL(fileURLWithPath: "/tmp/repo")

    let data = try await service.run(command: .ping, repoURL: repo, arguments: [], timeout: 12)
    let response = try service.decode(RustEnginePingData.self, from: data)
    let invocations = await runner.invocations
    let invocation = try #require(invocations.first)

    #expect(response.ok)
    #expect(response.data?.version == "0.1.0")
    #expect(invocation.command == .ping)
    #expect(invocation.repoURL == repo.standardizedFileURL)
    #expect(invocation.processArguments == ["ping", "--repo", repo.path, "--format", "json"])
  }

  @Test func runThrowsReadableErrorOnNonZeroExit() async throws {
    let runner = RustEngineInvocationRecorder(
      result: ProcessResult(exitCode: 2, stdout: "", stderr: "bad repo")
    )
    let service = RustCargoService(
      engineURL: URL(fileURLWithPath: "/tmp/compass-engine"),
      runner: runner
    )

    await #expect(throws: RustCargoServiceError.processFailed(exitCode: 2, stderr: "bad repo")) {
      _ = try await service.run(
        command: .ping,
        repoURL: URL(fileURLWithPath: "/tmp/repo"),
        arguments: [],
        timeout: 1
      )
    }
  }
}

private actor RustEngineInvocationRecorder: RustEngineProcessRunning {
  var result: ProcessResult
  private(set) var invocations: [RustEngineInvocation] = []

  init(result: ProcessResult) {
    self.result = result
  }

  func run(_ invocation: RustEngineInvocation, timeout: TimeInterval) async throws -> ProcessResult {
    invocations.append(invocation)
    return result
  }
}
