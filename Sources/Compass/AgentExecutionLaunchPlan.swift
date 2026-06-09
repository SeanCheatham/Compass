import Foundation

struct AgentExecutionInvocation: Sendable, Equatable {
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
          "Repository is not registered in the Shared VM workspace catalog; this phase runs on the host."
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
      return "This Mac"
    case .sharedVM:
      return "Private workspace"
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

  static func userFacingReadinessSummary(_ readiness: SharedCompassVMReadiness?) -> String {
    guard let readiness else { return "not checked yet" }
    switch readiness {
    case .unavailable(let reason):
      return "unavailable: \(reason)"
    case .notProvisioned:
      return "not prepared yet"
    case .downloadingIPSW(let fraction):
      return "downloading macOS \(Int((fraction * 100).rounded()))%"
    case .installing(let fraction):
      return "installing macOS \(Int((fraction * 100).rounded()))%"
    case .guestPrepping:
      return "finishing workspace setup"
    case .provisioningDevTools(let fraction):
      return "installing developer tools \(Int((fraction * 100).rounded()))%"
    case .ready:
      return "ready"
    case .error(let detail):
      return "needs attention: \(detail)"
    }
  }

  static func userFacingFallbackReason(_ reason: String) -> String {
    let normalized = boundedText(reason, limit: fallbackReasonLimit)
    let exactRewrites: [String: String] = [
      "Shared VM readiness has not been evaluated yet.":
        "private workspace readiness has not been checked yet.",
      "Repository is not registered in the Shared VM workspace catalog; this phase runs on the host.":
        "this project is not registered in the private workspace yet.",
      "Shared VM unavailable: 2-guest cap":
        "private workspace capacity is currently full.",
      "Shared VM has not been provisioned yet.":
        "the private workspace has not been prepared yet.",
      "Shared VM is downloading the restore image.":
        "the private workspace is downloading macOS.",
      "Shared VM is installing macOS.":
        "the private workspace is installing macOS.",
      "Shared VM guest preparation is in progress.":
        "private workspace setup is finishing.",
      "Shared VM is installing developer tools inside the guest.":
        "the private workspace is installing developer tools.",
    ]
    if let rewritten = exactRewrites[normalized] {
      return punctuatedSentence(rewritten)
    }
    if normalized.hasPrefix("Shared VM unavailable: 2-guest cap") {
      return "private workspace capacity is currently full."
    }

    var rewritten =
      normalized
      .replacingOccurrences(of: "Shared VM", with: "private workspace")
      .replacingOccurrences(of: "inside the guest", with: "inside the private workspace")
      .replacingOccurrences(of: "guest preparation", with: "private workspace setup")
      .replacingOccurrences(of: "workspace catalog", with: "workspace registration")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = rewritten.first, first.isUppercase {
      rewritten.replaceSubrange(
        rewritten.startIndex...rewritten.startIndex,
        with: String(first).lowercased()
      )
    }
    return punctuatedSentence(rewritten)
  }

  private static func punctuatedSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.last else { return "" }
    if [".", "!", "?"].contains(String(last)) {
      return trimmed
    }
    return "\(trimmed)."
  }

  func preflightSummary(phase: String) -> String {
    [
      "\(phase) runtime: selected \(selectedPreference.title)",
      "private workspace readiness \(Self.userFacingReadinessSummary(vmReadiness))",
      "effective route \(effectiveRouteTitle)",
      "image \(imageLabel)",
      "workspace \(workspaceLabel)",
      "fallback \(fallbackReason.map(Self.userFacingFallbackReason) ?? "none")",
    ].joined(separator: "; ")
  }

  func routeDetail() -> String {
    switch effectiveRoute {
    case .host:
      if let fallbackReason {
        return
          "Using this Mac because \(Self.userFacingFallbackReason(fallbackReason)) Private workspace readiness: \(Self.userFacingReadinessSummary(vmReadiness))."
      }
      return "Using this Mac for this phase."
    case .sharedVM:
      return "Using your private workspace for this phase."
    }
  }

  /// Build a one-shot shell invocation. Used by `ProcessRunner.runShell` for
  /// out-of-agent commands like Verify steps.
  ///
  /// Always returns a host-side `/bin/zsh -lc` invocation, even when
  /// the effective route is `.sharedVM`. Under `.sharedVM`, Verify
  /// goes through the vsock bash RPC instead of this helper;
  /// the host fallback remains for planning/review probes and for repos outside
  /// the guest workspace catalog.
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
