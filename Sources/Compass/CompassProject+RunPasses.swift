import AppKit
import Foundation

@MainActor
extension CompassProject {
  func runPlanPass(
    continueToDevelop: Bool,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String
  ) async {
    let workspace: CompassWorkspace
    do {
      workspace = try await resolveWorkspaceForRun()
    } catch {
      fail(error)
      return
    }

    do {
      try await initializeIfNeeded(workspace)
    } catch {
      fail(error)
      return
    }

    isRunning = true
    phase = .planning
    errorMessage = nil
    let sessionIndex = startSession()
    guard sessions.indices.contains(sessionIndex) else {
      fail(AppModelError.internalInvariant("Could not start a Compass session."))
      isRunning = false
      phase = .failed
      return
    }
    let sessionNumber = sessions[sessionIndex].session
    var consumedDrafts = ""

    do {
      try await commitPendingHostChangesIfNeeded(
        workspace: workspace,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        sessionIndex: sessionIndex
      )
      try workspace.backupStateFile()
      await refreshCodemapIfNeeded(
        workspace: workspace,
        sessionNumber: sessionNumber,
        agentSettings: agentSettings
      )
      try await runReflectIfNeeded(
        workspace,
        sessionIndex: sessionIndex,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )

      let priorFeedback = previousFeedback(excluding: sessionNumber)
      consumedDrafts = try workspace.snapshotAndClearDrafts()
      drafts = ""

      var currentState = try workspace.readState()
      let recordedState = PlanCompletionRecorder.recordingShippedIterations(
        into: currentState,
        sessions: sessions
      )
      if recordedState != currentState {
        try workspace.writeState(recordedState)
        currentState = recordedState
        state = recordedState
      }

      log(
        "Plan input: \(workspace.stateURL.path) (\(currentState.completed.count) completed, immediate: \(firstLine(currentState.immediate?.plan) ?? "none")).",
        level: .info
      )

      let focus = PlanFocus.weightedRandom()
      log("Plan focus this iteration: \(focus.displayName).", level: .info)

      let visionText = workspace.readVision()
      let productPainText = [visionText, consumedDrafts]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
      let productTournamentConfigForPrompt = try workspace.readOrSeedProductTournamentConfig(
        projectTitle: workspace.repoURL.lastPathComponent,
        rawPain: productPainText.isEmpty ? visionText : productPainText
      )
      let prompt = try Prompts.planPrompt(
        state: currentState.proposal,
        completedCount: currentState.completed.count,
        drafts: consumedDrafts,
        feedback: priorFeedback,
        lessons: workspace.readLessons(),
        assumptions: try workspace.readAssumptionLedger().formattedForPrompt(),
        vision: visionText,
        focus: focus,
        forgeProfile: forgeProfile,
        coverageSnapshot: ForgeProfileService.readCoverageSnapshot(from: workspace),
        productTournamentConfig: productTournamentConfigForPrompt,
        productTournamentEvidenceIndex: workspace.readProductTournamentEvidenceIndex(),
        hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
      )
      let promptURL = try workspace.writeSessionArtifact(
        session: sessionNumber,
        name: "plan-prompt.md",
        contents: prompt
      )
      log("Saved Plan prompt: \(promptURL.path)", level: .info)

      let launchPlan = agentLaunchPlan(for: workspace.repoURL)
      logExecutionEnvironmentPreflight(
        phase: "Plan",
        nativeExecutionURL: workspace.repoURL,
        launchPlan: launchPlan,
        sessionIndex: sessionIndex
      )
      log("Plan: launching agent.", level: .info)
      let planResult = try await runAgent(
        phase: .plan,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        workingDirectory: workspace.repoURL,
        userPrompt: prompt,
        submitResultSchema: Prompts.planSchema(
          hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
        ),
        codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
        planHistoryEntries: currentState.completed,
        sessionNumber: sessionNumber,
        decode: PlanRunResult.self
      )
      let nextState = currentState.applying(proposal: planResult.state)

      try validatePlanTransition(
        from: currentState,
        to: nextState,
        productTournamentConfig: productTournamentConfigForPrompt
      )
      let lessonEditCount = try workspace.applyLessonEdits(planResult.lessonEdits)
      try workspace.writeState(nextState)
      logLessonEdits(lessonEditCount)
      state = nextState
      log(
        "Plan accepted: \(nextState.completed.count) completed, immediate: \(firstLine(nextState.immediate?.plan) ?? "none").",
        level: .success
      )
      feedback(.planAccepted)
      guard sessions.indices.contains(sessionIndex) else {
        throw AppModelError.internalInvariant("Session #\(sessionNumber) disappeared during Plan.")
      }
      sessions[sessionIndex].plan = nextState.immediate?.plan
      sessions[sessionIndex].verify = nextState.immediate?.verify
      recordProductTournamentPlanMetadata(
        for: nextState.immediate,
        productTournamentConfig: productTournamentConfigForPrompt,
        sessionIndex: sessionIndex
      )
      try persistSessions()

      if nextState.immediate == nil {
        endSession(sessionIndex, status: .skipped)
        phase = .idle
        log("Plan returned no immediate work.", level: .info)
        feedback(.noImmediateWork)
        isRunning = false
        executor = nil
        await refresh()
        return
      }

      log("Plan selected: \(immediateTitle)", level: .success)

      if continueToDevelop {
        if isPaused && pauseMode == .immediate {
          guard sessions.indices.contains(sessionIndex) else {
            throw AppModelError.internalInvariant(
              "Session #\(sessionNumber) disappeared while pausing.")
          }
          sessions[sessionIndex].status = .awaitingApproval
          sessions[sessionIndex].endedAt = nil
          try persistSessions()
          try? workspace.updateSessionAuditManifest(
            session: sessionNumber,
            status: .awaitingApproval,
            startedAt: sessions[sessionIndex].startedAt,
            endedAt: nil
          )
          appendAuditEvent(
            kind: "session_paused",
            status: SessionStatus.awaitingApproval.rawValue,
            text: "Session #\(sessionNumber) paused before Develop."
          )
          deactivateSessionAuditIfCurrent(session: sessionNumber)
          phase = .paused
          log("Paused before Develop.", level: .warning)
          feedbackPlanReadinessGate(for: nextState, gate: .pausedBeforeDevelop)
          isRunning = false
          executor = nil
          await refresh()
          return
        }

        isRunning = false
        executor = nil
        await runDevelopPass(
          existingSessionIndex: sessionIndex,
          agentSettings: agentSettings,
          modelOverride: modelOverride
        )
      } else {
        appendSessionNote("Plan-only run; Develop was not started.", to: sessionIndex)
        endSession(sessionIndex, status: .awaitingApproval)
        phase = .idle
        feedbackPlanReadinessGate(for: nextState, gate: .planOnly)
        isRunning = false
        executor = nil
      }
    } catch {
      if !consumedDrafts.isEmpty {
        let current = workspace.readDrafts()
        try? workspace.writeDrafts(
          [consumedDrafts, current].filter { !$0.isEmpty }.joined(separator: "\n"))
      }
      performSessionErrorCleanup(sessionIndex: sessionIndex, error: error)
    }

    await refresh()
  }

  func runDevelopPass(
    existingSessionIndex: Int?,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String
  ) async {
    let workspace: CompassWorkspace
    do {
      workspace = try await resolveWorkspaceForRun()
    } catch {
      fail(error)
      return
    }

    do {
      try await initializeIfNeeded(workspace)
      state = try workspace.readState()
    } catch {
      fail(error)
      return
    }

    guard let next = state.immediate else {
      log("No immediate plan to develop.", level: .warning)
      feedback(.noImmediateWork)
      return
    }

    let repairGuide = PlanHandoffRepairGuide(
      plan: next.plan,
      verify: next.verify,
      languageProfile: languageProfile,
      forgeProfile: forgeProfile
    )
    guard repairGuide.status == .ready else {
      let missing = repairGuide.steps
        .filter { $0.isRequired && !$0.isSatisfied }
        .map(\.title)
      let missingLabel =
        missing.isEmpty
        ? "an executable handoff"
        : missing.joined(separator: " and ")
      let message = "Develop needs a stronger handoff. Add \(missingLabel) before editing."
      errorMessage = message
      log("\(message) \(repairGuide.detail)", level: .warning)
      return
    }

    isRunning = true
    phase = .developing
    errorMessage = nil
    let sessionIndex = existingSessionIndex ?? startSession()
    guard sessions.indices.contains(sessionIndex) else {
      fail(AppModelError.internalInvariant("Could not start a Develop session."))
      isRunning = false
      phase = .failed
      return
    }
    activateSessionAudit(sessionIndex: sessionIndex)
    sessions[sessionIndex].status = .developing
    sessions[sessionIndex].endedAt = nil
    sessions[sessionIndex].plan = next.plan
    sessions[sessionIndex].verify = next.verify
    try? persistSessions()
    feedback(.developStarted)

    do {
      try await commitPendingHostChangesIfNeeded(
        workspace: workspace,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        sessionIndex: sessionIndex
      )
    } catch {
      performSessionErrorCleanup(sessionIndex: sessionIndex, error: error)
      await refresh()
      return
    }

    let beforeSha = await gitCurrentSha(at: workspace.repoURL)
    sessions[sessionIndex].beforeSha = beforeSha
    try? persistSessions()

    await refreshCodemapIfNeeded(
      workspace: workspace,
      sessionNumber: sessions[sessionIndex].session,
      agentSettings: agentSettings
    )

    do {
      // The Develop iteration operates directly on `workspace.repoURL`.
      // Under the `.sharedVM` route the route layer remaps that URL
      // through `SharedCompassVMGuestWorkspaceCatalog` to a persistent
      // per-repo guest workspace under `/Users/compass/Compass/Repos/
      // <UUID>/worktree` and the agent runs there; under the host
      // route the agent runs in the user's working tree directly.
      // Either way, only one workspace handle is in play per
      // iteration, so Develop and Verify can't desynchronize onto
      // different catalog entries.

      var finalIssues: [String] = []
      var finalVerifyOutput: VerifyOutput?
      var succeeded = false
      var developHandOffToPlan = false
      var lastDevelopFeedback = ""
      var criticFeedbacks: [String] = []
      var criticAttempt = 0

      // Outer loop: adversarial Critic review gates each successful
      // Develop+post-check pass. On critic-reject Develop re-runs with
      // the critic's feedback added until the critic approves or the
      // user stops the run.
      criticLoop: while true {
        var priorIssues: [String] = []
        var postChecksPassed = false
        var postCheckSummary: DevelopSummary?
        var postCheckLaunchPlan: AgentExecutionLaunchPlan?
        var lastAttemptSummary: DevelopSummary?
        var lastAttemptLaunchPlan: AgentExecutionLaunchPlan?
        var lastPostCheckResult: PostCheckResult?

        for attempt in 1...maxDevelopAttempts {
          if stopRequested {
            break criticLoop
          }
          phase = .developing
          let prompt = Prompts.developPrompt(
            next: next,
            lessons: workspace.readLessons(),
            assumptions: try workspace.readAssumptionLedger().formattedForPrompt(),
            vision: workspace.readVision(),
            attempt: attempt,
            priorIssues: priorIssues,
            criticFeedback: criticFeedbacks,
            hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
          )

          let launchPlan = agentLaunchPlan(for: workspace.repoURL)
          logExecutionEnvironmentPreflight(
            phase: "Develop",
            nativeExecutionURL: workspace.repoURL,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex,
            attempt: attempt
          )
          log(
            "Develop: launching agent (attempt \(attempt)/\(maxDevelopAttempts), critic cycle \(criticAttempt + 1)/\(maxCriticAttempts)).",
            level: .info
          )
          let summary: DevelopSummary
          do {
            summary = try await runAgent(
              phase: .develop,
              agentSettings: agentSettings,
              modelOverride: modelOverride,
              workingDirectory: workspace.repoURL,
              userPrompt: prompt,
              submitResultSchema: Prompts.developSchema,
              codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
              sessionNumber: sessions[sessionIndex].session,
              requiresHostXcode: next.requiresHostXcode,
              hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled,
              decode: DevelopSummary.self
            )
          } catch let error as AgentExecutionError where error.isAgentBudgetExhaustion {
            // The agent ran out of wall-clock budget or iterations
            // mid-attempt. Treat that as a failed attempt with
            // budget-exhaustion context so the next attempt starts
            // fresh, rather than aborting the whole Develop pass.
            let note =
              "Develop attempt \(attempt) ended without submit_result: \(error.localizedDescription)."
            log(note, level: .warning)
            appendSessionNote(note, to: sessionIndex)
            priorIssues = [note]
            finalIssues = [note]
            if attempt < maxDevelopAttempts {
              feedback(.developRetrying)
            }
            continue
          }

          // Under the `.sharedVM` route the agent worked in the
          // guest workspace and Verify ran there too. We defer the
          // host-side pull and commit until Verify passes (and the
          // Critic approves) so failed attempts don't leave the main
          // repo dirty. Under the host route the agent already
          // committed in place using its own `git` tool.

          guard sessions.indices.contains(sessionIndex) else {
            throw AppModelError.internalInvariant("Develop session disappeared during agent run.")
          }
          lastAttemptSummary = summary
          sessions[sessionIndex].feedback = summary.feedback
          lastDevelopFeedback = summary.feedback
          appendSessionNote(summary.summary, to: sessionIndex)

          let post = try await runPostChecks(
            next: next,
            summary: summary,
            workingDirectory: workspace.repoURL,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex,
            attempt: attempt,
            beforeSha: beforeSha
          )
          finalIssues = post.verifyIssues + post.gitStatusIssues
          finalVerifyOutput = post.verifyOutput
          lastPostCheckResult = post
          lastAttemptLaunchPlan = launchPlan
          if sessions.indices.contains(sessionIndex) {
            sessions[sessionIndex].verifyOutput = post.verifyOutput
          }
          try? persistSessions()

          if post.requiresPlanRepair {
            developHandOffToPlan = true
            break criticLoop
          }

          if post.ok {
            postChecksPassed = true
            postCheckSummary = summary
            postCheckLaunchPlan = launchPlan
            break
          }

          priorIssues = post.verifyIssues + post.gitStatusIssues
          if attempt < maxDevelopAttempts {
            feedback(.developRetrying)
            log("Develop post-checks failed; retrying with failure context.", level: .warning)
          }
        }

        if stopRequested {
          break criticLoop
        }

        guard postChecksPassed,
          let summary = postCheckSummary,
          let launchPlan = postCheckLaunchPlan
        else {
          if let summary = lastAttemptSummary,
            let launchPlan = lastAttemptLaunchPlan,
            let post = lastPostCheckResult,
            post.gitStatusIssues.isEmpty,
            SharedCompassVMGitStateStore.context(forHostRepoURL: workspace.repoURL) != nil
          {
            let note =
              "Develop exhausted \(maxDevelopAttempts) attempts without passing Verify; promoting the latest committed guest state anyway."
            appendSessionNote(note, to: sessionIndex)
            log(note, level: .warning)
            if let issue = await promoteDevelopChangesIfNeeded(
              mainRepoURL: workspace.repoURL,
              plan: launchPlan,
              sessionNumber: sessions[sessionIndex].session,
              verifyPassed: false
            ) {
              finalIssues.append(issue)
              succeeded = false
            } else if let commitIssue = await landDevelopChanges(
              workspace: workspace,
              summary: summary,
              launchPlan: launchPlan,
              sessionIndex: sessionIndex
            ) {
              finalIssues.append(commitIssue)
              succeeded = false
            } else {
              succeeded = true
              feedback(.commitsPromoted)
            }
            break criticLoop
          }
          // Post-checks failed after every Develop attempt and either
          // the guest still has git-status issues or this workspace is
          // on the legacy tar-sync fallback, where failed-Verify commits
          // cannot be preserved safely. Hand the failure context to Plan.
          developHandOffToPlan = true
          break criticLoop
        }

        // Promote the committed guest state to the host before Critic
        // so existing host-side diff machinery can review real commits.
        // If Critic rejects, the next Develop attempt builds on those
        // commits and lands follow-up commits rather than rewriting
        // history behind the user's checkout.
        if let issue = await promoteDevelopChangesIfNeeded(
          mainRepoURL: workspace.repoURL,
          plan: launchPlan,
          sessionNumber: sessions[sessionIndex].session,
          verifyPassed: true
        ) {
          finalIssues = [issue]
          succeeded = false
          break criticLoop
        }

        if case .sharedVM = launchPlan.effectiveRoute,
          SharedCompassVMGitStateStore.context(forHostRepoURL: workspace.repoURL) == nil
        {
          await pullDevelopChangesIfNeeded(
            mainRepoURL: workspace.repoURL,
            plan: launchPlan
          )
        }

        criticAttempt += 1
        let verdict = await runCriticPass(
          next: next,
          developSummary: summary,
          verifyOutput: finalVerifyOutput,
          beforeSha: beforeSha,
          priorCritiques: criticFeedbacks,
          workspace: workspace,
          agentSettings: agentSettings,
          modelOverride: modelOverride,
          iteration: criticAttempt,
          sessionIndex: sessionIndex
        )

        if verdict.verdict == .approve {
          if let commitIssue = await landDevelopChanges(
            workspace: workspace,
            summary: summary,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex
          ) {
            finalIssues = [commitIssue]
            succeeded = false
          } else {
            succeeded = true
            feedback(.commitsPromoted)
          }
          break criticLoop
        }

        // Reject + budget remains: queue another Develop pass.
        criticFeedbacks.append(
          "Critic review \(criticAttempt) requested changes:\n\(verdict.feedback)")
        feedback(.developRetrying)
      }

      if stopRequested {
        performSessionErrorCleanup(sessionIndex: sessionIndex, error: nil)
        await refresh()
        return
      }

      for issue in finalIssues {
        appendSessionNote(issue, to: sessionIndex)
      }
      guard sessions.indices.contains(sessionIndex) else {
        throw AppModelError.internalInvariant("Develop session disappeared before completion.")
      }
      if developHandOffToPlan {
        sessions[sessionIndex].feedback = developFailureFeedbackForPlan(
          next: next,
          issues: finalIssues,
          developFeedback: lastDevelopFeedback,
          attempts: maxDevelopAttempts
        )
      }
      sessions[sessionIndex].verifyOutput = finalVerifyOutput
      let afterSha = await gitCurrentSha(at: workspace.repoURL)
      sessions[sessionIndex].afterSha = afterSha
      sessions[sessionIndex].commits = await gitCommits(
        in: workspace.repoURL,
        from: beforeSha,
        to: afterSha
      )

      endSession(sessionIndex, status: succeeded ? .succeeded : .failed)
      if developHandOffToPlan {
        phase = .idle
        log(
          "Develop post-checks failed after \(maxDevelopAttempts) attempts; handing off to Plan.",
          level: .warning
        )
        feedback(.postChecksFailed)
      } else {
        phase = succeeded ? .succeeded : .failed
        log(
          succeeded ? "Develop completed." : "Develop finished with failed post-checks.",
          level: succeeded ? .success : .error
        )
        if !succeeded {
          feedback(.postChecksFailed)
        }
      }

      if isPaused {
        phase = .paused
        log("Paused after iteration.", level: .warning)
        feedback(.paused)
      }
    } catch {
      performSessionErrorCleanup(sessionIndex: sessionIndex, error: error)
    }

    isRunning = false
    executor = nil
    await refresh()
  }

  func runReflectIfNeeded(
    _ workspace: CompassWorkspace,
    sessionIndex: Int,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String
  ) async throws {
    guard sessions.indices.contains(sessionIndex) else { return }
    let cadence = reflectEvery()
    guard cadence > 0, sessions[sessionIndex].session % cadence == 0 else { return }

    let iteration = sessions[sessionIndex].session
    let recentSessions =
      sessions
      .filter { $0.session != iteration && $0.endedAt != nil }
      .sorted { $0.startedAt > $1.startedAt }
      .prefix(reflectSessionWindow)

    let visionText = workspace.readVision()
    let productTournamentConfigForPrompt = try workspace.readOrSeedProductTournamentConfig(
      projectTitle: workspace.repoURL.lastPathComponent,
      rawPain: visionText
    )
    let prompt = try Prompts.reflectPrompt(
      state: workspace.readState().proposal,
      lessons: workspace.readLessons(),
      assumptions: try workspace.readAssumptionLedger().formattedForPrompt(),
      vision: visionText,
      recentSessions: Array(recentSessions),
      iteration: iteration,
      productTournamentConfig: productTournamentConfigForPrompt,
      productTournamentEvidenceIndex: workspace.readProductTournamentEvidenceIndex(),
      hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
    )

    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    logExecutionEnvironmentPreflight(
      phase: "Reflect",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex
    )
    log("Reflect: launching agent.", level: .info)
    let result = try await runAgent(
      phase: .reflect,
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      workingDirectory: workspace.repoURL,
      userPrompt: prompt,
      submitResultSchema: Prompts.reflectSchema(
        hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
      ),
      codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
      sessionNumber: iteration,
      decode: ReflectSummary.self
    )

    let tournamentDecisionUpdateCount = try applyProductTournamentDecisionUpdates(
      result.tournamentDecisionUpdates,
      from: productTournamentConfigForPrompt,
      workspace: workspace,
      sessionIndex: sessionIndex
    )
    let lessonEditCount = try workspace.applyLessonEdits(result.lessonEdits)
    if let reflectedProposal = result.state {
      let currentState = try workspace.readState()
      let mergedState = currentState.applying(proposal: reflectedProposal)
      try workspace.writeState(mergedState)
      state = mergedState
      log("Reflect updated state.json: \(result.summary)", level: .success)
    } else {
      log("Reflect: \(result.summary)", level: .info)
    }
    logLessonEdits(lessonEditCount)
    if tournamentDecisionUpdateCount > 0 {
      log(
        "Reflect updated \(tournamentDecisionUpdateCount) tournament experiment decision(s).",
        level: .success
      )
    }
  }

  func reflectEvery() -> Int {
    let raw = ProcessInfo.processInfo.environment["COMPASS_REFLECT_EVERY"]
    guard let raw, !raw.isEmpty, let parsed = Int(raw), parsed >= 0 else {
      return 5
    }
    return parsed
  }

  /// Run one Critic review pass against the Develop output that just
  /// passed post-checks. Always returns a verdict — Critic infrastructure
  /// failures (network, schema decode) log a warning and fall through to
  /// an `.approve` verdict so a flaky review path can't strand an
  /// otherwise-good Develop iteration.
  func runCriticPass(
    next: PlanNext,
    developSummary: DevelopSummary,
    verifyOutput: VerifyOutput?,
    beforeSha: String?,
    priorCritiques: [String],
    workspace: CompassWorkspace,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    iteration: Int,
    sessionIndex: Int
  ) async -> CriticVerdict {
    phase = .reviewing
    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    logExecutionEnvironmentPreflight(
      phase: "Critic",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex,
      attempt: iteration
    )
    log("Critic: launching review \(iteration)/\(maxCriticAttempts).", level: .info)

    let diff = await gitDiffSinceSha(beforeSha, in: workspace.repoURL)
    let verifyOutputText = verifyOutput?.tail ?? ""
    let verifyExitCode = verifyOutput?.exitCode
    let prompt = Prompts.criticPrompt(
      next: next,
      developSummary: developSummary,
      verifyCommand: next.verify,
      verifyExitCode: verifyExitCode,
      verifyOutput: verifyOutputText,
      gitDiff: diff,
      priorCritiques: priorCritiques,
      lessons: workspace.readLessons(),
      assumptions: (try? workspace.readAssumptionLedger().formattedForPrompt()) ?? "",
      vision: workspace.readVision(),
      forgeProfile: forgeProfile,
      iteration: iteration,
      maxIterations: maxCriticAttempts
    )

    let verdict: CriticVerdict
    do {
      verdict = try await runAgent(
        phase: .critic,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        workingDirectory: workspace.repoURL,
        userPrompt: prompt,
        submitResultSchema: Prompts.criticSchema,
        codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
        sessionNumber: sessions.indices.contains(sessionIndex)
          ? sessions[sessionIndex].session
          : nil,
        decode: CriticVerdict.self
      )
    } catch {
      let note =
        "Critic pass failed: \(error.localizedDescription); accepting Develop output."
      log(note, level: .warning)
      appendSessionNote(note, to: sessionIndex)
      return CriticVerdict(verdict: .approve, summary: "critic pass failed", feedback: "")
    }

    let level: LiveLine.Level = verdict.verdict == .approve ? .success : .warning
    let note =
      "Critic \(iteration)/\(maxCriticAttempts): \(verdict.verdict.rawValue) — \(verdict.summary)"
    log(note, level: level)
    appendSessionNote(note, to: sessionIndex)
    return verdict
  }

  func validatePlanTransition(
    from current: PlanState,
    to next: PlanState,
    productTournamentConfig: ProductTournamentConfig? = nil
  ) throws {
    do {
      try PlanTransitionValidator.validate(
        from: current,
        to: next,
        forgeProfile: forgeProfile,
        productTournamentConfig: productTournamentConfig
      )
    } catch let error as PlanTransitionValidationError {
      throw AppModelError.rejectedPlan(error.message)
    }
  }

  func applyProductTournamentDecisionUpdates(
    _ updates: [ProductTournamentReflectDecisionUpdate],
    from currentConfig: ProductTournamentConfig,
    workspace: CompassWorkspace,
    sessionIndex: Int
  ) throws -> Int {
    guard !updates.isEmpty else { return 0 }
    let nextConfig = try ProductTournamentReflectDecisionApplier.applying(
      updates,
      to: currentConfig
    )
    try workspace.writeProductTournamentConfig(nextConfig)
    productTournamentConfig = nextConfig

    recordProductTournamentDecisionMetadata(
      updates,
      previousConfig: currentConfig,
      nextConfig: nextConfig,
      sessionIndex: sessionIndex
    )
    try persistSessions()
    return updates.count
  }

  func recordProductTournamentPlanMetadata(
    for immediate: PlanNext?,
    productTournamentConfig: ProductTournamentConfig,
    sessionIndex: Int
  ) {
    guard sessions.indices.contains(sessionIndex), let immediate else { return }
    let experimentIDs = productTournamentExperimentIDs(
      mentionedIn: [
        immediate.plan,
        immediate.selectedBecause,
        immediate.candidateID,
      ]
      .compactMap { $0 }
      .joined(separator: "\n"),
      productTournamentConfig: productTournamentConfig
    )
    guard experimentIDs.count == 1,
      let experiment = productTournamentConfig.tournamentExperiments.first(where: {
        $0.id == experimentIDs[0]
      })
    else { return }

    sessions[sessionIndex].tournamentExperimentID = experiment.id
    sessions[sessionIndex].tournamentContenderPlanID = experiment.contenderPlanID
    sessions[sessionIndex].tournamentPainID = productTournamentPainID(
      forContenderPlanID: experiment.contenderPlanID,
      config: productTournamentConfig
    )
    sessions[sessionIndex].tournamentExperimentBranchName = experiment.branchName
    sessions[sessionIndex].tournamentExperimentCommitSha =
      experiment.currentSha ?? experiment.baseSha
    sessions[sessionIndex].tournamentExperimentBeforeSha =
      experiment.currentSha ?? experiment.baseSha
    sessions[sessionIndex].tournamentDecision = experiment.decision
  }

  func recordProductTournamentDecisionMetadata(
    _ updates: [ProductTournamentReflectDecisionUpdate],
    previousConfig: ProductTournamentConfig,
    nextConfig: ProductTournamentConfig,
    sessionIndex: Int
  ) {
    guard sessions.indices.contains(sessionIndex), let latest = updates.last,
      let experiment = nextConfig.tournamentExperiments.first(where: {
        $0.id == latest.experimentID
      })
    else { return }

    let previousExperiment = previousConfig.tournamentExperiments.first {
      $0.id == latest.experimentID
    }
    sessions[sessionIndex].tournamentExperimentID = experiment.id
    sessions[sessionIndex].tournamentContenderPlanID = experiment.contenderPlanID
    sessions[sessionIndex].tournamentPainID = productTournamentPainID(
      forContenderPlanID: experiment.contenderPlanID,
      config: nextConfig
    )
    sessions[sessionIndex].tournamentExperimentBranchName = experiment.branchName
    sessions[sessionIndex].tournamentExperimentCommitSha =
      experiment.currentSha ?? experiment.baseSha
    sessions[sessionIndex].tournamentExperimentBeforeSha =
      previousExperiment?.currentSha ?? previousExperiment?.baseSha
    sessions[sessionIndex].tournamentExperimentAfterSha =
      experiment.currentSha ?? experiment.baseSha
    sessions[sessionIndex].tournamentEvidenceRunIDs = Array(
      Set(updates.flatMap(\.evidenceRunIDs))
    )
    .sorted()
    sessions[sessionIndex].tournamentDecision = latest.decision
  }

  private func productTournamentPainID(
    forContenderPlanID contenderPlanID: String,
    config: ProductTournamentConfig
  ) -> String? {
    config.contenderPlans.first { $0.id == contenderPlanID }?.painID
  }

  private func productTournamentExperimentIDs(
    mentionedIn text: String,
    productTournamentConfig: ProductTournamentConfig
  ) -> [String] {
    let normalizedText = normalizedProductTournamentMatchText(text)
    guard !normalizedText.isEmpty else { return [] }
    var matches: [String] = []
    for experiment in productTournamentConfig.tournamentExperiments {
      let tokens = [
        experiment.id,
        experiment.branchName,
        experiment.worktreeID,
        experiment.title,
      ]
      .map(normalizedProductTournamentMatchText)
      .filter { $0.count >= 3 }
      if tokens.contains(where: { normalizedText.contains($0) }) {
        matches.append(experiment.id)
      }
    }
    return Array(Set(matches)).sorted()
  }

  private func normalizedProductTournamentMatchText(_ text: String) -> String {
    text
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9/._-]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func runPostChecks(
    next: PlanNext,
    summary: DevelopSummary,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int,
    attempt: Int,
    beforeSha: String?
  ) async throws -> PostCheckResult {
    var verifyIssues: [String] = []
    var gitStatusIssues: [String] = []
    var verifyOutput: VerifyOutput?
    var requiresPlanRepair = false
    var verifyPassed = false

    switch summary.status {
    case .succeeded:
      break
    case .blocked:
      if summary.bypassVerify != true {
        verifyIssues.append(
          "[verify] Develop reported it was blocked but did not request verify bypass.")
      }
    case .failed:
      verifyIssues.append("[verify] Develop reported failure: \(summary.feedback)")
    }

    let autoRepair = VerifyBypassAutoRepair.repair(
      plannedCommand: next.verify,
      developSummary: summary,
      forgeProfile: forgeProfile
    )
    if summary.bypassVerify == true, let autoRepair {
      log(
        "Post-check: auto-repairing verify bypass with `\(autoRepair.command)`.",
        level: .warning
      )
      appendSessionNote(
        """
        [verify] Auto-repaired Develop verify bypass (\(autoRepair.reason.rawValue)).
        Planned verify command: `\(next.verify)`
        Repaired verify command: `\(autoRepair.command)`
        \(autoRepair.note)
        """,
        to: sessionIndex
      )
    }

    if summary.bypassVerify == true, autoRepair == nil {
      requiresPlanRepair = true
      let issue = """
        [verify] Verify was skipped because Develop reported the planned command is wrong or out of scope.
        Planned verify command: `\(next.verify)`
        Develop handoff: \(summary.feedback)
        Plan should replace the verify command or rescope Immediate Work before Develop continues.
        """
      verifyIssues.append(issue)
      log(
        "Post-check: skipping verify per Develop bypassVerify=true; handing back to Plan.",
        level: .warning
      )
    } else {
      let verifyCommand = autoRepair?.command ?? next.verify
      phase = .verifying
      let timeoutMs = verifyTimeoutMs(for: next)
      logExecutionEnvironmentPreflight(
        phase: "Verify",
        nativeExecutionURL: workingDirectory,
        launchPlan: launchPlan,
        sessionIndex: sessionIndex,
        attempt: attempt
      )
      log(
        "Post-check: running verify command `\(verifyCommand)` (timeout \(timeoutMs)ms).",
        level: .info)
      feedback(.verifyStarted)
      // Verify runs in the same workspace the agent just operated
      // on. For .sharedVM that means inside the guest via the
      // vsock bash RPC against the persistent guest workspace; for
      // host runs the existing ProcessRunner.runShell path applies.
      // Sending Verify through the host while the agent worked in
      // the guest would race against any file the pull step
      // hadn't observed yet — and now that the guest is the source
      // of truth, it's also the only place the agent's tooling is
      // guaranteed to be the same as what we tested against.
      let verifyStartedAt = Date()
      let verify = try await runVerifyCommand(
        command: verifyCommand,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: TimeInterval(timeoutMs) / 1000,
        launchPlan: launchPlan,
        requiresHostXcode: next.requiresHostXcode,
        hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
      )
      recordVerifyAuditOutput(
        command: verifyCommand,
        result: verify,
        sessionIndex: sessionIndex,
        attempt: attempt,
        durationMs: Int(Date().timeIntervalSince(verifyStartedAt) * 1000)
      )
      if verify.exitCode == 0 {
        verifyPassed = true
        log("Verify passed.", level: .success)
        feedback(.verifyPassed)
        if let profile = forgeProfile {
          await collectCoverageAfterVerify(
            profile: profile,
            workingDirectory: workingDirectory,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex
          )
        }
      } else {
        let verifyTail = tail(verify.stdout + verify.stderr, max: 4000)
        let output = VerifyOutput(
          command: verifyCommand,
          exitCode: Int(verify.exitCode),
          tail: verifyTail
        )
        let message = """
          [verify] Verify command `\(verifyCommand)` exited with code \(output.exitCode ?? -1). Output (tail):
          ```
          \(output.tail)
          ```
          """
        verifyIssues.append(message)
        if let autoRepair {
          requiresPlanRepair = true
          verifyIssues.append(
            """
            [verify] Auto-repaired verify command failed after Develop requested bypassVerify=true.
            Planned verify command: `\(next.verify)`
            Repaired verify command: `\(autoRepair.command)`
            Develop handoff: \(summary.feedback)
            Plan should now replace the verify command or rescope Immediate Work.
            """
          )
        }
        verifyOutput = output
        log("Verify failed (exit \(verify.exitCode)).", level: .error)
      }
    }

    if verifyPassed, forgeProfile == .rustCargo {
      let visualIssues = await runRustDesktopVisualVerificationIfAvailable(
        workingDirectory: workingDirectory,
        launchPlan: launchPlan,
        sessionIndex: sessionIndex,
        attempt: attempt
      )
      verifyIssues.append(contentsOf: visualIssues)
      if !next.verify.contains("clippy") {
        let clippy = try await runVerifyCommand(
          command:
            "if command -v compass-engine >/dev/null 2>&1; then compass-engine clippy-lint --repo . --format json; else cargo clippy --workspace --all-targets --all-features -- -D warnings; fi",
          hostWorkingDirectory: workingDirectory,
          timeoutSeconds: 120,
          launchPlan: launchPlan
        )
        if clippy.exitCode != 0 {
          verifyIssues.append(
            """
            [verify] Rust post-verify clippy soft gate reported issues. Output (tail):
            ```
            \(tail(clippy.stdout + clippy.stderr, max: 4000))
            ```
            """
          )
          log("Rust post-verify clippy soft gate reported issues.", level: .warning)
        }
      }
    }

    if case .sharedVM(let route) = launchPlan.effectiveRoute,
      let machine = SharedCompassVM.shared.virtualMachine,
      SharedCompassVMGitStateStore.context(forHostRepoURL: workingDirectory) != nil
    {
      let client = SharedCompassVM.makeVsockClient(on: machine)
      let gitStatus = try await client.run(
        command: "git status --porcelain",
        workingDirectory: URL(fileURLWithPath: route.guestWorkspacePath),
        timeout: 30
      )
      if gitStatus.exitCode != 0 {
        let issue = """
          Guest `git status --porcelain` failed unexpectedly:
          ```
          \(tail(gitStatus.stdout + gitStatus.stderr, max: 2000))
          ```
          """
        gitStatusIssues.append(issue)
        log("Guest working-tree status check failed.", level: .error)
      } else {
        let status = gitStatus.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.isEmpty {
          log("Guest working tree clean.", level: .success)
        } else {
          let issue = """
            Uncommitted or untracked changes remain in the guest after Develop ran. Commit them before finishing.
            Guest `git status --porcelain` output:
            ```
            \(status)
            ```
            """
          gitStatusIssues.append(issue)
          log("Guest working tree is not clean after Develop.", level: .error)
        }
      }
    } else if case .sharedVM = launchPlan.effectiveRoute {
      log(
        "Post-check: skipping host git-status check under .sharedVM tar-sync fallback.",
        level: .info)
    } else {
      let gitStatus = try await ProcessRunner.runEnv(
        "git",
        ["status", "--porcelain"],
        workingDirectory: workingDirectory,
        timeout: 30
      )
      if gitStatus.exitCode != 0 {
        let issue = """
          `git status --porcelain` failed unexpectedly:
          ```
          \(tail(gitStatus.stdout + gitStatus.stderr, max: 2000))
          ```
          """
        gitStatusIssues.append(issue)
        log("Working-tree status check failed.", level: .error)
      } else {
        let status = gitStatus.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.isEmpty {
          log("Working tree clean.", level: .success)
        } else {
          let issue = """
            Uncommitted or untracked changes remain after Develop ran. Commit them or add them to .gitignore.
            `git status --porcelain` output:
            ```
            \(status)
            ```
            """
          gitStatusIssues.append(issue)
          log("Working tree is not clean after Develop.", level: .error)
        }
      }
    }

    let artifactIssues = try await runArtifactHygieneCheck(
      beforeSha: beforeSha,
      workingDirectory: workingDirectory,
      launchPlan: launchPlan
    )
    gitStatusIssues.append(contentsOf: artifactIssues)

    return PostCheckResult(
      ok: verifyIssues.isEmpty && gitStatusIssues.isEmpty,
      requiresPlanRepair: requiresPlanRepair,
      verifyIssues: verifyIssues,
      gitStatusIssues: gitStatusIssues,
      verifyOutput: verifyOutput
    )
  }

  func recordVerifyAuditOutput(
    command: String,
    result: ProcessResult,
    sessionIndex: Int,
    attempt: Int,
    durationMs: Int
  ) {
    guard sessions.indices.contains(sessionIndex), let workspace else { return }
    let session = sessions[sessionIndex].session
    let contents = """
      Command:
      \(command)

      Exit code: \(result.exitCode)
      Duration: \(durationMs)ms

      [stdout]
      \(result.stdout)

      [stderr]
      \(result.stderr)
      """
    do {
      let artifactURL = try workspace.writeSessionAuditArtifact(
        session: session,
        name: "verify-attempt-\(attempt)-full.log",
        kind: "verify_output",
        contents: contents,
        note: "Full Verify output for attempt \(attempt)."
      )
      recordSessionAuditArtifactEvent(
        session: session,
        kind: "verify_output_saved",
        artifactURL: artifactURL,
        note: "Saved full Verify output.",
        metadata: [
          "command": command,
          "attempt": "\(attempt)",
          "exitCode": "\(result.exitCode)",
          "durationMs": "\(durationMs)",
        ]
      )
    } catch {
      appendAuditEvent(
        kind: "verify_output_save_failed",
        status: "failed",
        text: error.localizedDescription,
        metadata: [
          "command": command,
          "attempt": "\(attempt)",
          "exitCode": "\(result.exitCode)",
          "durationMs": "\(durationMs)",
        ]
      )
    }
    appendAuditEvent(
      kind: "verify_result",
      status: result.exitCode == 0 ? "completed" : "failed",
      text: result.exitCode == 0 ? "Verify passed." : "Verify failed.",
      metadata: [
        "command": command,
        "attempt": "\(attempt)",
        "exitCode": "\(result.exitCode)",
        "durationMs": "\(durationMs)",
      ]
    )
  }

  func runArtifactHygieneCheck(
    beforeSha: String?,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan
  ) async throws -> [String] {
    let command: String
    if let beforeSha, !beforeSha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      command = "git -c core.quotepath=false diff --name-status --no-renames \(beforeSha)..HEAD"
    } else {
      command = "git -c core.quotepath=false diff-tree --root --no-commit-id --name-status -r HEAD"
    }
    let result = try await runVerifyCommand(
      command: command,
      hostWorkingDirectory: workingDirectory,
      timeoutSeconds: 30,
      launchPlan: launchPlan
    )
    guard result.exitCode == 0 else {
      log("Artifact hygiene check skipped: could not inspect changed files.", level: .warning)
      return []
    }
    let issues = GeneratedArtifactHygiene.issues(fromGitNameStatus: result.stdout)
    guard let message = GeneratedArtifactHygiene.formattedIssue(from: issues) else {
      return []
    }
    log("Artifact hygiene check found generated build outputs in the change set.", level: .error)
    return [message]
  }

  /// After verify passes, run the forge profile's coverage collector and
  /// persist a snapshot for the next Plan pass.
  func collectCoverageAfterVerify(
    profile: ForgeProfile,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) async {
    guard let workspace else { return }
    let sessionNumber =
      sessions.indices.contains(sessionIndex) ? sessions[sessionIndex].session : nil
    log("Post-check: collecting coverage for \(profile.displayName).", level: .info)
    do {
      let result = try await runVerifyCommand(
        command: profile.coverageCollectCommand(),
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: TimeInterval(verifyTimeoutMs(for: PlanNext(plan: "", verify: ""))) / 1000,
        launchPlan: launchPlan
      )
      var snapshot = profile.parseCoverageReport(
        output: result.stdout + "\n" + result.stderr,
        workingDirectory: workingDirectory
      )
      snapshot.sessionNumber = sessionNumber
      try ForgeProfileService.writeCoverageSnapshot(snapshot, workspace: workspace)
      if let overall = snapshot.overallLineCoveragePercent {
        log(
          String(
            format: "Coverage snapshot saved (overall %.1f%%, %d files).", overall,
            snapshot.files.count),
          level: .info
        )
      } else {
        log("Coverage snapshot saved (\(snapshot.files.count) files).", level: .info)
      }
    } catch {
      log(
        "Coverage collection failed (verify still passed): \(error.localizedDescription)",
        level: .warning
      )
    }
  }

  func verifyTimeoutMs(for next: PlanNext) -> Int {
    if let timeout = next.verifyTimeoutMs, timeout > 0 {
      return timeout
    }
    let raw = ProcessInfo.processInfo.environment["COMPASS_VERIFY_TIMEOUT_MS"]
    guard let raw, let parsed = Int(raw), parsed > 0 else {
      return 10 * 60 * 1000
    }
    return parsed
  }

  func developFailureFeedbackForPlan(
    next: PlanNext,
    issues: [String],
    developFeedback: String,
    attempts: Int
  ) -> String {
    var parts = [
      """
      Develop exhausted \(attempts) attempts on this increment without passing post-checks.
      Planned verify command: `\(next.verify)`
      """
    ]
    if !issues.isEmpty {
      parts.append("Post-check failures:\n" + issues.joined(separator: "\n"))
    }
    let trimmedDevelopFeedback = developFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedDevelopFeedback.isEmpty {
      parts.append("Develop handoff:\n\(trimmedDevelopFeedback)")
    }
    parts.append(
      "Replan: choose the next smallest step that resolves these failures or rescope so Develop can make progress."
    )
    return parts.joined(separator: "\n\n")
  }

}
