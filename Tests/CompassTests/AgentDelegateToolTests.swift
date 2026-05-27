import Foundation
import Testing

@testable import Compass

struct AgentDelegateToolTests {
  private let tool = AgentDelegateTool()

  private func context(runner: AgentDelegateRunner? = nil) -> AgentToolContext {
    AgentToolContext(
      workingDirectory: FileManager.default.temporaryDirectory,
      delegateRunner: runner
    )
  }

  @Test func testInvokeReturnsFailureWhenTaskIsEmpty() async throws {
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"   "}"#.utf8),
      context: context(runner: StubRunner(reply: "ignored"))
    )
    #require(result.isError)
    #require(result.errorKind == .invalidArguments)
    #require(result.content.contains("task is empty"))
  }

  @Test func testInvokeReturnsFailureWhenDelegateRunnerIsAbsent() async throws {
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"investigate Foo"}"#.utf8),
      context: context(runner: nil)
    )
    #require(result.isError)
    #require(
      result.content.contains("delegate is not available"),
      "missing runner must surface as a clean failure, not a crash: \(result.content)")
  }

  @Test func testInvokePropagatesFindingsFromRunner() async throws {
    let runner = StubRunner(reply: "callers in 3 files; all handle nil safely")
    let result = try await tool.invoke(
      arguments: Data(
        #"{"task":"find callers of bar","tools":["read_file"],"model":"alt-model"}"#.utf8),
      context: context(runner: runner)
    )
    #require(!result.isError)
    #require(result.content == "callers in 3 files; all handle nil safely")
    #require(runner.lastTask == "find callers of bar")
    #require(runner.lastToolNames == ["read_file"])
    #require(runner.lastModelOverride == "alt-model")
  }

  @Test func testInvokeRejectsOversizedTaskTextWithoutCallingRunner() async throws {
    let huge = String(repeating: "x", count: AgentDelegateTool.maxTaskLength + 1)
    let payload = #"{"task":"\#(huge)"}"#
    let runner = StubRunner(reply: "should not be called")
    let result = try await tool.invoke(
      arguments: Data(payload.utf8),
      context: context(runner: runner)
    )
    #require(result.isError)
    #require(result.content.contains("exceeds"))
    #require(runner.lastTask == nil, "runner must not be invoked when task is too long")
  }

  @Test func testInvokeSurfacesRunnerErrorsAsToolFailures() async throws {
    let runner = ThrowingRunner(error: .emptyTask)
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"do a thing"}"#.utf8),
      context: context(runner: runner)
    )
    #require(result.isError)
    #require(result.content.contains("delegate task is empty"))
  }

  // MARK: - Runner helper: tool filtering

  @Test func testFilterToolsDropsDelegateUnconditionallyToPreventNesting() {
    let parents: [AgentTool] = [
      AgentReadFileTool(),
      AgentDelegateTool(),
      AgentBashTool(),
    ]
    let filtered = AgentExecutorDelegateRunner.filterTools(parentTools: parents, requested: nil)
    let names = filtered.map { $0.spec.name }
    #require(
      !names.contains(AgentDelegateTool.toolName),
      "child tool list must never include `delegate`")
    #require(
      Set(names) == Set([AgentReadFileTool.toolName, AgentBashTool.toolName]))
  }

  @Test func testFilterToolsHonorsRequestedWhitelistAndIgnoresUnknownNames() {
    let parents: [AgentTool] = [
      AgentReadFileTool(),
      AgentBashTool(),
      AgentLsTool(),
      AgentDelegateTool(),
    ]
    let filtered = AgentExecutorDelegateRunner.filterTools(
      parentTools: parents,
      requested: ["read_file", "delegate", "nonexistent-tool"]
    )
    let names = filtered.map { $0.spec.name }
    #require(names == [AgentReadFileTool.toolName])
  }

  @Test func testFilterToolsWithEmptyRequestedListReturnsNoTools() {
    let parents: [AgentTool] = [AgentReadFileTool(), AgentBashTool(), AgentDelegateTool()]
    let filtered = AgentExecutorDelegateRunner.filterTools(parentTools: parents, requested: [])
    #require(
      filtered.isEmpty,
      "an empty whitelist means the caller explicitly wants no tools")
  }

  // MARK: - Stubs

  private final class StubRunner: AgentDelegateRunner, @unchecked Sendable {
    let reply: String
    private(set) var lastTask: String?
    private(set) var lastToolNames: [String]?
    private(set) var lastModelOverride: String?

    init(reply: String) { self.reply = reply }

    func delegate(
      task: String,
      toolNames: [String]?,
      modelOverride: String?
    ) async throws -> String {
      lastTask = task
      lastToolNames = toolNames
      lastModelOverride = modelOverride
      return reply
    }
  }

  private struct ThrowingRunner: AgentDelegateRunner {
    let error: AgentDelegateRunnerError

    func delegate(
      task: String,
      toolNames: [String]?,
      modelOverride: String?
    ) async throws -> String {
      throw error
    }
  }
}
