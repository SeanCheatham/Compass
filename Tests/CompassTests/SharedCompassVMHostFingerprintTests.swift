import Foundation
import XCTest

@testable import Compass

/// Coverage for `SharedCompassVMHostFingerprint`. The fingerprint is
/// what `SharedCompassVMRepoWorkspaceSync` checks on every session to
/// decide whether the user edited the host repo while Compass was
/// closed — a stale fingerprint silently discards those edits, so the
/// invariants here matter for correctness, not just hygiene.
final class SharedCompassVMHostFingerprintTests: XCTestCase {

  private var repo: URL!

  override func setUpWithError() throws {
    repo = try makeTempDir()
    try XCTSkipUnless(
      initGitRepo(at: repo),
      "git is not available on this host; skipping fingerprint tests"
    )
  }

  override func tearDownWithError() throws {
    if let repo {
      try? FileManager.default.removeItem(at: repo)
    }
    repo = nil
  }

  func testFingerprintIsStableAcrossIdenticalRepos() throws {
    try writeFile("a.swift", contents: "hello")
    try writeFile("docs/b.md", contents: "# hi")

    let first = try SharedCompassVMHostFingerprint.compute(at: repo)
    let second = try SharedCompassVMHostFingerprint.compute(at: repo)

    XCTAssertEqual(first.fingerprint, second.fingerprint)
    XCTAssertEqual(first.fileSet, second.fileSet)
    XCTAssertEqual(first.fileSet, ["a.swift", "docs/b.md"])
  }

  func testFingerprintChangesWhenContentChanges() throws {
    try writeFile("a.swift", contents: "v1")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    try writeFile("a.swift", contents: "v2")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    XCTAssertNotEqual(before.fingerprint, after.fingerprint)
    XCTAssertEqual(before.fileSet, after.fileSet, "Same paths, content-only change")
  }

  func testFingerprintChangesWhenFileAdded() throws {
    try writeFile("a.swift", contents: "x")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    try writeFile("b.swift", contents: "y")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    XCTAssertNotEqual(before.fingerprint, after.fingerprint)
    XCTAssertEqual(after.fileSet, ["a.swift", "b.swift"])
  }

  func testFingerprintRespectsGitignore() throws {
    try writeFile("a.swift", contents: "x")
    try writeFile(".gitignore", contents: "secret.env\n")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    // An ignored file should not affect the fingerprint — otherwise
    // every `.env` tweak would needlessly invalidate the guest copy.
    try writeFile("secret.env", contents: "TOKEN=abc")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    XCTAssertEqual(before.fingerprint, after.fingerprint)
    XCTAssertFalse(after.fileSet.contains("secret.env"))
  }

  func testFingerprintCoversUntrackedNotIgnoredFiles() throws {
    try writeFile("a.swift", contents: "x")
    let before = try SharedCompassVMHostFingerprint.compute(at: repo)

    // No .gitignore mentions it, so this untracked file should count
    // — it's exactly the kind of edit a user makes between sessions
    // that we need to push to the guest.
    try writeFile("scratch.swift", contents: "tmp")
    let after = try SharedCompassVMHostFingerprint.compute(at: repo)

    XCTAssertNotEqual(before.fingerprint, after.fingerprint)
    XCTAssertTrue(after.fileSet.contains("scratch.swift"))
  }

  // MARK: - Helpers

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "compass-fingerprint-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

  private func initGitRepo(at url: URL) -> Bool {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = [
      "-lc",
      "git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init",
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
