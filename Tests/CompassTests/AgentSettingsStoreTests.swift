import Foundation
import XCTest

@testable import Compass

final class AgentSettingsStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!
  private var secrets: InMemoryAgentSecretStorage!

  override func setUpWithError() throws {
    suiteName = "compass.test.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    for key in AgentSettingsStore.Key.allCases {
      defaults.removeObject(forKey: key.rawValue)
    }
    secrets = InMemoryAgentSecretStorage()
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    secrets = nil
  }

  // MARK: - Defaults

  func testEmptyStoreDefaultsToFoundationModelsForText() {
    let store = makeStore(environment: [:])
    let settings = store.load()
    XCTAssertEqual(settings.textProvider, .appleFoundationModels)
    XCTAssertEqual(settings.apiKey, "")
    XCTAssertEqual(settings.model, "")
    XCTAssertNil(settings.planModelOverride)
    XCTAssertNil(settings.imageAssignment)
    XCTAssertNil(settings.audioAssignment)
    XCTAssertNil(settings.videoAssignment)
  }

  func testEnvVarsSeedTheMinimaxCellWhenAPIKeyIsPresent() {
    let store = makeStore(environment: [
      "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
      "COMPASS_AGENT_API_KEY": "env-key",
      "COMPASS_AGENT_MODEL": "env-model",
      "COMPASS_AGENT_MODEL_PLAN": "env-plan",
    ])
    // Switch text to MiniMax explicitly so the env vars apply.
    store.setSelectedProvider(.minimaxToken, for: .text)
    let settings = store.load()
    XCTAssertEqual(settings.textProvider, .minimaxToken)
    XCTAssertEqual(settings.baseURL.absoluteString, "https://example.test/v1")
    XCTAssertEqual(settings.apiKey, "env-key")
    XCTAssertEqual(settings.model, "env-model")
    XCTAssertEqual(settings.planModelOverride, "env-plan")
  }

  // MARK: - Cell setters

  func testCellModelPersistsAndRoundTrips() {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    store.setCellModel("gpt-5", capability: .text, provider: .openAI)
    let settings = store.load()
    XCTAssertEqual(settings.textProvider, .openAI)
    XCTAssertEqual(settings.model, "gpt-5")
  }

  func testCellAPIKeyRoundTripsThroughSecretStorage() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    try store.setCellAPIKey("sk-abc", capability: .text, provider: .openAI)
    XCTAssertEqual(store.load().apiKey, "sk-abc")
    let direct = try secrets.read(
      service: AgentSettingsStore.secretService,
      account: AgentSettingsStore.secretAccount(for: .text, provider: .openAI)
    )
    XCTAssertEqual(direct, "sk-abc")
  }

  func testCellAPIKeysAreIsolatedAcrossCapabilities() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    store.setSelectedProvider(.minimaxToken, for: .image)
    try store.setCellAPIKey("text-mm-key", capability: .text, provider: .minimaxToken)
    try store.setCellAPIKey("image-mm-key", capability: .image, provider: .minimaxToken)
    let settings = store.load()
    XCTAssertEqual(settings.apiKey, "text-mm-key")
    XCTAssertEqual(settings.imageAssignment?.apiKey, "image-mm-key")
  }

  func testPhaseOverridesPersistPerProvider() {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    store.setTextPhaseOverride(.plan, "plan-x", provider: .minimaxToken)
    store.setTextPhaseOverride(.critic, "critic-x", provider: .minimaxToken)
    let settings = store.load()
    XCTAssertEqual(settings.planModelOverride, "plan-x")
    XCTAssertEqual(settings.criticModelOverride, "critic-x")
    // Switching text to OpenAI: its phase overrides start empty,
    // MiniMax's overrides remain untouched.
    store.setSelectedProvider(.openAI, for: .text)
    let openAISettings = store.load()
    XCTAssertNil(openAISettings.planModelOverride)
    store.setSelectedProvider(.minimaxToken, for: .text)
    XCTAssertEqual(store.load().planModelOverride, "plan-x")
  }

  // MARK: - Capability mix-and-match

  func testMixedCapabilityAssignmentsCoexist() throws {
    let store = makeStore(environment: [:])
    // Text → OpenAI API
    store.setSelectedProvider(.openAI, for: .text)
    try store.setCellAPIKey("sk-text", capability: .text, provider: .openAI)
    store.setCellModel("gpt-5", capability: .text, provider: .openAI)
    // Image → MiniMax Token
    store.setSelectedProvider(.minimaxToken, for: .image)
    try store.setCellAPIKey("mm-image", capability: .image, provider: .minimaxToken)
    store.setCellModel("image-99", capability: .image, provider: .minimaxToken)
    // Audio/Video stay None.

    let settings = store.load()
    XCTAssertEqual(settings.textProvider, .openAI)
    XCTAssertEqual(settings.apiKey, "sk-text")
    XCTAssertEqual(settings.model, "gpt-5")
    XCTAssertEqual(settings.imageAssignment?.provider, .minimaxToken)
    XCTAssertEqual(settings.imageAssignment?.apiKey, "mm-image")
    XCTAssertEqual(settings.imageAssignment?.model, "image-99")
    XCTAssertNil(settings.audioAssignment)
    XCTAssertNil(settings.videoAssignment)
  }

  func testNoneSentinelClearsAnOptionalCapability() {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .image)
    XCTAssertEqual(store.load().imageAssignment?.provider, .minimaxToken)
    store.setSelectedProvider(nil, for: .image)
    XCTAssertNil(store.load().imageAssignment)
  }

  func testFoundationModelsCellNeedsNoCredentials() {
    let store = makeStore(environment: [:])
    XCTAssertEqual(store.load().textProvider, .appleFoundationModels)
    XCTAssertEqual(store.load().apiKey, "")
    XCTAssertEqual(store.load().model, "")
  }

  // MARK: - Legacy fallback

  func testV0LegacyKeysSurfaceAsTextMinimaxCellWhenSelected() throws {
    // Seed pre-provider-abstraction keys.
    defaults.set("https://legacy.example/v1", forKey: "compass.agent.baseURL")
    defaults.set("legacy-model", forKey: "compass.agent.model")
    defaults.set("legacy-plan", forKey: "compass.agent.model.plan")
    try secrets.write(
      "legacy-key",
      service: AgentSettingsStore.secretService,
      account: AgentSettingsStore.legacySecretAccount)

    let store = makeStore(environment: [:])
    // v0 users only had MiniMax — picking it should resurrect their config.
    store.setSelectedProvider(.minimaxToken, for: .text)
    let settings = store.load()
    XCTAssertEqual(settings.textProvider, .minimaxToken)
    XCTAssertEqual(settings.baseURL.absoluteString, "https://legacy.example/v1")
    XCTAssertEqual(settings.apiKey, "legacy-key")
    XCTAssertEqual(settings.model, "legacy-model")
    XCTAssertEqual(settings.planModelOverride, "legacy-plan")
  }

  func testV1LegacyProviderKeysSurfaceAsTextCellWhenSelected() throws {
    // The intermediate per-provider scheme that briefly shipped.
    defaults.set(
      "https://v1.example/v1",
      forKey: "compass.provider.openAI.baseURL")
    defaults.set(
      "v1-text-model",
      forKey: "compass.provider.openAI.text.model")
    try secrets.write(
      "v1-key",
      service: AgentSettingsStore.secretService,
      account: AgentSettingsStore.legacyProviderSecretAccount(for: .openAI))

    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    let settings = store.load()
    XCTAssertEqual(settings.textProvider, .openAI)
    XCTAssertEqual(settings.baseURL.absoluteString, "https://v1.example/v1")
    XCTAssertEqual(settings.apiKey, "v1-key")
    XCTAssertEqual(settings.model, "v1-text-model")
  }

  // MARK: - Helpers

  private func makeStore(environment: [String: String]) -> AgentSettingsStore {
    AgentSettingsStore(
      defaults: defaults,
      secrets: secrets,
      environment: environment
    )
  }
}
