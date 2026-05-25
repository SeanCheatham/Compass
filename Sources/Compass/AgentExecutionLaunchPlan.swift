import Foundation

struct AgentExecutionInvocation: Equatable {
  var executable: String
  var arguments: [String]
  var workingDirectory: URL?

  init(executable: String, arguments: [String], workingDirectory: URL? = nil) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory?.standardizedFileURL
  }
}

struct AgentExecutionLaunchPlan: Equatable {
  static let fallbackReasonLimit = 180
  static let labelLimit = 80

  /// How an agent run is actually dispatched. The user no longer chooses
  /// between routes — Compass always targets the Shared VM. `Route.host`
  /// remains as an internal-only fallback when the guest workspace catalog
  /// cannot map this repo or the VM is not ready yet.
  enum Route: Equatable {
    case host
    case sharedVM(SharedVMRoute)
  }

  var selectedPreference: AgentExecutionEnvironmentPreference
  var effectiveRoute: Route
  var vmReadiness: SharedCompassVMReadiness?
  var fallbackReason: String?

  init(
    selectedPreference: AgentExecutionEnvironmentPreference = .sharedVM,
    effectiveRoute: Route,
    vmReadiness: SharedCompassVMReadiness? = nil,
    fallbackReason: String? = nil
  ) {
    self.selectedPreference = selectedPreference
    self.effectiveRoute = effectiveRoute
    self.vmReadiness = vmReadiness
    self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
  }

  static func host(
    vmReadiness: SharedCompassVMReadiness? = nil,
    fallbackReason: String? = nil
  ) -> Self {
    Self(
      selectedPreference: .sharedVM,
      effectiveRoute: .host,
      vmReadiness: vmReadiness,
      fallbackReason: fallbackReason
    )
  }

  static func plan(
    repoURL: URL,
    vmReadiness: SharedCompassVMReadiness? = nil,
    sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
  ) -> Self {
    guard let readiness = vmReadiness else {
      return host(
        vmReadiness: nil,
        fallbackReason: "Shared VM readiness has not been evaluated yet."
      )
    }

    switch readiness {
    case .ready:
      if let route = sharedVMRouteFactory(repoURL.standardizedFileURL) {
        return Self(
          selectedPreference: .sharedVM,
          effectiveRoute: .sharedVM(route),
          vmReadiness: readiness
        )
      }
      return host(
        vmReadiness: readiness,
        fallbackReason:
          "Worktree is outside the Shared VM workspaces share; this phase runs on the host."
      )
    case .unavailable(let reason):
      return host(
        vmReadiness: readiness,
        fallbackReason: Self.boundedText(
          "Shared VM unavailable: \(reason)",
          limit: Self.fallbackReasonLimit
        )
      )
    case .error(let detail):
      return host(
        vmReadiness: readiness,
        fallbackReason: Self.boundedText(
          "Shared VM error: \(detail)",
          limit: Self.fallbackReasonLimit
        )
      )
    case .notProvisioned:
      return host(
        vmReadiness: readiness,
        fallbackReason: "Shared VM has not been provisioned yet."
      )
    case .downloadingIPSW:
      return host(
        vmReadiness: readiness,
        fallbackReason: "Shared VM is downloading the restore image."
      )
    case .installing:
      return host(
        vmReadiness: readiness,
        fallbackReason: "Shared VM is installing macOS."
      )
    case .guestPrepping:
      return host(
        vmReadiness: readiness,
        fallbackReason: "Shared VM guest preparation is in progress."
      )
    case .provisioningDevTools:
      return host(
        vmReadiness: readiness,
        fallbackReason: "Shared VM is installing developer tools inside the guest."
      )
    }
  }

  var isVMRoute: Bool {
    if case .sharedVM = effectiveRoute { return true }
    return false
  }

  var effectiveRouteTitle: String {
    switch effectiveRoute {
    case .host:
      return "Native macOS"
    case .sharedVM:
      return "Shared VM"
    }
  }

  var effectiveRouteIdentifier: String {
    switch effectiveRoute {
    case .host:
      return "native-macos"
    case .sharedVM:
      return "shared-vm"
    }
  }

  var imageLabel: String {
    switch effectiveRoute {
    case .host:
      return "none"
    case .sharedVM(let route):
      return Self.boundedText(route.sshDestination, limit: Self.labelLimit)
    }
  }

  var workspaceLabel: String {
    switch effectiveRoute {
    case .host:
      return "host"
    case .sharedVM(let route):
      return Self.boundedText(route.guestWorkspacePath, limit: Self.labelLimit)
    }
  }

  var fallbackReasonLabel: String {
    fallbackReason ?? "none"
  }

  var vmReadinessLabel: String {
    guard let vmReadiness else { return "not-inspected" }
    return Self.readinessSummary(vmReadiness)
  }

  static func readinessSummary(_ readiness: SharedCompassVMReadiness) -> String {
    switch readiness {
    case .unavailable(let reason):
      return "unavailable: \(reason)"
    case .notProvisioned:
      return "not-provisioned"
    case .downloadingIPSW(let fraction):
      return "downloading-ipsw \(Int((fraction * 100).rounded()))%"
    case .installing(let fraction):
      return "installing \(Int((fraction * 100).rounded()))%"
    case .guestPrepping:
      return "guest-prepping"
    case .provisioningDevTools(let fraction):
      return "provisioning-dev-tools \(Int((fraction * 100).rounded()))%"
    case .ready(let sshDestination):
      return "ready \(sshDestination)"
    case .error(let detail):
      return "error: \(detail)"
    }
  }

  func preflightSummary(phase: String) -> String {
    [
      "\(phase) execution environment: selected \(selectedPreference.title)",
      "VM readiness \(vmReadinessLabel)",
      "effective route \(effectiveRouteTitle)",
      "image \(imageLabel)",
      "workspace \(workspaceLabel)",
      "fallback \(fallbackReasonLabel)",
    ].joined(separator: "; ")
  }

  func routeDetail() -> String {
    switch effectiveRoute {
    case .host:
      if let fallbackReason {
        return
          "Using native macOS execution because \(fallbackReason) VM readiness: \(vmReadinessLabel)."
      }
      return "Using native macOS execution."
    case .sharedVM(let route):
      return
        "Using Shared VM at \(Self.boundedText(route.sshDestination, limit: Self.labelLimit)) with workspace \(Self.boundedText(route.guestWorkspacePath, limit: Self.labelLimit))."
    }
  }

  /// Build a one-shot shell invocation. Used by `ProcessRunner.runShell` for
  /// out-of-agent commands like Verify steps.
  ///
  /// Always returns a host-side `/bin/zsh -lc` invocation, even when
  /// the effective route is `.sharedVM`. Under `.sharedVM`, Verify and
  /// Verify goes through the vsock bash RPC instead of this helper;
  /// the host fallback remains for Plan/Reflect and for repos outside
  /// the guest workspaces share.
  func shellInvocation(command: String, hostWorkingDirectory: URL) -> AgentExecutionInvocation {
    AgentExecutionInvocation(
      executable: "/bin/zsh",
      arguments: ["-lc", command],
      workingDirectory: hostWorkingDirectory
    )
  }

  static func boundedText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
    let bounded = boundedText(text ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }
}
