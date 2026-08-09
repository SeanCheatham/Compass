import Foundation

public struct HealthPassOptions: Equatable, Sendable {
  public var budget: HealthBudget
  public var skipHunt: Bool
  public var failOpen: Bool
  /// When true, create/checkout a Compass health branch for the pass and restore afterward.
  public var manageBranch: Bool
  /// When set, use this session for commit/metadata and skip begin/end (caller owns the branch).
  public var branchSession: HealthBranch.Session?
  public var focus: HealthFocus?
  public var projectId: String

  public static let factoryShip = HealthPassOptions(
    budget: .factoryShipDefault,
    skipHunt: false,
    failOpen: true,
    manageBranch: false,
    branchSession: nil,
    focus: .bugHunt,
    projectId: "factory"
  )

  public static let healthLoop = HealthPassOptions(
    budget: .healthLoopDefault,
    skipHunt: false,
    failOpen: false,
    manageBranch: true,
    branchSession: nil,
    focus: nil,
    projectId: "health"
  )

  public init(
    budget: HealthBudget = .factoryShipDefault,
    skipHunt: Bool = false,
    failOpen: Bool = true,
    manageBranch: Bool = false,
    branchSession: HealthBranch.Session? = nil,
    focus: HealthFocus? = nil,
    projectId: String = "health"
  ) {
    self.budget = budget
    self.skipHunt = skipHunt
    self.failOpen = failOpen
    self.manageBranch = manageBranch
    self.branchSession = branchSession
    self.focus = focus
    self.projectId = projectId
  }
}

public struct HealthPassOutcome: Equatable, Sendable {
  public var snapshot: HealthSnapshot
  public var errorMessage: String?

  public init(snapshot: HealthSnapshot, errorMessage: String? = nil) {
    self.snapshot = snapshot
    self.errorMessage = errorMessage
  }
}

/// Shared health orchestration for factory post-ship and pure health projects.
public enum HealthPassRunner {
  public static func run(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    bashRunner: AgentBashRunner,
    sessionNumber: Int,
    options: HealthPassOptions = .factoryShip,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void = { _ in },
    onLive: (@Sendable (LiveEvent) -> Void)? = nil,
    bindExecutor: (@Sendable (AgentExecutor?) -> Void)? = nil
  ) async -> HealthPassOutcome {
    let focus = options.focus ?? HealthFocus.weightedRandom()
    onEvent(
      HeadlessCompassEvent(
        kind: "health_start",
        status: "running",
        phase: AgentPhase.health.rawValue,
        message: "Health pass started (\(focus.displayName))."
      )
    )
    onLive?(
      LiveEvent(
        level: .info,
        text: "Health started",
        detail: options.skipHunt
          ? "Recon only"
          : "Recon → \(focus.displayName)",
        kind: .message,
        status: .running,
        metadata: [
          "phase": AgentPhase.health.rawValue,
          "focus": focus.rawValue,
        ]
      )
    )

    var branchSession: HealthBranch.Session?
    let ownsBranch: Bool
    if let external = options.branchSession {
      branchSession = external
      ownsBranch = false
    } else if options.manageBranch {
      ownsBranch = true
      do {
        branchSession = try HealthBranch.begin(
          repoURL: workspace.repoURL,
          projectId: options.projectId
        )
      } catch {
        let message = error.localizedDescription
        onEvent(
          HeadlessCompassEvent(
            kind: "health_branch_error",
            level: "error",
            status: "failed",
            phase: AgentPhase.health.rawValue,
            message: "Health branch setup failed.",
            detail: message
          )
        )
        return HealthPassOutcome(
          snapshot: HealthSnapshot(
            sessionNumber: sessionNumber,
            notes: [message],
            partial: true,
            focus: focus
          ),
          errorMessage: message
        )
      }
    } else {
      ownsBranch = false
    }
    defer {
      if ownsBranch, let branchSession {
        try? HealthBranch.end(repoURL: workspace.repoURL, session: branchSession)
      }
    }

    let prior = HealthSnapshotStore.readSnapshot(from: workspace)
    let recon = await HealthRecon.run(
      repoURL: workspace.repoURL,
      bashRunner: bashRunner,
      timeout: TimeInterval(options.budget.wallClockSecs),
      focus: focus,
      onLive: onLive
    )

    if var coverage = recon.coverage {
      coverage.sessionNumber = sessionNumber
      try? CoverageSnapshotStore.writeCoverageSnapshot(coverage, workspace: workspace)
    }

    var snapshot = HealthSnapshot(
      collectedAt: Date(),
      sessionNumber: sessionNumber,
      recon: recon,
      notes: recon.notes,
      partial: false,
      focus: focus,
      healthBranch: branchSession?.healthBranch,
      baseSHA: branchSession?.baseSHA
    )

    if !recon.baselineTests.success {
      snapshot.findings.append(
        HealthFinding(
          kind: .baselineFailure,
          title: "Baseline tests failing",
          description: "Existing suite is red before health pass.",
          confidence: 0.9,
          triage: HealthTriageResult(
            isRealBug: true,
            rationale: "Baseline cargo test failed; treat as real defect signal."
          ),
          evidence: String((recon.baselineTests.stdout + recon.baselineTests.stderr).suffix(4000)),
          focus: focus
        )
      )
    }

    if focus == .cleanup, !recon.deadCodeCandidates.isEmpty, !options.skipHunt {
      let probeTimeout = min(
        TimeInterval(options.budget.wallClockSecs) / 4,
        600
      )
      let probe = await DeletionTester.probe(
        repoURL: workspace.repoURL,
        candidates: recon.deadCodeCandidates,
        bashRunner: bashRunner,
        timeout: max(60, probeTimeout),
        onLive: onLive
      )
      snapshot.deletionProbe = probe
      snapshot.notes.append(contentsOf: probe.notes)
      onEvent(
        HeadlessCompassEvent(
          kind: "health_deletion_probe",
          status: "completed",
          phase: AgentPhase.health.rawValue,
          message:
            "Deletion probe: \(probe.proven.count) proven, \(probe.live.count) live, \(probe.tangled.count) tangled.",
          metadata: [
            "proven": "\(probe.proven.count)",
            "live": "\(probe.live.count)",
            "tangled": "\(probe.tangled.count)",
          ]
        )
      )
    }

    if options.skipHunt {
      return await finalize(
        snapshot: snapshot,
        workspace: workspace,
        bashRunner: bashRunner,
        branchSession: branchSession,
        focus: focus,
        onEvent: onEvent,
        onLive: onLive
      )
    }

    do {
      let hunt = try await runHunt(
        workspace: workspace,
        settings: settings,
        runtime: runtime,
        bashRunner: bashRunner,
        recon: recon,
        prior: prior,
        deletionProbe: snapshot.deletionProbe,
        focus: focus,
        sessionNumber: sessionNumber,
        budget: options.budget,
        onEvent: onEvent,
        onLive: onLive,
        bindExecutor: bindExecutor
      )
      snapshot.plan = hunt.plan
      snapshot.generatedTests = hunt.generatedTests
      var findings = hunt.findings.map { finding in
        var updated = finding
        if updated.focus == nil { updated.focus = focus }
        return updated
      }
      if !recon.baselineTests.success,
        !findings.contains(where: { $0.kind == .baselineFailure })
      {
        findings.insert(contentsOf: snapshot.findings.filter { $0.kind == .baselineFailure }, at: 0)
      }
      snapshot.findings = HealthFPGuards.apply(to: findings)
      snapshot.notes.append(contentsOf: hunt.notes)
    } catch {
      snapshot.partial = true
      snapshot.notes.append("health pass failed: \(error.localizedDescription)")
      onEvent(
        HeadlessCompassEvent(
          kind: "health_hunt_error",
          level: options.failOpen ? "warning" : "error",
          status: options.failOpen ? "completed" : "failed",
          phase: AgentPhase.health.rawValue,
          message: "Health pass failed\(options.failOpen ? " (fail-open)" : "").",
          detail: error.localizedDescription
        )
      )
      onLive?(
        LiveEvent(
          level: options.failOpen ? .warning : .error,
          text: "Health pass failed",
          detail: error.localizedDescription,
          kind: .message,
          status: .failed,
          metadata: ["phase": AgentPhase.health.rawValue]
        )
      )
      if !options.failOpen {
        bindExecutor?(nil)
        return HealthPassOutcome(
          snapshot: snapshot,
          errorMessage: error.localizedDescription
        )
      }
    }

    bindExecutor?(nil)
    return await finalize(
      snapshot: snapshot,
      workspace: workspace,
      bashRunner: bashRunner,
      branchSession: branchSession,
      focus: focus,
      onEvent: onEvent,
      onLive: onLive
    )
  }

  private static func finalize(
    snapshot: HealthSnapshot,
    workspace: CompassWorkspace,
    bashRunner: AgentBashRunner,
    branchSession: HealthBranch.Session?,
    focus: HealthFocus,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) async -> HealthPassOutcome {
    var snapshot = snapshot

    if focus == .cleanup {
      snapshot = await verifyCleanupEdits(
        snapshot: snapshot,
        workspace: workspace,
        bashRunner: bashRunner,
        onEvent: onEvent,
        onLive: onLive
      )
    }

    if branchSession != nil {
      do {
        if let tip = try HealthBranch.commitIfDirty(
          repoURL: workspace.repoURL,
          message: "health(\(focus.rawValue)): proposed patches"
        ) {
          snapshot.tipSHA = tip
          snapshot.findings = snapshot.findings.map { finding in
            var updated = finding
            if updated.commitSHA == nil { updated.commitSHA = tip }
            return updated
          }
        } else if let tip = try? HealthBranch.tipSHA(repoURL: workspace.repoURL) {
          snapshot.tipSHA = tip
        }
        if let base = snapshot.baseSHA, let tip = snapshot.tipSHA {
          snapshot.commits = (try? HealthBranch.commits(
            repoURL: workspace.repoURL,
            baseSHA: base,
            tipSHA: tip
          )) ?? []
        }
      } catch {
        snapshot.notes.append("health commit failed: \(error.localizedDescription)")
      }
    }

    return persist(snapshot: snapshot, workspace: workspace, onEvent: onEvent, onLive: onLive)
  }

  /// Cleanup evidence gate: dirty tree must still pass `cargo test`, else restore and demote.
  private static func verifyCleanupEdits(
    snapshot: HealthSnapshot,
    workspace: CompassWorkspace,
    bashRunner: AgentBashRunner,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) async -> HealthSnapshot {
    var snapshot = snapshot
    let dirty: Bool
    do {
      dirty = try HealthBranch.isDirty(repoURL: workspace.repoURL)
    } catch {
      // Not a git repo (factory in-tree) — still try cargo test if there are cleanup findings.
      dirty = !snapshot.findings.filter({
        $0.kind == .deadCode || $0.kind == .orphanedSurface
      }).isEmpty
    }
    guard dirty else { return snapshot }

    let command =
      "cargo test --workspace -- --nocapture 2>&1 | tee /tmp/compass-health-cleanup-verify.log | tail -c 80000"
    let correlationID = UUID().uuidString
    onLive?(
      LiveEvent(
        level: .raw,
        text: "health cleanup verify",
        detail: command,
        kind: .command,
        status: .running,
        correlationID: correlationID,
        metadata: [
          "tool": "bash",
          "command": command,
          "phase": AgentPhase.health.rawValue,
        ],
        payload: .bash(command: command, cwd: "/workspace", output: nil, isError: nil)
      )
    )

    do {
      let result = try await bashRunner.run(
        command: command,
        workingDirectory: workspace.repoURL,
        timeout: 600
      )
      let failed = result.exitCode != 0
      let combined = result.stdout + result.stderr
      onLive?(
        LiveEvent(
          level: failed ? .error : .success,
          text: "health cleanup verify",
          detail: failed
            ? "exit \(result.exitCode)\n\(String(combined.suffix(2000)))"
            : "exit 0",
          kind: .command,
          status: failed ? .failed : .completed,
          correlationID: correlationID,
          metadata: [
            "tool": "bash",
            "exitCode": "\(result.exitCode)",
            "phase": AgentPhase.health.rawValue,
          ],
          payload: .bash(
            command: command,
            cwd: "/workspace",
            output: String(combined.suffix(2000)),
            isError: failed
          )
        )
      )
      if failed {
        snapshot.notes.append(
          "cleanup verify failed — restoring dirty tree and demoting deadCode confidence"
        )
        try? HealthBranch.restoreDirty(repoURL: workspace.repoURL)
        snapshot.findings = snapshot.findings.map { finding in
          var updated = finding
          switch updated.kind {
          case .deadCode, .orphanedSurface:
            updated.confidence = min(updated.confidence, 0.2)
            if !updated.evidence.contains("verify-failed") {
              updated.evidence =
                (updated.evidence.isEmpty ? "" : updated.evidence + "\n")
                + "verify-failed: suite red after cleanup edits"
            }
          default:
            break
          }
          return updated
        }
        onEvent(
          HeadlessCompassEvent(
            kind: "health_cleanup_verify",
            level: "warning",
            status: "failed",
            phase: AgentPhase.health.rawValue,
            message: "Cleanup edits failed cargo test; tree restored.",
            detail: String(combined.suffix(2000))
          )
        )
      } else {
        onEvent(
          HeadlessCompassEvent(
            kind: "health_cleanup_verify",
            status: "completed",
            phase: AgentPhase.health.rawValue,
            message: "Cleanup edits passed cargo test."
          )
        )
      }
    } catch {
      snapshot.notes.append("cleanup verify did not run: \(error.localizedDescription)")
      onEvent(
        HeadlessCompassEvent(
          kind: "health_cleanup_verify",
          level: "warning",
          status: "failed",
          phase: AgentPhase.health.rawValue,
          message: "Cleanup verify failed to run.",
          detail: error.localizedDescription
        )
      )
    }
    return snapshot
  }

  private static func persist(
    snapshot: HealthSnapshot,
    workspace: CompassWorkspace,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) -> HealthPassOutcome {
    do {
      try HealthSnapshotStore.writeSnapshot(snapshot, workspace: workspace)
    } catch {
      onEvent(
        HeadlessCompassEvent(
          kind: "health_persist_error",
          level: "warning",
          status: "completed",
          phase: AgentPhase.health.rawValue,
          message: "Failed to persist health snapshot.",
          detail: error.localizedDescription
        )
      )
    }
    let confirmed = snapshot.findings.filter(\.isConfirmedRealBug).count
    onEvent(
      HeadlessCompassEvent(
        kind: "health_end",
        level: "success",
        status: "completed",
        phase: AgentPhase.health.rawValue,
        message:
          "Health pass completed (\(confirmed) confirmed bug(s)).",
        metadata: [
          "findings": "\(snapshot.findings.count)",
          "confirmed": "\(confirmed)",
          "partial": snapshot.partial ? "1" : "0",
          "focus": snapshot.focus?.rawValue ?? "",
        ]
      )
    )
    onLive?(
      LiveEvent(
        level: .success,
        text: "Health completed",
        detail: "\(snapshot.findings.count) finding(s), \(confirmed) confirmed",
        kind: .message,
        status: .completed,
        metadata: ["phase": AgentPhase.health.rawValue]
      )
    )
    return HealthPassOutcome(snapshot: snapshot)
  }

  private static func runHunt(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    bashRunner: AgentBashRunner,
    recon: HealthReconResult,
    prior: HealthSnapshot?,
    deletionProbe: DeletionProbeResult?,
    focus: HealthFocus,
    sessionNumber: Int,
    budget: HealthBudget,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void,
    onLive: (@Sendable (LiveEvent) -> Void)?,
    bindExecutor: (@Sendable (AgentExecutor?) -> Void)?
  ) async throws -> HealthHuntSubmit {
    let promptMode = ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
    let userPrompt = try Prompts.healthPrompt(
      recon: recon,
      priorSnapshot: prior,
      focus: focus,
      deletionProbe: deletionProbe,
      promptMode: promptMode
    )
    let executor = AgentExecutor { live in
      onLive?(live)
      onEvent(HeadlessCompassEvent(live: live, phase: .health))
    }
    bindExecutor?(executor)
    let configuration = AgentExecutionConfiguration(
      settings: settings,
      phase: .health,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: .health,
        workingDirectoryPath: workspace.repoURL.path,
        executionEnvironment: .macOSVM,
        promptMode: promptMode
      ),
      userPrompt: userPrompt,
      tools: ToolRegistry.tools(for: .health, promptMode: promptMode, healthFocus: focus),
      modelRuntime: runtime,
      agentVisibleWorkspacePath: "/workspace",
      submitResultSchema: AgentToolParametersSchema(json: Data(Prompts.healthSchema.utf8)),
      workingDirectory: workspace.repoURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: bashRunner,
      codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
      planHistoryEntries: [],
      assumptionsURL: workspace.assumptionsURL,
      sessionNumber: sessionNumber,
      promptLogLabelPrefix: "health",
      validateSubmitResult: { args in
        _ = try JSONDecoder().decode(HealthHuntSubmit.self, from: args)
      },
      promptMode: promptMode,
      maxIterations: budget.maxIterations,
      wallClockTimeout: TimeInterval(budget.wallClockSecs)
    )
    let result = try await executor.run(configuration)
    _ = try? workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "health-submit-payload.json",
      kind: "phase_submit_payload",
      contents: String(decoding: result.submitResultArguments, as: UTF8.self),
      note: "health submit payload."
    )
    return try JSONDecoder().decode(HealthHuntSubmit.self, from: result.submitResultArguments)
  }
}
