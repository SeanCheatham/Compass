import Foundation
import XCTest

@testable import Compass

final class AgentDelegateToolTests: XCTestCase {
  private let tool = AgentDelegateTool()

  private func context(runner: AgentDelegateRunner? = nil) -> AgentToolContext {
    AgentToolContext(
      workingDirectory: FileManager.default.temporaryDirectory,
      delegateRunner: runner
    )
  }

  func testInvokeReturnsFailureWhenTaskIsEmpty() async throws {
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"   "}"#.utf8),
      context: context(runner: StubRunner(reply: "ignored"))
    )
    XCTAssertTrue(result.isError)
    XCTAssertEqual(result.content, "task is empty")
  }

  func testInvokeReturnsFailureWhenDelegateRunnerIsAbsent() async throws {
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"investigate Foo"}"#.utf8),
      context: context(runner: nil)
    )
    XCTAssertTrue(result.isError)
    XCTAssertTrue(
      result.content.contains("delegate is not available"),
      "missing runner must surface as a clean failure, not a crash: \(result.content)")
  }

  func testInvokePropagatesFindingsFromRunner() async throws {
    let runner = StubRunner(reply: "callers in 3 files; all handle nil safely")
    let result = try await tool.invoke(
      arguments: Data(
        #"{"task":"find callers of bar","tools":["read_file"],"model":"alt-model"}"#.utf8),
      context: context(runner: runner)
    )
    XCTAssertFalse(result.isError)
    XCTAssertEqual(result.content, "callers in 3 files; all handle nil safely")
    XCTAssertEqual(runner.lastTask, "find callers of bar")
    XCTAssertEqual(runner.lastToolNames, ["read_file"])
    XCTAssertEqual(runner.lastModelOverride, "alt-model")
  }

  func testInvokeRejectsOversizedTaskTextWithoutCallingRunner() async throws {
    let huge = String(repeating: "x", count: AgentDelegateTool.maxTaskLength + 1)
    let payload = #"{"task":"\#(huge)"}"#
    let runner = StubRunner(reply: "should not be called")
    let result = try await tool.invoke(
      arguments: Data(payload.utf8),
      context: context(runner: runner)
    )
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("exceeds"))
    XCTAssertNil(runner.lastTask, "runner must not be invoked when task is too long")
  }

  func testInvokeSurfacesRunnerErrorsAsToolFailures() async throws {
    let runner = ThrowingRunner(error: .emptyTask)
    let result = try await tool.invoke(
      arguments: Data(#"{"task":"do a thing"}"#.utf8),
      context: context(runner: runner)
    )
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("delegate task is empty"))
  }

  // MARK: - Runner helper: tool filtering

  func testFilterToolsDropsDelegateUnconditionallyToPreventNesting() {
    let parents: [AgentTool] = [
      AgentReadFileTool(),
      AgentDelegateTool(),
      AgentBashTool(),
    ]
    let filtered = AgentExecutorDelegateRunner.filterTools(parentTools: parents, requested: nil)
    let names = filtered.map { $0.spec.name }
    XCTAssertFalse(
      names.contains(AgentDelegateTool.toolName),
      "child tool list must never include `delegate`")
    XCTAssertEqual(
      Set(names),
      Set([AgentReadFileTool.toolName, AgentBashTool.toolName]))
  }

  func testFilterToolsHonorsRequestedWhitelistAndIgnoresUnknownNames() {
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
    XCTAssertEqual(names, [AgentReadFileTool.toolName])
  }

  func testFilterToolsWithEmptyRequestedListReturnsNoTools() {
    let parents: [AgentTool] = [AgentReadFileTool(), AgentBashTool(), AgentDelegateTool()]
    let filtered = AgentExecutorDelegateRunner.filterTools(parentTools: parents, requested: [])
    XCTAssertTrue(
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
