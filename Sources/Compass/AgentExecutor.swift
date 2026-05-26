import Foundation
import OpenAI

/// Outcome of one Plan / Reflect / Develop pass.
///
/// `submitResultArguments` holds the JSON args the model passed to the
/// terminal `submit_result` tool — the structured response Compass decodes
/// into `PlanRunResult` / `DevelopSummary` / `ReflectSummary`.
struct AgentExecutionResult: Equatable {
  var submitResultArguments: Data
  var iterations: Int
  var assistantText: String
  var reasoningText: String
}

/// Configuration for a single AgentExecutor.run() invocation.
struct AgentExecutionConfiguration {
  var settings: AgentRuntimeSettings
  var phase: AgentPhase
  var modelOverride: String
  var systemPrompt: String
  var userPrompt: String
  var tools: [AgentTool]
  var submitResultSchema: AgentToolParametersSchema
  var workingDirectory: URL
  var filesystem: AgentFilesystem
  var bashRunner: AgentBashRunner
  /// Host-side codemap directory. When the agent runs in the Shared VM,
  /// `workingDirectory` is the guest worktree path and is *not* where
  /// the codemap lives — the caller must supply the actual store
  /// location so codemap-backed tools see real entries. `nil` falls
  /// back to `<workingDirectory>/.compass/codemap`, which is correct
  /// only for host-route runs against a canonical repo-local workspace.
  var codemapStoreDirectory: URL?
  /// Host-side completed plan summaries for the `plan_history` tool.
  var planHistoryEntries: [String]
  var toolchainService: (any SharedVMToolchainService)?
  var maxIterations: Int
  var wallClockTimeout: TimeInterval

  init(
    settings: AgentRuntimeSettings,
    phase: AgentPhase,
    modelOverride: String = "",
    systemPrompt: String,
    userPrompt: String,
    tools: [AgentTool],
    submitResultSchema: AgentToolParametersSchema,
    workingDirectory: URL,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    codemapStoreDirectory: URL? = nil,
    planHistoryEntries: [String] = [],
    toolchainService: (any SharedVMToolchainService)? = nil,
    maxIterations: Int = 512,
    wallClockTimeout: TimeInterval = 60 * 60
  ) {
    self.settings = settings
    self.phase = phase
    self.modelOverride = modelOverride
    self.systemPrompt = systemPrompt
    self.userPrompt = userPrompt
    self.tools = tools
    self.submitResultSchema = submitResultSchema
    self.workingDirectory = workingDirectory
    self.filesystem = filesystem
    self.bashRunner = bashRunner
    self.codemapStoreDirectory = codemapStoreDirectory
    self.planHistoryEntries = planHistoryEntries
    self.toolchainService = toolchainService
    self.maxIterations = maxIterations
    self.wallClockTimeout = wallClockTimeout
  }

  /// Effective context window from the runtime settings. `0` means
  /// auto-compaction is disabled.
  var contextWindowTokens: Int { settings.contextWindowTokens }
}

enum AgentExecutionError: LocalizedError, Equatable {
  case streamFailed(String)
  case maxIterationsExceeded(Int)
  case wallClockExceeded(TimeInterval)
  case modelStoppedWithoutSubmitResult
  case toolCallDecodeFailed(name: String, detail: String)
  case duplicateToolName(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .streamFailed(let detail): return "Chat completions stream failed: \(detail)"
    case .maxIterationsExceeded(let n): return "Agent exceeded max iterations (\(n))"
    case .wallClockExceeded(let timeout):
      return "Agent exceeded wall-clock timeout (\(Int(timeout))s)"
    case .modelStoppedWithoutSubmitResult: return "Model stopped without calling submit_result"
    case .toolCallDecodeFailed(let name, let detail):
      return "Tool call \(name) had undecodable args: \(detail)"
    case .duplicateToolName(let name): return "Duplicate tool name in registry: \(name)"
    case .cancelled: return "Agent execution cancelled"
    }
  }

  /// True when the agent's wall-clock or iteration budget was the cause
  /// — i.e. it didn't finish via `submit_result` because it ran out of
  /// time/turns, not because the LLM stream broke or the user cancelled.
  /// Develop treats these as a retryable "failed attempt" so the next
  /// attempt gets a fresh budget; everything else surfaces as a session
  /// failure.
  var isAgentBudgetExhaustion: Bool {
    switch self {
    case .wallClockExceeded, .maxIterationsExceeded:
      return true
    default:
      return false
    }
  }
}

/// Runs the OpenAI-compatible chat-completions loop with tool dispatch.
/// Terminates when the model invokes the `submit_result` tool, whose
/// `parameters` schema is the phase's output schema.
final class AgentExecutor {
  static let submitResultToolName = "submit_result"

  /// Per-turn output budget Compass requests from the chat completions
  /// endpoint. Set high so `submit_result` JSON (which carries
  /// `state.completed`, lessons, and free-form summaries) doesn't get
  /// truncated mid-tool-call. Modern providers cap this on their end
  /// — MiniMax M-series goes to ~80k, Claude Sonnet 64k, OpenAI 16–100k
  /// depending on model — and a value above the provider's cap is
  /// typically silently clamped, so a generous default is the right
  /// trade-off against the cascade we used to hit on truncation
  /// (rejected submit_result → unparseable tool-call args in the next
  /// request → upstream 400).
  static let maxCompletionTokensPerTurn = 65_536

  /// How many times we'll re-issue a chat completions request when the
  /// upstream returns a transient error (overload, rate limit, network
  /// blip) before giving up on the turn. Includes the initial attempt,
  /// so a value of 5 means up to 4 retries.
  static let maxStreamAttempts = 5

  /// Base delay for exponential backoff between retries (seconds). The
  /// effective delay is `base * 2^(attempt-1)` with ±20% jitter, capped
  /// at `maxStreamRetryDelay`.
  static let baseStreamRetryDelay: TimeInterval = 1.0
  static let maxStreamRetryDelay: TimeInterval = 30.0

  /// Fraction of the configured context window at which the executor
  /// runs auto-compaction. We measure against a chars-per-token estimate
  /// of the current `messages` array (see `estimatedTokens(in:)`); the
  /// next turn also adds tool-result messages, so triggering at 0.75
  /// leaves headroom for one more full turn before the request itself
  /// would exceed the window.
  static let compactionThresholdFraction: Double = 0.75

  /// Conventional chars-per-token divisor for English + JSON payloads.
  /// Used to estimate prompt token cost from the encoded `messages`
  /// array — chosen over provider-reported `usage.totalTokens` because
  /// several OpenAI-compatible endpoints (MiniMax included) drop usage
  /// on tool-calling stream chunks, silently disabling compaction for
  /// the whole run.
  static let estimatedCharsPerToken: Int = 4

  /// Per-call output cap for the summarization request. The summary
  /// replaces the entire mid-conversation history, so we let it run
  /// long enough to capture pending file paths / errors / next steps
  /// without bumping into the model's hard ceiling.
  static let maxSummaryCompletionTokens: Int = 8_192

  private let onEvent: @Sendable (LiveEvent) -> Void
  private var cancelled = false

  init(onEvent: @Sendable @escaping (LiveEvent) -> Void = { _ in }) {
    self.onEvent = onEvent
  }

  func cancel() {
    cancelled = true
  }

  func run(_ configuration: AgentExecutionConfiguration) async throws -> AgentExecutionResult {
    // Foundation Models (on-device) is a separate backend with its own
    // session + tool-dispatch shape — see `FoundationModelsAgentRuntime`.
    // Branch up front so the OpenAI-compatible stream/tool/compaction
    // machinery below stays focused on its own provider class.
    if configuration.settings.textProvider == .appleFoundationModels {
      let onEvent = self.onEvent
      return try await FoundationModelsAgentRuntime.run(
        configuration,
        isCancelled: { [weak self] in self?.cancelled ?? false },
        emit: { event in onEvent(event) }
      )
    }

    try Self.ensureUniqueToolNames(configuration.tools)
    let registry = Dictionary(uniqueKeysWithValues: configuration.tools.map { ($0.spec.name, $0) })

    let requestRecorder = UpstreamRequestRecorder()
    let openAI = Self.makeClient(
      settings: configuration.settings, requestRecorder: requestRecorder)
    let openAITools = try Self.buildOpenAITools(configuration: configuration)
    let delegateRunner: AgentDelegateRunner? = Self.makeDelegateRunner(
      configuration: configuration, onEvent: onEvent)
    let toolContext = AgentToolContext(
      workingDirectory: configuration.workingDirectory,
      filesystem: configuration.filesystem,
      bashRunner: configuration.bashRunner,
      delegateRunner: delegateRunner,
      codemapStoreDirectory: configuration.codemapStoreDirectory,
      planHistoryEntries: configuration.planHistoryEntries,
      toolchainService: configuration.toolchainService
    )
    let model = configuration.settings.model(
      for: configuration.phase, sidebarOverride: configuration.modelOverride)

    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      .system(.init(content: .textContent(configuration.systemPrompt))),
      .user(.init(content: .string(configuration.userPrompt))),
    ]
    // Indices of `.user` messages we appended as remediation nudges (for
    // invalid submit_result or "no tool calls" stalls). Tracked so two
    // consecutive failed iterations collapse into a single nudge instead
    // of pushing back-to-back `.user` messages, which strict providers
    // reject as a malformed role sequence. The set is mutated alongside
    // `messages`; on rollback we drop entries whose index no longer
    // exists.
    var remediationNudgeIndices = Set<Int>()
    var assistantTranscript = ""
    var reasoningTranscript = ""
    let startedAt = Date()

    for iteration in 1...configuration.maxIterations {
      if cancelled { throw AgentExecutionError.cancelled }
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed > configuration.wallClockTimeout {
        throw AgentExecutionError.wallClockExceeded(configuration.wallClockTimeout)
      }

      emit(level: .info, text: "Agent iteration \(iteration)", kind: .lifecycle, status: .running)

      let query = ChatQuery(
        messages: messages,
        model: model,
        maxCompletionTokens: Self.maxCompletionTokensPerTurn,
        tools: openAITools,
        stream: true,
        // Asks the upstream to emit a final usage chunk for log
        // observability only — compaction itself runs off a local
        // chars/4 estimate so providers that drop usage on
        // tool-calling chunks can't silently disable it.
        streamOptions: .init(includeUsage: true)
      )

      let aggregated: AggregatedTurn
      do {
        aggregated = try await streamOneTurnWithRetry(openAI: openAI, query: query)
      } catch is CancellationError {
        throw AgentExecutionError.cancelled
      } catch {
        if cancelled { throw AgentExecutionError.cancelled }
        let enriched = await enrichedStreamFailureDetail(
          error: error, recorder: requestRecorder)
        throw AgentExecutionError.streamFailed(enriched)
      }

      assistantTranscript += aggregated.assistantText
      reasoningTranscript += aggregated.reasoningText

      if !aggregated.assistantText.isEmpty {
        emit(
          level: .raw, text: "Assistant", detail: previewString(aggregated.assistantText),
          kind: .agentMessage, status: .completed)
      }

      // Snapshot the message count *before* this iteration appends its
      // assistant turn. If any tool call in this turn carries malformed
      // JSON arguments we roll back to here, dropping the assistant
      // (and, in the pre-flight path, never appending tool responses
      // for its siblings). Leaving a `.tool` response without its
      // declaring assistant turn would orphan its `toolCallId`, which
      // is exactly the 400 cascade MiniMax surfaces.
      let messageCountBeforeAssistant = messages.count

      messages.append(
        .assistant(
          .init(
            content: aggregated.assistantText.isEmpty
              ? nil : .textContent(aggregated.assistantText),
            toolCalls: aggregated.toolCalls.isEmpty
              ? nil : aggregated.toolCalls.map { $0.asAssistantToolCall() }
          )))

      // No tool calls → either submit_result was missed or the model
      // gave up. Either way, nudge it once; on the next loop we'll
      // either get tool calls or break out.
      if aggregated.toolCalls.isEmpty {
        if aggregated.finishReason == "stop" || aggregated.finishReason == nil {
          Self.appendRemediationNudge(
            "You must call the submit_result tool to finish this phase. Use it now.",
            messages: &messages,
            nudgeIndices: &remediationNudgeIndices
          )
          continue
        }
      }

      // Pre-flight: any tool call whose `arguments` field isn't
      // well-formed JSON will be rejected by strict upstream
      // providers (MiniMax has been observed doing this) on the
      // *next* request, with a 400 that aborts the whole run.
      // MiniMax has been seen truncating mid-token without setting
      // `finishReason == "length"`, so this catches all sources of
      // bad args: silent truncation, model-emitted escape bugs in
      // big `edit_file` / `write_file` payloads, etc. Drop the
      // assistant turn and inject a remediation nudge instead of
      // invoking any tools — replaying the bad turn would orphan
      // its tool responses too.
      if let bad = aggregated.toolCalls.first(where: {
        (try? JSONSerialization.jsonObject(with: Data($0.arguments.utf8))) == nil
      }) {
        Self.rollback(
          messages: &messages,
          nudgeIndices: &remediationNudgeIndices,
          to: messageCountBeforeAssistant
        )
        let nudge: InvalidToolArgumentsNudge =
          bad.name == Self.submitResultToolName
          ? Self.invalidSubmitResultNudge(
            finishReason: aggregated.finishReason,
            argumentsPreview: previewString(bad.arguments),
            maxCompletionTokens: Self.maxCompletionTokensPerTurn
          )
          : Self.invalidToolArgumentsNudge(
            toolName: bad.name,
            finishReason: aggregated.finishReason,
            argumentsPreview: previewString(bad.arguments),
            maxCompletionTokens: Self.maxCompletionTokensPerTurn
          )
        Self.appendRemediationNudge(
          nudge.userMessage,
          messages: &messages,
          nudgeIndices: &remediationNudgeIndices
        )
        emit(
          level: .warning,
          text: nudge.eventText,
          detail: nudge.eventDetail,
          kind: .agentMessage,
          status: .failed,
          correlationID: bad.id
        )
        continue
      }

      for toolCall in aggregated.toolCalls {
        if cancelled { throw AgentExecutionError.cancelled }

        if toolCall.name == Self.submitResultToolName {
          // JSON validity already enforced by the pre-flight above.
          let argsData = Data(toolCall.arguments.utf8)
          emit(
            level: .success, text: "submit_result", detail: previewString(toolCall.arguments),
            kind: .agentMessage, status: .completed, correlationID: toolCall.id)
          return AgentExecutionResult(
            submitResultArguments: argsData,
            iterations: iteration,
            assistantText: assistantTranscript,
            reasoningText: reasoningTranscript
          )
        }

        guard let tool = registry[toolCall.name] else {
          let detail = "Unknown tool: \(toolCall.name)"
          messages.append(.tool(.init(content: .textContent(detail), toolCallId: toolCall.id)))
          emit(
            level: .error, text: detail, kind: .lifecycle, status: .failed,
            correlationID: toolCall.id)
          continue
        }

        emitToolStart(
          name: toolCall.name, arguments: toolCall.arguments, correlationID: toolCall.id)

        let result: AgentToolInvocationResult
        do {
          result = try await tool.invoke(
            arguments: Data(toolCall.arguments.utf8), context: toolContext)
        } catch let toolError as AgentToolError {
          // Preserve the typed kind so the UI / logs can categorize.
          let failure = AgentToolInvocationResult.failure(toolError)
          messages.append(
            .tool(.init(content: .textContent(failure.content), toolCallId: toolCall.id)))
          emitToolEnd(
            name: toolCall.name, arguments: toolCall.arguments, result: failure,
            correlationID: toolCall.id)
          continue
        } catch {
          let message = "Tool \(toolCall.name) threw: \(error.localizedDescription)"
          messages.append(.tool(.init(content: .textContent(message), toolCallId: toolCall.id)))
          emitToolEnd(
            name: toolCall.name, arguments: toolCall.arguments,
            result: .failure(message, kind: .unknown),
            correlationID: toolCall.id)
          continue
        }
        messages.append(
          .tool(.init(content: .textContent(result.content), toolCallId: toolCall.id)))
        emitToolEnd(
          name: toolCall.name, arguments: toolCall.arguments, result: result,
          correlationID: toolCall.id)
      }

      let estimated = Self.estimatedTokens(in: messages)
      if Self.shouldCompact(
        estimatedTokens: estimated, contextWindowTokens: configuration.contextWindowTokens)
      {
        try await compactMessages(
          openAI: openAI,
          model: model,
          messages: &messages,
          estimatedTokensBeforeCompaction: estimated,
          contextWindowTokens: configuration.contextWindowTokens
        )
        // Compaction rewrites the entire `messages` array (keeps system,
        // original user, appends a summary recap), so all previously
        // tracked nudge indices are stale. Drop them; any nudges we add
        // in subsequent iterations will be re-tracked from scratch.
        remediationNudgeIndices.removeAll()
      }
    }
    throw AgentExecutionError.maxIterationsExceeded(configuration.maxIterations)
  }

  /// Build the sub-agent runner for this turn, or `nil` when this
  /// configuration is itself a sub-agent (we detect that by the absence
  /// of `AgentDelegateTool` from the tool list — top-level configs
  /// always include it). Returning nil leaves the delegate tool — if
  /// somehow re-added in a child — surfacing a clean failure instead
  /// of crashing on a missing runner.
  static func makeDelegateRunner(
    configuration: AgentExecutionConfiguration,
    onEvent: @Sendable @escaping (LiveEvent) -> Void
  ) -> AgentDelegateRunner? {
    let hasDelegateTool = configuration.tools.contains {
      $0.spec.name == AgentDelegateTool.toolName
    }
    guard hasDelegateTool else { return nil }
    return AgentExecutorDelegateRunner(
      settings: configuration.settings,
      parentPhase: configuration.phase,
      parentModelOverride: configuration.modelOverride,
      workingDirectory: configuration.workingDirectory,
      filesystem: configuration.filesystem,
      bashRunner: configuration.bashRunner,
      codemapStoreDirectory: configuration.codemapStoreDirectory,
      parentTools: configuration.tools,
      parentMaxIterations: configuration.maxIterations,
      parentWallClockTimeout: configuration.wallClockTimeout,
      toolchainService: configuration.toolchainService,
      onEvent: onEvent
    )
  }

  static func ensureUniqueToolNames(_ tools: [AgentTool]) throws {
    var seen = Set<String>()
    for tool in tools {
      if tool.spec.name == Self.submitResultToolName {
        throw AgentExecutionError.duplicateToolName(tool.spec.name)
      }
      if !seen.insert(tool.spec.name).inserted {
        throw AgentExecutionError.duplicateToolName(tool.spec.name)
      }
    }
  }

  static func makeClient(
    settings: AgentRuntimeSettings,
    requestRecorder: UpstreamRequestRecorder? = nil
  ) -> OpenAI {
    let components = URLComponents(url: settings.baseURL, resolvingAgainstBaseURL: false)
    let host = components?.host ?? "api.openai.com"
    let port = components?.port ?? (settings.baseURL.scheme == "http" ? 80 : 443)
    let scheme = components?.scheme ?? "https"
    let basePath = components.flatMap { $0.path.isEmpty ? nil : $0.path } ?? "/v1"

    let configuration = OpenAI.Configuration(
      token: settings.apiKey,
      organizationIdentifier: nil,
      host: host,
      port: port,
      scheme: scheme,
      basePath: basePath,
      timeoutInterval: 600.0,
      customHeaders: [:],
      parsingOptions: [.relaxed]
    )
    return OpenAI(
      configuration: configuration,
      middlewares: requestRecorder.map { [$0] } ?? []
    )
  }

  static func buildOpenAITools(
    configuration: AgentExecutionConfiguration
  ) throws -> [ChatQuery.ChatCompletionToolParam] {
    var out: [ChatQuery.ChatCompletionToolParam] = []
    for tool in configuration.tools {
      out.append(try Self.buildFunctionParam(spec: tool.spec))
    }
    let submitSpec = AgentToolSpec(
      name: Self.submitResultToolName,
      description:
        "Call this once with the structured result for this phase. The arguments object must match the phase output schema. Calling this ends the phase.",
      parameters: configuration.submitResultSchema
    )
    out.append(try Self.buildFunctionParam(spec: submitSpec))
    return out
  }

  private static func buildFunctionParam(spec: AgentToolSpec) throws
    -> ChatQuery.ChatCompletionToolParam
  {
    let schema = try JSONDecoder().decode(JSONSchema.self, from: spec.parameters.json)
    return ChatQuery.ChatCompletionToolParam(
      function: .init(
        name: spec.name,
        description: spec.description,
        parameters: schema,
        strict: nil
      ))
  }

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
  private func streamOneTurnWithRetry(
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
    var totalTokens: Int?

    for try await chunk in stream {
      if cancelled { throw AgentExecutionError.cancelled }
      // The final chunk emitted by `include_usage` carries an empty
      // `choices` array but a populated `usage` field. Take the last
      // non-nil value we see — upstreams that send usage on every
      // chunk will just keep overwriting it with the running total.
      if let usage = chunk.usage {
        totalTokens = usage.totalTokens
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
      totalTokens: totalTokens
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

  // MARK: - Invalid-tool-arguments remediation

  /// Wording for the user-visible event and the user-side nudge
  /// appended to `messages` when a tool call arrived with invalid JSON
  /// arguments. Split out so the wording stays unit-testable without
  /// needing to drive the full streaming loop.
  struct InvalidToolArgumentsNudge: Equatable {
    var eventText: String
    var eventDetail: String
    var userMessage: String
  }

  /// Build the remediation copy for a malformed `submit_result` turn.
  /// `finishReason == "length"` is the canonical truncation signal;
  /// providers that omit it still produce invalid JSON the same way
  /// (mid-token cutoff), so we fall back to a generic "args wouldn't
  /// parse" nudge that nudges the model toward shorter output.
  static func invalidSubmitResultNudge(
    finishReason: String?,
    argumentsPreview: String,
    maxCompletionTokens: Int
  ) -> InvalidToolArgumentsNudge {
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "submit_result truncated",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)); asking the model to retry with shorter fields.",
        userMessage:
          "Your previous `submit_result` was truncated by the output-token limit. Retry with the same structure but shorter free-form text — trim `summary`, keep plan fields concise, and avoid restating context. The tool args must be complete, valid JSON."
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "submit_result rejected",
      eventDetail: "submit_result args are not valid JSON: \(argumentsPreview)",
      userMessage:
        "Your previous `submit_result` arguments could not be parsed as JSON — the upstream often truncates mid-token without flagging it. Retry with the same structure but noticeably shorter free-form text: trim `summary`, keep plan fields concise, and avoid restating prior context. The tool args must be complete, valid JSON."
    )
  }

  /// Build the remediation copy for any non-`submit_result` tool call
  /// whose `arguments` field isn't valid JSON. Two common causes: the
  /// model emitted unescaped control characters or unbalanced strings
  /// inside a large `edit_file` / `write_file` payload, or the upstream
  /// silently truncated mid-token (MiniMax has been observed doing this
  /// without setting `finishReason == "length"`). The `length` branch
  /// owns the truncation-specific wording; the fallthrough handles both
  /// silent-truncation and model-side escape errors with a generic
  /// "retry with valid JSON" nudge.
  static func invalidToolArgumentsNudge(
    toolName: String,
    finishReason: String?,
    argumentsPreview: String,
    maxCompletionTokens: Int
  ) -> InvalidToolArgumentsNudge {
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "\(toolName) truncated",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)); asking the model to retry with a smaller payload.",
        userMessage:
          "Your previous `\(toolName)` call was truncated by the output-token limit, so its arguments were not valid JSON. Retry with a smaller payload — for file edits, break the change into multiple smaller `edit_file` calls instead of one large one. The tool args must be complete, valid JSON."
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "\(toolName) rejected",
      eventDetail: "\(toolName) args are not valid JSON: \(argumentsPreview)",
      userMessage:
        "Your previous `\(toolName)` arguments could not be parsed as JSON. The upstream rejects the next request when any tool call's arguments are malformed, so the call was dropped without invoking the tool. Retry with valid JSON — pay attention to escaping (`\\n` for newlines, `\\\"` for quotes inside strings) and to closing all braces/brackets. If the payload is very large, split it into multiple smaller calls."
    )
  }

  /// Drop everything from `messages` from `targetCount` onward. Used when
  /// an iteration's `submit_result` arrived malformed: we need to peel
  /// back the assistant turn *and* any `.tool` responses we appended for
  /// sibling tool calls in the same turn (those responses would orphan
  /// without the assistant turn that declared the matching tool_call
  /// IDs). Also drops any nudge-index entries that referred to messages
  /// we just removed, so the index set stays consistent with the
  /// truncated array.
  static func rollback(
    messages: inout [ChatQuery.ChatCompletionMessageParam],
    nudgeIndices: inout Set<Int>,
    to targetCount: Int
  ) {
    guard targetCount >= 0, targetCount < messages.count else { return }
    messages.removeLast(messages.count - targetCount)
    nudgeIndices = nudgeIndices.filter { $0 < targetCount }
  }

  /// Append a `.user` remediation message and track its index. If the
  /// last message is itself a tracked remediation nudge, replace it
  /// instead of appending — two consecutive `.user` messages from
  /// back-to-back failed iterations is a malformed role sequence and
  /// strict providers (MiniMax has been observed doing this) reject the
  /// next request with a 400.
  static func appendRemediationNudge(
    _ text: String,
    messages: inout [ChatQuery.ChatCompletionMessageParam],
    nudgeIndices: inout Set<Int>
  ) {
    let lastIndex = messages.count - 1
    if lastIndex >= 0, nudgeIndices.contains(lastIndex) {
      messages.removeLast()
      nudgeIndices.remove(lastIndex)
    }
    messages.append(.user(.init(content: .string(text))))
    nudgeIndices.insert(messages.count - 1)
  }

  // MARK: - Auto-compaction

  /// True when the current `messages` array — sized via
  /// `estimatedTokens(in:)` — has used enough of the configured context
  /// window that the *next* turn risks an out-of-context rejection.
  /// `contextWindowTokens <= 0` disables compaction so tests and unusual
  /// setups can opt out cleanly.
  static func shouldCompact(estimatedTokens: Int, contextWindowTokens: Int) -> Bool {
    guard contextWindowTokens > 0 else { return false }
    let threshold = Int(Double(contextWindowTokens) * compactionThresholdFraction)
    return estimatedTokens >= threshold
  }

  /// Rough chars/4 token estimate for the encoded `messages` array.
  /// JSON-encoding each message captures the same structural overhead
  /// the provider sees on the wire (role tags, tool_call IDs, content
  /// envelopes) so the estimate stays comparable across plain text,
  /// assistant tool_calls, and tool responses. A message that fails to
  /// encode contributes 0 — safer to under-count one message than to
  /// abort the run, since the rest of the history will still dominate.
  static func estimatedTokens(
    in messages: [ChatQuery.ChatCompletionMessageParam]
  ) -> Int {
    let encoder = JSONEncoder()
    let totalChars = messages.reduce(0) { acc, message in
      let bytes = (try? encoder.encode(message))?.count ?? 0
      return acc + bytes
    }
    return (totalChars + estimatedCharsPerToken - 1) / estimatedCharsPerToken
  }

  /// Re-issue a tool-free chat completion that asks the model to
  /// summarize the current conversation, then collapse the message
  /// history down to `[system, originalUserPrompt, summaryRecap]`.
  /// A summarization failure is logged but non-fatal — the run
  /// continues with the uncompacted history rather than aborting an
  /// in-flight phase mid-stream.
  private func compactMessages(
    openAI: OpenAI,
    model: Model,
    messages: inout [ChatQuery.ChatCompletionMessageParam],
    estimatedTokensBeforeCompaction: Int,
    contextWindowTokens: Int
  ) async throws {
    guard messages.count >= 2 else { return }
    emit(
      level: .info,
      text: "Auto-compacting conversation",
      detail:
        "Context at ~\(estimatedTokensBeforeCompaction) / \(contextWindowTokens) estimated tokens (≥ \(Int(Self.compactionThresholdFraction * 100))%). Summarizing prior turns to free space.",
      kind: .lifecycle,
      status: .running
    )

    let summaryMessages =
      messages + [
        .user(.init(content: .string(Prompts.conversationSummarizationInstruction)))
      ]
    // No `tools:` — the summary call must return plain text, not a
    // tool invocation. `include_usage` lets us log the post-compaction
    // budget for observability.
    let summaryQuery = ChatQuery(
      messages: summaryMessages,
      model: model,
      maxCompletionTokens: Self.maxSummaryCompletionTokens,
      stream: true,
      streamOptions: .init(includeUsage: true)
    )

    let summaryTurn: AggregatedTurn
    do {
      summaryTurn = try await streamOneTurnWithRetry(openAI: openAI, query: summaryQuery)
    } catch is CancellationError {
      throw AgentExecutionError.cancelled
    } catch {
      if cancelled { throw AgentExecutionError.cancelled }
      emit(
        level: .warning,
        text: "Auto-compaction failed; continuing with full history",
        detail: error.localizedDescription,
        kind: .lifecycle,
        status: .failed
      )
      return
    }

    let summary = summaryTurn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !summary.isEmpty else {
      emit(
        level: .warning,
        text: "Auto-compaction produced empty summary; keeping prior history",
        kind: .lifecycle,
        status: .failed
      )
      return
    }

    let collapsedCount = messages.count
    messages = Self.compactedMessages(
      system: messages[0],
      originalUser: messages[1],
      summary: summary
    )
    emit(
      level: .info,
      text: "Auto-compacted conversation",
      detail:
        "Collapsed \(collapsedCount) messages into a summary (~\(summaryTurn.totalTokens ?? 0) tokens).",
      kind: .lifecycle,
      status: .completed
    )
  }

  /// Rebuild the message history after a successful summarization.
  /// Keeping the original system prompt and the original user prompt
  /// gives the next turn the same phase framing it started with; the
  /// summary recap stands in for everything that happened between.
  static func compactedMessages(
    system: ChatQuery.ChatCompletionMessageParam,
    originalUser: ChatQuery.ChatCompletionMessageParam,
    summary: String
  ) -> [ChatQuery.ChatCompletionMessageParam] {
    let recap = """
      The conversation prior to this point was auto-compacted to stay within the model's context window. Use the summary below to resume — it captures the original goal, what was done, key findings, and the immediate next step.

      --- Compacted conversation summary ---
      \(summary)
      --- End compacted summary ---

      Continue the task from where the summary leaves off. When the phase is complete, call `submit_result` exactly as instructed in the original task.
      """
    return [
      system,
      originalUser,
      .user(.init(content: .string(recap))),
    ]
  }

  // MARK: - LiveEvent mapping

  private func emit(
    level: LiveLine.Level = .info,
    text: String,
    detail: String? = nil,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none,
    correlationID: String? = nil
  ) {
    onEvent(
      LiveEvent(
        level: level, text: text, detail: detail, kind: kind, status: status,
        correlationID: correlationID))
  }

  private func emitToolStart(name: String, arguments: String, correlationID: String) {
    let kind = liveKind(forTool: name)
    let level: LiveLine.Level = kind == .command ? .raw : .info
    let detail = previewString(arguments)
    emit(
      level: level, text: toolTitle(name: name, arguments: arguments), detail: detail, kind: kind,
      status: .running, correlationID: correlationID)
  }

  private func emitToolEnd(
    name: String, arguments: String, result: AgentToolInvocationResult, correlationID: String
  ) {
    let kind = liveKind(forTool: name)
    let status: LiveLine.Status = result.isError ? .failed : .completed
    let level: LiveLine.Level = result.isError ? .error : (kind == .command ? .success : .info)
    emit(
      level: level, text: toolTitle(name: name, arguments: arguments),
      detail: previewString(result.content), kind: kind, status: status,
      correlationID: correlationID)
  }

  private func liveKind(forTool name: String) -> LiveLine.Kind {
    switch name {
    case AgentBashTool.toolName: return .command
    case AgentWriteFileTool.toolName, AgentEditFileTool.toolName: return .fileChange
    default: return .lifecycle
    }
  }

  /// Build a one-line title that names the tool *and* the most relevant argument
  /// (bash command, file path, search pattern, ...) so the live log reads as
  /// "what is the agent doing" instead of just "which tool was called".
  private func toolTitle(name: String, arguments: String) -> String {
    if let descriptor = toolDescriptor(name: name, arguments: arguments) {
      return "\(name) · \(descriptor)"
    }
    return "Tool \(name)"
  }

  private func toolDescriptor(name: String, arguments: String) -> String? {
    guard let data = arguments.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    func string(_ key: String) -> String? {
      guard let raw = json[key] as? String else { return nil }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    switch name {
    case AgentBashTool.toolName:
      return string("command").map { truncateOneLine($0, limit: 100) }
    case AgentReadFileTool.toolName,
      AgentWriteFileTool.toolName,
      AgentEditFileTool.toolName:
      return string("path")
    case AgentLsTool.toolName:
      return string("path") ?? "."
    case AgentGrepTool.toolName, AgentGlobTool.toolName:
      guard let pattern = string("pattern") else { return nil }
      if let path = string("path") {
        return "\(pattern) in \(path)"
      }
      return pattern
    case AgentOutlineTool.toolName,
      AgentSummaryTool.toolName,
      AgentImportersOfTool.toolName:
      return string("path")
    case AgentFindSymbolTool.toolName:
      guard let name = string("name") else { return nil }
      if let kind = string("kind") { return "\(name) (\(kind))" }
      return name
    case AgentListFilesTool.toolName:
      return string("filter") ?? "(all)"
    default:
      return nil
    }
  }

  private func truncateOneLine(_ s: String, limit: Int) -> String {
    let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
    if firstLine.count <= limit { return firstLine }
    return String(firstLine.prefix(limit)) + "…"
  }

  private func previewString(_ s: String, limit: Int = 280) -> String {
    let stripped = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if stripped.count <= limit { return stripped }
    return String(stripped.prefix(limit)) + " ..."
  }

}
