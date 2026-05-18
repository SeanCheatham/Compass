import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactRollupTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testRollupBucketsStatusesAndSessionRangeDeterministically() throws {
        let workspace = try makeInitializedWorkspace()
        let statuses = [
            1: "succeeded",
            2: "failed verify",
            3: "cancelled by user",
            4: "skipped",
            5: "retry warning",
            6: "mystery status"
        ]
        for session in 1...6 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-status-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Status Recap \(session)",
                    status: try XCTUnwrap(statuses[session]),
                    commit: "Commit \(session)",
                    body: "status body \(session)"
                )
            )
        }

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(historyPlan: history)

        XCTAssertTrue(rollup.isAvailable)
        XCTAssertEqual(rollup.retainedEntryCount, 6)
        XCTAssertEqual(rollup.matchingEntryCount, 6)
        XCTAssertEqual(rollup.sessionRangeLabel, "S1-S6")
        XCTAssertEqual(rollup.newestSessionNumber, 6)
        XCTAssertEqual(rollup.oldestSessionNumber, 1)
        XCTAssertEqual(bucketCounts(rollup), [
            "cancelled": 1,
            "failed": 1,
            "other": 1,
            "skipped": 1,
            "succeeded": 1,
            "warning": 1
        ])
        XCTAssertTrue(rollup.statusBucketSummary.contains("succeeded 1"))
        XCTAssertTrue(rollup.statusBucketSummary.contains("failed 1"))
        XCTAssertTrue(rollup.exportText.contains("- failed: 1"))
        XCTAssertTrue(rollup.exportText.contains("## Matching Entries"))
    }

    func testRollupUsesSearchAwareCountsWithoutChangingPreviewOrSubsetExports() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-search-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Search Recap \(session)",
                    status: session == 4 ? "failed" : "succeeded",
                    commit: "Search commit \(session)",
                    body: [2, 4].contains(session) ? "needle rollup body" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let fullLibraryExport = history.combinedMarkdownExport
        let expectedEntries = history.entries.filter { [2, 4].contains($0.sessionNumber) }

        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            searchQuery: " NEEDLE   ROLLUP "
        )
        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: " NEEDLE   ROLLUP "
        )
        let filteredExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: " NEEDLE   ROLLUP ",
            scope: .filtered
        )

        XCTAssertTrue(rollup.isAvailable)
        XCTAssertEqual(rollup.searchQuerySnippet, "needle rollup")
        XCTAssertNotEqual(rollup.searchQueryFingerprint, "none")
        XCTAssertEqual(rollup.retainedEntryCount, 4)
        XCTAssertEqual(rollup.matchingEntryCount, 2)
        XCTAssertEqual(rollup.unfilteredVisibleCount, 4)
        XCTAssertEqual(rollup.sessionRangeLabel, "S2-S4")
        XCTAssertEqual(rollup.newestSessionNumber, 4)
        XCTAssertEqual(rollup.oldestSessionNumber, 2)
        XCTAssertEqual(rollup.selectedEntryIdentifier, expectedEntries.first?.identifier)
        XCTAssertEqual(preview.matchCount, rollup.matchingEntryCount)
        XCTAssertEqual(filteredExport.exportedEntryIdentifiers, expectedEntries.map(\.identifier))
        XCTAssertEqual(history.combinedMarkdownExport, fullLibraryExport)
        XCTAssertTrue(rollup.exportText.contains("4-recap-share-search-4.md"))
        XCTAssertTrue(rollup.exportText.contains("2-recap-share-search-2.md"))
        XCTAssertFalse(rollup.exportText.contains("3-recap-share-search-3.md"))
    }

    func testRollupUnavailableForEmptyAndNoMatchHistories() throws {
        let emptyWorkspace = try makeInitializedWorkspace()
        let emptyHistory = emptyWorkspace.refreshRunRecapShareArtifactHistory()
        let emptyRollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: emptyHistory,
            searchQuery: "missing"
        )

        XCTAssertFalse(emptyRollup.isAvailable)
        XCTAssertEqual(emptyRollup.availabilityReason, "no-recap-share-artifacts")
        XCTAssertNil(emptyRollup.noMatchAvailabilityReason)
        XCTAssertEqual(emptyRollup.retainedEntryCount, 0)
        XCTAssertEqual(emptyRollup.matchingEntryCount, 0)
        XCTAssertEqual(emptyRollup.sessionRangeLabel, "none")
        XCTAssertEqual(emptyRollup.copyLabel, "Rollup unavailable")
        XCTAssertTrue(emptyRollup.exportText.contains("unavailable (no-recap-share-artifacts)"))

        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 3,
            name: "recap-share-available.md",
            contents: artifactMarkdown(
                session: 3,
                title: "Available Recap",
                status: "succeeded",
                commit: "Available commit",
                body: "available body"
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let noMatchRollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            searchQuery: "missing query"
        )

        XCTAssertFalse(noMatchRollup.isAvailable)
        XCTAssertEqual(noMatchRollup.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchRollup.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchRollup.retainedEntryCount, 1)
        XCTAssertEqual(noMatchRollup.matchingEntryCount, 0)
        XCTAssertEqual(noMatchRollup.statusBucketSummary, "none")
        XCTAssertTrue(noMatchRollup.exportText.contains("- No-match reason: no-matching-recap-share-artifacts"))
    }

    func testRollupExposesHiddenCleanupAndWarningState() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit
            + CinematicRunRecapShareArtifactHistoryPlan.cleanupCandidateIdentifierLimit
            + 3
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-retained-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Retained Recap \(session)",
                    status: "succeeded",
                    commit: "Retained commit \(session)",
                    body: "retained body \(session)"
                )
            )
        }
        for warningSession in 100..<(100 + CinematicRunRecapShareArtifactHistoryPlan.warningLimit + 2) {
            _ = try workspace.writeSessionArtifact(
                session: warningSession,
                name: "recap-share-corrupt-\(warningSession).md",
                contents: "corrupt rollup warning \(warningSession)"
            )
        }

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(historyPlan: history)

        XCTAssertTrue(rollup.isAvailable)
        XCTAssertEqual(rollup.totalCount, artifactCount)
        XCTAssertEqual(rollup.retainedEntryCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(rollup.hiddenCount, CinematicRunRecapShareArtifactHistoryPlan.cleanupCandidateIdentifierLimit + 3)
        XCTAssertEqual(rollup.cleanupCandidateCount, CinematicRunRecapShareArtifactHistoryPlan.cleanupCandidateIdentifierLimit + 3)
        XCTAssertEqual(rollup.cleanupCandidateIdentifiers.count, CinematicRunRecapShareArtifactHistoryPlan.cleanupCandidateIdentifierLimit)
        XCTAssertEqual(rollup.hiddenCleanupCandidateCount, 3)
        XCTAssertTrue(rollup.hasWarnings)
        XCTAssertEqual(rollup.warningStateIdentifier, "warnings")
        XCTAssertEqual(rollup.warningCount, CinematicRunRecapShareArtifactHistoryPlan.warningLimit + 2)
        XCTAssertEqual(rollup.warningIdentifiers.count, CinematicRunRecapShareArtifactHistoryPlan.warningLimit)
        XCTAssertEqual(rollup.hiddenWarningCount, 2)
        XCTAssertTrue(rollup.insightText.contains("+11 hidden"))
        XCTAssertTrue(rollup.insightText.contains("11 cleanup"))
        XCTAssertTrue(rollup.insightText.contains("6 warning"))
        XCTAssertTrue(rollup.exportText.contains("- Hidden cleanup candidates: 3"))
        XCTAssertTrue(rollup.exportText.contains("- Hidden warnings: 2"))
    }

    func testRollupBoundsIdentifiersInsightExportAndCopyText() throws {
        let workspace = try makeInitializedWorkspace()
        let longNeedle = String(repeating: "Bounded Rollup Needle ", count: 20)
        for session in 1...CinematicRunRecapShareArtifactHistoryPlan.retentionLimit {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-\(String(repeating: "long-name-", count: 14))\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: String(repeating: "Very long rollup title ", count: 14),
                    status: String(repeating: "Very long succeeded status ", count: 10),
                    commit: String(repeating: "Very long commit ", count: 16),
                    body: longNeedle + String(repeating: "bounded rollup body\n", count: 300)
                )
            )
        }

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            searchQuery: longNeedle
        )

        XCTAssertTrue(rollup.isAvailable)
        XCTAssertLessThanOrEqual(rollup.identifier.count, CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.exportIdentifier.count, CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.searchQuerySnippet.count, CinematicRunRecapShareArtifactRollupPlan.searchQuerySnippetMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.statusBucketSummary.count, CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.insightText.count, CinematicRunRecapShareArtifactRollupPlan.insightTextMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.exportTextLength, CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.copyLabel.count, CinematicRunRecapShareArtifactRollupPlan.copyLabelMaxCharacters)
        XCTAssertLessThanOrEqual(rollup.copyHelp.count, CinematicRunRecapShareArtifactRollupPlan.copyHelpMaxCharacters)
        XCTAssertTrue(rollup.exportText.contains("# Compass Recap Artifact Rollup"))
        XCTAssertEqual(rollup.copyLabel, "Copy artifact rollup")
        XCTAssertTrue(rollup.copyHelp.contains("Copy recap artifact rollup"))
    }

    private func bucketCounts(
        _ rollup: CinematicRunRecapShareArtifactRollupPlan
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: rollup.statusBuckets.map { ($0.identifier, $0.count) })
            .filter { $0.value > 0 }
    }

    private func artifactMarkdown(
        session: Int,
        title: String,
        status: String,
        commit: String,
        body: String = "Compass recap body."
    ) -> String {
        """
        # Compass Run Recap Share

        - Artifact: artifact-\(session)
        - Availability: available
        - Session: \(session)
        - Filename: recap-share-\(session).md
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
        \(body)
        ```
        """
    }

    private func makeInitializedWorkspace() throws -> CompassWorkspace {
        let repoURL = try makeTemporaryGitRepository()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        return workspace
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeTemporaryDirectory(prefix: String = "CinematicRunRecapShareArtifactRollupTests") throws -> URL {
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
