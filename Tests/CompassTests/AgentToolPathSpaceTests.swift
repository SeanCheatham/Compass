import Foundation
import Testing

@testable import Compass

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
      try context.resolvePath("/workspace/packages/cli/src/main.ts").path
        == host.appendingPathComponent("packages/cli/src/main.ts").path
    )
    #expect(
      try context.resolvePath("packages/cli/src/main.ts").path
        == host.appendingPathComponent("packages/cli/src/main.ts").path
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
    let fileURL = host.appendingPathComponent("packages/core/src/index.ts")

    #expect(context.displayPath(for: host) == "/workspace")
    #expect(context.displayPath(for: fileURL) == "/workspace/packages/core/src/index.ts")
    #expect(
      context.sanitizeHostPaths(
        in: "failed in /Users/sean/git/demo/packages/core/src/index.ts under /Users/sean/git/demo"
      )
        == "failed in /workspace/packages/core/src/index.ts under /workspace"
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
}
