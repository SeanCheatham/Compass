import AppKit
import Foundation
import CompassCore

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
      let prompt = try Prompts.planPrompt(
        state: currentState.proposal,
        completedCount: currentState.completed.count,
        drafts: consumedDrafts,
        feedback: priorFeedback,
        lessons: workspace.readLessons(),
        assumptions: try workspace.readAssumptionLedger().formattedForPrompt(),
        vision: visionText,
        focus: focus,
        coverageSnapshot: CoverageSnapshotStore.readCoverageSnapshot(from: workspace),
        mutationSnapshot: MutationSnapshotStore.readMutationSnapshot(from: workspace),
        promptMode: ModelRuntimeFactory.promptMode(settings: agentSettings)
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
        submitResultSchema: Prompts.planSchema,
        codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
        planHistoryEntries: currentState.completed,
        sessionNumber: sessionNumber,
        decode: PlanRunResult.self
      )
      let nextState = currentState.applying(proposal: planResult.state)

      try validatePlanTransition(
        from: currentState,
        to: nextState
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
      languageProfile: languageProfile
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
      // The Develop iteration operates on `workspace.repoURL`: file tools
      // read/write the host worktree, while bash and Verify run inside
      // containerized Linux with the same tree mounted at `/workspace`.

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
            promptMode: ModelRuntimeFactory.promptMode(settings: agentSettings)
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
              decode: DevelopSummary.self
            )
          } catch let error as AgentExecutionError where error.isAgentBudgetExhaustion {
            // The agent ran out of wall-clock budget or iterations
            // mid-attempt. Treat that as a failed attempt with
            // budget-exhaustion context so the next attempt starts
            // fresh, rather than aborting the whole Develop pass.
            let note =
              "Develop attempt \(attempt) ended without a phase submit envelope: \(error.localizedDescription)."
            log(note, level: .warning)
            appendSessionNote(note, to: sessionIndex)
            priorIssues = [note]
            finalIssues = [note]
            if attempt < maxDevelopAttempts {
              feedback(.developRetrying)
            }
            continue
          }

          // Bash and Verify run in the same containerized Linux view of
          // the host worktree, so post-checks inspect the same files the
          // agent edited.

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
          _ = lastAttemptSummary
          _ = lastAttemptLaunchPlan
          _ = lastPostCheckResult
          // Post-checks failed after every Develop attempt. Hand the
          // failure context to Plan.
          developHandOffToPlan = true
          break criticLoop
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
      iteration: iteration,
      maxIterations: maxCriticAttempts,
      promptMode: ModelRuntimeFactory.promptMode(settings: agentSettings)
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
    to next: PlanState
  ) throws {
    do {
      try PlanTransitionValidator.validate(
        from: current,
        to: next,
        repoURL: workspace?.repoURL
      )
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
    attempt: Int,
    beforeSha: String?
  ) async throws -> PostCheckResult {
    var verifyIssues: [String] = []
    var gitStatusIssues: [String] = []
    var verifyOutput: VerifyOutput?
    var requiresPlanRepair = false

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
      developSummary: summary
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
      // Verify runs in the same containerized Linux runtime used by
      // the agent's bash tool.
      let verifyStartedAt = Date()
      let verify = try await runVerifyCommand(
        command: verifyCommand,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: TimeInterval(timeoutMs) / 1000,
        launchPlan: launchPlan
      )
      recordVerifyAuditOutput(
        command: verifyCommand,
        result: verify,
        sessionIndex: sessionIndex,
        attempt: attempt,
        durationMs: Int(Date().timeIntervalSince(verifyStartedAt) * 1000)
      )
      if verify.exitCode == 0 {
        log("Verify passed.", level: .success)
        feedback(.verifyPassed)
        await collectCoverageAfterVerify(
          workingDirectory: workingDirectory,
          launchPlan: launchPlan,
          sessionIndex: sessionIndex
        )
        await collectMutationAfterVerify(
          workingDirectory: workingDirectory,
          launchPlan: launchPlan,
          sessionIndex: sessionIndex,
          beforeSha: beforeSha
        )
        if let macosIssue = await runMacOSVerifyIfNeeded(
          workingDirectory: workingDirectory,
          sessionIndex: sessionIndex
        ) {
          verifyIssues.append(macosIssue)
          log("macOS host verify failed after a green Rust verify.", level: .error)
        }
        let gateIssues = acceptanceGateIssues()
        if !gateIssues.isEmpty {
          verifyIssues.append(contentsOf: gateIssues)
          log("Acceptance gates failed after a green verify.", level: .error)
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

  /// After verify passes, run the coverage collector and persist a snapshot
  /// for the next Plan pass.
  func collectCoverageAfterVerify(
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) async {
    guard let workspace else { return }
    let sessionNumber =
      sessions.indices.contains(sessionIndex) ? sessions[sessionIndex].session : nil
    log("Post-check: collecting coverage.", level: .info)
    do {
      let result = try await runVerifyCommand(
        command: GeneratedProjectQuality.coverageCollectCommand,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: TimeInterval(verifyTimeoutMs(for: PlanNext(plan: "", verify: ""))) / 1000,
        launchPlan: launchPlan
      )
      var snapshot = GeneratedProjectQuality.parseCoverageReport(
        output: result.stdout + "\n" + result.stderr
      )
      guard snapshot.overallLineCoveragePercent != nil || !snapshot.files.isEmpty else {
        log(
          "Coverage collection produced no data (exit \(result.exitCode)); no snapshot saved.",
          level: .warning
        )
        return
      }
      snapshot.sessionNumber = sessionNumber
      try CoverageSnapshotStore.writeCoverageSnapshot(snapshot, workspace: workspace)
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

  /// After verify passes, run scoped mutation testing on changed Rust files
  /// and persist the snapshot for gate evaluation and the next Plan pass.
  func collectMutationAfterVerify(
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int,
    beforeSha: String?
  ) async {
    guard let workspace else { return }
    let sessionNumber =
      sessions.indices.contains(sessionIndex) ? sessions[sessionIndex].session : nil
    log("Post-check: running mutation testing.", level: .info)
    do {
      var changedFiles: [String] = []
      let diffCommand: String
      if let beforeSha, !beforeSha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        diffCommand = """
          git -c core.quotepath=false diff --name-only \(beforeSha)..HEAD
          git -c core.quotepath=false diff --name-only
          git -c core.quotepath=false diff --cached --name-only
          git -c core.quotepath=false ls-files --others --exclude-standard
          """
      } else {
        diffCommand = """
          git -c core.quotepath=false diff-tree --root --no-commit-id --name-only -r HEAD
          git -c core.quotepath=false diff --name-only
          git -c core.quotepath=false diff --cached --name-only
          git -c core.quotepath=false ls-files --others --exclude-standard
          """
      }
      let diff = try await runVerifyCommand(
        command: diffCommand,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: 30,
        launchPlan: launchPlan
      )
      if diff.exitCode == 0 {
        changedFiles = Array(
          Set(diff.stdout.split(whereSeparator: \.isNewline).map(String.init))
        ).sorted()
      }
      let command = GeneratedProjectQuality.mutationTestCommand(forChangedFiles: changedFiles)
      let result = try await runVerifyCommand(
        command: command,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: Self.qualityCollectionTimeoutSeconds(),
        launchPlan: launchPlan
      )
      var snapshot = MutationReportParser.parse(
        output: result.stdout + "\n" + result.stderr,
        exitCode: Int(result.exitCode),
        command: command
      )
      guard snapshot.tested > 0 || result.exitCode == 0 else {
        log(
          "Mutation collection did not run (exit \(result.exitCode)); no snapshot saved.",
          level: .warning
        )
        return
      }
      snapshot.sessionNumber = sessionNumber
      try MutationSnapshotStore.writeMutationSnapshot(snapshot, workspace: workspace)
      if let score = snapshot.mutationScorePercent {
        log(
          String(
            format: "Mutation snapshot saved (score %.1f%%, %d caught, %d missed).",
            score, snapshot.caught, snapshot.missed),
          level: snapshot.missed > 0 ? .warning : .info
        )
      } else {
        log("Mutation snapshot saved (no mutants tested).", level: .info)
      }
    } catch {
      log(
        "Mutation testing failed (verify still passed): \(error.localizedDescription)",
        level: .warning
      )
    }
  }

  /// Host-side macOS product gate (temporary stand-in for a future macOS VM).
  func runMacOSVerifyIfNeeded(
    workingDirectory: URL,
    sessionIndex: Int
  ) async -> String? {
    guard let workspace,
      let state = try? workspace.readState(),
      GeneratedProducts.contains(state.products, .macos)
    else { return nil }

    log(
      "Post-check: running host macOS verify `\(GeneratedProjectQuality.macosVerifyCommand)` (temporary; VM later).",
      level: .info
    )
    let sessionNumber =
      sessions.indices.contains(sessionIndex) ? sessions[sessionIndex].session : 0
    do {
      let result = try await AgentHostBashRunner().run(
        command: GeneratedProjectQuality.macosVerifyCommand,
        workingDirectory: workingDirectory,
        timeout: Self.qualityCollectionTimeoutSeconds()
      )
      let combined = result.stdout + "\n" + result.stderr
      _ = try? workspace.writeSessionAuditArtifact(
        session: sessionNumber,
        name: "macos-verify.log",
        kind: "log",
        contents: "$ \(GeneratedProjectQuality.macosVerifyCommand)\n\n" + combined,
        note: "Host macOS verify output (temporary runner)."
      )
      guard result.exitCode == 0 else {
        let tail = String(combined.suffix(4000))
        return """
          [macos-verify] Host macOS verify `\(GeneratedProjectQuality.macosVerifyCommand)` exited with code \(result.exitCode). \
          This gate is temporary host-side and will move to a macOS VM later. Output (tail):
          ```
          \(tail)
          ```
          """
      }
      log("macOS host verify passed.", level: .success)
      return nil
    } catch {
      return """
        [macos-verify] Host macOS verify failed to run: \(error.localizedDescription). \
        macOS product requires a Mac host/VM with the Swift toolchain.
        """
    }
  }

  /// Evaluates persisted evidence against the active acceptance gates.
  func acceptanceGateIssues() -> [String] {
    guard let workspace,
      let state = try? workspace.readState(),
      let gates = AcceptanceGates.active(from: state)
    else { return [] }
    let violations = gates.violations(
      coverage: CoverageSnapshotStore.readCoverageSnapshot(from: workspace),
      mutation: MutationSnapshotStore.readMutationSnapshot(from: workspace)
    )
    guard !violations.isEmpty else { return [] }
    return [
      """
      [acceptance-gate] Verify passed, but the acceptance gates rejected this iteration:
      \(violations.map { "- \($0)" }.joined(separator: "\n"))

      Gates are deterministic quality thresholds (see `acceptanceGates` in .compass/state.json). \
      Strengthen tests until the collected coverage/mutation evidence satisfies them; do not \
      weaken or delete the gates to make the iteration pass.
      """
    ]
  }

  static func qualityCollectionTimeoutSeconds() -> TimeInterval {
    let raw = ProcessInfo.processInfo.environment["COMPASS_QUALITY_COLLECTION_TIMEOUT_MS"]
    guard let raw, let ms = Int(raw), ms > 0 else { return 600 }
    return TimeInterval(ms) / 1000
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
