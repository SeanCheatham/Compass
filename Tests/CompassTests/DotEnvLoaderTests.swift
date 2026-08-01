import Foundation
import Testing

@testable import CompassCore

@Suite("DotEnvLoader")
struct DotEnvLoaderTests {
  @Test
  func parsesKeyValueCommentsAndQuotes() {
    let contents = """
      # a comment
      COMPASS_AGENT_BASE_URL=https://api.moonshot.ai/v1
      export COMPASS_AGENT_MODEL="kimi-k2-0905-preview"
      COMPASS_AGENT_API_KEY='sk-test 123' # trailing comment
      INVALID LINE
      1BAD_KEY=nope
      """

    let pairs = DotEnvLoader.parse(contents)

    #expect(pairs.count == 3)
    #expect(pairs[0] == ("COMPASS_AGENT_BASE_URL", "https://api.moonshot.ai/v1"))
    #expect(pairs[1] == ("COMPASS_AGENT_MODEL", "kimi-k2-0905-preview"))
    #expect(pairs[2] == ("COMPASS_AGENT_API_KEY", "sk-test 123"))
  }

  @Test
  func loadsWithoutOverridingRealEnvironment() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "dotenv-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try "COMPASS_DOTENV_TEST_KEY=from-file\n".write(
      to: directory.appending(path: ".env"), atomically: true, encoding: .utf8)

    setenv("COMPASS_DOTENV_TEST_KEY", "from-env", 1)
    defer { unsetenv("COMPASS_DOTENV_TEST_KEY") }

    let applied = DotEnvLoader.loadIntoEnvironment(from: directory)

    #expect(applied.isEmpty)
    #expect(String(cString: getenv("COMPASS_DOTENV_TEST_KEY")!) == "from-env")
  }

  @Test
  func appliesMissingKeysFromDotEnv() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "dotenv-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try "COMPASS_DOTENV_APPLY_KEY=applied\n".write(
      to: directory.appending(path: ".env"), atomically: true, encoding: .utf8)

    unsetenv("COMPASS_DOTENV_APPLY_KEY")
    defer { unsetenv("COMPASS_DOTENV_APPLY_KEY") }

    let applied = DotEnvLoader.loadIntoEnvironment(from: directory)

    #expect(applied == ["COMPASS_DOTENV_APPLY_KEY"])
    #expect(String(cString: getenv("COMPASS_DOTENV_APPLY_KEY")!) == "applied")
  }
}
