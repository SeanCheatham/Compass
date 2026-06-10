import Foundation

extension AgentExecutor {
  func run(_ configuration: AgentExecutionConfiguration) async throws -> AgentExecutionResult {
    try AgentExecutor.ensureUniqueToolNames(configuration.tools)

    let startedAt = Date()
    let runtime = configuration.modelRuntime ?? MLXLocalModelRuntime.shared
    let toolContext = AgentToolContext(
      workingDirectory: configuration.workingDirectory,
      filesystem: configuration.filesystem,
      bashRunner: configuration.bashRunner,
      delegateRunner: AgentExecutor.makeDelegateRunner(
        configuration: configuration,
        onEvent: onEvent
      ),
      codemapStoreDirectory: configuration.codemapStoreDirectory,
      planHistoryEntries: configuration.planHistoryEntries,
      assumptionsURL: configuration.assumptionsURL,
      phase: configuration.phase,
      sessionNumber: configuration.sessionNumber
    )
    let toolsByName = Dictionary(uniqueKeysWithValues: configuration.tools.map { ($0.spec.name, $0) })
    let availableToolNames = Set(toolsByName.keys)

    var iterations = 0
    var assistantTranscript = ""
    var transcript: [ContinuationTranscriptEntry] = []
    var tokenUsage = AgentRunTokenUsage()
    var lastFailedToolCall: FailedToolCallSignature?
    var repeatedFailedToolCallCount = 0

    while iterations < configuration.maxIterations {
      if cancelled { throw AgentExecutionError.cancelled }
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed > configuration.wallClockTimeout {
        throw AgentExecutionError.wallClockExceeded(configuration.wallClockTimeout)
      }

      iterations += 1
      emit(
        level: .info,
        text: "MLX continuation iteration \(iterations)",
        kind: .lifecycle,
        status: .running
      )

      let prompt = Self.continuationPrompt(
        configuration: configuration,
        transcript: transcript
      )
      let generation: LocalModelGenerationResult
      do {
        generation = try await runtime.generateText(
          request: LocalModelGenerationRequest(
            modelID: LocalModelCatalog.blessedModelID,
            systemPrompt: configuration.systemPrompt,
            prompt: prompt,
            maxOutputTokens: Self.maxCompletionTokensPerTurn
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
        inputTokens: generation.tokenUsage.inputTokens,
        outputTokens: generation.tokenUsage.outputTokens,
        totalTokens: generation.tokenUsage.totalTokens,
        isEstimated: generation.tokenUsage.usesEstimate,
        streamedUsageAvailable: generation.tokenUsage.streamedUsageAvailable
      )
      if let durationMs = generation.tokenUsage.durationMs {
        tokenUsage.durationMs = (tokenUsage.durationMs ?? 0) + durationMs
      }

      let output = generation.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !output.isEmpty {
        assistantTranscript += assistantTranscript.isEmpty ? output : "\n\n\(output)"
        emit(
          level: .raw,
          text: "Assistant JSON",
          detail: previewString(output),
          kind: .agentMessage,
          status: .completed
        )
        transcript.append(.assistant(output))
      }

      let continuation: AgentContinuation
      do {
        continuation = try AgentContinuationParser.parse(
          output,
          phase: configuration.continuationPhase,
          availableToolNames: availableToolNames
        )
      } catch {
        let detail = error.localizedDescription
        emit(
          level: .warning,
          text: "Continuation rejected",
          detail: previewString(detail),
          kind: .agentMessage,
          status: .failed
        )
        transcript.append(
          .repair(
            Self.continuationRepairMessage(
              error: detail,
              invalidOutput: output,
              phase: configuration.continuationPhase
            )
          )
        )
        continue
      }

      switch continuation.action {
      case .submit(let payload):
        if let rejection = Self.rejectSubmitResultIfNeeded(
          payload,
          configuration: configuration
        ) {
          emit(
            level: .warning,
            text: rejection.eventText,
            detail: rejection.eventDetail,
            kind: .agentMessage,
            status: .failed
          )
          transcript.append(
            .repair(
              Self.continuationRepairMessage(
                error: rejection.userMessage,
                invalidOutput: output,
                phase: configuration.continuationPhase
              )
            )
          )
          continue
        }
        emit(
          level: .success,
          text: continuation.kind,
          detail: previewString(String(decoding: payload, as: UTF8.self)),
          kind: .agentMessage,
          status: .completed
        )
        tokenUsage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return AgentExecutionResult(
          submitResultArguments: payload,
          iterations: iterations,
          assistantText: assistantTranscript,
          reasoningText: "",
          tokenUsage: tokenUsage
        )

      case .continueTool(let toolName, let arguments, let reason):
        guard let tool = toolsByName[toolName] else {
          transcript.append(
            .repair(
              Self.continuationRepairMessage(
                error: "Unknown tool `\(toolName)` after validation.",
                invalidOutput: output,
                phase: configuration.continuationPhase
              )
            )
          )
          continue
        }

        let argumentText = String(decoding: arguments, as: UTF8.self)
        let correlationID = UUID().uuidString
        emitToolStart(name: toolName, arguments: argumentText, correlationID: correlationID)
        let result: AgentToolInvocationResult
        do {
          result = try await tool.invoke(arguments: arguments, context: toolContext)
        } catch let toolError as AgentToolError {
          result = .failure(toolError)
        } catch {
          result = .failure("Tool \(toolName) threw: \(error.localizedDescription)", kind: .unknown)
        }
        emitToolEnd(name: toolName, arguments: argumentText, result: result, correlationID: correlationID)

        let observation = Self.toolObservationJSON(
          toolName: toolName,
          result: result,
          reason: reason
        )
        transcript.append(.toolObservation(observation))
        if result.isError {
          let signature = FailedToolCallSignature(toolName: toolName, arguments: argumentText)
          if signature == lastFailedToolCall {
            repeatedFailedToolCallCount += 1
          } else {
            lastFailedToolCall = signature
            repeatedFailedToolCallCount = 1
          }
          if repeatedFailedToolCallCount >= 2 {
            transcript.append(
              .repair(
                Self.repeatedToolFailureRepairMessage(
                  toolName: toolName,
                  arguments: argumentText,
                  repeatCount: repeatedFailedToolCallCount,
                  phase: configuration.continuationPhase
                )
              )
            )
          }
        } else {
          lastFailedToolCall = nil
          repeatedFailedToolCallCount = 0
        }
      }
    }

    throw AgentExecutionError.maxIterationsExceeded(configuration.maxIterations)
  }

  static func ensureUniqueToolNames(_ tools: [AgentTool]) throws {
    var names = Set<String>()
    for tool in tools {
      let name = tool.spec.name
      guard names.insert(name).inserted else {
        throw AgentExecutionError.duplicateToolName(name)
      }
    }
  }

  static func canonicalToolName(_ raw: String, availableToolNames: Set<String>) -> String? {
    let normalized =
      raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    guard !normalized.isEmpty else { return nil }
    if availableToolNames.contains(normalized) { return normalized }
    return availableToolNames.first { name in
      name.replacingOccurrences(of: "-", with: "_").lowercased() == normalized
    }
  }

  static func makeDelegateRunner(
    configuration: AgentExecutionConfiguration,
    onEvent: @escaping @Sendable (LiveEvent) -> Void
  ) -> AgentDelegateRunner? {
    guard configuration.tools.contains(where: { $0.spec.name == AgentDelegateTool.toolName }) else {
      return nil
    }
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
      onEvent: onEvent
    )
  }

  static func stripThinkBlocks(_ text: String) -> (String, String) {
    var cleaned = text
    var extracted: [String] = []
    while let start = cleaned.range(of: "<think>", options: .caseInsensitive),
      let end = cleaned.range(of: "</think>", options: .caseInsensitive, range: start.upperBound..<cleaned.endIndex)
    {
      let body = String(cleaned[start.upperBound..<end.lowerBound])
      extracted.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
      cleaned.removeSubrange(start.lowerBound..<end.upperBound)
    }
    return (
      cleaned.trimmingCharacters(in: .whitespacesAndNewlines),
      extracted.filter { !$0.isEmpty }.joined(separator: "\n\n")
    )
  }

  private struct ContinuationTranscriptEntry: Equatable {
    var title: String
    var body: String

    static func assistant(_ body: String) -> Self {
      Self(title: "Assistant JSON", body: body)
    }

    static func toolObservation(_ body: String) -> Self {
      Self(title: "Compass Observation", body: body)
    }

    static func repair(_ body: String) -> Self {
      Self(title: "Compass Repair", body: body)
    }
  }

  private struct FailedToolCallSignature: Equatable {
    var toolName: String
    var arguments: String
  }

  private static func continuationPrompt(
    configuration: AgentExecutionConfiguration,
    transcript: [ContinuationTranscriptEntry]
  ) -> String {
    var sections: [String] = [
      """
      ## Original Phase Packet
      \(fencedContinuationText(configuration.userPrompt, limit: 16_000))
      """,
      """
      ## Continuation Contract
      Emit exactly one JSON object and no prose.
      Use `\(configuration.continuationPhase.continueKind)` to request one Compass tool.
      Use `\(configuration.continuationPhase.submitKind)` with `payload` to finish this phase.
      """
    ]

    if !transcript.isEmpty {
      let recent = transcript.suffix(8).map { entry in
        """
        ### \(entry.title)
        \(fencedContinuationText(entry.body, limit: 8_000))
        """
      }.joined(separator: "\n\n")
      sections.append(
        """
        ## Recent History
        \(recent)
        """
      )
    }

    sections.append(
      """
      ## Next Output
      Return exactly one JSON object for the current phase.
      """
    )
    return sections.joined(separator: "\n\n")
  }

  private static func continuationRepairMessage(
    error: String,
    invalidOutput: String,
    phase: AgentContinuationPhase
  ) -> String {
    """
    Your previous response could not be used.

    Error:
    \(error)

    Required shape:
    {"kind":"\(phase.continueKind)","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current package scripts."}
    or
    {"kind":"\(phase.submitKind)","payload":{...}}

    Invalid response:
    \(fencedContinuationText(invalidOutput, limit: 4_000))
    """
  }

  private static func repeatedToolFailureRepairMessage(
    toolName: String,
    arguments: String,
    repeatCount: Int,
    phase: AgentContinuationPhase
  ) -> String {
    """
    You repeated the exact same failed `\(toolName)` call \(repeatCount) times.

    Do not call `\(toolName)` again with the same arguments. Choose a different next action:
    - If this is an edit_file failure, change the startLine/endLine and replacement lines using the latest read_file output.
    - If the path or lines are uncertain, call read_file or list_files first.
    - If you cannot make a different concrete tool call now, return `\(phase.submitKind)` with status=failed or status=blocked and concise feedback.

    Repeated arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func toolObservationJSON(
    toolName: String,
    result: AgentToolInvocationResult,
    reason: String?
  ) -> String {
    var object: [String: Any] = [
      "tool": toolName,
      "isError": result.isError,
      "content": boundedObservation(result.content),
    ]
    if let reason, !reason.isEmpty {
      object["reason"] = reason
    }
    if let errorKind = result.errorKind {
      object["errorKind"] = errorKind.rawValue
    }
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
    else {
      return #"{"tool":"\#(toolName)","isError":true,"content":"Compass could not serialize the observation."}"#
    }
    return String(decoding: data, as: UTF8.self)
  }

  private static func boundedObservation(_ text: String, limit: Int = 6_000) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    let headCount = max(0, (limit / 2) - 80)
    let tailCount = max(0, (limit / 2) - 80)
    return """
    \(String(trimmed.prefix(headCount)))

    ... [Compass truncated \(trimmed.count - headCount - tailCount) characters from this observation] ...

    \(String(trimmed.suffix(tailCount)))
    """
  }

  private static func fencedContinuationText(_ text: String, limit: Int) -> String {
    let bounded: String
    if text.count <= limit {
      bounded = text
    } else {
      bounded = String(text.prefix(max(0, limit - 80)))
        + "\n... [Compass truncated \(text.count - limit) characters] ..."
    }
    return """
    ```
    \(bounded)
    ```
    """
  }

  private static func rejectSubmitResultIfNeeded(
    _ submitResultJSON: Data,
    configuration: AgentExecutionConfiguration
  ) -> InvalidToolArgumentsNudge? {
    guard let validate = configuration.validateSubmitResult else { return nil }
    do {
      try validate(submitResultJSON)
      return nil
    } catch {
      return submitResultValidationNudge(for: error, phase: configuration.phase)
    }
  }
}
