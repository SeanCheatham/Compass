import Foundation
import Testing

@testable import CompassSandbox

@Suite("ContainerSandbox")
struct ContainerSandboxTests {
  @Test
  func defaultsUseTwoGiBMemory() {
    let configuration = ContainerSandboxConfiguration()

    #expect(configuration.memorySizeBytes == 2 * 1024 * 1024 * 1024)
  }

  @Test
  func mapsHostRootAndChildrenToWorkspace() throws {
    let mapper = ContainerWorkspacePathMapper(
      hostRoot: URL(fileURLWithPath: "/tmp/repo"),
      containerRoot: "/workspace"
    )

    #expect(try mapper.containerPath(for: URL(fileURLWithPath: "/tmp/repo")) == "/workspace")
    #expect(
      try mapper.containerPath(for: URL(fileURLWithPath: "/tmp/repo/src/index.ts"))
        == "/workspace/src/index.ts"
    )
  }

  @Test
  func rejectsCwdOutsideRepoRoot() {
    let mapper = ContainerWorkspacePathMapper(
      hostRoot: URL(fileURLWithPath: "/tmp/repo"),
      containerRoot: "/workspace"
    )

    #expect(throws: ContainerSandboxError.self) {
      _ = try mapper.containerPath(for: URL(fileURLWithPath: "/tmp/other"))
    }
  }

  @Test
  func captureWriterTruncatesOutput() throws {
    let writer = CapturingWriter(label: "stdout", maxBytes: 5)

    try writer.write(Data("abcdef".utf8))
    try writer.write(Data("gh".utf8))

    #expect(writer.string == "abcde\n... [stdout truncated after 5 bytes; dropped 3 bytes]")
  }
}
