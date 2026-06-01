import Foundation
import Testing

@testable import Compass

/// Tests `SharedCompassVMGuestBridge.populateKnownHosts`. The helper is the
/// fix for the first-boot "Host key verification failed" deadlock: the SSH
/// readiness probe runs with `StrictHostKeyChecking=yes` against an empty
/// `known_hosts`, so it can never succeed on a fresh guest until we TOFU-
/// trust the freshly-generated host key. These tests exercise the bootstrap
/// against a fake `ssh-keyscan` stand-in so we can validate parsing,
/// dedup, and append behaviour without touching a real network.
@Suite(.serialized)
struct SharedCompassVMGuestBridgeKnownHostsTests {
  private let fakeKeyscanTimeout: TimeInterval = 2

  // MARK: - Fixtures

  /// Writes a tiny shell stub that mimics `ssh-keyscan` by echoing
  /// `cannedOutput`. The stub is installed at a unique temp path so each
  /// test gets a fresh sandbox.
  private func makeFakeKeyscan(
    cannedOutput: String,
    exitCode: Int = 0,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> URL {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-keyscan-stub-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let stub = tmpDir.appendingPathComponent("ssh-keyscan")
    let script = """
      #!/bin/bash
      \(Self.printfScript(for: cannedOutput))
      exit \(exitCode)
      """
    do {
      try script.write(to: stub, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o755)],
        ofItemAtPath: stub.path
      )
    } catch {
      #expect(Bool(false), "could not write keyscan stub: \(error)")
    }
    return stub
  }

  private static func printfScript(for output: String) -> String {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
    guard !lines.isEmpty else { return ":" }
    return "printf '%s\\n' " + lines.map { shellSingleQuote(String($0)) }.joined(separator: " ")
  }

  private static func shellSingleQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func makeKnownHostsPath() -> URL {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-knownhosts-\(UUID().uuidString)", isDirectory: true)
    return tmpDir.appendingPathComponent("known_hosts", isDirectory: false)
  }

  // MARK: - Tests

  @Test
  func testPopulateKnownHostsWritesScannedKeysToEmptyFile() async throws {
    // Realistic ssh-keyscan output: one or two `<host> <type> <base64>`
    // lines plus a comment line that should be ignored.
    let keyscanOutput = """
      # 192.168.64.9:22 SSH-2.0-OpenSSH_9.6
      192.168.64.9 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKE_KEY_DATA_HERE
      192.168.64.9 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoFAKEECDSAKEYDATA
      """
    let keyscan = makeFakeKeyscan(cannedOutput: keyscanOutput)
    let knownHosts = makeKnownHostsPath()

    let result = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: "192.168.64.9",
      knownHostsFile: knownHosts.path,
      timeout: fakeKeyscanTimeout,
      sshKeyscanPath: keyscan.path
    )

    try #require(result.succeeded)
    try #require(result.entriesAppended == 2, "both non-comment lines should be appended")

    let contents = try String(contentsOf: knownHosts, encoding: .utf8)
    try #require(contents.contains("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKE_KEY_DATA_HERE"))
    try #require(contents.contains("ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoFAKEECDSAKEYDATA"))
    try #require(!contents.contains("#"), "comment lines must be filtered out")
  }

  @Test
  func testPopulateKnownHostsDoesNotDuplicateExistingEntries() async throws {
    // Pre-populate the file with one of the keys, then run keyscan
    // with output containing the same key plus a new one. We expect
    // only the new key to be appended.
    let existing = "192.168.64.9 ssh-ed25519 ALREADY_PRESENT_KEY\n"
    let knownHosts = makeKnownHostsPath()
    try FileManager.default.createDirectory(
      at: knownHosts.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try existing.write(to: knownHosts, atomically: true, encoding: .utf8)

    let keyscanOutput = """
      192.168.64.9 ssh-ed25519 ALREADY_PRESENT_KEY
      192.168.64.9 ssh-rsa BRAND_NEW_RSA_KEY
      """
    let keyscan = makeFakeKeyscan(cannedOutput: keyscanOutput)

    let result = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: "192.168.64.9",
      knownHostsFile: knownHosts.path,
      timeout: fakeKeyscanTimeout,
      sshKeyscanPath: keyscan.path
    )

    try #require(result.succeeded)
    try #require(result.entriesAppended == 1, "only the new RSA line should be appended")

    let contents = try String(contentsOf: knownHosts, encoding: .utf8)
    let alreadyCount = contents.components(separatedBy: "ALREADY_PRESENT_KEY").count - 1
    try #require(alreadyCount == 1, "must not duplicate the pre-existing key")
    try #require(contents.contains("BRAND_NEW_RSA_KEY"))
  }

  @Test
  func testPopulateKnownHostsReportsSuccessButZeroAppendedWhenAllDuplicates() async throws {
    // All scanned keys are already in the file — succeed without
    // appending anything. The caller should treat this as a green
    // light to run the strict probe (the keys are present, the file
    // just didn't need to grow).
    let knownHosts = makeKnownHostsPath()
    try FileManager.default.createDirectory(
      at: knownHosts.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "192.168.64.9 ssh-ed25519 SAME_KEY\n".write(
      to: knownHosts, atomically: true, encoding: .utf8
    )

    let keyscan = makeFakeKeyscan(cannedOutput: "192.168.64.9 ssh-ed25519 SAME_KEY")

    let result = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: "192.168.64.9",
      knownHostsFile: knownHosts.path,
      timeout: fakeKeyscanTimeout,
      sshKeyscanPath: keyscan.path
    )

    try #require(result.succeeded)
    try #require(result.entriesAppended == 0)
  }

  @Test
  func testPopulateKnownHostsReturnsFailureWhenKeyscanExitsNonZero() async throws {
    let keyscan = makeFakeKeyscan(cannedOutput: "", exitCode: 1)
    let knownHosts = makeKnownHostsPath()

    let result = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: "192.168.64.9",
      knownHostsFile: knownHosts.path,
      timeout: fakeKeyscanTimeout,
      sshKeyscanPath: keyscan.path
    )

    try #require(!result.succeeded)
    try #require(result.entriesAppended == 0)
    try #require(
      !FileManager.default.fileExists(atPath: knownHosts.path),
      "must not create an empty known_hosts on failure"
    )
  }

  @Test
  func testPopulateKnownHostsCreatesParentDirectoryWhenMissing() async throws {
    // Brand-new sandbox where the parent dir doesn't exist yet. The
    // bundle's known_hosts lives under the SharedVM bundle path; on
    // a fresh install that directory may not yet have been written
    // when we call populateKnownHosts, so we have to create it.
    let knownHosts = makeKnownHostsPath()
    let keyscan = makeFakeKeyscan(
      cannedOutput: "192.168.64.9 ssh-ed25519 TEST_KEY_FOR_PARENT_CREATE"
    )

    let result = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: "192.168.64.9",
      knownHostsFile: knownHosts.path,
      timeout: fakeKeyscanTimeout,
      sshKeyscanPath: keyscan.path
    )

    try #require(result.succeeded)
    try #require(result.entriesAppended == 1)
    try #require(FileManager.default.fileExists(atPath: knownHosts.path))
    let contents = try String(contentsOf: knownHosts, encoding: .utf8)
    try #require(contents.contains("TEST_KEY_FOR_PARENT_CREATE"))
  }

  @Test
  func testPopulateKnownHostsReturnsFailureWhenKeyscanBinaryMissing() async throws {
    let result = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: "192.168.64.9",
      knownHostsFile: makeKnownHostsPath().path,
      timeout: 2,
      sshKeyscanPath: "/does/not/exist/ssh-keyscan"
    )
    try #require(!result.succeeded)
    try #require(result.entriesAppended == 0)
  }
}
