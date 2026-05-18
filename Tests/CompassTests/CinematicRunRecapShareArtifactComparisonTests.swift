import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactComparisonTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testComparisonTargetsNearestOlderMatchingArtifact() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-adjacent-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Adjacent Recap \(session)",
                    status: "succeeded",
                    commit: "Adjacent commit \(session)",
                    body: "Adjacent body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let target = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })

        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier
        )

        XCTAssertTrue(comparison.isAvailable)
        XCTAssertEqual(comparison.availabilityReason, "available")
        XCTAssertEqual(comparison.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(comparison.compareEntryIdentifier, target.identifier)
        XCTAssertEqual(comparison.targetDirectionIdentifier, "older")
        XCTAssertEqual(comparison.sessionDelta, 1)
        XCTAssertEqual(comparison.selectedSessionNumber, 3)
        XCTAssertEqual(comparison.compareSessionNumber, 2)
        XCTAssertEqual(comparison.selectedTitleSnippet, "Adjacent Recap 3")
        XCTAssertEqual(comparison.compareTitleSnippet, "Adjacent Recap 2")
        XCTAssertEqual(comparison.selectedStatusSnippet, "succeeded")
        XCTAssertEqual(comparison.compareCommitSnippet, "Adjacent commit 2")
        XCTAssertTrue(comparison.selectedBodyPreviewText?.contains("Adjacent body 3") == true)
        XCTAssertTrue(comparison.compareBodyPreviewText?.contains("Adjacent body 2") == true)
        XCTAssertTrue(comparison.exportText.contains("- Target direction: older"))
        XCTAssertTrue(comparison.exportText.contains("## Selected Artifact"))
        XCTAssertTrue(comparison.exportText.contains("## Comparison Target"))
        XCTAssertEqual(comparison.copyLabel, "Copy comparison")
    }

    func testComparisonUsesOlderFromNewestAndNewerFallbackFromOldest() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-direction-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Direction Recap \(session)",
                    status: "succeeded",
                    commit: "Direction commit \(session)",
                    body: "Direction body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let newest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let middle = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let oldest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })

        let newestComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(historyPlan: history)
        let oldestComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: oldest.identifier
        )

        XCTAssertEqual(newestComparison.selectedEntryIdentifier, newest.identifier)
        XCTAssertEqual(newestComparison.compareEntryIdentifier, middle.identifier)
        XCTAssertEqual(newestComparison.targetDirectionIdentifier, "older")
        XCTAssertEqual(newestComparison.sessionDelta, 1)

        XCTAssertEqual(oldestComparison.selectedEntryIdentifier, oldest.identifier)
        XCTAssertEqual(oldestComparison.compareEntryIdentifier, middle.identifier)
        XCTAssertEqual(oldestComparison.targetDirectionIdentifier, "newer")
        XCTAssertEqual(oldestComparison.sessionDelta, 1)
        XCTAssertTrue(oldestComparison.exportText.contains("- Target direction: newer"))
    }

    func testSearchAwareComparisonPreservesSiblingPlannerOutputs() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...5 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-search-compare-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Search Compare Recap \(session)",
                    status: session == 5 ? "failed verify" : "succeeded",
                    commit: "Search compare commit \(session)",
                    body: [1, 3, 5].contains(session) ? "compare cluster body" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let target = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let query = " COMPARE   CLUSTER "
        let historyExportBefore = history.combinedMarkdownExport
        let previewBefore = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query
        )
        let selectedExportBefore = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query,
            scope: .selected
        )
        let filteredExportBefore = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query,
            scope: .filtered
        )
        let rollupBefore = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query
        )

        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query
        )

        XCTAssertTrue(comparison.isAvailable)
        XCTAssertTrue(comparison.isSearchActive)
        XCTAssertEqual(comparison.searchQuerySnippet, "compare cluster")
        XCTAssertEqual(comparison.matchingEntryCount, 3)
        XCTAssertEqual(comparison.unfilteredVisibleCount, 5)
        XCTAssertEqual(comparison.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(comparison.compareEntryIdentifier, target.identifier)
        XCTAssertEqual(comparison.targetDirectionIdentifier, "older")
        XCTAssertEqual(comparison.selectedFallbackReasonIdentifier, "none")
        XCTAssertTrue(comparison.exportText.contains("3-recap-share-search-compare-3.md"))
        XCTAssertTrue(comparison.exportText.contains("1-recap-share-search-compare-1.md"))
        XCTAssertFalse(comparison.exportText.contains("2-recap-share-search-compare-2.md"))
        XCTAssertEqual(history.combinedMarkdownExport, historyExportBefore)
        XCTAssertEqual(
            CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: selected.identifier,
                searchQuery: query
            ),
            previewBefore
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: selected.identifier,
                searchQuery: query,
                scope: .selected
            ),
            selectedExportBefore
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: selected.identifier,
                searchQuery: query,
                scope: .filtered
            ),
            filteredExportBefore
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactRollupPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: selected.identifier,
                searchQuery: query
            ),
            rollupBefore
        )
    }

    func testComparisonUnavailableForEmptyNoMatchAndSingleEntryHistories() throws {
        let emptyWorkspace = try makeInitializedWorkspace()
        let emptyComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: emptyWorkspace.refreshRunRecapShareArtifactHistory(),
            searchQuery: "missing"
        )

        XCTAssertFalse(emptyComparison.isAvailable)
        XCTAssertEqual(emptyComparison.availabilityReason, "no-recap-share-artifacts")
        XCTAssertNil(emptyComparison.noMatchAvailabilityReason)
        XCTAssertNil(emptyComparison.selectedEntryIdentifier)
        XCTAssertNil(emptyComparison.compareEntryIdentifier)
        XCTAssertEqual(emptyComparison.targetDirectionIdentifier, "none")

        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-single.md",
            contents: artifactMarkdown(
                session: 1,
                title: "Single Recap",
                status: "succeeded",
                commit: "Single commit",
                body: "single available body"
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let singleComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(historyPlan: history)
        let singleMatchingComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            searchQuery: "single available"
        )
        let noMatchComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            searchQuery: "missing query"
        )

        XCTAssertFalse(singleComparison.isAvailable)
        XCTAssertEqual(singleComparison.availabilityReason, "single-recap-share-artifact")
        XCTAssertEqual(singleComparison.selectedEntryIdentifier, history.entries.first?.identifier)
        XCTAssertNil(singleComparison.compareEntryIdentifier)
        XCTAssertTrue(singleComparison.exportText.contains("unavailable (single-recap-share-artifact)"))

        XCTAssertFalse(singleMatchingComparison.isAvailable)
        XCTAssertEqual(singleMatchingComparison.availabilityReason, "single-matching-recap-share-artifact")
        XCTAssertEqual(singleMatchingComparison.matchingEntryCount, 1)

        XCTAssertFalse(noMatchComparison.isAvailable)
        XCTAssertEqual(noMatchComparison.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchComparison.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchComparison.matchingEntryCount, 0)
        XCTAssertNil(noMatchComparison.selectedEntryIdentifier)
    }

    func testComparisonBoundsSnippetsExportCopyTextAndWarningState() throws {
        let workspace = try makeInitializedWorkspace()
        let repeatedNeedle = String(repeating: "Bounded Compare Needle ", count: 20)
        for session in 8...9 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-\(String(repeating: "long-name-", count: 12))\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: String(repeating: "Very long comparison title ", count: 14),
                    status: String(repeating: "Very long comparison status ", count: 14),
                    commit: String(repeating: "Very long comparison commit ", count: 12),
                    body: repeatedNeedle + String(repeating: "long comparison body\n", count: 400)
                )
            )
        }
        _ = try workspace.writeSessionArtifact(
            session: 10,
            name: "recap-share-corrupt.md",
            contents: "corrupt comparison warning"
        )

        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: workspace.refreshRunRecapShareArtifactHistory(),
            searchQuery: repeatedNeedle
        )

        XCTAssertTrue(comparison.isAvailable)
        XCTAssertTrue(comparison.hasWarnings)
        XCTAssertEqual(comparison.warningStateIdentifier, "warnings")
        XCTAssertEqual(comparison.warningCount, 1)
        XCTAssertEqual(comparison.warningIdentifiers.count, 1)
        XCTAssertLessThanOrEqual(
            comparison.identifier.count,
            CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.exportIdentifier.count,
            CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.searchQuerySnippet.count,
            CinematicRunRecapShareArtifactComparisonPlan.searchQuerySnippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.selectedTitleSnippet?.count ?? 0,
            CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.compareStatusSnippet?.count ?? 0,
            CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.selectedCommitSnippet?.count ?? 0,
            CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.selectedBodyPreviewText?.count ?? 0,
            CinematicRunRecapShareArtifactComparisonPlan.bodyPreviewMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.compareBodyPreviewText?.count ?? 0,
            CinematicRunRecapShareArtifactComparisonPlan.bodyPreviewMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.exportTextLength,
            CinematicRunRecapShareArtifactComparisonPlan.exportTextMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.copyLabel.count,
            CinematicRunRecapShareArtifactComparisonPlan.copyLabelMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            comparison.copyHelp.count,
            CinematicRunRecapShareArtifactComparisonPlan.copyHelpMaxCharacters
        )
        XCTAssertTrue(comparison.exportText.contains("# Compass Recap Artifact Comparison"))
        XCTAssertTrue(comparison.exportText.contains("## Warnings"))
        XCTAssertTrue(comparison.exportText.contains(try XCTUnwrap(comparison.warningIdentifiers.first)))
    }

    func testDiagnosticsExposeComparisonSnapshotSummaryExportAndIdentifierCorrelation() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 10...11 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-diagnostics-compare-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Diagnostics Compare \(session)",
                    status: "succeeded",
                    commit: "Diagnostics compare commit \(session)",
                    body: "diagnostics compare body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 11 })
        let comparisonPlan = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "DIAGNOSTICS   COMPARE"
        )

        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Succeeded",
            immediateTitle: "Expose recap artifact comparison diagnostics",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: history,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: selected.identifier,
            runRecapShareArtifactPreviewSearchQuery: "DIAGNOSTICS   COMPARE"
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-comparison" })

        XCTAssertTrue(report.runRecapShareArtifactComparison.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactComparison.identifier, comparisonPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.exportIdentifier, comparisonPlan.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.searchQuerySnippet, "diagnostics compare")
        XCTAssertEqual(report.runRecapShareArtifactComparison.matchingEntryCount, 2)
        XCTAssertEqual(report.runRecapShareArtifactComparison.unfilteredVisibleCount, 2)
        XCTAssertEqual(report.runRecapShareArtifactComparison.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.compareSessionNumber, 10)
        XCTAssertEqual(report.runRecapShareArtifactComparison.targetDirectionIdentifier, "older")
        XCTAssertEqual(report.runRecapShareArtifactComparison.sessionDelta, 1)
        XCTAssertEqual(report.runRecapShareArtifactComparison.exportTextLength, comparisonPlan.exportTextLength)
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-comparison:\(comparisonPlan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-comparison-export:\(comparisonPlan.exportIdentifier)"))
        XCTAssertTrue(row.detail.contains("available"))
        XCTAssertTrue(row.detail.contains("search diagnostics compare"))
        XCTAssertTrue(row.detail.contains("matches 2/2"))
        XCTAssertTrue(row.detail.contains("selected S11"))
        XCTAssertTrue(row.detail.contains("target S10"))
        XCTAssertTrue(row.detail.contains("direction older"))
        XCTAssertTrue(row.detail.contains("delta 1"))
        XCTAssertTrue(row.detail.contains("copy \(comparisonPlan.exportTextLength) chars"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact compare: available"))
        XCTAssertTrue(summary.exportText.contains("matches 2/2"))
        XCTAssertTrue(summary.exportText.contains("direction older"))
        XCTAssertTrue(summary.exportText.contains("selected S11"))
        XCTAssertTrue(summary.exportText.contains("target S10"))
    }

    private func artifactMarkdown(
        session: Int,
        title: String,
        status: String,
        commit: String,
        body: String
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
        - Detail: Comparison detail
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
        try FileManager.default.createDirectory(
            at: directory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CinematicRunRecapShareArtifactComparisonTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
