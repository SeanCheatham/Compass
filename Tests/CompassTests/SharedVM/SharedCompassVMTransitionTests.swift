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
      .stopped,
      .starting,
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

  @MainActor @Test
  func stoppedFoldsLiveStatesAndReentersForwardStates() {
    // `stop()` folds any live state to `.stopped`; the bundle on disk is
    // untouched.
    for from in [
      SharedCompassVMReadiness.ready(sshDestination: "compass@192.168.66.2"),
      .guestPrepping,
      .provisioningDevTools(fractionCompleted: 0.5),
      .downloadingIPSW(fractionCompleted: 0.5),
      .installing(fractionCompleted: 0.5),
      .starting,
    ] {
      #expect(
        SharedCompassVM.isLegalTransition(from: from, to: .stopped),
        "expected \(from) → .stopped to be legal"
      )
    }
    // A stopped VM re-enters whichever forward state the persisted
    // provision step dictates on the next `start()` (or re-provision).
    for next in [
      SharedCompassVMReadiness.guestPrepping,
      .provisioningDevTools(fractionCompleted: 0),
      .ready(sshDestination: "compass@192.168.66.2"),
      .downloadingIPSW(fractionCompleted: 0),
      .installing(fractionCompleted: 0),
      .starting,
    ] {
      #expect(
        SharedCompassVM.isLegalTransition(from: .stopped, to: next),
        "expected .stopped → \(next) to be legal"
      )
    }
    // Stopping is a no-op from states that already describe a
    // not-running VM.
    #expect(!SharedCompassVM.isLegalTransition(from: .notProvisioned, to: .stopped))
    #expect(!SharedCompassVM.isLegalTransition(from: .unavailable(reason: "x"), to: .stopped))
  }

  @MainActor @Test
  func startingCoversPostBootSSHPoll() {
    #expect(SharedCompassVM.isLegalTransition(from: .stopped, to: .starting))
    #expect(
      SharedCompassVM.isLegalTransition(
        from: .starting, to: .ready(sshDestination: "compass@192.168.66.2")))
    #expect(SharedCompassVM.isLegalTransition(from: .starting, to: .error(detail: "ssh down")))
    #expect(SharedCompassVM.isLegalTransition(from: .starting, to: .stopped))
    // A live ready guest must not jump to starting without stop/start.
    #expect(
      !SharedCompassVM.isLegalTransition(
        from: .ready(sshDestination: "compass@192.168.66.2"), to: .starting))
  }
}
