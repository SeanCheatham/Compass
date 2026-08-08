import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  /// Post-ship health pass (fail-open). Feeds Plan pressure via snapshot.
  func runHealthPassAfterShip(
    workspace: CompassWorkspace,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    sessionIndex: Int
  ) async {
    guard state.projectKind == .factory else { return }
    phase = .hunting
    log("Health pass after ship…", level: .info)
    let sessionNumber = sessions.indices.contains(sessionIndex) ? sessions[sessionIndex].session : 0
    var settings = agentSettings
    if !modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      settings.model = modelOverride
    }
    let runtime = ModelRuntimeFactory.makeRouted(settings: settings)
    let environment = resolveAgentEnvironment(forHostURL: workspace.repoURL)
    var options = HealthPassOptions.factoryShip
    options.budget = healthBudget
    let outcome = await HealthPassRunner.run(
      workspace: workspace,
      settings: settings,
      runtime: runtime,
      bashRunner: environment.bashRunner,
      sessionNumber: sessionNumber,
      options: options,
      onEvent: { [weak self] event in
        Task { @MainActor in
          self?.logHealthStatus(event)
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
    healthSnapshot = outcome.snapshot
    if let error = outcome.errorMessage {
      log("Health pass warning: \(error)", level: .warning)
    } else {
      let confirmed = outcome.snapshot.findings.filter(\.isConfirmedRealBug).count
      log(
        "Health pass recorded \(outcome.snapshot.findings.count) finding(s) (\(confirmed) confirmed).",
        level: .success
      )
    }
  }

  func playHealth(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning, !isAutoPlaying else { return }
    stopRequested = false
    isAutoPlaying = true
    isPaused = false
    log("Health auto-play started.", level: .success)

    var branchSession: HealthBranch.Session?
    var repoURL: URL?
    defer {
      if let branchSession, let repoURL {
        try? HealthBranch.end(repoURL: repoURL, session: branchSession)
      }
      if isAutoPlaying {
        isAutoPlaying = false
      }
    }

    do {
      let workspace = try await resolveWorkspaceForRun()
      try await initializeIfNeeded(workspace)
      try await requireMacOSVMReady()
      repoURL = workspace.repoURL
      branchSession = try HealthBranch.begin(
        repoURL: workspace.repoURL,
        projectId: id.uuidString
      )
    } catch {
      phase = .failed
      errorMessage = error.localizedDescription
      fail(error)
      return
    }

    let priorFindings: [HealthFinding]
    if let existing = healthSnapshot?.findings {
      priorFindings = existing
    } else if let repoURL {
      priorFindings =
        HealthSnapshotStore.readSnapshot(from: CompassWorkspace(repoURL: repoURL))?.findings ?? []
    } else {
      priorFindings = []
    }
    var seen = HealthLoopNovelty.noveltyKeys(in: priorFindings)
    var idleStreak = 0
    let idleLimit = healthBudget.idleStopPasses

    while isAutoPlaying, !isPaused, !stopRequested {
      guard phase != .failed, phase != .cancelled else {
        return
      }

      let ok = await runHealthPass(
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        failOpen: false,
        manageBranch: false,
        branchSession: branchSession
      )
      if !ok || stopRequested || isPaused {
        return
      }

      let findings = healthSnapshot?.findings ?? []
      let incorporated = HealthLoopNovelty.incorporate(current: findings, seen: seen)
      seen = incorporated.seen
      if incorporated.newCount == 0 {
        idleStreak += 1
        log(
          "Health pass added no new findings (\(idleStreak)/\(idleLimit) idle).",
          level: .info
        )
      } else {
        idleStreak = 0
        log(
          "Health pass added \(incorporated.newCount) new finding(s); idle streak reset.",
          level: .info
        )
      }

      if idleStreak >= idleLimit {
        phase = .succeeded
        log(
          "Health auto-play stopped: no new findings for \(idleStreak) passes.",
          level: .success
        )
        return
      }

      phase = .idle
      await Task.yield()
    }
  }

  func runHealthHuntOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    _ = await runHealthPass(
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      failOpen: false
    )
  }

  func runHealthReconOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    _ = await runHealthPass(
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      failOpen: false,
      skipHunt: true
    )
  }

  @discardableResult
  func runHealthPass(
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    failOpen: Bool,
    skipHunt: Bool = false,
    manageBranch: Bool = true,
    branchSession: HealthBranch.Session? = nil
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
      current.projectKind = .health
      try workspace.writeState(current)
      state = current
      projectKind = .health

      sessionIndex = startSession()
      let sessionNumber = sessions[sessionIndex!].session

      var settings = agentSettings
      if !modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        settings.model = modelOverride
      }
      let runtime = ModelRuntimeFactory.makeRouted(settings: settings)
      let environment = resolveAgentEnvironment(forHostURL: workspace.repoURL)
      var options = HealthPassOptions.healthLoop
      options.failOpen = failOpen
      options.skipHunt = skipHunt
      options.budget = healthBudget
      options.projectId = id.uuidString
      options.manageBranch = manageBranch
      options.branchSession = branchSession

      let outcome = await HealthPassRunner.run(
        workspace: workspace,
        settings: settings,
        runtime: runtime,
        bashRunner: environment.bashRunner,
        sessionNumber: sessionNumber,
        options: options,
        onEvent: { [weak self] event in
          Task { @MainActor in
            self?.logHealthStatus(event)
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
      healthSnapshot = outcome.snapshot
      if let error = outcome.errorMessage, !failOpen {
        phase = .failed
        errorMessage = error
        if let sessionIndex {
          endSession(sessionIndex, status: .failed)
        }
        log("Health pass failed: \(error)", level: .error)
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

  /// High-level health status lines for Activity (Studio gets full LiveEvents via `onLive`).
  private func logHealthStatus(_ event: HeadlessCompassEvent) {
    switch event.kind {
    case "tool_start", "tool_end", "assistant_json", "submit_accepted", "submit_rejected",
      "continuation_repair":
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
