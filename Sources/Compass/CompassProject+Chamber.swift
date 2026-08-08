import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  /// Post-ship chamber pass (fail-open). Feeds Plan pressure via snapshot.
  func runChamberPassAfterShip(
    workspace: CompassWorkspace,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    sessionIndex: Int
  ) async {
    guard state.projectKind == .factory else { return }
    phase = .hunting
    log("Chamber pass after ship…", level: .info)
    let sessionNumber = sessions.indices.contains(sessionIndex) ? sessions[sessionIndex].session : 0
    var settings = agentSettings
    if !modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      settings.model = modelOverride
    }
    let runtime = ModelRuntimeFactory.makeRouted(settings: settings)
    let environment = resolveAgentEnvironment(forHostURL: workspace.repoURL)
    var options = ChamberPassOptions.factoryShip
    options.budget = chamberBudget
    let outcome = await ChamberPassRunner.run(
      workspace: workspace,
      settings: settings,
      runtime: runtime,
      bashRunner: environment.bashRunner,
      sessionNumber: sessionNumber,
      options: options,
      onEvent: { [weak self] event in
        Task { @MainActor in
          self?.logChamberStatus(event)
        }
      },
      onLive: { [weak self] live in
        Task { @MainActor in
          self?.log(live)
        }
      },
      bindExecutor: { [weak self] agent in
        Task { @MainActor in
          self?.executor = agent
        }
      }
    )
    executor = nil
    chamberSnapshot = outcome.snapshot
    if let error = outcome.errorMessage {
      log("Chamber pass warning: \(error)", level: .warning)
    } else {
      let confirmed = outcome.snapshot.findings.filter(\.isConfirmedRealBug).count
      log(
        "Chamber pass recorded \(outcome.snapshot.findings.count) finding(s) (\(confirmed) confirmed).",
        level: .success
      )
    }
  }

  func playChamber(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning, !isAutoPlaying else { return }
    stopRequested = false
    isAutoPlaying = true
    isPaused = false
    log("Chamber auto-play started.", level: .success)

    while isAutoPlaying, !isPaused, !stopRequested {
      let ok = await runChamberHuntPass(
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        failOpen: false
      )
      if !ok || stopRequested || isPaused {
        isAutoPlaying = false
        return
      }
      // One full hunt per play iteration; stop unless user starts again.
      isAutoPlaying = false
      phase = .succeeded
      log("Chamber hunt completed.", level: .success)
      return
    }
  }

  func runChamberHuntOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    _ = await runChamberHuntPass(
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      failOpen: false
    )
  }

  func runChamberReconOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    _ = await runChamberHuntPass(
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      failOpen: false,
      skipHunt: true
    )
  }

  @discardableResult
  func runChamberHuntPass(
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    failOpen: Bool,
    skipHunt: Bool = false
  ) async -> Bool {
    guard !isRunning else { return false }
    isRunning = true
    stopRequested = false
    phase = .hunting
    defer {
      isRunning = false
      executor = nil
    }

    var sessionIndex: Int?
    do {
      let workspace = try await resolveWorkspaceForRun()
      try await initializeIfNeeded(workspace)
      try await requireMacOSVMReady()
      var current = try workspace.readState()
      current.projectKind = .chamber
      try workspace.writeState(current)
      state = current
      projectKind = .chamber

      sessionIndex = startSession()
      let sessionNumber = sessions[sessionIndex!].session

      var settings = agentSettings
      if !modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        settings.model = modelOverride
      }
      let runtime = ModelRuntimeFactory.makeRouted(settings: settings)
      let environment = resolveAgentEnvironment(forHostURL: workspace.repoURL)
      var options = ChamberPassOptions.chamberLoop
      options.failOpen = failOpen
      options.skipHunt = skipHunt
      options.budget = chamberBudget

      let outcome = await ChamberPassRunner.run(
        workspace: workspace,
        settings: settings,
        runtime: runtime,
        bashRunner: environment.bashRunner,
        sessionNumber: sessionNumber,
        options: options,
        onEvent: { [weak self] event in
          Task { @MainActor in
            self?.logChamberStatus(event)
          }
        },
        onLive: { [weak self] live in
          Task { @MainActor in
            self?.log(live)
          }
        },
        bindExecutor: { [weak self] agent in
          Task { @MainActor in
            self?.executor = agent
          }
        }
      )
      chamberSnapshot = outcome.snapshot
      if let error = outcome.errorMessage, !failOpen {
        phase = .failed
        errorMessage = error
        if let sessionIndex {
          endSession(sessionIndex, status: .failed)
        }
        log("Chamber hunt failed: \(error)", level: .error)
        return false
      }
      phase = .succeeded
      if let sessionIndex {
        endSession(sessionIndex, status: .succeeded)
      }
      return true
    } catch {
      phase = .failed
      if let sessionIndex {
        endSession(sessionIndex, status: .failed)
      }
      fail(error)
      return false
    }
  }

  /// High-level chamber status lines for Activity (Studio gets full LiveEvents via `onLive`).
  private func logChamberStatus(_ event: HeadlessCompassEvent) {
    switch event.kind {
    case "tool_start", "tool_end", "assistant_json", "submit_accepted", "submit_rejected",
      "continuation_repair":
      // Mirrored already through onLive → Studio / Activity LiveEvent stream.
      return
    default:
      break
    }
    let level: LiveLine.Level
    switch event.level {
    case "error": level = .error
    case "warning": level = .warning
    case "success": level = .success
    default: level = .info
    }
    log(event.message, level: level)
  }
}
