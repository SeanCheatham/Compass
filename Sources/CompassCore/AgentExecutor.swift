import Foundation

/// Outcome of one Plan / Develop / Critic pass.
///
/// `submitResultArguments` holds the JSON payload the model returned in the
/// terminal phase submit envelope: the structured response Compass decodes
/// into `PlanRunResult`, `DevelopSummary`, or `CriticVerdict`.
public struct AgentExecutionResult: Equatable {
  public var submitResultArguments: Data
  public var iterations: Int
  public var assistantText: String
  public var reasoningText: String
  public var tokenUsage: AgentRunTokenUsage
}

/// Configuration for a single AgentExecutor.run() invocation.
public struct AgentExecutionConfiguration {
  public var settings: AgentRuntimeSettings
  public var phase: AgentPhase
  public var continuationPhase: AgentContinuationPhase
  public var modelOverride: String
  public var systemPrompt: String
  public var userPrompt: String
  public var tools: [AgentTool]
  public var modelRuntime: (any LocalModelGenerating)?
  /// Virtual workspace root presented to the model (typically `/workspace`
  /// for macOS VM factory phases). `nil` keeps host-native paths.
  public var agentVisibleWorkspacePath: String?
  public var submitResultSchema: AgentToolParametersSchema
  public var workingDirectory: URL
  public var filesystem: AgentFilesystem
  public var bashRunner: AgentBashRunner
  /// Host-side codemap directory. When the agent runs in the macOS VM,
  /// `workingDirectory` is the guest workspace path and is *not* where
  /// the codemap lives — the caller must supply the actual store
  /// location so codemap-backed tools see real entries. `nil` falls
  /// back to `<workingDirectory>/.compass/codemap`, which is correct
  /// only for host-route runs against a canonical repo-local workspace.
  public var codemapStoreDirectory: URL?
  /// Host-side completed plan summaries for the `plan_history` tool.
  public var planHistoryEntries: [String]
  /// Host-side assumptions ledger URL for assumption-management tools.
  public var assumptionsURL: URL?
  /// Compass session number associated with this phase, when one exists.
  public var sessionNumber: Int?
  /// Optional prefix for prompt-log artifact labels, such as `develop-attempt-2`.
  public var promptLogLabelPrefix: String?
  /// Optional post-decode guard for the phase submit payload. When it throws,
  /// the executor rolls back the turn and reprompts — same remediation
  /// path as malformed tool JSON. `runAgent` uses this to reject lesson
  /// edits that don't match lessons.md, payloads that don't decode into
  /// the phase result model, and phase-specific weak handoffs.
  public var validateSubmitResult: (@Sendable (Data) throws -> Void)?
  /// Which loop protocol the prompts were built for. `.nativeTools` runs the
  /// native tool-calling loop when the resolved backend supports it.
  public var promptMode: AgentPromptMode
  public var maxIterations: Int
  public var wallClockTimeout: TimeInterval

  public init(
    settings: AgentRuntimeSettings,
    phase: AgentPhase,
    continuationPhase: AgentContinuationPhase? = nil,
    modelOverride: String = "",
    systemPrompt: String,
    userPrompt: String,
    tools: [AgentTool],
    modelRuntime: (any LocalModelGenerating)? = nil,
    agentVisibleWorkspacePath: String? = nil,
    submitResultSchema: AgentToolParametersSchema,
    workingDirectory: URL,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    codemapStoreDirectory: URL? = nil,
    planHistoryEntries: [String] = [],
    assumptionsURL: URL? = nil,
    sessionNumber: Int? = nil,
    promptLogLabelPrefix: String? = nil,
    validateSubmitResult: (@Sendable (Data) throws -> Void)? = nil,
    promptMode: AgentPromptMode = .envelope,
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
    self.agentVisibleWorkspacePath = agentVisibleWorkspacePath
    self.submitResultSchema = submitResultSchema
    self.workingDirectory = workingDirectory
    self.filesystem = filesystem
    self.bashRunner = bashRunner
    self.codemapStoreDirectory = codemapStoreDirectory
    self.planHistoryEntries = planHistoryEntries
    self.assumptionsURL = assumptionsURL
    self.sessionNumber = sessionNumber
    self.promptLogLabelPrefix = promptLogLabelPrefix
    self.validateSubmitResult = validateSubmitResult
    self.promptMode = promptMode
    self.maxIterations = maxIterations
    self.wallClockTimeout = wallClockTimeout
  }

  /// Effective context window from the runtime settings. `0` means
  /// auto-compaction is disabled.
  public var contextWindowTokens: Int { settings.contextWindowTokens }
}

public enum AgentExecutionError: LocalizedError, Equatable {
  case streamFailed(String)
  case maxIterationsExceeded(Int)
  case wallClockExceeded(TimeInterval)
  case modelStoppedWithoutSubmitResult
  case toolCallDecodeFailed(name: String, detail: String)
  case duplicateToolName(String)
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .streamFailed(let detail): return "Model generation failed: \(detail)"
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
  public var isAgentBudgetExhaustion: Bool {
    switch self {
    case .wallClockExceeded, .maxIterationsExceeded:
      return true
    default:
      return false
    }
  }
}

/// Runs an agent phase (Plan / Develop / Critic) against the configured model
/// runtime. The primary path is native tool calling; the legacy path terminates
/// when the model emits the phase's `*_submit` envelope, whose `payload` matches
/// the phase's output schema.
public final class AgentExecutor {
  /// Retained as the recovery prompt budget for compatibility with existing
  /// remediation text.
  public static let maxCompletionTokensPerTurn = 65_536

  /// Fraction of the configured context window at which the executor
  /// runs auto-compaction. We measure against a chars-per-token estimate
  /// of the current `messages` array (see `estimatedTokens(in:)`); the
  /// next turn also adds tool-result messages, so triggering at 0.75
  /// leaves headroom for one more full turn before the request itself
  /// would exceed the window.
  public static let compactionThresholdFraction: Double = 0.75

  /// Conventional chars-per-token divisor for local token estimates.
  public static let estimatedCharsPerToken: Int = 4

  /// Per-call output cap for the summarization request. The summary
  /// replaces the entire mid-conversation history, so we let it run
  /// long enough to capture pending file paths / errors / next steps
  /// without bumping into the model's hard ceiling.
  public static let maxSummaryCompletionTokens: Int = 8_192

  public let onEvent: @Sendable (LiveEvent) -> Void
  public var cancelled = false

  public init(onEvent: @Sendable @escaping (LiveEvent) -> Void = { _ in }) {
    self.onEvent = onEvent
  }

  public func cancel() {
    cancelled = true
  }
}
