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
    try #require(result.isError)
    try #require(result.errorKind == .invalidArguments)
    try #require(result.content.contains("task is empty"))
  }

  @Test func testInvokeReturnsFailureWhenDelegateRunnerIsAbsent() async throws {
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"investigate Foo"}"#.utf8),
      context: context(runner: nil)
    )
    try #require(result.isError)
    try #require(
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
    try #require(!result.isError)
    try #require(result.content == "callers in 3 files; all handle nil safely")
    try #require(runner.lastTask == "find callers of bar")
    try #require(runner.lastToolNames == ["read_file"])
    try #require(runner.lastModelOverride == "alt-model")
  }

  @Test func testInvokeAcceptsCommonAliasArgumentsFromLessCapableModels() async throws {
    let runner = StubRunner(reply: "alias findings")
    let result = try await tool.invoke(
      arguments: Data(
        """
        {
          "instructions": "inspect the codemap tools",
          "tool_names": "read_file,bash",
          "model_override": "small-model"
        }
        """.utf8),
      context: context(runner: runner)
    )
    try #require(!result.isError)
    try #require(result.content == "alias findings")
    try #require(runner.lastTask == "inspect the codemap tools")
    try #require(runner.lastToolNames == ["read_file", "bash"])
    try #require(runner.lastModelOverride == "small-model")
  }

  @Test func testInvokeRejectsOversizedTaskTextWithoutCallingRunner() async throws {
    let huge = String(repeating: "x", count: AgentDelegateTool.maxTaskLength + 1)
    let payload = #"{"task":"\#(huge)"}"#
    let runner = StubRunner(reply: "should not be called")
    let result = try await tool.invoke(
      arguments: Data(payload.utf8),
      context: context(runner: runner)
    )
    try #require(result.isError)
    try #require(result.content.contains("exceeds"))
    try #require(runner.lastTask == nil, "runner must not be invoked when task is too long")
  }

  @Test func testInvokeSurfacesRunnerErrorsAsToolFailures() async throws {
    let runner = ThrowingRunner(error: .emptyTask)
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"do a thing"}"#.utf8),
      context: context(runner: runner)
    )
    try #require(result.isError)
    try #require(result.content.contains("delegate task is empty"))
  }

  // MARK: - Runner helper: tool filtering

  @Test func testFilterToolsDropsDelegateUnconditionallyToPreventNesting() throws {
    let parents: [AgentTool] = [
      AgentReadFileTool(),
      AgentDelegateTool(),
      AgentBashTool(),
    ]
    let filtered = AgentExecutorDelegateRunner.filterTools(parentTools: parents, requested: nil)
    let names = filtered.map { $0.spec.name }
    try #require(
      !names.contains(AgentDelegateTool.toolName),
      "child tool list must never include `delegate`")
    try #require(
      Set(names) == Set([AgentReadFileTool.toolName, AgentBashTool.toolName]))
  }

  @Test func testFilterToolsHonorsRequestedWhitelistAndIgnoresUnknownNames() throws {
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
    try #require(names == [AgentReadFileTool.toolName])
  }

  @Test func testFilterToolsAcceptsCommonToolNameVariants() throws {
    let parents: [AgentTool] = [
      AgentReadFileTool(),
      AgentListFilesTool(),
      AgentBashTool(),
      AgentDelegateTool(),
    ]
    let filtered = AgentExecutorDelegateRunner.filterTools(
      parentTools: parents,
      requested: ["read-file", "list file", "bash tool", "delegate"]
    )
    let names = filtered.map { $0.spec.name }
    try #require(
      names == [
        AgentReadFileTool.toolName,
        AgentListFilesTool.toolName,
        AgentBashTool.toolName,
      ])
  }

  @Test func testFilterToolsWithEmptyRequestedListReturnsNoTools() throws {
    let parents: [AgentTool] = [AgentReadFileTool(), AgentBashTool(), AgentDelegateTool()]
    let filtered = AgentExecutorDelegateRunner.filterTools(parentTools: parents, requested: [])
    try #require(
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
