import Foundation
import Testing

@testable import Compass

struct AgentSettingsStoreTests: ~Copyable {
  private var defaults: UserDefaults!
  private var suiteName: String!
  private var secrets: InMemoryAgentSecretStorage!

  init() throws {
    suiteName = "compass.test.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    for key in AgentSettingsStore.Key.allCases {
      defaults.removeObject(forKey: key.rawValue)
    }
    secrets = InMemoryAgentSecretStorage()
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  // MARK: - Defaults

  @Test func testEmptyStoreDefaultsToFoundationModelsForText() {
    let store = makeStore(environment: [:])
    let settings = store.load()
    #require(settings.textProvider == .appleFoundationModels)
    #require(settings.apiKey == "")
    #require(settings.model == "")
    #require(settings.planModelOverride == nil)
    #require(settings.imageAssignment == nil)
    #require(settings.audioAssignment == nil)
    #require(settings.videoAssignment == nil)
  }

  @Test func testEnvVarsSeedTheMinimaxCellWhenAPIKeyIsPresent() {
    let store = makeStore(environment: [
      "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
      "COMPASS_AGENT_API_KEY": "env-key",
      "COMPASS_AGENT_MODEL": "env-model",
      "COMPASS_AGENT_MODEL_PLAN": "env-plan",
    ])
    // Switch text to MiniMax explicitly so the env vars apply.
    store.setSelectedProvider(.minimaxToken, for: .text)
    let settings = store.load()
    #require(settings.textProvider == .minimaxToken)
    #require(settings.baseURL.absoluteString == "https://example.test/v1")
    #require(settings.apiKey == "env-key")
    #require(settings.model == "env-model")
    #require(settings.planModelOverride == "env-plan")
  }

  // MARK: - Cell setters

  @Test func testCellModelPersistsAndRoundTrips() {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    store.setCellModel("gpt-5", capability: .text, provider: .openAI)
    let settings = store.load()
    #require(settings.textProvider == .openAI)
    #require(settings.model == "gpt-5")
  }

  @Test func testCellAPIKeyRoundTripsThroughSecretStorage() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    try store.setCellAPIKey("sk-abc", capability: .text, provider: .openAI)
    #require(store.load().apiKey == "sk-abc")
    let direct = try secrets.read(
      service: AgentSettingsStore.secretService,
      account: AgentSettingsStore.secretAccount(for: .text, provider: .openAI)
    )
    #require(direct == "sk-abc")
  }

  @Test func testCellAPIKeysAreIsolatedAcrossCapabilities() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    store.setSelectedProvider(.minimaxToken, for: .image)
    try store.setCellAPIKey("text-mm-key", capability: .text, provider: .minimaxToken)
    try store.setCellAPIKey("image-mm-key", capability: .image, provider: .minimaxToken)
    let settings = store.load()
    #require(settings.apiKey == "text-mm-key")
    #require(settings.imageAssignment?.apiKey == "image-mm-key")
  }

  @Test func testPhaseOverridesPersistPerProvider() {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    store.setTextPhaseOverride(.plan, "plan-x", provider: .minimaxToken)
    store.setTextPhaseOverride(.critic, "critic-x", provider: .minimaxToken)
    let settings = store.load()
    #require(settings.planModelOverride == "plan-x")
    #require(settings.criticModelOverride == "critic-x")
    // Switching text to OpenAI: its phase overrides start empty,
    // MiniMax's overrides remain untouched.
    store.setSelectedProvider(.openAI, for: .text)
    let openAISettings = store.load()
    #require(openAISettings.planModelOverride == nil)
    store.setSelectedProvider(.minimaxToken, for: .text)
    #require(store.load().planModelOverride == "plan-x")
  }

  // MARK: - Capability mix-and-match

  @Test func testMixedCapabilityAssignmentsCoexist() throws {
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
    #require(settings.textProvider == .openAI)
    #require(settings.apiKey == "sk-text")
    #require(settings.model == "gpt-5")
    #require(settings.imageAssignment?.provider == .minimaxToken)
    #require(settings.imageAssignment?.apiKey == "mm-image")
    #require(settings.imageAssignment?.model == "image-99")
    #require(settings.audioAssignment == nil)
    #require(settings.videoAssignment == nil)
  }

  @Test func testNoneSentinelClearsAnOptionalCapability() {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .image)
    #require(store.load().imageAssignment?.provider == .minimaxToken)
    store.setSelectedProvider(nil, for: .image)
    #require(store.load().imageAssignment == nil)
  }

  @Test func testFoundationModelsCellNeedsNoCredentials() {
    let store = makeStore(environment: [:])
    #require(store.load().textProvider == .appleFoundationModels)
    #require(store.load().apiKey == "")
    #require(store.load().model == "")
  }

  // MARK: - Per-provider context window

  @Test func testContextWindowMatchesActiveTextProvider() {
    let store = makeStore(environment: [:])
    #require(
      store.load().contextWindowTokens ==
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
    store.setSelectedProvider(.minimaxToken, for: .text)
    #require(
      store.load().contextWindowTokens ==
      AgentProviderKind.minimaxToken.defaultTextContextWindowTokens)
    store.setSelectedProvider(.openAI, for: .text)
    #require(
      store.load().contextWindowTokens ==
      AgentProviderKind.openAI.defaultTextContextWindowTokens)
  }

  @Test func testContextWindowEnvOverrideAppliesAcrossProviders() {
    let store = makeStore(environment: [
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "262144"
    ])
    #require(store.load().contextWindowTokens == 262_144)
    store.setSelectedProvider(.minimaxToken, for: .text)
    #require(
      store.load().contextWindowTokens == 262_144,
      "env override beats the provider's built-in ceiling")
  }

  @Test func testContextWindowEnvZeroDisablesCompactionRegardlessOfProvider() {
    let store = makeStore(environment: [
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "0"
    ])
    store.setSelectedProvider(.openAI, for: .text)
    #require(store.load().contextWindowTokens == 0)
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