import Foundation
import Testing

@testable import Compass

/// Coverage for the per-repo guest workspace catalog. The catalog is the
/// stable bridge between host repo URLs and guest worktree paths — every
/// agent phase routes through here when the Shared VM is selected, so a
/// silent corruption or ID rotation breaks the whole sandbox model.
struct SharedCompassVMGuestWorkspaceCatalogTests {

  @Test
  func testEnsureEntryCreatesAndPersistsFreshID() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let first = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let second = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)

    try #require(first.id == second.id, "Ensure must be idempotent")
    try #require(!first.id.isEmpty)
    try #require(
      first.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" },
      "ID must be safe for shell paths"
    )
  }

  @Test
  func testEnsureEntryPersistsToCompassDirectory() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)

    try #require(FileManager.default.fileExists(atPath: catalogURL.path))
    try #require(catalogURL.lastPathComponent == "guest-workspace.json")
    try #require(catalogURL.deletingLastPathComponent().lastPathComponent == ".compass")

    let data = try Data(contentsOf: catalogURL)
    let decoded = try JSONDecoder().decode(
      SharedCompassVMGuestWorkspaceCatalog.CatalogEntry.self,
      from: data
    )
    try #require(decoded.id == entry.id)
  }

  @Test
  func testLoadEntryReturnsNilWhenAbsent() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let loaded = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    try #require(loaded == nil)
  }

  @Test
  func testEnsureEntryDoesNotRotateAcrossCalls() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let first = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    // Simulate a re-launch by re-reading via loadEntry rather than calling ensureEntry.
    let reloaded = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    try #require(reloaded?.id == first.id)
  }

  @Test
  func testRemoveEntryWipesTheCatalogFile() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)
    try #require(FileManager.default.fileExists(atPath: catalogURL.path))

    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
    try #require(!FileManager.default.fileExists(atPath: catalogURL.path))
  }

  @Test
  func testRemoveEntryIsIdempotent() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }
    // XCTAssertNoThrow → just calls, any throw is a test failure
    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
  }

  @Test
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
    try #require(!entry.id.isEmpty)
    // Subsequent ensure reads back the new ID, not the original junk.
    let reread = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try #require(reread.id == entry.id)
  }

  @Test
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
    try #require(entry.id != "abc/../../etc")
    try #require(entry.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
  }

  // MARK: - Fingerprint + fileset persistence

  @Test
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

    let reloaded = try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    try #require(reloaded.lastSyncedHostFingerprint == "deadbeef")

    let loadedFileSet = try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo)
    )
    try #require(loadedFileSet == files)
  }

  @Test
  func testRecordSyncDoesNotRotateID() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let original = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo,
      fingerprint: "abc123",
      fileSet: ["one.swift"]
    )

    let reloaded = try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    // ID must survive — rotating it would orphan the existing guest
    // workspace directory and force a full re-push every sync.
    try #require(reloaded.id == original.id)
  }

  @Test
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

    let reloaded = try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    try #require(reloaded.lastSyncedHostFingerprint == "second")

    let loadedFileSet = try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo)
    )
    try #require(loadedFileSet == ["y.swift", "z.swift"])
  }

  @Test
  func testLegacyCatalogWithoutFingerprintFieldDecodesAsNil() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    // Hand-write the pre-fingerprint catalog shape.
    let compassDir = repo.appending(path: ".compass")
    try FileManager.default.createDirectory(at: compassDir, withIntermediateDirectories: true)
    let catalogURL = SharedCompassVMGuestWorkspaceCatalog.catalogURL(forRepoURL: repo)
    try Data(#"{"id":"00000000-0000-0000-0000-000000000001"}"#.utf8).write(to: catalogURL)

    let reloaded = try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo)
    )
    try #require(reloaded.id == "00000000-0000-0000-0000-000000000001")
    try #require(reloaded.lastSyncedHostFingerprint == nil)
  }

  @Test
  func testLoadLastSyncedFileSetReturnsNilWhenSidecarMissing() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try #require(
      try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo) == nil)
  }

  @Test
  func testRemoveEntryAlsoWipesFilesetSidecar() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    _ = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo, fingerprint: "x", fileSet: ["a.swift"]
    )
    let filesetURL = SharedCompassVMGuestWorkspaceCatalog.filesetURL(forRepoURL: repo)
    try #require(FileManager.default.fileExists(atPath: filesetURL.path))

    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
    try #require(!FileManager.default.fileExists(atPath: filesetURL.path))
  }

  // MARK: - Guest path mapping

  @Test
  func testGuestLayoutNamesCurrentMacOSAndFutureLinuxRoots() throws {
    try #require(SharedCompassVMGuestWorkspaceCatalog.guestLayout == .currentMacOS)
    try #require(
      SharedCompassVMGuestLayout.currentMacOS.reposRoot == "/Users/compass/Compass/Repos")
    try #require(SharedCompassVMGuestLayout.futureLinux.reposRoot == "/home/compass/Compass/Repos")
    try #require(
      SharedCompassVMGuestLayout.futureLinux.worktreePath(
        workspaceID: "repo-id",
        subdirectory: "worktree"
      ) == "/home/compass/Compass/Repos/repo-id/worktree"
    )
  }

  @Test
  func testGuestWorktreePathHasExpectedShape() throws {
    let entry = SharedCompassVMGuestWorkspaceCatalog.CatalogEntry(
      id: "00000000-0000-0000-0000-000000000001"
    )
    let path = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
    try #require(
      path == "/Users/compass/Compass/Repos/00000000-0000-0000-0000-000000000001/worktree"
    )
  }

  @Test
  func testEnsureGuestWorktreePathCreatesEntryOnFirstCall() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    try #require(try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo) == nil)
    let path = try SharedCompassVMGuestWorkspaceCatalog.ensureGuestWorktreePath(forRepoURL: repo)
    try #require(path.hasPrefix("/Users/compass/Compass/Repos/"))
    try #require(path.hasSuffix("/worktree"))
    try #require(try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo) != nil)
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
