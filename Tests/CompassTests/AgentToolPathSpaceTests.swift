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
      try context.resolvePath("/workspace/crates/app-cli/src/main.rs").path
        == host.appendingPathComponent("crates/app-cli/src/main.rs").path
    )
    #expect(
      try context.resolvePath("crates/app-cli/src/main.rs").path
        == host.appendingPathComponent("crates/app-cli/src/main.rs").path
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
    let fileURL = host.appendingPathComponent("crates/app-core/src/lib.rs")

    #expect(context.displayPath(for: host) == "/workspace")
    #expect(context.displayPath(for: fileURL) == "/workspace/crates/app-core/src/lib.rs")
    #expect(
      context.sanitizeHostPaths(
        in: "failed in /Users/sean/git/demo/crates/app-core/src/lib.rs under /Users/sean/git/demo"
      )
        == "failed in /workspace/crates/app-core/src/lib.rs under /workspace"
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
