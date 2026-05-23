import AppKit
import Foundation
import Virtualization

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

    guard readiness.isReady,
      let next = state.immediate
    else {
      errorMessage = action.helpText
      log(action.helpText, level: .warning)
      return
    }

    let command = next.verify.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else {
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

    logExecutionEnvironmentPreflight(
      phase: "Mutation",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex
    )
    log(
      "Mutation testing: running `\(readiness.seedCommandLabel)` through \(readiness.routeLabel).",
      level: .info
    )

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
      }

      if result.exitCode == 0 {
        endSession(sessionIndex, status: .succeeded)
        phase = .succeeded
        log("Mutation testing completed.", level: .success)
      } else {
        endSession(sessionIndex, status: .failed)
        phase = .failed
        log("Mutation testing failed (exit \(result.exitCode)).", level: .error)
      }
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
      }
      endSession(sessionIndex, status: .failed)
      phase = .failed
      errorMessage = safeError
      log("Mutation testing failed: \(safeError)", level: .error)
    }

    isRunning = false
    executor = nil
    await refresh()
  }
}
