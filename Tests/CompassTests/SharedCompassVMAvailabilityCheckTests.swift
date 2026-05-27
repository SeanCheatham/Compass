import Foundation
import Virtualization
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMAvailabilityCheck.describe(error:)` — the mapping
/// that turns raw `VZError` codes into user-readable reason strings shown in the
/// availability banner / fallback message.
struct SharedCompassVMAvailabilityCheckTests {
  @Test func describeMapsVirtualMachineLimitExceededToUserFacingTwoGuestCapHint() {
    let nsError = NSError(
      domain: VZErrorDomain,
      code: VZError.Code.virtualMachineLimitExceeded.rawValue,
      userInfo: [NSLocalizedDescriptionKey: "limit exceeded"]
    )
    let description = SharedCompassVMAvailabilityCheck.describe(error: nsError)
    #require(!description.isEmpty)
    // The user-facing message must point the user at the 2-guest cap or a
    // recovery hint (quit other VM apps). We accept either phrasing.
    let lowercased = description.lowercased()
    let mentionsLimit =
      lowercased.contains("limit")
      || lowercased.contains("2-guest")
      || lowercased.contains("quit other vm")
    #require(
      mentionsLimit,
      "Expected user-facing limit/cap hint in: \(description)"
    )
  }

  @Test func describeReturnsNonEmptyStringForOtherVZErrorCodes() {
    let codes: [VZError.Code] = [
      .networkError,
      .invalidVirtualMachineConfiguration,
      .invalidVirtualMachineState,
      .internalError,
      .operationCancelled,
    ]
    for code in codes {
      let nsError = NSError(
        domain: VZErrorDomain,
        code: code.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "vz code \(code.rawValue)"]
      )
      let description = SharedCompassVMAvailabilityCheck.describe(error: nsError)
      #require(
        !description.isEmpty,
        "describe(error:) returned empty string for VZ code \(code.rawValue)"
      )
    }
  }

  @Test func describeFallsThroughToLocalizedDescriptionForNonVZErrors() {
    struct DummyError: LocalizedError {
      var errorDescription: String? { "compass-test-detail" }
    }
    let description = SharedCompassVMAvailabilityCheck.describe(error: DummyError())
    #require(description == "compass-test-detail")
  }

  @Test func describeFallsThroughForUnknownVZErrorCode() {
    // Pick a code that isn't one of the curated cases — the function must
    // still produce a non-empty user-facing string.
    let nsError = NSError(
      domain: VZErrorDomain,
      code: 99_999,  // not a documented VZError code
      userInfo: [NSLocalizedDescriptionKey: "unknown vz code"]
    )
    let description = SharedCompassVMAvailabilityCheck.describe(error: nsError)
    #require(!description.isEmpty)
    #require(description == "unknown vz code")
  }

  @Test func availabilityIsAvailableConvenienceFlag() {
    #require(SharedCompassVMAvailability.available.isAvailable)
    #require(!SharedCompassVMAvailability.unavailable(reason: "x").isAvailable)
    #require(SharedCompassVMAvailability.unavailable(reason: "x").unavailableReason == "x")
    #require(SharedCompassVMAvailability.available.unavailableReason == nil)
  }
}