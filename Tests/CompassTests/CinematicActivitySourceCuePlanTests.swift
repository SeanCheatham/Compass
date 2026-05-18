import Foundation
@testable import Compass
import XCTest

final class CinematicActivitySourceCuePlanTests: XCTestCase {
    func testRepoLocalAvailableBaselineIsHidden() {
        let snapshot = makeActivitySourceSnapshot(
            activeStorage: .repoLocal,
            sourceAvailability: .available,
            repoLocalSessionsState: .activeSource
        )
        let status = ProjectActivitySourceStatus(snapshot: snapshot)

        let cue = CinematicActivitySourceCuePlan(snapshot: snapshot, status: status)

        XCTAssertFalse(cue.isVisible)
        XCTAssertFalse(cue.isCritical)
        XCTAssertFalse(cue.isQuietModeSuppressible)
        XCTAssertEqual(cue.kindIdentifier, "hidden")
        XCTAssertEqual(cue.severityIdentifier, "healthy")
        XCTAssertEqual(cue.tintIdentifier, "green")
        XCTAssertEqual(cue.label, "")
        XCTAssertEqual(cue.detail, "")
        XCTAssertEqual(cue.helpText, "")
        XCTAssertEqual(cue.copyText, "")
        XCTAssertEqual(cue.statusIdentifier, status.identifier)
        XCTAssertEqual(
            cue.identifier,
            "activity-source-cue|hidden|storage:repo_local|availability:available|repo-local:active-source|repo-local-mode:active"
        )
        assertBounded(cue)
    }

    func testApplicationSupportAvailableWithMissingAndCompatibleRepoLocalRecordsIsVisible() {
        let cases: [(RepositoryActivitySourceSnapshot.RepoLocalSessionsState, String)] = [
            (.ignoredMissing, "missing and ignored"),
            (.ignoredCompatible, "present but ignored as stale")
        ]

        for (state, expectedCopy) in cases {
            let snapshot = makeActivitySourceSnapshot(
                activeStorage: .applicationSupport,
                sourceAvailability: .available,
                repoLocalSessionsState: state
            )

            let cue = CinematicActivitySourceCuePlan(snapshot: snapshot)

            XCTAssertTrue(cue.isVisible, state.rawValue)
            XCTAssertFalse(cue.isCritical, state.rawValue)
            XCTAssertTrue(cue.isQuietModeSuppressible, state.rawValue)
            XCTAssertEqual(cue.kindIdentifier, "application-support-active")
            XCTAssertEqual(cue.severityIdentifier, "info")
            XCTAssertEqual(cue.tintIdentifier, "blue")
            XCTAssertEqual(cue.systemImage, "externaldrive.fill.badge.checkmark")
            XCTAssertEqual(cue.activeStorageIdentifier, "application_support")
            XCTAssertEqual(cue.availabilityIdentifier, "available")
            XCTAssertEqual(cue.repoLocalSessionsStateIdentifier, state.rawValue)
            XCTAssertTrue(cue.label.contains("Support"), state.rawValue)
            XCTAssertTrue(cue.detail.contains("Application Support sessions.json"), state.rawValue)
            XCTAssertTrue(cue.detail.contains(expectedCopy), state.rawValue)
            XCTAssertTrue(cue.helpText.contains("repo-local \(state.rawValue)"), state.rawValue)
            XCTAssertTrue(cue.copyText.contains("policy-source application-support-active"), state.rawValue)
            assertBounded(cue)
        }
    }

    func testMissingUnreadableAndOversizedActiveSessionsRecordsStayCriticalAndVisible() {
        let cases: [(RepositoryActivitySourceSnapshot.SourceAvailability, String, String, Bool)] = [
            (.sessionsRecordMissing, "warning", "orange", true),
            (.sessionsRecordUnreadable, "failure", "red", true),
            (.sessionsRecordOversized, "failure", "red", true)
        ]

        for (availability, severity, tint, critical) in cases {
            let snapshot = makeActivitySourceSnapshot(
                activeStorage: .applicationSupport,
                sourceAvailability: availability,
                repoLocalSessionsState: .ignoredMissing
            )

            let cue = CinematicActivitySourceCuePlan(snapshot: snapshot)

            XCTAssertTrue(cue.isVisible, availability.rawValue)
            XCTAssertEqual(cue.isCritical, critical, availability.rawValue)
            XCTAssertFalse(cue.isQuietModeSuppressible, availability.rawValue)
            XCTAssertEqual(cue.kindIdentifier, "application-support-unavailable")
            XCTAssertEqual(cue.availabilityIdentifier, availability.rawValue)
            XCTAssertEqual(cue.severityIdentifier, severity)
            XCTAssertEqual(cue.tintIdentifier, tint)
            XCTAssertTrue(cue.detail.contains("sessions.json"), availability.rawValue)
            XCTAssertTrue(cue.identifier.contains("availability:\(availability.rawValue)"), availability.rawValue)
            assertBounded(cue)
        }
    }

    func testBoundedCopyAndIdentifiersForLongStoragePaths() {
        let longComponent = String(repeating: "VeryLongCompassActivitySourcePath", count: 16)
        let repoURL = URL(fileURLWithPath: "/tmp/\(longComponent)", isDirectory: true)
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: longComponent, directoryHint: .isDirectory)
        let snapshot = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .sessionsRecordUnreadable,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredUnreadable
        )

        let cue = CinematicActivitySourceCuePlan(snapshot: snapshot)

        XCTAssertTrue(cue.isVisible)
        XCTAssertTrue(cue.isCritical)
        XCTAssertLessThanOrEqual(cue.identifier.count, CinematicActivitySourceCuePlan.identifierLimit)
        XCTAssertLessThanOrEqual(cue.sourceIdentifier.count, CinematicActivitySourceCuePlan.sourceIdentifierLimit)
        XCTAssertLessThanOrEqual(cue.statusIdentifier.count, CinematicActivitySourceCuePlan.identifierLimit)
        assertBounded(cue)
    }

    private func assertBounded(
        _ cue: CinematicActivitySourceCuePlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(cue.identifier.count, CinematicActivitySourceCuePlan.identifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.sourceIdentifier.count, CinematicActivitySourceCuePlan.sourceIdentifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.statusIdentifier.count, CinematicActivitySourceCuePlan.identifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.label.count, CinematicActivitySourceCuePlan.labelLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.detail.count, CinematicActivitySourceCuePlan.detailLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.helpText.count, CinematicActivitySourceCuePlan.helpLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.systemImage.count, CinematicActivitySourceCuePlan.systemImageLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.tintIdentifier.count, CinematicActivitySourceCuePlan.tintIdentifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(cue.copyText.count, CinematicActivitySourceCuePlan.copyTextLimit, file: file, line: line)
    }
}

private func makeActivitySourceSnapshot(
    activeStorage: KnownProjectActiveStorage,
    sourceAvailability: RepositoryActivitySourceSnapshot.SourceAvailability,
    repoLocalSessionsState: RepositoryActivitySourceSnapshot.RepoLocalSessionsState
) -> RepositoryActivitySourceSnapshot {
    let repoURL = URL(fileURLWithPath: "/tmp/CompassCinematicActivitySourceCue", isDirectory: true)
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
