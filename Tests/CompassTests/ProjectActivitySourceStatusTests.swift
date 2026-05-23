import Foundation
@testable import Compass
import XCTest

final class ProjectActivitySourceStatusTests: XCTestCase {
    func testRepoLocalAvailableBaselineIsHidden() {
        let snapshot = makeSnapshot(
            activeStorage: .repoLocal,
            sourceAvailability: .available,
            repoLocalSessionsState: .activeSource
        )

        let status = ProjectActivitySourceStatus(snapshot: snapshot)

        XCTAssertFalse(status.isVisible)
        XCTAssertEqual(status.kind, .hidden)
        XCTAssertEqual(
            status.identifier,
            "hidden|storage:repo_local|availability:available|repo-local:active-source|repo-local-mode:active"
        )
        XCTAssertEqual(status.activitySourceIdentifier, snapshot.identifier)
        XCTAssertEqual(status.label, "")
        XCTAssertEqual(status.detail, "")
        XCTAssertEqual(status.helpText, "")
        XCTAssertEqual(status.accessibilityLabel, "")
        XCTAssertEqual(status.accessibilityValue, "")
        XCTAssertEqual(status.accessibilityHint, "")
        assertBounded(status)
    }

    func testApplicationSupportAvailableWithMissingRepoLocalSessionsIsVisible() throws {
        let snapshot = makeSnapshot(
            activeStorage: .applicationSupport,
            sourceAvailability: .available,
            repoLocalSessionsState: .ignoredMissing
        )

        let status = ProjectActivitySourceStatus(snapshot: snapshot)

        XCTAssertTrue(status.isVisible)
        XCTAssertEqual(status.kind, .applicationSupportActive)
        XCTAssertEqual(
            status.identifier,
            "application-support-active|storage:application_support|availability:available|repo-local:ignored-missing|repo-local-mode:ignored"
        )
        XCTAssertEqual(status.activitySourceIdentifier, snapshot.identifier)
        XCTAssertEqual(status.label, "Activity from Support")
        XCTAssertEqual(status.severity, .info)
        XCTAssertEqual(status.systemImage, "externaldrive.fill.badge.checkmark")
        XCTAssertTrue(status.detail.contains("Application Support sessions.json"))
        XCTAssertTrue(status.detail.contains("Repo-local sessions.json is missing and ignored"))
        XCTAssertTrue(status.helpText.contains("storage application_support"))
        XCTAssertTrue(status.helpText.contains("availability available"))
        XCTAssertTrue(status.helpText.contains("repo-local ignored-missing"))
        XCTAssertTrue(status.helpText.contains("repo-local-mode ignored"))
        XCTAssertTrue(status.accessibilityLabel.contains("Activity source"))
        XCTAssertTrue(status.accessibilityValue.contains(status.detail))
        XCTAssertTrue(status.accessibilityHint.contains("Read-only"))
        assertBounded(status)
        try assertDiagnosticsParity(snapshot: snapshot, status: status)
    }

    func testApplicationSupportAvailableWithCompatibleRepoLocalSessionsMarksStaleIgnoredRecord() throws {
        let snapshot = makeSnapshot(
            activeStorage: .applicationSupport,
            sourceAvailability: .available,
            repoLocalSessionsState: .ignoredCompatible
        )

        let status = ProjectActivitySourceStatus(snapshot: snapshot)

        XCTAssertTrue(status.isVisible)
        XCTAssertEqual(status.kind, .applicationSupportActive)
        XCTAssertTrue(status.detail.contains("present but ignored"))
        XCTAssertTrue(status.detail.contains("stale repo-local activity"))
        XCTAssertTrue(status.helpText.contains("repo-local ignored-compatible"))
        XCTAssertTrue(status.identifier.contains("repo-local:ignored-compatible"))
        assertBounded(status)
        try assertDiagnosticsParity(snapshot: snapshot, status: status)
    }

    func testIgnoredRepoLocalSessionsStatesUseExplicitCopy() {
        let cases: [(RepositoryActivitySourceSnapshot.RepoLocalSessionsState, String)] = [
            (.ignoredMissing, "missing and ignored"),
            (.ignoredCompatible, "present but ignored as stale"),
            (.ignoredOversized, "oversized and ignored"),
            (.ignoredUnreadable, "unreadable and ignored")
        ]

        for (state, expectedCopy) in cases {
            let snapshot = makeSnapshot(
                activeStorage: .applicationSupport,
                sourceAvailability: .available,
                repoLocalSessionsState: state
            )
            let status = ProjectActivitySourceStatus(snapshot: snapshot)

            XCTAssertTrue(status.isVisible)
            XCTAssertTrue(status.detail.contains(expectedCopy), "Missing \(expectedCopy) for \(state.rawValue)")
            XCTAssertTrue(status.helpText.contains("repo-local \(state.rawValue)"))
            assertBounded(status)
        }
    }

    func testMissingActiveSupportRootIsVisibleAndReadOnly() throws {
        let snapshot = makeSnapshot(
            activeStorage: .applicationSupport,
            sourceAvailability: .storageRootMissing,
            repoLocalSessionsState: .ignoredMissing
        )

        let status = ProjectActivitySourceStatus(snapshot: snapshot)

        XCTAssertTrue(status.isVisible)
        XCTAssertEqual(status.kind, .applicationSupportUnavailable)
        XCTAssertEqual(status.label, "Activity root missing")
        XCTAssertEqual(status.severity, .warning)
        XCTAssertEqual(status.systemImage, "folder.badge.questionmark")
        XCTAssertTrue(status.detail.contains("Application Support activity root is missing"))
        XCTAssertTrue(status.detail.contains("empty source"))
        XCTAssertTrue(status.helpText.contains("availability storage-root-missing"))
        XCTAssertTrue(status.accessibilityHint.contains("Read-only"))
        assertBounded(status)
        try assertDiagnosticsParity(snapshot: snapshot, status: status)
    }

    func testNoRepositoryFallbackIsVisibleAndMatchesDiagnosticsSnapshot() throws {
        let snapshot = RepositoryActivitySourceSnapshot.noRepository(
            activeStorage: .applicationSupport
        )

        let status = ProjectActivitySourceStatus(snapshot: snapshot)

        XCTAssertTrue(status.isVisible)
        XCTAssertEqual(status.kind, .applicationSupportUnavailable)
        XCTAssertEqual(status.label, "No repository activity")
        XCTAssertEqual(status.severity, .warning)
        XCTAssertTrue(status.detail.contains("No repository is available"))
        XCTAssertTrue(status.helpText.contains("availability no-repository"))
        XCTAssertTrue(status.helpText.contains("root none"))
        XCTAssertTrue(status.helpText.contains("sessions none"))
        XCTAssertEqual(status.activitySourceIdentifier, snapshot.identifier)
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
            activeRoot = repoURL
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
        status: ProjectActivitySourceStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(status.activitySourceIdentifier, snapshot.identifier, file: file, line: line)
        XCTAssertTrue(
            status.helpText.contains("storage \(snapshot.activeStorageIdentifier)"),
            file: file,
            line: line
        )
        XCTAssertTrue(
            status.helpText.contains("availability \(snapshot.sourceAvailabilityIdentifier)"),
            file: file,
            line: line
        )
    }

    private func assertBounded(
        _ status: ProjectActivitySourceStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(status.label.count, ProjectActivitySourceStatus.labelLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(status.detail.count, ProjectActivitySourceStatus.detailLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(status.helpText.count, ProjectActivitySourceStatus.helpLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(
            status.systemImage.count,
            ProjectActivitySourceStatus.systemImageLimit,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            status.accessibilityLabel.count,
            ProjectActivitySourceStatus.accessibilityLabelLimit,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            status.accessibilityHint.count,
            ProjectActivitySourceStatus.accessibilityHintLimit,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(status.severity.rawValue.count, 16, file: file, line: line)
    }
}
