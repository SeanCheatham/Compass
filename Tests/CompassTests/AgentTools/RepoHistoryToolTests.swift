import Foundation
import Testing

@testable import CompassCore

@Suite("Repo history tools")
struct RepoHistoryToolTests {
  @Test("file_history and annotate on a temp Git repo")
  func historyAndAnnotate() async throws {
    let root = try makeTempGitRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    try "line one\n".write(to: root.appending(path: "note.txt"), atomically: true, encoding: .utf8)
    try runGit(root, ["add", "note.txt"])
    try runGit(root, ["commit", "-m", "add note"])

    try "line one\nline two\n".write(
      to: root.appending(path: "note.txt"), atomically: true, encoding: .utf8)
    try runGit(root, ["add", "note.txt"])
    try runGit(root, ["commit", "-m", "extend note"])

    let context = AgentToolContext(workingDirectory: root)
    let history = try await AgentFileHistoryTool().invoke(
      arguments: Data(#"{"path":"note.txt","limit":5}"#.utf8),
      context: context
    )
    #expect(!history.isError)
    #expect(history.content.contains("History for note.txt"))
    #expect(history.content.contains("extend note"))
    #expect(history.content.contains("add note"))
    #expect(!history.content.contains(root.path))

    let annotate = try await AgentAnnotateTool().invoke(
      arguments: Data(#"{"path":"note.txt","startLine":1,"endLine":2}"#.utf8),
      context: context
    )
    #expect(!annotate.isError)
    #expect(annotate.content.contains("Annotations for note.txt"))
    #expect(annotate.content.contains("line two") || annotate.content.contains("line one"))
    #expect(annotate.content.contains("\t"))
  }

  @Test("non-git workspace returns friendly no-history message")
  func noVCS() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "compass-no-vcs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "x".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: root)
    let history = try await AgentFileHistoryTool().invoke(
      arguments: Data(#"{"path":"a.txt"}"#.utf8),
      context: context
    )
    #expect(!history.isError)
    #expect(history.content.contains("No version history available"))

    let annotate = try await AgentAnnotateTool().invoke(
      arguments: Data(#"{"path":"a.txt"}"#.utf8),
      context: context
    )
    #expect(!annotate.isError)
    #expect(annotate.content.contains("No version history available"))
  }

  @Test("path jail rejects escapes")
  func pathJail() async throws {
    let root = try makeTempGitRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    let context = AgentToolContext(workingDirectory: root)
    let history = try await AgentFileHistoryTool().invoke(
      arguments: Data(#"{"path":"/etc/passwd"}"#.utf8),
      context: context
    )
    #expect(history.isError)

    let annotate = try await AgentAnnotateTool().invoke(
      arguments: Data(#"{"path":"../outside"}"#.utf8),
      context: context
    )
    #expect(annotate.isError)
  }

  @Test("readOnlyTools includes file_history and annotate")
  func registry() {
    let names = Set(ToolRegistry.readOnlyTools().map(\.spec.name))
    #expect(names.contains("file_history"))
    #expect(names.contains("annotate"))
  }

  @Test("blame porcelain parser extracts rows")
  func porcelainParse() {
    let sample = """
      abcdef0123456789abcdef0123456789abcdef01 1 1 1
      author Ada
      author-mail <ada@example.com>
      author-time 1700000000
      author-tz +0000
      summary first line
      filename note.txt
      \tline one
      abcdef0123456789abcdef0123456789abcdef01 2 2 1
      author Ada
      author-mail <ada@example.com>
      author-time 1700000000
      author-tz +0000
      summary first line
      filename note.txt
      \tline two
      """
    let rows = RepoHistoryProvider.parseBlamePorcelain(sample)
    #expect(rows.count == 2)
    #expect(rows[0].line == 1)
    #expect(rows[0].author == "Ada")
    #expect(rows[0].text == "line one")
    #expect(rows[1].line == 2)
    #expect(rows[1].text == "line two")
  }
}

private func makeTempGitRepo() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appending(path: "compass-repo-history-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try runGit(root, ["init"])
  try runGit(root, ["config", "user.email", "compass-test@localhost"])
  try runGit(root, ["config", "user.name", "Compass Test"])
  return root
}

private func runGit(_ root: URL, _ args: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = ["-C", root.path] + args
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw NSError(
      domain: "RepoHistoryToolTests",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed"]
    )
  }
}
