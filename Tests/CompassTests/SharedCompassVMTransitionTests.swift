import XCTest

@testable import Compass

/// Tests `SharedCompassVM.isLegalTransition(from:to:)`, the legal-edge
/// table that gates every `readiness` change. The transition chokepoint
/// itself is fileprivate; this suite exercises the pure-function side so
/// the matrix can be audited without standing up a live VM.
@MainActor
final class SharedCompassVMTransitionTests: XCTestCase {
  // MARK: - Absorbing / re-enterable states

  func testCanTransitionToErrorFromAnyState() {
    for state in Self.allRepresentativeStates {
      XCTAssertTrue(
        SharedCompassVM.isLegalTransition(from: state, to: .error(detail: "boom")),
        "every state must be able to transition to .error; failed on \(state)"
      )
    }
  }

  func testCanTransitionToUnavailableFromAnyState() {
    for state in Self.allRepresentativeStates {
      XCTAssertTrue(
        SharedCompassVM.isLegalTransition(from: state, to: .unavailable(reason: "n/a")),
        "every state must be able to transition to .unavailable; failed on \(state)"
      )
    }
  }

  func testCanTransitionToNotProvisionedFromAnyState() {
    for state in Self.allRepresentativeStates {
      XCTAssertTrue(
        SharedCompassVM.isLegalTransition(from: state, to: .notProvisioned),
        "every state must be able to reset to .notProvisioned; failed on \(state)"
      )
    }
  }

  // MARK: - Happy-path forward progress

  func testNormalProvisioningChainIsLegal() {
    let chain: [SharedCompassVMReadiness] = [
      .notProvisioned,
      .downloadingIPSW(fractionCompleted: 0),
      .installing(fractionCompleted: 0),
      .guestPrepping,
      .provisioningDevTools(fractionCompleted: 0),
      .ready(sshDestination: "compass@10.0.0.5"),
    ]
    for (from, to) in zip(chain, chain.dropFirst()) {
      XCTAssertTrue(
        SharedCompassVM.isLegalTransition(from: from, to: to),
        "expected \(from) → \(to) to be legal in the happy path"
      )
    }
  }

  // MARK: - Progress-bearing self-edges

  func testProgressBearingStatesAcceptFractionUpdates() {
    XCTAssertTrue(
      SharedCompassVM.isLegalTransition(
        from: .downloadingIPSW(fractionCompleted: 0.1),
        to: .downloadingIPSW(fractionCompleted: 0.5)
      )
    )
    XCTAssertTrue(
      SharedCompassVM.isLegalTransition(
        from: .installing(fractionCompleted: 0.3),
        to: .installing(fractionCompleted: 0.7)
      )
    )
    XCTAssertTrue(
      SharedCompassVM.isLegalTransition(
        from: .provisioningDevTools(fractionCompleted: 0),
        to: .provisioningDevTools(fractionCompleted: 0.8)
      )
    )
  }

  // MARK: - Illegal forward jumps

  func testCannotJumpFromNotProvisionedDirectlyToError() {
    // .error / .unavailable / .notProvisioned themselves are always
    // legal — they're handled by the absorbing-state shortcut.  Make
    // sure a real forward jump that skips a required stage is rejected.
    XCTAssertFalse(
      SharedCompassVM.isLegalTransition(
        from: .downloadingIPSW(fractionCompleted: 0),
        to: .ready(sshDestination: "x")
      ),
      "downloadingIPSW → ready bypasses installing/prepping/dev-tools and should be rejected"
    )
  }

  func testCannotMoveBackwardsAlongTheChain() {
    XCTAssertFalse(
      SharedCompassVM.isLegalTransition(
        from: .installing(fractionCompleted: 0),
        to: .downloadingIPSW(fractionCompleted: 0)
      ),
      "installing → downloadingIPSW reverses progress and should be rejected"
    )
    XCTAssertFalse(
      SharedCompassVM.isLegalTransition(
        from: .provisioningDevTools(fractionCompleted: 0),
        to: .installing(fractionCompleted: 0)
      )
    )
  }

  func testUnavailableIsAbsorbingExceptForReset() {
    // .unavailable is the "this Mac can't host the VM" terminal state.
    // The only legal way out is the .notProvisioned reset (via the
    // absorbing-state shortcut).
    let unavailable = SharedCompassVMReadiness.unavailable(reason: "no virt")
    XCTAssertFalse(
      SharedCompassVM.isLegalTransition(
        from: unavailable,
        to: .downloadingIPSW(fractionCompleted: 0)
      ),
      "unavailable should not transition forward without resetting first"
    )
    XCTAssertTrue(
      SharedCompassVM.isLegalTransition(
        from: unavailable,
        to: .notProvisioned
      ),
      "unavailable must allow a hard reset to .notProvisioned"
    )
  }

  // MARK: - Ready → re-warm

  func testReadyCanRewarmIntoGuestPreppingOrDevTools() {
    let ready = SharedCompassVMReadiness.ready(sshDestination: "compass@10.0.0.5")
    XCTAssertTrue(
      SharedCompassVM.isLegalTransition(from: ready, to: .guestPrepping))
    XCTAssertTrue(
      SharedCompassVM.isLegalTransition(
        from: ready, to: .provisioningDevTools(fractionCompleted: 0)))
  }

  // MARK: - Same-state nudges

  func testSameStateIsAlwaysLegal() {
    for state in Self.allRepresentativeStates {
      XCTAssertTrue(
        SharedCompassVM.isLegalTransition(from: state, to: state),
        "same-state is always legal; failed on \(state)"
      )
    }
  }

  // MARK: - Fixture

  private static let allRepresentativeStates: [SharedCompassVMReadiness] = [
    .unavailable(reason: "no virt"),
    .notProvisioned,
    .downloadingIPSW(fractionCompleted: 0),
    .installing(fractionCompleted: 0),
    .guestPrepping,
    .provisioningDevTools(fractionCompleted: 0),
    .ready(sshDestination: "compass@10.0.0.5"),
    .error(detail: "boom"),
  ]
}
