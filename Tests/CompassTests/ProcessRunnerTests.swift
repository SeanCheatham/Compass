import Foundation
import Testing

@testable import Compass

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
}
