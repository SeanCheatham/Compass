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
    var compactedHistory: String?
    var tokenUsage = AgentRunTokenUsage()
    var lastFailedToolCall: ToolCallSignature?
    var repeatedFailedToolCallCount = 0
    var sawSubmitRejection = false
    var lastSuccessfulToolCallAfterSubmitRejection: ToolCallSignature?
    var repeatedSuccessfulToolCallAfterSubmitRejectionCount = 0

    while iterations < configuration.maxIterations {
      if cancelled { throw AgentExecutionError.cancelled }
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed > configuration.wallClockTimeout {
        throw AgentExecutionError.wallClockExceeded(configuration.wallClockTimeout)
      }

      var prompt = Self.continuationPrompt(
        configuration: configuration,
        compactedHistory: compactedHistory,
        transcript: transcript,
        historyMode: configuration.contextWindowTokens == 0 ? .boundedRecent : .full
      )
      if configuration.contextWindowTokens > 0,
        Self.promptNeedsCompaction(
          prompt: prompt,
          systemPrompt: configuration.systemPrompt,
          configuration: configuration
        )
      {
        do {
          if let compaction = try await Self.compactContinuationHistory(
            configuration: configuration,
            runtime: runtime,
            compactedHistory: compactedHistory,
            transcript: transcript
          ) {
            compactedHistory = compaction.summary
            transcript = Array(transcript.suffix(Self.rawTranscriptEntriesAfterCompaction))
            tokenUsage.recordTurn(
              inputTokens: compaction.tokenUsage.inputTokens,
              outputTokens: compaction.tokenUsage.outputTokens,
              totalTokens: compaction.tokenUsage.totalTokens,
              isEstimated: compaction.tokenUsage.usesEstimate,
              streamedUsageAvailable: compaction.tokenUsage.streamedUsageAvailable
            )
            tokenUsage.recordCompaction(summaryTokens: compaction.tokenUsage.outputTokens)
            if let durationMs = compaction.tokenUsage.durationMs {
              tokenUsage.durationMs = (tokenUsage.durationMs ?? 0) + durationMs
            }
            emit(
              level: .info,
              text: "Compacted continuation history",
              detail: previewString(compaction.summary),
              kind: .lifecycle,
              status: .completed
            )
            prompt = Self.continuationPrompt(
              configuration: configuration,
              compactedHistory: compactedHistory,
              transcript: transcript,
              historyMode: .full
            )
          } else {
            prompt = Self.continuationPrompt(
              configuration: configuration,
              compactedHistory: compactedHistory,
              transcript: transcript,
              historyMode: .boundedRecent
            )
          }
        } catch is CancellationError {
          throw AgentExecutionError.cancelled
        } catch let agentError as AgentExecutionError {
          throw agentError
        } catch {
          emit(
            level: .warning,
            text: "Continuation compaction skipped",
            detail: previewString(error.localizedDescription),
            kind: .lifecycle,
            status: .failed
          )
          prompt = Self.continuationPrompt(
            configuration: configuration,
            compactedHistory: compactedHistory,
            transcript: transcript,
            historyMode: .boundedRecent
          )
        }
      }

      iterations += 1
      emit(
        level: .info,
        text: "MLX continuation iteration \(iterations)",
        kind: .lifecycle,
        status: .running
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
          sawSubmitRejection = true
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

      case .continueTool(let toolName, let arguments, let reason, let note):
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
        let signature = ToolCallSignature(toolName: toolName, arguments: argumentText)
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
        if let note {
          transcript.append(.assistantNote(note))
        }
        if result.isError {
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
          lastSuccessfulToolCallAfterSubmitRejection = nil
          repeatedSuccessfulToolCallAfterSubmitRejectionCount = 0
        } else {
          lastFailedToolCall = nil
          repeatedFailedToolCallCount = 0
          if sawSubmitRejection {
            if signature == lastSuccessfulToolCallAfterSubmitRejection {
              repeatedSuccessfulToolCallAfterSubmitRejectionCount += 1
            } else {
              lastSuccessfulToolCallAfterSubmitRejection = signature
              repeatedSuccessfulToolCallAfterSubmitRejectionCount = 1
            }
            if repeatedSuccessfulToolCallAfterSubmitRejectionCount >= 2 {
              transcript.append(
                .repair(
                  Self.repeatedToolAfterSubmitRejectionRepairMessage(
                    toolName: toolName,
                    arguments: argumentText,
                    repeatCount: repeatedSuccessfulToolCallAfterSubmitRejectionCount,
                    phase: configuration.continuationPhase
                  )
                )
              )
            }
          }
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

    static func assistantNote(_ body: String) -> Self {
      Self(title: "Assistant Note (unverified)", body: body)
    }

    static func repair(_ body: String) -> Self {
      Self(title: "Compass Repair", body: body)
    }
  }

  private enum ContinuationHistoryMode {
    case full
    case boundedRecent
  }

  private struct ContinuationCompactionResult {
    var summary: String
    var tokenUsage: AgentRunTokenUsage
  }

  private struct ToolCallSignature: Equatable {
    var toolName: String
    var arguments: String
  }

  private static let rawTranscriptEntriesAfterCompaction = 8

  private static func continuationPrompt(
    configuration: AgentExecutionConfiguration,
    compactedHistory: String?,
    transcript: [ContinuationTranscriptEntry],
    historyMode: ContinuationHistoryMode
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
      A continue envelope may include optional `note`: a short unverified working note for how to use the upcoming real tool observation.
      Use `\(configuration.continuationPhase.submitKind)` with `payload` to finish this phase.
      """
    ]

    if let compactedHistory = sanitizedCompactedHistory(compactedHistory) {
      sections.append(
        """
        ## Compacted History
        The following is model-generated compressed history. It is useful context, but lower authority than real `Compass Observation` entries below.
        \(fencedContinuationText(compactedHistory, limit: 12_000))
        """
      )
    }

    let historyEntries =
      historyMode == .boundedRecent
      ? transcript.suffix(rawTranscriptEntriesAfterCompaction)
      : transcript[...]
    if !historyEntries.isEmpty {
      sections.append(
        """
        ## Recent History
        \(renderTranscriptEntries(historyEntries, entryLimit: 8_000))
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

  private static func promptNeedsCompaction(
    prompt: String,
    systemPrompt: String,
    configuration: AgentExecutionConfiguration
  ) -> Bool {
    let contextWindowTokens = configuration.contextWindowTokens
    guard contextWindowTokens > 0 else { return false }
    let threshold = max(
      1,
      Int((Double(contextWindowTokens) * compactionThresholdFraction).rounded(.down))
    )
    let estimatedTokens = AgentRunTokenUsage.estimateTokens(
      characters: prompt.count + systemPrompt.count,
      charsPerToken: estimatedCharsPerToken
    )
    return estimatedTokens > threshold
  }

  private static func compactContinuationHistory(
    configuration: AgentExecutionConfiguration,
    runtime: any LocalModelGenerating,
    compactedHistory: String?,
    transcript: [ContinuationTranscriptEntry]
  ) async throws -> ContinuationCompactionResult? {
    let olderCount = max(0, transcript.count - rawTranscriptEntriesAfterCompaction)
    let olderEntries = transcript.prefix(olderCount)
    guard sanitizedCompactedHistory(compactedHistory) != nil || !olderEntries.isEmpty else {
      return nil
    }

    let generation = try await runtime.generateText(
      request: LocalModelGenerationRequest(
        modelID: LocalModelCatalog.blessedModelID,
        systemPrompt: continuationCompactionSystemPrompt(),
        prompt: continuationCompactionPrompt(
          configuration: configuration,
          compactedHistory: compactedHistory,
          olderEntries: olderEntries,
          recentEntries: transcript.suffix(rawTranscriptEntriesAfterCompaction)
        ),
        maxOutputTokens: maxSummaryCompletionTokens
      )
    )

    let (cleaned, _) = stripThinkBlocks(generation.text)
    let summary = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !summary.isEmpty else { return nil }
    return ContinuationCompactionResult(
      summary: boundedCompactedHistory(summary),
      tokenUsage: generation.tokenUsage
    )
  }

  private static func continuationCompactionSystemPrompt() -> String {
    """
    You compact Compass continuation history for a small local coding agent.
    Preserve only useful resumable state. Do not invent facts. Return plain text only.
    """
  }

  private static func continuationCompactionPrompt(
    configuration: AgentExecutionConfiguration,
    compactedHistory: String?,
    olderEntries: ArraySlice<ContinuationTranscriptEntry>,
    recentEntries: ArraySlice<ContinuationTranscriptEntry>
  ) -> String {
    var sections: [String] = [
      """
      ## Task
      Compact the older Compass continuation history. The latest raw entries will remain visible separately, so summarize older context only enough to resume.

      Authority rules:
      - `Compass Observation` entries are real tool output.
      - `Assistant JSON` and `Assistant Note (unverified)` entries are model intent, not proof.
      - If entries conflict, preserve the real observation and note the conflict tersely.
      - Do not invent tool results, file contents, or completed work.

      Required output headings, in this exact order:
      Goal / Current Phase
      Established Facts
      Files / Symbols
      Errors / Repairs
      Current Step / Next Action
      """,
      """
      ## Original Phase Packet
      \(fencedContinuationText(configuration.userPrompt, limit: 8_000))
      """
    ]

    if let compactedHistory = sanitizedCompactedHistory(compactedHistory) {
      sections.append(
        """
        ## Existing Compacted History
        \(fencedContinuationText(compactedHistory, limit: 8_000))
        """
      )
    }

    if !olderEntries.isEmpty {
      sections.append(
        """
        ## Raw History To Compact
        \(renderTranscriptEntries(olderEntries, entryLimit: 6_000))
        """
      )
    }

    if !recentEntries.isEmpty {
      sections.append(
        """
        ## Latest Raw History Kept Verbatim
        Do not duplicate these entries unless needed to connect the older summary.
        \(renderTranscriptEntries(recentEntries, entryLimit: 4_000))
        """
      )
    }

    sections.append(
      """
      ## Output
      Return only the compacted plain-text summary with the required headings.
      """
    )
    return sections.joined(separator: "\n\n")
  }

  private static func renderTranscriptEntries(
    _ entries: ArraySlice<ContinuationTranscriptEntry>,
    entryLimit: Int
  ) -> String {
    entries.map { entry in
      """
      ### \(entry.title)
      \(fencedContinuationText(entry.body, limit: entryLimit))
      """
    }.joined(separator: "\n\n")
  }

  private static func sanitizedCompactedHistory(_ text: String?) -> String? {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func boundedCompactedHistory(_ text: String, limit: Int = 16_000) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(max(0, limit - 80)))
      + "\n... [Compass truncated \(trimmed.count - limit) characters from compacted history] ..."
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
    {"kind":"\(phase.continueKind)","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current package scripts.","note":"If package scripts exist, run the relevant verify command next."}
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

  private static func repeatedToolAfterSubmitRejectionRepairMessage(
    toolName: String,
    arguments: String,
    repeatCount: Int,
    phase: AgentContinuationPhase
  ) -> String {
    """
    Compass already rejected a recent `\(phase.submitKind)` payload, and you then called
    `\(toolName)` with the same arguments \(repeatCount) times. The repeated observation
    did not repair the rejected payload.

    Do not call `\(toolName)` again with the same arguments. Repair the rejected
    `\(phase.submitKind)` now:
    - Reuse the useful fields from your rejected payload.
    - Apply the latest Compass Repair instruction exactly.
    - Return `\(phase.submitKind)` with a corrected `payload`.
    - Only call a different tool if the repair instruction explicitly requires new evidence.

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
