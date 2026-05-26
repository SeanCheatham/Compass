import Foundation

/// Host-driven ripgrep provisioning for the Compass shared VM guest.
///
/// Thin wrapper around `SharedCompassVMToolchainProvisioner` for the ripgrep
/// catalog entry. Homebrew must be installed first (see default provisioning).
enum SharedCompassVMRipgrepProvisioner {
  static let ripgrepInstallPath = SharedVMToolchainPaths.ripgrepInstallPath
  static let brewRipgrepPath = SharedVMToolchainPaths.brewRipgrepPath
  static let brewInstallPath = SharedVMToolchainPaths.brewInstallPath

  typealias ProvisionError = SharedCompassVMToolchainProvisioner.ProvisionError
  typealias ProvisionReport = SharedCompassVMToolchainProvisioner.ProvisionReport
  typealias PollSnapshot = SharedCompassVMToolchainProvisioner.PollSnapshot

  enum InstallPhase: String, Equatable {
    case kickoff
    case bootstrappingHomebrew
    case installingRipgrep
    case done
  }

  private static var definition: SharedVMToolchainDefinition {
    SharedVMToolchainCatalog.definition(for: .ripgrep)
  }

  static func provision(
    runner: any AgentBashRunner,
    progress: (Double) async -> Void,
    now: @Sendable () -> Date = { Date() },
    sleep: @Sendable (UInt64) async -> Void = { ns in try? await Task.sleep(nanoseconds: ns) }
  ) async throws -> ProvisionReport {
    try await SharedCompassVMToolchainProvisioner.provision(
      definition: definition,
      runner: runner,
      progress: progress,
      now: now,
      sleep: sleep
    )
  }

  static func probeAlreadyInstalled(runner: any AgentBashRunner) async throws -> Bool {
    try await SharedCompassVMToolchainProvisioner.probe(definition: definition, runner: runner)
  }

  static func renderInstallScript() -> String {
    definition.renderInstallScript()
  }

  static func renderInstallLaunchDaemonPlist() -> String {
    SharedCompassVMToolchainProvisioner.renderInstallLaunchDaemonPlist(definition: definition)
  }

  static func parsePhase(fromLogTail tail: String) -> InstallPhase? {
    let lower = tail.lowercased()
    if lower.contains("exit=0") {
      return .done
    }
    if lower.contains("brew install ripgrep") || lower.contains("installed /usr/local/bin/rg") {
      return .installingRipgrep
    }
    if lower.contains("bootstrapping homebrew") {
      return .bootstrappingHomebrew
    }
    if lower.contains("starting") {
      return .kickoff
    }
    return nil
  }

  static func fractionForPhase(_ phase: InstallPhase) -> Double {
    switch phase {
    case .kickoff: return 0.1
    case .bootstrappingHomebrew: return 0.35
    case .installingRipgrep: return 0.75
    case .done: return 1.0
    }
  }
}
