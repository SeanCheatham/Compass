import Foundation
import Testing

@testable import Compass

@Suite(.serialized)
struct ProcessRunnerTests {
  @Test func testRunClosesEmptyInputWithDevNull() async throws {
    let result = try await ProcessRunner.run(
      executable: "/bin/cat",
      arguments: [],
      timeout: 2
    )

    try #require(result.exitCode == 0)
    try #require(result.stdout.isEmpty)
    try #require(result.stderr.isEmpty)
  }

  @Test func testRunDrainsLargeOutputWithoutStreamingCallbacks() async throws {
    let result = try await ProcessRunner.run(
      executable: "/bin/zsh",
      arguments: ["-lc", "dd if=/dev/zero bs=1024 count=256 2>/dev/null"],
      timeout: 5
    )

    try #require(result.exitCode == 0)
    try #require(result.stdout.utf8.count == 262_144)
    try #require(result.stderr.isEmpty)
  }

  @Test func testRunExecutesShellStubWithoutInput() async throws {
    let directory = try makeTempDir()
    let stub = directory.appendingPathComponent("ssh-keyscan")
    let script = """
      #!/bin/bash
      printf '%s\\n' '192.168.64.9 ssh-ed25519 TEST_KEY'
      exit 0
      """
    try script.write(to: stub, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o755)],
      ofItemAtPath: stub.path
    )

    let result = try await ProcessRunner.run(
      executable: stub.path,
      arguments: ["-T", "2", "-t", "ed25519,rsa,ecdsa", "192.168.64.9"],
      timeout: 30
    )

    try #require(result.exitCode == 0)
    try #require(result.stdout.contains("TEST_KEY"))
    try #require(result.stderr.isEmpty)
  }
}
