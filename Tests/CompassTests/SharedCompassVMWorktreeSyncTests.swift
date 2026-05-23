import Foundation
import XCTest

@testable import Compass

/// Coverage for `SharedCompassVMWorktreeSync` security and policy
/// constants. The class itself is mostly side-effectful (vsock + tar
/// streaming), so tests pin invariants that are cheap to assert and
/// expensive to silently regress.
final class SharedCompassVMWorktreeSyncTests: XCTestCase {

  /// The allow-list backs `validateGuestPath`, which gates every
  /// `rm -rf` the sync script runs against the guest. Locking the
  /// contents down here is a tripwire against future "let's add a
  /// new sync root" changes that forget to extend the security
  /// boundary along with them.
  func testAllowedGuestPathPrefixesAreOnlyTheCatalogRoot() {
    XCTAssertEqual(
      SharedCompassVMWorktreeSync.allowedGuestPathPrefixes,
      [SharedCompassVMGuestWorkspaceCatalog.guestReposRoot]
    )
  }
}
