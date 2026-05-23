import AppKit
import Foundation
import Virtualization

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
    AgentExecutionEnvironment.discover(
      vmReadiness: SharedCompassVM.shared.readiness
    )
  }

  var runtimeDiagnosticsMenu: AgentExecutionEnvironmentMenu {
    let environment = agentExecutionEnvironment
    // Both Develop and mutation testing route off the main repo
    // URL now (the per-iteration host worktree concept is gone),
    // so the env-presentation plan and the mutation-testing plan
    // share the same launch plan.
    let envLaunchPlan = agentLaunchPlan(for: repoURL)
    let mutationLaunchPlan = envLaunchPlan
    let mutationTestingPlan = AgentMutationTestingPlan(
      state: state,
      languageProfile: languageProfile,
      launchPlan: mutationLaunchPlan
    )
    let mutationRecoveryDescriptor = MutationTestingRecoveryDescriptor.runtimeDescriptor(
      sessions: sessions,
      readiness: mutationTestingPlan
    )
    return AgentExecutionEnvironmentMenu(
      environment: environment,
      launchPlan: envLaunchPlan,
      mutationTestingPlan: mutationTestingPlan,
      mutationRecoveryDescriptor: mutationRecoveryDescriptor,
      mutationExecutionState: mutationTestingExecutionState
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

  var isIdleForMutationTesting: Bool {
    !isRunning
      && !isAutoPlaying
      && !isPaused
      && !storageMigrationState.isRunning
      && !activeStorageActivationState.isRunning
  }

  var mutationTestingExecutionState: AgentMutationTestingMenuAction.ExecutionState {
    if isPaused { return .paused }
    if !isIdleForMutationTesting { return .running }
    return .idle
  }
}
