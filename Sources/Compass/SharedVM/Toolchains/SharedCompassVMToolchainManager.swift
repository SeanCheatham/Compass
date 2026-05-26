import Foundation

/// Status of one catalog toolchain as observed in the guest.
struct ToolchainStatus: Sendable, Equatable {
  var id: String
  var displayName: String
  var description: String
  var installed: Bool
  var defaultProvisioned: Bool
}

/// Host-side service for listing and installing Shared VM toolchains.
protocol SharedVMToolchainService: Sendable {
  func listToolchains(runner: any AgentBashRunner) async throws -> [ToolchainStatus]
  func installToolchain(
    id: String,
    runner: any AgentBashRunner,
    progress: @Sendable (Double) async -> Void
  ) async throws -> SharedCompassVMToolchainManager.InstallReport
}

/// Orchestrates toolchain probes, dependency-ordered installs, and
/// persisted install bookkeeping in `state.json`.
struct SharedCompassVMToolchainManager: SharedVMToolchainService {
  enum ManagerError: Error, CustomStringConvertible, Equatable {
    case unknownToolchainID(String)
    case notInstallable(String)
    case installFailed(String)

    var description: String {
      switch self {
      case .unknownToolchainID(let id):
        return "Unknown toolchain id: \(id)"
      case .notInstallable(let id):
        return "Toolchain \(id) is default-provisioned and cannot be installed on demand"
      case .installFailed(let detail):
        return detail
      }
    }
  }

  struct InstallReport: Sendable, Equatable {
    var toolchainID: String
    var alreadyInstalled: Bool
    var logTail: String
  }

  var bundle: SharedCompassVMBundle
  /// `FileManager` is not `Sendable` because its underlying coordinate methods can race,
  /// but this manager is always constructed and used from a single actor context in
  /// practice — the violation is deliberate and safe in this context.
  nonisolated(unsafe) var fileManager: FileManager

  init(bundle: SharedCompassVMBundle, fileManager: FileManager = .default) {
    self.bundle = bundle
    self.fileManager = fileManager
  }

  func listToolchains(runner: any AgentBashRunner) async throws -> [ToolchainStatus] {
    var statuses: [ToolchainStatus] = []
    statuses.reserveCapacity(SharedVMToolchainCatalog.all.count)
    for definition in SharedVMToolchainCatalog.all {
      let installed = try await probeInstalled(definition: definition, runner: runner)
      statuses.append(
        ToolchainStatus(
          id: definition.stringID,
          displayName: definition.displayName,
          description: definition.description,
          installed: installed,
          defaultProvisioned: definition.defaultProvisioned
        ))
    }
    return statuses
  }

  func installToolchain(
    id: String,
    runner: any AgentBashRunner,
    progress: @Sendable (Double) async -> Void
  ) async throws -> InstallReport {
    guard let definition = SharedVMToolchainCatalog.definition(forStringID: id) else {
      throw ManagerError.unknownToolchainID(id)
    }

    if definition.defaultProvisioned {
      if try await probeInstalled(definition: definition, runner: runner) {
        return InstallReport(toolchainID: id, alreadyInstalled: true, logTail: "")
      }
      throw ManagerError.notInstallable(id)
    }

    if try await probeInstalled(definition: definition, runner: runner) {
      try? recordInstalled(id)
      return InstallReport(toolchainID: id, alreadyInstalled: true, logTail: "")
    }

    for dependency in definition.dependencies {
      let depDefinition = SharedVMToolchainCatalog.definition(for: dependency)
      if try await probeInstalled(definition: depDefinition, runner: runner) {
        continue
      }
      if depDefinition.defaultProvisioned {
        throw ManagerError.installFailed(
          "Required dependency \(dependency.rawValue) is missing from the guest. Re-provision the Shared VM."
        )
      }
      _ = try await installToolchain(
        id: dependency.rawValue,
        runner: runner,
        progress: { _ in }
      )
    }

    guard definition.installableViaGenericProvisioner else {
      throw ManagerError.notInstallable(id)
    }

    let report = try await SharedCompassVMToolchainProvisioner.provision(
      definition: definition,
      runner: runner,
      progress: progress
    )
    try recordInstalled(id)
    return InstallReport(
      toolchainID: report.toolchainID,
      alreadyInstalled: report.alreadyInstalled,
      logTail: report.logTail
    )
  }

  func probeInstalled(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner
  ) async throws -> Bool {
    if definition.id == .commandLineTools {
      return try await SharedCompassVMDevToolsProvisioner.probeAlreadyInstalled(runner: runner)
    }
    return try await SharedCompassVMToolchainProvisioner.probe(
      definition: definition,
      runner: runner
    )
  }

  func installedToolchainIDsFromProbe(runner: any AgentBashRunner) async -> [String] {
    var installed: [String] = []
    for definition in SharedVMToolchainCatalog.all {
      guard (try? await probeInstalled(definition: definition, runner: runner)) == true else {
        continue
      }
      installed.append(definition.stringID)
    }
    return installed
  }

  func seedDefaultProvisionedToolchains() throws {
    try bundle.mutateState(fileManager: fileManager) { state in
      var merged = Set(state.installedToolchains)
      merged.formUnion(SharedVMToolchainCatalog.defaultProvisionedIDs)
      state.installedToolchains = merged.sorted()
    }
  }

  func recordInstalled(_ id: String) throws {
    try bundle.mutateState(fileManager: fileManager) { state in
      if !state.installedToolchains.contains(id) {
        state.installedToolchains.append(id)
        state.installedToolchains.sort()
      }
    }
  }
}
