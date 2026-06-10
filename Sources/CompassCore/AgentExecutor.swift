import Foundation

/// Outcome of one Plan / Develop / Critic pass.
///
/// `submitResultArguments` holds the JSON payload the model returned in the
/// terminal phase submit envelope: the structured response Compass decodes
/// into `PlanRunResult`, `DevelopSummary`, or `CriticVerdict`.
struct AgentExecutionResult: Equatable {
  var submitResultArguments: Data
  var iterations: Int
  var assistantText: String
  var reasoningText: String
  var tokenUsage: AgentRunTokenUsage
}

/// Configuration for a single AgentExecutor.run() invocation.
struct AgentExecutionConfiguration {
  var settings: AgentRuntimeSettings
  var phase: AgentPhase
  var continuationPhase: AgentContinuationPhase
  var modelOverride: String
  var systemPrompt: String
  var userPrompt: String
  var tools: [AgentTool]
  var modelRuntime: (any LocalModelGenerating)?
  var submitResultSchema: AgentToolParametersSchema
  var workingDirectory: URL
  var filesystem: AgentFilesystem
  var bashRunner: AgentBashRunner
  /// Host-side codemap directory. When the agent runs in the containerized Linux runtime,
  /// `workingDirectory` is the container workspace path and is *not* where
  /// the codemap lives — the caller must supply the actual store
  /// location so codemap-backed tools see real entries. `nil` falls
  /// back to `<workingDirectory>/.compass/codemap`, which is correct
  /// only for host-route runs against a canonical repo-local workspace.
  var codemapStoreDirectory: URL?
  /// Host-side completed plan summaries for the `plan_history` tool.
  var planHistoryEntries: [String]
  /// Host-side assumptions ledger URL for assumption-management tools.
  var assumptionsURL: URL?
  /// Compass session number associated with this phase, when one exists.
  var sessionNumber: Int?
  /// Optional post-decode guard for the phase submit payload. When it throws,
  /// the executor rolls back the turn and reprompts — same remediation
  /// path as malformed tool JSON. `runAgent` uses this to reject lesson
  /// edits that don't match lessons.md, payloads that don't decode into
  /// the phase result model, and phase-specific weak handoffs.
  var validateSubmitResult: (@Sendable (Data) throws -> Void)?
  var maxIterations: Int
  var wallClockTimeout: TimeInterval

  init(
    settings: AgentRuntimeSettings,
    phase: AgentPhase,
    continuationPhase: AgentContinuationPhase? = nil,
    modelOverride: String = "",
    systemPrompt: String,
    userPrompt: String,
    tools: [AgentTool],
    modelRuntime: (any LocalModelGenerating)? = nil,
    submitResultSchema: AgentToolParametersSchema,
    workingDirectory: URL,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    codemapStoreDirectory: URL? = nil,
    planHistoryEntries: [String] = [],
    assumptionsURL: URL? = nil,
    sessionNumber: Int? = nil,
    validateSubmitResult: (@Sendable (Data) throws -> Void)? = nil,
    maxIterations: Int = 512,
    wallClockTimeout: TimeInterval = 60 * 60
  ) {
    self.settings = settings
    self.phase = phase
    self.continuationPhase = continuationPhase ?? AgentContinuationPhase(agentPhase: phase)
    self.modelOverride = modelOverride
    self.systemPrompt = systemPrompt
    self.userPrompt = userPrompt
    self.tools = tools
    self.modelRuntime = modelRuntime
    self.submitResultSchema = submitResultSchema
    self.workingDirectory = workingDirectory
    self.filesystem = filesystem
    self.bashRunner = bashRunner
    self.codemapStoreDirectory = codemapStoreDirectory
    self.planHistoryEntries = planHistoryEntries
    self.assumptionsURL = assumptionsURL
    self.sessionNumber = sessionNumber
    self.validateSubmitResult = validateSubmitResult
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
    case .streamFailed(let detail): return "Local model generation failed: \(detail)"
    case .maxIterationsExceeded(let n): return "Agent exceeded max iterations (\(n))"
    case .wallClockExceeded(let timeout):
      return "Agent exceeded wall-clock timeout (\(Int(timeout))s)"
    case .modelStoppedWithoutSubmitResult:
      return "Model stopped without returning a phase submit envelope"
    case .toolCallDecodeFailed(let name, let detail):
      return "Tool call \(name) had undecodable args: \(detail)"
    case .duplicateToolName(let name): return "Duplicate tool name in registry: \(name)"
    case .cancelled: return "Agent execution cancelled"
    }
  }

  /// True when the agent's wall-clock or iteration budget was the cause
  /// — i.e. it didn't finish via a phase submit envelope because it ran out of
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

/// Runs the local MLX loop with Compass-owned JSON continuations. Terminates when
/// the model emits the phase's `*_submit` envelope, whose `payload` matches
/// the phase's output schema.
final class AgentExecutor {
  /// Retained as the recovery prompt budget for compatibility with existing
  /// remediation text.
  static let maxCompletionTokensPerTurn = 65_536

  /// Retained for older budget summaries; the local runtime owns retry policy.
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

  /// Conventional chars-per-token divisor for local token estimates.
  static let estimatedCharsPerToken: Int = 4

  /// Per-call output cap for the summarization request. The summary
  /// replaces the entire mid-conversation history, so we let it run
  /// long enough to capture pending file paths / errors / next steps
  /// without bumping into the model's hard ceiling.
  static let maxSummaryCompletionTokens: Int = 8_192

  let onEvent: @Sendable (LiveEvent) -> Void
  var cancelled = false

  init(onEvent: @Sendable @escaping (LiveEvent) -> Void = { _ in }) {
    self.onEvent = onEvent
  }

  func cancel() {
    cancelled = true
  }
}
