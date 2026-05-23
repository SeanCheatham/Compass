import AppKit
import Foundation
import Virtualization

@MainActor
extension CompassProject {
  func play(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
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
    } else {
      log("Auto-play started.", level: .success)
    }

    while isAutoPlaying, !isPaused, !stopRequested {
      guard phase != .failed, phase != .cancelled else {
        isAutoPlaying = false
        return
      }

      await runPlanPass(
        continueToDevelop: true,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )

      if state.immediate == nil, phase == .idle {
        isAutoPlaying = false
        log("Auto-play stopped: no immediate work.", level: .info)
        return
      }

      if phase == .failed || phase == .cancelled {
        isAutoPlaying = false
        return
      }

      await Task.yield()
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
