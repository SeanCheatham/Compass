import AppKit
import Foundation
import CompassCore

@MainActor
extension CompassProject {
  var displayName: String {
    repoURL.lastPathComponent
  }

  var repoPath: String {
    repoURL.path
  }

  var compassPath: String {
    makeStorageResolver(repoURL: repoURL).storageRootURL.path
  }

  var agentExecutionEnvironment: AgentExecutionEnvironment {
    AgentExecutionEnvironment.discover()
  }

  var runtimeDiagnosticsMenu: AgentExecutionEnvironmentMenu {
    AgentExecutionEnvironmentMenu(
      environment: agentExecutionEnvironment,
      launchPlan: agentLaunchPlan(for: repoURL)
    )
  }

  var hasRepository: Bool {
    workspace != nil
  }

  var canStop: Bool {
    isRunning || isAutoPlaying || isPaused
  }

  var immediateTitle: String {
    guard let immediate = state.immediate else { return "No immediate plan" }
    return immediate.plan
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init) ?? "Immediate plan"
  }

  var isIdleForActiveStorageActivation: Bool {
    !isRunning && !isAutoPlaying && !isPaused
  }
}
