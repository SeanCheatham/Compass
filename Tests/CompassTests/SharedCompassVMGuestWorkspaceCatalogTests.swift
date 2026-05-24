import Foundation
import XCTest

@testable import Compass

/// Coverage for the per-repo guest workspace catalog. The catalog is the
/// stable bridge between host repo URLs and guest worktree paths — every
/// agent phase routes through here when the Shared VM is selected, so a
/// silent corruption or ID rotation breaks the whole sandbox model.
final class SharedCompassVMGuestWorkspaceCatalogTests: XCTestCase {

  func testEnsureEntryCreatesAndPersistsFreshID() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let first = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let second = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)

    XCTAssertEqual(first.id, second.id, "Ensure must be idempotent")
    XCTAssertFalse(first.id.isEmpty)
    XCTAssertTrue(
      first.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" },
      "ID must be safe for shell paths"
    )
  }

  func testEnsureEntryPersistsToCompassDirectory() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)

    XCTAssertTrue(FileManager.default.fileExists(atPath: catalogURL.path))
    XCTAssertEqual(catalogURL.lastPathComponent, "guest-workspace.json")
    XCTAssertEqual(catalogURL.deletingLastPathComponent().lastPathComponent, ".compass")

    let data = try Data(contentsOf: catalogURL)
    let decoded = try JSONDecoder().decode(
      SharedCompassVMGuestWorkspaceCatalog.CatalogEntry.self,
      from: data
    )
    XCTAssertEqual(decoded.id, entry.id)
  }

  func testLoadEntryReturnsNilWhenAbsent() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let loaded = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    XCTAssertNil(loaded)
  }

  func testEnsureEntryDoesNotRotateAcrossCalls() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let first = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    // Simulate a re-launch by re-reading via loadEntry rather than calling ensureEntry.
    let reloaded = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    XCTAssertEqual(reloaded?.id, first.id)
  }

  func testRemoveEntryWipesTheCatalogFile() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)
    XCTAssertTrue(FileManager.default.fileExists(atPath: catalogURL.path))

    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
    XCTAssertFalse(FileManager.default.fileExists(atPath: catalogURL.path))
  }

  func testRemoveEntryIsIdempotent() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }
    XCTAssertNoThrow(try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo))
    XCTAssertNoThrow(try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo))
  }

  func testCorruptCatalogIsTreatedAsAbsent() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let compassDir = repo.appending(path: ".compass")
    try FileManager.default.createDirectory(at: compassDir, withIntermediateDirectories: true)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)
    try Data("not json".utf8).write(to: catalogURL)

    // A corrupt file must not throw — ensureEntry treats it as
    // "needs allocation" and writes a fresh ID over the top.
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    XCTAssertFalse(entry.id.isEmpty)
    // Subsequent ensure reads back the new ID, not the original junk.
    let reread = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    XCTAssertEqual(reread.id, entry.id)
  }

  func testCatalogWithInjectionAttemptIdIsTreatedAsAbsent() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let compassDir = repo.appending(path: ".compass")
    try FileManager.default.createDirectory(at: compassDir, withIntermediateDirectories: true)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)
    try Data(#"{"id":"abc/../../etc"}"#.utf8).write(to: catalogURL)

    // Defensive: the ID becomes a shell path component in the guest.
    // Anything with a slash, dot, or other non-[a-z0-9-] char must be
    // rejected so an attacker who plants a catalog cannot pivot to
    // arbitrary guest paths.
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    XCTAssertNotEqual(entry.id, "abc/../../etc")
    XCTAssertTrue(entry.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
  }

  // MARK: - Fingerprint + fileset persistence

  func testRecordSyncStampsFingerprintAndFileset() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let files: Set<String> = ["a.swift", "src/b.txt", "README.md"]
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo,
      fingerprint: "deadbeef",
      fileSet: files
    )

    let reloaded = try XCTUnwrap(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    XCTAssertEqual(reloaded.lastSyncedHostFingerprint, "deadbeef")

    let loadedFileSet = try XCTUnwrap(
      try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo)
    )
    XCTAssertEqual(loadedFileSet, files)
  }

  func testRecordSyncDoesNotRotateID() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let original = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo,
      fingerprint: "abc123",
      fileSet: ["one.swift"]
    )

    let reloaded = try XCTUnwrap(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    // ID must survive — rotating it would orphan the existing guest
    // workspace directory and force a full re-push every sync.
    XCTAssertEqual(reloaded.id, original.id)
  }

  func testRecordSyncOverwritesPreviousValues() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo, fingerprint: "first", fileSet: ["x.swift"]
    )
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo, fingerprint: "second", fileSet: ["y.swift", "z.swift"]
    )

    let reloaded = try XCTUnwrap(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    XCTAssertEqual(reloaded.lastSyncedHostFingerprint, "second")

    let loadedFileSet = try XCTUnwrap(
      try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo)
    )
    XCTAssertEqual(loadedFileSet, ["y.swift", "z.swift"])
  }

  func testLegacyCatalogWithoutFingerprintFieldDecodesAsNil() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    // Hand-write the pre-fingerprint catalog shape.
    let compassDir = repo.appending(path: ".compass")
    try FileManager.default.createDirectory(at: compassDir, withIntermediateDirectories: true)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)
    try Data(#"{"id":"00000000-0000-0000-0000-000000000001"}"#.utf8).write(to: catalogURL)

    let reloaded = try XCTUnwrap(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    XCTAssertEqual(reloaded.id, "00000000-0000-0000-0000-000000000001")
    XCTAssertNil(reloaded.lastSyncedHostFingerprint)
  }

  func testLoadLastSyncedFileSetReturnsNilWhenSidecarMissing() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    XCTAssertNil(try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo))
  }

  func testRemoveEntryAlsoWipesFilesetSidecar() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo, fingerprint: "x", fileSet: ["a.swift"]
    )
    let filesetURL = SharedCompassVMGuestWorkspaceCatalog.filesetURL(forRepoURL: repo)
    XCTAssertTrue(FileManager.default.fileExists(atPath: filesetURL.path))

    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
    XCTAssertFalse(FileManager.default.fileExists(atPath: filesetURL.path))
  }

  // MARK: - Guest path mapping

  func testGuestWorktreePathHasExpectedShape() {
    let entry = SharedCompassVMGuestWorkspaceCatalog.CatalogEntry(
      id: "00000000-0000-0000-0000-000000000001"
    )
    let path = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
    XCTAssertEqual(
      path,
      "/Users/compass/Compass/Repos/00000000-0000-0000-0000-000000000001/worktree"
    )
  }

  func testEnsureGuestWorktreePathCreatesEntryOnFirstCall() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    XCTAssertNil(try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo))
    let path = try SharedCompassVMGuestWorkspaceCatalog.ensureGuestWorktreePath(forRepoURL: repo)
    XCTAssertTrue(path.hasPrefix("/Users/compass/Compass/Repos/"))
    XCTAssertTrue(path.hasSuffix("/worktree"))
    XCTAssertNotNil(try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo))
  }

  // MARK: - Helpers

  private func makeTempRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(
        path: "compass-guest-catalog-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
