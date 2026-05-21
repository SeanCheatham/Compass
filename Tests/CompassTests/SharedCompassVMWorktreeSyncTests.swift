import Foundation
@testable import Compass
import XCTest

/// Coverage for `SharedCompassVMWorktreeSync.guestWorktreePath` — the
/// host worktree → guest worktree mapping is what wires every Develop
/// iteration to the right copy in the guest, so getting it wrong is
/// not a soft failure.
final class SharedCompassVMWorktreeSyncTests: XCTestCase {
    func testGuestPathMapsHostWorktreeIntoGuestWorkspacesRoot() {
        let host = URL(fileURLWithPath: "/Users/dev/Library/Caches/Compass/Worktrees/dev-AAA/worktree")
        let root = URL(fileURLWithPath: "/Users/dev/Library/Caches/Compass/Worktrees")
        let guest = SharedCompassVMWorktreeSync.guestWorktreePath(
            forHostURL: host,
            hostWorkspacesRootURL: root
        )
        XCTAssertEqual(guest, "/Users/compass/Compass/Worktrees/dev-AAA/worktree")
    }

    func testGuestPathHandlesHostRootItself() {
        let root = URL(fileURLWithPath: "/Users/dev/Library/Caches/Compass/Worktrees")
        let guest = SharedCompassVMWorktreeSync.guestWorktreePath(
            forHostURL: root,
            hostWorkspacesRootURL: root
        )
        XCTAssertEqual(guest, "/Users/compass/Compass/Worktrees")
    }

    func testGuestPathReturnsNilForHostUrlOutsideRoot() {
        let host = URL(fileURLWithPath: "/Users/dev/other-place/worktree")
        let root = URL(fileURLWithPath: "/Users/dev/Library/Caches/Compass/Worktrees")
        XCTAssertNil(SharedCompassVMWorktreeSync.guestWorktreePath(
            forHostURL: host,
            hostWorkspacesRootURL: root
        ))
    }

    func testGuestPathHandlesTrailingSlashOnRoot() {
        let host = URL(fileURLWithPath: "/Users/dev/Library/Caches/Compass/Worktrees/dev-BBB/worktree")
        let root = URL(fileURLWithPath: "/Users/dev/Library/Caches/Compass/Worktrees/")
        XCTAssertEqual(
            SharedCompassVMWorktreeSync.guestWorktreePath(forHostURL: host, hostWorkspacesRootURL: root),
            "/Users/compass/Compass/Worktrees/dev-BBB/worktree"
        )
    }

    func testGuestWorktreesRootMatchesFirstBootStagedPath() {
        // The first-boot script creates /Users/compass/Compass/Worktrees;
        // diverging the two constants would silently break sync on every
        // new VM. Pin them together.
        XCTAssertEqual(SharedCompassVMWorktreeSync.guestWorktreesRoot, "/Users/compass/Compass/Worktrees")
    }
}
