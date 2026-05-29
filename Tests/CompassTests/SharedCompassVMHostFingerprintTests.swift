import Foundation
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMHostFingerprint`. The fingerprint is
/// what `SharedCompassVMRepoWorkspaceSync` checks on every session to
/// decide whether the user edited the host repo while Compass was
/// closed — a stale fingerprint silently discards those edits, so the
/// invariants here matter for correctness, not just hygiene.
final class SharedCompassVMHostFingerprintTests {

  private let repo: URL

  init() throws {
    repo = try Self.makeTempDir()
    // Skip this test if git isn't available on this host
    try #require(
      Self.initGitRepo(at: repo), "git is not available on this host; skipping fingerprint tests")
  }

  deinit {
    try? FileManager.default.removeItem(at: repo)
  }

  @Test
  func testFingerprintIsStableAcrossIdenticalRepos() throws {
    try writeFile("a.swift", contents: "hello")
    try writeFile("docs/b.md", contents: "# hi")

    let first = try SharedCompassVMHostFingerprint.compute(at: repo)
    let second = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(first.fingerprint == second.fingerprint)
    try #require(first.fileSet == second.fileSet)
    try #require(first.fileSet == ["a.swift", "docs/b.md"])
  }

  @Test
  func testFingerprintChangesWhenContentChanges() throws {
    try writeFile("a.swift", contents: "v1")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    try writeFile("a.swift", contents: "v2")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(before.fingerprint != after.fingerprint)
    try #require(before.fileSet == after.fileSet, "Same paths, content-only change")
  }

  @Test
  func testFingerprintChangesWhenFileAdded() throws {
    try writeFile("a.swift", contents: "x")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    try writeFile("b.swift", contents: "y")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(before.fingerprint != after.fingerprint)
    try #require(after.fileSet == ["a.swift", "b.swift"])
  }

  @Test
  func testFingerprintRespectsGitignore() throws {
    try writeFile("a.swift", contents: "x")
    try writeFile(".gitignore", contents: "secret.env\n")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    try writeFile("secret.env", contents: "TOKEN=abc")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(before.fingerprint == after.fingerprint)
    try #require(!after.fileSet.contains("secret.env"))
  }

  @Test
  func testFingerprintCoversUntrackedNotIgnoredFiles() throws {
    try writeFile("a.swift", contents: "x")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    try writeFile("scratch.swift", contents: "tmp")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(before.fingerprint != after.fingerprint)
    try #require(after.fileSet.contains("scratch.swift"))
  }

  @Test
  func testFingerprintHashesSymlinkByTarget() throws {
    try writeFile("a.swift", contents: "x")
    let targetDir = repo.appendingPathComponent("payload")
    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: repo.appendingPathComponent("link").path,
      withDestinationPath: "payload"
    )

    let result = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(result.fileSet.contains("link"))
  }

  @Test
  func testFingerprintExcludesBuildArtifactsEvenWithoutGitignore() throws {
    try writeFile("a.swift", contents: "x")
    let artifact = repo.appendingPathComponent(".build/debug/App.swift")
    try FileManager.default.createDirectory(
      at: artifact.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "binary".write(to: artifact, atomically: true, encoding: .utf8)

    let result = try SharedCompassVMHostFingerprint.compute(at: repo)

    try #require(result.fileSet == ["a.swift"])
  }

  // MARK: - Helpers

  private static func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(
        path: "compass-fingerprint-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeFile(_ relative: String, contents: String) throws {
    let url = repo.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func initGitRepo(at url: URL) -> Bool {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = [
      "-lc",
      "git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init && git branch -M main",
    ]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }
}
