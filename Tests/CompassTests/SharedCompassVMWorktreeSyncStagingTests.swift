import Foundation
import Testing

@testable import CompassCore

struct SharedCompassVMWorktreeSyncStagingTests {

  @Test
  func guestSyncStagingPathStaysUnderReposJail() {
    let worktree = "/Users/compass/Compass/Repos/abc-123/worktree"
    let staged = SharedCompassVMWorktreeSync.guestSyncStagingPath(
      nearGuestWorktreePath: worktree,
      name: "compass-sync-in-deadbeef.tar"
    )
    #expect(staged == "/Users/compass/Compass/Repos/abc-123/compass-sync-in-deadbeef.tar")
    #expect(staged.hasPrefix(SharedCompassVMGuestWorkspaceCatalog.guestReposRoot + "/"))
    #expect(!staged.hasPrefix("/tmp/"))
  }

  @Test
  func guestWorkspaceRootIsParentOfWorktree() {
    #expect(
      SharedCompassVMWorktreeSync.guestWorkspaceRoot(
        for: "/Users/compass/Compass/Repos/abc-123/worktree"
      ) == "/Users/compass/Compass/Repos/abc-123"
    )
  }
}
