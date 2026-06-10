import Foundation

public enum HeadlessModelMode: String, Codable, Equatable, Sendable {
  case auto
  case fixture
  case mlx
}

public enum HeadlessCompassError: LocalizedError, Equatable {
  case fixtureRequired
  case fixtureDecodeFailed(String)
  case fixtureExhausted
  case modelMissing(String)
  case missingTool(String)
  case invalidBrief(String)
  case noImmediateWork

  public var errorDescription: String? {
    switch self {
    case .fixtureRequired:
      return "Fixture mode requires --fixture <jsonl>."
    case .fixtureDecodeFailed(let detail):
      return detail
    case .fixtureExhausted:
      return "Fixture output exhausted before the agent submitted a phase result."
    case .modelMissing(let detail):
      return detail
    case .missingTool(let name):
      return "Required host tool is missing: \(name)"
    case .invalidBrief(let detail):
      return detail
    case .noImmediateWork:
      return "Plan did not select immediate work."
    }
  }
}

public struct HeadlessRunOptions: Equatable, Sendable {
  public var repoURL: URL
  public var brief: String
  public var mode: HeadlessModelMode
  public var fixtureURL: URL?
  public var promptLogDirectory: URL?
  public var maxIterations: Int
  public var runDevelop: Bool
  public var runCritic: Bool

  public init(
    repoURL: URL,
    brief: String,
    mode: HeadlessModelMode = .auto,
    fixtureURL: URL? = nil,
    promptLogDirectory: URL? = nil,
    maxIterations: Int = 24,
    runDevelop: Bool = true,
    runCritic: Bool = false
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.brief = brief
    self.mode = mode
    self.fixtureURL = fixtureURL?.standardizedFileURL
    self.promptLogDirectory = promptLogDirectory?.standardizedFileURL
    self.maxIterations = max(1, maxIterations)
    self.runDevelop = runDevelop
    self.runCritic = runCritic
  }
}

public struct HeadlessVerifyOptions: Equatable, Sendable {
  public var repoURL: URL
  public var command: String?
  public var timeoutSeconds: TimeInterval

  public init(
    repoURL: URL,
    command: String? = nil,
    timeoutSeconds: TimeInterval = 600
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.command = command
    self.timeoutSeconds = timeoutSeconds
  }
}

public struct HeadlessCompassRunner: Sendable {
  public init() {}

  @discardableResult
  public func doctor(
    repoURL: URL,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async -> Bool {
    let repoURL = repoURL.standardizedFileURL
    let workspace = CompassWorkspace(repoURL: repoURL)
    let modelReady = LocalModelCatalog.isBlessedModelReady()
    let toolchain = await HostToolchainPreflight.snapshot()

    onEvent(
      HeadlessCompassEvent(
        kind: "doctor",
        status: "completed",
        message: "CompassCLI doctor completed.",
        metadata: [
          "repo": repoURL.path,
          "compass": workspace.compassURL.path,
          "model": LocalModelCatalog.blessedModelID,
          "modelReady": modelReady ? "true" : "false",
          "modelDirectory": LocalModelCatalog.blessedModelDirectory.path,
        ]
      )
    )
    for tool in toolchain.tools {
      var metadata = ["tool": tool.name]
      if let path = tool.path {
        metadata["path"] = path
      }
      if let version = tool.version {
        metadata["version"] = version
      }
      onEvent(
        HeadlessCompassEvent(
          kind: "toolchain",
          level: tool.isAvailable ? "success" : "warning",
          status: tool.isAvailable ? "ready" : "missing",
          message: tool.isAvailable ? "\(tool.name) ready." : "\(tool.name) missing.",
          metadata: metadata
        )
      )
    }
    if !modelReady {
      onEvent(
        HeadlessCompassEvent(
          kind: "model_readiness",
          level: "warning",
          status: "missing",
          message: "Blessed MLX model is not ready.",
          metadata: ["model": LocalModelCatalog.blessedModelID]
        )
      )
    }
    return modelReady && toolchain.isTypeScriptReady
  }

  public func scaffoldTypeScript(
    at url: URL,
    name: String?,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) throws {
    let url = url.standardizedFileURL
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let projectName = name ?? url.lastPathComponent
    try TypeScriptProjectScaffold.write(
      to: url,
      options: TypeScriptProjectScaffold.Options(projectName: projectName)
    )
    let workspace = CompassWorkspace(repoURL: url)
    try workspace.initialize()
    try ForgeProfileService.writeRecord(
      ForgeProfileRecord(
        profile: .typeScriptPnpmVite,
        version: ForgeProfileRecord.currentVersion
      ),
      workspace: workspace
    )
    onEvent(
      HeadlessCompassEvent(
        kind: "scaffold",
        level: "success",
        status: "completed",
        message: "TypeScript project scaffolded.",
        metadata: ["path": url.path, "name": projectName]
      )
    )
  }

  @discardableResult
  public func verify(
    options: HeadlessVerifyOptions,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async throws -> Bool {
    let workspace = CompassWorkspace(repoURL: options.repoURL)
    try workspace.initialize()
    let state = try workspace.readState()
    let command = options.command?.trimmingCharacters(in: .whitespacesAndNewlines)
    let verifyCommand =
      command?.isEmpty == false
      ? command!
      : state.immediate?.verify.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        ?? "pnpm verify"
    return try await runVerifyCommand(
      verifyCommand,
      repoURL: options.repoURL,
      timeoutSeconds: options.timeoutSeconds,
      onEvent: onEvent
    ).exitCode == 0
  }

  @discardableResult
  public func run(
    options: HeadlessRunOptions,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> Bool {
    let repoURL = options.repoURL.standardizedFileURL
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()
    let sessionNumber = workspace.maxSessionNumber() + 1
    var session = SessionRecord.started(sessionNumber)
    session.beforeSha = await gitCurrentSHA(repoURL: repoURL)
    session.recordExecutionEnvironmentSnapshot(
      SessionExecutionEnvironmentSnapshot(
        phase: "CLI",
        launchPlan: .host(fallbackReason: "CompassCLI uses host execution in v1.")
      )
    )
    try persist(session: session, workspace: workspace)

    let mode = resolveMode(options.mode)
    let runtime = try makeRuntime(
      mode: mode,
      fixtureURL: options.fixtureURL,
      promptLogDirectory: options.promptLogDirectory,
      onEvent: onEvent
    )
    let settings = AgentRuntimeSettings.defaultFromEnvironment()
    let forgeProfile =
      (try? ForgeProfileService.detectAndPersist(repoURL: repoURL, workspace: workspace))
      ?? .generatedProjectDefault

    let brief = options.brief.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !brief.isEmpty else {
      throw HeadlessCompassError.invalidBrief("Brief cannot be empty.")
    }
    try workspace.writeVision(brief)

    onEvent(
      HeadlessCompassEvent(
        kind: "session_start",
        status: "running",
        message: "Headless Compass session #\(sessionNumber) started.",
        metadata: ["repo": repoURL.path, "mode": mode.rawValue]
      )
    )

    do {
      _ = try? await refreshCodemap(workspace: workspace, settings: settings, onEvent: onEvent)
      let plan = try await runPlan(
        workspace: workspace,
        settings: settings,
        runtime: runtime,
        forgeProfile: forgeProfile,
        sessionNumber: sessionNumber,
        maxIterations: options.maxIterations,
        onEvent: onEvent
      )
      try workspace.applyLessonEdits(plan.lessonEdits)
      let plannedState = try workspace.readState().applying(proposal: plan.state)
      try workspace.writeState(plannedState)
      session.plan = plannedState.immediate?.plan
      session.verify = plannedState.immediate?.verify
      session.status = .awaitingApproval
      try persist(session: session, workspace: workspace)

      guard options.runDevelop, let immediate = plannedState.immediate else {
        session.status = .succeeded
        session.endedAt = Date().timeIntervalSince1970 * 1000
        try persist(session: session, workspace: workspace)
        onEvent(
          HeadlessCompassEvent(
            kind: "session_end",
            level: "success",
            status: "completed",
            message: "Plan completed without Develop.",
            metadata: ["session": "\(sessionNumber)"]
          )
        )
        return true
      }

      session.status = .developing
      try persist(session: session, workspace: workspace)
      let develop = try await runDevelop(
        immediate: immediate,
        workspace: workspace,
        settings: settings,
        runtime: runtime,
        sessionNumber: sessionNumber,
        maxIterations: options.maxIterations,
        onEvent: onEvent
      )
      try workspace.applyLessonEdits(develop.lessonEdits)
      session.feedback = develop.feedback
      guard develop.status == .succeeded, develop.bypassVerify != true else {
        session.notes.append(develop.summary)
        session.status = .failed
        session.endedAt = Date().timeIntervalSince1970 * 1000
        try persist(session: session, workspace: workspace)
        onEvent(
          HeadlessCompassEvent(
            kind: "session_end",
            level: "error",
            status: "failed",
            message: "Develop did not produce a verifiable success.",
            detail: develop.summary,
            metadata: ["session": "\(sessionNumber)"]
          )
        )
        return false
      }

      let verify = try await runVerifyCommand(
        immediate.verify,
        repoURL: repoURL,
        timeoutSeconds: TimeInterval(immediate.verifyTimeoutMs ?? 600_000) / 1000,
        onEvent: onEvent
      )
      session.verifyOutput = VerifyOutput(
        command: immediate.verify,
        exitCode: Int(verify.exitCode),
        tail: tail(verify.stdout + verify.stderr, max: 4000)
      )
      _ = try? workspace.writeSessionAuditArtifact(
        session: sessionNumber,
        name: "verify.log",
        kind: "verify_output",
        contents: verify.stdout + verify.stderr,
        note: "CLI verify output."
      )

      var ok = verify.exitCode == 0
      if ok, options.runCritic {
        let critic = try await runCritic(
          immediate: immediate,
          develop: develop,
          verify: session.verifyOutput,
          beforeSha: session.beforeSha,
          workspace: workspace,
          settings: settings,
          runtime: runtime,
          forgeProfile: forgeProfile,
          sessionNumber: sessionNumber,
          maxIterations: options.maxIterations,
          onEvent: onEvent
        )
        ok = critic.verdict == .approve
        session.notes.append("Critic: \(critic.summary)")
        if !critic.feedback.isEmpty {
          session.feedback = critic.feedback
        }
      }

      session.afterSha = await gitCurrentSHA(repoURL: repoURL)
      session.status = ok ? .succeeded : .failed
      session.endedAt = Date().timeIntervalSince1970 * 1000
      try persist(session: session, workspace: workspace)
      onEvent(
        HeadlessCompassEvent(
          kind: "session_end",
          level: ok ? "success" : "error",
          status: ok ? "completed" : "failed",
          message: ok ? "Headless Compass session succeeded." : "Headless Compass session failed.",
          metadata: ["session": "\(sessionNumber)"]
        )
      )
      return ok
    } catch {
      session.status = .failed
      session.notes.append(error.localizedDescription)
      session.endedAt = Date().timeIntervalSince1970 * 1000
      try? persist(session: session, workspace: workspace)
      onEvent(
        HeadlessCompassEvent(
          kind: "fatal_error",
          level: "error",
          status: "failed",
          message: error.localizedDescription,
          metadata: ["session": "\(sessionNumber)"]
        )
      )
      throw error
    }
  }

  private func runPlan(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    forgeProfile: ForgeProfile,
    sessionNumber: Int,
    maxIterations: Int,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> PlanRunResult {
    let current = try workspace.readState()
    let prompt = try Prompts.planPrompt(
      state: current.proposal,
      completedCount: current.completed.count,
      drafts: workspace.readDrafts(),
      feedback: workspace.previousSessionFeedback(
        excluding: sessionNumber,
        activeSessions: workspace.readSessions()
      ),
      lessons: workspace.readLessons(),
      assumptions: (try? workspace.readAssumptionLedger().formattedForPrompt()) ?? "",
      vision: workspace.readVision(),
      focus: .feature,
      forgeProfile: forgeProfile,
      coverageSnapshot: ForgeProfileService.readCoverageSnapshot(from: workspace)
    )
    _ = try workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "plan-prompt.md",
      kind: "prompt",
      contents: prompt,
      note: "Plan prompt."
    )
    return try await runAgent(
      phase: .plan,
      settings: settings,
      runtime: runtime,
      userPrompt: prompt,
      schema: Prompts.planSchema,
      workspace: workspace,
      forgeProfile: forgeProfile,
      sessionNumber: sessionNumber,
      maxIterations: maxIterations,
      decode: PlanRunResult.self,
      onEvent: onEvent
    )
  }

  private func runDevelop(
    immediate: PlanNext,
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    sessionNumber: Int,
    maxIterations: Int,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> DevelopSummary {
    let prompt = Prompts.developPrompt(
      next: immediate,
      lessons: workspace.readLessons(),
      assumptions: (try? workspace.readAssumptionLedger().formattedForPrompt()) ?? "",
      vision: workspace.readVision(),
      attempt: 1,
      priorIssues: []
    )
    _ = try workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "develop-prompt.md",
      kind: "prompt",
      contents: prompt,
      note: "Develop prompt."
    )
    return try await runAgent(
      phase: .develop,
      settings: settings,
      runtime: runtime,
      userPrompt: prompt,
      schema: Prompts.developSchema,
      workspace: workspace,
      forgeProfile: ForgeProfileService.resolve(repoURL: workspace.repoURL, workspace: workspace),
      sessionNumber: sessionNumber,
      maxIterations: maxIterations,
      decode: DevelopSummary.self,
      onEvent: onEvent
    )
  }

  private func runCritic(
    immediate: PlanNext,
    develop: DevelopSummary,
    verify: VerifyOutput?,
    beforeSha: String?,
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    forgeProfile: ForgeProfile,
    sessionNumber: Int,
    maxIterations: Int,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> CriticVerdict {
    let diff = await gitDiffSinceSHA(beforeSha, repoURL: workspace.repoURL)
    let prompt = Prompts.criticPrompt(
      next: immediate,
      developSummary: develop,
      verifyCommand: immediate.verify,
      verifyExitCode: verify?.exitCode,
      verifyOutput: verify?.tail ?? "",
      gitDiff: diff,
      priorCritiques: [],
      lessons: workspace.readLessons(),
      assumptions: (try? workspace.readAssumptionLedger().formattedForPrompt()) ?? "",
      vision: workspace.readVision(),
      forgeProfile: forgeProfile,
      iteration: 1,
      maxIterations: 1
    )
    _ = try workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "critic-prompt.md",
      kind: "prompt",
      contents: prompt,
      note: "Critic prompt."
    )
    return try await runAgent(
      phase: .critic,
      settings: settings,
      runtime: runtime,
      userPrompt: prompt,
      schema: Prompts.criticSchema,
      workspace: workspace,
      forgeProfile: forgeProfile,
      sessionNumber: sessionNumber,
      maxIterations: maxIterations,
      decode: CriticVerdict.self,
      onEvent: onEvent
    )
  }

  private func runAgent<T: Decodable>(
    phase: AgentPhase,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    userPrompt: String,
    schema: String,
    workspace: CompassWorkspace,
    forgeProfile: ForgeProfile?,
    sessionNumber: Int,
    maxIterations: Int,
    decode: T.Type,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> T {
    onEvent(
      HeadlessCompassEvent(
        kind: "phase_start",
        status: "running",
        phase: phase.rawValue,
        message: "\(phase.rawValue.capitalized) started."
      )
    )
    let executor = AgentExecutor { live in
      onEvent(HeadlessCompassEvent(live: live, phase: phase))
    }
    let configuration = AgentExecutionConfiguration(
      settings: settings,
      phase: phase,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: phase,
        workingDirectoryPath: workspace.repoURL.path,
        executionEnvironment: .host,
        installedToolchainIDs: [],
        externalToolNames: []
      ),
      userPrompt: userPrompt,
      tools: ToolRegistry.tools(for: phase, settings: settings),
      modelRuntime: runtime,
      submitResultSchema: AgentToolParametersSchema(json: Data(schema.utf8)),
      workingDirectory: workspace.repoURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: AgentHostBashRunner(),
      codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
      planHistoryEntries: workspace.readSessions(includeArchived: true).compactMap(\.plan),
      assumptionsURL: workspace.assumptionsURL,
      sessionNumber: sessionNumber,
      validateSubmitResult: submitResultValidation(
        for: phase,
        workspace: workspace,
        forgeProfile: forgeProfile,
        decode: T.self
      ),
      maxIterations: maxIterations,
      wallClockTimeout: 60 * 60
    )
    let result = try await executor.run(configuration)
    _ = try workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "\(phase.rawValue)-submit-payload.json",
      kind: "phase_submit_payload",
      contents: String(decoding: result.submitResultArguments, as: UTF8.self),
      note: "\(phase.rawValue) submit payload."
    )
    onEvent(
      HeadlessCompassEvent(
        kind: "token_usage",
        status: "completed",
        phase: phase.rawValue,
        message: "Token usage recorded.",
        metadata: [
          "inputTokens": "\(result.tokenUsage.inputTokens)",
          "outputTokens": "\(result.tokenUsage.outputTokens)",
          "totalTokens": "\(result.tokenUsage.totalTokens)",
          "estimatedTokens": "\(result.tokenUsage.estimatedTokens)",
          "iterations": "\(result.iterations)",
        ]
      )
    )
    onEvent(
      HeadlessCompassEvent(
        kind: "phase_end",
        level: "success",
        status: "completed",
        phase: phase.rawValue,
        message: "\(phase.rawValue.capitalized) completed."
      )
    )
    return try JSONDecoder().decode(T.self, from: result.submitResultArguments)
  }

  private func submitResultValidation<T: Decodable>(
    for phase: AgentPhase,
    workspace: CompassWorkspace,
    forgeProfile: ForgeProfile?,
    decode: T.Type
  ) -> @Sendable (Data) throws -> Void {
    { args in
      if phase == .plan || phase == .develop {
        try workspace.validateSubmitResultLessonEdits(args)
      }
      let decoded = try JSONDecoder().decode(T.self, from: args)
      if phase == .develop, let develop = decoded as? DevelopSummary {
        try DevelopFeedbackValidator.validate(develop)
        try DevelopVerifyBypassValidator.validate(develop)
      }
      if phase == .critic, let critic = decoded as? CriticVerdict {
        try CriticFeedbackValidator.validate(critic)
      }
      guard phase == .plan, let plan = decoded as? PlanRunResult else { return }
      let current = try workspace.readState()
      let next = current.applying(proposal: plan.state)
      try PlanTransitionValidator.validate(from: current, to: next, forgeProfile: forgeProfile)
    }
  }

  private func refreshCodemap(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async throws -> CodemapRefresher.Result {
    onEvent(
      HeadlessCompassEvent(
        kind: "codemap_start",
        status: "running",
        message: "Refreshing codemap."
      )
    )
    let result = try await CodemapRefresher.make(workspace: workspace, settings: settings).refresh()
    onEvent(
      HeadlessCompassEvent(
        kind: "codemap_end",
        status: "completed",
        message: "Codemap refreshed.",
        metadata: [
          "indexed": "\(result.indexed)",
          "unchanged": "\(result.unchanged)",
          "failed": "\(result.indexerFailed)",
        ]
      )
    )
    return result
  }

  private func runVerifyCommand(
    _ command: String,
    repoURL: URL,
    timeoutSeconds: TimeInterval,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async throws -> ProcessResult {
    if HostToolchainPreflight.verifyCommandRequiresPnpm(command) {
      let toolchain = await HostToolchainPreflight.snapshot()
      if toolchain.tool(named: "pnpm")?.isAvailable != true {
        onEvent(
          HeadlessCompassEvent(
            kind: "toolchain_missing",
            level: "error",
            status: "failed",
            phase: "verify",
            message: "Cannot run verify because pnpm is missing.",
            metadata: ["command": command, "tool": "pnpm"]
          )
        )
        throw HeadlessCompassError.missingTool("pnpm")
      }
    }

    onEvent(
      HeadlessCompassEvent(
        kind: "verify_start",
        status: "running",
        phase: "verify",
        message: "Running verify command.",
        metadata: ["command": command]
      )
    )
    let started = Date()
    let result = try await ProcessRunner.runShell(
      command,
      workingDirectory: repoURL,
      timeout: timeoutSeconds,
      launchPlan: .host()
    )
    let combined = result.stdout + result.stderr
    onEvent(
      HeadlessCompassEvent(
        kind: "verify_result",
        level: result.exitCode == 0 ? "success" : "error",
        status: result.exitCode == 0 ? "completed" : "failed",
        phase: "verify",
        message: result.exitCode == 0 ? "Verify passed." : "Verify failed.",
        detail: tail(combined, max: 4000),
        metadata: [
          "command": command,
          "exitCode": "\(result.exitCode)",
          "durationMs": "\(Int(Date().timeIntervalSince(started) * 1000))",
        ]
      )
    )
    return result
  }

  private func makeRuntime(
    mode: HeadlessModelMode,
    fixtureURL: URL?,
    promptLogDirectory: URL?,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) throws -> any LocalModelGenerating {
    switch mode {
    case .fixture:
      guard let fixtureURL else { throw HeadlessCompassError.fixtureRequired }
      onEvent(
        HeadlessCompassEvent(
          kind: "model_runtime",
          status: "ready",
          message: "Using fixture model runtime.",
          metadata: ["fixture": fixtureURL.path]
        )
      )
      return try FixtureLocalModelRuntime(
        jsonlURL: fixtureURL,
        promptLogDirectory: promptLogDirectory
      )
    case .mlx, .auto:
      guard LocalModelCatalog.isBlessedModelReady() else {
        let message =
          "\(LocalModelCatalog.blessedModelID) is not downloaded. Run doctor or download the model in Compass settings."
        onEvent(
          HeadlessCompassEvent(
            kind: "model_readiness",
            level: "error",
            status: "missing",
            message: message,
            metadata: ["model": LocalModelCatalog.blessedModelID]
          )
        )
        throw HeadlessCompassError.modelMissing(message)
      }
      onEvent(
        HeadlessCompassEvent(
          kind: "model_runtime",
          status: "ready",
          message: "Using MLX model runtime.",
          metadata: ["model": LocalModelCatalog.blessedModelID]
        )
      )
      return MLXLocalModelRuntime.shared
    }
  }

  private func resolveMode(_ mode: HeadlessModelMode) -> HeadlessModelMode {
    switch mode {
    case .auto:
      return .mlx
    case .fixture, .mlx:
      return mode
    }
  }

  private func persist(session: SessionRecord, workspace: CompassWorkspace) throws {
    var records = workspace.readSessions()
    if let index = records.firstIndex(where: { $0.session == session.session }) {
      records[index] = session
    } else {
      records.append(session)
    }
    try workspace.writeSessions(records)
    try workspace.updateSessionAuditManifest(
      session: session.session,
      status: session.status,
      startedAt: session.startedAt,
      endedAt: session.endedAt
    )
  }

  private func gitCurrentSHA(repoURL: URL) async -> String? {
    guard
      let result = try? await ProcessRunner.runShell(
        "git rev-parse HEAD",
        workingDirectory: repoURL,
        timeout: 10,
        launchPlan: .host()
      ),
      result.exitCode == 0
    else {
      return nil
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
  }

  private func gitDiffSinceSHA(_ sha: String?, repoURL: URL) async -> String {
    let command: String
    if let sha, !sha.isEmpty {
      command = "git -c core.quotepath=false diff --stat && git -c core.quotepath=false diff \(sha)..HEAD"
    } else {
      command = "git -c core.quotepath=false diff --stat && git -c core.quotepath=false diff"
    }
    guard
      let result = try? await ProcessRunner.runShell(
        command,
        workingDirectory: repoURL,
        timeout: 30,
        launchPlan: .host()
      ),
      result.exitCode == 0
    else {
      return ""
    }
    return tail(result.stdout, max: 24_000)
  }
}

private func tail(_ text: String, max: Int) -> String {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard trimmed.count > max else { return trimmed }
  return String(trimmed.suffix(max))
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
