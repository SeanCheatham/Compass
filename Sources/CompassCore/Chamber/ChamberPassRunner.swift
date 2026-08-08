import Foundation

public struct ChamberPassOptions: Equatable, Sendable {
  public var budget: ChamberBudget
  public var skipHunt: Bool
  public var failOpen: Bool

  public static let factoryShip = ChamberPassOptions(
    budget: .factoryShipDefault,
    skipHunt: false,
    failOpen: true
  )

  public static let chamberLoop = ChamberPassOptions(
    budget: .chamberLoopDefault,
    skipHunt: false,
    failOpen: false
  )

  public init(
    budget: ChamberBudget = .factoryShipDefault,
    skipHunt: Bool = false,
    failOpen: Bool = true
  ) {
    self.budget = budget
    self.skipHunt = skipHunt
    self.failOpen = failOpen
  }
}

public struct ChamberPassOutcome: Equatable, Sendable {
  public var snapshot: ChamberSnapshot
  public var errorMessage: String?

  public init(snapshot: ChamberSnapshot, errorMessage: String? = nil) {
    self.snapshot = snapshot
    self.errorMessage = errorMessage
  }
}

/// Shared chamber orchestration for factory post-ship and pure chamber projects.
public enum ChamberPassRunner {
  public static func run(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    bashRunner: AgentBashRunner,
    sessionNumber: Int,
    options: ChamberPassOptions = .factoryShip,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void = { _ in },
    onLive: (@Sendable (LiveEvent) -> Void)? = nil,
    bindExecutor: (@Sendable (AgentExecutor?) -> Void)? = nil
  ) async -> ChamberPassOutcome {
    onEvent(
      HeadlessCompassEvent(
        kind: "chamber_start",
        status: "running",
        phase: AgentPhase.chamber.rawValue,
        message: "Chamber pass started."
      )
    )
    onLive?(
      LiveEvent(
        level: .info,
        text: "Chamber started",
        detail: options.skipHunt ? "Recon only" : "Recon → hunt",
        kind: .message,
        status: .running,
        metadata: ["phase": AgentPhase.chamber.rawValue]
      )
    )

    let prior = ChamberSnapshotStore.readSnapshot(from: workspace)
    let recon = await ChamberRecon.run(
      repoURL: workspace.repoURL,
      bashRunner: bashRunner,
      timeout: TimeInterval(options.budget.wallClockSecs),
      onLive: onLive
    )

    var snapshot = ChamberSnapshot(
      collectedAt: Date(),
      sessionNumber: sessionNumber,
      recon: recon,
      notes: recon.notes,
      partial: false
    )

    if !recon.baselineTests.success {
      snapshot.findings.append(
        ChamberFinding(
          kind: .baselineFailure,
          title: "Baseline tests failing",
          description: "Existing suite is red before chamber hunt.",
          confidence: 0.9,
          triage: ChamberTriageResult(
            isRealBug: true,
            rationale: "Baseline cargo test failed; treat as real defect signal."
          ),
          evidence: String((recon.baselineTests.stdout + recon.baselineTests.stderr).suffix(4000))
        )
      )
    }

    if options.skipHunt {
      return persist(snapshot: snapshot, workspace: workspace, onEvent: onEvent, onLive: onLive)
    }

    do {
      let hunt = try await runHunt(
        workspace: workspace,
        settings: settings,
        runtime: runtime,
        bashRunner: bashRunner,
        recon: recon,
        prior: prior,
        sessionNumber: sessionNumber,
        budget: options.budget,
        onEvent: onEvent,
        onLive: onLive,
        bindExecutor: bindExecutor
      )
      snapshot.plan = hunt.plan
      snapshot.generatedTests = hunt.generatedTests
      var findings = hunt.findings
      if !recon.baselineTests.success,
        !findings.contains(where: { $0.kind == .baselineFailure })
      {
        findings.insert(contentsOf: snapshot.findings.filter { $0.kind == .baselineFailure }, at: 0)
      }
      snapshot.findings = ChamberFPGuards.apply(to: findings)
      snapshot.notes.append(contentsOf: hunt.notes)
    } catch {
      snapshot.partial = true
      snapshot.notes.append("chamber hunt failed: \(error.localizedDescription)")
      onEvent(
        HeadlessCompassEvent(
          kind: "chamber_hunt_error",
          level: options.failOpen ? "warning" : "error",
          status: options.failOpen ? "completed" : "failed",
          phase: AgentPhase.chamber.rawValue,
          message: "Chamber hunt failed\(options.failOpen ? " (fail-open)" : "").",
          detail: error.localizedDescription
        )
      )
      onLive?(
        LiveEvent(
          level: options.failOpen ? .warning : .error,
          text: "Chamber hunt failed",
          detail: error.localizedDescription,
          kind: .message,
          status: .failed,
          metadata: ["phase": AgentPhase.chamber.rawValue]
        )
      )
      if !options.failOpen {
        bindExecutor?(nil)
        return ChamberPassOutcome(
          snapshot: snapshot,
          errorMessage: error.localizedDescription
        )
      }
    }

    bindExecutor?(nil)
    return persist(snapshot: snapshot, workspace: workspace, onEvent: onEvent, onLive: onLive)
  }

  private static func persist(
    snapshot: ChamberSnapshot,
    workspace: CompassWorkspace,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) -> ChamberPassOutcome {
    do {
      try ChamberSnapshotStore.writeSnapshot(snapshot, workspace: workspace)
      try ChamberSnapshotStore.writeFindingsReport(snapshot, workspace: workspace)
    } catch {
      onEvent(
        HeadlessCompassEvent(
          kind: "chamber_persist_error",
          level: "warning",
          status: "completed",
          phase: AgentPhase.chamber.rawValue,
          message: "Failed to persist chamber snapshot.",
          detail: error.localizedDescription
        )
      )
    }
    let confirmed = snapshot.findings.filter(\.isConfirmedRealBug).count
    onEvent(
      HeadlessCompassEvent(
        kind: "chamber_end",
        level: "success",
        status: "completed",
        phase: AgentPhase.chamber.rawValue,
        message:
          "Chamber pass completed (\(confirmed) confirmed bug(s)).",
        metadata: [
          "findings": "\(snapshot.findings.count)",
          "confirmed": "\(confirmed)",
          "partial": snapshot.partial ? "1" : "0",
        ]
      )
    )
    onLive?(
      LiveEvent(
        level: .success,
        text: "Chamber completed",
        detail: "\(snapshot.findings.count) finding(s), \(confirmed) confirmed",
        kind: .message,
        status: .completed,
        metadata: ["phase": AgentPhase.chamber.rawValue]
      )
    )
    return ChamberPassOutcome(snapshot: snapshot)
  }

  private static func runHunt(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    runtime: any LocalModelGenerating,
    bashRunner: AgentBashRunner,
    recon: ChamberReconResult,
    prior: ChamberSnapshot?,
    sessionNumber: Int,
    budget: ChamberBudget,
    onEvent: @Sendable @escaping (HeadlessCompassEvent) -> Void,
    onLive: (@Sendable (LiveEvent) -> Void)?,
    bindExecutor: (@Sendable (AgentExecutor?) -> Void)?
  ) async throws -> ChamberHuntSubmit {
    let promptMode = ModelRuntimeFactory.promptMode(settings: settings, modelRuntime: runtime)
    let userPrompt = try Prompts.chamberPrompt(
      recon: recon,
      priorSnapshot: prior,
      promptMode: promptMode
    )
    let executor = AgentExecutor { live in
      onLive?(live)
      onEvent(HeadlessCompassEvent(live: live, phase: .chamber))
    }
    bindExecutor?(executor)
    let configuration = AgentExecutionConfiguration(
      settings: settings,
      phase: .chamber,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: .chamber,
        workingDirectoryPath: workspace.repoURL.path,
        executionEnvironment: .macOSVM,
        promptMode: promptMode
      ),
      userPrompt: userPrompt,
      tools: ToolRegistry.tools(for: .chamber, promptMode: promptMode),
      modelRuntime: runtime,
      agentVisibleWorkspacePath: "/workspace",
      submitResultSchema: AgentToolParametersSchema(json: Data(Prompts.chamberSchema.utf8)),
      workingDirectory: workspace.repoURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: bashRunner,
      codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
      planHistoryEntries: [],
      assumptionsURL: workspace.assumptionsURL,
      sessionNumber: sessionNumber,
      promptLogLabelPrefix: "chamber",
      validateSubmitResult: { args in
        _ = try JSONDecoder().decode(ChamberHuntSubmit.self, from: args)
      },
      promptMode: promptMode,
      maxIterations: budget.maxIterations,
      wallClockTimeout: TimeInterval(budget.wallClockSecs)
    )
    let result = try await executor.run(configuration)
    _ = try? workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "chamber-submit-payload.json",
      kind: "phase_submit_payload",
      contents: String(decoding: result.submitResultArguments, as: UTF8.self),
      note: "chamber submit payload."
    )
    return try JSONDecoder().decode(ChamberHuntSubmit.self, from: result.submitResultArguments)
  }
}
