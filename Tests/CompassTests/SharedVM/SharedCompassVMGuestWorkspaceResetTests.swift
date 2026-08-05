import Foundation
import Testing

@testable import CompassCore

@Suite("SharedCompassVMGuestWorkspaceReset")
struct SharedCompassVMGuestWorkspaceResetTests {
  @Test
  func validateWorkspaceIDAcceptsCatalogStyleUUIDs() throws {
    try SharedCompassVMGuestWorkspaceReset.validateWorkspaceID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")
    try SharedCompassVMGuestWorkspaceReset.validateWorkspaceID("abc")
  }

  @Test
  func validateWorkspaceIDRejectsUnsafePaths() {
    #expect(throws: SharedCompassVMGuestWorkspaceReset.ResetError.self) {
      try SharedCompassVMGuestWorkspaceReset.validateWorkspaceID("../escape")
    }
    #expect(throws: SharedCompassVMGuestWorkspaceReset.ResetError.self) {
      try SharedCompassVMGuestWorkspaceReset.validateWorkspaceID("has space")
    }
    #expect(throws: SharedCompassVMGuestWorkspaceReset.ResetError.self) {
      try SharedCompassVMGuestWorkspaceReset.validateWorkspaceID("UPPER")
    }
  }

  @Test
  func guestWorkspaceRootPathNestsUnderRepos() {
    let entry = SharedCompassVMGuestWorkspaceCatalog.CatalogEntry(id: "deadbeef-0000-0000-0000-000000000001")
    let root = SharedCompassVMGuestWorkspaceCatalog.guestWorkspaceRootPath(forEntry: entry)
    #expect(root == "/Users/compass/Compass/Repos/deadbeef-0000-0000-0000-000000000001")
    let worktree = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
    #expect(worktree.hasPrefix(root + "/"))
    #expect(worktree.hasSuffix("/worktree"))
  }

  @Test
  func removeEntryClearsCatalogAndFileset() throws {
    let temp = FileManager.default.temporaryDirectory
      .appending(path: "compass-reset-catalog-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temp) }
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

    // Point catalog writes at a temp repo by using a fake repo with .compass storage.
    // Catalog uses CompassWorkspace.repoLocalStorageRootURL — create a minimal layout.
    let repo = temp.appending(path: "repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    let compass = CompassWorkspace.repoLocalStorageRootURL(for: repo)
    try FileManager.default.createDirectory(at: compass, withIntermediateDirectories: true)

    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    #expect(!entry.id.isEmpty)
    try SharedCompassVMGuestWorkspaceCatalog.recordSync(
      forRepoURL: repo,
      fingerprint: "abc",
      fileSet: ["Cargo.toml"]
    )
    #expect(try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo) != nil)
    #expect(try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo) == ["Cargo.toml"])

    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(forRepoURL: repo)
    #expect(try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: repo) == nil)
    #expect(try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(forRepoURL: repo) == nil)

    let rotated = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repo)
    #expect(rotated.id != entry.id)
  }
}
