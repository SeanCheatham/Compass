import Foundation
import Testing

@testable import Compass

struct ProjectActivitySourceStatusTests {
  @Test
  func testRepoLocalAvailableBaselineIsHidden() {
    let snapshot = makeSnapshot(
      activeStorage: .repoLocal,
      sourceAvailability: .available,
      repoLocalSessionsState: .activeSource
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    #require(!status.isVisible)
    #require(status.kind == .hidden)
    #require(
      status.identifier ==
      "hidden|storage:repo_local|availability:available|repo-local:active-source|repo-local-mode:active"
    )
    #require(status.activitySourceIdentifier == snapshot.identifier)
    #require(status.label == "")
    #require(status.detail == "")
    #require(status.helpText == "")
    #require(status.accessibilityLabel == "")
    #require(status.accessibilityValue == "")
    #require(status.accessibilityHint == "")
    assertBounded(status)
  }

  @Test
  func testApplicationSupportAvailableWithMissingRepoLocalSessionsIsVisible() throws {
    let snapshot = makeSnapshot(
      activeStorage: .applicationSupport,
      sourceAvailability: .available,
      repoLocalSessionsState: .ignoredMissing
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    #require(status.isVisible)
    #require(status.kind == .applicationSupportActive)
    #require(
      status.identifier ==
      "application-support-active|storage:application_support|availability:available|repo-local:ignored-missing|repo-local-mode:ignored"
    )
    #require(status.activitySourceIdentifier == snapshot.identifier)
    #require(status.label == "Activity from Support")
    #require(status.severity == .info)
    #require(status.systemImage == "externaldrive.fill.badge.checkmark")
    #require(status.detail.contains("Application Support sessions.json"))
    #require(status.detail.contains("Repo-local sessions.json is missing and not checked"))
    #require(status.helpText.contains("storage application_support"))
    #require(status.helpText.contains("availability available"))
    #require(status.helpText.contains("repo-local ignored-missing"))
    #require(status.helpText.contains("repo-local-mode ignored"))
    #require(status.accessibilityLabel.contains("Activity source"))
    #require(status.accessibilityValue.contains(status.detail))
    #require(status.accessibilityHint.contains("Read-only"))
    assertBounded(status)
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

    #require(status.isVisible)
    #require(status.kind == .applicationSupportActive)
    #require(status.detail.contains("present but ignored"))
    #require(status.detail.contains("stale repo-local activity"))
    #require(status.helpText.contains("repo-local ignored-compatible"))
    #require(status.identifier.contains("repo-local:ignored-compatible"))
    assertBounded(status)
    try assertDiagnosticsParity(snapshot: snapshot, status: status)
  }

  @Test
  func testIgnoredRepoLocalSessionsStatesUseExplicitCopy() {
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

      #require(status.isVisible)
      #require(
        status.detail.contains(expectedCopy), "Missing \(expectedCopy) for \(state.rawValue)")
      #require(status.helpText.contains("repo-local \(state.rawValue)"))
      assertBounded(status)
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

    #require(status.isVisible)
    #require(status.kind == .applicationSupportUnavailable)
    #require(status.label == "Activity root missing")
    #require(status.severity == .warning)
    #require(status.systemImage == "folder.badge.questionmark")
    #require(status.detail.contains("Application Support activity root is missing"))
    #require(!status.detail.contains("empty source"))
    #require(status.helpText.contains("availability storage-root-missing"))
    #require(status.accessibilityHint.contains("Read-only"))
    assertBounded(status)
    try assertDiagnosticsParity(snapshot: snapshot, status: status)
  }

  @Test
  func testNoRepositoryFallbackIsVisibleAndMatchesDiagnosticsSnapshot() throws {
    let snapshot = RepositoryActivitySourceSnapshot.noRepository(
      activeStorage: .applicationSupport
    )

    let status = ProjectActivitySourceStatus(snapshot: snapshot)

    #require(status.isVisible)
    #require(status.kind == .applicationSupportUnavailable)
    #require(status.label == "No repository activity")
    #require(status.severity == .warning)
    #require(status.detail.contains("No repository is available"))
    #require(status.helpText.contains("availability no-repository"))
    #require(status.helpText.contains("root none"))
    #require(status.helpText.contains("sessions none"))
    #require(status.activitySourceIdentifier == snapshot.identifier)
    assertBounded(status)
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
    #require(status.activitySourceIdentifier == snapshot.identifier)
    #require(
      status.helpText.contains("storage \(snapshot.activeStorageIdentifier)")
    )
    #require(
      status.helpText.contains("availability \(snapshot.sourceAvailabilityIdentifier)")
    )
  }

  private func assertBounded(
    _ status: ProjectActivitySourceStatus
  ) {
    try? #require(status.label.count <= ProjectActivitySourceStatus.labelLimit)
    try? #require(status.detail.count <= ProjectActivitySourceStatus.detailLimit)
    try? #require(status.helpText.count <= ProjectActivitySourceStatus.helpLimit)
    try? #require(status.systemImage.count <= ProjectActivitySourceStatus.systemImageLimit)
    try? #require(
      status.accessibilityLabel.count <= ProjectActivitySourceStatus.accessibilityLabelLimit
    )
    try? #require(
      status.accessibilityHint.count <= ProjectActivitySourceStatus.accessibilityHintLimit
    )
    try? #require(status.severity.rawValue.count <= 16)
  }
}
