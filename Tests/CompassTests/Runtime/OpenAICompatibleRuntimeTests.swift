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
    let defaults = UserDefaults(
      suiteName: "CompassOpenAICompatibleRuntimeTests.\(UUID().uuidString)")!
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

  @Test
  func generateTextThrowsWhenResponseIsReasoningOnly() async throws {
    final class JSONProtocol: URLProtocol, @unchecked Sendable {
      nonisolated(unsafe) static var responseBody: String = ""

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        let body = Data(Self.responseBody.utf8)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
      }

      override func stopLoading() {}
    }

    JSONProtocol.responseBody = """
      {"choices":[{"message":{"role":"assistant","content":"","reasoning_content":"I should call a tool."},"finish_reason":"stop"}]}
      """
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [JSONProtocol.self]
    let runtime = OpenAICompatibleModelRuntime(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: URL(string: "https://api.example.com/v1")!,
        apiKey: "sk-test",
        model: "k3"
      ),
      session: URLSession(configuration: config)
    )
    do {
      _ = try await runtime.generateText(
        request: LocalModelGenerationRequest(systemPrompt: "sys", prompt: "hi")
      )
      Issue.record("expected reasoning-only response to throw")
    } catch let error as OpenAICompatibleRuntimeError {
      guard case .reasoningOnlyResponse(let finishReason, let reasoningCharacters) = error else {
        Issue.record("expected reasoningOnlyResponse, got \(error)")
        return
      }
      #expect(finishReason == "stop")
      #expect(reasoningCharacters == "I should call a tool.".count)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }

  @Test
  func transientStatusCodesIncludeOverloadAndGatewayFailures() {
    for code in [408, 429, 500, 502, 503, 504] {
      #expect(OpenAICompatibleRetryPolicy.isTransientHTTPStatus(code))
      #expect(
        OpenAICompatibleRuntimeError.httpStatus(code, "overloaded", retryAfterSeconds: nil)
          .isTransient
      )
    }
    for code in [400, 401, 403, 404, 422] {
      #expect(!OpenAICompatibleRetryPolicy.isTransientHTTPStatus(code))
      #expect(
        !OpenAICompatibleRuntimeError.httpStatus(code, "nope", retryAfterSeconds: nil).isTransient
      )
    }
  }

  @Test
  func retryPolicyDoublesBackoffAndHonorsRetryAfter() {
    let policy = OpenAICompatibleRetryPolicy(
      maxAttempts: 5,
      initialBackoffNanoseconds: 1_000_000_000,
      maxBackoffNanoseconds: 8_000_000_000,
      jitterFraction: 0
    )
    #expect(policy.delayNanoseconds(afterFailedAttempt: 1) == 1_000_000_000)
    #expect(policy.delayNanoseconds(afterFailedAttempt: 2) == 2_000_000_000)
    #expect(policy.delayNanoseconds(afterFailedAttempt: 3) == 4_000_000_000)
    #expect(policy.delayNanoseconds(afterFailedAttempt: 4) == 8_000_000_000)
    #expect(policy.delayNanoseconds(afterFailedAttempt: 5) == 8_000_000_000)
    #expect(
      policy.delayNanoseconds(afterFailedAttempt: 1, retryAfterSeconds: 3) == 3_000_000_000
    )
  }

  @Test
  func generateTextRetriesTransientOverloadThenSucceeds() async throws {
    final class FlakyProtocol: URLProtocol, @unchecked Sendable {
      nonisolated(unsafe) static var callCount = 0

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        Self.callCount += 1
        if Self.callCount == 1 {
          let body = Data(
            #"{"error":{"message":"The engine is currently overloaded, please try again later","type":"engine_overloaded_error"}}"#
              .utf8
          )
          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: [
              "Content-Type": "application/json",
              "Retry-After": "0",
            ]
          )!
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: body)
          client?.urlProtocolDidFinishLoading(self)
          return
        }

        let body = Data(
          #"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
            .utf8
        )
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
      }

      override func stopLoading() {}
    }

    FlakyProtocol.callCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FlakyProtocol.self]
    final class SleepCounter: @unchecked Sendable {
      var delays: [UInt64] = []
    }
    let sleeps = SleepCounter()
    let runtime = OpenAICompatibleModelRuntime(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: URL(string: "https://api.example.com/v1")!,
        apiKey: "sk-test",
        model: "k3"
      ),
      session: URLSession(configuration: config),
      retryPolicy: OpenAICompatibleRetryPolicy(
        maxAttempts: 3,
        initialBackoffNanoseconds: 100,
        maxBackoffNanoseconds: 1_000,
        jitterFraction: 0
      ),
      sleep: { ns in sleeps.delays.append(ns) }
    )

    let result = try await runtime.generateText(
      request: LocalModelGenerationRequest(systemPrompt: "sys", prompt: "hi")
    )
    #expect(result.text == "ok")
    #expect(FlakyProtocol.callCount == 2)
    #expect(sleeps.delays.count == 1)
  }

  @Test
  func generateTextDoesNotRetryClientErrors() async throws {
    final class AuthProtocol: URLProtocol, @unchecked Sendable {
      nonisolated(unsafe) static var callCount = 0

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        Self.callCount += 1
        let body = Data(#"{"error":{"message":"invalid api key"}}"#.utf8)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 401,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
      }

      override func stopLoading() {}
    }

    AuthProtocol.callCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AuthProtocol.self]
    let runtime = OpenAICompatibleModelRuntime(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: URL(string: "https://api.example.com/v1")!,
        apiKey: "sk-bad",
        model: "k3"
      ),
      session: URLSession(configuration: config),
      retryPolicy: .default,
      sleep: { _ in Issue.record("should not sleep for non-transient errors") }
    )

    do {
      _ = try await runtime.generateText(
        request: LocalModelGenerationRequest(systemPrompt: "sys", prompt: "hi")
      )
      Issue.record("expected 401 to throw")
    } catch let error as OpenAICompatibleRuntimeError {
      guard case .httpStatus(let code, _, _) = error else {
        Issue.record("expected httpStatus, got \(error)")
        return
      }
      #expect(code == 401)
      #expect(AuthProtocol.callCount == 1)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }
}

private final class RecordingModelRuntime: LocalModelGenerating, @unchecked Sendable {
  let name: String
  private(set) var lastModelID: String?

  init(name: String) {
    self.name = name
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult
  {
    lastModelID = request.modelID
    return LocalModelGenerationResult(text: name, tokenUsage: AgentRunTokenUsage())
  }
}
