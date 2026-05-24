import AppKit
import Foundation
import Virtualization

struct MutationTestingPassResult: Equatable {
  var ran: Bool
  var succeeded: Bool
  var issue: String?

  static let skipped = MutationTestingPassResult(ran: false, succeeded: true, issue: nil)

  static func completed(succeeded: Bool, issue: String? = nil) -> MutationTestingPassResult {
    MutationTestingPassResult(ran: true, succeeded: succeeded, issue: issue)
  }
}

@MainActor
extension CompassProject {
  func runMutationTesting() async {
    let initialLaunchPlan = agentLaunchPlan(for: repoURL)
    let initialReadiness = AgentMutationTestingPlan(
      state: state,
      languageProfile: languageProfile,
      launchPlan: initialLaunchPlan
    )
    let initialAction = AgentMutationTestingMenuAction(
      readiness: initialReadiness,
      executionState: mutationTestingExecutionState
    )

    guard isIdleForMutationTesting else {
      errorMessage = initialAction.helpText
      log(initialAction.helpText, level: .warning)
      return
    }

    let workspace: CompassWorkspace
    do {
      workspace = try await resolveWorkspaceForRun()
      try await initializeIfNeeded(workspace)
      state = try workspace.readState()
    } catch {
      fail(error)
      return
    }

    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    let readiness = AgentMutationTestingPlan(
      state: state,
      languageProfile: languageProfile,
      launchPlan: launchPlan
    )
    let action = AgentMutationTestingMenuAction(
      readiness: readiness,
      executionState: .idle
    )

    guard readiness.isReady else {
      errorMessage = action.helpText
      log(action.helpText, level: .warning)
      return
    }

    isRunning = true
    isAutoPlaying = false
    isPaused = false
    phase = .verifying
    errorMessage = nil
    let sessionIndex = startSession()
    guard sessions.indices.contains(sessionIndex) else {
      fail(AppModelError.internalInvariant("Could not start a mutation testing session."))
      isRunning = false
      phase = .failed
      return
    }

    sessions[sessionIndex].status = .developing
    sessions[sessionIndex].endedAt = nil
    try? persistSessions()

    let result = await executeMutationTestingPass(
      workspace: workspace,
      sessionIndex: sessionIndex,
      next: state.immediate,
      launchPlan: launchPlan,
      readiness: readiness
    )

    if sessions.indices.contains(sessionIndex) {
      endSession(sessionIndex, status: result.succeeded ? .succeeded : .failed)
    }
    phase = result.succeeded ? .succeeded : .failed
    if let issue = result.issue, !result.succeeded {
      errorMessage = issue
    }

    isRunning = false
    executor = nil
    await refresh()
  }

  /// Runs mutation testing after a successful Develop pass when auto mode
  /// is enabled. Records results on the existing Develop session.
  func runAutoMutationTestingIfNeeded(
    workspace: CompassWorkspace,
    sessionIndex: Int,
    next: PlanNext,
    launchPlan: AgentExecutionLaunchPlan
  ) async -> MutationTestingPassResult {
    guard sessions.indices.contains(sessionIndex) else {
      return .skipped
    }
    guard MutationTestingPolicy.shouldRunAutomatically(
      sessionNumber: sessions[sessionIndex].session,
      estimatedDifficulty: next.estimatedDifficulty
    ) else {
      return .skipped
    }

    let readiness = AgentMutationTestingPlan(
      immediate: next,
      languageProfile: languageProfile,
      launchPlan: launchPlan
    )
    guard readiness.isReady else {
      log(
        "Mutation testing skipped: \(readiness.detailText)",
        level: .info
      )
      return .skipped
    }

    return await executeMutationTestingPass(
      workspace: workspace,
      sessionIndex: sessionIndex,
      next: next,
      launchPlan: launchPlan,
      readiness: readiness
    )
  }

  func executeMutationTestingPass(
    workspace: CompassWorkspace,
    sessionIndex: Int,
    next: PlanNext?,
    launchPlan: AgentExecutionLaunchPlan,
    readiness: AgentMutationTestingPlan
  ) async -> MutationTestingPassResult {
    guard let next,
      let command = readiness.mutationCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
      !command.isEmpty
    else {
      let issue = "Mutation testing has no command to run."
      log(issue, level: .warning)
      return .completed(succeeded: false, issue: issue)
    }

    logExecutionEnvironmentPreflight(
      phase: "Mutation",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex
    )
    log(
      "Mutation testing: running `\(readiness.mutationCommandLabel)` (verify seed `\(readiness.seedCommandLabel)`) through \(readiness.routeLabel).",
      level: .info
    )
    phase = .verifying

    let startedAt = Date().timeIntervalSince1970 * 1000
    let timeoutMs = verifyTimeoutMs(for: next)
    do {
      let result = try await ProcessRunner.runShell(
        command,
        workingDirectory: workspace.repoURL,
        timeout: TimeInterval(timeoutMs) / 1000,
        launchPlan: launchPlan,
        runner: mutationTestingRunner
      )
      let endedAt = Date().timeIntervalSince1970 * 1000
      let execution = SessionMutationTestingExecution(
        readiness: readiness,
        exitCode: Int(result.exitCode),
        startedAt: startedAt,
        endedAt: endedAt,
        outputTail: result.stdout + result.stderr,
        launchPlan: launchPlan
      )
      if sessions.indices.contains(sessionIndex) {
        sessions[sessionIndex].recordMutationTestingExecution(execution)
        try? persistSessions()
      }

      if result.exitCode == 0 {
        log("Mutation testing completed.", level: .success)
        return .completed(succeeded: true)
      }

      let issue = "Mutation testing failed (exit \(result.exitCode))."
      log(issue, level: .error)
      return .completed(succeeded: false, issue: issue)
    } catch {
      let endedAt = Date().timeIntervalSince1970 * 1000
      let safeError = AgentMutationTestingMetadataSanitizer.sanitizedOutputTail(
        error.localizedDescription,
        launchPlan: launchPlan,
        limit: 360
      )
      let execution = SessionMutationTestingExecution(
        readiness: readiness,
        exitCode: nil,
        startedAt: startedAt,
        endedAt: endedAt,
        outputTail: safeError,
        launchPlan: launchPlan
      )
      if sessions.indices.contains(sessionIndex) {
        sessions[sessionIndex].recordMutationTestingExecution(execution)
        try? persistSessions()
      }
      log("Mutation testing failed: \(safeError)", level: .error)
      return .completed(succeeded: false, issue: safeError)
    }
  }
}
