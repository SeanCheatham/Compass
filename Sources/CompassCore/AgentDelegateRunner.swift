import Foundation

/// Spawn a focused sub-agent that runs inside the same working
/// directory / filesystem / bash runner as the parent and returns a
/// structured findings payload. The sub-agent inherits the parent's model
/// settings and working context.
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
  /// which is wrong for VM routes — top-level callers should
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
  /// Tighter budget for `repair` profile sub-agents.
  public static let maxRepairSubAgentIterations = 48
  /// Wall-clock cap for a single sub-agent invocation.
  public static let maxSubAgentWallClock: TimeInterval = 15 * 60
  /// Tighter wall clock for `repair` profile sub-agents.
  public static let maxRepairSubAgentWallClock: TimeInterval = 10 * 60

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

    let normalizedProfile = Self.normalizedProfile(profile)
    let effectiveTools = Self.filterTools(
      parentTools: parentTools,
      requested: toolNames ?? Self.toolNames(forProfile: normalizedProfile)
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
    let iterationCap =
      normalizedProfile == "repair"
      ? Self.maxRepairSubAgentIterations
      : Self.maxSubAgentIterations
    let wallClockCap =
      normalizedProfile == "repair"
      ? Self.maxRepairSubAgentWallClock
      : Self.maxSubAgentWallClock
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
      maxIterations: min(parentMaxIterations, iterationCap),
      wallClockTimeout: min(parentWallClockTimeout, wallClockCap)
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
    return payload.formattedToolResult()
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

  public static func normalizedProfile(_ rawProfile: String?) -> String? {
    guard let profile = rawProfile?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      !profile.isEmpty
    else { return nil }
    return profile
  }

  public static func toolNames(forProfile rawProfile: String?) -> [String]? {
    guard let profile = normalizedProfile(rawProfile) else { return nil }
    switch profile {
    case "explore":
      return [
        AgentReadFileTool.toolName,
        AgentLsTool.toolName,
        AgentGrepTool.toolName,
        AgentGlobTool.toolName,
        AgentOutlineTool.toolName,
        AgentFindSymbolTool.toolName,
        AgentSummaryTool.toolName,
        AgentListFilesTool.toolName,
        AgentImportersOfTool.toolName,
      ]
    case "verify", "test", "typecheck":
      return [
        AgentReadFileTool.toolName,
        AgentListFilesTool.toolName,
        AgentOutlineTool.toolName,
        AgentFindSymbolTool.toolName,
        AgentSummaryTool.toolName,
        AgentGrepTool.toolName,
        AgentBashTool.toolName,
      ]
    case "repair":
      // Full parent tool set minus `delegate` (via filterTools nil path).
      return nil
    default:
      return nil
    }
  }
}

public struct SubAgentResult: Decodable, Equatable, Sendable {
  public let findings: String
  public let filesRead: [String]
  public let commandsRun: [String]
  public let openQuestions: [String]

  public enum CodingKeys: String, CodingKey {
    case findings
    case filesRead
    case filesReadSnake = "files_read"
    case commandsRun
    case commandsRunSnake = "commands_run"
    case openQuestions
    case openQuestionsSnake = "open_questions"
  }

  public init(
    findings: String,
    filesRead: [String] = [],
    commandsRun: [String] = [],
    openQuestions: [String] = []
  ) {
    self.findings = findings
    self.filesRead = filesRead
    self.commandsRun = commandsRun
    self.openQuestions = openQuestions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    findings = try container.decode(String.self, forKey: .findings)
    filesRead = try Self.decodeStringArray(
      from: container,
      preferred: .filesRead,
      alias: .filesReadSnake
    )
    commandsRun = try Self.decodeStringArray(
      from: container,
      preferred: .commandsRun,
      alias: .commandsRunSnake
    )
    openQuestions = try Self.decodeStringArray(
      from: container,
      preferred: .openQuestions,
      alias: .openQuestionsSnake
    )
  }

  private static func decodeStringArray(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferred: CodingKeys,
    alias: CodingKeys
  ) throws -> [String] {
    if let values = try container.decodeIfPresent([String].self, forKey: preferred) {
      return values
    }
    if let values = try container.decodeIfPresent([String].self, forKey: alias) {
      return values
    }
    return []
  }

  /// Format for the parent tool observation: findings first, then optional
  /// grounded evidence sections the parent can cite without re-reading logs.
  public func formattedToolResult() -> String {
    let trimmedFindings = findings.trimmingCharacters(in: .whitespacesAndNewlines)
    var sections: [String] = [
      trimmedFindings.isEmpty ? "(sub-agent returned no findings)" : trimmedFindings
    ]
    let cleanedFiles = filesRead.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    if !cleanedFiles.isEmpty {
      sections.append("[filesRead]\n" + cleanedFiles.joined(separator: "\n"))
    }
    let cleanedCommands = commandsRun.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    if !cleanedCommands.isEmpty {
      sections.append("[commandsRun]\n" + cleanedCommands.joined(separator: "\n"))
    }
    let cleanedQuestions = openQuestions.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    if !cleanedQuestions.isEmpty {
      sections.append("[openQuestions]\n" + cleanedQuestions.joined(separator: "\n"))
    }
    return sections.joined(separator: "\n\n")
  }
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
