import Foundation
import Testing

@testable import CompassCore

@Suite("String-replacement edit_file")
struct AgentEditFileTextToolTests {
  private func makeWorkspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "edit-text-tool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func context(for url: URL) -> AgentToolContext {
    AgentToolContext(workingDirectory: url, enforceReadBeforeWrite: false)
  }

  @Test
  func replacesUniqueString() async throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "main.rs")
    try "fn main() {\n    println!(\"old\");\n}\n".write(to: file, atomically: true, encoding: .utf8)

    let tool = AgentEditFileTextTool()
    let result = try await tool.invoke(
      arguments: Data(
        #"{"path":"main.rs","edits":[{"old_string":"println!(\"old\");","new_string":"println!(\"new\");"}]}"#
          .utf8),
      context: context(for: workspace)
    )
    #expect(!result.isError)
    let content = try String(contentsOf: file, encoding: .utf8)
    #expect(content.contains("println!(\"new\");"))
  }

  @Test
  func rejectsNonUniqueString() async throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "lib.rs")
    try "let a = 1;\nlet b = 1;\n".write(to: file, atomically: true, encoding: .utf8)

    let tool = AgentEditFileTextTool()
    let result = try await tool.invoke(
      arguments: Data(
        #"{"path":"lib.rs","edits":[{"old_string":"= 1;","new_string":"= 2;"}]}"#.utf8),
      context: context(for: workspace)
    )
    #expect(result.isError)
    #expect(result.content.contains("occurs 2 times"))
    let content = try String(contentsOf: file, encoding: .utf8)
    #expect(content.contains("let a = 1;"))
  }

  @Test
  func replaceAllReplacesEveryOccurrence() async throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "lib.rs")
    try "foo();\nfoo();\n".write(to: file, atomically: true, encoding: .utf8)

    let tool = AgentEditFileTextTool()
    let result = try await tool.invoke(
      arguments: Data(
        #"{"path":"lib.rs","edits":[{"old_string":"foo()","new_string":"bar()","replace_all":true}]}"#
          .utf8),
      context: context(for: workspace)
    )
    #expect(!result.isError)
    let content = try String(contentsOf: file, encoding: .utf8)
    #expect(content == "bar();\nbar();\n")
  }

  @Test
  func missingOldStringFailsWithoutWriting() async throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "a.txt")
    try "actual content".write(to: file, atomically: true, encoding: .utf8)

    let tool = AgentEditFileTextTool()
    let result = try await tool.invoke(
      arguments: Data(
        #"{"path":"a.txt","edits":[{"old_string":"hallucinated","new_string":"x"}]}"#.utf8),
      context: context(for: workspace)
    )
    #expect(result.isError)
    #expect(result.content.contains("not found"))
    #expect(try String(contentsOf: file, encoding: .utf8) == "actual content")
  }

  @Test
  func sequentialEditsSeePriorResults() async throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "seq.txt")
    try "start".write(to: file, atomically: true, encoding: .utf8)

    let tool = AgentEditFileTextTool()
    let result = try await tool.invoke(
      arguments: Data(
        #"{"path":"seq.txt","edits":[{"old_string":"start","new_string":"middle"},{"old_string":"middle","new_string":"end"}]}"#
          .utf8),
      context: context(for: workspace)
    )
    #expect(!result.isError)
    #expect(try String(contentsOf: file, encoding: .utf8) == "end")
  }
}
