import Foundation
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMWorktreeSync` security and policy
/// constants. The class itself is mostly side-effectful (vsock + tar
/// streaming), so tests pin invariants that are cheap to assert and
/// expensive to silently regress.
struct SharedCompassVMWorktreeSyncTests {

  /// The allow-list backs `validateGuestPath`, which gates every
  /// `rm -rf` the sync script runs against the guest. Locking the
  /// contents down here is a tripwire against future "let's add a
  /// new sync root" changes that forget to extend the security
  /// boundary along with them.
  @Test func allowedGuestPathPrefixesAreOnlyTheCatalogRoot() throws {
    try #require(
      SharedCompassVMWorktreeSync.allowedGuestPathPrefixes ==
      [SharedCompassVMGuestWorkspaceCatalog.guestReposRoot]
    )
  }

  // MARK: - Deletion scope

  /// The agent removed `b.swift`; `a.swift` is untouched. With a
  /// scope from the last push (`{a, b}`), we delete exactly `b`.
  @Test func deletionsScopedToLastPushedFileset() throws {
    let deletions = SharedCompassVMWorktreeSync.computeDeletions(
      host: ["a.swift", "b.swift"],
      guest: ["a.swift"],
      scope: ["a.swift", "b.swift"]
    )
    try #require(deletions == ["b.swift"])
  }

  /// The headline drift case: the user added `user-new.txt` on the
  /// host while Compass was closed; the agent didn't see it during
  /// the session. The deletion step must NOT touch it just because
  /// it isn't in the guest — that would clobber the user's work.
  @Test func deletionsLeaveUserAddedFilesAlone() throws {
    let deletions = SharedCompassVMWorktreeSync.computeDeletions(
      host: ["a.swift", "user-new.txt"],
      guest: ["a.swift"],
      scope: ["a.swift"]
    )
    try #require(deletions == [])
  }

  /// Belt-and-braces: a path already gone from the host shouldn't
  /// generate a spurious deletion attempt, even if it's still in the
  /// scope. (The `removeItem` call would no-op anyway, but keeping
  /// the deletion set tight makes logs easier to read.)
  @Test func deletionsRequirePresenceOnHost() throws {
    let deletions = SharedCompassVMWorktreeSync.computeDeletions(
      host: ["a.swift"],
      guest: [],
      scope: ["a.swift", "b.swift"]
    )
    try #require(deletions == ["a.swift"])
  }

  /// Legacy catalog path: no recorded scope yet, so we fall back to
  /// the original `host − guest` semantics. This keeps the first pull
  /// after upgrading from a pre-fingerprint build functional, even
  /// though the result is broader (= less protective of user files).
  @Test func nilScopeFallsBackToHostMinusGuest() throws {
    let deletions = SharedCompassVMWorktreeSync.computeDeletions(
      host: ["a.swift", "b.swift", "user-new.txt"],
      guest: ["a.swift"],
      scope: nil
    )
    try #require(deletions == ["b.swift", "user-new.txt"])
  }

  @Test func excludesSyncPathSkipsBuildArtifactTrees() throws {
    try #require(SharedCompassVMWorktreeSync.excludesSyncPath(".build"))
    try #require(SharedCompassVMWorktreeSync.excludesSyncPath(".build/debug"))
    try #require(
      SharedCompassVMWorktreeSync.excludesSyncPath(".build/arm64-apple-macosx/debug/App.swift"))
    try #require(!SharedCompassVMWorktreeSync.excludesSyncPath("Sources/App.swift"))
    try #require(!SharedCompassVMWorktreeSync.excludesSyncPath("build.gradle"))
  }
}