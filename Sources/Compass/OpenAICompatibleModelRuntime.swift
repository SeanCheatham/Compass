import Foundation

struct OpenAICompatibleEndpoint: Sendable, Equatable {
  var baseURL: URL
  var apiKey: String
  var model: String

  var trimmedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var trimmedModel: String {
    model.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isConfigured: Bool {
    !trimmedAPIKey.isEmpty && !trimmedModel.isEmpty
  }

  func chatCompletionsURL() throws -> URL {
    var normalized = baseURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
    while normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    guard let url = URL(string: normalized + "/chat/completions") else {
      throw OpenAICompatibleRuntimeError.invalidBaseURL(baseURL.absoluteString)
    }
    return url
  }
}

enum OpenAICompatibleRuntimeError: LocalizedError, Equatable {
  case notConfigured
  case invalidBaseURL(String)
  case httpStatus(Int, String)
  case emptyResponse
  case decodeFailed(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "OpenAI-compatible cloud provider is not configured (need API key, base URL, and model)."
    case .invalidBaseURL(let value):
      return "Invalid OpenAI-compatible base URL: \(value)"
    case .httpStatus(let code, let body):
      let preview = body.trimmingCharacters(in: .whitespacesAndNewlines)
      let clipped = preview.count > 400 ? String(preview.prefix(400)) + "…" : preview
      return "OpenAI-compatible request failed (\(code)): \(clipped)"
    case .emptyResponse:
      return "OpenAI-compatible response contained no assistant text."
    case .decodeFailed(let detail):
      return "OpenAI-compatible response decode failed: \(detail)"
    }
  }
}

/// Thin non-streaming OpenAI chat-completions client used as a `LocalModelGenerating` backend.
actor OpenAICompatibleModelRuntime: LocalModelGenerating {
  private let endpoint: OpenAICompatibleEndpoint
  private let session: URLSession

  init(endpoint: OpenAICompatibleEndpoint, session: URLSession = .shared) {
    self.endpoint = endpoint
    self.session = session
  }

  init(settings: AgentRuntimeSettings, session: URLSession = .shared) {
    self.init(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: settings.baseURL,
        apiKey: settings.apiKey,
        model: settings.model
      ),
      session: session
    )
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    guard endpoint.isConfigured else {
      throw OpenAICompatibleRuntimeError.notConfigured
    }

    let modelID =
      request.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? endpoint.trimmedModel
      : request.modelID
    let url = try endpoint.chatCompletionsURL()
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(endpoint.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
    urlRequest.timeoutInterval = 300

    let body = OpenAIChatCompletionsRequest(
      model: modelID,
      messages: [
        .init(role: "system", content: request.systemPrompt),
        .init(role: "user", content: request.prompt),
      ],
      maxTokens: request.maxOutputTokens,
      stream: false
    )
    urlRequest.httpBody = try JSONEncoder().encode(body)

    let startedAt = Date()
    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else {
      throw OpenAICompatibleRuntimeError.decodeFailed("Missing HTTP response.")
    }
    guard (200..<300).contains(http.statusCode) else {
      let bodyText = String(data: data, encoding: .utf8) ?? ""
      throw OpenAICompatibleRuntimeError.httpStatus(http.statusCode, bodyText)
    }

    let decoded: OpenAIChatCompletionsResponse
    do {
      decoded = try JSONDecoder().decode(OpenAIChatCompletionsResponse.self, from: data)
    } catch {
      throw OpenAICompatibleRuntimeError.decodeFailed(error.localizedDescription)
    }

    let text =
      decoded.choices
      .compactMap { $0.message?.content }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
      ?? ""
    guard !text.isEmpty else {
      throw OpenAICompatibleRuntimeError.emptyResponse
    }

    var tokenUsage = AgentRunTokenUsage()
    let inputTokens = decoded.usage?.promptTokens ?? 0
    let outputTokens = decoded.usage?.completionTokens ?? 0
    let totalTokens = decoded.usage?.totalTokens ?? (inputTokens + outputTokens)
    tokenUsage.recordTurn(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      isEstimated: decoded.usage == nil,
      streamedUsageAvailable: decoded.usage != nil
    )
    tokenUsage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
    return LocalModelGenerationResult(text: text, tokenUsage: tokenUsage)
  }
}

struct OpenAIChatCompletionsRequest: Encodable, Equatable, Sendable {
  struct Message: Encodable, Equatable, Sendable {
    var role: String
    var content: String
  }

  var model: String
  var messages: [Message]
  var maxTokens: Int
  var stream: Bool

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case maxTokens = "max_tokens"
    case stream
  }
}

struct OpenAIChatCompletionsResponse: Decodable, Equatable, Sendable {
  struct Choice: Decodable, Equatable, Sendable {
    struct Message: Decodable, Equatable, Sendable {
      var role: String?
      var content: String?
    }

    var message: Message?
  }

  struct Usage: Decodable, Equatable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?

    enum CodingKeys: String, CodingKey {
      case promptTokens = "prompt_tokens"
      case completionTokens = "completion_tokens"
      case totalTokens = "total_tokens"
    }
  }

  var choices: [Choice]
  var usage: Usage?
}
