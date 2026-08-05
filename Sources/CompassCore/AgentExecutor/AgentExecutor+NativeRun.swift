import Foundation

public extension AgentExecutor {
  /// Native tool-calling loop for capable backends (cloud models and modern
  /// MLX checkpoints). The provider owns tool-call parsing; Compass keeps the
  /// phase submit gauntlet, verify bookkeeping, and compaction.
  ///
  /// The phase submit envelope becomes a synthetic `<phase>_submit` tool whose
  /// parameters are the phase's output schema, so the same validators decode
  /// the payload unchanged.
  func runNative(
    _ configuration: AgentExecutionConfiguration,
    chatRuntime: any AgentChatGenerating,
    textRuntime: any LocalModelGenerating
  ) async throws -> AgentExecutionResult {
    try AgentExecutor.ensureUniqueToolNames(configuration.tools)

    let startedAt = Date()
    let toolContext = AgentToolContext(
      workingDirectory: configuration.workingDirectory,
      agentVisibleWorkspacePath: configuration.agentVisibleWorkspacePath,
      filesystem: configuration.filesystem,
      bashRunner: configuration.bashRunner,
      readTracker: AgentReadTracker(),
      delegateRunner: AgentExecutor.makeDelegateRunner(
        configuration: configuration,
        onEvent: onEvent
      ),
      codemapStoreDirectory: configuration.codemapStoreDirectory,
      planHistoryEntries: configuration.planHistoryEntries,
      assumptionsURL: configuration.assumptionsURL,
      phase: configuration.phase,
      sessionNumber: configuration.sessionNumber,
      enforceReadBeforeWrite: false
    )
    let toolsByName = Dictionary(uniqueKeysWithValues: configuration.tools.map { ($0.spec.name, $0) })

    let submitKind = configuration.continuationPhase.submitKind
    let submitTool = AgentToolSpec(
      name: submitKind,
      description:
        "Finish the \(configuration.continuationPhase.rawValue) phase. Call this exactly once when the phase goal is met; the arguments are the phase's structured result payload.",
      parameters: configuration.submitResultSchema
    )
    let toolSpecs = configuration.tools.map(\.spec) + [submitTool]

    var messages: [AgentChatMessage] = [
      .system(configuration.systemPrompt),
      .user(configuration.userPrompt),
    ]

    var iterations = 0
    var assistantTranscript = ""
    var reasoningTranscript = ""
    var tokenUsage = AgentRunTokenUsage()
    var lastPromptTokens: Int?
    var consecutiveNoToolCallTurns = 0
    var lastFailedToolCall: NativeToolCallSignature?
    var repeatedFailedToolCallCount = 0
    var lastSuccessfulVerifyCommand: String?
    var lastFailedVerifyCommand: String?
    var failedVerifyInvalidatedByMutationCommand: String?

    while iterations < configuration.maxIterations {
      if cancelled { throw AgentExecutionError.cancelled }
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed > configuration.wallClockTimeout {
        throw AgentExecutionError.wallClockExceeded(configuration.wallClockTimeout)
      }

      if configuration.contextWindowTokens > 0,
        Self.nativeMessagesNeedCompaction(
          messages: messages,
          lastPromptTokens: lastPromptTokens,
          configuration: configuration
        )
      {
        do {
          if let compaction = try await Self.compactNativeMessages(
            configuration: configuration,
            runtime: textRuntime,
            messages: messages
          ) {
            messages = compaction
            emit(
              level: .info,
              text: "Compacted conversation history",
              detail: nil,
              kind: .lifecycle,
              status: .completed
            )
          }
        } catch is CancellationError {
          throw AgentExecutionError.cancelled
        } catch let agentError as AgentExecutionError {
          throw agentError
        } catch {
          emit(
            level: .warning,
            text: "Conversation compaction skipped",
            detail: previewString(error.localizedDescription),
            kind: .lifecycle,
            status: .failed
          )
        }
      }

      iterations += 1
      emit(
        level: .info,
        text: "Agent turn \(iterations)",
        kind: .lifecycle,
        status: .running
      )

      let response: AgentChatResponse
      do {
        response = try await chatRuntime.generateChat(
          request: AgentChatRequest(
            modelID: configuration.settings.model(
              for: configuration.phase,
              sidebarOverride: configuration.modelOverride
            ),
            messages: messages,
            tools: toolSpecs,
            maxOutputTokens: Self.maxCompletionTokensPerTurn,
            logLabel: Self.nativeGenerationLogLabel(
              configuration: configuration,
              iteration: iterations
            ),
            routingHint: .cloudPrimary
          )
        )
      } catch is CancellationError {
        throw AgentExecutionError.cancelled
      } catch let agentError as AgentExecutionError {
        throw agentError
      } catch {
        throw AgentExecutionError.streamFailed(error.localizedDescription)
      }

      tokenUsage.recordTurn(
        inputTokens: response.tokenUsage.inputTokens,
        outputTokens: response.tokenUsage.outputTokens,
        totalTokens: response.tokenUsage.totalTokens,
        isEstimated: response.tokenUsage.usesEstimate,
        streamedUsageAvailable: response.tokenUsage.streamedUsageAvailable
      )
      if !response.tokenUsage.usesEstimate, response.tokenUsage.inputTokens > 0 {
        lastPromptTokens = response.tokenUsage.inputTokens
      }
      if let durationMs = response.tokenUsage.durationMs {
        tokenUsage.durationMs = (tokenUsage.durationMs ?? 0) + durationMs
      }

      let trimmedReasoning = response.reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedReasoning.isEmpty {
        reasoningTranscript +=
          reasoningTranscript.isEmpty
          ? trimmedReasoning
          : "\n\n\(trimmedReasoning)"
        let displayThinking = Self.capHead(
          trimmedReasoning,
          bytes: Self.payloadMaxTerminalBytes
        )
        emit(
          level: .raw,
          text: "Thinking",
          detail: previewString(trimmedReasoning),
          kind: .agentMessage,
          status: .completed,
          payload: .thinking(text: displayThinking)
        )
      }

      if !response.text.isEmpty {
        assistantTranscript += assistantTranscript.isEmpty ? response.text : "\n\n\(response.text)"
        emit(
          level: .raw,
          text: "Assistant message",
          detail: previewString(response.text),
          kind: .agentMessage,
          status: .completed
        )
      }

      let reasoningForWriteback = trimmedReasoning.isEmpty ? nil : trimmedReasoning

      if response.toolCalls.isEmpty {
        consecutiveNoToolCallTurns += 1
        if !response.text.isEmpty || reasoningForWriteback != nil {
          messages.append(
            .assistant(response.text, reasoningContent: reasoningForWriteback)
          )
        }
        if consecutiveNoToolCallTurns >= 5 {
          throw AgentExecutionError.modelStoppedWithoutSubmitResult
        }
        messages.append(
          .user(
            """
            Compass note: no tool call was made. Continue the phase by calling a Compass tool, \
            or finish by calling `\(submitKind)` with the phase payload. Do not answer in prose.
            """
          )
        )
        continue
      }
      consecutiveNoToolCallTurns = 0

      messages.append(
        .assistant(
          response.text,
          toolCalls: response.toolCalls,
          reasoningContent: reasoningForWriteback
        )
      )

      var callIndex = 0
      while callIndex < response.toolCalls.count {
        let call = response.toolCalls[callIndex]

        if call.name == submitKind {
          let argumentText = call.argumentsJSON
          let arguments = Data(argumentText.utf8)
          let payload: Data
          do {
            payload = try Self.normalizedSubmitPayload(arguments)
          } catch {
            let message =
              "Compass rejected `\(submitKind)`: the arguments must be one JSON object matching the phase schema. \(error.localizedDescription)"
            emit(
              level: .warning,
              text: "Submit payload rejected",
              detail: previewString(message),
              kind: .agentMessage,
              status: .failed
            )
            messages.append(.toolResult(message, toolCallID: call.id))
            callIndex += 1
            continue
          }

          if let rejection =
            Self.rejectDevelopSubmitAfterSuccessfulVerify(
              payload,
              successfulVerifyCommand: lastSuccessfulVerifyCommand,
              configuration: configuration
            )
            ?? Self.rejectFailedDevelopSubmitAfterInvalidatedVerify(
              payload,
              invalidatedVerifyCommand: failedVerifyInvalidatedByMutationCommand,
              configuration: configuration
            )
            ?? Self.rejectSubmitResultIfNeeded(
              payload,
              configuration: configuration
            )
          {
            emit(
              level: .warning,
              text: rejection.eventText,
              detail: rejection.eventDetail,
              kind: .agentMessage,
              status: .failed
            )
            messages.append(.toolResult(rejection.userMessage, toolCallID: call.id))
            callIndex += 1
            continue
          }

          emit(
            level: .success,
            text: submitKind,
            detail: previewString(String(decoding: payload, as: UTF8.self)),
            kind: .agentMessage,
            status: .completed
          )
          tokenUsage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
          return AgentExecutionResult(
            submitResultArguments: payload,
            iterations: iterations,
            assistantText: assistantTranscript,
            reasoningText: reasoningTranscript,
            tokenUsage: tokenUsage
          )
        }

        // Coalesce consecutive read-only inspection calls into one parallel batch.
        if Self.isParallelizableNativeTool(call.name) {
          var batch: [AgentChatToolCall] = []
          while callIndex < response.toolCalls.count {
            let candidate = response.toolCalls[callIndex]
            if candidate.name == submitKind
              || !Self.isParallelizableNativeTool(candidate.name)
            {
              break
            }
            batch.append(candidate)
            callIndex += 1
          }

          let prepared = batch.map { call -> (call: AgentChatToolCall, correlationID: String) in
            let correlationID = UUID().uuidString
            emitToolStart(
              name: call.name,
              arguments: call.argumentsJSON,
              correlationID: correlationID
            )
            return (call, correlationID)
          }

          let batchResults = await Self.invokeNativeToolBatch(
            calls: prepared.map(\.call),
            toolsByName: toolsByName,
            toolContext: toolContext
          )

          for (index, item) in batchResults.enumerated() {
            let correlationID = prepared[index].correlationID
            emitToolEnd(
              name: item.call.name,
              arguments: item.call.argumentsJSON,
              result: item.result,
              correlationID: correlationID
            )
            var observation = Self.toolObservationJSON(
              toolName: item.call.name,
              result: item.result,
              reason: nil,
              pathSanitizer: { toolContext.sanitizeHostPaths(in: $0) },
              limit: Self.nativeObservationCharacterLimit
            )
            Self.applyNativeToolSideEffects(
              toolName: item.call.name,
              argumentText: item.call.argumentsJSON,
              arguments: Data(item.call.argumentsJSON.utf8),
              result: item.result,
              submitKind: submitKind,
              lastSuccessfulVerifyCommand: &lastSuccessfulVerifyCommand,
              lastFailedVerifyCommand: &lastFailedVerifyCommand,
              failedVerifyInvalidatedByMutationCommand: &failedVerifyInvalidatedByMutationCommand,
              lastFailedToolCall: &lastFailedToolCall,
              repeatedFailedToolCallCount: &repeatedFailedToolCallCount,
              observation: &observation
            )
            messages.append(.toolResult(observation, toolCallID: item.call.id))
          }
          continue
        }

        guard let tool = toolsByName[call.name] else {
          messages.append(
            .toolResult(
              #"{"tool":"\#(call.name)","isError":true,"content":"Unknown tool for this phase."}"#,
              toolCallID: call.id
            )
          )
          callIndex += 1
          continue
        }

        let argumentText = call.argumentsJSON
        let arguments = Data(argumentText.utf8)
        let correlationID = UUID().uuidString
        emitToolStart(name: call.name, arguments: argumentText, correlationID: correlationID)
        let result: AgentToolInvocationResult
        do {
          result = try await tool.invoke(arguments: arguments, context: toolContext)
        } catch let toolError as AgentToolError {
          result = .failure(toolError)
        } catch {
          result = .failure("Tool \(call.name) threw: \(error.localizedDescription)", kind: .unknown)
        }
        emitToolEnd(
          name: call.name,
          arguments: argumentText,
          result: result,
          correlationID: correlationID
        )

        var observation = Self.toolObservationJSON(
          toolName: call.name,
          result: result,
          reason: nil,
          pathSanitizer: { toolContext.sanitizeHostPaths(in: $0) },
          limit: Self.nativeObservationCharacterLimit
        )
        Self.applyNativeToolSideEffects(
          toolName: call.name,
          argumentText: argumentText,
          arguments: arguments,
          result: result,
          submitKind: submitKind,
          lastSuccessfulVerifyCommand: &lastSuccessfulVerifyCommand,
          lastFailedVerifyCommand: &lastFailedVerifyCommand,
          failedVerifyInvalidatedByMutationCommand: &failedVerifyInvalidatedByMutationCommand,
          lastFailedToolCall: &lastFailedToolCall,
          repeatedFailedToolCallCount: &repeatedFailedToolCallCount,
          observation: &observation
        )
        messages.append(.toolResult(observation, toolCallID: call.id))
        callIndex += 1
      }
    }

    throw AgentExecutionError.maxIterationsExceeded(configuration.maxIterations)
  }

  private struct NativeBatchItem: Sendable {
    var call: AgentChatToolCall
    var result: AgentToolInvocationResult
  }

  private static func invokeNativeToolBatch(
    calls: [AgentChatToolCall],
    toolsByName: [String: any AgentTool],
    toolContext: AgentToolContext
  ) async -> [NativeBatchItem] {
    struct Work: Sendable {
      var offset: Int
      var call: AgentChatToolCall
      var result: AgentToolInvocationResult
    }

    if calls.isEmpty { return [] }
    if calls.count == 1, let call = calls.first {
      let result = await invokeSingleNativeTool(
        call: call,
        toolsByName: toolsByName,
        toolContext: toolContext
      )
      return [NativeBatchItem(call: call, result: result)]
    }

    var works: [Work] = []
    works.reserveCapacity(calls.count)
    await withTaskGroup(of: Work.self) { group in
      for (offset, call) in calls.enumerated() {
        group.addTask {
          let result = await invokeSingleNativeTool(
            call: call,
            toolsByName: toolsByName,
            toolContext: toolContext
          )
          return Work(offset: offset, call: call, result: result)
        }
      }
      for await work in group {
        works.append(work)
      }
    }

    works.sort { $0.offset < $1.offset }
    return works.map { NativeBatchItem(call: $0.call, result: $0.result) }
  }

  private static func invokeSingleNativeTool(
    call: AgentChatToolCall,
    toolsByName: [String: any AgentTool],
    toolContext: AgentToolContext
  ) async -> AgentToolInvocationResult {
    guard let tool = toolsByName[call.name] else {
      return .failure("Unknown tool for this phase.", kind: .invalidArguments)
    }
    let arguments = Data(call.argumentsJSON.utf8)
    do {
      return try await tool.invoke(arguments: arguments, context: toolContext)
    } catch let toolError as AgentToolError {
      return .failure(toolError)
    } catch {
      return .failure(
        "Tool \(call.name) threw: \(error.localizedDescription)",
        kind: .unknown
      )
    }
  }

  private static func applyNativeToolSideEffects(
    toolName: String,
    argumentText: String,
    arguments: Data,
    result: AgentToolInvocationResult,
    submitKind: String,
    lastSuccessfulVerifyCommand: inout String?,
    lastFailedVerifyCommand: inout String?,
    failedVerifyInvalidatedByMutationCommand: inout String?,
    lastFailedToolCall: inout NativeToolCallSignature?,
    repeatedFailedToolCallCount: inout Int,
    observation: inout String
  ) {
    if !result.isError, Self.isFileMutationTool(toolName) {
      lastSuccessfulVerifyCommand = nil
      if let lastFailedVerifyCommand {
        failedVerifyInvalidatedByMutationCommand = lastFailedVerifyCommand
      }
      lastFailedVerifyCommand = nil
    }
    if let command = Self.successfulVerifyCommand(
      toolName: toolName,
      arguments: arguments,
      result: result
    ) {
      lastSuccessfulVerifyCommand = command
      lastFailedVerifyCommand = nil
      failedVerifyInvalidatedByMutationCommand = nil
    }
    if let command = Self.failedVerifyCommand(
      toolName: toolName,
      arguments: arguments,
      result: result
    ) {
      lastFailedVerifyCommand = command
      failedVerifyInvalidatedByMutationCommand = nil
    }

    if result.isError {
      let signature = NativeToolCallSignature(toolName: toolName, arguments: argumentText)
      if signature == lastFailedToolCall {
        repeatedFailedToolCallCount += 1
      } else {
        lastFailedToolCall = signature
        repeatedFailedToolCallCount = 1
      }
      if repeatedFailedToolCallCount >= 2 {
        observation += """

          Compass note: this exact `\(toolName)` call has now failed \
          \(repeatedFailedToolCallCount) times with the same arguments. Do not repeat it \
          unchanged — adjust the arguments from the error above, gather the missing fact \
          with a different call, or finish with `\(submitKind)` reporting the blocker.
          """
      }
    } else {
      lastFailedToolCall = nil
      repeatedFailedToolCallCount = 0
    }
  }

  /// Tool observations in the native loop may be much larger than the old
  /// 6 KB cap: capable models use long reads productively, and the
  /// provider-reported prompt tokens drive compaction instead of blind caps.
  static let nativeObservationCharacterLimit = 48_000

  struct NativeToolCallSignature: Equatable, Hashable {
    var toolName: String
    var arguments: String
  }

  static func normalizedSubmitPayload(_ arguments: Data) throws -> Data {
    let raw = try JSONSerialization.jsonObject(with: arguments)
    guard let object = raw as? [String: Any], JSONSerialization.isValidJSONObject(object) else {
      throw AgentExecutionError.toolCallDecodeFailed(
        name: "submit",
        detail: "submit arguments must be a JSON object"
      )
    }
    return try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
  }

  static func nativeGenerationLogLabel(
    configuration: AgentExecutionConfiguration,
    iteration: Int
  ) -> String {
    "\(configuration.promptLogLabelBase)-turn-\(iteration)"
  }

  static func nativeMessagesNeedCompaction(
    messages: [AgentChatMessage],
    lastPromptTokens: Int?,
    configuration: AgentExecutionConfiguration
  ) -> Bool {
    let contextWindowTokens = configuration.contextWindowTokens
    guard contextWindowTokens > 0, messages.count > 8 else { return false }
    let threshold = max(
      1,
      Int((Double(contextWindowTokens) * compactionThresholdFraction).rounded(.down))
    )
    if let lastPromptTokens {
      // The last turn's real prompt tokens plus one generous response and one
      // more tool round-trip: compact before the next request would overflow.
      let projected = lastPromptTokens + maxCompletionTokensPerTurn / 2
      return projected > threshold
    }
    let characters = messages.reduce(0) { partial, message in
      partial
        + message.content.count
        + (message.reasoningContent?.count ?? 0)
        + message.toolCalls.reduce(0) { $0 + $1.argumentsJSON.count }
    }
    return AgentRunTokenUsage.estimateTokens(
      characters: characters,
      charsPerToken: estimatedCharsPerToken
    ) > threshold
  }

  /// Replaces the middle of the conversation with a model-generated summary,
  /// keeping the system prompt, original packet, and the most recent
  /// tool-call exchange intact.
  static func compactNativeMessages(
    configuration: AgentExecutionConfiguration,
    runtime: any LocalModelGenerating,
    messages: [AgentChatMessage]
  ) async throws -> [AgentChatMessage]? {
    let keepRecent = 6
    guard messages.count > keepRecent + 2 else { return nil }

    var recent = Array(messages.suffix(keepRecent))
    while let first = recent.first, first.role == .tool {
      recent.removeFirst()
    }
    let older = messages.dropFirst(2).dropLast(recent.count)
    guard !older.isEmpty else { return nil }

    let serializedOlder = older.map { message -> String in
      switch message.role {
      case .assistant:
        let calls = message.toolCalls.map { "\($0.name)(\($0.argumentsJSON))" }.joined(separator: ", ")
        let reasoning = message.reasoningContent?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasoningBlock =
          reasoning.isEmpty ? "" : "\nReasoning:\n\(reasoning)"
        return """
          ### Assistant\(calls.isEmpty ? "" : " [called \(calls)]")
          \(message.content)\(reasoningBlock)
          """
      case .tool:
        return "### Tool result\n\(message.content)"
      case .user:
        return "### Compass\n\(message.content)"
      case .system:
        return ""
      }
    }.filter { !$0.isEmpty }.joined(separator: "\n\n")

    let generation = try await runtime.generateText(
      request: LocalModelGenerationRequest(
        modelID: configuration.settings.codemapModel,
        systemPrompt: """
          You compact an in-progress coding agent conversation. Preserve only resumable state: \
          the goal, established facts from tool results, touched files and symbols, errors and \
          their repairs, and the current next step. Do not invent facts. Return plain text only.
          """,
        prompt: """
          ## Phase packet
          \(fencedContinuationText(configuration.userPrompt, limit: 8_000))

          ## Conversation so far
          \(fencedContinuationText(serializedOlder, limit: 48_000))

          ## Output
          Compact the conversation with these headings: Goal, Established Facts, Files / Symbols, Errors / Repairs, Current Step / Next Action.
          """,
        maxOutputTokens: maxSummaryCompletionTokens,
        logLabel: nil,
        routingHint: .localPreferred
      )
    )
    let (summary, _) = stripThinkBlocks(generation.text)
    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return [
      .system(configuration.systemPrompt),
      .user(configuration.userPrompt),
      .user(
        """
        ## Compacted history
        The conversation so far was compacted by Compass. Tool results summarized here are \
        real observations; assistant intent is not proof. Continue from the current step.

        \(trimmed)
        """
      ),
    ] + recent
  }
}
