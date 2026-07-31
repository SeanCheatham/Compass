import CompassSandbox
import Foundation

public enum HeadlessModelMode: String, Codable, Equatable, Sendable {
  case auto
  case fixture
  case mlx
  case cloud
}

public enum HeadlessCompassError: LocalizedError, Equatable {
  case fixtureRequired
  case fixtureDecodeFailed(String)
  case fixtureExhausted
  case modelMissing(String)
  case cloudNotConfigured(String)
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
    case .cloudNotConfigured(let detail):
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
  public var maxDevelopAttempts: Int
  public var maxVerifyRepairAttempts: Int
  public var runDevelop: Bool
  public var runCritic: Bool

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
    runCritic: Bool = false
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
  typealias BashRunnerFactory = @Sendable (URL, String) -> any AgentBashRunner

  private let bashRunnerFactory: BashRunnerFactory

  public init() {
    self.init { repoURL, label in
      AgentContainerBashRunner(repoRoot: repoURL, label: label)
    }
  }

  init(bashRunnerFactory: @escaping BashRunnerFactory) {
    self.bashRunnerFactory = bashRunnerFactory
  }

  @discardableResult
  public func doctor(
    repoURL: URL,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async -> Bool {
    let repoURL = repoURL.standardizedFileURL
    let workspace = CompassWorkspace(repoURL: repoURL)
    let settings = AgentSettingsStore().load()
    let modelReady = LocalModelCatalog.isBlessedModelReady()
    let cloudReady = settings.hasCloudCredentials
    let textReady = settings.isTextCapabilityRunnable(localModelReady: modelReady)
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
          "textProvider": settings.textProvider.rawValue,
          "cloudReady": cloudReady ? "true" : "false",
          "cloudBaseURL": settings.cloudEndpointDisplay(),
          "cloudModel": settings.trimmedModel,
          "localAssistModel": LocalModelCatalog.blessedModelID,
          "localAssistReady": modelReady ? "true" : "false",
          "localAssistDirectory": LocalModelCatalog.blessedModelDirectory.path,
          "textReady": textReady ? "true" : "false",
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
    onEvent(
      HeadlessCompassEvent(
        kind: "cloud_readiness",
        level: cloudReady ? "success" : "warning",
        status: cloudReady ? "ready" : "missing",
        message: cloudReady
          ? "OpenAI-compatible cloud endpoint is configured."
          : "OpenAI-compatible cloud endpoint is not fully configured.",
        metadata: [
          "baseURL": settings.cloudEndpointDisplay(),
          "model": settings.trimmedModel,
          "apiKeyPresent": settings.trimmedAPIKey.isEmpty ? "false" : "true",
        ]
      )
    )
    if !modelReady {
      onEvent(
        HeadlessCompassEvent(
          kind: "model_readiness",
          level: "warning",
          status: "missing",
          message: "Blessed MLX assist model is not ready.",
          metadata: ["model": LocalModelCatalog.blessedModelID]
        )
      )
    }
    return textReady && sandboxStatus.ok
  }

  public func scaffoldTypeScript(
    at url: URL,
    name: String?,
    initializeGit: Bool = false,
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
    var settings = AgentRuntimeSettings.defaultFromEnvironment()
    switch mode {
    case .mlx:
      settings.textProvider = .mlx
    case .cloud:
      settings.textProvider = .openAICompatible
    case .auto, .fixture:
      break
    }
    let forgeProfile =
      (try? ForgeProfileService.detectAndPersist(repoURL: repoURL, workspace: workspace))
      ?? .generatedProjectDefault

    let brief = options.brief.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !brief.isEmpty else {
      throw HeadlessCompassError.invalidBrief("Brief cannot be empty.")
    }
    try workspace.writeVision(brief)
    try seedHeadlessBrief(brief, workspace: workspace)

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
          if let infrastructureIssue = packageManagerBootstrapFailureIssue(from: issue) {
            session.notes.append(infrastructureIssue)
            session.status = .failed
            session.endedAt = Date().timeIntervalSince1970 * 1000
            try persist(session: session, workspace: workspace)
            onEvent(
              HeadlessCompassEvent(
                kind: "session_end",
                level: "error",
                status: "failed",
                message: "Develop hit a package-manager bootstrap failure.",
                detail: infrastructureIssue,
                metadata: [
                  "session": "\(sessionNumber)",
                  "retryKind": "infrastructure_failure",
                ]
              )
            )
            return false
          }
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

        if verify.exitCode == 0,
          let issue = await successfulVerifyCoverageIssue(
            command: immediate.verify,
            output: verify.stdout + verify.stderr,
            beforeSha: session.beforeSha,
            repoURL: repoURL
          )
        {
          session.notes.append("Verify attempt \(attempt) passed with coverage gaps.")
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
              retryKind: "coverage_gap",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }
          break
        }

        if verify.exitCode == 0,
          let issue = await successfulVerifyMissingRequiredTestIssue(
            immediate: immediate,
            brief: plannedState.brief,
            command: immediate.verify,
            beforeSha: session.beforeSha,
            repoURL: repoURL
          )
        {
          session.notes.append("Verify attempt \(attempt) passed without required test changes.")
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
              retryKind: "missing_required_tests",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }
          break
        }

        if verify.exitCode == 0,
          let issue = await successfulVerifyWeakCLIFlagTestIssue(
            immediate: immediate,
            brief: plannedState.brief,
            command: immediate.verify,
            beforeSha: session.beforeSha,
            repoURL: repoURL
          )
        {
          session.notes.append("Verify attempt \(attempt) passed with weak CLI flag tests.")
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
              retryKind: "weak_cli_flag_tests",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }
          break
        }

        if verify.exitCode == 0,
          let issue = await successfulVerifyMissingPackageEntryIssue(
            command: immediate.verify,
            beforeSha: session.beforeSha,
            repoURL: repoURL
          )
        {
          session.notes.append("Verify attempt \(attempt) passed with broken package entry points.")
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
              retryKind: "missing_package_entry",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }
          break
        }

        if verify.exitCode == 0,
          let issue = await successfulVerifyManifestOnlyImplementationIssue(
            immediate: immediate,
            brief: plannedState.brief,
            command: immediate.verify,
            beforeSha: session.beforeSha,
            repoURL: repoURL
          )
        {
          session.notes.append("Verify attempt \(attempt) passed after metadata-only changes.")
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
              retryKind: "metadata_only_implementation",
              onEvent: onEvent
            )
            attempt += 1
            continue
          }
          break
        }

        if verify.exitCode == 0 {
          successfulDevelop = develop
          ok = true
          break
        }

        let issue = verifyFailureIssue(command: immediate.verify, result: verify)
        if let infrastructureIssue = packageManagerBootstrapFailureIssue(
          from: verify.stdout + verify.stderr
        ) {
          session.notes.append("Verify attempt \(attempt) hit a package-manager bootstrap failure.")
          session.notes.append(infrastructureIssue)
          session.status = .failed
          session.endedAt = Date().timeIntervalSince1970 * 1000
          try persist(session: session, workspace: workspace)
          onEvent(
            HeadlessCompassEvent(
              kind: "session_end",
              level: "error",
              status: "failed",
              message: "Verify hit a package-manager bootstrap failure.",
              detail: infrastructureIssue,
              metadata: [
                "session": "\(sessionNumber)",
                "retryKind": "infrastructure_failure",
                "command": immediate.verify,
              ]
            )
          )
          return false
        }
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

  private func seedHeadlessBrief(_ brief: String, workspace: CompassWorkspace) throws {
    let current = try workspace.readState()
    let seeded = Self.stateBySeedingHeadlessBrief(current, brief: brief)
    guard seeded != current else { return }
    try workspace.writeState(seeded)
  }

  static func stateBySeedingHeadlessBrief(_ state: PlanState, brief: String) -> PlanState {
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

  private static func compactBriefSummary(_ brief: String, limit: Int = 280) -> String {
    let compact = brief
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
      vision: workspace.readVision(),
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
    onEvent(
      HeadlessCompassEvent(
        kind: "verify_start",
        status: "running",
        phase: "verify",
        message: "Running verify command in containerized Linux runtime.",
        metadata: ["command": command, "runtime": "containerized_linux"]
      )
    )
    let started = Date()
    let result = try await bashRunnerFactory(repoURL, "verify").run(
      command: command,
      workingDirectory: repoURL,
      timeout: timeoutSeconds
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

  private func packageManagerBootstrapFailureIssue(from detail: String) -> String? {
    let insight = VerifyFailureInsight(detail: detail, metadata: nil)
    guard insight.kind == .packageManagerBootstrap else { return nil }
    return """
      TypeScript package-manager bootstrap failed before project verification could run.

      \(insight.inspectDetail)

      Repair guidance: \(insight.repairDetail)

      Compass will not retry Develop for this failure because application code changes cannot
      repair Corepack, pnpm, or network availability in the execution environment.
      """
  }

  private struct CoverageTableRow {
    let path: String
    let statements: Double?
    let functions: Double?
    let lines: Double?
  }

  private struct CoverageGap {
    let changedPath: String
    let coverageLine: String
    let testTargetLines: [String]
  }

  private struct PackageEntryPointIssue {
    let manifestPath: String
    let field: String
    let declaredPath: String
    let targetPath: String
  }

  private func successfulVerifyCoverageIssue(
    command: String,
    output: String,
    beforeSha: String?,
    repoURL: URL
  ) async -> String? {
    let rows = Self.vitestCoverageRows(in: output)
    guard !rows.isEmpty,
      let changedPaths = await gitChangedPathsSince(beforeSha, repoURL: repoURL)
    else {
      return nil
    }

    let changedSourcePaths = changedPaths.filter(Self.isCoverageGatedSourcePath)
    guard !changedSourcePaths.isEmpty else { return nil }

    let gaps = changedSourcePaths.compactMap { changedPath -> CoverageGap? in
      guard
        let row = rows.first(where: {
          Self.coveragePath($0.path, matchesChangedPath: changedPath)
        }),
        row.statements == 0 || row.functions == 0 || row.lines == 0
      else {
        return nil
      }

      let coveragePath = row.path == changedPath ? row.path : "\(changedPath) (reported as \(row.path))"
      let coverageLine =
        "- \(coveragePath): statements \(Self.percentLabel(row.statements)), functions \(Self.percentLabel(row.functions)), lines \(Self.percentLabel(row.lines))"
      return CoverageGap(
        changedPath: changedPath,
        coverageLine: coverageLine,
        testTargetLines: Self.coverageRepairTestTargetLines(for: changedPath, repoURL: repoURL)
      )
    }

    guard !gaps.isEmpty else { return nil }
    let targetLines = gaps.flatMap(\.testTargetLines)
    let testTargetSection =
      targetLines.isEmpty
      ? ""
      : """

        Suggested test targets:
        \(targetLines.joined(separator: "\n"))
        """
    let sourceList = gaps.map { "`\($0.changedPath)`" }.joined(separator: ", ")
    return """
      Verify passed for `\(command)`, but coverage shows changed source files were not exercised:
      \(gaps.map(\.coverageLine).joined(separator: "\n"))

      Coverage repair instructions:
      - Your next Develop action should be test-focused, not another source-only inspection.
      - Add or update a test that imports and executes \(sourceList).
      - Do not edit those source files merely to say no changes were needed; the problem is
        missing execution evidence, not a source formatting issue.
      - If an existing sibling or package test file is listed below, read it and edit it.
        Otherwise create the suggested sibling `*.test.ts` file.
      \(testTargetSection)

      A green verify is not enough when new or changed source has 0% coverage. Add or update tests that import and execute these changed files, wire the new code into the planned behavior when needed, then rerun `\(command)`.
      """
  }

  private static func coverageRepairTestTargetLines(for changedPath: String, repoURL: URL)
    -> [String]
  {
    var candidates = coverageRepairTestTargets(for: changedPath)
    let existingPackageTests = existingCoveragePackageTestTargets(for: changedPath, repoURL: repoURL)
    for candidate in existingPackageTests where !candidates.contains(candidate) {
      candidates.append(candidate)
    }

    let fm = FileManager.default
    return candidates.map { candidate in
      let exists = fm.fileExists(atPath: repoURL.appending(path: candidate).path)
      let action = exists ? "read_file then edit_file" : "write_file"
      return "- `\(candidate)` (\(action)) should import and execute `\(changedPath)`."
    }
  }

  private static func coverageRepairTestTargets(for changedPath: String) -> [String] {
    let url = URL(fileURLWithPath: changedPath)
    let ext = url.pathExtension
    let basename = url.deletingPathExtension().lastPathComponent
    guard !ext.isEmpty else { return [] }
    let sibling = url
      .deletingLastPathComponent()
      .appending(path: "\(basename).test.\(ext)")
      .relativePath
    return [sibling]
  }

  private func successfulVerifyMissingRequiredTestIssue(
    immediate: PlanNext,
    brief: PlanStrategicContext,
    command: String,
    beforeSha: String?,
    repoURL: URL
  ) async -> String? {
    guard let changedPaths = await gitChangedPathsSince(beforeSha, repoURL: repoURL) else {
      return nil
    }

    let changedSourcePaths = changedPaths.filter(Self.isCoverageGatedSourcePath)
    guard !changedSourcePaths.isEmpty else { return nil }
    guard !changedPaths.contains(where: Self.isTestPath) else { return nil }

    let requestedTestPaths = Self.mentionedTestPaths(
      in: [
        immediate.plan,
        immediate.selectedBecause ?? "",
        brief.summary,
        brief.desiredOutcomes.joined(separator: "\n"),
        brief.constraints.joined(separator: "\n"),
        brief.acceptanceSignals.joined(separator: "\n"),
      ].joined(separator: "\n")
    )
    guard !requestedTestPaths.isEmpty else { return nil }

    return """
      Verify passed for `\(command)`, but the accepted plan or brief explicitly requires test changes and no test/spec file changed.

      Requested test file(s):
      \(requestedTestPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Changed source file(s) without a matching test edit:
      \(changedSourcePaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Missing required test instructions:
      - Your next Develop action should update one of the requested test files before submitting success.
      - Add assertions for the new behavior named in the plan or brief, then rerun `\(command)`.
      - Do not rely on a green verify from the old tests when the acceptance checks explicitly call for new or updated tests.
      """
  }

  private func successfulVerifyWeakCLIFlagTestIssue(
    immediate: PlanNext,
    brief: PlanStrategicContext,
    command: String,
    beforeSha: String?,
    repoURL: URL
  ) async -> String? {
    let handoffText = [
      immediate.plan,
      immediate.selectedBecause ?? "",
      brief.summary,
      brief.desiredOutcomes.joined(separator: "\n"),
      brief.constraints.joined(separator: "\n"),
      brief.acceptanceSignals.joined(separator: "\n"),
    ].joined(separator: "\n").lowercased()
    guard handoffText.contains("--format json"), handoffText.contains("cli") else {
      return nil
    }
    guard let changedPaths = await gitChangedPathsSince(beforeSha, repoURL: repoURL) else {
      return nil
    }
    let changedCLIPaths = changedPaths.filter { path in
      path.hasPrefix("packages/cli/src/") && Self.isCoverageGatedSourcePath(path)
    }
    guard !changedCLIPaths.isEmpty else { return nil }
    let changedTestPaths = changedPaths.filter { path in
      path.hasPrefix("packages/cli/src/") && Self.isTestPath(path)
    }
    guard !changedTestPaths.isEmpty else { return nil }

    let changedTestFiles: [(path: String, contents: String)] = changedTestPaths.compactMap { path in
      let url = repoURL.appending(path: path)
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
      return (path, contents)
    }
    guard !changedTestFiles.contains(where: { Self.containsSplitFormatJSONAssertion($0.contents) }) else {
      return nil
    }
    let weakTestPaths = changedTestFiles.map(\.path)
    guard !weakTestPaths.isEmpty else { return nil }

    return """
      Verify passed for `\(command)`, but the CLI `--format json` tests do not exercise real argv splitting.

      In `process.argv`, `--format json` arrives as separate `--format` and `json` arguments. A test like `["--format json", "Ship", "it"]` can pass while the real CLI command fails.

      Weak or missing split-argv test file(s):
      \(weakTestPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Changed CLI source file(s):
      \(changedCLIPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Required repair:
      - Update the CLI test to call the exported CLI function with split arguments, for example `main(["--format", "json", "Ship", "it"])`.
      - Assert the JSON title is `Ship it`, with `open` and `total` fields present.
      - Rerun `\(command)` after the test and implementation agree on real argv behavior.
      """
  }

  private func successfulVerifyMissingPackageEntryIssue(
    command: String,
    beforeSha: String?,
    repoURL: URL
  ) async -> String? {
    guard let changedPaths = await gitChangedPathsSince(beforeSha, repoURL: repoURL),
      !changedPaths.isEmpty
    else {
      return nil
    }

    let reviewPaths = changedPaths.filter { !Self.isHeadlessFixtureArtifactPath($0) }
    let issues = Self.missingPackageEntryPointIssues(repoURL: repoURL).filter { issue in
      reviewPaths.contains(issue.manifestPath) || reviewPaths.contains(issue.targetPath)
    }
    guard !issues.isEmpty else { return nil }

    return """
      Verify passed for `\(command)`, but package entry points now reference files that do not exist:
      \(issues.map { "- `\($0.manifestPath)` \($0.field) = `\($0.declaredPath)` -> missing `\($0.targetPath)`" }.joined(separator: "\n"))

      Package-entry repair instructions:
      - If this is a real replacement entry point, create the missing target file with the implementation and add or update tests that execute it.
      - If the replacement was accidental, restore the manifest entry to the existing source file and edit that existing file instead.
      - Rerun `\(command)` after the manifest and files agree.

      A green package build can miss a package `bin` target when the TypeScript project only compiles files from `tsconfig.json`. Do not submit success while a package entry points at a missing file.
      """
  }

  private func successfulVerifyManifestOnlyImplementationIssue(
    immediate: PlanNext,
    brief: PlanStrategicContext,
    command: String,
    beforeSha: String?,
    repoURL: URL
  ) async -> String? {
    guard let changedPaths = await gitChangedPathsSince(beforeSha, repoURL: repoURL),
      !changedPaths.isEmpty
    else {
      return nil
    }
    let reviewPaths = changedPaths.filter { !Self.isHeadlessFixtureArtifactPath($0) }
    guard !reviewPaths.isEmpty,
      !reviewPaths.contains(where: Self.isCoverageGatedSourcePath),
      !reviewPaths.contains(where: Self.isTestPath),
      reviewPaths.allSatisfy(Self.isPackageMetadataPath)
    else {
      return nil
    }

    let handoffText = [
      immediate.plan,
      immediate.selectedBecause ?? "",
      brief.summary,
      brief.desiredOutcomes.joined(separator: "\n"),
      brief.constraints.joined(separator: "\n"),
      brief.acceptanceSignals.joined(separator: "\n"),
    ].joined(separator: "\n")
    guard Self.handoffRequiresSourceOrTestWork(handoffText) else { return nil }

    return """
      Verify passed for `\(command)`, but this Develop attempt changed only package metadata or lockfiles:
      \(reviewPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      The accepted handoff asks for source behavior or tests, so metadata-only changes are not enough.

      Required repair:
      - Edit or create the source file that implements the requested behavior.
      - Add or update a test/spec file that executes that behavior.
      - Keep package metadata changes only if they are still needed after the source and test edits.
      - Rerun `\(command)` after source and test files changed.
      """
  }

  private static func containsSplitFormatJSONAssertion(_ contents: String) -> Bool {
    let normalized = contents
      .replacingOccurrences(of: "'", with: "\"")
      .unicodeScalars
      .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
      .map(String.init)
      .joined()
    return normalized.contains("[\"--format\",\"json\"")
      || normalized.contains("([\"--format\",\"json\"")
  }

  private static func mentionedTestPaths(in text: String) -> [String] {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
    let normalized = String(
      text.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
    )
    var seen: Set<String> = []
    var paths: [String] = []
    for rawToken in normalized.split(whereSeparator: \.isWhitespace) {
      let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
      guard !token.isEmpty, isTestPath(token), seen.insert(token).inserted else { continue }
      paths.append(token)
    }
    return paths.sorted()
  }

  private static func existingCoveragePackageTestTargets(for changedPath: String, repoURL: URL)
    -> [String]
  {
    let sourceURL = URL(fileURLWithPath: changedPath)
    let sourceDirectory = sourceURL.deletingLastPathComponent()
    let fm = FileManager.default
    let directoryURL = repoURL.appending(path: sourceDirectory.relativePath)
    guard
      let entries = try? fm.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return entries.compactMap { entry -> String? in
      let filename = entry.lastPathComponent.lowercased()
      guard filename.contains(".test.") || filename.contains(".spec.") else { return nil }
      guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        return nil
      }
      return sourceDirectory.appending(path: entry.lastPathComponent).relativePath
    }.sorted()
  }

  private static func missingPackageEntryPointIssues(repoURL: URL) -> [PackageEntryPointIssue] {
    packageManifestURLs(in: repoURL).flatMap { manifestURL in
      missingPackageEntryPointIssues(manifestURL: manifestURL, repoURL: repoURL)
    }
    .sorted {
      [$0.manifestPath, $0.field, $0.targetPath].joined(separator: "\u{0}")
        < [$1.manifestPath, $1.field, $1.targetPath].joined(separator: "\u{0}")
    }
  }

  private static func packageManifestURLs(in repoURL: URL) -> [URL] {
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: repoURL,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var manifests: [URL] = []
    for case let url as URL in enumerator {
      let name = url.lastPathComponent
      if Self.shouldSkipPackageManifestScanDescendants(url) {
        enumerator.skipDescendants()
        continue
      }
      guard name == "package.json",
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      else {
        continue
      }
      manifests.append(url)
    }
    return manifests
  }

  private static func shouldSkipPackageManifestScanDescendants(_ url: URL) -> Bool {
    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
      return false
    }
    return [".compass", ".git", "dist", "node_modules"].contains(url.lastPathComponent)
  }

  private static func missingPackageEntryPointIssues(
    manifestURL: URL,
    repoURL: URL
  ) -> [PackageEntryPointIssue] {
    guard let data = try? Data(contentsOf: manifestURL),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return []
    }

    let manifestPath = relativePath(manifestURL, repoURL: repoURL)
    let packageDirectory = manifestURL.deletingLastPathComponent()
    let scalarEntries: [(field: String, rawPath: String)] = [
      "main", "module", "browser", "types", "typings",
    ].compactMap { field in
      (object[field] as? String).map { (field, $0) }
    }

    let binEntries: [(field: String, rawPath: String)]
    if let bin = object["bin"] as? String {
      binEntries = [("bin", bin)]
    } else if let bin = object["bin"] as? [String: Any] {
      binEntries = bin.compactMap { key, value in
        (value as? String).map { ("bin.\(key)", $0) }
      }
    } else {
      binEntries = []
    }

    return (scalarEntries + binEntries).compactMap { entry in
      guard let cleanedPath = cleanedLocalPackageEntryPath(entry.rawPath) else { return nil }
      let targetURL = packageDirectory.appending(path: cleanedPath).standardizedFileURL
      guard !FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
      return PackageEntryPointIssue(
        manifestPath: manifestPath,
        field: entry.field,
        declaredPath: entry.rawPath,
        targetPath: relativePath(targetURL, repoURL: repoURL)
      )
    }
  }

  private static func cleanedLocalPackageEntryPath(_ rawPath: String) -> String? {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !trimmed.hasPrefix("#"),
      !trimmed.contains("://")
    else {
      return nil
    }

    let withoutFragment = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
    let withoutQuery =
      withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
    let cleaned = withoutQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }
    return cleaned
  }

  private static func isPackageMetadataPath(_ path: String) -> Bool {
    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return filename == "package.json"
      || filename == "pnpm-lock.yaml"
      || filename == "package-lock.json"
      || filename == "npm-shrinkwrap.json"
      || filename == "yarn.lock"
  }

  private static func isHeadlessFixtureArtifactPath(_ path: String) -> Bool {
    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return filename == "fixture.jsonl" || filename.hasSuffix("-fixture.jsonl")
  }

  private static func handoffRequiresSourceOrTestWork(_ text: String) -> Bool {
    let normalized = text.lowercased()
    let sourceSignals = [
      "acceptance checks",
      "add core",
      "cli",
      "command",
      "component",
      "cover",
      "function",
      "implement",
      "logic",
      "source",
      "test",
      "web",
    ]
    return sourceSignals.contains { normalized.contains($0) }
  }

  private static func relativePath(_ url: URL, repoURL: URL) -> String {
    let repoPath = repoURL.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path == repoPath || path.hasPrefix(repoPath + "/") else {
      return url.path
    }
    if path == repoPath { return "." }
    return String(path.dropFirst(repoPath.count + 1))
  }

  private static func vitestCoverageRows(in output: String) -> [CoverageTableRow] {
    var rows: [CoverageTableRow] = []
    var currentDirectory: String?

    for line in output.components(separatedBy: "\n") {
      guard line.contains("|") else { continue }
      let columns = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
      guard columns.count >= 5 else { continue }

      let displayPath = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !displayPath.isEmpty,
        displayPath != "File",
        displayPath != "All files",
        !displayPath.allSatisfy({ $0 == "-" })
      else {
        continue
      }

      if !Self.hasSourceExtension(displayPath), displayPath.contains("/") {
        currentDirectory = displayPath
        continue
      }
      guard Self.hasSourceExtension(displayPath) else { continue }

      let coveragePath: String
      if displayPath.contains("/") || currentDirectory == nil {
        coveragePath = displayPath
      } else {
        coveragePath = [currentDirectory!, displayPath].joined(separator: "/")
      }

      rows.append(
        CoverageTableRow(
          path: coveragePath,
          statements: Self.coveragePercent(columns[1]),
          functions: Self.coveragePercent(columns[3]),
          lines: Self.coveragePercent(columns[4])
        ))
    }

    return rows
  }

  private static func coveragePath(_ coveragePath: String, matchesChangedPath changedPath: String)
    -> Bool
  {
    changedPath == coveragePath || changedPath.hasSuffix("/\(coveragePath)")
      || changedPath.hasSuffix(coveragePath)
  }

  private static func isCoverageGatedSourcePath(_ path: String) -> Bool {
    let lowercased = path.lowercased()
    guard hasSourceExtension(lowercased),
      !lowercased.contains("/dist/"),
      !lowercased.contains("/node_modules/")
    else {
      return false
    }
    let filename = URL(fileURLWithPath: lowercased).lastPathComponent
    return !filename.contains(".test.") && !filename.contains(".spec.")
  }

  private static func isTestPath(_ path: String) -> Bool {
    let lowercased = path.lowercased()
    guard hasSourceExtension(lowercased) else { return false }
    let filename = URL(fileURLWithPath: lowercased).lastPathComponent
    return filename.contains(".test.") || filename.contains(".spec.")
  }

  private static func hasSourceExtension(_ path: String) -> Bool {
    ["js", "jsx", "mjs", "mts", "ts", "tsx"].contains(
      URL(fileURLWithPath: path).pathExtension.lowercased())
  }

  private static func coveragePercent(_ value: String) -> Double? {
    let cleaned = value
      .replacingOccurrences(of: "%", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Double(cleaned)
  }

  private static func percentLabel(_ value: Double?) -> String {
    guard let value else { return "unknown" }
    if value.rounded() == value {
      return "\(Int(value))%"
    }
    return String(format: "%.2f%%", value)
  }

  private func makeRuntime(
    mode: HeadlessModelMode,
    fixtureURL: URL?,
    promptLogDirectory: URL?,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) throws -> any LocalModelGenerating {
    let settings = AgentSettingsStore().load()
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
    case .mlx:
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
    case .cloud, .auto:
      let runtime = ModelRuntimeFactory.makeRouted(settings: settings)
      if mode == .cloud {
        guard settings.hasCloudCredentials else {
          let message =
            "OpenAI-compatible cloud endpoint is not configured. Set COMPASS_AGENT_API_KEY, COMPASS_AGENT_BASE_URL, and COMPASS_AGENT_MODEL."
          onEvent(
            HeadlessCompassEvent(
              kind: "cloud_readiness",
              level: "error",
              status: "missing",
              message: message,
              metadata: [
                "baseURL": settings.cloudEndpointDisplay(),
                "model": settings.trimmedModel,
              ]
            )
          )
          throw HeadlessCompassError.cloudNotConfigured(message)
        }
      } else if runtime.cloud == nil && runtime.local == nil {
        let message =
          "No model backend is ready. Configure an OpenAI-compatible endpoint or download the local MLX model."
        onEvent(
          HeadlessCompassEvent(
            kind: "model_readiness",
            level: "error",
            status: "missing",
            message: message
          )
        )
        throw HeadlessCompassError.modelMissing(message)
      }
      onEvent(
        HeadlessCompassEvent(
          kind: "model_runtime",
          status: "ready",
          message: mode == .cloud
            ? "Using OpenAI-compatible cloud runtime."
            : "Using routed cloud/local model runtime.",
          metadata: [
            "mode": mode.rawValue,
            "cloudReady": runtime.cloud == nil ? "false" : "true",
            "localAssistReady": runtime.local == nil ? "false" : "true",
            "textProvider": settings.textProvider.rawValue,
            "cloudModel": settings.trimmedModel,
            "cloudBaseURL": settings.cloudEndpointDisplay(),
          ]
        )
      )
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
      let settings = AgentSettingsStore().load()
      if settings.hasCloudCredentials {
        return .cloud
      }
      if LocalModelCatalog.isBlessedModelReady() {
        return .mlx
      }
      return .cloud
    case .fixture, .mlx, .cloud:
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
      let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? ""
      let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
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
