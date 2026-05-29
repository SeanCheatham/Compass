import Foundation

/// The runtime environment Compass targets for an agent run.
///
/// Compass has collapsed to a single user-facing environment (the
/// Shared VM); the type is retained so diagnostics and stored session
/// history continue to carry an explicit identifier for the chosen
/// environment. Legacy stored values (`native_macos`, etc.) are decoded
/// as `.sharedVM`.
enum AgentExecutionEnvironmentPreference: String, Codable, Identifiable {
  case sharedVM = "shared_vm"

  var id: Self { self }

  /// Any stored raw value (including legacy `native_macos` /
  /// `devcontainer_preferred`) is silently upgraded — Compass no longer
  /// supports a host-execution preference.
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    _ = try container.decode(String.self)
    self = .sharedVM
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var title: String {
    "Shared VM"
  }

  var systemImage: String {
    "macwindow.on.rectangle"
  }
}

struct AgentExecutionEnvironmentReadiness: Equatable {
  static let detailLimit = 280

  var vmReadiness: SharedCompassVMReadiness
  var detail: String

  init(
    vmReadiness: SharedCompassVMReadiness,
    detail: String? = nil
  ) {
    self.vmReadiness = vmReadiness
    let computed = detail ?? Self.detail(for: vmReadiness)
    self.detail = StringUtils.boundedText(computed, limit: Self.detailLimit)
  }

  static func inspect(vmReadiness: SharedCompassVMReadiness) -> Self {
    Self(vmReadiness: vmReadiness)
  }

  private static func detail(for readiness: SharedCompassVMReadiness) -> String {
    switch readiness {
    case .unavailable(let reason):
      return "Shared VM is unavailable: \(reason)."
    case .notProvisioned:
      return "Shared VM has not been provisioned."
    case .downloadingIPSW(let fraction):
      return
        "Shared VM is downloading the macOS restore image (\(Int((fraction * 100).rounded()))%)."
    case .installing(let fraction):
      return "Shared VM is installing macOS (\(Int((fraction * 100).rounded()))%)."
    case .guestPrepping:
      return "Shared VM is finishing headless first-boot setup."
    case .provisioningDevTools(let fraction):
      return
        "Shared VM is installing developer tools inside the guest (\(Int((fraction * 100).rounded()))%)."
    case .ready(let sshDestination):
      return "Shared VM is ready at \(sshDestination)."
    case .error(let detail):
      return "Shared VM reported an error: \(detail)."
    }
  }

  // MARK: - boundedText
}

struct AgentExecutionEnvironmentPresentation: Equatable {
  static let titleLimit = 48
  static let statusLimit = 180
  static let detailLimit = 320

  var title: String
  var status: String
  var detail: String
  var systemImage: String
  var isWarning: Bool

  init(
    title: String,
    status: String,
    detail: String,
    systemImage: String,
    isWarning: Bool = false
  ) {
    self.title = StringUtils.boundedText(title, limit: Self.titleLimit)
    self.status = StringUtils.boundedText(status, limit: Self.statusLimit)
    self.detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    self.systemImage = systemImage
    self.isWarning = isWarning
  }

  // MARK: - boundedText
}

struct AgentExecutionEnvironment: Equatable {
  var preference: AgentExecutionEnvironmentPreference
  var readiness: AgentExecutionEnvironmentReadiness

  init(
    preference: AgentExecutionEnvironmentPreference = .sharedVM,
    readiness: AgentExecutionEnvironmentReadiness
  ) {
    self.preference = preference
    self.readiness = readiness
  }

  static func discover(
    vmReadiness: SharedCompassVMReadiness = .notProvisioned
  ) -> Self {
    Self(
      preference: .sharedVM,
      readiness: AgentExecutionEnvironmentReadiness.inspect(vmReadiness: vmReadiness)
    )
  }

  func presentation(launchPlan plan: AgentExecutionLaunchPlan)
    -> AgentExecutionEnvironmentPresentation
  {
    if plan.isVMRoute {
      return AgentExecutionEnvironmentPresentation(
        title: "Shared VM",
        status: "Running the agent inside the Shared VM via vsock.",
        detail: plan.routeDetail(),
        systemImage: preference.systemImage
      )
    }
    // When the VM is ready but the route still falls back to host,
    // surface it as informational; reserve warning styling for actual
    // VM-availability problems.
    if case .ready = readiness.vmReadiness {
      return AgentExecutionEnvironmentPresentation(
        title: "Shared VM",
        status:
          "Shared VM ready. This phase is running on the host repo as an internal fallback.",
        detail: readiness.detail,
        systemImage: preference.systemImage
      )
    }
    return AgentExecutionEnvironmentPresentation(
      title: "Shared VM",
      status:
        "Shared VM not ready; Develop is blocked until the VM finishes preparing.",
      detail: fallbackDetail(plan: plan),
      systemImage: "desktopcomputer.trianglebadge.exclamationmark",
      isWarning: true
    )
  }

  func launchPlan(
    repoURL: URL,
    sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
  ) -> AgentExecutionLaunchPlan {
    AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: readiness.vmReadiness,
      sharedVMRouteFactory: sharedVMRouteFactory
    )
  }

  private func fallbackDetail(plan: AgentExecutionLaunchPlan) -> String {
    [readiness.detail, plan.fallbackReason.map { "Fallback: \($0)" }]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

struct AgentExecutionEnvironmentDiagnosticsReport: Equatable, Identifiable {
  static let copyTextLimit = 2_000
  static let fieldLimit = 120
  static let helpLimit = 240
  static let stableCopyActionIdentifier = "runtime-diagnostics.copy"
  static let copyIdentifierPrefix = "runtime-diagnostics.copy.v1"

  var selectedPreferenceIdentifier: String
  var selectedPreferenceTitle: String
  var effectiveRouteIdentifier: String
  var effectiveRouteTitle: String
  var vmReadinessIdentifier: String
  var vmBuildStateIdentifier: String
  var vmBundleSizeLabel: String
  var vmGuestOSVersion: String
  var imageLabel: String
  var workspaceLabel: String
  var fallbackReason: String
  var copyActionIdentifier: String
  var copyIdentifier: String

  var id: String { copyIdentifier }

  init(
    environment: AgentExecutionEnvironment,
    launchPlan: AgentExecutionLaunchPlan,
    vmBundleSizeBytes: Int? = nil,
    vmGuestOSVersion: String? = nil
  ) {
    selectedPreferenceIdentifier = environment.preference.rawValue
    selectedPreferenceTitle = Self.sanitizedField(
      environment.preference.title,
      limit: Self.fieldLimit
    )
    effectiveRouteIdentifier = launchPlan.effectiveRouteIdentifier
    effectiveRouteTitle = Self.sanitizedField(
      launchPlan.effectiveRouteTitle,
      limit: Self.fieldLimit
    )
    vmReadinessIdentifier = Self.vmReadinessIdentifier(launchPlan.vmReadiness)
    vmBuildStateIdentifier = Self.vmBuildStateIdentifier(launchPlan.vmReadiness)
    vmBundleSizeLabel = Self.vmBundleSizeLabel(vmBundleSizeBytes)
    self.vmGuestOSVersion = Self.sanitizedField(
      vmGuestOSVersion ?? "unknown", limit: Self.fieldLimit)
    imageLabel = Self.sanitizedField(launchPlan.imageLabel, limit: Self.fieldLimit)
    workspaceLabel = Self.sanitizedField(launchPlan.workspaceLabel, limit: Self.fieldLimit)
    fallbackReason = Self.sanitizedField(
      launchPlan.fallbackReasonLabel,
      limit: AgentExecutionLaunchPlan.fallbackReasonLimit
    )

    copyActionIdentifier = Self.stableCopyActionIdentifier
    copyIdentifier = [
      Self.copyIdentifierPrefix,
      selectedPreferenceIdentifier,
      effectiveRouteIdentifier,
      vmReadinessIdentifier,
    ].joined(separator: ".")
  }

  var copyText: String {
    Self.boundedCopyText(
      [
        "Runtime Diagnostics",
        "copy-id: \(copyIdentifier)",
        "copy-action-id: \(copyActionIdentifier)",
        "selected-preference: \(selectedPreferenceIdentifier) (\(selectedPreferenceTitle))",
        "effective-route: \(effectiveRouteIdentifier) (\(effectiveRouteTitle))",
        "vm-readiness: \(vmReadinessIdentifier)",
        "vm-build-state: \(vmBuildStateIdentifier)",
        "vm-bundle-size: \(vmBundleSizeLabel)",
        "vm-guest-os: \(vmGuestOSVersion)",
        "image: \(imageLabel)",
        "workspace: \(workspaceLabel)",
        "fallback: \(fallbackReason)",
      ].joined(separator: "\n"),
      limit: Self.copyTextLimit
    )
  }

  var helpText: String {
    Self.boundedField(
      "Copy sanitized runtime diagnostics using \(copyActionIdentifier). No runtime preference, VM lifecycle, or project state is changed.",
      limit: Self.helpLimit
    )
  }

  private static func vmReadinessIdentifier(_ readiness: SharedCompassVMReadiness?) -> String {
    guard let readiness else { return "not-evaluated" }
    switch readiness {
    case .unavailable:
      return "unavailable"
    case .notProvisioned:
      return "not-provisioned"
    case .downloadingIPSW:
      return "downloading-ipsw"
    case .installing:
      return "installing"
    case .guestPrepping:
      return "guest-prepping"
    case .provisioningDevTools:
      return "provisioning-dev-tools"
    case .ready:
      return "ready"
    case .error:
      return "error"
    }
  }

  private static func vmBuildStateIdentifier(_ readiness: SharedCompassVMReadiness?) -> String {
    guard let readiness else { return "not-evaluated" }
    switch readiness {
    case .downloadingIPSW, .installing:
      return "building"
    case .ready, .guestPrepping, .provisioningDevTools:
      return "built"
    case .notProvisioned:
      return "not-built"
    case .unavailable, .error:
      return "blocked"
    }
  }

  private static func vmBundleSizeLabel(_ bytes: Int?) -> String {
    guard let bytes, bytes > 0 else { return "unknown" }
    let gigabytes = Double(bytes) / 1_073_741_824
    if gigabytes >= 1 {
      return String(format: "%.1fGB", gigabytes)
    }
    let megabytes = Double(bytes) / 1_048_576
    return String(format: "%.0fMB", megabytes)
  }

  private static func sanitizedField(_ text: String, limit: Int) -> String {
    boundedField(
      text
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      limit: limit
    )
  }

  private static func boundedField(_ text: String, limit: Int) -> String {
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

  private static func boundedCopyText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct AgentExecutionEnvironmentCopyDiagnosticsAction: Identifiable, Equatable {
  static let actionIdentifier = AgentExecutionEnvironmentDiagnosticsReport
    .stableCopyActionIdentifier
  static let titleLimit = 34
  static let descriptionLimit = 220

  var report: AgentExecutionEnvironmentDiagnosticsReport

  var id: String { Self.actionIdentifier }

  var title: String {
    StringUtils.boundedText("Copy Runtime Diagnostics", limit: Self.titleLimit)
  }

  var systemImage: String {
    "doc.on.doc"
  }

  var description: String {
    StringUtils.boundedText(
      "Copy a bounded sanitized runtime report for the selected route and VM readiness.",
      limit: Self.descriptionLimit
    )
  }

  var helpText: String {
    report.helpText
  }

  var copyIdentifier: String {
    report.copyIdentifier
  }

  var copyText: String {
    report.copyText
  }

  // MARK: - boundedText
}

struct AgentExecutionEnvironmentMenu: Equatable {
  var labelSystemImage: String
  var helpText: String
  var statusText: String
  var copyDiagnosticsAction: AgentExecutionEnvironmentCopyDiagnosticsAction

  init(
    environment: AgentExecutionEnvironment,
    launchPlan: AgentExecutionLaunchPlan? = nil,
    vmBundleSizeBytes: Int? = nil,
    vmGuestOSVersion: String? = nil
  ) {
    let effectiveLaunchPlan =
      launchPlan ?? environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
    labelSystemImage = presentation.systemImage
    helpText = "Execution environment: \(presentation.title). \(presentation.detail)"
    statusText = [presentation.status, presentation.detail]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    copyDiagnosticsAction = AgentExecutionEnvironmentCopyDiagnosticsAction(
      report: AgentExecutionEnvironmentDiagnosticsReport(
        environment: environment,
        launchPlan: effectiveLaunchPlan,
        vmBundleSizeBytes: vmBundleSizeBytes,
        vmGuestOSVersion: vmGuestOSVersion
      )
    )
  }
}
