import Foundation

package extension AgentExecutor {
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
    var failedToolFamilyCounts: [ToolFailureFamilySignature: Int] = [:]
    var lastMalformedContinuationSignature: String?
    var repeatedMalformedContinuationCount = 0
    var sawContinuationRejection = false
    var latestContinuationRejectionRepairMessage: String?
    var latestContinuationRejectionDescription = "continuation"
    var pendingSubmitRepair: PendingSubmitRepair?
    var blockedToolCallCountsDuringSubmitRepair: [ToolCallSignature: Int] = [:]
    var lastSubmitRejectionSignature: String?
    var repeatedSubmitRejectionCount = 0
    var successfulToolCallCountsAfterContinuationRejection: [ToolCallSignature: Int] = [:]
    var successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation = 0
    var lastSuccessfulVerifyCommand: String?
    var lastFailedVerifyCommand: String?
    var failedVerifyInvalidatedByMutationCommand: String?
    var repeatedSuccessfulReadOnlyDevelopToolCallCount = 0
    var consecutiveSuccessfulReadOnlyDevelopToolCallCount = 0
    var successfulReadOnlyDevelopToolCallCounts: [ToolCallSignature: Int] = [:]

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
            maxOutputTokens: Self.maxCompletionTokensPerTurn,
            logLabel: Self.generationLogLabel(configuration: configuration, iteration: iterations)
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
        let repairMessage = Self.continuationRepairMessage(
          error: detail,
          invalidOutput: output,
          phase: configuration.continuationPhase
        )
        sawContinuationRejection = true
        latestContinuationRejectionRepairMessage = repairMessage
        latestContinuationRejectionDescription =
          "malformed \(configuration.continuationPhase.rawValue.capitalized) continuation response"
        successfulToolCallCountsAfterContinuationRejection = [:]
        successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation = 0
        let malformedSignature = Self.malformedContinuationSignature(
          error: detail,
          output: output,
          phase: configuration.continuationPhase
        )
        if malformedSignature == "malformed `\(configuration.continuationPhase.submitKind)` JSON" {
          pendingSubmitRepair = PendingSubmitRepair(
            submitKind: configuration.continuationPhase.submitKind,
            rejectionDescription: "malformed `\(configuration.continuationPhase.submitKind)` JSON",
            malformedJSON: true,
            repairMessage: repairMessage
          )
          blockedToolCallCountsDuringSubmitRepair = [:]
        }
        if malformedSignature == lastMalformedContinuationSignature {
          repeatedMalformedContinuationCount += 1
        } else {
          lastMalformedContinuationSignature = malformedSignature
          repeatedMalformedContinuationCount = 1
        }
        emit(
          level: .warning,
          text: "Continuation rejected",
          detail: previewString(detail),
          kind: .agentMessage,
          status: .failed
        )
        transcript.append(
          .repair(repairMessage)
        )
        if repeatedMalformedContinuationCount >= 2 {
          transcript.append(
            .repair(
              Self.repeatedMalformedContinuationRepairMessage(
                signature: malformedSignature,
                error: detail,
                invalidOutput: output,
                repeatCount: repeatedMalformedContinuationCount,
                phase: configuration.continuationPhase
              )
            )
          )
        }
        continue
      }

      switch continuation.action {
      case .submit(let payload):
        pendingSubmitRepair = nil
        blockedToolCallCountsDuringSubmitRepair = [:]
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
          ?? Self.rejectFailedDevelopSubmitAfterContinuationRejection(
            payload,
            sawContinuationRejection: sawContinuationRejection,
            latestRepairMessage: latestContinuationRejectionRepairMessage,
            rejectionDescription: latestContinuationRejectionDescription,
            configuration: configuration
          )
          ?? Self.rejectSubmitResultIfNeeded(
          payload,
          configuration: configuration
          )
        {
          sawContinuationRejection = true
          latestContinuationRejectionRepairMessage = rejection.userMessage
          latestContinuationRejectionDescription = "`\(configuration.continuationPhase.submitKind)` payload"
          successfulToolCallCountsAfterContinuationRejection = [:]
          successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation = 0
          if configuration.phase == .plan {
            pendingSubmitRepair = PendingSubmitRepair(
              submitKind: configuration.continuationPhase.submitKind,
              rejectionDescription: "rejected `\(configuration.continuationPhase.submitKind)` payload",
              malformedJSON: false,
              repairMessage: rejection.userMessage
            )
            blockedToolCallCountsDuringSubmitRepair = [:]
          }
          let rejectionSignature = "\(rejection.eventText)\n\(rejection.eventDetail)"
          if rejectionSignature == lastSubmitRejectionSignature {
            repeatedSubmitRejectionCount += 1
          } else {
            lastSubmitRejectionSignature = rejectionSignature
            repeatedSubmitRejectionCount = 1
          }
          emit(
            level: .warning,
            text: rejection.eventText,
            detail: rejection.eventDetail,
            kind: .agentMessage,
            status: .failed
          )
          transcript.append(
            .repair(
              Self.submitResultRepairMessage(
                error: rejection.userMessage,
                invalidOutput: output,
                phase: configuration.continuationPhase
              )
            )
          )
          if repeatedSubmitRejectionCount >= 2 {
            transcript.append(
              .repair(
                Self.repeatedSubmitRejectionRepairMessage(
                  eventText: rejection.eventText,
                  eventDetail: rejection.eventDetail,
                  latestRepairMessage: rejection.userMessage,
                  repeatCount: repeatedSubmitRejectionCount,
                  phase: configuration.continuationPhase
                )
              )
            )
          }
          continue
        }
        emit(
          level: .success,
          text: continuation.kind,
          detail: previewString(String(decoding: payload, as: UTF8.self)),
          kind: .agentMessage,
          status: .completed
        )
        lastMalformedContinuationSignature = nil
        repeatedMalformedContinuationCount = 0
        tokenUsage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return AgentExecutionResult(
          submitResultArguments: payload,
          iterations: iterations,
          assistantText: assistantTranscript,
          reasoningText: "",
          tokenUsage: tokenUsage
        )

      case .continueTool(let toolName, let arguments, let reason, let note):
        let argumentText = String(decoding: arguments, as: UTF8.self)
        let signature = ToolCallSignature(toolName: toolName, arguments: argumentText)
        if let pendingSubmitRepair {
          let blockedRepeatCount = (blockedToolCallCountsDuringSubmitRepair[signature] ?? 0) + 1
          blockedToolCallCountsDuringSubmitRepair[signature] = blockedRepeatCount
          let repairMessage = Self.toolAfterSubmitRepairMessage(
            toolName: toolName,
            arguments: argumentText,
            pendingRepair: pendingSubmitRepair,
            phase: configuration.continuationPhase,
            repeatCount: blockedRepeatCount
          )
          sawContinuationRejection = true
          latestContinuationRejectionRepairMessage = repairMessage
          latestContinuationRejectionDescription = pendingSubmitRepair.rejectionDescription
          successfulToolCallCountsAfterContinuationRejection = [:]
          emit(
            level: .warning,
            text: "Tool call after rejected submit rejected",
            detail: previewString(
              "Compass did not run `\(toolName)` after \(pendingSubmitRepair.rejectionDescription)."
            ),
            kind: .agentMessage,
            status: .failed
          )
          transcript.append(.repair(repairMessage))
          continue
        }

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

        let correlationID = UUID().uuidString
        emitToolStart(name: toolName, arguments: argumentText, correlationID: correlationID)
        let result: AgentToolInvocationResult
        if configuration.phase == .develop,
          let lastSuccessfulVerifyCommand,
          Self.isFileMutationTool(toolName),
          !Self.isPostVerifyMutationJustified(reason: reason, note: note)
        {
          result = .failure(
            Self.postVerifyMutationRejectedMessage(
              command: lastSuccessfulVerifyCommand,
              toolName: toolName,
              phase: configuration.continuationPhase
            ),
            kind: .invalidArguments
          )
        } else if configuration.phase == .develop,
          let lastSuccessfulVerifyCommand,
          let requestedVerifyCommand = Self.verifyCommand(arguments: arguments)
        {
          result = .failure(
            Self.repeatedSuccessfulVerifyRejectedMessage(
              previousCommand: lastSuccessfulVerifyCommand,
              requestedCommand: requestedVerifyCommand,
              phase: configuration.continuationPhase
            ),
            kind: .invalidArguments
          )
        } else {
          do {
            result = try await tool.invoke(arguments: arguments, context: toolContext)
          } catch let toolError as AgentToolError {
            result = .failure(toolError)
          } catch {
            result = .failure("Tool \(toolName) threw: \(error.localizedDescription)", kind: .unknown)
          }
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
        if !result.isError, Self.isFileMutationTool(toolName) {
          if let lastSuccessfulVerifyCommand {
            transcript.append(
              .repair(
                Self.successfulVerifyInvalidatedByMutationRepairMessage(
                  command: lastSuccessfulVerifyCommand,
                  toolName: toolName,
                  phase: configuration.continuationPhase
                )
              )
            )
          }
          lastSuccessfulVerifyCommand = nil
          if let lastFailedVerifyCommand {
            transcript.append(
              .repair(
                Self.failedVerifyInvalidatedByMutationRepairMessage(
                  command: lastFailedVerifyCommand,
                  toolName: toolName,
                  phase: configuration.continuationPhase
                )
              )
            )
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
          transcript.append(
            .repair(
              Self.successfulVerifyObservedRepairMessage(
                command: command,
                phase: configuration.continuationPhase
              )
            )
          )
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
          repeatedSuccessfulReadOnlyDevelopToolCallCount = 0
          consecutiveSuccessfulReadOnlyDevelopToolCallCount = 0
          successfulReadOnlyDevelopToolCallCounts = [:]
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
          if let failureFamily = Self.toolFailureFamily(
            toolName: toolName,
            arguments: arguments,
            result: result
          ) {
            let repeatCount = (failedToolFamilyCounts[failureFamily] ?? 0) + 1
            failedToolFamilyCounts[failureFamily] = repeatCount
            if repeatCount >= 2 {
              transcript.append(
                .repair(
                  Self.repeatedToolFailureFamilyRepairMessage(
                    toolName: toolName,
                    arguments: argumentText,
                    family: failureFamily.family,
                    path: failureFamily.path,
                    repeatCount: repeatCount,
                    latestFailure: result.content,
                    phase: configuration.continuationPhase
                  )
                )
              )
            }
          }
          successfulToolCallCountsAfterContinuationRejection = [:]
          successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation = 0
        } else {
          lastFailedToolCall = nil
          repeatedFailedToolCallCount = 0
          if let path = Self.pathArgument(from: arguments) {
            failedToolFamilyCounts = failedToolFamilyCounts.filter {
              $0.key.toolName != toolName || $0.key.path != path
            }
          }
          if configuration.phase == .develop, Self.isReadOnlyInspectionTool(toolName) {
            consecutiveSuccessfulReadOnlyDevelopToolCallCount += 1
            let readOnlyRepeatCount = (successfulReadOnlyDevelopToolCallCounts[signature] ?? 0) + 1
            successfulReadOnlyDevelopToolCallCounts[signature] = readOnlyRepeatCount
            repeatedSuccessfulReadOnlyDevelopToolCallCount = readOnlyRepeatCount
            if repeatedSuccessfulReadOnlyDevelopToolCallCount == 2
              || consecutiveSuccessfulReadOnlyDevelopToolCallCount == 6
            {
              transcript.append(
                .repair(
                  Self.repeatedReadOnlyDevelopToolRepairMessage(
                    toolName: toolName,
                    arguments: argumentText,
                    repeatCount: repeatedSuccessfulReadOnlyDevelopToolCallCount,
                    readOnlyCount: consecutiveSuccessfulReadOnlyDevelopToolCallCount,
                    phase: configuration.continuationPhase
                  )
                )
              )
            }
          } else {
            repeatedSuccessfulReadOnlyDevelopToolCallCount = 0
            consecutiveSuccessfulReadOnlyDevelopToolCallCount = 0
            successfulReadOnlyDevelopToolCallCounts = [:]
          }
          if sawContinuationRejection {
            if configuration.phase == .develop,
              Self.isReadOnlyInspectionTool(toolName),
              Self.isMalformedDevelopContinuationRejection(latestContinuationRejectionDescription)
            {
              successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation += 1
              if successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation == 1 {
                transcript.append(
                  .repair(
                    Self.readOnlyToolAfterMalformedDevelopContinuationRepairMessage(
                      toolName: toolName,
                      arguments: argumentText,
                      latestRepairMessage: latestContinuationRejectionRepairMessage,
                      phase: configuration.continuationPhase
                    )
                  )
                )
              }
            } else if !Self.isReadOnlyInspectionTool(toolName) {
              successfulReadOnlyToolCallCountAfterMalformedDevelopContinuation = 0
            }
            let repeatCount = (successfulToolCallCountsAfterContinuationRejection[signature] ?? 0) + 1
            successfulToolCallCountsAfterContinuationRejection[signature] = repeatCount
            if repeatCount >= 2 {
              transcript.append(
                .repair(
                  Self.repeatedToolAfterContinuationRejectionRepairMessage(
                    toolName: toolName,
                    arguments: argumentText,
                    repeatCount: repeatCount,
                    latestRepairMessage: latestContinuationRejectionRepairMessage,
                    rejectionDescription: latestContinuationRejectionDescription,
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

  private struct ToolCallSignature: Equatable, Hashable {
    var toolName: String
    var arguments: String
  }

  private struct ToolFailureFamilySignature: Equatable, Hashable {
    var toolName: String
    var path: String
    var family: String
  }

  private struct PendingSubmitRepair: Equatable {
    var submitKind: String
    var rejectionDescription: String
    var malformedJSON: Bool
    var repairMessage: String
  }

  private static func isFileMutationTool(_ toolName: String) -> Bool {
    toolName == AgentWriteFileTool.toolName || toolName == AgentEditFileTool.toolName
  }

  private static let readOnlyInspectionToolNames: Set<String> = [
    AgentFindSymbolTool.toolName,
    AgentGlobTool.toolName,
    AgentGrepTool.toolName,
    AgentImportersOfTool.toolName,
    AgentListFilesTool.toolName,
    AgentLsTool.toolName,
    AgentOutlineTool.toolName,
    AgentPlanHistoryTool.toolName,
    AgentReadFileTool.toolName,
    AgentSummaryTool.toolName,
  ]

  private static func isReadOnlyInspectionTool(_ toolName: String) -> Bool {
    readOnlyInspectionToolNames.contains(toolName)
  }

  private static func isMalformedDevelopContinuationRejection(_ description: String) -> Bool {
    description == "malformed Develop continuation response"
  }

  private static func toolFailureFamily(
    toolName: String,
    arguments: Data,
    result: AgentToolInvocationResult
  ) -> ToolFailureFamilySignature? {
    guard result.isError, toolName == AgentEditFileTool.toolName else { return nil }
    let lowered = result.content.lowercased()
    let family: String
    if lowered.contains("partial whole-file rewrite") {
      family = "partial whole-file rewrite"
    } else if lowered.contains("would remove the function declaration")
      && lowered.contains("body-only")
    {
      family = "body-only function declaration replacement"
    } else if lowered.contains("line range") && lowered.contains("out of range") {
      family = "out-of-range edit range"
    } else {
      return nil
    }

    return ToolFailureFamilySignature(
      toolName: toolName,
      path: pathArgument(from: arguments) ?? "<unknown>",
      family: family
    )
  }

  private static func pathArgument(from arguments: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any],
      let path = object["path"] as? String
    else {
      return nil
    }
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func isPostVerifyMutationJustified(reason: String?, note: String?) -> Bool {
    let text = [reason, note]
      .compactMap { $0 }
      .joined(separator: "\n")
      .lowercased()
    guard text.contains("acceptance") else { return false }
    return text.contains("missing")
      || text.contains("unmet")
      || text.contains("remaining")
      || text.contains("not yet")
      || text.contains("repair")
  }

  private static func successfulVerifyCommand(
    toolName: String,
    arguments: Data,
    result: AgentToolInvocationResult
  ) -> String? {
    guard toolName == AgentBashTool.toolName,
      !result.isError,
      result.content.contains("[exit 0]")
    else { return nil }

    return verifyCommand(arguments: arguments)
  }

  private static func failedVerifyCommand(
    toolName: String,
    arguments: Data,
    result: AgentToolInvocationResult
  ) -> String? {
    guard toolName == AgentBashTool.toolName,
      result.isError,
      result.errorKind == .bashFailure
    else { return nil }

    return verifyCommand(arguments: arguments)
  }

  private static func verifyCommand(arguments: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any] else {
      return nil
    }
    let command = [
      "command",
      "cmd",
      "shellCommand",
      "shell_command",
      "script",
    ].compactMap { object[$0] as? String }
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !command.isEmpty, AgentBashTool.isVerifyCommand(command) else { return nil }
    return command
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

  private static func generationLogLabel(
    configuration: AgentExecutionConfiguration,
    iteration: Int
  ) -> String {
    generationLogLabel(configuration: configuration, suffix: "iteration-\(iteration)")
  }

  private static func generationLogLabel(
    configuration: AgentExecutionConfiguration,
    suffix: String
  ) -> String {
    let prefix = configuration.promptLogLabelPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = prefix?.isEmpty == false ? prefix! : configuration.phase.rawValue
    return "\(base)-\(suffix)"
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
        maxOutputTokens: maxSummaryCompletionTokens,
        logLabel: Self.generationLogLabel(configuration: configuration, suffix: "compaction")
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

  private static func submitResultRepairMessage(
    error: String,
    invalidOutput: String,
    phase: AgentContinuationPhase
  ) -> String {
    """
    Your previous `\(phase.submitKind)` payload could not be used.

    Error:
    \(error)

    Required next shape:
    {"kind":"\(phase.submitKind)","payload":{...}}

    Do not call `\(phase.continueKind)` or any tool to repair this rejected submit.
    Existing observations remain available in recent history.

    Invalid response:
    \(fencedContinuationText(invalidOutput, limit: 4_000))
    """
  }

  private static func malformedContinuationSignature(
    error: String,
    output: String,
    phase: AgentContinuationPhase
  ) -> String {
    if mentionsContinuationKind(phase.submitKind, in: output) {
      return "malformed `\(phase.submitKind)` JSON"
    }
    if mentionsContinuationKind(phase.continueKind, in: output) {
      return "malformed `\(phase.continueKind)` JSON"
    }
    return error
  }

  private static func mentionsContinuationKind(_ kind: String, in output: String) -> Bool {
    output.range(
      of: #""kind"\s*:\s*"\#(NSRegularExpression.escapedPattern(for: kind))""#,
      options: .regularExpression
    ) != nil
  }

  private static func repeatedMalformedContinuationRepairMessage(
    signature: String,
    error: String,
    invalidOutput: String,
    repeatCount: Int,
    phase: AgentContinuationPhase
  ) -> String {
    let planGuidance =
      phase == .plan
      ? """

        For Plan, do not call more tools to repair JSON syntax. Return `\(phase.submitKind)`
        with a smaller valid payload. Keep `state.immediate.verify` as the planned verify command.
        If the plan text needs to mention an argv example, either escape quotes inside
        the JSON string or write it in words, for example: split `--count`, `3`, `Ship`,
        `it` argv.
        """
      : ""
    return """
    Compass rejected \(signature) \(repeatCount) times.

    This is a JSON syntax problem, not missing repository context. Do not call
    `read_file`, `list_files`, or other tools just to repair JSON formatting.
    Common cause: quotes inside string fields must be escaped, or the sentence should
    be rewritten without nested quoted code.

    Error:
    \(error)
    \(planGuidance)

    Return exactly one valid JSON object now:
    {"kind":"\(phase.submitKind)","payload":{...}}

    Latest invalid response:
    \(fencedContinuationText(invalidOutput, limit: 3_000))
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
    - If this is an edit_file failure, read the Compass Observation immediately above and
      use its concrete repair shape. For a partial whole-file rewrite, choose exactly one:
      whole-file replacement (`startLine=1`, `endLine=<current file line count>`, complete
      intended file content), insertion (`startLine=N`, `endLine=N-1`, only the new lines),
      or exact range replacement (the existing lines that should be removed). Do not submit
      failed/blocked just because the previous edit range was wrong.
    - If the path or lines are uncertain, call read_file or list_files first.
    - If you cannot make a different concrete tool call now, return `\(phase.submitKind)` with status=failed or status=blocked and concise feedback.

    Repeated arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func repeatedToolFailureFamilyRepairMessage(
    toolName: String,
    arguments: String,
    family: String,
    path: String,
    repeatCount: Int,
    latestFailure: String,
    phase: AgentContinuationPhase
  ) -> String {
    let guidance: String
    switch family {
    case "partial whole-file rewrite":
      guidance =
        "If you intended a whole-file rewrite, use the full file range from the latest read_file output. If you intended a local change, replace only the exact existing lines that should be removed. Do not move the same multi-line replacement to another single-line range."
    case "body-only function declaration replacement":
      guidance =
        "Either include the complete function declaration, body, and closing brace in the replacement, or edit only the body lines inside the function. Do not replace a function declaration line with indented body-only lines."
    case "out-of-range edit range":
      guidance =
        "Use the line count from the latest read_file/tool error. For a whole-file replacement, replace line 1 through the last existing line; for an append, insert at lastLine+1 with endLine=lastLine."
    default:
      guidance =
        "Use the concrete repair shape in the latest Compass Observation instead of shifting the same edit to a nearby range."
    }
    let concreteRepair: String
    if let payload = firstFencedJSONBlock(in: latestFailure) {
      concreteRepair = """

        Concrete repair arguments from the latest Compass Observation:
        ```json
        \(payload)
        ```
        Use these as the `arguments` for the next `\(toolName)` call. Do not call `read_file`
        before trying these arguments unless the payload is missing a required line range.
        """
    } else {
      concreteRepair = ""
    }

    return """
    You repeated `\(toolName)` failures in the same repair family for `\(path)`.

    Failure family: \(family)
    Seen in this phase: \(repeatCount) time(s)
    \(concreteRepair)

    Changing only `startLine`/`endLine` or rereading files is not repairing this failure.
    \(guidance)

    Choose exactly one next action:
    - Call `\(toolName)` with the concrete repair shape named in the latest Compass Observation.
    - Call `read_file` only if the latest observation does not include the current line count or needed range.
    - Return `\(phase.submitKind)` with status=failed or status=blocked if you cannot make a different concrete edit.

    Latest failure:
    \(fencedContinuationText(latestFailure, limit: 2_000))

    Latest failed arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func firstFencedJSONBlock(in text: String) -> String? {
    guard let regex = try? NSRegularExpression(
      pattern: #"```json\s*(.*?)\s*```"#,
      options: [.dotMatchesLineSeparators]
    ) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      match.numberOfRanges >= 2,
      let blockRange = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    let block = text[blockRange].trimmingCharacters(in: .whitespacesAndNewlines)
    return block.isEmpty ? nil : block
  }

  private static func toolAfterSubmitRepairMessage(
    toolName: String,
    arguments: String,
    pendingRepair: PendingSubmitRepair,
    phase: AgentContinuationPhase,
    repeatCount: Int
  ) -> String {
    let reason = pendingRepair.malformedJSON
      ? "because the JSON was malformed"
      : "because Compass rejected its payload"
    let repairTarget = pendingRepair.malformedJSON
      ? "malformed submit JSON"
      : "a rejected submit payload"
    let planPayloadRepair =
      phase == .plan
      ? """

        For Plan, repair `state.immediate.plan` directly:
        - Keep the same Outcome if it is still useful.
        - Add the missing Acceptance checks line from the Compass Repair below.
        - Include both the target test file path and the concrete invocation in that line.
        - Return `\(phase.submitKind)` immediately; no repository file needs to be reread.
        """
      : ""
    let repeatedWarning =
      repeatCount >= 2
      ? """

        You have now tried the same blocked `\(toolName)` call \(repeatCount) times after
        Compass rejected `\(pendingRepair.submitKind)`. Compass will keep rejecting tools
        until you repair the submit envelope.

        The continuation-contract `read_file package.json` shape is only an example. It is
        lower authority than this Compass Repair. Do not copy that example here.

        Your next response must be `\(phase.submitKind)`, not `\(phase.continueKind)`.
        """
      : ""
    return """
    Your previous `\(pendingRepair.submitKind)` was rejected \(reason).
    The next action must repair that submit envelope; it must not call tools.

    Compass did not run `\(toolName)`. Do not call `read_file`, `list_files`, `bash`,
    or other tools just to repair \(repairTarget). Existing observations remain
    available in the recent history.

    Return exactly one valid JSON object now:
    {"kind":"\(phase.submitKind)","payload":{...}}
    \(planPayloadRepair)\(repeatedWarning)

    Apply this repair:
    \(pendingRepair.repairMessage)

    Rejected tool arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func repeatedToolAfterContinuationRejectionRepairMessage(
    toolName: String,
    arguments: String,
    repeatCount: Int,
    latestRepairMessage: String?,
    rejectionDescription: String,
    phase: AgentContinuationPhase
  ) -> String {
    let planInstruction =
      phase == .plan
      ? """

        For Plan, read-only tools cannot repair a rejected handoff. Return `\(phase.submitKind)` now.
        Do not call `read_file`, `list_files`, `bash`, or reread `package.json` just to repair
        Plan payload text.
        """
      : ""
    let repairHeading = rejectionDescription.contains("payload")
      ? "Latest rejected-payload repair to apply now:"
      : "Latest continuation repair to apply now:"
    let latestRepair = latestRepairMessage.map {
      """

      \(repairHeading)
      \($0)
      """
    } ?? ""
    return """
    Compass already rejected a recent \(rejectionDescription), and you then called
    `\(toolName)` with the same arguments \(repeatCount) times. The repeated observation
    did not repair the rejected continuation.

    Do not call `\(toolName)` again with the same arguments. Repair the rejected
    continuation now:
    - Reuse useful fields from the rejected output, if any.
    - Apply the latest Compass Repair instruction exactly.
    - If the rejected payload said a verify command still needs to run, call `bash`
      with that command now. Do not call `read_file`, `list_files`, or reread
      `package.json` merely to rediscover scripts.
    - Return `\(phase.submitKind)` with a corrected `payload`.
    - Only call a different tool if the repair instruction explicitly requires new evidence.
    \(planInstruction)\(latestRepair)

    Repeated arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func readOnlyToolAfterMalformedDevelopContinuationRepairMessage(
    toolName: String,
    arguments: String,
    latestRepairMessage: String?,
    phase: AgentContinuationPhase
  ) -> String {
    let latestRepair = latestRepairMessage.map {
      """

      Latest malformed-continuation repair to apply now:
      \($0)
      """
    } ?? ""
    return """
    You called read-only inspection tool `\(toolName)` after Compass rejected a malformed
    Develop continuation. Compass ran the tool and the observation is now in history, but
    reading more files does not repair malformed JSON or malformed tool arguments.

    Use the latest observations and repair the rejected continuation now:
    - If the rejected response was an `edit_file` with multiline content, return
      `\(phase.continueKind)` using `edit_file` and `replacementLines` as an array of strings.
    - Do not reread `package.json`, list files, or inspect other files merely to repair JSON syntax.
    - Call `bash` only after the needed file edits/tests have been accepted.
    - Return `\(phase.submitKind)` with status=failed or status=blocked only if no concrete
      edit or verify call remains.
    \(latestRepair)

    Read-only detour arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func repeatedSubmitRejectionRepairMessage(
    eventText: String,
    eventDetail: String,
    latestRepairMessage: String,
    repeatCount: Int,
    phase: AgentContinuationPhase
  ) -> String {
    let planRepair =
      phase == .plan
      ? """

        Plan repair checklist:
        - Do not call another tool. The rejected payload text is what must change.
        - Do not resubmit the same `state.immediate.plan`.
        - Keep `state.immediate.verify` as the planned verify command unless the latest repair says otherwise.
        - If the rejection is about CLI proof, add an explicit Acceptance check in
          `state.immediate.plan` naming the CLI test file and invocation, for example:
          `packages/cli/src/main.test.ts` calls `main(["--format", "json", "Ship", "it"])`
          and asserts the parsed JSON title is `Ship it`.
        """
      : ""
    return """
      Compass rejected `\(phase.submitKind)` for the same reason \(repeatCount) times:
      \(eventText)

      Rejection detail:
      \(eventDetail)

      Do not return the same payload again. Return `\(phase.submitKind)` now with a changed
      `payload` that applies the latest repair exactly.\(planRepair)

      Latest rejected-payload repair to apply now:
      \(latestRepairMessage)
      """
  }

  private static func repeatedReadOnlyDevelopToolRepairMessage(
    toolName: String,
    arguments: String,
    repeatCount: Int,
    readOnlyCount: Int,
    phase: AgentContinuationPhase
  ) -> String {
    """
    You repeated successful read-only Develop tool calls without changing files.

    The latest `\(toolName)` observation succeeded and already contains the concrete
    evidence available from that tool. You have made \(readOnlyCount) successful
    read-only tool calls in a row without changing files, and the latest exact
    `\(toolName)` arguments have been seen \(repeatCount) time(s) in that streak.

    Do not call `\(toolName)` again with the same arguments. Do not keep calling
    `read_file`, `list_files`, `ls`, `glob`, `grep`, `outline`, `find_symbol`,
    `importers_of`, `summary`, or `plan_history` merely to rediscover context.
    Choose exactly one next action:
    - Call `edit_file` or `write_file` using the known paths and line numbers.
    - Call `bash` with the verify command only if the implementation is complete.
    - Return `\(phase.submitKind)` with status=failed or status=blocked if you cannot
      make a concrete edit within this budget.

    Latest arguments:
    \(fencedContinuationText(arguments, limit: 2_000))
    """
  }

  private static func successfulVerifyObservedRepairMessage(
    command: String,
    phase: AgentContinuationPhase
  ) -> String {
    """
    Compass observed `\(command)` exit 0. This verify command passed.

    Do not interpret earlier stdout lines as failures unless the final exit marker is nonzero.
    If the requested packet and acceptance checks are complete, return `\(phase.submitKind)` now
    with status=succeeded, bypassVerify=false, and feedback naming `\(command)` as verified.
    Continue only if a specific acceptance requirement is still missing.
    """
  }

  private static func successfulVerifyInvalidatedByMutationRepairMessage(
    command: String,
    toolName: String,
    phase: AgentContinuationPhase
  ) -> String {
    """
    You just changed files with `\(toolName)` after Compass observed `\(command)` exit 0.

    That earlier verify result no longer proves the current worktree. Do not submit
    status=succeeded based on the old verify result. Choose exactly one next action:
    - If the requested packet is now complete, call `bash` with `\(command)` again.
    - If a specific acceptance requirement is still missing, make that concrete edit now.
    - If you cannot complete the repair in this budget, return `\(phase.submitKind)` with
      status=failed or status=blocked and concise feedback.
    """
  }

  private static func failedVerifyInvalidatedByMutationRepairMessage(
    command: String,
    toolName: String,
    phase: AgentContinuationPhase
  ) -> String {
    """
    You just changed files with `\(toolName)` after Compass observed `\(command)` fail.

    That earlier failure no longer proves the current worktree. Do not submit
    status=failed based on the old verify/typecheck/test output. Choose exactly one next action:
    - If the requested packet might now be complete, call `bash` with `\(command)` again.
    - If a specific acceptance requirement is still missing, make that concrete edit now.
    - If verification cannot be rerun because of an external blocker, return `\(phase.submitKind)`
      with status=blocked and concise feedback explaining why.
    """
  }

  private static func repeatedSuccessfulVerifyRejectedMessage(
    previousCommand: String,
    requestedCommand: String,
    phase: AgentContinuationPhase
  ) -> String {
    let requestedLine =
      requestedCommand == previousCommand
      ? ""
      : "\nThe latest requested verify command was `\(requestedCommand)`, which is still a verify command."
    return """
      Compass already observed `\(previousCommand)` exit 0, and no accepted file edit has happened since that successful verify.\(requestedLine)

      Do not rerun verify against the same worktree. Repeating the proof command cannot implement missing acceptance requirements and wastes the Develop budget. Choose exactly one next action:
      - If the requested packet is complete, return `\(phase.submitKind)` with status=succeeded, bypassVerify=false, and one concrete feedback sentence naming `\(previousCommand)` as the passing verification.
      - If a specific acceptance requirement is still missing, call `edit_file` or `write_file` now, then run `\(previousCommand)` after that accepted mutation.
      - If you cannot make a concrete edit in this budget, return `\(phase.submitKind)` with status=failed or status=blocked and concise feedback.
      """
  }

  private static func postVerifyMutationRejectedMessage(
    command: String,
    toolName: String,
    phase: AgentContinuationPhase
  ) -> String {
    """
    Compass already observed `\(command)` exit 0. A generic `\(toolName)` call after a
    passing verify would invalidate that proof before the phase can submit.

    Choose exactly one next action:
    - If the requested packet is complete, return `\(phase.submitKind)` now with
      status=succeeded, bypassVerify=false, and feedback naming `\(command)` as verified.
    - If an acceptance check is still missing, retry `\(toolName)` only with a `reason` that
      explicitly names the missing acceptance check it repairs, then rerun `\(command)`.
    - If you cannot finish in budget, return `\(phase.submitKind)` with status=failed or
      status=blocked and concise feedback.
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

  private static func rejectFailedDevelopSubmitAfterContinuationRejection(
    _ submitResultJSON: Data,
    sawContinuationRejection: Bool,
    latestRepairMessage: String?,
    rejectionDescription: String,
    configuration: AgentExecutionConfiguration
  ) -> InvalidToolArgumentsNudge? {
    guard configuration.phase == .develop,
      sawContinuationRejection,
      let summary = try? JSONDecoder().decode(DevelopSummary.self, from: submitResultJSON),
      summary.status == .failed,
      let proceduralFeedback = proceduralFailedDevelopFeedback(summary)
    else { return nil }

    let repair = latestRepairMessage.map {
      "\n\nLatest Compass repair message:\n\(fencedContinuationText($0, limit: 2_000))"
    } ?? ""

    return InvalidToolArgumentsNudge(
      eventText: "develop_submit procedural failure rejected",
      eventDetail:
        "Develop submitted status=failed after a repairable \(rejectionDescription) rejection: `\(proceduralFeedback)`.",
      userMessage: """
        Your previous `develop_submit` reported status=failed after Compass had already rejected
        a repairable \(rejectionDescription), and its feedback says to fix tool/JSON formatting
        and try again:
        `\(proceduralFeedback)`

        This is not a terminal Develop result. Do not submit failed for malformed continuation JSON.
        Return a valid `develop_continue` with corrected JSON now. If you need multiline
        `edit_file` content, use `replacementLines` as an array of strings, not JavaScript
        template literals.

        Submit status=failed only for a real project blocker after you have no concrete
        tool call left to try.
        \(repair)

        \(submitResultDecodeRetryShape(for: .develop))
        """
    )
  }

  private static func rejectFailedDevelopSubmitAfterInvalidatedVerify(
    _ submitResultJSON: Data,
    invalidatedVerifyCommand: String?,
    configuration: AgentExecutionConfiguration
  ) -> InvalidToolArgumentsNudge? {
    guard configuration.phase == .develop,
      let invalidatedVerifyCommand,
      let summary = try? JSONDecoder().decode(DevelopSummary.self, from: submitResultJSON),
      summary.status == .failed
    else { return nil }

    return InvalidToolArgumentsNudge(
      eventText: "develop_submit used stale verify failure",
      eventDetail:
        "Develop submitted status=failed after files changed following a failed `\(invalidatedVerifyCommand)` run.",
      userMessage: """
        Compass previously observed this verify command fail:
        `\(invalidatedVerifyCommand)`

        But files were changed after that failure, so the old verify/typecheck/test output
        no longer proves the current worktree. Do not submit status=failed from stale
        verification errors.

        Choose exactly one repair:
        - If the requested packet might now be complete, call `bash` with `\(invalidatedVerifyCommand)` again.
        - If a specific acceptance requirement is still missing, call `develop_continue`
          with the concrete `edit_file` or `write_file` repair now.
        - If verification cannot be rerun because of an external blocker, return
          `develop_submit` with status=blocked and concise feedback explaining why.

        \(submitResultDecodeRetryShape(for: .develop))
        """
    )
  }

  private static func proceduralFailedDevelopFeedback(_ summary: DevelopSummary) -> String? {
    let feedback = normalizedInlineText(summary.feedback)
    let combined = normalizedInlineText("\(summary.summary) \(summary.feedback)")
    let lowercased = combined.lowercased()
    let retryPhrases = [
      "try again",
      "retry",
      "re-try",
      "rerun",
      "re-run",
    ]
    guard retryPhrases.contains(where: { lowercased.contains($0) }) else { return nil }

    let toolShapePhrases = [
      "arguments",
      "continuation",
      "develop_continue",
      "edit_file",
      "format",
      "formatting",
      "json",
      "malformed",
      "parse",
      "payload",
      "schema",
      "syntax",
      "tool",
    ]
    guard toolShapePhrases.contains(where: { lowercased.contains($0) }) else { return nil }
    return feedback.isEmpty ? combined : feedback
  }

  private static func normalizedInlineText(_ text: String) -> String {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func rejectDevelopSubmitAfterSuccessfulVerify(
    _ submitResultJSON: Data,
    successfulVerifyCommand: String?,
    configuration: AgentExecutionConfiguration
  ) -> InvalidToolArgumentsNudge? {
    guard configuration.phase == .develop,
      let successfulVerifyCommand,
      let summary = try? JSONDecoder().decode(DevelopSummary.self, from: submitResultJSON),
      summary.status != .succeeded || summary.bypassVerify == true
    else { return nil }

    let submittedState =
      "status=\(summary.status.rawValue), bypassVerify=\(summary.bypassVerify == true ? "true" : "false")"
    return InvalidToolArgumentsNudge(
      eventText: "develop_submit contradicted successful verify",
      eventDetail:
        "`\(successfulVerifyCommand)` exited 0, but Develop submitted \(submittedState).",
      userMessage: """
        Compass already observed this verify command pass:
        `\(successfulVerifyCommand)`

        The bash observation ended with `[exit 0]`. Your previous Develop payload reported
        \(submittedState), which contradicts the successful verify result.

        Do not call another tool to inspect that verify output. Choose exactly one repair:
        - If the requested packet is complete, return `develop_submit` again with
          status=succeeded, bypassVerify=false, and feedback that names `\(successfulVerifyCommand)`
          as the passing verification.
        - If a specific acceptance check from the Handoff is still missing, return
          `develop_continue` for that missing check and name it in the reason.

        \(submitResultDecodeRetryShape(for: .develop))
        """
    )
  }
}
