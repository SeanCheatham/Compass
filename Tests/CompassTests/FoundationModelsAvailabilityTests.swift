import Testing

@testable import Compass

struct FoundationModelsAvailabilityTests {
  @Test
  func textProviderOverride_suppliesDeterministicAvailabilityAndResponse() async throws {
    try await withMockFoundationModels(available: true, response: "mocked text") {
      #expect(FoundationModelsAvailability.isAvailable)
      let result = await FoundationModelsAvailability._streamText(prompt: "Hello")
      try #require(result == "mocked text")
    }
  }

  @Test
  func textProviderOverride_canForceUnavailable() async throws {
    try await withMockFoundationModels(available: false, response: nil) {
      #expect(!FoundationModelsAvailability.isAvailable)
      let result = await FoundationModelsAvailability._streamText(prompt: "Hello")
      try #require(result == nil)
    }
  }
}
