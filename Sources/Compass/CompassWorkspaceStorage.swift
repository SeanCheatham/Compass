import AppKit
import Foundation

typealias CompassWorkspaceStorageMigrationAction = (CompassWorkspaceStorageMigrationPlan) throws ->
  CompassWorkspaceStorageMigrationResult

struct CompassWorkspaceStorageActivationConfirmation: Identifiable, Equatable {
  static let titleLimit = 58
  static let messageLimit = 900
  static let actionLabelLimit = 32

  var plan: CompassWorkspaceStorageActivationPlan

  var id: String {
    [
      plan.repoURL.path,
      plan.candidateURL.path,
      plan.projectStorageIdentifier,
    ]
    .joined(separator: "|")
  }

  var title: String {
    Self.boundedText("Activate Application Support storage?", limit: Self.titleLimit)
  }

  var message: String {
    Self.boundedText(
      [
        "Active state root: \(boundedPath(plan.candidateURL.path, limit: 220))",
        "Git/agent repo: \(boundedPath(plan.repoURL.path, limit: 180))",
        "Repo-local fallback: \(boundedPath(plan.repoLocalURL.path, limit: 180))",
        "This switches Compass state to the prepared Application Support candidate without changing the Git working directory.",
      ]
      .joined(separator: "\n"),
      limit: Self.messageLimit
    )
  }

  var confirmLabel: String {
    Self.boundedText("Activate Candidate", limit: Self.actionLabelLimit)
  }

  var cancelLabel: String {
    Self.boundedText("Cancel", limit: Self.actionLabelLimit)
  }

  private func boundedPath(_ value: String, limit: Int) -> String {
    Self.boundedPath(value, limit: limit)
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassProjectActiveStorageState: Equatable {
  static let labelLimit = 38
  static let detailLimit = 280
  static let helpLimit = 560

  enum Phase: Equatable {
    case idle
    case awaitingConfirmation
    case running
    case succeeded
    case failed
    case blocked
  }

  var phase: Phase
  var label: String
  var detail: String
  var systemImage: String

  var isRunning: Bool {
    phase == .running
  }

  var shouldShowFeedback: Bool {
    phase != .idle
  }

  var helpText: String {
    Self.boundedText(
      [label, detail]
        .filter { !$0.isEmpty }
        .joined(separator: " - "),
      limit: Self.helpLimit
    )
  }

  static let idle = CompassProjectActiveStorageState(
    phase: .idle,
    label: "Activate storage",
    detail:
      "Switch a prepared Application Support candidate into active Compass state while keeping repoURL as the Git/agent workspace.",
    systemImage: "externaldrive.badge.checkmark"
  )

  static func awaitingConfirmation(_ confirmation: CompassWorkspaceStorageActivationConfirmation)
    -> Self
  {
    Self(
      phase: .awaitingConfirmation,
      label: "Confirm activation",
      detail:
        "Review the active-storage switch before Compass starts reading Application Support state.",
      systemImage: confirmation.plan.systemImage
    )
  }

  static func running(plan: CompassWorkspaceStorageActivationPlan) -> Self {
    Self(
      phase: .running,
      label: "Activating storage",
      detail:
        "Switching active Compass state to \(boundedPath(plan.candidateURL.path, limit: 144)).",
      systemImage: "externaldrive.badge.checkmark"
    )
  }

  static func succeeded(plan: CompassWorkspaceStorageActivationPlan) -> Self {
    Self(
      phase: .succeeded,
      label: "Support storage active",
      detail:
        "Compass now reads and writes state at \(boundedPath(plan.candidateURL.path, limit: 144)); repoURL remains \(boundedPath(plan.repoURL.path, limit: 96)).",
      systemImage: "checkmark.circle.fill"
    )
  }

  static func failed(_ error: Error) -> Self {
    Self(
      phase: .failed,
      label: "Activation failed",
      detail: error.localizedDescription,
      systemImage: "exclamationmark.triangle.fill"
    )
  }

  static func blocked(plan: CompassWorkspaceStorageActivationPlan) -> Self {
    Self(
      phase: .blocked,
      label: plan.label,
      detail: plan.detail,
      systemImage: plan.systemImage
    )
  }

  static func blockedWhileBusy() -> Self {
    Self(
      phase: .blocked,
      label: "Activation blocked",
      detail: "Stop or finish the active Compass run before switching active storage.",
      systemImage: "pause.circle.fill"
    )
  }

  init(phase: Phase, label: String, detail: String, systemImage: String) {
    self.phase = phase
    self.label = Self.boundedText(label, limit: Self.labelLimit)
    self.detail = Self.boundedText(detail, limit: Self.detailLimit)
    self.systemImage = systemImage
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

enum CompassProjectActiveStorageActivationError: LocalizedError, Equatable {
  case unavailable(CompassWorkspaceStorageActivationPlan.Kind, String)
  case rolledBack(primary: String, rollbackFailure: String?)

  var errorDescription: String? {
    switch self {
    case .unavailable(_, let detail):
      return "Active-storage activation is unavailable: \(detail)"
    case .rolledBack(let primary, let rollbackFailure):
      if let rollbackFailure {
        return
          "Activation failed and Compass rolled back to repo-local storage. Primary failure: \(primary) Rollback persistence also failed: \(rollbackFailure)"
      }
      return
        "Activation failed and Compass rolled back to repo-local storage. Primary failure: \(primary)"
    }
  }
}

struct CompassWorkspaceStorageMigrationConfirmation: Identifiable, Equatable {
  static let titleLimit = 58
  static let messageLimit = 900
  static let actionLabelLimit = 32

  var plan: CompassWorkspaceStorageMigrationPlan

  var id: String {
    [
      plan.repoURL.path,
      plan.destinationURL.path,
      plan.manifestURL.path,
    ]
    .joined(separator: "|")
  }

  var title: String {
    Self.boundedText("Prepare Application Support storage?", limit: Self.titleLimit)
  }

  var message: String {
    Self.boundedText(
      [
        "Source: \(boundedPath(plan.sourceCompassURL.path, limit: 160))",
        "Destination: \(boundedPath(plan.destinationURL.path, limit: 220))",
        "Manifest: \(boundedPath(plan.manifestURL.path, limit: 220))",
        "No active-storage switch: repo-local .compass/ remains the source of truth after this copy.",
      ]
      .joined(separator: "\n"),
      limit: Self.messageLimit
    )
  }

  var confirmLabel: String {
    Self.boundedText("Prepare Candidate", limit: Self.actionLabelLimit)
  }

  var cancelLabel: String {
    Self.boundedText("Cancel", limit: Self.actionLabelLimit)
  }

  private func boundedPath(_ value: String, limit: Int) -> String {
    Self.boundedPath(value, limit: limit)
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassProjectStorageMigrationState: Equatable {
  static let labelLimit = 38
  static let detailLimit = 260
  static let helpLimit = 520

  enum Phase: Equatable {
    case idle
    case awaitingConfirmation
    case running
    case succeeded
    case failed
    case blocked
  }

  var phase: Phase
  var label: String
  var detail: String
  var systemImage: String

  var isRunning: Bool {
    phase == .running
  }

  var shouldShowFeedback: Bool {
    phase != .idle
  }

  var helpText: String {
    Self.boundedText(
      [label, detail]
        .filter { !$0.isEmpty }
        .joined(separator: " - "),
      limit: Self.helpLimit
    )
  }

  static let idle = CompassProjectStorageMigrationState(
    phase: .idle,
    label: "Prepare storage",
    detail:
      "Copy repo-local .compass/ to Application Support as an opt-in candidate. Repo-local remains active.",
    systemImage: "arrow.triangle.2.circlepath"
  )

  static func awaitingConfirmation(_ confirmation: CompassWorkspaceStorageMigrationConfirmation)
    -> Self
  {
    Self(
      phase: .awaitingConfirmation,
      label: "Confirm storage copy",
      detail: "Review the Application Support candidate transaction before it runs.",
      systemImage: confirmation.plan.systemImage
    )
  }

  static func running(plan: CompassWorkspaceStorageMigrationPlan) -> Self {
    Self(
      phase: .running,
      label: "Preparing storage",
      detail:
        "Copying repo-local .compass/ to \(boundedPath(plan.destinationURL.path, limit: 128)); repo-local remains active.",
      systemImage: "arrow.triangle.2.circlepath"
    )
  }

  static func succeeded(_ result: CompassWorkspaceStorageMigrationResult) -> Self {
    Self(
      phase: .succeeded,
      label: "Storage candidate ready",
      detail: result.detail,
      systemImage: "checkmark.circle.fill"
    )
  }

  static func failed(_ error: Error) -> Self {
    Self(
      phase: .failed,
      label: "Storage copy failed",
      detail: error.localizedDescription,
      systemImage: "exclamationmark.triangle.fill"
    )
  }

  static func blocked(plan: CompassWorkspaceStorageMigrationPlan) -> Self {
    Self(
      phase: .blocked,
      label: plan.label,
      detail: plan.detail,
      systemImage: plan.systemImage
    )
  }

  static func blockedWhileRunning() -> Self {
    Self(
      phase: .blocked,
      label: "Migration blocked",
      detail: "Stop the active agent run before preparing Application Support candidate storage.",
      systemImage: "pause.circle.fill"
    )
  }

  init(phase: Phase, label: String, detail: String, systemImage: String) {
    self.phase = phase
    self.label = Self.boundedText(label, limit: Self.labelLimit)
    self.detail = Self.boundedText(detail, limit: Self.detailLimit)
    self.systemImage = systemImage
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

enum CompassProjectStorageMigrationActionError: LocalizedError, Equatable {
  case activeStorageChanged
  case repoLocalSourceMissing(String)

  var errorDescription: String? {
    switch self {
    case .activeStorageChanged:
      return
        "Storage migration unexpectedly reported an active-storage switch; repo-local .compass/ must remain active."
    case .repoLocalSourceMissing(let path):
      return "Repo-local .compass/ was not preserved at \(path)."
    }
  }
}

enum PlanReadinessNativeFeedbackGate: String, Equatable {
  case planOnly = "plan-only"
  case pausedBeforeDevelop = "paused-before-develop"
}
