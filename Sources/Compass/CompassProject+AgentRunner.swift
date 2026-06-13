import AppKit
import Foundation
import CompassCore

@MainActor
extension CompassProject {
  func agentLaunchPlan(for nativeExecutionURL: URL) -> AgentExecutionLaunchPlan {
    AgentExecutionLaunchPlan.plan(repoURL: nativeExecutionURL)
  }

  func logExecutionEnvironmentPreflight(
    phase: String,
    nativeExecutionURL: URL,
    launchPlan: AgentExecutionLaunchPlan? = nil,
    sessionIndex: Int? = nil,
    attempt: Int? = nil
  ) {
    let environment = AgentExecutionEnvironment.discover()
    let effectiveLaunchPlan = launchPlan ?? environment.launchPlan(repoURL: nativeExecutionURL)
    log(
      effectiveLaunchPlan.preflightSummary(phase: phase),
      level: .info
    )
    if let sessionIndex {
      recordSessionExecutionEnvironmentSnapshot(
        phase: phase,
        attempt: attempt,
        launchPlan: effectiveLaunchPlan,
        sessionIndex: sessionIndex
      )
    }
    let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
    let detail = [presentation.status, presentation.detail, effectiveLaunchPlan.routeDetail()]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    log(detail, level: presentation.isWarning ? .warning : .info)
  }

  func recordSessionExecutionEnvironmentSnapshot(
    phase: String,
    attempt: Int?,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) {
    guard sessions.indices.contains(sessionIndex) else { return }
    let snapshot = SessionExecutionEnvironmentSnapshot(
      phase: phase,
      attempt: attempt,
      launchPlan: launchPlan
    )
    sessions[sessionIndex].recordExecutionEnvironmentSnapshot(snapshot)
    try? persistSessions()
  }

  /// Build an AgentExecutionConfiguration, run it, and decode the
  /// phase submit payload into the phase result model. Assigns the
  /// executor to `self.executor` so `stopRun()` can cancel mid-stream.
  func runAgent<T: Decodable>(
    phase: AgentPhase,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    workingDirectory: URL,
    userPrompt: String,
    submitResultSchema: String,
    codemapStoreDirectory: URL,
    planHistoryEntries: [String] = [],
    sessionNumber: Int? = nil,
    requiresHostXcode: Bool = false,
    hostXcodeBuildTestEnabled: Bool = false,
    decode: T.Type
  ) async throws -> T {
    let schema = AgentToolParametersSchema(json: Data(submitResultSchema.utf8))
    let environment = resolveAgentEnvironment(forHostURL: workingDirectory)
    let validateSubmitResult = submitResultValidation(
      for: phase,
      hostRepoURL: workingDirectory,
      decode: T.self
    )
    let tools = ToolRegistry.tools(for: phase, settings: agentSettings)
    let configuration = AgentExecutionConfiguration(
      settings: agentSettings,
      phase: phase,
      modelOverride: modelOverride,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: phase,
        workingDirectoryPath: environment.workingDirectory.path,
        executionEnvironment: .containerizedLinux,
        hostXcodeBuildTestEnabled: false,
        externalToolNames: []
      ),
      userPrompt: userPrompt,
      tools: tools,
      submitResultSchema: schema,
      workingDirectory: environment.workingDirectory,
      filesystem: environment.filesystem,
      bashRunner: environment.bashRunner,
      codemapStoreDirectory: codemapStoreDirectory,
      planHistoryEntries: planHistoryEntries,
      assumptionsURL: makeWorkspace(repoURL: workingDirectory).assumptionsURL,
      sessionNumber: sessionNumber,
      validateSubmitResult: validateSubmitResult
    )
    log("\(phase.rawValue.capitalized): starting agent loop.", level: .info)
    let agent = AgentExecutor { [weak self] event in
      Task { @MainActor in self?.log(event) }
    }
    executor = agent
    let result = try await agent.run(configuration)
    if let sessionNumber {
      do {
        let artifactURL = try makeWorkspace(repoURL: workingDirectory).writeSessionAuditArtifact(
          session: sessionNumber,
          name: "\(phase.rawValue)-submit-payload.json",
          kind: "phase_submit_payload",
          contents: String(decoding: result.submitResultArguments, as: UTF8.self),
          note: "\(phase.rawValue) submit payload."
        )
        recordSessionAuditArtifactEvent(
          session: sessionNumber,
          kind: "phase_submit_payload_saved",
          artifactURL: artifactURL,
          note: "Saved \(phase.rawValue) submit payload.",
          metadata: [
            "phase": phase.rawValue,
            "iterations": "\(result.iterations)",
          ]
        )
      } catch {
        appendAuditEvent(
          kind: "phase_submit_payload_save_failed",
          status: "failed",
          text: error.localizedDescription,
          metadata: ["phase": phase.rawValue]
        )
      }
    }
    let decoded: T
    do {
      decoded = try JSONDecoder().decode(T.self, from: result.submitResultArguments)
    } catch {
      let body = String(decoding: result.submitResultArguments, as: UTF8.self)
      throw AppModelError.internalInvariant(
        "Could not decode \(T.self) from phase submit payload: \(error.localizedDescription)\n\(body)"
      )
    }
    if let sessionNumber {
      recordAgentTokenUsage(
        result.tokenUsage,
        phase: phase,
        decodedResult: decoded,
        sessionNumber: sessionNumber
      )
    }
    return decoded
  }

  func recordAgentTokenUsage<T>(
    _ usage: AgentRunTokenUsage,
    phase: AgentPhase,
    decodedResult: T,
    sessionNumber: Int
  ) {
    guard usage.hasUsage,
      let sessionIndex = sessions.firstIndex(where: { $0.session == sessionNumber })
    else { return }

    let phaseUsage = SessionPhaseTokenUsage(
      phase: phase.rawValue,
      usage: usage,
      outcome: tokenOutcome(from: decodedResult)
    )
    sessions[sessionIndex].tokenSummary.record(phaseUsage)
    try? persistSessions()

    let title = phase.rawValue.capitalized
    let source = phaseUsage.usesEstimate ? "estimated" : "provider reported"
    let compaction =
      phaseUsage.compactionCount > 0
      ? " Compactions: \(phaseUsage.compactionCount), summary \(SessionPhaseTokenUsage.formatTokens(phaseUsage.summaryTokens)) tokens."
      : ""
    let retries = phaseUsage.retryCount > 0 ? " Retries: \(phaseUsage.retryCount)." : ""
    log(
      "\(title) used \(SessionPhaseTokenUsage.formatTokens(phaseUsage.inputTokens)) input / \(SessionPhaseTokenUsage.formatTokens(phaseUsage.outputTokens)) output tokens (\(SessionPhaseTokenUsage.formatTokens(phaseUsage.totalTokens)) total, \(source)).\(compaction)\(retries)",
      level: .info
    )
    appendAuditEvent(
      kind: "token_usage",
      status: "completed",
      text: "\(title) token usage recorded.",
      metadata: [
        "phase": phase.rawValue,
        "inputTokens": "\(phaseUsage.inputTokens)",
        "outputTokens": "\(phaseUsage.outputTokens)",
        "totalTokens": "\(phaseUsage.totalTokens)",
        "estimatedTokens": "\(phaseUsage.estimatedTokens)",
        "streamedUsageAvailable": phaseUsage.streamedUsageAvailable ? "true" : "false",
        "compactionCount": "\(phaseUsage.compactionCount)",
        "summaryTokens": "\(phaseUsage.summaryTokens)",
        "retryCount": "\(phaseUsage.retryCount)",
        "outcome": phaseUsage.outcome ?? "",
      ]
    )
  }

  private func tokenOutcome<T>(from decodedResult: T) -> String? {
    if let result = decodedResult as? PlanRunResult {
      return result.state.immediate == nil ? "no_immediate" : "accepted"
    }
    if let result = decodedResult as? DevelopSummary {
      return result.status.rawValue
    }
    if let result = decodedResult as? CriticVerdict {
      return result.verdict.rawValue
    }
    return nil
  }

  /// Reject a phase submit payload in-flight when lesson edits don't match
  /// lessons.md or the payload can't decode into the phase result model.
  func submitResultValidation<T: Decodable>(
    for phase: AgentPhase,
    hostRepoURL: URL,
    decode: T.Type
  ) -> (@Sendable (Data) throws -> Void) {
    let hostWorkspace = makeWorkspace(repoURL: hostRepoURL)
    let validatesLessonEdits = phase == .plan || phase == .develop
    let activeForgeProfile = forgeProfile
    return { args in
      if validatesLessonEdits {
        try hostWorkspace.validateSubmitResultLessonEdits(args)
      }
      let decoded = try JSONDecoder().decode(T.self, from: args)
      if phase == .develop, let developResult = decoded as? DevelopSummary {
        try DevelopFeedbackValidator.validate(developResult)
        try DevelopVerifyBypassValidator.validate(developResult)
      }
      if phase == .critic, let criticResult = decoded as? CriticVerdict {
        try CriticFeedbackValidator.validate(criticResult)
      }
      guard phase == .plan, let planResult = decoded as? PlanRunResult else { return }
      let currentState = try hostWorkspace.readState()
      let nextState = currentState.applying(proposal: planResult.state)
      try PlanTransitionValidator.validate(
        from: currentState,
        to: nextState,
        forgeProfile: activeForgeProfile,
        repoURL: hostRepoURL
      )
    }
  }

  /// Resolved working directory + tool backends for an agent run.
  /// File/search tools operate on the host worktree while bash runs
  /// inside a disposable Linux container with that worktree mounted at
  /// `/workspace`.
  struct AgentEnvironment {
    enum Kind {
      case containerizedLinux
    }
    var kind: Kind
    var workingDirectory: URL
    var filesystem: AgentFilesystem
    var bashRunner: AgentBashRunner
    var launchPlan: AgentExecutionLaunchPlan
  }

  func resolveAgentEnvironment(forHostURL hostURL: URL) -> AgentEnvironment {
    let launchPlan = agentLaunchPlan(for: hostURL)
    log("Agent route: containerized Linux runtime at /workspace.", level: .info)
    return AgentEnvironment(
      kind: .containerizedLinux,
      workingDirectory: hostURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: AgentContainerBashRunner(repoRoot: hostURL, label: "agent"),
      launchPlan: launchPlan
    )
  }

  /// Runs the Verify shell command in the containerized Linux runtime
  /// against the host worktree mounted at `/workspace`.
  func runVerifyCommand(
    command: String,
    hostWorkingDirectory: URL,
    timeoutSeconds: TimeInterval,
    launchPlan: AgentExecutionLaunchPlan,
    requiresHostXcode: Bool = false,
    hostXcodeBuildTestEnabled: Bool = false,
    hostXcodeMirrorRoot: URL? = nil,
    hostRunner: ProcessRunner.InvocationRunner? = nil
  ) async throws -> ProcessResult {
    _ = launchPlan
    _ = requiresHostXcode
    _ = hostXcodeBuildTestEnabled
    _ = hostXcodeMirrorRoot
    _ = hostRunner
    if CompassEngineProcess.shouldUseEmbeddedTessera(command: command, forgeProfile: forgeProfile) {
      log(
        "Verify: running embedded Tessera engine (timeout \(Int(timeoutSeconds * 1000))ms).",
        level: .info
      )
      return try await CompassEngineProcess.verifyProject(root: hostWorkingDirectory)
    }
    log(
      "Verify: running inside containerized Linux runtime at /workspace (timeout \(Int(timeoutSeconds * 1000))ms).",
      level: .info
    )
    return try await AgentContainerBashRunner(
      repoRoot: hostWorkingDirectory,
      label: "verify"
    ).run(
      command: command,
      workingDirectory: hostWorkingDirectory,
      timeout: timeoutSeconds
    )
  }

  /// Pulls the container workspace's current state (filtered against the
  /// well-known build-output dirs) back onto the host's main repo.
  /// Retained for compatibility with the old promotion flow. Container
  /// writes already land in the host worktree.
  ///
  /// Pull failures are logged but not thrown: the subsequent
  /// `git status` will surface "nothing to commit" or partial state
  /// instead of dropping the entire iteration on a transient
  /// transport hiccup.
  func pullDevelopChangesIfNeeded(
    mainRepoURL: URL,
    plan: AgentExecutionLaunchPlan
  ) async {
    _ = mainRepoURL
    _ = plan
  }

  /// Pushes the committed container HEAD to the Compass exchange repo and
  /// fast-forwards the host checkout from that staging ref. Returns a
  /// human-readable issue on failure so the Develop loop can stop
  /// cleanly instead of silently losing agent commits.
  func promoteDevelopChangesIfNeeded(
    mainRepoURL: URL,
    plan: AgentExecutionLaunchPlan,
    sessionNumber: Int,
    verifyPassed: Bool
  ) async -> String? {
    _ = mainRepoURL
    _ = plan
    _ = sessionNumber
    _ = verifyPassed
    return nil
  }
}
