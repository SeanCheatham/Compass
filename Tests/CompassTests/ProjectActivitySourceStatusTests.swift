import Foundation
import Testing

@testable import Compass

struct ProjectActivitySourceStatusTests {
  @Test
  func testRepoLocalAvailableBaselineIsHidden() throws {
    let snapshot = makeSnapshot(
      activeStorage: .repoLocal,
      sourceAvailability: .available,
      repoLocalSessionsState: .activeSource
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    try #require(!status.isVisible)
    try #require(status.kind == .hidden)
    try #require(
      status.identifier
        == "hidden|storage:repo_local|availability:available|repo-local:active-source|repo-local-mode:active"
    )
    try #require(status.activitySourceIdentifier == snapshot.identifier)
    try #require(status.label == "")
    try #require(status.detail == "")
    try #require(status.helpText == "")
    try #require(status.accessibilityLabel == "")
    try #require(status.accessibilityValue == "")
    try #require(status.accessibilityHint == "")
    try assertBounded(status)
  }

  @Test
  func testApplicationSupportAvailableWithMissingRepoLocalSessionsIsVisible() throws {
    let snapshot = makeSnapshot(
      activeStorage: .applicationSupport,
      sourceAvailability: .available,
      repoLocalSessionsState: .ignoredMissing
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    try #require(status.isVisible)
    try #require(status.kind == .applicationSupportActive)
    try #require(
      status.identifier
        == "application-support-active|storage:application_support|availability:available|repo-local:ignored-missing|repo-local-mode:ignored"
    )
    try #require(status.activitySourceIdentifier == snapshot.identifier)
    try #require(status.label == "Activity from Support")
    try #require(status.severity == .info)
    try #require(status.systemImage == "externaldrive.fill.badge.checkmark")
    try #require(status.detail.contains("Application Support sessions.json"))
    try #require(status.detail.contains("Repo-local sessions.json is missing and ignored"))
    try #require(status.helpText.contains("storage application_support"))
    try #require(status.helpText.contains("availability available"))
    try #require(status.helpText.contains("repo-local ignored-missing"))
    try #require(status.helpText.contains("repo-local-mode ignored"))
    try #require(status.accessibilityLabel.contains("Activity source"))
    try #require(status.accessibilityValue.contains(status.detail))
    try #require(status.accessibilityHint.contains("Read-only"))
    try assertBounded(status)
    try assertDiagnosticsParity(snapshot: snapshot, status: status)
  }

  @Test
  func testApplicationSupportAvailableWithCompatibleRepoLocalSessionsMarksStaleIgnoredRecord()
    throws
  {
    let snapshot = makeSnapshot(
      activeStorage: .applicationSupport,
      sourceAvailability: .available,
      repoLocalSessionsState: .ignoredCompatible
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    try #require(status.isVisible)
    try #require(status.kind == .applicationSupportActive)
    try #require(status.detail.contains("present but ignored"))
    try #require(status.detail.contains("stale repo-local activity"))
    try #require(status.helpText.contains("repo-local ignored-compatible"))
    try #require(status.identifier.contains("repo-local:ignored-compatible"))
    try assertBounded(status)
    try assertDiagnosticsParity(snapshot: snapshot, status: status)
  }

  @Test
  func testIgnoredRepoLocalSessionsStatesUseExplicitCopy() throws {
    let cases: [(RepositoryActivitySourceSnapshot.RepoLocalSessionsState, String)] = [
      (.ignoredMissing, "missing and ignored"),
      (.ignoredCompatible, "present but ignored as stale"),
      (.ignoredOversized, "oversized and ignored"),
      (.ignoredUnreadable, "unreadable and ignored"),
    ]

    for (state, expectedCopy) in cases {
      let snapshot = makeSnapshot(
        activeStorage: .applicationSupport,
        sourceAvailability: .available,
        repoLocalSessionsState: state
      )
      let status = ProjectActivitySourceStatus(snapshot: snapshot)

      try #require(status.isVisible)
      try #require(
        status.detail.contains(expectedCopy), "Missing \(expectedCopy) for \(state.rawValue)")
      try #require(status.helpText.contains("repo-local \(state.rawValue)"))
      try assertBounded(status)
    }
  }

  @Test
  func testMissingActiveSupportRootIsVisibleAndReadOnly() throws {
    let snapshot = makeSnapshot(
      activeStorage: .applicationSupport,
      sourceAvailability: .storageRootMissing,
      repoLocalSessionsState: .ignoredMissing
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    try #require(status.isVisible)
    try #require(status.kind == .applicationSupportUnavailable)
    try #require(status.label == "Activity root missing")
    try #require(status.severity == .warning)
    try #require(status.systemImage == "folder.badge.questionmark")
    try #require(status.detail.contains("Application Support activity root is missing"))
    try #require(status.detail.contains("empty source"))
    try #require(status.helpText.contains("availability storage-root-missing"))
    try #require(status.accessibilityHint.contains("Read-only"))
    try assertBounded(status)
    try assertDiagnosticsParity(snapshot: snapshot, status: status)
  }

  @Test
  func testNoRepositoryFallbackIsVisibleAndMatchesDiagnosticsSnapshot() throws {
    let snapshot = RepositoryActivitySourceSnapshot.noRepository(
      activeStorage: .applicationSupport
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    try #require(status.isVisible)
    try #require(status.kind == .applicationSupportUnavailable)
    try #require(status.label == "No repository activity")
    try #require(status.severity == .warning)
    try #require(status.detail.contains("No repository is available"))
    try #require(status.helpText.contains("availability no-repository"))
    try #require(status.helpText.contains("root none"))
    try #require(status.helpText.contains("sessions none"))
    try #require(status.activitySourceIdentifier == snapshot.identifier)
    try assertBounded(status)
    try assertDiagnosticsParity(snapshot: snapshot, status: status)
  }

  private func makeSnapshot(
    activeStorage: KnownProjectActiveStorage,
    sourceAvailability: RepositoryActivitySourceSnapshot.SourceAvailability,
    repoLocalSessionsState: RepositoryActivitySourceSnapshot.RepoLocalSessionsState
  ) -> RepositoryActivitySourceSnapshot {
    let repoURL = URL(fileURLWithPath: "/tmp/CompassActivitySourceStatus", isDirectory: true)
    let activeRoot: URL
    switch activeStorage {
    case .repoLocal:
      activeRoot = repoURL.appending(path: ".compass", directoryHint: .isDirectory)
    case .applicationSupport:
      activeRoot =
        repoURL
        .appending(path: "Application Support", directoryHint: .isDirectory)
        .appending(path: "Compass", directoryHint: .isDirectory)
    }
    let repoLocalRoot = repoURL.appending(path: ".compass", directoryHint: .isDirectory)

    return RepositoryActivitySourceSnapshot(
      activeStorage: activeStorage,
      storageRootURL: activeRoot,
      sessionsRecordURL: activeRoot.appending(path: "sessions.json"),
      sourceAvailability: sourceAvailability,
      repoLocalSessionsRecordURL: repoLocalRoot.appending(path: "sessions.json"),
      repoLocalSessionsState: repoLocalSessionsState
    )
  }

  private func assertDiagnosticsParity(
    snapshot: RepositoryActivitySourceSnapshot,
    status: ProjectActivitySourceStatus
  ) throws {
    try #require(status.activitySourceIdentifier == snapshot.identifier)
    try #require(
      status.helpText.contains("storage \(snapshot.activeStorageIdentifier)")
    )
    try #require(
      status.helpText.contains("availability \(snapshot.sourceAvailabilityIdentifier)")
    )
  }

  private func assertBounded(
    _ status: ProjectActivitySourceStatus
  ) throws {
    try #require(status.label.count <= ProjectActivitySourceStatus.labelLimit)
    try #require(status.detail.count <= ProjectActivitySourceStatus.detailLimit)
    try #require(status.helpText.count <= ProjectActivitySourceStatus.helpLimit)
    try #require(status.systemImage.count <= ProjectActivitySourceStatus.systemImageLimit)
    try #require(
      status.accessibilityLabel.count <= ProjectActivitySourceStatus.accessibilityLabelLimit
    )
    try #require(
      status.accessibilityHint.count <= ProjectActivitySourceStatus.accessibilityHintLimit
    )
    try #require(status.severity.rawValue.count <= 16)
  }
}
