import CompassSandbox
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
  case gitCommitFailed(String)

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
    case .gitCommitFailed(let detail):
      return detail
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
  public var maxDevelopAttempts: Int
  public var maxVerifyRepairAttempts: Int
  public var runDevelop: Bool
  public var runCritic: Bool
  public var persistBriefToVision: Bool

  public init(
    repoURL: URL,
    brief: String,
    mode: HeadlessModelMode = .auto,
    fixtureURL: URL? = nil,
    promptLogDirectory: URL? = nil,
    maxIterations: Int = 24,
    maxDevelopAttempts: Int = 2,
    maxVerifyRepairAttempts: Int = 1,
    runDevelop: Bool = true,
    runCritic: Bool = false,
    persistBriefToVision: Bool = true
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.brief = brief
    self.mode = mode
    self.fixtureURL = fixtureURL?.standardizedFileURL
    self.promptLogDirectory = promptLogDirectory?.standardizedFileURL
    self.maxIterations = max(1, maxIterations)
    self.maxDevelopAttempts = max(1, maxDevelopAttempts)
    self.maxVerifyRepairAttempts = max(0, maxVerifyRepairAttempts)
    self.runDevelop = runDevelop
    self.runCritic = runCritic
    self.persistBriefToVision = persistBriefToVision
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
  package typealias BashRunnerFactory = @Sendable (URL, String) -> any AgentBashRunner

  private let bashRunnerFactory: BashRunnerFactory

  public init() {
    self.init { repoURL, label in
      AgentContainerBashRunner(repoRoot: repoURL, label: label)
    }
  }

  package init(bashRunnerFactory: @escaping BashRunnerFactory) {
    self.bashRunnerFactory = bashRunnerFactory
  }

  @discardableResult
  public func doctor(
    repoURL: URL,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async -> Bool {
    let repoURL = repoURL.standardizedFileURL
    let workspace = CompassWorkspace(repoURL: repoURL)
    let modelReady = LocalModelCatalog.isBlessedModelReady()
    let sandboxConfiguration = ContainerSandboxConfiguration()
    onEvent(
      HeadlessCompassEvent(
        kind: "container_runtime",
        status: "checking",
        message: "Checking containerized Linux runtime.",
        metadata: [
          "runtime": "containerized_linux",
          "stateRoot": sandboxConfiguration.stateRoot.path,
          "runtimeImage": sandboxConfiguration.runtimeImage,
          "initfsReference": sandboxConfiguration.initfsReference,
        ]
      )
    )
    let sandboxStatus = await ContainerizedLinuxSandbox.shared.smokeTest()

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
    var runtimeMetadata = [
      "runtime": "containerized_linux",
      "stateRoot": sandboxStatus.stateRoot.path,
      "runtimeImage": sandboxStatus.runtimeImage,
      "initfsReference": sandboxStatus.initfsReference,
      "message": sandboxStatus.message,
    ]
    if let kernelURL = sandboxStatus.kernelURL {
      runtimeMetadata["kernel"] = kernelURL.path
    }
    onEvent(
      HeadlessCompassEvent(
        kind: "container_runtime",
        level: sandboxStatus.ok ? "success" : "error",
        status: sandboxStatus.ok ? "ready" : "failed",
        message: sandboxStatus.ok
          ? "Containerized Linux runtime is ready."
          : "Containerized Linux runtime smoke test failed.",
        metadata: runtimeMetadata
      )
    )
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
    return modelReady && sandboxStatus.ok
  }

  public func scaffoldTessera(
    at url: URL,
    name: String?,
    initializeGit: Bool = false,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) throws {
    let url = url.standardizedFileURL
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let projectName = name ?? url.lastPathComponent
    try TesseraProjectScaffold.write(
      to: url,
      options: TesseraProjectScaffold.Options(projectName: projectName)
    )
    let workspace = CompassWorkspace(repoURL: url)
    try workspace.initialize()
    try ForgeProfileService.writeRecord(
      ForgeProfileRecord(
        profile: .tesseraApp,
        version: ForgeProfileRecord.currentVersion
      ),
      workspace: workspace
    )
    onEvent(
      HeadlessCompassEvent(
        kind: "scaffold",
        level: "success",
        status: "completed",
        message: "Tessera app scaffolded.",
        metadata: ["path": url.path, "name": projectName]
      )
    )

    guard initializeGit else { return }
    let result = Self.initializeScaffoldGitBaseline(at: url)
    if result.exitCode == 0 {
      onEvent(
        HeadlessCompassEvent(
          kind: "scaffold_git_baseline",
          level: "success",
          status: "completed",
          message: "Initial Git baseline committed.",
          metadata: ["path": url.path]
        )
      )
    } else {
      onEvent(
        HeadlessCompassEvent(
          kind: "scaffold_git_baseline",
          level: "warning",
          status: "failed",
          message: "Initial Git baseline was not created.",
          detail: [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        )
      )
    }
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
        ?? (ForgeProfileService.resolve(repoURL: options.repoURL, workspace: workspace)
        ?? .generatedProjectDefault).standardVerifyCommand
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
    let harnessExcludes = Self.gitHarnessExcludes(
      repoURL: repoURL,
      fixtureURL: options.fixtureURL,
      promptLogDirectory: options.promptLogDirectory
    )
    try await installLocalGitExcludes(repoURL: repoURL, paths: harnessExcludes)
    try await checkpointPendingGitChangesIfNeeded(
      repoURL: repoURL,
      excluding: harnessExcludes,
      onEvent: onEvent
    )
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
    let promptVision: String
    if options.persistBriefToVision {
      try workspace.writeVision(brief)
      try seedHeadlessBrief(brief, workspace: workspace)
      promptVision = workspace.readVision()
    } else {
      promptVision = Self.transientPromptVision(
        brief: brief,
        existingVision: workspace.readVision()
      )
    }

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
        vision: promptVision,
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

      var priorIssues: [String] = []
      var successfulDevelop: DevelopSummary?
      var ok = false
      var attempt = 1
      var verifyRepairAttemptsUsed = 0

      while attempt <= options.maxDevelopAttempts + options.maxVerifyRepairAttempts {
        session.status = .developing
        try persist(session: session, workspace: workspace)

        let develop: DevelopSummary
        do {
          develop = try await runDevelop(
            immediate: immediate,
            workspace: workspace,
            settings: settings,
            runtime: runtime,
            vision: promptVision,
            sessionNumber: sessionNumber,
            attempt: attempt,
            priorIssues: priorIssues,
            maxIterations: options.maxIterations,
            onEvent: onEvent
          )
        } catch let error as AgentExecutionError where error.isAgentBudgetExhaustion {
          let issue = developBudgetExhaustionIssue(attempt: attempt, error: error)
          session.notes.append(issue)
          if attempt < options.maxDevelopAttempts {
            priorIssues = [issue]
            try persist(session: session, workspace: workspace)
            emitDevelopRetry(
              attempt: attempt,
              maxAttempts: options.maxDevelopAttempts,
              issue: issue,
              retryKind: "budget_exhaustion",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }

          session.status = .failed
          session.endedAt = Date().timeIntervalSince1970 * 1000
          try persist(session: session, workspace: workspace)
          onEvent(
            HeadlessCompassEvent(
              kind: "session_end",
              level: "error",
              status: "failed",
              message: "Develop exhausted its execution budget.",
              detail: issue,
              metadata: ["session": "\(sessionNumber)"]
            )
          )
          return false
        }
        try workspace.applyLessonEdits(develop.lessonEdits)
        session.feedback = develop.feedback

        guard develop.status == .succeeded, develop.bypassVerify != true else {
          let issue = developFailureIssue(develop)
          session.notes.append(issue)
          if attempt < options.maxDevelopAttempts {
            priorIssues = [issue]
            try persist(session: session, workspace: workspace)
            emitDevelopRetry(
              attempt: attempt,
              maxAttempts: options.maxDevelopAttempts,
              issue: issue,
              retryKind: "develop_postcheck",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }

          session.status = .failed
          session.endedAt = Date().timeIntervalSince1970 * 1000
          try persist(session: session, workspace: workspace)
          onEvent(
            HeadlessCompassEvent(
              kind: "session_end",
              level: "error",
              status: "failed",
              message: "Develop did not produce a verifiable success.",
              detail: issue,
              metadata: ["session": "\(sessionNumber)"]
            )
          )
          return false
        }

        if let changed = await gitHasChangesSince(session.beforeSha, repoURL: repoURL), !changed {
          let issue = noDevelopChangesIssue(develop)
          session.notes.append(issue)
          if attempt < options.maxDevelopAttempts {
            priorIssues = [issue]
            try persist(session: session, workspace: workspace)
            emitDevelopRetry(
              attempt: attempt,
              maxAttempts: options.maxDevelopAttempts,
              issue: issue,
              retryKind: "no_git_changes",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }

          session.status = .failed
          session.endedAt = Date().timeIntervalSince1970 * 1000
          try persist(session: session, workspace: workspace)
          onEvent(
            HeadlessCompassEvent(
              kind: "session_end",
              level: "error",
              status: "failed",
              message: "Develop reported success without changing the repository.",
              detail: issue,
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
        let verifyTail = tail(verify.stdout + verify.stderr, max: 4000)
        session.verifyOutput = VerifyOutput(
          command: immediate.verify,
          exitCode: Int(verify.exitCode),
          tail: verifyTail
        )
        writeVerifyAuditArtifacts(
          workspace: workspace,
          sessionNumber: sessionNumber,
          attempt: attempt,
          contents: verify.stdout + verify.stderr
        )
        try persist(session: session, workspace: workspace)

        if verify.exitCode == 0 {
          successfulDevelop = develop
          ok = true
          break
        }

        let issue = verifyFailureIssue(command: immediate.verify, result: verify)
        session.notes.append("Verify attempt \(attempt) failed.")
        let canUseDevelopAttempt = attempt < options.maxDevelopAttempts
        let canUseVerifyRepairAttempt =
          !canUseDevelopAttempt && verifyRepairAttemptsUsed < options.maxVerifyRepairAttempts
        if canUseDevelopAttempt || canUseVerifyRepairAttempt {
          if canUseVerifyRepairAttempt {
            verifyRepairAttemptsUsed += 1
          }
          priorIssues = [issue]
          try persist(session: session, workspace: workspace)
          emitDevelopRetry(
            attempt: attempt,
            maxAttempts: options.maxDevelopAttempts + options.maxVerifyRepairAttempts,
            issue: issue,
            retryKind: canUseVerifyRepairAttempt ? "verify_repair" : "verify_failure",
            onEvent: onEvent
          )
          attempt += 1
          continue
        }
        break
      }

      if ok, options.runCritic, let successfulDevelop {
        let critic = try await runCritic(
          immediate: immediate,
          develop: successfulDevelop,
          verify: session.verifyOutput,
          beforeSha: session.beforeSha,
          workspace: workspace,
          settings: settings,
          runtime: runtime,
          forgeProfile: forgeProfile,
          vision: promptVision,
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

      if ok, let successfulDevelop {
        _ = try await commitSuccessfulDevelopChangesIfNeeded(
          develop: successfulDevelop,
          repoURL: repoURL,
          excluding: harnessExcludes,
          onEvent: onEvent
        )
      }
      session.afterSha = await gitCurrentSHA(repoURL: repoURL)
      session.commits = await GitSessionCommitLog.commits(
        in: repoURL,
        from: session.beforeSha,
        to: session.afterSha
      )
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

  private func seedHeadlessBrief(_ brief: String, workspace: CompassWorkspace) throws {
    let current = try workspace.readState()
    let seeded = Self.stateBySeedingHeadlessBrief(current, brief: brief)
    guard seeded != current else { return }
    try workspace.writeState(seeded)
  }

  package static func stateBySeedingHeadlessBrief(_ state: PlanState, brief: String) -> PlanState {
    let rawSummary = Self.compactBriefSummary(brief)
    guard !rawSummary.isEmpty else { return state }

    var seeded = state
    var strategicContext = state.brief
    if strategicContext.summary.isEmpty {
      strategicContext.summary = rawSummary
    }
    if strategicContext.targetUsers.isEmpty {
      strategicContext.targetUsers = ["People using this repository's Compass workflow."]
    }
    if strategicContext.desiredOutcomes.isEmpty {
      strategicContext.desiredOutcomes = [
        "The requested brief is implemented with verified, repository-local changes."
      ]
    }
    if strategicContext.constraints.isEmpty {
      strategicContext.constraints = [
        "Preserve existing project behavior and work within the current repository."
      ]
    }
    if strategicContext.acceptanceSignals.isEmpty {
      strategicContext.acceptanceSignals = [
        "The configured verify command passes and the changes match the brief."
      ]
    }
    seeded.brief = strategicContext
    return seeded
  }

  private static func transientPromptVision(brief: String, existingVision: String) -> String {
    let existing = existingVision.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !existing.isEmpty else { return brief }
    return """
      Existing project context:
      \(existing)

      Transient run context:
      \(brief)
      """
  }

  private static func compactBriefSummary(_ brief: String, limit: Int = 280) -> String {
    let compact =
      brief
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard compact.count > limit else { return compact }
    guard limit > 3 else { return String(compact.prefix(limit)) }
    return compact.prefix(limit - 3).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  private func runPlan(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    forgeProfile: ForgeProfile,
    vision: String,
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
      vision: vision,
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
      promptLogLabelPrefix: "plan",
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
    vision: String,
    sessionNumber: Int,
    attempt: Int,
    priorIssues: [String],
    maxIterations: Int,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> DevelopSummary {
    let prompt = Prompts.developPrompt(
      next: immediate,
      lessons: workspace.readLessons(),
      assumptions: (try? workspace.readAssumptionLedger().formattedForPrompt()) ?? "",
      vision: vision,
      attempt: attempt,
      priorIssues: priorIssues
    )
    _ = try workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: attempt == 1 ? "develop-prompt.md" : "develop-attempt-\(attempt)-prompt.md",
      kind: "prompt",
      contents: prompt,
      note: "Develop prompt for attempt \(attempt)."
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
      promptLogLabelPrefix: "develop-attempt-\(attempt)",
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
    vision: String,
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
      vision: vision,
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
      promptLogLabelPrefix: "critic",
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
    promptLogLabelPrefix: String?,
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
        executionEnvironment: .containerizedLinux,
        externalToolNames: []
      ),
      userPrompt: userPrompt,
      tools: ToolRegistry.tools(for: phase, settings: settings),
      modelRuntime: runtime,
      submitResultSchema: AgentToolParametersSchema(json: Data(schema.utf8)),
      workingDirectory: workspace.repoURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: bashRunnerFactory(workspace.repoURL, phase.rawValue),
      codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
      planHistoryEntries: workspace.readSessions(includeArchived: true).compactMap(\.plan),
      assumptionsURL: workspace.assumptionsURL,
      sessionNumber: sessionNumber,
      promptLogLabelPrefix: promptLogLabelPrefix,
      validateSubmitResult: submitResultValidation(
        for: phase,
        workspace: workspace,
        forgeProfile: forgeProfile,
        decode: T.self
      ),
      maxIterations: maxIterations,
      wallClockTimeout: 60 * 60
    )
    let result: AgentExecutionResult
    do {
      result = try await executor.run(configuration)
    } catch {
      onEvent(
        HeadlessCompassEvent(
          kind: "phase_end",
          level: "error",
          status: "failed",
          phase: phase.rawValue,
          message: "\(phase.rawValue.capitalized) failed.",
          detail: error.localizedDescription,
          metadata: ["maxIterations": "\(maxIterations)"]
        )
      )
      throw error
    }
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
      try PlanTransitionValidator.validate(
        from: current,
        to: next,
        forgeProfile: forgeProfile,
        repoURL: workspace.repoURL
      )
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
    let workspace = CompassWorkspace(repoURL: repoURL)
    let forgeProfile = ForgeProfileService.resolve(repoURL: repoURL, workspace: workspace)
    let useEmbeddedTessera = CompassEngineProcess.shouldUseEmbeddedTessera(
      command: command,
      forgeProfile: forgeProfile
    )
    onEvent(
      HeadlessCompassEvent(
        kind: "verify_start",
        status: "running",
        phase: "verify",
        message: useEmbeddedTessera
          ? "Running Tessera verify with embedded Compass engine."
          : "Running verify command in containerized Linux runtime.",
        metadata: [
          "command": command,
          "runtime": useEmbeddedTessera ? "embedded_tessera" : "containerized_linux",
        ]
      )
    )
    let started = Date()
    let result: ProcessResult
    if useEmbeddedTessera {
      result = try await CompassEngineProcess.verifyProject(root: repoURL)
    } else {
      result = try await bashRunnerFactory(repoURL, "verify").run(
        command: command,
        workingDirectory: repoURL,
        timeout: timeoutSeconds
      )
    }
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

  private func writeVerifyAuditArtifacts(
    workspace: CompassWorkspace,
    sessionNumber: Int,
    attempt: Int,
    contents: String
  ) {
    _ = try? workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "verify.log",
      kind: "verify_output",
      contents: contents,
      note: "Latest CLI verify output."
    )
    _ = try? workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "verify-attempt-\(attempt).log",
      kind: "verify_output",
      contents: contents,
      note: "CLI verify output for attempt \(attempt)."
    )
  }

  private func emitDevelopRetry(
    attempt: Int,
    maxAttempts: Int,
    issue: String,
    retryKind: String,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) {
    onEvent(
      HeadlessCompassEvent(
        kind: "develop_retry",
        level: "warning",
        status: "running",
        phase: "develop",
        message: "Develop attempt \(attempt) failed post-checks; retrying with failure context.",
        detail: tail(issue, max: 4000),
        metadata: [
          "attempt": "\(attempt)",
          "nextAttempt": "\(attempt + 1)",
          "maxAttempts": "\(maxAttempts)",
          "retryKind": retryKind,
        ]
      )
    )
  }

  private func developFailureIssue(_ develop: DevelopSummary) -> String {
    let summary = develop.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let feedback = develop.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = [summary, feedback].filter { !$0.isEmpty }.joined(separator: "\n\n")
    return """
      Develop did not produce a verifiable success.

      Status: \(develop.status.rawValue)
      bypassVerify: \(develop.bypassVerify == true ? "true" : "false")

      \(detail.isEmpty ? "_(no summary or feedback)_" : detail)
      """
  }

  private func developBudgetExhaustionIssue(
    attempt: Int,
    error: AgentExecutionError
  ) -> String {
    """
    Develop attempt \(attempt) ended without a phase submit envelope: \(error.localizedDescription).

    The next attempt should make a smaller, more direct change. Reuse already discovered file paths and tool results, avoid repeating failed path guesses, and submit status=failed with concise feedback if the requested plan is not achievable within the iteration budget.
    """
  }

  private func noDevelopChangesIssue(_ develop: DevelopSummary) -> String {
    let summary = develop.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let feedback = develop.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    return """
      Develop submitted status=succeeded, but Compass did not detect any Git-visible file changes or commits.

      A successful Develop pass must modify, create, delete, or commit files that implement the handoff before verification can prove anything. Do not submit success after only failed tool calls.

      Reported summary:
      \(summary.isEmpty ? "_(empty)_" : summary)

      Reported feedback:
      \(feedback.isEmpty ? "_(empty)_" : feedback)
      """
  }

  private func verifyFailureIssue(command: String, result: ProcessResult) -> String {
    let combined = tail(result.stdout + result.stderr, max: 4000)
    let insight = VerifyFailureInsight(
      detail: combined,
      metadata: "command=\(command) exitCode=\(result.exitCode)"
    )
    return """
      Verify failed for `\(command)` with exit code \(result.exitCode).

      \(insight.inspectDetail)

      Repair guidance: \(insight.repairDetail)

      Verify output:
      \(combined.isEmpty ? "_(no output)_" : combined)
      """
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
      let runtime: any LocalModelGenerating = MLXLocalModelRuntime.shared
      guard let promptLogDirectory else { return runtime }
      return PromptLoggingLocalModelRuntime(
        base: runtime,
        promptLogDirectory: promptLogDirectory
      )
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

  private static func initializeScaffoldGitBaseline(at repoURL: URL) -> ProcessResult {
    runShellSync(
      """
      set -e
      if [ -e .git ]; then
        :
      elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "not creating scaffold baseline inside an existing parent Git worktree" >&2
        exit 3
      else
        git init
      fi

      if git rev-parse --verify HEAD >/dev/null 2>&1; then
        exit 0
      fi

      git add .
      git -c user.name='Compass Scaffold' \
        -c user.email='compass-scaffold@localhost' \
        commit -m 'Initial Compass scaffold'
      """,
      workingDirectory: repoURL
    )
  }

  private static func runShellSync(_ command: String, workingDirectory: URL) -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.currentDirectoryURL = workingDirectory

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

    do {
      try process.run()
      process.waitUntilExit()
      let stdout =
        String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? ""
      let stderr =
        String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? ""
      return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    } catch {
      return ProcessResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
    }
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

  private func commitSuccessfulDevelopChangesIfNeeded(
    develop: DevelopSummary,
    repoURL: URL,
    excluding excludedPaths: [String],
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async throws -> String? {
    guard await gitIsInsideWorkTree(repoURL: repoURL) else { return nil }
    let status = try await gitStatus(repoURL: repoURL, excluding: excludedPaths)
    guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    onEvent(
      HeadlessCompassEvent(
        kind: "host_commit_start",
        status: "running",
        phase: "commit",
        message: "Committing verified Develop changes on the host.",
        detail: status
      )
    )

    let add = try await ProcessRunner.runEnv(
      "git",
      Self.gitAddArguments(forStatus: status),
      workingDirectory: repoURL,
      timeout: 30
    )
    guard add.exitCode == 0 else {
      let detail = tail(add.stderr + add.stdout, max: 2000)
      onEvent(
        HeadlessCompassEvent(
          kind: "host_commit_result",
          level: "error",
          status: "failed",
          phase: "commit",
          message: "Failed to stage verified Develop changes.",
          detail: detail
        )
      )
      throw HeadlessCompassError.gitCommitFailed("Failed to stage verified changes: \(detail)")
    }

    var commitArguments = [
      "-c", "user.name=Compass Agent",
      "-c", "user.email=compass-agent@localhost",
      "commit", "-m", Self.commitSubject(for: develop),
    ]
    let body = develop.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    if !body.isEmpty {
      commitArguments += ["-m", body]
    }
    let commit = try await ProcessRunner.runEnv(
      "git",
      commitArguments,
      workingDirectory: repoURL,
      timeout: 60
    )
    guard commit.exitCode == 0 else {
      let detail = tail(commit.stderr + commit.stdout, max: 2000)
      onEvent(
        HeadlessCompassEvent(
          kind: "host_commit_result",
          level: "error",
          status: "failed",
          phase: "commit",
          message: "Failed to commit verified Develop changes.",
          detail: detail
        )
      )
      throw HeadlessCompassError.gitCommitFailed("Failed to commit verified changes: \(detail)")
    }

    let sha = await gitCurrentSHA(repoURL: repoURL)
    onEvent(
      HeadlessCompassEvent(
        kind: "host_commit_result",
        level: "success",
        status: "completed",
        phase: "commit",
        message: "Verified Develop changes committed on the host.",
        detail: tail(commit.stdout + commit.stderr, max: 2000),
        metadata: [
          "sha": sha ?? "",
          "subject": Self.commitSubject(for: develop),
        ]
      )
    )
    return sha
  }

  private func checkpointPendingGitChangesIfNeeded(
    repoURL: URL,
    excluding excludedPaths: [String],
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async throws {
    guard await gitIsInsideWorkTree(repoURL: repoURL) else { return }
    let status = try await gitStatus(repoURL: repoURL, excluding: excludedPaths)
    guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    onEvent(
      HeadlessCompassEvent(
        kind: "preflight_commit_start",
        status: "running",
        phase: "preflight",
        message: "Checkpointing pending Git changes before Compass run.",
        detail: status
      )
    )

    let add = try await ProcessRunner.runEnv(
      "git",
      Self.gitAddArguments(forStatus: status),
      workingDirectory: repoURL,
      timeout: 30
    )
    guard add.exitCode == 0 else {
      let detail = tail(add.stderr + add.stdout, max: 2000)
      onEvent(
        HeadlessCompassEvent(
          kind: "preflight_commit_result",
          level: "error",
          status: "failed",
          phase: "preflight",
          message: "Failed to stage pre-existing Git changes.",
          detail: detail
        )
      )
      throw HeadlessCompassError.gitCommitFailed(
        "Failed to stage pre-existing Git changes: \(detail)"
      )
    }

    let commit = try await ProcessRunner.runEnv(
      "git",
      [
        "-c", "user.name=Compass Preflight",
        "-c", "user.email=compass-preflight@localhost",
        "commit", "-m", "Checkpoint pending changes before Compass run",
      ],
      workingDirectory: repoURL,
      timeout: 60
    )
    guard commit.exitCode == 0 else {
      let detail = tail(commit.stderr + commit.stdout, max: 2000)
      onEvent(
        HeadlessCompassEvent(
          kind: "preflight_commit_result",
          level: "error",
          status: "failed",
          phase: "preflight",
          message: "Failed to commit pre-existing Git changes.",
          detail: detail
        )
      )
      throw HeadlessCompassError.gitCommitFailed(
        "Failed to commit pre-existing Git changes: \(detail)"
      )
    }

    let sha = await gitCurrentSHA(repoURL: repoURL)
    onEvent(
      HeadlessCompassEvent(
        kind: "preflight_commit_result",
        level: "success",
        status: "completed",
        phase: "preflight",
        message: "Pending Git changes checkpointed before Compass run.",
        detail: tail(commit.stdout + commit.stderr, max: 2000),
        metadata: ["sha": sha ?? ""]
      )
    )
  }

  private func installLocalGitExcludes(repoURL: URL, paths: [String]) async throws {
    let paths = Self.uniqueNonEmptyPaths(paths)
    guard !paths.isEmpty, await gitIsInsideWorkTree(repoURL: repoURL) else { return }
    let result = try await ProcessRunner.runEnv(
      "git",
      ["rev-parse", "--git-dir"],
      workingDirectory: repoURL,
      timeout: 10
    )
    guard result.exitCode == 0 else {
      let detail = tail(result.stderr + result.stdout, max: 2000)
      throw HeadlessCompassError.gitCommitFailed("Failed to locate Git directory: \(detail)")
    }
    let rawGitDir = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawGitDir.isEmpty else { return }

    let gitDirURL =
      rawGitDir.hasPrefix("/")
      ? URL(fileURLWithPath: rawGitDir)
      : repoURL.appending(path: rawGitDir, directoryHint: .isDirectory)
    let excludeURL = gitDirURL.appending(path: "info/exclude")
    try FileManager.default.createDirectory(
      at: excludeURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing = (try? String(contentsOf: excludeURL, encoding: .utf8)) ?? ""
    var linesToAdd: [String] = []
    for path in paths {
      for pattern in Self.gitInfoExcludePatterns(for: path)
      where !existing.split(whereSeparator: \.isNewline).contains(Substring(pattern)) {
        linesToAdd.append(pattern)
      }
    }
    guard !linesToAdd.isEmpty else { return }
    let prefix = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
    let header = existing.contains("# Compass CLI harness artifacts") ? "" : "# Compass CLI harness artifacts\n"
    let updated = existing + prefix + header + linesToAdd.joined(separator: "\n") + "\n"
    try updated.write(to: excludeURL, atomically: true, encoding: .utf8)
  }

  private func gitIsInsideWorkTree(repoURL: URL) async -> Bool {
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "--is-inside-work-tree"],
        workingDirectory: repoURL,
        timeout: 10
      )
    else {
      return false
    }
    return result.exitCode == 0
  }

  private func gitStatus(repoURL: URL, excluding excludedPaths: [String] = []) async throws -> String {
    let result = try await ProcessRunner.runEnv(
      "git",
      Self.gitStatusArguments(excluding: excludedPaths),
      workingDirectory: repoURL,
      timeout: 30
    )
    guard result.exitCode == 0 else {
      let detail = tail(result.stderr + result.stdout, max: 2000)
      throw HeadlessCompassError.gitCommitFailed("Failed to inspect Git status: \(detail)")
    }
    return result.stdout.trimmingCharacters(in: .newlines)
  }

  private static func gitHarnessExcludes(
    repoURL: URL,
    fixtureURL: URL?,
    promptLogDirectory: URL?
  ) -> [String] {
    uniqueNonEmptyPaths(
      [fixtureURL, promptLogDirectory]
        .compactMap { $0.flatMap { relativeGitPath(for: $0, repoURL: repoURL) } }
    )
  }

  private static func relativeGitPath(for url: URL, repoURL: URL) -> String? {
    let rootPath = repoURL.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path != rootPath else { return nil }
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard path.hasPrefix(rootPrefix) else { return nil }
    let relative = String(path.dropFirst(rootPrefix.count))
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return relative.isEmpty ? nil : relative
  }

  private static func gitStatusArguments(excluding excludedPaths: [String]) -> [String] {
    var arguments = ["status", "--porcelain", "--untracked-files=all"]
    let pathspecs = gitExcludePathspecs(for: excludedPaths)
    if !pathspecs.isEmpty {
      arguments += ["--", "."] + pathspecs
    }
    return arguments
  }

  private static func gitAddArguments(forStatus status: String) -> [String] {
    ["add", "-A", "--"] + gitStatusPaths(status)
  }

  private static func gitStatusPaths(_ status: String) -> [String] {
    status
      .split(whereSeparator: \.isNewline)
      .compactMap { line -> String? in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        let rawPath = fields.count > 1 ? String(fields.last ?? "") : String(line.dropFirst(3))
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
      }
  }

  private static func gitExcludePathspecs(for paths: [String]) -> [String] {
    uniqueNonEmptyPaths(paths).flatMap { path in
      [":(exclude)\(path)", ":(exclude)\(path)/**"]
    }
  }

  private static func gitInfoExcludePatterns(for path: String) -> [String] {
    let escaped = path
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: " ", with: "\\ ")
    return ["/\(escaped)", "/\(escaped)/**"]
  }

  private static func uniqueNonEmptyPaths(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.compactMap { raw in
      let path = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
      guard !path.isEmpty, seen.insert(path).inserted else { return nil }
      return path
    }
  }

  private static func commitSubject(for develop: DevelopSummary) -> String {
    boundedFirstLine(develop.summary, limit: 72)
  }

  private static func boundedFirstLine(_ text: String, limit: Int) -> String {
    let firstLine =
      text
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let fallback = firstLine.isEmpty ? "Develop iteration" : firstLine
    guard fallback.count > limit else { return fallback }
    return fallback.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func gitHasChangesSince(_ beforeSha: String?, repoURL: URL) async -> Bool? {
    guard let beforeSha, !beforeSha.isEmpty else { return nil }
    let command = """
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        exit 2
      fi
      current="$(git rev-parse HEAD 2>/dev/null || true)"
      if [ "$current" != "\(beforeSha)" ]; then
        exit 0
      fi
      if ! git diff --quiet || ! git diff --cached --quiet; then
        exit 0
      fi
      if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
        exit 0
      fi
      exit 1
      """
    guard
      let result = try? await ProcessRunner.runShell(
        command,
        workingDirectory: repoURL,
        timeout: 10,
        launchPlan: .host()
      )
    else {
      return nil
    }
    switch result.exitCode {
    case 0: return true
    case 1: return false
    default: return nil
    }
  }

  private func gitChangedPathsSince(_ beforeSha: String?, repoURL: URL) async -> [String]? {
    let command: String
    if let beforeSha, !beforeSha.isEmpty {
      command = """
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          exit 2
        fi
        git -c core.quotepath=false diff --name-only \(beforeSha)..HEAD
        git -c core.quotepath=false diff --name-only
        git -c core.quotepath=false diff --cached --name-only
        git -c core.quotepath=false ls-files --others --exclude-standard
        """
    } else {
      command = """
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          exit 2
        fi
        git -c core.quotepath=false diff --name-only
        git -c core.quotepath=false diff --cached --name-only
        git -c core.quotepath=false ls-files --others --exclude-standard
        """
    }

    guard
      let result = try? await ProcessRunner.runShell(
        command,
        workingDirectory: repoURL,
        timeout: 10,
        launchPlan: .host()
      ),
      result.exitCode == 0
    else {
      return nil
    }

    let paths = Set(
      result.stdout
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
    return Array(paths).sorted()
  }

  private func gitDiffSinceSHA(_ sha: String?, repoURL: URL) async -> String {
    let command: String
    if let sha, !sha.isEmpty {
      command =
        "git -c core.quotepath=false diff --stat && git -c core.quotepath=false diff \(sha)..HEAD"
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

extension String {
  fileprivate var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
