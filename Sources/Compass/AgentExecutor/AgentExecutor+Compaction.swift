import Foundation
import OpenAI

extension AgentExecutor {
  // MARK: - Auto-compaction

  struct CompactionTokenUsage: Equatable, Sendable {
    var summaryTokens: Int
  }

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
  func compactMessages(
    openAI: OpenAI,
    model: Model,
    messages: inout [ChatQuery.ChatCompletionMessageParam],
    estimatedTokensBeforeCompaction: Int,
    contextWindowTokens: Int
  ) async throws -> CompactionTokenUsage? {
    guard messages.count >= 2 else { return nil }
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
      return nil
    }

    let summary = summaryTurn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !summary.isEmpty else {
      emit(
        level: .warning,
        text: "Auto-compaction produced empty summary; keeping prior history",
        kind: .lifecycle,
        status: .failed
      )
      return nil
    }

    let collapsedCount = messages.count
    let summaryTokens = summaryTurn.usage?.outputTokens
      ?? AgentRunTokenUsage.estimateTokens(
        characters: summary.count,
        charsPerToken: Self.estimatedCharsPerToken
      )
    messages = Self.compactedMessages(
      system: messages[0],
      originalUser: messages[1],
      summary: summary
    )
    emit(
      level: .info,
      text: "Auto-compacted conversation",
      detail:
        "Collapsed \(collapsedCount) messages into a summary (~\(summaryTokens) tokens).",
      kind: .lifecycle,
      status: .completed
    )
    return CompactionTokenUsage(summaryTokens: summaryTokens)
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
}
