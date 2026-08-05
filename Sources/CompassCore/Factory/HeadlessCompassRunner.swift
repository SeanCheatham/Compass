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
  public var sessionCount: Int
  public var runDevelop: Bool
  public var runCritic: Bool
  public var commitIterations: Bool

  public init(
    repoURL: URL,
    brief: String,
    mode: HeadlessModelMode = .auto,
    fixtureURL: URL? = nil,
    promptLogDirectory: URL? = nil,
    maxIterations: Int = 24,
    maxDevelopAttempts: Int = 2,
    maxVerifyRepairAttempts: Int = 1,
    sessionCount: Int = 1,
    runDevelop: Bool = true,
    runCritic: Bool = false,
    commitIterations: Bool = false
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.brief = brief
    self.mode = mode
    self.fixtureURL = fixtureURL?.standardizedFileURL
    self.promptLogDirectory = promptLogDirectory?.standardizedFileURL
    self.maxIterations = max(1, maxIterations)
    self.maxDevelopAttempts = max(1, maxDevelopAttempts)
    self.maxVerifyRepairAttempts = max(0, maxVerifyRepairAttempts)
    self.sessionCount = max(1, sessionCount)
    self.runDevelop = runDevelop
    self.runCritic = runCritic
    self.commitIterations = commitIterations
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
  public typealias BashRunnerFactory = @Sendable (URL, String) -> any AgentBashRunner
  public typealias CloudPingHandler =
    @Sendable (OpenAICompatibleEndpoint) async
    -> OpenAICompatiblePingResult

  private let bashRunnerFactory: BashRunnerFactory
  private let cloudPingHandler: CloudPingHandler
  /// Production runs always require the embedded macOS VM. Injected test
  /// factories set this to `false` so fixture bash runners can exercise the
  /// factory loop without Virtualization entitlements.
  private let requireMacOSVM: Bool

  public init() {
    self.init(
      bashRunnerFactory: { repoURL, label in
        // Agent phases may mutate the guest worktree; pull those edits back
        // so host file tools stay consistent. Verify/coverage/mutation are
        // read-mostly and should not sync build noise back to the host.
        let pullAfterRun = !Self.readOnlyBashLabels.contains(label)
        return AgentMacOSVMBashRunner(
          repoRoot: repoURL,
          label: label,
          pullAfterRun: pullAfterRun
        )
      },
      requireMacOSVM: true
    )
  }

  private static let readOnlyBashLabels: Set<String> = [
    "verify", "coverage", "mutation", "doctor", "macos-verify",
  ]

  /// Factory bash/verify always use the embedded macOS VM. Legacy
  /// `COMPASS_BASH_RUNTIME` values are ignored (including `host`).
  public enum BashRuntimeSelection: String, Sendable {
    case macOSVM = "macos_vm"
  }

  public static func bashRuntimeSelection(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> BashRuntimeSelection {
    _ = environment
    return .macOSVM
  }

  public static func bashRuntimePrefersHost(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    _ = environment
    return false
  }

  public static var bashRuntimeName: String {
    BashRuntimeSelection.macOSVM.rawValue
  }

  public static var bashRuntimeDescription: String {
    "embedded macOS VM"
  }

  public init(
    bashRunnerFactory: @escaping BashRunnerFactory,
    cloudPing: CloudPingHandler? = nil
  ) {
    self.init(
      bashRunnerFactory: bashRunnerFactory,
      requireMacOSVM: false,
      cloudPing: cloudPing
    )
  }

  public init(
    bashRunnerFactory: @escaping BashRunnerFactory,
    requireMacOSVM: Bool,
    cloudPing: CloudPingHandler? = nil
  ) {
    self.bashRunnerFactory = bashRunnerFactory
    self.requireMacOSVM = requireMacOSVM
    self.cloudPingHandler =
      cloudPing
      ?? { endpoint in
        await OpenAICompatibleModelRuntime.ping(endpoint: endpoint)
      }
  }

  @discardableResult
  public func doctor(
    repoURL: URL,
    checkCloud: Bool = false,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async -> Bool {
    let repoURL = repoURL.standardizedFileURL
    let workspace = CompassWorkspace(repoURL: repoURL)
    let settings = AgentSettingsStore().load()
    let modelReady = LocalModelCatalog.isBlessedModelReady()
    let cloudReady = settings.hasCloudCredentials
    let textReady = settings.isTextCapabilityRunnable(localModelReady: modelReady)
    let runtimeName = Self.bashRuntimeName
    onEvent(
      HeadlessCompassEvent(
        kind: "vm_runtime",
        status: "checking",
        message: "Checking the embedded macOS VM runtime.",
        metadata: ["runtime": runtimeName]
      )
    )
    let runtimeReady: Bool
    let vmReady: Bool
    let vmMessage: String
    do {
      let runner = AgentMacOSVMBashRunner(repoRoot: repoURL, label: "doctor")
      let probe = try await runner.run(
        command: "sw_vers && cargo --version && swift --version",
        workingDirectory: repoURL,
        timeout: 120
      )
      vmReady = probe.exitCode == 0
      vmMessage =
        vmReady
        ? "macOS VM runtime is ready."
        : "macOS VM probe exited \(probe.exitCode): \(probe.stderr)"
    } catch {
      vmReady = false
      vmMessage = "macOS VM runtime probe failed: \(error.localizedDescription)"
    }
    onEvent(
      HeadlessCompassEvent(
        kind: "vm_runtime",
        level: vmReady ? "success" : "error",
        status: vmReady ? "ready" : "failed",
        message: vmMessage,
        metadata: ["runtime": runtimeName]
      )
    )
    runtimeReady = vmReady
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
          "bashRuntime": runtimeName,
        ]
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
    let cloudConnectivityOK =
      checkCloud
      ? await runCloudConnectivityCheck(settings: settings, onEvent: onEvent)
      : true
    return textReady && runtimeReady && cloudConnectivityOK
  }

  /// Live-pings the configured OpenAI-compatible endpoint with a 1-token request.
  /// Returns true when the check is skipped (cloud not configured) so doctor's
  /// existing readiness signals keep their meaning; a failed ping returns false.
  @discardableResult
  public func runCloudConnectivityCheck(
    settings: AgentRuntimeSettings,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async -> Bool {
    guard settings.hasCloudCredentials else {
      onEvent(
        HeadlessCompassEvent(
          kind: "cloud_connectivity",
          level: "warning",
          status: "skipped",
          message: "Cloud endpoint is not configured; skipping connectivity check."
        )
      )
      return true
    }
    onEvent(
      HeadlessCompassEvent(
        kind: "cloud_connectivity",
        status: "checking",
        message: "Pinging OpenAI-compatible cloud endpoint.",
        metadata: [
          "baseURL": settings.cloudEndpointDisplay(),
          "model": settings.trimmedModel,
        ]
      )
    )
    let ping = await cloudPingHandler(
      OpenAICompatibleEndpoint(
        baseURL: settings.baseURL,
        apiKey: settings.apiKey,
        model: settings.model
      )
    )
    var metadata = [
      "baseURL": settings.cloudEndpointDisplay(),
      "model": settings.trimmedModel,
      "latencyMs": "\(ping.latencyMs)",
    ]
    if let statusCode = ping.statusCode {
      metadata["statusCode"] = "\(statusCode)"
    }
    onEvent(
      HeadlessCompassEvent(
        kind: "cloud_connectivity",
        level: ping.ok ? "success" : "error",
        status: ping.ok ? "ready" : "failed",
        message: ping.ok
          ? "Cloud endpoint connectivity check passed."
          : "Cloud endpoint connectivity check failed.",
        detail: ping.message,
        metadata: metadata
      )
    )
    return ping.ok
  }

  public func scaffoldRust(
    at url: URL,
    name: String?,
    products: [GeneratedProduct] = GeneratedProducts.default,
    initializeGit: Bool = false,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) throws {
    let url = url.standardizedFileURL
    let normalizedProducts = GeneratedProducts.normalize(products)
    if let error = GeneratedProducts.validate(normalizedProducts) {
      throw GeneratedProductError.invalid(error)
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let projectName = name ?? url.lastPathComponent
    try RustProjectScaffold.write(
      to: url,
      options: RustProjectScaffold.Options(projectName: projectName, products: normalizedProducts)
    )
    let workspace = CompassWorkspace(repoURL: url)
    try workspace.initialize()
    var state = try workspace.readState()
    state.products = normalizedProducts
    try workspace.writeState(state)
    onEvent(
      HeadlessCompassEvent(
        kind: "scaffold",
        level: "success",
        status: "completed",
        message: "Project scaffolded (core + \(GeneratedProducts.summary(normalizedProducts))).",
        metadata: [
          "path": url.path,
          "name": projectName,
          "products": GeneratedProducts.summary(normalizedProducts),
        ]
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
        ?? GeneratedProjectQuality.standardVerifyCommand
    return try await runVerifyCommand(
      verifyCommand,
      repoURL: options.repoURL,
      timeoutSeconds: options.timeoutSeconds,
      onEvent: onEvent
    ).exitCode == 0
  }

  @discardableResult
  public func runSessions(
    options: HeadlessRunOptions,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> Bool {
    for iteration in 1...options.sessionCount {
      var iterationOptions = options
      if options.sessionCount > 1, let promptLog = options.promptLogDirectory {
        iterationOptions.promptLogDirectory =
          promptLog.appending(path: String(format: "iteration-%03d", iteration))
      }
      if options.sessionCount > 1 {
        onEvent(
          HeadlessCompassEvent(
            kind: "factory_iteration",
            status: "running",
            message: "Factory iteration \(iteration) of \(options.sessionCount) started.",
            metadata: [
              "iteration": "\(iteration)",
              "sessionCount": "\(options.sessionCount)",
            ]
          )
        )
      }
      let ok = try await run(options: iterationOptions, onEvent: onEvent)
      guard ok else {
        if options.sessionCount > 1 {
          onEvent(
            HeadlessCompassEvent(
              kind: "factory_iteration",
              level: "error",
              status: "failed",
              message: "Factory iteration \(iteration) of \(options.sessionCount) failed; "
                + "stopping.",
              metadata: [
                "iteration": "\(iteration)",
                "sessionCount": "\(options.sessionCount)",
              ]
            )
          )
        }
        return false
      }
    }
    return true
  }

  @discardableResult
  public func run(
    options: HeadlessRunOptions,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> Bool {
    let repoURL = options.repoURL.standardizedFileURL
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    if requireMacOSVM {
      onEvent(
        HeadlessCompassEvent(
          kind: "vm_runtime",
          status: "checking",
          message: "Ensuring the embedded macOS VM is ready before the factory session."
        )
      )
      do {
        _ = try await AgentMacOSVMBashRunner.ensureReady()
        onEvent(
          HeadlessCompassEvent(
            kind: "vm_runtime",
            level: "success",
            status: "ready",
            message: "macOS VM is ready."
          )
        )
      } catch {
        onEvent(
          HeadlessCompassEvent(
            kind: "vm_runtime",
            level: "error",
            status: "failed",
            message: "macOS VM is required but not ready: \(error.localizedDescription)"
          )
        )
        throw error
      }
    }

    let sessionNumber = workspace.maxSessionNumber() + 1
    var session = SessionRecord.started(sessionNumber)
    session.beforeSha = await gitCurrentSHA(repoURL: repoURL)
    session.recordExecutionEnvironmentSnapshot(
      SessionExecutionEnvironmentSnapshot(
        phase: "CLI",
        launchPlan: requireMacOSVM
          ? .macOSVM(repoURL: repoURL)
          : .host(fallbackReason: "Injected bash runner (tests / fixtures).")
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
      try recordShippedIterations(workspace: workspace, onEvent: onEvent)
      let plan = try await runPlan(
        workspace: workspace,
        settings: settings,
        runtime: runtime,
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
          let issue = DevelopPostCheckIssues.developBudgetExhaustionIssue(
            attempt: attempt, error: error)
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
          let issue = DevelopPostCheckIssues.developFailureIssue(develop)
          if let infrastructureIssue = DevelopPostCheckIssues.packageManagerBootstrapFailureIssue(
            from: issue)
          {
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
          let issue = DevelopPostCheckIssues.noDevelopChangesIssue(develop)
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

        let changedPaths =
          verify.exitCode == 0
          ? await gitChangedPathsSince(session.beforeSha, repoURL: repoURL)
          : nil
        if verify.exitCode == 0,
          let finding = SuccessfulVerifyGates.firstFinding(
            immediate: immediate,
            brief: plannedState.brief,
            command: immediate.verify,
            verifyOutput: verify.stdout + verify.stderr,
            changedPaths: changedPaths,
            repoURL: repoURL
          )
        {
          let issue = finding.issue
          switch finding.retryKind {
          case "coverage_gap":
            session.notes.append("Verify attempt \(attempt) passed with coverage gaps.")
          case "missing_required_tests":
            session.notes.append("Verify attempt \(attempt) passed without required test changes.")
          case "weak_cli_flag_tests":
            session.notes.append("Verify attempt \(attempt) passed with weak CLI flag tests.")
          case "missing_package_entry":
            session.notes.append(
              "Verify attempt \(attempt) passed with broken package entry points.")
          case "metadata_only_implementation":
            session.notes.append("Verify attempt \(attempt) passed after metadata-only changes.")
          default:
            break
          }
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
              retryKind: finding.retryKind,
              onEvent: onEvent
            )
            attempt += 1
            continue
          }
          break
        }

        if verify.exitCode == 0 {
          await collectQualitySnapshotsAfterVerify(
            workspace: workspace,
            sessionNumber: sessionNumber,
            beforeSha: session.beforeSha,
            repoURL: repoURL,
            onEvent: onEvent
          )
          if let issue = AcceptanceGateEvaluator.issue(state: plannedState, workspace: workspace) {
            session.notes.append("Verify attempt \(attempt) passed but acceptance gates failed.")
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
                retryKind: "acceptance_gate",
                onEvent: onEvent
              )
              attempt += 1
              continue
            }
            break
          }
          if GeneratedProducts.contains(plannedState.products, .macos) {
            let macosOutcome = await MacOSVerifyGate.run(
              workingDirectory: repoURL,
              repoRoot: repoURL,
              timeout: QualityCollectionTimeout.seconds()
            )
            let macosResult = macosOutcome.result
            let macosFallbackNote =
              macosOutcome.fallbackReason.map { " (VM unavailable: \($0))" }
              ?? ""
            _ = try? workspace.writeSessionAuditArtifact(
              session: sessionNumber,
              name: "macos-verify.log",
              kind: "log",
              contents: "$ \(GeneratedProjectQuality.macosVerifyCommand)\n\n"
                + macosResult.stdout + "\n" + macosResult.stderr,
              note: "macOS verify output (\(macosOutcome.runtimeDescription)\(macosFallbackNote))."
            )
            _ = await MacOSUISmokeSupport.writeScreenshotAuditArtifact(
              workspace: workspace,
              session: sessionNumber,
              repoURL: repoURL
            )
            if macosResult.exitCode != 0 {
              let issue = """
                macOS verify `\(GeneratedProjectQuality.macosVerifyCommand)` on \(macosOutcome.runtimeDescription)\(macosFallbackNote) exited with code \(macosResult.exitCode).
                \(tail(macosResult.stdout + macosResult.stderr, max: 4000))
                """
              session.notes.append(
                "Verify attempt \(attempt) passed Rust verify but the macOS gate failed.")
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
                  retryKind: "macos_verify",
                  onEvent: onEvent
                )
                attempt += 1
                continue
              }
              break
            }
            onEvent(
              HeadlessCompassEvent(
                kind: "macos_verify",
                status: "completed",
                phase: "verify",
                message: "macOS verify passed (\(macosOutcome.runtimeDescription))."
              )
            )
          }
          successfulDevelop = develop
          ok = true
          break
        }

        let issue = DevelopPostCheckIssues.verifyFailureIssue(
          command: immediate.verify, result: verify)
        if let infrastructureIssue = DevelopPostCheckIssues.packageManagerBootstrapFailureIssue(
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
      if ok {
        try? recordShippedIterations(workspace: workspace, onEvent: onEvent)
        if options.commitIterations {
          commitIterationChanges(
            repoURL: repoURL,
            workspace: workspace,
            sessionNumber: sessionNumber,
            onEvent: onEvent
          )
        }
      }
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

  public static func stateBySeedingHeadlessBrief(_ state: PlanState, brief: String) -> PlanState {
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

  private func recordShippedIterations(
    workspace: CompassWorkspace,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) throws {
    let current = try workspace.readState()
    let recorded = PlanCompletionRecorder.recordingShippedIterations(
      into: current,
      sessions: workspace.readSessions()
    )
    guard recorded != current else { return }
    try workspace.writeState(recorded)
    onEvent(
      HeadlessCompassEvent(
        kind: "state_recorded",
        status: "completed",
        message: "Recorded \(recorded.completed.count) completed iteration(s) into factory state.",
        metadata: ["completedCount": "\(recorded.completed.count)"]
      )
    )
  }

  private func runPlan(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    sessionNumber: Int,
    maxIterations: Int,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> PlanRunResult {
    let current = try workspace.readState()
    let promptMode = ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
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
      coverageSnapshot: CoverageSnapshotStore.readCoverageSnapshot(from: workspace),
      mutationSnapshot: MutationSnapshotStore.readMutationSnapshot(from: workspace),
      promptMode: promptMode
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
    let promptMode = ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
    let prompt = Prompts.developPrompt(
      next: immediate,
      lessons: workspace.readLessons(),
      assumptions: (try? workspace.readAssumptionLedger().formattedForPrompt()) ?? "",
      vision: workspace.readVision(),
      attempt: attempt,
      priorIssues: priorIssues,
      promptMode: promptMode
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
    sessionNumber: Int,
    maxIterations: Int,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void
  ) async throws -> CriticVerdict {
    let diff = await gitDiffSinceSHA(beforeSha, repoURL: workspace.repoURL)
    let promptMode = ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
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
      iteration: 1,
      maxIterations: 1,
      promptMode: promptMode
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
        executionEnvironment: .macOSVM,
        promptMode: ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
      ),
      userPrompt: userPrompt,
      tools: ToolRegistry.tools(
        for: phase,
        promptMode: ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
      ),
      modelRuntime: runtime,
      agentVisibleWorkspacePath: "/workspace",
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
        decode: T.self
      ),
      promptMode: ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime),
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
        message: "Running verify command in \(Self.bashRuntimeDescription).",
        metadata: ["command": command, "runtime": Self.bashRuntimeName]
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

  /// After a green verify, collect coverage and mutation evidence (scoped to
  /// changed files) and persist snapshots for gate evaluation and the next
  /// Plan pass. Collection failures are non-fatal warnings.
  private func collectQualitySnapshotsAfterVerify(
    workspace: CompassWorkspace,
    sessionNumber: Int,
    beforeSha: String?,
    repoURL: URL,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async {
    let changedFiles = await gitChangedPathsSince(beforeSha, repoURL: repoURL) ?? []
    let outcome = await QualitySnapshotCollector.collect(
      context: QualitySnapshotCollector.Context(
        workspace: workspace,
        sessionNumber: sessionNumber,
        changedFiles: changedFiles,
        repoURL: repoURL
      ),
      bash: bashRunnerFactory(repoURL, "quality")
    )
    if let coverageLog = outcome.coverageLog {
      _ = try? workspace.writeSessionAuditArtifact(
        session: sessionNumber,
        name: "coverage.log",
        kind: "log",
        contents: coverageLog,
        note: "Coverage collection output."
      )
    }
    if let mutationLog = outcome.mutationLog {
      _ = try? workspace.writeSessionAuditArtifact(
        session: sessionNumber,
        name: "mutation.log",
        kind: "log",
        contents: mutationLog,
        note: "Mutation testing output."
      )
    }
    for event in outcome.events {
      onEvent(
        HeadlessCompassEvent(
          kind: event.kind.rawValue,
          level: event.level,
          status: event.status,
          phase: "verify",
          message: event.message,
          detail: event.detail,
          metadata: event.metadata
        )
      )
    }
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

  private func commitIterationChanges(
    repoURL: URL,
    workspace: CompassWorkspace,
    sessionNumber: Int,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) {
    let lastCompleted = (try? workspace.readState().completed.last) ?? nil
    let title =
      lastCompleted.map { Self.compactBriefSummary($0, limit: 72) }
      ?? "iteration \(sessionNumber)"
    let message = "Compass iteration \(sessionNumber): \(title)"
    let escaped = message.replacingOccurrences(of: "'", with: "'\\''")
    let result = Self.runShellSync(
      """
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "not a Git worktree" >&2
        exit 3
      fi
      git add -A
      if git diff --cached --quiet; then
        echo "nothing to commit"
        exit 0
      fi
      git -c user.name='Compass Factory' \
        -c user.email='compass-factory@localhost' \
        commit -m '\(escaped)'
      """,
      workingDirectory: repoURL
    )
    let committed = result.exitCode == 0 && !result.stdout.contains("nothing to commit")
    onEvent(
      HeadlessCompassEvent(
        kind: "iteration_commit",
        level: result.exitCode == 0 ? "info" : "warning",
        status: result.exitCode == 0 ? "completed" : "failed",
        message:
          result.exitCode == 0
          ? (committed
            ? "Committed iteration \(sessionNumber) changes."
            : "Nothing to commit for iteration \(sessionNumber).")
          : "Iteration commit failed (session still succeeded): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
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
