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
  /// Non-2xx HTTP response. `retryAfterSeconds` is parsed from `Retry-After` when present.
  case httpStatus(Int, String, retryAfterSeconds: Double?)
  case emptyResponse
  /// Provider finished a turn with reasoning tokens but no assistant `content`
  /// (common with thinking models when the prompt confuses the final answer).
  case reasoningOnlyResponse(finishReason: String?, reasoningCharacters: Int)
  case decodeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "OpenAI-compatible cloud provider is not configured (need API key, base URL, and model)."
    case .invalidBaseURL(let value):
      return "Invalid OpenAI-compatible base URL: \(value)"
    case .httpStatus(let code, let body, _):
      let preview = body.trimmingCharacters(in: .whitespacesAndNewlines)
      let clipped = preview.count > 400 ? String(preview.prefix(400)) + "…" : preview
      return "OpenAI-compatible request failed (\(code)): \(clipped)"
    case .emptyResponse:
      return "OpenAI-compatible response contained no assistant text."
    case .reasoningOnlyResponse(let finishReason, let reasoningCharacters):
      let reason = finishReason?.trimmingCharacters(in: .whitespacesAndNewlines)
      let reasonSuffix =
        (reason?.isEmpty == false) ? " finish_reason=\(reason!)." : ""
      return
        "OpenAI-compatible response contained reasoning (\(reasoningCharacters) chars) but no assistant text.\(reasonSuffix)"
    case .decodeFailed(let detail):
      return "OpenAI-compatible response decode failed: \(detail)"
    }
  }

  /// True for overloaded / rate-limited / temporary upstream failures that are
  /// worth retrying with backoff (e.g. 429 `engine_overloaded_error`).
  public var isTransient: Bool {
    switch self {
    case .httpStatus(let code, _, _):
      return OpenAICompatibleRetryPolicy.isTransientHTTPStatus(code)
    case .notConfigured, .invalidBaseURL, .emptyResponse, .reasoningOnlyResponse, .decodeFailed:
      return false
    }
  }

  public var retryAfterSeconds: Double? {
    switch self {
    case .httpStatus(_, _, let retryAfterSeconds):
      return retryAfterSeconds
    default:
      return nil
    }
  }
}

/// Exponential-backoff policy for transient OpenAI-compatible HTTP failures.
public struct OpenAICompatibleRetryPolicy: Sendable, Equatable {
  /// Total attempts including the first try. `1` disables retries.
  public var maxAttempts: Int
  public var initialBackoffNanoseconds: UInt64
  public var maxBackoffNanoseconds: UInt64
  /// Extra random delay as a fraction of the computed backoff (`0` disables jitter).
  public var jitterFraction: Double

  public static let `default` = OpenAICompatibleRetryPolicy(
    maxAttempts: 5,
    initialBackoffNanoseconds: 1_000_000_000,
    maxBackoffNanoseconds: 32_000_000_000,
    jitterFraction: 0.25
  )

  public static let disabled = OpenAICompatibleRetryPolicy(
    maxAttempts: 1,
    initialBackoffNanoseconds: 0,
    maxBackoffNanoseconds: 0,
    jitterFraction: 0
  )

  public init(
    maxAttempts: Int,
    initialBackoffNanoseconds: UInt64,
    maxBackoffNanoseconds: UInt64,
    jitterFraction: Double
  ) {
    self.maxAttempts = max(1, maxAttempts)
    self.initialBackoffNanoseconds = initialBackoffNanoseconds
    self.maxBackoffNanoseconds = maxBackoffNanoseconds
    self.jitterFraction = max(0, jitterFraction)
  }

  public static func isTransientHTTPStatus(_ code: Int) -> Bool {
    switch code {
    case 408, 429, 500, 502, 503, 504:
      return true
    default:
      return false
    }
  }

  public static func isTransientURLError(_ error: URLError) -> Bool {
    switch error.code {
    case .timedOut,
      .networkConnectionLost,
      .notConnectedToInternet,
      .cannotConnectToHost,
      .dnsLookupFailed,
      .cannotFindHost,
      .resourceUnavailable,
      .internationalRoamingOff,
      .callIsActive,
      .dataNotAllowed:
      return true
    default:
      return false
    }
  }

  /// Parses `Retry-After` as delay-seconds or HTTP-date.
  public static func retryAfterSeconds(from response: HTTPURLResponse) -> Double? {
    guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return nil
    }
    if let seconds = Double(raw), seconds >= 0 {
      return seconds
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let date = formatter.date(from: raw) {
      return max(0, date.timeIntervalSinceNow)
    }
    return nil
  }

  /// Backoff after a failed attempt (`attempt` is 1-based and already failed).
  /// Prefers a provider `Retry-After` hint when present, otherwise doubles from
  /// `initialBackoffNanoseconds` up to `maxBackoffNanoseconds`, with optional jitter.
  public func delayNanoseconds(
    afterFailedAttempt attempt: Int,
    retryAfterSeconds: Double? = nil
  ) -> UInt64 {
    let cappedAttempt = max(1, attempt)
    var base: UInt64
    if let retryAfterSeconds, retryAfterSeconds > 0 {
      let fromHeader = UInt64(min(retryAfterSeconds, Double(UInt64.max) / 1_000_000_000) * 1_000_000_000)
      base = min(max(fromHeader, initialBackoffNanoseconds), maxBackoffNanoseconds)
    } else {
      var delay = initialBackoffNanoseconds
      for _ in 1..<cappedAttempt {
        if delay >= maxBackoffNanoseconds / 2 {
          delay = maxBackoffNanoseconds
          break
        }
        delay = min(delay * 2, maxBackoffNanoseconds)
      }
      base = min(delay, maxBackoffNanoseconds)
    }
    guard jitterFraction > 0, base > 0 else { return base }
    let span = Double(base) * jitterFraction
    let jitter = Double.random(in: -span...span)
    let adjusted = Double(base) + jitter
    return UInt64(max(0, adjusted))
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
  private let retryPolicy: OpenAICompatibleRetryPolicy
  private let sleep: @Sendable (UInt64) async -> Void

  public init(
    endpoint: OpenAICompatibleEndpoint,
    session: URLSession = .shared,
    retryPolicy: OpenAICompatibleRetryPolicy = .default,
    sleep: @escaping @Sendable (UInt64) async -> Void = { ns in
      try? await Task.sleep(nanoseconds: ns)
    }
  ) {
    self.endpoint = endpoint
    self.session = session
    self.retryPolicy = retryPolicy
    self.sleep = sleep
  }

  public init(
    settings: AgentRuntimeSettings,
    session: URLSession = .shared,
    retryPolicy: OpenAICompatibleRetryPolicy = .default
  ) {
    self.init(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: settings.baseURL,
        apiKey: settings.apiKey,
        model: settings.model
      ),
      session: session,
      retryPolicy: retryPolicy
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
        let error = OpenAICompatibleRuntimeError.httpStatus(
          http.statusCode,
          bodyText,
          retryAfterSeconds: OpenAICompatibleRetryPolicy.retryAfterSeconds(from: http)
        )
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
    return try await withTransientRetry {
      let (data, response) = try await session.data(for: urlRequest)
      guard let http = response as? HTTPURLResponse else {
        throw OpenAICompatibleRuntimeError.decodeFailed("Missing HTTP response.")
      }
      guard (200..<300).contains(http.statusCode) else {
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        throw OpenAICompatibleRuntimeError.httpStatus(
          http.statusCode,
          bodyText,
          retryAfterSeconds: OpenAICompatibleRetryPolicy.retryAfterSeconds(from: http)
        )
      }

      let decoded: OpenAIChatCompletionsResponse
      do {
        decoded = try JSONDecoder().decode(OpenAIChatCompletionsResponse.self, from: data)
      } catch {
        throw OpenAICompatibleRuntimeError.decodeFailed(error.localizedDescription)
      }

      let choice = decoded.choices.first
      let text =
        decoded.choices
        .compactMap { $0.message?.content }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        ?? ""
      if text.isEmpty {
        let reasoning =
          decoded.choices
          .compactMap { $0.message?.reasoningContent }
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .first { !$0.isEmpty }
        if let reasoning {
          throw OpenAICompatibleRuntimeError.reasoningOnlyResponse(
            finishReason: choice?.finishReason,
            reasoningCharacters: reasoning.count
          )
        }
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

  /// Retries transient HTTP / transport failures with exponential backoff.
  /// Non-transient errors (4xx auth, empty response, decode) fail immediately.
  private func withTransientRetry<T: Sendable>(
    operation: () async throws -> T
  ) async throws -> T {
    var attempt = 0
    while true {
      attempt += 1
      do {
        return try await operation()
      } catch let error as OpenAICompatibleRuntimeError where error.isTransient {
        guard attempt < retryPolicy.maxAttempts else { throw error }
        let delay = retryPolicy.delayNanoseconds(
          afterFailedAttempt: attempt,
          retryAfterSeconds: error.retryAfterSeconds
        )
        await sleep(delay)
      } catch let error as URLError
      where OpenAICompatibleRetryPolicy.isTransientURLError(error) {
        guard attempt < retryPolicy.maxAttempts else { throw error }
        let delay = retryPolicy.delayNanoseconds(afterFailedAttempt: attempt)
        await sleep(delay)
      } catch {
        throw error
      }
    }
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
    return try await withTransientRetry {
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
        throw OpenAICompatibleRuntimeError.httpStatus(
          http.statusCode,
          errorBody,
          retryAfterSeconds: OpenAICompatibleRetryPolicy.retryAfterSeconds(from: http)
        )
      }

      var content = ""
      var reasoningContent = ""
      var toolCalls: [Int: (id: String, name: String, arguments: String)] = [:]
      var usage: OpenAIChatCompletionsResponse.Usage?
      var sawFinishReason = false
      var lastFinishReason: String?

      for try await line in bytes.lines {
        try Task.checkCancellation()
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
          if let finishReason = choice.finishReason {
            sawFinishReason = true
            lastFinishReason = finishReason
          }
          guard let delta = choice.delta else { continue }
          if let text = delta.content {
            content += text
          }
          if let reasoning = delta.reasoningContent {
            reasoningContent += reasoning
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
      let trimmedReasoning = reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
      if resolvedToolCalls.isEmpty && trimmed.isEmpty && !sawFinishReason {
        if !trimmedReasoning.isEmpty {
          throw OpenAICompatibleRuntimeError.reasoningOnlyResponse(
            finishReason: lastFinishReason,
            reasoningCharacters: trimmedReasoning.count
          )
        }
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
      public var reasoningContent: String?
      public var toolCalls: [ToolCall]?

      public enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
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
      public var reasoningContent: String?

      public enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
      }
    }

    public var message: Message?
    public var finishReason: String?

    public enum CodingKeys: String, CodingKey {
      case message
      case finishReason = "finish_reason"
    }
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
