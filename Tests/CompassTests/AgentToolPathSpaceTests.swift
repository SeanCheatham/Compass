import Foundation
import Testing

@testable import Compass
@testable import CompassCore

@Suite("Agent tool path space")
struct AgentToolPathSpaceTests {
  @Test
  func resolvePathMapsWorkspaceRootOntoHostWorktree() throws {
    let host = URL(fileURLWithPath: "/tmp/compass-repo")
    let context = AgentToolContext(
      workingDirectory: host,
      agentVisibleWorkspacePath: "/workspace"
    )

    #expect(try context.resolvePath("/workspace").path == host.path)
    #expect(
      try context.resolvePath("/workspace/crates/cli/src/main.rs").path
        == host.appendingPathComponent("crates/cli/src/main.rs").path
    )
    #expect(
      try context.resolvePath("crates/cli/src/main.rs").path
        == host.appendingPathComponent("crates/cli/src/main.rs").path
    )
  }

  @Test
  func resolvePathRejectsPathsOutsideVisibleRoot() {
    let context = AgentToolContext(
      workingDirectory: URL(fileURLWithPath: "/tmp/compass-repo"),
      agentVisibleWorkspacePath: "/workspace"
    )

    #expect(throws: AgentToolError.self) {
      _ = try context.resolvePath("/etc/passwd")
    }
    #expect(throws: AgentToolError.self) {
      _ = try context.resolvePath("/workspace-other/file")
    }
  }

  @Test
  func displayPathAndSanitizeHideHostPrefixes() {
    let host = URL(fileURLWithPath: "/Users/sean/git/demo")
    let context = AgentToolContext(
      workingDirectory: host,
      agentVisibleWorkspacePath: "/workspace"
    )
    let fileURL = host.appendingPathComponent("crates/core/src/lib.rs")

    #expect(context.displayPath(for: host) == "/workspace")
    #expect(context.displayPath(for: fileURL) == "/workspace/crates/core/src/lib.rs")
    #expect(
      context.sanitizeHostPaths(
        in: "failed in /Users/sean/git/demo/crates/core/src/lib.rs under /Users/sean/git/demo"
      )
        == "failed in /workspace/crates/core/src/lib.rs under /workspace"
    )
  }

  @Test
  func hostNativeContextKeepsAbsoluteHostPaths() throws {
    let host = URL(fileURLWithPath: "/tmp/compass-repo")
    let context = AgentToolContext(workingDirectory: host)

    #expect(try context.resolvePath(host.path).path == host.path)
    #expect(context.displayPath(for: host) == ".")
    #expect(
      context.sanitizeHostPaths(in: "/tmp/compass-repo/src/main.ts")
        == "/tmp/compass-repo/src/main.ts"
    )
  }

  @Test
  func resolvePathRejectsSymlinkEscapeOutsideWorktree() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-symlink-jail-\(UUID().uuidString)", isDirectory: true)
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-symlink-outside-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: outside)
    }
    let escapeTarget = outside.appendingPathComponent("secret.txt")
    try Data("secret".utf8).write(to: escapeTarget)
    let link = root.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(
      atPath: link.path,
      withDestinationPath: outside.path
    )

    let context = AgentToolContext(
      workingDirectory: root,
      agentVisibleWorkspacePath: "/workspace"
    )
    #expect(throws: AgentToolError.self) {
      _ = try context.resolvePath("/workspace/escape/secret.txt")
    }
    #expect(throws: AgentToolError.self) {
      _ = try context.resolvePath("escape/secret.txt")
    }
  }
}
