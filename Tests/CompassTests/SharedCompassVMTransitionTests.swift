import CompassCore
import Foundation
import Testing

struct SharedCompassVMTransitionTests {
  @MainActor @Test
  func errorIsNotAbsorbingSoRetriesCanReenterForwardStates() {
    for next in [
      SharedCompassVMReadiness.guestPrepping,
      .provisioningDevTools(fractionCompleted: 0.5),
      .ready(sshDestination: "compass@192.168.66.2"),
      .downloadingIPSW(fractionCompleted: 0),
      .installing(fractionCompleted: 0),
    ] {
      #expect(
        SharedCompassVM.isLegalTransition(from: .error(detail: "boom"), to: next),
        "expected .error → \(next) to be legal"
      )
    }
  }

  @MainActor @Test
  func terminalStatesAreAlwaysEnterable() {
    let states: [SharedCompassVMReadiness] = [
      .unavailable(reason: "x"),
      .notProvisioned,
      .downloadingIPSW(fractionCompleted: 0.2),
      .installing(fractionCompleted: 0.2),
      .guestPrepping,
      .provisioningDevTools(fractionCompleted: 0.2),
      .ready(sshDestination: "compass@192.168.66.2"),
      .error(detail: "x"),
    ]
    for from in states {
      #expect(SharedCompassVM.isLegalTransition(from: from, to: .error(detail: "y")))
      #expect(SharedCompassVM.isLegalTransition(from: from, to: .notProvisioned))
      #expect(
        SharedCompassVM.isLegalTransition(from: from, to: .unavailable(reason: "y")))
    }
  }

  @MainActor @Test
  func unavailableOnlyReleasesToNotProvisioned() {
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .unavailable(reason: "x"), to: .notProvisioned))
    #expect(
      !SharedCompassVM.isLegalTransition(
        from: .unavailable(reason: "x"), to: .guestPrepping))
    #expect(
      !SharedCompassVM.isLegalTransition(
        from: .unavailable(reason: "x"), to: .ready(sshDestination: "compass@1.2.3.4")))
  }

  @MainActor @Test
  func forwardProgressFollowsTheProvisioningOrder() {
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .notProvisioned, to: .downloadingIPSW(fractionCompleted: 0)))
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .downloadingIPSW(fractionCompleted: 1), to: .installing(fractionCompleted: 0)))
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .installing(fractionCompleted: 1), to: .guestPrepping))
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .guestPrepping, to: .provisioningDevTools(fractionCompleted: 0)))
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .provisioningDevTools(fractionCompleted: 1),
        to: .ready(sshDestination: "compass@1.2.3.4")))
    // Skipping the download/install legs is allowed (cached IPSW,
    // resumed bundles).
    #expect(SharedCompassVM.isLegalTransition(from: .notProvisioned, to: .guestPrepping))
  }
}
