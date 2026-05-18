import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactPinnedComparisonTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testAdjacentModeRemainsDefaultEvenWithPinnedContext() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-adjacent-default-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Adjacent Default \(session)",
                    status: "succeeded",
                    commit: "Adjacent default commit \(session)",
                    body: "adjacent default body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let newest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let middle = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let oldest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })

        let defaultComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: newest.identifier
        )
        let adjacentComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: newest.identifier,
            targetMode: .adjacent,
            pinnedEntryIdentifiers: [oldest.identifier]
        )

        XCTAssertEqual(defaultComparison.compareEntryIdentifier, middle.identifier)
        XCTAssertEqual(adjacentComparison.compareEntryIdentifier, middle.identifier)
        XCTAssertEqual(adjacentComparison.targetMode, .adjacent)
        XCTAssertEqual(adjacentComparison.targetModeIdentifier, "adjacent")
        XCTAssertEqual(adjacentComparison.targetDirectionIdentifier, "older")
        XCTAssertNil(adjacentComparison.pinnedTargetEntryIdentifier)
        XCTAssertEqual(adjacentComparison.pinnedTargetStateIdentifier, "adjacent-mode")
        XCTAssertEqual(adjacentComparison.retainedPinnedEntryIdentifiers, [oldest.identifier])
        XCTAssertEqual(adjacentComparison.copyLabel, "Copy comparison")
        XCTAssertTrue(adjacentComparison.exportText.contains("- Comparison mode: adjacent"))
    }

    func testPinnedModePrefersSearchVisibleRetainedPinOtherThanSelection() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-pinned-target-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Pinned Target \(session)",
                    status: "succeeded",
                    commit: "Pinned target commit \(session)",
                    body: [2, 4].contains(session) ? "visible comparison beacon" : "ordinary pinned body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 4 })
        let filteredFirstPin = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let visibleSecondPin = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let stalePin = "stale-pinned-comparison"

        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "VISIBLE   COMPARISON",
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [
                selected.identifier,
                filteredFirstPin.identifier,
                visibleSecondPin.identifier,
                stalePin
            ]
        )

        XCTAssertTrue(comparison.isAvailable)
        XCTAssertEqual(comparison.targetMode, .pinnedReference)
        XCTAssertEqual(comparison.targetModeIdentifier, "pinned_reference")
        XCTAssertEqual(comparison.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(comparison.compareEntryIdentifier, visibleSecondPin.identifier)
        XCTAssertEqual(comparison.pinnedTargetEntryIdentifier, visibleSecondPin.identifier)
        XCTAssertEqual(comparison.targetDirectionIdentifier, "pinned")
        XCTAssertEqual(comparison.pinnedTargetStateIdentifier, "visible-pinned-target")
        XCTAssertNil(comparison.pinnedTargetUnavailableReasonIdentifier)
        XCTAssertEqual(comparison.pinnedEntryCount, 4)
        XCTAssertEqual(comparison.retainedPinnedEntryCount, 3)
        XCTAssertEqual(comparison.missingPinnedEntryIdentifiers, [stalePin])
        XCTAssertEqual(comparison.filteredPinnedEntryIdentifiers, [filteredFirstPin.identifier])
        XCTAssertEqual(comparison.sessionDelta, 2)
        XCTAssertEqual(comparison.copyLabel, "Copy pinned comparison")
        XCTAssertTrue(comparison.exportText.contains("- Pinned target: \(visibleSecondPin.identifier)"))
        XCTAssertTrue(comparison.exportText.contains("- Missing pins: 1"))
        XCTAssertTrue(comparison.exportText.contains("- Filtered pins: 1"))
    }

    func testPinnedModeReportsSelectedOnlyNoMatchAndStalePinStates() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...2 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-pinned-unavailable-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Pinned Unavailable \(session)",
                    status: "succeeded",
                    commit: "Pinned unavailable commit \(session)",
                    body: "pinned unavailable body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let retainedOther = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let stalePin = "missing-pinned-comparison-target"

        let selectedOnly = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [selected.identifier]
        )
        let noMatch = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "missing comparison query",
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [selected.identifier, retainedOther.identifier]
        )
        let staleOnly = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [stalePin]
        )

        XCTAssertFalse(selectedOnly.isAvailable)
        XCTAssertEqual(selectedOnly.availabilityReason, "selected-only-pinned-recap-share-artifact")
        XCTAssertEqual(selectedOnly.pinnedTargetStateIdentifier, "selected-only-pinned-recap-share-artifact")
        XCTAssertEqual(selectedOnly.pinnedTargetUnavailableReasonIdentifier, "selected-only-pinned-recap-share-artifact")

        XCTAssertFalse(noMatch.isAvailable)
        XCTAssertEqual(noMatch.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatch.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatch.pinnedTargetStateIdentifier, "no-selected-recap-share-artifact")
        XCTAssertEqual(noMatch.filteredPinnedEntryCount, 2)

        XCTAssertFalse(staleOnly.isAvailable)
        XCTAssertEqual(staleOnly.availabilityReason, "pinned-recap-share-artifacts-missing")
        XCTAssertEqual(staleOnly.missingPinnedEntryIdentifiers, [stalePin])
        XCTAssertEqual(staleOnly.pinnedTargetUnavailableReasonIdentifier, "pinned-recap-share-artifacts-missing")
    }

    func testDiagnosticsExposePinnedComparisonSnapshotExportAndIdentifierCorrelation() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 10...12 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-pinned-diagnostics-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Pinned Diagnostics \(session)",
                    status: "succeeded",
                    commit: "Pinned diagnostics commit \(session)",
                    body: [10, 12].contains(session) ? "diagnostic pinned beacon" : "ordinary diagnostics body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 12 })
        let filtered = try XCTUnwrap(history.entries.first { $0.sessionNumber == 11 })
        let target = try XCTUnwrap(history.entries.first { $0.sessionNumber == 10 })
        let stalePin = "diagnostic-stale-pinned-comparison"
        let comparisonPlan = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "diagnostic pinned beacon",
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [filtered.identifier, target.identifier, stalePin]
        )

        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Succeeded",
            immediateTitle: "Expose pinned comparison diagnostics",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: history,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: selected.identifier,
            runRecapShareArtifactPreviewSearchQuery: "diagnostic pinned beacon",
            runRecapShareArtifactComparisonTargetMode: .pinnedReference,
            runRecapShareArtifactPinnedEntryIdentifiers: [filtered.identifier, target.identifier, stalePin]
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-comparison" })

        XCTAssertEqual(report.runRecapShareArtifactComparison.identifier, comparisonPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.exportIdentifier, comparisonPlan.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.targetModeIdentifier, "pinned_reference")
        XCTAssertEqual(report.runRecapShareArtifactComparison.pinnedTargetEntryIdentifier, target.identifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.pinnedTargetStateIdentifier, "visible-pinned-target")
        XCTAssertEqual(report.runRecapShareArtifactComparison.missingPinnedEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactComparison.filteredPinnedEntryIdentifiers, [filtered.identifier])
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-comparison:\(comparisonPlan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-comparison-export:\(comparisonPlan.exportIdentifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-comparison-mode:pinned_reference"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-comparison-pinned-target:\(target.identifier)"))
        XCTAssertTrue(row.detail.contains("mode pinned_reference"))
        XCTAssertTrue(row.detail.contains("pinned state visible-pinned-target"))
        XCTAssertTrue(row.detail.contains("missing pins 1"))
        XCTAssertTrue(row.detail.contains("filtered pins 1"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact compare: available"))
        XCTAssertTrue(summary.exportText.contains("mode pinned_reference"))
        XCTAssertTrue(summary.exportText.contains("pinned state visible-pinned-target"))
    }

    func testPinnedComparisonPreservesSiblingPlannerOutputs() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-pinned-invariant-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Pinned Invariant \(session)",
                    status: session == 4 ? "failed verify" : "succeeded",
                    commit: "Pinned invariant commit \(session)",
                    body: [2, 4].contains(session) ? "pinned invariant cluster" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 4 })
        let pinned = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let query = " PINNED   INVARIANT "
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
        let pinPlanBefore = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [selected.identifier, pinned.identifier, "missing-invariant-pin"],
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query
        )

        _ = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [selected.identifier, pinned.identifier, "missing-invariant-pin"]
        )

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
        XCTAssertEqual(
            CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
                historyPlan: history,
                pinnedEntryIdentifiers: [selected.identifier, pinned.identifier, "missing-invariant-pin"],
                selectedEntryIdentifier: selected.identifier,
                searchQuery: query
            ),
            pinPlanBefore
        )
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
        - Filename: recap-share-pinned-comparison-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Pinned comparison detail
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
        let repoURL = try makeTemporaryGitRepository(prefix: "CinematicRunRecapShareArtifactPinnedComparisonRepo")
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        return workspace
    }

    private func makeTemporaryGitRepository(prefix: String) throws -> URL {
        let directory = try makeTemporaryDirectory(prefix: prefix)
        try FileManager.default.createDirectory(
            at: directory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
