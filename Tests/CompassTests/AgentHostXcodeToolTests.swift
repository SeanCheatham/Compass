import Foundation
import Testing

@testable import Compass

struct AgentHostXcodeToolTests {

  @Test func testToolFailsCleanlyWhenServiceIsAbsent() async throws {
    let tool = AgentHostXcodeTool()
    let result = try await tool.invoke(
      arguments: Data(#"{"action":"status"}"#.utf8),
      context: AgentToolContext(workingDirectory: URL(fileURLWithPath: "/tmp/work"))
    )

    #expect(result.isError)
    #expect(result.content.contains("not enabled"))
  }

  @Test func testStatusFormatsReadyService() async throws {
    let service = FakeHostXcodeService(
      statusValue: .ready(
        developerDir: "/Applications/Xcode.app/Contents/Developer",
        xcodebuildPath: "/usr/bin/xcodebuild",
        version: "Xcode 17.0"
      )
    )
    let tool = AgentHostXcodeTool()
    let result = try await tool.invoke(
      arguments: Data(#"{"action":"status"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/work"),
        hostXcodeService: service
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("Host Xcode ready"))
    #expect(result.content.contains("Xcode 17.0"))
  }

  @Test func testBuildAndTestDispatchToService() async throws {
    let service = FakeHostXcodeService(
      runResult: ProcessResult(exitCode: 0, stdout: "ok", stderr: "")
    )
    let tool = AgentHostXcodeTool()
    let context = AgentToolContext(
      workingDirectory: URL(fileURLWithPath: "/tmp/work"),
      hostXcodeService: service
    )
    let buildResult = try await tool.invoke(
      arguments: Data(#"{"action":"build","arguments":["-scheme","App"],"timeoutMs":5000}"#.utf8),
      context: context
    )
    let testResult = try await tool.invoke(
      arguments: Data(#"{"action":"test","arguments":["-scheme","App"]}"#.utf8),
      context: context
    )
    let calls = await service.calls

    #expect(!buildResult.isError)
    #expect(!testResult.isError)
    #expect(calls.map(\.action) == [.build, .test])
    #expect(calls[0].arguments == ["-scheme", "App"])
    #expect(calls[0].timeout == 5)
  }

  @Test func testToolRegistryOmitsHostXcodeByDefaultAndAddsItWhenServiceProvided() throws {
    let defaultNames = Set(ToolRegistry.tools(for: .develop).map(\.spec.name))
    let service = FakeHostXcodeService()
    let enabledNames = Set(
      ToolRegistry.tools(
        for: .develop,
        settings: AgentRuntimeSettings(),
        hostXcodeService: service
      ).map(\.spec.name)
    )
    let planNames = Set(
      ToolRegistry.tools(
        for: .plan,
        settings: AgentRuntimeSettings(),
        hostXcodeService: service
      ).map(\.spec.name)
    )

    #expect(!defaultNames.contains(AgentHostXcodeTool.toolName))
    #expect(enabledNames.contains(AgentHostXcodeTool.toolName))
    #expect(!planNames.contains(AgentHostXcodeTool.toolName))
  }
}

private actor FakeHostXcodeService: HostXcodeServicing {
  struct Call: Equatable {
    var action: HostXcodeAction
    var arguments: [String]
    var timeout: TimeInterval
  }

  var statusValue: HostXcodeStatus
  var runResult: ProcessResult
  private(set) var calls: [Call] = []

  init(
    statusValue: HostXcodeStatus = .ready(
      developerDir: "/Applications/Xcode.app/Contents/Developer",
      xcodebuildPath: "/usr/bin/xcodebuild",
      version: "Xcode 17.0"
    ),
    runResult: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")
  ) {
    self.statusValue = statusValue
    self.runResult = runResult
  }

  func status() async -> HostXcodeStatus {
    statusValue
  }

  func run(
    action: HostXcodeAction,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    calls.append(Call(action: action, arguments: arguments, timeout: timeout))
    return runResult
  }

  func runVerifyCommand(_ command: String, timeout: TimeInterval) async throws -> ProcessResult {
    runResult
  }
}
