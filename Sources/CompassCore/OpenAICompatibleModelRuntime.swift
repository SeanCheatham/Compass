import Foundation

public struct OpenAICompatibleEndpoint: Sendable, Equatable {
  public var baseURL: URL
  public var apiKey: String
  public var model: String

  public var trimmedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedModel: String {
    model.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var isConfigured: Bool {
    !trimmedAPIKey.isEmpty && !trimmedModel.isEmpty
  }

  public func chatCompletionsURL() throws -> URL {
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

public enum OpenAICompatibleRuntimeError: LocalizedError, Equatable {
  case notConfigured
  case invalidBaseURL(String)
  case httpStatus(Int, String)
  case emptyResponse
  case decodeFailed(String)

  public var errorDescription: String? {
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

public struct OpenAICompatiblePingResult: Sendable, Equatable {
  public var ok: Bool
  public var statusCode: Int?
  public var latencyMs: Int
  public var message: String

  public init(ok: Bool, statusCode: Int?, latencyMs: Int, message: String) {
    self.ok = ok
    self.statusCode = statusCode
    self.latencyMs = latencyMs
    self.message = message
  }
}

/// Thin non-streaming OpenAI chat-completions client used as a `LocalModelGenerating` backend.
public actor OpenAICompatibleModelRuntime: LocalModelGenerating {
  private let endpoint: OpenAICompatibleEndpoint
  private let session: URLSession

  public init(endpoint: OpenAICompatibleEndpoint, session: URLSession = .shared) {
    self.endpoint = endpoint
    self.session = session
  }

  public init(settings: AgentRuntimeSettings, session: URLSession = .shared) {
    self.init(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: settings.baseURL,
        apiKey: settings.apiKey,
        model: settings.model
      ),
      session: session
    )
  }

  /// Minimal 1-token chat completion used by `doctor --check-cloud` to prove the
  /// configured base URL, API key, and model actually work before a factory run.
  public static func ping(
    endpoint: OpenAICompatibleEndpoint,
    session: URLSession = .shared,
    timeout: TimeInterval = 30
  ) async -> OpenAICompatiblePingResult {
    let startedAt = Date()
    func result(ok: Bool, statusCode: Int?, message: String) -> OpenAICompatiblePingResult {
      OpenAICompatiblePingResult(
        ok: ok,
        statusCode: statusCode,
        latencyMs: Int(Date().timeIntervalSince(startedAt) * 1_000),
        message: message
      )
    }
    do {
      guard endpoint.isConfigured else {
        throw OpenAICompatibleRuntimeError.notConfigured
      }
      let url = try endpoint.chatCompletionsURL()
      var urlRequest = URLRequest(url: url)
      urlRequest.httpMethod = "POST"
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
      urlRequest.setValue("Bearer \(endpoint.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
      urlRequest.timeoutInterval = timeout
      urlRequest.httpBody = try JSONEncoder().encode(
        OpenAIChatCompletionsRequest(
          model: endpoint.trimmedModel,
          messages: [.init(role: "user", content: "ping")],
          maxTokens: 1,
          stream: false
        )
      )
      let (data, response) = try await session.data(for: urlRequest)
      guard let http = response as? HTTPURLResponse else {
        throw OpenAICompatibleRuntimeError.decodeFailed("Missing HTTP response.")
      }
      guard (200..<300).contains(http.statusCode) else {
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        let error = OpenAICompatibleRuntimeError.httpStatus(http.statusCode, bodyText)
        return result(ok: false, statusCode: http.statusCode, message: error.localizedDescription)
      }
      return result(
        ok: true,
        statusCode: http.statusCode,
        message: "Cloud endpoint answered a 1-token chat completion."
      )
    } catch {
      return result(ok: false, statusCode: nil, message: error.localizedDescription)
    }
  }

  public func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
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
    urlRequest.timeoutInterval = 900

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

extension OpenAICompatibleModelRuntime: AgentChatGenerating {
  /// Streams one chat-completions turn with native tool calling. Streaming
  /// keeps long cloud turns alive (proxies idle-kill non-streaming requests)
  /// and surfaces provider token usage for real context-window accounting.
  public func generateChat(request: AgentChatRequest) async throws -> AgentChatResponse {
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
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    urlRequest.timeoutInterval = 900

    let toolObjects = request.tools.compactMap { $0.nativeToolJSONObject }
    var bodyObject: [String: Any] = [
      "model": modelID,
      "messages": request.messages.map { Self.wireMessage($0) },
      "max_tokens": request.maxOutputTokens,
      "stream": true,
      "stream_options": ["include_usage": true],
    ]
    if !toolObjects.isEmpty {
      bodyObject["tools"] = toolObjects
      bodyObject["tool_choice"] = "auto"
    }
    guard JSONSerialization.isValidJSONObject(bodyObject) else {
      throw OpenAICompatibleRuntimeError.decodeFailed("Request body is not valid JSON.")
    }
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: bodyObject)

    let startedAt = Date()
    let (bytes, response) = try await session.bytes(for: urlRequest)
    guard let http = response as? HTTPURLResponse else {
      throw OpenAICompatibleRuntimeError.decodeFailed("Missing HTTP response.")
    }
    guard (200..<300).contains(http.statusCode) else {
      var errorBody = ""
      for try await line in bytes.lines {
        errorBody += line
        if errorBody.count > 4_000 { break }
      }
      throw OpenAICompatibleRuntimeError.httpStatus(http.statusCode, errorBody)
    }

    var content = ""
    var toolCalls: [Int: (id: String, name: String, arguments: String)] = [:]
    var usage: OpenAIChatCompletionsResponse.Usage?
    var sawFinishReason = false

    for try await line in bytes.lines {
      guard line.hasPrefix("data:") else { continue }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if payload == "[DONE]" { break }
      guard let data = payload.data(using: .utf8),
        let chunk = try? JSONDecoder().decode(OpenAIChatStreamChunk.self, from: data)
      else {
        continue
      }
      if let chunkUsage = chunk.usage {
        usage = chunkUsage
      }
      for choice in chunk.choices {
        if choice.finishReason != nil {
          sawFinishReason = true
        }
        guard let delta = choice.delta else { continue }
        if let text = delta.content {
          content += text
        }
        for toolDelta in delta.toolCalls ?? [] {
          let index = toolDelta.index ?? 0
          var accumulated = toolCalls[index] ?? (id: "", name: "", arguments: "")
          if let id = toolDelta.id, !id.isEmpty {
            accumulated.id = id
          }
          if let name = toolDelta.function?.name, !name.isEmpty {
            accumulated.name = name
          }
          if let arguments = toolDelta.function?.arguments {
            accumulated.arguments += arguments
          }
          toolCalls[index] = accumulated
        }
      }
    }

    let resolvedToolCalls: [AgentChatToolCall] = toolCalls
      .sorted { $0.key < $1.key }
      .map { index, accumulated in
        AgentChatToolCall(
          id: accumulated.id.isEmpty ? "toolcall_\(index)" : accumulated.id,
          name: accumulated.name,
          argumentsJSON: accumulated.arguments
        )
      }

    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if resolvedToolCalls.isEmpty && trimmed.isEmpty && !sawFinishReason {
      throw OpenAICompatibleRuntimeError.emptyResponse
    }

    var tokenUsage = AgentRunTokenUsage()
    let inputTokens = usage?.promptTokens ?? 0
    let outputTokens = usage?.completionTokens ?? 0
    let totalTokens = usage?.totalTokens ?? (inputTokens + outputTokens)
    tokenUsage.recordTurn(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      isEstimated: usage == nil,
      streamedUsageAvailable: usage != nil
    )
    tokenUsage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
    return AgentChatResponse(text: trimmed, toolCalls: resolvedToolCalls, tokenUsage: tokenUsage)
  }

  private static func wireMessage(_ message: AgentChatMessage) -> [String: Any] {
    var object: [String: Any] = ["role": message.role.rawValue]
    switch message.role {
    case .assistant:
      object["content"] = message.content.isEmpty ? NSNull() : message.content
      if !message.toolCalls.isEmpty {
        object["tool_calls"] = message.toolCalls.map { call in
          [
            "id": call.id,
            "type": "function",
            "function": [
              "name": call.name,
              "arguments": call.argumentsJSON,
            ],
          ] as [String: Any]
        }
      }
    case .tool:
      object["content"] = message.content
      if let toolCallID = message.toolCallID {
        object["tool_call_id"] = toolCallID
      }
    case .system, .user:
      object["content"] = message.content
    }
    return object
  }
}

public struct OpenAIChatStreamChunk: Decodable, Equatable, Sendable {
  public struct Choice: Decodable, Equatable, Sendable {
    public struct Delta: Decodable, Equatable, Sendable {
      public struct ToolCall: Decodable, Equatable, Sendable {
        public struct Function: Decodable, Equatable, Sendable {
          public var name: String?
          public var arguments: String?
        }

        public var index: Int?
        public var id: String?
        public var function: Function?
      }

      public var role: String?
      public var content: String?
      public var toolCalls: [ToolCall]?

      public enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
      }
    }

    public var delta: Delta?
    public var finishReason: String?

    public enum CodingKeys: String, CodingKey {
      case delta
      case finishReason = "finish_reason"
    }
  }

  public var choices: [Choice]
  public var usage: OpenAIChatCompletionsResponse.Usage?
}

public struct OpenAIChatCompletionsRequest: Encodable, Equatable, Sendable {
  public struct Message: Encodable, Equatable, Sendable {
    public var role: String
    public var content: String
  }

  public var model: String
  public var messages: [Message]
  public var maxTokens: Int
  public var stream: Bool

  public enum CodingKeys: String, CodingKey {
    case model
    case messages
    case maxTokens = "max_tokens"
    case stream
  }
}

public struct OpenAIChatCompletionsResponse: Decodable, Equatable, Sendable {
  public struct Choice: Decodable, Equatable, Sendable {
    public struct Message: Decodable, Equatable, Sendable {
      public var role: String?
      public var content: String?
    }

    public var message: Message?
  }

  public struct Usage: Decodable, Equatable, Sendable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public enum CodingKeys: String, CodingKey {
      case promptTokens = "prompt_tokens"
      case completionTokens = "completion_tokens"
      case totalTokens = "total_tokens"
    }
  }

  public var choices: [Choice]
  public var usage: Usage?
}
