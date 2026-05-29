import AppKit
import Foundation
import Virtualization

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

      let prompt = try Prompts.planPrompt(
        state: currentState.proposal,
        completedCount: currentState.completed.count,
        drafts: consumedDrafts,
        feedback: priorFeedback,
        lessons: workspace.readLessons(),
        vision: workspace.readVision(),
        focus: focus,
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
        decode: PlanRunResult.self
      )
      let nextState = currentState.applying(proposal: planResult.state)

      try validatePlanTransition(from: currentState, to: nextState)
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
    sessions[sessionIndex].status = .developing
    sessions[sessionIndex].endedAt = nil
    sessions[sessionIndex].plan = next.plan
    sessions[sessionIndex].verify = next.verify
    let beforeSha = await gitCurrentSha(at: workspace.repoURL)
    sessions[sessionIndex].beforeSha = beforeSha
    try? persistSessions()
    feedback(.developStarted)

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

        for attempt in 1...maxDevelopAttempts {
          if stopRequested {
            break criticLoop
          }
          phase = .developing
          let prompt = Prompts.developPrompt(
            next: next,
            lessons: workspace.readLessons(),
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
          sessions[sessionIndex].feedback = summary.feedback
          lastDevelopFeedback = summary.feedback
          appendSessionNote(summary.summary, to: sessionIndex)

          let post = try await runPostChecks(
            next: next,
            summary: summary,
            workingDirectory: workspace.repoURL,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex,
            attempt: attempt
          )
          finalIssues = post.verifyIssues + post.gitStatusIssues
          finalVerifyOutput = post.verifyOutput
          if sessions.indices.contains(sessionIndex) {
            sessions[sessionIndex].verifyOutput = post.verifyOutput
          }
          try? persistSessions()

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
          // Post-checks failed after every Develop attempt — hand the
          // failure context to Plan on the next loop iteration instead
          // of stopping auto-play.
          developHandOffToPlan = true
          break criticLoop
        }

        // Pull guest workspace onto the host so the Critic can diff
        // against the pre-Develop SHA. We do this regardless of the
        // critic's verdict because the inner loop already passed —
        // even on critic-reject the next Develop attempt sees the
        // cumulative guest state (persistent), and the next pull
        // overwrites the dirty host state with whatever the new
        // Verify-passing iteration produced.
        if case .sharedVM = launchPlan.effectiveRoute {
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

    let prompt = try Prompts.reflectPrompt(
      state: workspace.readState().proposal,
      lessons: workspace.readLessons(),
      vision: workspace.readVision(),
      recentSessions: Array(recentSessions),
      iteration: iteration,
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
      decode: ReflectSummary.self
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
      vision: workspace.readVision(),
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

  func validatePlanTransition(from current: PlanState, to next: PlanState) throws {
    do {
      try PlanTransitionValidator.validate(from: current, to: next)
    } catch let error as PlanTransitionValidationError {
      throw AppModelError.rejectedPlan(error.message)
    }
  }

  func runPostChecks(
    next: PlanNext,
    summary: DevelopSummary,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int,
    attempt: Int
  ) async throws -> PostCheckResult {
    var verifyIssues: [String] = []
    var gitStatusIssues: [String] = []
    var verifyOutput: VerifyOutput?

    switch summary.status {
    case .succeeded:
      break
    case .blocked:
      if summary.bypassVerify != true {
        verifyIssues.append("[verify] Develop reported it was blocked but did not request verify bypass.")
      }
    case .failed:
      verifyIssues.append("[verify] Develop reported failure: \(summary.feedback)")
    }

    if summary.bypassVerify == true {
      log("Post-check: skipping verify per Develop bypassVerify=true.", level: .warning)
    } else {
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
        "Post-check: running verify command `\(next.verify)` (timeout \(timeoutMs)ms).",
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
      let verify = try await runVerifyCommand(
        command: next.verify,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: TimeInterval(timeoutMs) / 1000,
        launchPlan: launchPlan,
        requiresHostXcode: next.requiresHostXcode,
        hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
      )
      if verify.exitCode == 0 {
        log("Verify passed.", level: .success)
        feedback(.verifyPassed)
      } else {
        let verifyTail = tail(verify.stdout + verify.stderr, max: 4000)
        let output = VerifyOutput(
          command: next.verify,
          exitCode: Int(verify.exitCode),
          tail: verifyTail
        )
        let message = """
          [verify] Verify command `\(next.verify)` exited with code \(output.exitCode ?? -1). Output (tail):
          ```
          \(output.tail)
          ```
          """
        verifyIssues.append(message)
        verifyOutput = output
        log("Verify failed (exit \(verify.exitCode)).", level: .error)
      }
    }

    // Under `.sharedVM` the agent runs in the guest workspace,
    // which has no `.git`, so a host-side `git status` here would
    // either look stale (the post-Verify pull hasn't happened yet)
    // or always-dirty (after an early pull). The Develop loop's
    // `commitAgentChangesOnHost` does the host-side commit
    // explicitly once Verify passes.
    if case .sharedVM = launchPlan.effectiveRoute {
      log(
        "Post-check: skipping host git-status check under .sharedVM (commits are managed post-Verify by the Develop loop).",
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

    return PostCheckResult(
      ok: verifyIssues.isEmpty && gitStatusIssues.isEmpty,
      verifyIssues: verifyIssues,
      gitStatusIssues: gitStatusIssues,
      verifyOutput: verifyOutput
    )
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
      """,
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
