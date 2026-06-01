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

  @Test func testEmptyStoreDefaultsToFoundationModelsForText() throws {
    let store = makeStore(environment: [:])
    let settings = store.load()
    try #require(settings.textProvider == .appleFoundationModels)
    try #require(settings.apiKey == "")
    try #require(settings.model == "")
    try #require(settings.planModelOverride == nil)
    try #require(settings.webSearchAssignment == nil)
    try #require(settings.imageUnderstandingAssignment == nil)
    try #require(settings.imageAssignment == nil)
    try #require(settings.audioAssignment == nil)
    try #require(settings.videoAssignment == nil)
  }

  @Test func testEnvVarsSeedTheMinimaxCellWhenAPIKeyIsPresent() throws {
    let store = makeStore(environment: [
      "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
      "COMPASS_AGENT_API_KEY": "env-key",
      "COMPASS_AGENT_MODEL": "env-model",
      "COMPASS_AGENT_MODEL_PLAN": "env-plan",
    ])
    // Switch text to MiniMax explicitly so the env vars apply.
    store.setSelectedProvider(.minimaxToken, for: .text)
    let settings = store.load()
    try #require(settings.textProvider == .minimaxToken)
    try #require(settings.baseURL.absoluteString == "https://example.test/v1")
    try #require(settings.apiKey == "env-key")
    try #require(settings.model == "env-model")
    try #require(settings.planModelOverride == "env-plan")
  }

  // MARK: - Cell setters

  @Test func testCellModelPersistsAndRoundTrips() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    store.setCellModel("gpt-5", capability: .text, provider: .openAI)
    let settings = store.load()
    try #require(settings.textProvider == .openAI)
    try #require(settings.model == "gpt-5")
  }

  @Test func testMiniMaxTextModelVersionPersistsAndResizesContextWindow() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    try #require(store.load().model == MiniMaxTextModelVersion.m27.modelIdentifier)
    try #require(store.load().contextWindowTokens == 200_000)

    store.setCellModel(
      MiniMaxTextModelVersion.m3.modelIdentifier,
      capability: .text,
      provider: .minimaxToken
    )
    let m3Settings = store.load()
    try #require(m3Settings.model == MiniMaxTextModelVersion.m3.modelIdentifier)
    try #require(m3Settings.contextWindowTokens == 1_000_000)

    store.setCellModel(
      MiniMaxTextModelVersion.m27.modelIdentifier,
      capability: .text,
      provider: .minimaxToken
    )
    let m27Settings = store.load()
    try #require(m27Settings.model == MiniMaxTextModelVersion.m27.modelIdentifier)
    try #require(m27Settings.contextWindowTokens == 200_000)
  }

  @Test func testCellAPIKeyRoundTripsThroughSecretStorage() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.openAI, for: .text)
    try store.setCellAPIKey("sk-abc", capability: .text, provider: .openAI)
    try #require(store.load().apiKey == "sk-abc")
    let direct = try secrets.read(
      service: AgentSettingsStore.secretService,
      account: AgentSettingsStore.secretAccount(for: .text, provider: .openAI)
    )
    try #require(direct == "sk-abc")
  }

  @Test func testCellAPIKeysAreIsolatedAcrossCapabilities() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    store.setSelectedProvider(.minimaxToken, for: .image)
    try store.setCellAPIKey("text-mm-key", capability: .text, provider: .minimaxToken)
    try store.setCellAPIKey("image-mm-key", capability: .image, provider: .minimaxToken)
    let settings = store.load()
    try #require(settings.apiKey == "text-mm-key")
    try #require(settings.imageAssignment?.apiKey == "image-mm-key")
  }

  @Test func testPhaseOverridesPersistPerProvider() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .text)
    store.setTextPhaseOverride(.plan, "plan-x", provider: .minimaxToken)
    store.setTextPhaseOverride(.critic, "critic-x", provider: .minimaxToken)
    let settings = store.load()
    try #require(settings.planModelOverride == "plan-x")
    try #require(settings.criticModelOverride == "critic-x")
    // Switching text to OpenAI: its phase overrides start empty,
    // MiniMax's overrides remain untouched.
    store.setSelectedProvider(.openAI, for: .text)
    let openAISettings = store.load()
    try #require(openAISettings.planModelOverride == nil)
    store.setSelectedProvider(.minimaxToken, for: .text)
    try #require(store.load().planModelOverride == "plan-x")
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
    // Web Search → MiniMax Token
    store.setSelectedProvider(.minimaxToken, for: .webSearch)
    try store.setCellAPIKey("mm-search", capability: .webSearch, provider: .minimaxToken)
    // Image Understanding → MiniMax Token
    store.setSelectedProvider(.minimaxToken, for: .imageUnderstanding)
    try store.setCellAPIKey("mm-vision", capability: .imageUnderstanding, provider: .minimaxToken)
    // Audio/Video stay None.

    let settings = store.load()
    try #require(settings.textProvider == .openAI)
    try #require(settings.apiKey == "sk-text")
    try #require(settings.model == "gpt-5")
    try #require(settings.webSearchAssignment?.provider == .minimaxToken)
    try #require(settings.webSearchAssignment?.apiKey == "mm-search")
    try #require(settings.webSearchAssignment?.model == "")
    try #require(settings.imageUnderstandingAssignment?.provider == .minimaxToken)
    try #require(settings.imageUnderstandingAssignment?.apiKey == "mm-vision")
    try #require(settings.imageUnderstandingAssignment?.model == "")
    try #require(settings.imageAssignment?.provider == .minimaxToken)
    try #require(settings.imageAssignment?.apiKey == "mm-image")
    try #require(settings.imageAssignment?.model == "image-99")
    try #require(settings.audioAssignment == nil)
    try #require(settings.videoAssignment == nil)
  }

  @Test func testNoneSentinelClearsAnOptionalCapability() throws {
    let store = makeStore(environment: [:])
    store.setSelectedProvider(.minimaxToken, for: .image)
    try #require(store.load().imageAssignment?.provider == .minimaxToken)
    store.setSelectedProvider(nil, for: .image)
    try #require(store.load().imageAssignment == nil)
  }

  @Test func testFoundationModelsCellNeedsNoCredentials() throws {
    let store = makeStore(environment: [:])
    try #require(store.load().textProvider == .appleFoundationModels)
    try #require(store.load().apiKey == "")
    try #require(store.load().model == "")
  }

  // MARK: - Per-provider context window

  @Test func testContextWindowMatchesActiveTextProvider() throws {
    let store = makeStore(environment: [:])
    try #require(
      store.load().contextWindowTokens
        == AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
    store.setSelectedProvider(.minimaxToken, for: .text)
    try #require(
      store.load().contextWindowTokens
        == AgentProviderKind.minimaxToken.defaultTextContextWindowTokens)
    store.setSelectedProvider(.openAI, for: .text)
    try #require(
      store.load().contextWindowTokens == AgentProviderKind.openAI.defaultTextContextWindowTokens)
  }

  @Test func testContextWindowEnvOverrideAppliesAcrossProviders() throws {
    let store = makeStore(environment: [
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "262144"
    ])
    try #require(store.load().contextWindowTokens == 262_144)
    store.setSelectedProvider(.minimaxToken, for: .text)
    try #require(
      store.load().contextWindowTokens == 262_144,
      "env override beats the provider's built-in ceiling")
  }

  @Test func testContextWindowEnvZeroDisablesCompactionRegardlessOfProvider() throws {
    let store = makeStore(environment: [
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "0"
    ])
    store.setSelectedProvider(.openAI, for: .text)
    try #require(store.load().contextWindowTokens == 0)
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
