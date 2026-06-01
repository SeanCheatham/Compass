import Foundation
import OpenAI

extension AgentExecutor {
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
      assumptionsURL: configuration.assumptionsURL,
      phase: configuration.phase,
      sessionNumber: configuration.sessionNumber,
      toolchainService: configuration.toolchainService,
      hostXcodeService: configuration.hostXcodeService
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

      var rejectedSubmitResult = false
      for toolCall in aggregated.toolCalls {
        if cancelled { throw AgentExecutionError.cancelled }

        if toolCall.name == Self.submitResultToolName {
          // JSON validity already enforced by the pre-flight above.
          let argsData = Data(toolCall.arguments.utf8)
          if let validate = configuration.validateSubmitResult {
            do {
              try validate(argsData)
            } catch {
              Self.rollback(
                messages: &messages,
                nudgeIndices: &remediationNudgeIndices,
                to: messageCountBeforeAssistant
              )
              let nudge = Self.submitResultValidationNudge(
                for: error,
                phase: configuration.phase
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
                correlationID: toolCall.id
              )
              rejectedSubmitResult = true
              break
            }
          }
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

      if rejectedSubmitResult {
        continue
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
      assumptionsURL: configuration.assumptionsURL,
      sessionNumber: configuration.sessionNumber,
      parentTools: configuration.tools,
      parentMaxIterations: configuration.maxIterations,
      parentWallClockTimeout: configuration.wallClockTimeout,
      toolchainService: configuration.toolchainService,
      hostXcodeService: configuration.hostXcodeService,
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
}
