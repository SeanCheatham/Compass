import CompassCore
import Foundation

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
}

struct AgentExecutionEnvironment: Equatable {
  var preference: AgentExecutionEnvironmentPreference

  init(preference: AgentExecutionEnvironmentPreference = .macOSVM) {
    self.preference = preference
  }

  static func discover() -> Self {
    Self()
  }

  func presentation(launchPlan plan: AgentExecutionLaunchPlan)
    -> AgentExecutionEnvironmentPresentation
  {
    AgentExecutionEnvironmentPresentation(
      title: plan.effectiveRouteTitle,
      status: "Running agents in the embedded macOS VM.",
      detail: plan.routeDetail(),
      systemImage: preference.systemImage,
      isWarning: false
    )
  }

  func launchPlan(repoURL: URL) -> AgentExecutionLaunchPlan {
    AgentExecutionLaunchPlan.plan(repoURL: repoURL)
  }
}

struct AgentExecutionEnvironmentDiagnosticsReport: Equatable, Identifiable {
  static let copyTextLimit = 2_000
  static let fieldLimit = 120
  static let helpLimit = 240
  static let stableCopyActionIdentifier = "runtime-diagnostics.copy"
  static let copyIdentifierPrefix = "runtime-diagnostics.copy.v2"

  var selectedPreferenceIdentifier: String
  var selectedPreferenceTitle: String
  var effectiveRouteIdentifier: String
  var effectiveRouteTitle: String
  var imageLabel: String
  var workspaceLabel: String
  var fallbackReason: String
  var copyActionIdentifier: String
  var copyIdentifier: String

  var id: String { copyIdentifier }

  init(
    environment: AgentExecutionEnvironment,
    launchPlan: AgentExecutionLaunchPlan,
    runtimeBundleSizeBytes: Int? = nil,
    runtimeOSVersion: String? = nil
  ) {
    _ = runtimeBundleSizeBytes
    _ = runtimeOSVersion
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
        "runtime: macos_vm",
        "image: \(imageLabel)",
        "workspace: \(workspaceLabel)",
        "fallback: \(fallbackReason)",
      ].joined(separator: "\n"),
      limit: Self.copyTextLimit
    )
  }

  var helpText: String {
    Self.boundedField(
      "Copy sanitized runtime diagnostics using \(copyActionIdentifier). No runtime preference, cache state, or project state is changed.",
      limit: Self.helpLimit
    )
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
      ClipboardHelpText.runtimeDiagnostics,
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
}

struct AgentExecutionEnvironmentMenu: Equatable {
  var labelSystemImage: String
  var helpText: String
  var statusText: String
  var copyDiagnosticsAction: AgentExecutionEnvironmentCopyDiagnosticsAction

  init(
    environment: AgentExecutionEnvironment,
    launchPlan: AgentExecutionLaunchPlan? = nil,
    runtimeBundleSizeBytes: Int? = nil,
    runtimeOSVersion: String? = nil
  ) {
    let effectiveLaunchPlan =
      launchPlan ?? environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
    labelSystemImage = presentation.systemImage
    helpText = "Runtime: \(presentation.title). \(presentation.detail)"
    statusText = [presentation.status, presentation.detail]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    copyDiagnosticsAction = AgentExecutionEnvironmentCopyDiagnosticsAction(
      report: AgentExecutionEnvironmentDiagnosticsReport(
        environment: environment,
        launchPlan: effectiveLaunchPlan,
        runtimeBundleSizeBytes: runtimeBundleSizeBytes,
        runtimeOSVersion: runtimeOSVersion
      )
    )
  }
}
