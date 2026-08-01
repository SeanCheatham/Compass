import Foundation
import Testing

@testable import Compass
@testable import CompassCore

@Suite("OpenAI-compatible runtime")
struct OpenAICompatibleRuntimeTests {
  @Test
  func chatCompletionsRequestEncodesExpectedKeys() throws {
    let request = OpenAIChatCompletionsRequest(
      model: "example-model",
      messages: [
        .init(role: "system", content: "sys"),
        .init(role: "user", content: "hi"),
      ],
      maxTokens: 128,
      stream: false
    )
    let data = try JSONEncoder().encode(request)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"model\":\"example-model\""))
    #expect(json.contains("\"max_tokens\":128"))
    #expect(json.contains("\"stream\":false"))
    #expect(json.contains("\"role\":\"system\""))
    #expect(json.contains("\"content\":\"sys\""))
  }

  @Test
  func endpointBuildsChatCompletionsURL() throws {
    let endpoint = OpenAICompatibleEndpoint(
      baseURL: URL(string: "https://api.example.com/v1/")!,
      apiKey: "sk-test",
      model: "m"
    )
    #expect(endpoint.isConfigured)
    #expect(
      try endpoint.chatCompletionsURL().absoluteString
        == "https://api.example.com/v1/chat/completions"
    )
  }

  @Test
  func routedRuntimePrefersCloudForPrimaryAndLocalForAssist() throws {
    let cloud = RecordingModelRuntime(name: "cloud")
    let local = RecordingModelRuntime(name: "local")
    let routed = RoutedModelRuntime(
      cloud: cloud,
      local: local,
      preferCloudWhenAvailable: true
    )

    let cloudRuntime = try routed.selectRuntime(for: .cloudPrimary)
    let localRuntime = try routed.selectRuntime(for: .localPreferred)
    #expect((cloudRuntime as? RecordingModelRuntime)?.name == "cloud")
    #expect((localRuntime as? RecordingModelRuntime)?.name == "local")
  }

  @Test
  func routedRuntimeFallsBackWhenPreferredBackendMissing() throws {
    let cloud = RecordingModelRuntime(name: "cloud")
    let cloudOnly = RoutedModelRuntime(
      cloud: cloud,
      local: nil,
      preferCloudWhenAvailable: true
    )
    #expect(
      try (cloudOnly.selectRuntime(for: .localPreferred) as? RecordingModelRuntime)?.name
        == "cloud"
    )

    let local = RecordingModelRuntime(name: "local")
    let localOnly = RoutedModelRuntime(
      cloud: nil,
      local: local,
      preferCloudWhenAvailable: true
    )
    #expect(
      try (localOnly.selectRuntime(for: .cloudPrimary) as? RecordingModelRuntime)?.name
        == "local"
    )
  }

  @Test
  func routedRuntimeRewritesModelIDWhenFallingBackToLocal() async throws {
    let local = RecordingModelRuntime(name: "local")
    let localOnly = RoutedModelRuntime(
      cloud: nil,
      local: local,
      preferCloudWhenAvailable: true
    )

    _ = try await localOnly.generateText(
      request: LocalModelGenerationRequest(
        modelID: "",
        systemPrompt: "sys",
        prompt: "hi",
        routingHint: .cloudPrimary
      )
    )
    #expect(local.lastModelID == LocalModelCatalog.blessedModelID)

    let cloud = RecordingModelRuntime(name: "cloud")
    let both = RoutedModelRuntime(
      cloud: cloud,
      local: local,
      preferCloudWhenAvailable: true
    )
    _ = try await both.generateText(
      request: LocalModelGenerationRequest(
        modelID: "cloud-model",
        systemPrompt: "sys",
        prompt: "hi",
        routingHint: .cloudPrimary
      )
    )
    #expect(cloud.lastModelID == "cloud-model")
  }

  @Test
  func settingsStoreLoadsCloudFieldsFromEnvironment() {
    let defaults = UserDefaults(suiteName: "CompassOpenAICompatibleRuntimeTests.\(UUID().uuidString)")!
    defer {
      for key in AgentSettingsStore.Key.allCases {
        defaults.removeObject(forKey: key.rawValue)
      }
    }
    let secrets = InMemoryAgentSecretStorage()
    let store = AgentSettingsStore(
      defaults: defaults,
      secrets: secrets,
      environment: [
        "COMPASS_AGENT_TEXT_PROVIDER": "openAICompatible",
        "COMPASS_AGENT_BASE_URL": "https://api.example.com/v1",
        "COMPASS_AGENT_API_KEY": "sk-env",
        "COMPASS_AGENT_MODEL": "env-model",
        "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "64000",
      ]
    )

    let settings = store.load()
    #expect(settings.textProvider == .openAICompatible)
    #expect(settings.baseURL.absoluteString == "https://api.example.com/v1")
    #expect(settings.apiKey == "sk-env")
    #expect(settings.model == "env-model")
    #expect(settings.contextWindowTokens == 64_000)
    #expect(settings.hasCloudCredentials)
  }
}

private final class RecordingModelRuntime: LocalModelGenerating, @unchecked Sendable {
  let name: String
  private(set) var lastModelID: String?

  init(name: String) {
    self.name = name
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    lastModelID = request.modelID
    return LocalModelGenerationResult(text: name, tokenUsage: AgentRunTokenUsage())
  }
}
