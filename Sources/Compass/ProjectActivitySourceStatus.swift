import Foundation

struct ProjectActivitySourceStatus: Equatable {
  static let labelLimit = 38
  static let detailLimit = 220
  static let helpLimit = 520
  static let systemImageLimit = 64
  static let accessibilityLabelLimit = 80
  static let accessibilityHintLimit = 220

  enum Kind: String, Equatable {
    case hidden
    case applicationSupportActive = "application-support-active"
    case applicationSupportUnavailable = "application-support-unavailable"
    case repoLocalUnavailable = "repo-local-unavailable"
    case repoLocalIgnored = "repo-local-ignored"
  }

  var kind: Kind
  var identifier: String
  var activitySourceIdentifier: String
  var label: String
  var detail: String
  var helpText: String
  var systemImage: String
  var severity: CompassWorkspaceStorageAssessment.Severity
  var accessibilityLabel: String
  var accessibilityValue: String
  var accessibilityHint: String

  var isVisible: Bool {
    kind != .hidden
  }

  init(snapshot: RepositoryActivitySourceSnapshot) {
    let presentation = Self.presentation(for: snapshot)
    kind = presentation.kind
    identifier = Self.identifier(kind: presentation.kind, snapshot: snapshot)
    activitySourceIdentifier = snapshot.identifier
    label = Self.boundedText(presentation.label, limit: Self.labelLimit)
    detail = Self.boundedText(presentation.detail, limit: Self.detailLimit)
    helpText =
      presentation.kind == .hidden
      ? ""
      : Self.boundedText(
        Self.helpText(detail: presentation.detail, snapshot: snapshot),
        limit: Self.helpLimit
      )
    systemImage = Self.boundedText(presentation.systemImage, limit: Self.systemImageLimit)
    severity = presentation.severity
    accessibilityLabel = Self.boundedText(
      presentation.label.isEmpty ? "" : "Activity source: \(presentation.label)",
      limit: Self.accessibilityLabelLimit
    )
    accessibilityValue = detail
    accessibilityHint = Self.boundedText(
      presentation.kind == .hidden
        ? ""
        : "Read-only activity-source status. \(presentation.detail)",
      limit: Self.accessibilityHintLimit
    )
  }

  private struct Presentation {
    var kind: Kind
    var label: String
    var detail: String
    var systemImage: String
    var severity: CompassWorkspaceStorageAssessment.Severity
  }

  private static func presentation(for snapshot: RepositoryActivitySourceSnapshot) -> Presentation {
    let activeIsAvailable = snapshot.sourceAvailability == .available
    let repoLocalIsOrdinary = snapshot.repoLocalSessionsState == .activeSource

    if snapshot.activeStorage == .repoLocal,
      activeIsAvailable,
      repoLocalIsOrdinary
    {
      return Presentation(
        kind: .hidden,
        label: "",
        detail: "",
        systemImage: "checkmark.circle",
        severity: .healthy
      )
    }

    if snapshot.sourceAvailability == .notScanned {
      return Presentation(
        kind: .hidden,
        label: "",
        detail: "",
        systemImage: "clock.badge.questionmark",
        severity: .info
      )
    }

    if snapshot.sourceAvailability != .available {
      return unavailablePresentation(for: snapshot)
    }

    if snapshot.activeStorage == .applicationSupport {
      return Presentation(
        kind: .applicationSupportActive,
        label: "Activity from Support",
        detail: [
          "Session activity reads Application Support session records.",
          repoLocalIgnoredSentence(snapshot.repoLocalSessionsState),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " "),
        systemImage: "externaldrive.fill.badge.checkmark",
        severity: .info
      )
    }

    if snapshot.ignoresRepoLocalSessions {
      return Presentation(
        kind: .repoLocalIgnored,
        label: "Repo sessions ignored",
        detail: repoLocalIgnoredSentence(snapshot.repoLocalSessionsState),
        systemImage: "eye.slash.fill",
        severity: .info
      )
    }

    return Presentation(
      kind: .hidden,
      label: "",
      detail: "",
      systemImage: "checkmark.circle",
      severity: .healthy
    )
  }

  private static func unavailablePresentation(
    for snapshot: RepositoryActivitySourceSnapshot
  ) -> Presentation {
    let storageName =
      snapshot.activeStorage == .applicationSupport
      ? "Application Support"
      : "repo-local .compass/"
    let kind: Kind =
      snapshot.activeStorage == .applicationSupport
      ? .applicationSupportUnavailable
      : .repoLocalUnavailable
    let detail: String

    switch snapshot.sourceAvailability {
    case .available:
      detail = "\(storageName) active session record is available."
    case .noRepository:
      detail = "No repository is available, so session activity uses an empty activity source."
    case .notScanned:
      detail =
        "\(storageName) session record has not been scanned yet; session activity is pending."
    case .storageRootMissing:
      detail =
        "\(storageName) activity root is missing; session activity uses an empty source until storage returns."
    case .sessionsRecordMissing:
      detail =
        "\(storageName) session record is missing; session activity uses an empty source until the record returns."
    case .sessionsRecordOversized:
      detail =
        "\(storageName) active session record is oversized and ignored for session activity."
    case .sessionsRecordUnreadable:
      detail = "\(storageName) session record is unreadable and ignored for session activity."
    }

    return Presentation(
      kind: kind,
      label: unavailableLabel(snapshot.sourceAvailability),
      detail: [
        detail,
        snapshot.ignoresRepoLocalSessions
          ? repoLocalIgnoredSentence(snapshot.repoLocalSessionsState)
          : "",
      ]
      .filter { !$0.isEmpty }
      .joined(separator: " "),
      systemImage: unavailableSystemImage(snapshot.sourceAvailability),
      severity: unavailableSeverity(snapshot.sourceAvailability)
    )
  }

  private static func unavailableLabel(
    _ availability: RepositoryActivitySourceSnapshot.SourceAvailability
  ) -> String {
    switch availability {
    case .available:
      return "Activity available"
    case .noRepository:
      return "No repository activity"
    case .notScanned:
      return "Activity not scanned"
    case .storageRootMissing:
      return "Activity root missing"
    case .sessionsRecordMissing:
      return "Activity record missing"
    case .sessionsRecordOversized:
      return "Activity record oversized"
    case .sessionsRecordUnreadable:
      return "Activity record unreadable"
    }
  }

  private static func unavailableSystemImage(
    _ availability: RepositoryActivitySourceSnapshot.SourceAvailability
  ) -> String {
    switch availability {
    case .available:
      return "checkmark.circle"
    case .noRepository:
      return "folder.badge.questionmark"
    case .notScanned:
      return "clock.badge.questionmark"
    case .storageRootMissing:
      return "folder.badge.questionmark"
    case .sessionsRecordMissing:
      return "doc.badge.plus"
    case .sessionsRecordOversized:
      return "doc.badge.exclamationmark"
    case .sessionsRecordUnreadable:
      return "exclamationmark.triangle.fill"
    }
  }

  private static func unavailableSeverity(
    _ availability: RepositoryActivitySourceSnapshot.SourceAvailability
  ) -> CompassWorkspaceStorageAssessment.Severity {
    switch availability {
    case .available:
      return .healthy
    case .noRepository,
      .notScanned,
      .storageRootMissing,
      .sessionsRecordMissing:
      return .warning
    case .sessionsRecordOversized,
      .sessionsRecordUnreadable:
      return .failure
    }
  }

  private static func repoLocalIgnoredSentence(
    _ state: RepositoryActivitySourceSnapshot.RepoLocalSessionsState
  ) -> String {
    switch state {
    case .activeSource:
      return ""
    case .ignoredMissing:
      return "Repo-local session record is missing and ignored."
    case .ignoredCompatible:
      return "Repo-local session record is present but ignored as stale repo-local activity."
    case .ignoredOversized:
      return "Repo-local active session record is oversized and ignored."
    case .ignoredUnreadable:
      return "Repo-local session record is unreadable and ignored."
    }
  }

  private static func helpText(
    detail: String,
    snapshot: RepositoryActivitySourceSnapshot
  ) -> String {
    [
      "Read-only activity source",
      "storage \(snapshot.activeStorageIdentifier)",
      "availability \(snapshot.sourceAvailabilityIdentifier)",
      "repo-local \(snapshot.repoLocalSessionsStateIdentifier)",
      "repo-local-mode \(snapshot.repoLocalSessionsIgnoredIdentifier)",
      "root \(path(snapshot.storageRootURL))",
      "sessions \(path(snapshot.sessionsRecordURL))",
      "repo-local-sessions \(path(snapshot.repoLocalSessionsRecordURL))",
      detail,
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " | ")
  }

  private static func identifier(
    kind: Kind,
    snapshot: RepositoryActivitySourceSnapshot
  ) -> String {
    [
      kind.rawValue,
      "storage:\(snapshot.activeStorageIdentifier)",
      "availability:\(snapshot.sourceAvailabilityIdentifier)",
      "repo-local:\(snapshot.repoLocalSessionsStateIdentifier)",
      "repo-local-mode:\(snapshot.repoLocalSessionsIgnoredIdentifier)",
    ].joined(separator: "|")
  }

  private static func path(_ url: URL?) -> String {
    guard let url else { return "none" }
    let path = url.standardizedFileURL.path
    let limit = 112
    guard path.count > limit else { return path }
    return "..." + path.suffix(limit - 3)
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    let normalized =
      value
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard limit > 0 else { return "" }
    guard normalized.count > limit else { return normalized }
    guard limit > 3 else { return String(normalized.prefix(limit)) }
    return normalized.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
