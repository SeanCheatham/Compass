import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactSourceReconciliationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testRepoLocalActiveUsesActiveOnlyWithoutRepoLocalRescan() throws {
        let repoURL = try makeTemporaryGitRepository()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        _ = try workspace.writeSessionArtifact(
            session: 4,
            name: "recap-share-active.md",
            contents: artifactMarkdown(title: "Active Recap", status: "succeeded", commit: "Active commit")
        )
        let activeHistory = workspace.refreshRunRecapShareArtifactHistory()
        let activitySource = RepositoryActivitySourceSnapshot.snapshot(
            activeStorage: .repoLocal,
            workspace: workspace
        )

        let plan = workspace.refreshRunRecapShareArtifactSourceReconciliation(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: activitySource
        )

        XCTAssertEqual(plan.stateIdentifier, "active-only")
        XCTAssertFalse(plan.isApplicationSupportComparison)
        XCTAssertEqual(plan.activeStorageIdentifier, "repo_local")
        XCTAssertEqual(plan.activeTotalCount, 1)
        XCTAssertEqual(plan.repoLocalTotalCount, 0)
        XCTAssertEqual(plan.repoLocalHistoryIdentifier, "not-scanned")
        XCTAssertEqual(plan.activeLatestSessionNumber, 4)
        XCTAssertEqual(plan.warningStateIdentifier, "clear")
    }

    func testApplicationSupportCompatibleAndMissingRepoLocalStatesAreBounded() throws {
        let repoURL = try makeTemporaryGitRepository()
        let supportWorkspace = try makeApplicationSupportWorkspace(repoURL: repoURL)
        let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
        try supportWorkspace.initialize()
        try repoLocalWorkspace.initialize()
        let contents = artifactMarkdown(
            title: "Compatible Recap",
            status: "succeeded",
            commit: "Compatible commit"
        )
        _ = try supportWorkspace.writeSessionArtifact(
            session: 11,
            name: "recap-share-compatible.md",
            contents: contents
        )
        _ = try repoLocalWorkspace.writeSessionArtifact(
            session: 11,
            name: "recap-share-compatible.md",
            contents: contents
        )
        let activeHistory = supportWorkspace.refreshRunRecapShareArtifactHistory()
        let activitySource = RepositoryActivitySourceSnapshot.snapshot(
            activeStorage: .applicationSupport,
            workspace: supportWorkspace
        )

        let compatible = supportWorkspace.refreshRunRecapShareArtifactSourceReconciliation(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: activitySource
        )

        XCTAssertEqual(compatible.stateIdentifier, "compatible")
        XCTAssertTrue(compatible.isApplicationSupportComparison)
        XCTAssertEqual(compatible.activeTotalCount, 1)
        XCTAssertEqual(compatible.repoLocalTotalCount, 1)
        XCTAssertEqual(compatible.activeLatestSessionNumber, 11)
        XCTAssertEqual(compatible.repoLocalLatestSessionNumber, 11)
        XCTAssertEqual(compatible.representativeActiveEntryIdentifiers, compatible.representativeRepoLocalEntryIdentifiers)
        XCTAssertLessThanOrEqual(
            compatible.identifier.count,
            CinematicRunRecapShareArtifactSourceReconciliationPlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            compatible.activeSessionsDisplayText.count,
            CinematicRunRecapShareArtifactSourceReconciliationPlan.pathDisplayMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            compatible.repoLocalSessionsDisplayText.count,
            CinematicRunRecapShareArtifactSourceReconciliationPlan.pathDisplayMaxCharacters
        )

        try FileManager.default.removeItem(at: repoLocalWorkspace.compassURL)
        let missingRepoLocal = supportWorkspace.refreshRunRecapShareArtifactSourceReconciliation(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: activitySource
        )

        XCTAssertEqual(missingRepoLocal.stateIdentifier, "repo-local-missing")
        XCTAssertEqual(missingRepoLocal.repoLocalAvailabilityReason, "sessions-directory-unavailable")
        XCTAssertEqual(missingRepoLocal.repoLocalTotalCount, 0)
    }

    func testApplicationSupportDivergenceReportsRepoLocalExtraReadOnly() throws {
        let repoURL = try makeTemporaryGitRepository()
        let supportWorkspace = try makeApplicationSupportWorkspace(repoURL: repoURL)
        let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
        try supportWorkspace.initialize()
        try repoLocalWorkspace.initialize()
        let sharedContents = artifactMarkdown(
            title: "Shared Recap",
            status: "succeeded",
            commit: "Shared commit"
        )
        _ = try supportWorkspace.writeSessionArtifact(
            session: 20,
            name: "recap-share-shared.md",
            contents: sharedContents
        )
        _ = try repoLocalWorkspace.writeSessionArtifact(
            session: 20,
            name: "recap-share-shared.md",
            contents: sharedContents
        )
        let extraURL = try repoLocalWorkspace.writeSessionArtifact(
            session: 21,
            name: "recap-share-extra.md",
            contents: artifactMarkdown(title: "Extra Recap", status: "failed", commit: "Extra commit")
        )
        let extraContentsBefore = try String(contentsOf: extraURL, encoding: .utf8)
        let activeHistory = supportWorkspace.refreshRunRecapShareArtifactHistory()
        let activitySource = RepositoryActivitySourceSnapshot.snapshot(
            activeStorage: .applicationSupport,
            workspace: supportWorkspace
        )

        let plan = supportWorkspace.refreshRunRecapShareArtifactSourceReconciliation(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: activitySource
        )

        XCTAssertEqual(plan.stateIdentifier, "repo-local-extra")
        XCTAssertEqual(plan.activeTotalCount, 1)
        XCTAssertEqual(plan.repoLocalTotalCount, 2)
        XCTAssertEqual(plan.activeLatestSessionNumber, 20)
        XCTAssertEqual(plan.repoLocalLatestSessionNumber, 21)
        XCTAssertEqual(plan.representativeRepoLocalExtraEntryIdentifiers.count, 1)
        XCTAssertTrue(plan.representativeRepoLocalExtraEntryIdentifiers[0].contains("session:21"))
        XCTAssertEqual(try String(contentsOf: extraURL, encoding: .utf8), extraContentsBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extraURL.path))
        XCTAssertEqual(supportWorkspace.refreshRunRecapShareArtifactHistory(), activeHistory)
    }

    @MainActor
    func testActiveMissingRepoLocalAvailableThreadsThroughProjectDiagnosticsReadOnly() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let supportWorkspace = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        ).workspace
        let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
        try repoLocalWorkspace.initialize()
        let repoLocalArtifactURL = try repoLocalWorkspace.writeSessionArtifact(
            session: 33,
            name: "recap-share-repo-local.md",
            contents: artifactMarkdown(
                title: "Repo Local Recap",
                status: "succeeded",
                commit: "Repo local commit"
            )
        )
        let repoLocalContentsBefore = try String(contentsOf: repoLocalArtifactURL, encoding: .utf8)
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )

        await project.refresh()

        let plan = project.cinematicRunRecapShareArtifactSourceReconciliation
        let activeHistoryAvailability = project.cinematicRunRecapShareArtifactHistory.availabilityReason
        let report = CinematicDiagnostics.currentReport(for: project)
        let summary = CinematicDiagnosticsSummary(report: report)
        let row = try XCTUnwrap(summary.row(id: "run-recap-share-artifact-sources"))

        XCTAssertEqual(activeHistoryAvailability, "storage-root-missing")
        XCTAssertEqual(plan.stateIdentifier, "active-missing-repo-local-available")
        XCTAssertEqual(plan.activeStorageIdentifier, "application_support")
        XCTAssertEqual(plan.activeTotalCount, 0)
        XCTAssertEqual(plan.repoLocalTotalCount, 1)
        XCTAssertEqual(plan.repoLocalLatestSessionNumber, 33)
        XCTAssertEqual(report.runRecapShareArtifactSourceReconciliation.identifier, plan.identifier)
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-sources:\(plan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-sources-active:\(plan.activeHistoryIdentifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-sources-repo-local:\(plan.repoLocalHistoryIdentifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-sources-activity-source:\(plan.activitySourceIdentifier)"))
        XCTAssertTrue(row.detail.contains("state active-missing-repo-local-available"))
        XCTAssertTrue(row.detail.contains("active total 0"))
        XCTAssertTrue(row.detail.contains("repo-local total 1"))
        XCTAssertTrue(row.detail.contains("repo-local latest S33"))
        XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(summary.exportText.contains("Recap artifact sources:"))
        XCTAssertTrue(summary.exportText.contains("state active-missing-repo-local-available"))
        XCTAssertTrue(summary.exportText.contains("repo-local total 1"))
        XCTAssertEqual(try String(contentsOf: repoLocalArtifactURL, encoding: .utf8), repoLocalContentsBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportWorkspace.compassURL.path))
    }

    func testScanWarningsStateIncludesBoundedWarningCounts() throws {
        let repoURL = try makeTemporaryGitRepository()
        let supportWorkspace = try makeApplicationSupportWorkspace(repoURL: repoURL)
        let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
        try supportWorkspace.initialize()
        try repoLocalWorkspace.initialize()
        _ = try supportWorkspace.writeSessionArtifact(
            session: 41,
            name: "recap-share-active.md",
            contents: artifactMarkdown(title: "Active Recap", status: "succeeded", commit: "Active commit")
        )
        _ = try repoLocalWorkspace.writeSessionArtifact(
            session: 42,
            name: "recap-share-corrupt.md",
            contents: "not a recap share artifact"
        )
        let activeHistory = supportWorkspace.refreshRunRecapShareArtifactHistory()
        let activitySource = RepositoryActivitySourceSnapshot.snapshot(
            activeStorage: .applicationSupport,
            workspace: supportWorkspace
        )

        let plan = supportWorkspace.refreshRunRecapShareArtifactSourceReconciliation(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: activitySource
        )

        XCTAssertEqual(plan.stateIdentifier, "scan-warnings")
        XCTAssertEqual(plan.activeWarningCount, 0)
        XCTAssertEqual(plan.repoLocalWarningCount, 1)
        XCTAssertEqual(plan.warningStateIdentifier, "warnings")
        XCTAssertEqual(plan.repoLocalAvailabilityReason, "no-recap-share-artifacts")
        XCTAssertLessThanOrEqual(
            plan.repoLocalHistoryIdentifier.count,
            CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )
    }

    private func makeApplicationSupportWorkspace(repoURL: URL) throws -> CompassWorkspace {
        let root = try makeTemporaryDirectory(prefix: "RecapArtifactSourcesSupport")
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: "project-storage", directoryHint: .isDirectory)
        return CompassWorkspace(repoURL: repoURL, storageRootURL: root)
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let root = try makeTemporaryDirectory(prefix: "RecapArtifactSourcesKnownProjects")
        return KnownProjectStore.ApplicationSupportRoots(
            current: root.appending(path: "Current", directoryHint: .isDirectory),
            legacy: root.appending(path: "Legacy", directoryHint: .isDirectory)
        )
    }

    private func artifactMarkdown(
        title: String,
        status: String,
        commit: String
    ) -> String {
        """
        # Compass Run Recap Share

        - Artifact: artifact-id
        - Availability: available
        - Session: 1
        - Filename: recap-share.md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Detail text
        - Commit: \(commit)

        ## Events
        - event

        ## Share Text

        ```text
        Compass recap body.
        ```
        """
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeTemporaryDirectory(prefix: String = "CinematicRunRecapShareArtifactSourceTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
