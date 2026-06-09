import Foundation
import OpenAI

extension AgentExecutor {
  // MARK: - Streaming aggregation

  /// Aggregated result of one chat-completions streaming turn. Internal
  /// (rather than fileprivate) so tests can build canned streams and
  /// exercise `aggregate(stream:)` directly without standing up an
  /// `OpenAI` client.
  struct AggregatedTurn: Equatable {
    var assistantText: String
    var reasoningText: String
    var toolCalls: [PendingToolCall]
    var finishReason: String?
    /// Prompt + completion tokens reported by the upstream's final
    /// usage chunk. Nil when the provider does not honour
    /// `stream_options.include_usage`. Kept for log observability only —
    /// auto-compaction runs off `estimatedTokens(in:)` so it isn't
    /// disabled when a provider drops usage on tool-calling chunks.
    var usage: StreamedTokenUsage?

    var totalTokens: Int? { usage?.totalTokens }
  }

  struct StreamedTokenUsage: Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
  }

  struct PendingToolCall: Equatable {
    var index: Int
    var id: String
    var name: String
    var arguments: String

    func asAssistantToolCall()
      -> ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam
    {
      .init(id: id, function: .init(arguments: arguments, name: name))
    }
  }

  /// On a permanent stream failure, MacPaw's `OpenAIError.statusError`
  /// carries only the `HTTPURLResponse` — the body that contains the
  /// actual error message was discarded when `StreamingSession` cancelled
  /// the URLSession data task on the 4xx. Replay the exact request the
  /// middleware recorded so we can surface the body to the user, with
  /// `stream` flipped off so providers send a regular JSON error instead
  /// of an SSE event. Returns the original `localizedDescription` plus the
  /// captured body when one is available; falls back to just the
  /// description if no recorded request exists or the replay itself
  /// fails.
  func enrichedStreamFailureDetail(
    error: Error, recorder: UpstreamRequestRecorder
  ) async -> String {
    let baseDescription = error.localizedDescription
    guard let openAIError = error as? OpenAIError,
      case .statusError(_, _) = openAIError,
      let recorded = recorder.lastRequest
    else {
      return baseDescription
    }
    guard let body = await Self.captureErrorBody(from: recorded) else {
      return baseDescription
    }
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return baseDescription
    }
    return "\(baseDescription) — upstream body: \(previewString(trimmed))"
  }

  /// Replay a recorded request with `stream=false` and a short timeout to
  /// pull the response body. Returns nil on any networking or encoding
  /// failure — body capture is best-effort and must never mask the
  /// original error.
  static func captureErrorBody(from request: URLRequest) async -> String? {
    var probe = request
    probe.timeoutInterval = 30
    // Streaming responses use SSE framing; flipping `stream` to false in
    // the JSON payload makes MiniMax / OpenAI return a regular JSON error
    // body that's easier to read.
    if let originalBody = probe.httpBody,
      var payload = (try? JSONSerialization.jsonObject(with: originalBody)) as? [String: Any]
    {
      payload["stream"] = false
      payload.removeValue(forKey: "stream_options")
      if let reencoded = try? JSONSerialization.data(withJSONObject: payload) {
        probe.httpBody = reencoded
        probe.setValue("\(reencoded.count)", forHTTPHeaderField: "Content-Length")
      }
    }
    probe.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, _) = try await URLSession.shared.data(for: probe)
      return String(data: data, encoding: .utf8)
    } catch {
      return nil
    }
  }

  /// Wraps `streamOneTurn` in an exponential-backoff retry loop for
  /// transient upstream failures. Anything classified as transient by
  /// `Self.shouldRetry` gets re-issued after a backoff sleep, up to
  /// `maxStreamAttempts`. Permanent errors (4xx other than 408/429,
  /// decode failures, etc.) propagate immediately so we don't waste
  /// minutes hammering a request the server will never accept.
  ///
  /// The retry decision considers `OpenAIError.statusError` (the
  /// MacPaw library's HTTP-error type — covers MiniMax's 529
  /// "overloaded" responses and Cloudflare-fronted 5xx blips) and
  /// `URLError` (network-layer drops). Other thrown types are treated
  /// as permanent.
  func streamOneTurnWithRetry(
    openAI: OpenAI,
    query: ChatQuery
  ) async throws -> AggregatedTurn {
    var lastError: Error?
    for attempt in 1...Self.maxStreamAttempts {
      if cancelled { throw AgentExecutionError.cancelled }
      do {
        return try await streamOneTurn(openAI: openAI, query: query)
      } catch is CancellationError {
        throw AgentExecutionError.cancelled
      } catch {
        if cancelled { throw AgentExecutionError.cancelled }
        lastError = error
        guard Self.shouldRetry(error), attempt < Self.maxStreamAttempts else {
          throw error
        }
        let delay = Self.retryDelay(forAttempt: attempt)
        emit(
          level: .warning,
          text: "Chat completions stream transient error; retrying",
          detail:
            "attempt \(attempt)/\(Self.maxStreamAttempts) in \(String(format: "%.1f", delay))s — \(error.localizedDescription)",
          kind: .lifecycle,
          status: .running
        )
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }
    // Loop only exits via return or throw, but the compiler can't see that.
    throw lastError
      ?? AgentExecutionError.streamFailed("retry loop exhausted with no recorded error")
  }

  /// Classify whether a thrown error from `chatsStream` is worth
  /// retrying. Tests live in `AgentExecutorTests`; keep the lists here
  /// in sync with the test expectations.
  static func shouldRetry(_ error: Error) -> Bool {
    if let openAIError = error as? OpenAIError {
      switch openAIError {
      case .statusError(_, let statusCode):
        return isTransientHTTPStatus(statusCode)
      case .emptyData:
        // Server returned a 2xx with no body — usually a flaky
        // edge node; cheap to retry.
        return true
      }
    }
    if let urlError = error as? URLError {
      return isTransientURLErrorCode(urlError.code)
    }
    return false
  }

  /// Status codes that represent transient upstream pressure rather
  /// than a permanent client-side problem. Covers Cloudflare 520-526
  /// and the "I'm overloaded" 529 MiniMax has been emitting.
  static func isTransientHTTPStatus(_ statusCode: Int) -> Bool {
    switch statusCode {
    case 408, 425, 429: return true  // request timeout / too early / rate limit
    case 500, 502, 503, 504: return true  // server errors / gateway timeouts
    case 520, 521, 522, 523, 524, 525, 526: return true  // Cloudflare upstream errors
    case 529: return true  // "site is overloaded" (Cloudflare / MiniMax)
    default: return false
    }
  }

  /// `URLError` codes that indicate the connection itself failed, not
  /// that the server returned a definitive answer we should respect.
  static func isTransientURLErrorCode(_ code: URLError.Code) -> Bool {
    switch code {
    case .timedOut, .cannotConnectToHost, .cannotFindHost,
      .networkConnectionLost, .notConnectedToInternet,
      .dnsLookupFailed, .resourceUnavailable,
      .internationalRoamingOff, .callIsActive,
      .dataNotAllowed:
      return true
    default:
      return false
    }
  }

  /// Exponential backoff with ±20% jitter, capped at
  /// `maxStreamRetryDelay`. Attempt is 1-based.
  static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
    let exponential = Self.baseStreamRetryDelay * pow(2.0, Double(attempt - 1))
    let capped = min(exponential, Self.maxStreamRetryDelay)
    let jitterFactor = 0.8 + Double.random(in: 0...0.4)  // 0.8...1.2
    return capped * jitterFactor
  }

  private func streamOneTurn(
    openAI: OpenAI,
    query: ChatQuery
  ) async throws -> AggregatedTurn {
    try await aggregate(stream: openAI.chatsStream(query: query))
  }

  /// Aggregate a chat-completions stream into a single `AggregatedTurn`.
  /// Internal seam so tests can hand a canned `AsyncThrowingStream` in
  /// without standing up an `OpenAI` client. Cancellation honours
  /// `self.cancelled` (so `cancel()` while a turn is in flight still
  /// short-circuits) and `CancellationError` from the upstream stream
  /// itself.
  func aggregate<S: AsyncSequence>(stream: S) async throws -> AggregatedTurn
  where S.Element == ChatStreamResult {
    var assistantText = ""
    var reasoningText = ""
    var pending: [Int: PendingToolCall] = [:]
    var finishReason: String?
    var usage: StreamedTokenUsage?

    for try await chunk in stream {
      if cancelled { throw AgentExecutionError.cancelled }
      // The final chunk emitted by `include_usage` carries an empty
      // `choices` array but a populated `usage` field. Take the last
      // non-nil value we see — upstreams that send usage on every
      // chunk will just keep overwriting it with the running total.
      if let chunkUsage = chunk.usage {
        usage = StreamedTokenUsage(
          inputTokens: chunkUsage.promptTokens,
          outputTokens: chunkUsage.completionTokens,
          totalTokens: chunkUsage.totalTokens
        )
      }
      for choice in chunk.choices {
        if let delta = choice.delta.content {
          assistantText += delta
        }
        if let reasoning = choice.delta.reasoning {
          reasoningText += reasoning
        }
        if let toolCalls = choice.delta.toolCalls {
          for fragment in toolCalls {
            let index = fragment.index
            var current =
              pending[index] ?? PendingToolCall(index: index, id: "", name: "", arguments: "")
            if let id = fragment.id, !id.isEmpty { current.id = id }
            if let name = fragment.function?.name, !name.isEmpty { current.name = name }
            if let args = fragment.function?.arguments { current.arguments += args }
            pending[index] = current
          }
        }
        if let reason = choice.finishReason {
          finishReason = String(describing: reason)
        }
      }
    }

    // Strip <think>...</think> blocks the model might embed when the
    // endpoint doesn't split reasoning into its own field. Move the
    // contents into reasoningText so the assistant message we replay to
    // the API contains only the user-visible reply.
    let (cleaned, extractedReasoning) = Self.stripThinkBlocks(assistantText)
    assistantText = cleaned
    if !extractedReasoning.isEmpty {
      reasoningText += extractedReasoning
    }

    let ordered = pending.keys.sorted().compactMap { pending[$0] }
    let valid = ordered.filter { !$0.id.isEmpty && !$0.name.isEmpty }
    return AggregatedTurn(
      assistantText: assistantText.trimmingCharacters(in: .whitespacesAndNewlines),
      reasoningText: reasoningText.trimmingCharacters(in: .whitespacesAndNewlines),
      toolCalls: valid,
      finishReason: finishReason,
      usage: usage
    )
  }

  static func stripThinkBlocks(_ text: String) -> (String, String) {
    guard text.contains("<think>") else { return (text, "") }
    var output = ""
    var reasoning = ""
    var remaining = Substring(text)
    while let start = remaining.range(of: "<think>") {
      output += remaining[..<start.lowerBound]
      let afterOpen = remaining[start.upperBound...]
      if let end = afterOpen.range(of: "</think>") {
        reasoning += afterOpen[..<end.lowerBound]
        remaining = afterOpen[end.upperBound...]
      } else {
        reasoning += afterOpen
        remaining = ""
        break
      }
    }
    output += remaining
    return (output, reasoning)
  }
}
