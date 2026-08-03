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
    decode: T.Type
  ) async throws -> T {
    let schema = AgentToolParametersSchema(json: Data(submitResultSchema.utf8))
    let environment = resolveAgentEnvironment(forHostURL: workingDirectory)
    let validateSubmitResult = submitResultValidation(
      for: phase,
      hostRepoURL: workingDirectory,
      decode: T.self
    )
    let modelRuntime = ModelRuntimeFactory.makeRouted(settings: agentSettings)
    let promptMode = ModelRuntimeFactory.promptMode(
      settings: agentSettings,
      modelRuntime: modelRuntime
    )
    let tools = ToolRegistry.tools(for: phase, promptMode: promptMode)
    let configuration = AgentExecutionConfiguration(
      settings: agentSettings,
      phase: phase,
      modelOverride: modelOverride,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: phase,
        workingDirectoryPath: environment.workingDirectory.path,
        executionEnvironment: .macOSVM,
        externalToolNames: [],
        promptMode: promptMode
      ),
      userPrompt: userPrompt,
      tools: tools,
      modelRuntime: modelRuntime,
      agentVisibleWorkspacePath: "/workspace",
      submitResultSchema: schema,
      workingDirectory: environment.workingDirectory,
      filesystem: environment.filesystem,
      bashRunner: environment.bashRunner,
      codemapStoreDirectory: codemapStoreDirectory,
      planHistoryEntries: planHistoryEntries,
      assumptionsURL: makeWorkspace(repoURL: workingDirectory).assumptionsURL,
      sessionNumber: sessionNumber,
      validateSubmitResult: validateSubmitResult,
      promptMode: promptMode
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
        repoURL: hostRepoURL
      )
    }
  }

  /// Resolved working directory + tool backends for an agent run.
  /// File/search tools operate on the host worktree while bash runs
  /// inside the embedded macOS VM against a synced copy of that
  /// worktree (`/workspace` paths in commands are rewritten to the
  /// guest worktree).
  struct AgentEnvironment {
    enum Kind {
      case macOSVM
    }
    var kind: Kind
    var workingDirectory: URL
    var filesystem: AgentFilesystem
    var bashRunner: AgentBashRunner
    var launchPlan: AgentExecutionLaunchPlan
  }

  func resolveAgentEnvironment(forHostURL hostURL: URL) -> AgentEnvironment {
    let launchPlan = agentLaunchPlan(for: hostURL)
    log("Agent route: embedded macOS VM at /workspace.", level: .info)
    return AgentEnvironment(
      kind: .macOSVM,
      workingDirectory: hostURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: AgentMacOSVMBashRunner(repoRoot: hostURL, label: "agent"),
      launchPlan: launchPlan
    )
  }

  /// Runs the Verify shell command inside the embedded macOS VM against
  /// the synced guest worktree.
  func runVerifyCommand(
    command: String,
    hostWorkingDirectory: URL,
    timeoutSeconds: TimeInterval,
    launchPlan: AgentExecutionLaunchPlan
  ) async throws -> ProcessResult {
    _ = launchPlan
    log(
      "Verify: running inside the macOS VM (timeout \(Int(timeoutSeconds * 1000))ms).",
      level: .info
    )
    return try await AgentMacOSVMBashRunner(
      repoRoot: hostWorkingDirectory,
      label: "verify"
    ).run(
      command: command,
      workingDirectory: hostWorkingDirectory,
      timeout: timeoutSeconds
    )
  }
}
