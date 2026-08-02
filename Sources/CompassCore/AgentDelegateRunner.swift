import Foundation

/// Spawn a focused sub-agent that runs inside the same working
/// directory / filesystem / bash runner as the parent and returns a
/// single `findings` string. The sub-agent inherits the parent's local
/// MLX runtime and working context.
///
/// `toolNames == nil` means "give the sub-agent the parent's full tool
/// set (minus `delegate`)". A non-nil array filters the parent's tools
/// by name; unknown names are silently dropped so a typoed request
/// doesn't fail the whole turn.
public protocol AgentDelegateRunner: Sendable {
  func delegate(
    task: String,
    toolNames: [String]?,
    profile: String?,
    modelOverride: String?
  ) async throws -> String
}

/// Default runner that spins up a child `AgentExecutor` configured
/// against the parent's settings. The child uses `Prompts.subAgentSchema`
/// and `Prompts.subAgentSystemPrompt`; its tool list excludes
/// `AgentDelegateTool` so sub-agents cannot delegate further. That
/// depth-cap is the only nesting-prevention — every other Sendable
/// invariant (the runner itself, the captured tools, the event sink)
/// is fine to share across levels because tools are stateless and the
/// executor's transient state lives on the stack of `run`.
public struct AgentExecutorDelegateRunner: AgentDelegateRunner {
  public let settings: AgentRuntimeSettings
  public let parentPhase: AgentPhase
  public let parentModelOverride: String
  public let workingDirectory: URL
  public let agentVisibleWorkspacePath: String?
  public let filesystem: AgentFilesystem
  public let bashRunner: AgentBashRunner
  /// Host-side codemap directory inherited from the parent run. Nil
  /// means the sub-agent falls back to `<workingDirectory>/.compass/codemap`,
  /// which is wrong for container routes — top-level callers should
  /// always supply this.
  public let codemapStoreDirectory: URL?
  /// Host-side assumptions ledger inherited from the parent so sub-agents
  /// can record assumptions made during focused investigations.
  public let assumptionsURL: URL?
  public let sessionNumber: Int?
  /// Snapshot of the parent's tool list. `delegate(toolNames:)` filters
  /// this; `AgentDelegateTool` is always excluded from the child's
  /// effective tool list so sub-agents cannot recurse.
  public let parentTools: [AgentTool]
  public let parentMaxIterations: Int
  public let parentWallClockTimeout: TimeInterval
  /// Live-log sink so sub-agent activity surfaces under the parent run.
  public let onEvent: @Sendable (LiveEvent) -> Void

  /// Hard cap on sub-agent iterations even when the parent has a higher
  /// budget. Sub-agents should produce focused investigations, not
  /// open-ended phase work.
  public static let maxSubAgentIterations = 96
  /// Wall-clock cap for a single sub-agent invocation.
  public static let maxSubAgentWallClock: TimeInterval = 15 * 60

  public func delegate(
    task: String,
    toolNames: [String]?,
    profile: String?,
    modelOverride: String?
  ) async throws -> String {
    let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTask.isEmpty else {
      throw AgentDelegateRunnerError.emptyTask
    }

    let effectiveTools = Self.filterTools(
      parentTools: parentTools,
      requested: toolNames ?? Self.toolNames(forProfile: profile)
    )
    let toolNameList = effectiveTools.map { $0.spec.name }
    let promptMode = ModelRuntimeFactory.promptMode(settings: settings)
    let systemPrompt = Prompts.subAgentSystemPrompt(
      parentPhase: parentPhase,
      workingDirectoryPath: agentVisibleWorkspacePath
        ?? workingDirectory.path,
      toolNames: toolNameList,
      promptMode: promptMode
    )
    let configuration = AgentExecutionConfiguration(
      settings: settings,
      phase: parentPhase,
      continuationPhase: .delegate,
      modelOverride: (modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
        $0.isEmpty ? nil : $0
      } ?? parentModelOverride,
      systemPrompt: systemPrompt,
      userPrompt: trimmedTask,
      tools: effectiveTools,
      agentVisibleWorkspacePath: agentVisibleWorkspacePath,
      submitResultSchema: AgentToolParametersSchema(json: Data(Prompts.subAgentSchema.utf8)),
      workingDirectory: workingDirectory,
      filesystem: filesystem,
      bashRunner: bashRunner,
      codemapStoreDirectory: codemapStoreDirectory,
      assumptionsURL: assumptionsURL,
      sessionNumber: sessionNumber,
      promptMode: promptMode,
      maxIterations: min(parentMaxIterations, Self.maxSubAgentIterations),
      wallClockTimeout: min(parentWallClockTimeout, Self.maxSubAgentWallClock)
    )
    let executor = AgentExecutor(onEvent: onEvent)
    let result = try await executor.run(configuration)
    let payload: SubAgentResult
    do {
      payload = try JSONDecoder().decode(SubAgentResult.self, from: result.submitResultArguments)
    } catch {
      let body = String(decoding: result.submitResultArguments, as: UTF8.self)
      throw AgentDelegateRunnerError.malformedFindings(detail: body)
    }
    let trimmed = payload.findings.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "(sub-agent returned no findings)" : trimmed
  }

  /// Build the child's tool list from the parent's, dropping the
  /// `delegate` tool unconditionally (depth-cap) and intersecting with
  /// `requested` when non-nil. Requested names accept the same common model
  /// variants as top-level tool dispatch. Unknown names are silently dropped
  /// so a misspelled tool name doesn't blow up the whole turn — the sub-agent
  /// will simply find that name absent from its system prompt.
  public static func filterTools(parentTools: [AgentTool], requested: [String]?) -> [AgentTool] {
    let withoutDelegate = parentTools.filter { $0.spec.name != AgentDelegateTool.toolName }
    guard let requested else { return withoutDelegate }
    let availableNames = Set(withoutDelegate.map(\.spec.name))
    let allowed = Set(
      requested.compactMap {
        AgentExecutor.canonicalToolName($0, availableToolNames: availableNames)
      })
    return withoutDelegate.filter { allowed.contains($0.spec.name) }
  }

  public static func toolNames(forProfile rawProfile: String?) -> [String]? {
    guard let profile = rawProfile?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      !profile.isEmpty
    else { return nil }
    switch profile {
    case "test", "typecheck":
      return [
        AgentReadFileTool.toolName,
        AgentListFilesTool.toolName,
        AgentOutlineTool.toolName,
        AgentFindSymbolTool.toolName,
        AgentSummaryTool.toolName,
        AgentGrepTool.toolName,
        AgentBashTool.toolName,
      ]
    default:
      return nil
    }
  }
}

public struct SubAgentResult: Decodable {
  public let findings: String
}

public enum AgentDelegateRunnerError: LocalizedError, Equatable {
  case emptyTask
  case malformedFindings(detail: String)

  public var errorDescription: String? {
    switch self {
    case .emptyTask: return "delegate task is empty"
    case .malformedFindings(let detail):
      return "Sub-agent returned malformed findings: \(detail)"
    }
  }
}
