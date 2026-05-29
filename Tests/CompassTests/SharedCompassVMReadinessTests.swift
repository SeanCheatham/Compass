import Foundation
import Testing

@testable import Compass

/// Coverage for the `isReady` / `isUnavailable` convenience predicates on
/// `SharedCompassVMReadiness`. These ride hot paths in routing decisions
/// (Phase 3 fallback), so a wrongly-true predicate would silently misroute.
struct SharedCompassVMReadinessTests {
  @Test func testIsReadyOnlyTrueForReadyCase() throws {
    try #require(SharedCompassVMReadiness.ready(sshDestination: "compass@10.0.0.42").isReady)

    let notReady: [SharedCompassVMReadiness] = [
      .unavailable(reason: "no virt"),
      .notProvisioned,
      .downloadingIPSW(fractionCompleted: 0.5),
      .installing(fractionCompleted: 0.5),
      .guestPrepping,
      .provisioningDevTools(fractionCompleted: 0.5),
      .error(detail: "kaboom"),
    ]
    for readiness in notReady {
      try #require(!readiness.isReady)
    }
  }

  @Test func testIsUnavailableOnlyTrueForUnavailableCase() throws {
    try #require(SharedCompassVMReadiness.unavailable(reason: "no virt").isUnavailable)

    let notUnavailable: [SharedCompassVMReadiness] = [
      .notProvisioned,
      .downloadingIPSW(fractionCompleted: 0),
      .installing(fractionCompleted: 1.0),
      .guestPrepping,
      .provisioningDevTools(fractionCompleted: 0.0),
      .ready(sshDestination: "compass@host"),
      .error(detail: "kaboom"),
    ]
    for readiness in notUnavailable {
      try #require(!readiness.isUnavailable)
    }
  }

  @Test func testIsReadyAndIsUnavailableAreMutuallyExclusive() throws {
    // Cross-check: no single case may report both true.
    let allCases: [SharedCompassVMReadiness] = [
      .unavailable(reason: "x"),
      .notProvisioned,
      .downloadingIPSW(fractionCompleted: 0.25),
      .installing(fractionCompleted: 0.75),
      .guestPrepping,
      .provisioningDevTools(fractionCompleted: 0.5),
      .ready(sshDestination: "compass@host"),
      .error(detail: "x"),
    ]
    for readiness in allCases {
      try #require(!(readiness.isReady && readiness.isUnavailable))
    }
  }
}
