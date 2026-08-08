import AppKit
import CompassCore
import Foundation

/// Result of one Plan pass for auto-play control flow.
///
/// Distinguishes "Develop finished and retired Immediate Work" from
/// "Plan found no Immediate Work" — both leave `state.immediate == nil`,
/// but only the latter (plus a passing requirements audit) should stop the loop.
enum PlanPassOutcome: Equatable, Sendable {
  case developed
  case noImmediateWork
  case requirementsComplete
  case requirementsNeedReplan
  case paused
  case failed
  case cancelled
}

@MainActor
extension CompassProject {
  func play(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    if projectKind == .health || state.projectKind == .health {
      await playHealth(agentSettings: agentSettings, modelOverride: modelOverride)
      return
    }
    guard !isRunning, !isAutoPlaying else { return }
    stopRequested = false
    let resumedFromPause = isPaused
    isAutoPlaying = true
    isPaused = false
    pauseMode = .immediate

    if resumedFromPause,
      let sessionIndex = latestAwaitingDevelopSessionIndex(),
      state.immediate != nil
    {
      log("Auto-play resumed.", level: .success)
      await runDevelopPass(
        existingSessionIndex: sessionIndex,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )
      if phase == .failed || phase == .cancelled {
        isAutoPlaying = false
        return
      }
      // Successful (or Plan-handoff) Develop clears Immediate Work; keep looping
      // so the next Plan can pick up unsatisfied requirements.
      if isAutoPlaying, !isPaused, phase == .succeeded {
        phase = .idle
      }
    } else {
      log("Auto-play started.", level: .success)
    }

    while isAutoPlaying, !isPaused, !stopRequested {
      guard phase != .failed, phase != .cancelled else {
        isAutoPlaying = false
        return
      }

      let outcome = await runPlanPass(
        continueToDevelop: true,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )

      switch outcome {
      case .developed:
        // Next Plan iteration — Incremental audit may have left requirements open.
        await Task.yield()
        continue
      case .requirementsNeedReplan:
        pendingRequirementsReplan = false
        log("Continuing auto-play to replan unsatisfied requirements.", level: .info)
        await Task.yield()
        continue
      case .requirementsComplete:
        isAutoPlaying = false
        log("Auto-play stopped: all product requirements verified.", level: .success)
        return
      case .noImmediateWork:
        isAutoPlaying = false
        log("Auto-play stopped: no immediate work.", level: .info)
        return
      case .paused:
        isAutoPlaying = false
        return
      case .failed, .cancelled:
        isAutoPlaying = false
        return
      }
    }
  }

  func runPlanOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    await runPlanPass(
      continueToDevelop: false,
      agentSettings: agentSettings,
      modelOverride: modelOverride
    )
  }

  func runDevelopOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    isPaused = false
    await runDevelopPass(
      existingSessionIndex: nil,
      agentSettings: agentSettings,
      modelOverride: modelOverride
    )
  }

  func requestPause(_ mode: PauseMode) {
    if isPaused && (mode == .afterIteration || mode == pauseMode) {
      return
    }

    isPaused = true
    isAutoPlaying = false
    pauseMode = mode
    let pausedImmediately = !isRunning
    if !isRunning {
      phase = .paused
    }
    switch mode {
    case .immediate:
      log("Pause requested: stopping at the next gate.", level: .warning)
    case .afterIteration:
      log("Pause requested: after this iteration.", level: .warning)
    }
    if pausedImmediately {
      feedback(.paused)
    }
  }

  func stopRun() {
    let wasRunning = isRunning
    stopRequested = wasRunning
    executor?.cancel()
    isAutoPlaying = false
    isPaused = false
    pauseMode = .immediate
    phase = .cancelled
    isRunning = wasRunning
    if let sessionIndex = latestAwaitingDevelopSessionIndex() {
      endSession(sessionIndex, status: .cancelled)
    }
    if !wasRunning {
      stopRequested = false
    }
    log("Stop requested.", level: .warning)
    if !wasRunning {
      feedback(.stopped)
    }
  }
}
