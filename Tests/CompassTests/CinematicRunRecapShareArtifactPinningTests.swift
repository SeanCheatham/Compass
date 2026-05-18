import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactPinningTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testContextBoundsDedupesAndRoundTripsPinnedIdentifiers() throws {
        let longIdentifier = String(repeating: "pin-identifier-", count: 40)
        let overflowIdentifiers = (0...CinematicRunRecapShareArtifactLibraryContext.pinnedEntryIdentifierLimit)
            .map { "overflow-pin-\($0)" }
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: " selected-pin ",
            searchText: "  Pinned   Search  ",
            pinnedEntryIdentifiers: [
                "  duplicate-pin  ",
                "duplicate-pin",
                "\n\t ",
                longIdentifier
            ] + overflowIdentifiers,
            comparisonTargetMode: .pinnedReference
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(CinematicRunRecapShareArtifactLibraryContext.self, from: data)
        let olderContextData = try XCTUnwrap("""
        {
          "selectedEntryIdentifier": "older-selection",
          "searchText": "older search"
        }
        """.data(using: .utf8))
        let olderContext = try JSONDecoder().decode(
            CinematicRunRecapShareArtifactLibraryContext.self,
            from: olderContextData
        )

        XCTAssertEqual(decoded, context)
        XCTAssertEqual(context.selectedEntryIdentifier, "selected-pin")
        XCTAssertEqual(context.searchText, "Pinned Search")
        XCTAssertEqual(context.comparisonTargetMode, .pinnedReference)
        XCTAssertEqual(
            context.pinnedEntryIdentifiers.count,
            CinematicRunRecapShareArtifactLibraryContext.pinnedEntryIdentifierLimit
        )
        XCTAssertEqual(context.pinnedEntryIdentifiers.first, "duplicate-pin")
        XCTAssertEqual(Set(context.pinnedEntryIdentifiers).count, context.pinnedEntryIdentifiers.count)
        XCTAssertLessThanOrEqual(
            context.pinnedEntryIdentifiers[1].count,
            CinematicRunRecapShareArtifactLibraryContext.selectedEntryIdentifierMaxCharacters
        )
        XCTAssertEqual(olderContext.pinnedEntryIdentifiers, [])
        XCTAssertEqual(olderContext.comparisonTargetMode, .adjacent)
    }

    func testContextResolutionDropsStalePinsAgainstActiveStorageHistory() throws {
        let repoURL = try makeTemporaryGitRepository(prefix: "PinningActiveStorageRepo")
        let storageRootURL = try makeTemporaryDirectory(prefix: "PinningActiveStorage")
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: "project-storage", directoryHint: .isDirectory)
        let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
        try workspace.initialize()

        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-active-pins-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Active Pin \(session)",
                    status: "succeeded",
                    commit: "Active pin commit \(session)",
                    body: "active pin body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let stalePinnedEntry = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let retainedPinnedEntry = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: stalePinnedEntry.identifier,
            searchText: "active pin body",
            pinnedEntryIdentifiers: [
                stalePinnedEntry.identifier,
                retainedPinnedEntry.identifier,
                "missing-active-pin"
            ]
        )

        try FileManager.default.removeItem(at: stalePinnedEntry.url)
        let refreshedHistory = workspace.refreshRunRecapShareArtifactHistory()
        let resolved = context.resolvingSelection(in: refreshedHistory)

        XCTAssertEqual(resolved.searchText, "active pin body")
        XCTAssertEqual(resolved.selectedEntryIdentifier, refreshedHistory.entries.first?.identifier)
        XCTAssertEqual(resolved.pinnedEntryIdentifiers, [retainedPinnedEntry.identifier])
        XCTAssertTrue(
            refreshedHistory.entries.allSatisfy {
                $0.url.standardizedFileURL.path.hasPrefix(storageRootURL.standardizedFileURL.path)
                    && !$0.url.standardizedFileURL.path.hasPrefix(workspace.repoLocalCompassURL.standardizedFileURL.path)
            }
        )
    }

    func testPinPlannerTracksRetainedMissingFilteredAndQuickSelectPins() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-pin-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Pinned Recap \(session)",
                    status: session == 2 ? "retry warning" : "succeeded",
                    commit: "Pinned commit \(session)",
                    body: session == 4 ? "visible pin beacon" : "ordinary pin body"
                )
            )
        }
        _ = try workspace.writeSessionArtifact(
            session: 40,
            name: "recap-share-corrupt.md",
            contents: "corrupt pinned reference warning"
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let filteredPin = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let visiblePin = try XCTUnwrap(history.entries.first { $0.sessionNumber == 4 })
        let stalePin = "stale-pinned-recap-share-artifact"

        let pinPlan = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [
                filteredPin.identifier,
                visiblePin.identifier,
                filteredPin.identifier,
                stalePin
            ],
            selectedEntryIdentifier: visiblePin.identifier,
            searchQuery: " VISIBLE   PIN "
        )
        let noMatchPlan = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [
                filteredPin.identifier,
                visiblePin.identifier
            ],
            selectedEntryIdentifier: visiblePin.identifier,
            searchQuery: "missing pin query"
        )

        XCTAssertTrue(pinPlan.isAvailable)
        XCTAssertTrue(pinPlan.isSearchActive)
        XCTAssertEqual(pinPlan.searchQuerySnippet, "visible pin")
        XCTAssertEqual(pinPlan.pinnedEntryCount, 3)
        XCTAssertEqual(pinPlan.retainedPinnedEntryCount, 2)
        XCTAssertEqual(pinPlan.missingPinnedEntryCount, 1)
        XCTAssertEqual(pinPlan.filteredPinnedEntryCount, 1)
        XCTAssertEqual(pinPlan.quickSelectEntryCount, 1)
        XCTAssertEqual(pinPlan.retainedPinnedEntryIdentifiers, [filteredPin.identifier, visiblePin.identifier])
        XCTAssertEqual(pinPlan.missingPinnedEntryIdentifiers, [stalePin])
        XCTAssertEqual(pinPlan.filteredPinnedEntryIdentifiers, [filteredPin.identifier])
        XCTAssertEqual(pinPlan.quickSelectEntryIdentifiers, [visiblePin.identifier])
        XCTAssertTrue(pinPlan.selectedEntryIsPinned)
        XCTAssertEqual(pinPlan.selectedPinStateIdentifier, "pinned")
        XCTAssertEqual(pinPlan.references.map(\.identifier), [filteredPin.identifier, visiblePin.identifier])
        XCTAssertEqual(pinPlan.references.map(\.isQuickSelectable), [false, true])
        XCTAssertEqual(pinPlan.warningStateIdentifier, "warnings")
        XCTAssertEqual(pinPlan.warningCount, 1)
        XCTAssertLessThanOrEqual(
            pinPlan.identifier.count,
            CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            pinPlan.exportIdentifier.count,
            CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            pinPlan.exportTextLength,
            CinematicRunRecapShareArtifactPinnedReferencePlan.exportTextMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            pinPlan.copyLabel.count,
            CinematicRunRecapShareArtifactPinnedReferencePlan.copyLabelMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            pinPlan.copyHelp.count,
            CinematicRunRecapShareArtifactPinnedReferencePlan.copyHelpMaxCharacters
        )
        XCTAssertTrue(pinPlan.exportText.contains("- Missing pins: 1"))
        XCTAssertTrue(pinPlan.exportText.contains("- Filtered pins: 1"))
        XCTAssertTrue(pinPlan.exportText.contains("- Quick-select pins: 1"))
        XCTAssertTrue(pinPlan.exportText.contains("S4 4-recap-share-pin-4.md"))
        XCTAssertEqual(pinPlan.copyLabel, "Copy pinned export")

        XCTAssertTrue(noMatchPlan.isAvailable)
        XCTAssertEqual(noMatchPlan.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchPlan.quickSelectEntryCount, 0)
        XCTAssertEqual(noMatchPlan.filteredPinnedEntryCount, 2)
        XCTAssertTrue(noMatchPlan.exportText.contains("- No-match reason: no-matching-recap-share-artifacts"))
    }

    func testDiagnosticsExposePinnedReferenceSnapshotSummaryExportAndIdentifierCorrelation() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 10...12 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-diagnostics-pin-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Diagnostics Pin \(session)",
                    status: "succeeded",
                    commit: "Diagnostics pin commit \(session)",
                    body: session == 12 ? "diagnostics pin beacon" : "ordinary diagnostics pin body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 12 })
        let filtered = try XCTUnwrap(history.entries.first { $0.sessionNumber == 10 })
        let stalePin = "diagnostics-stale-pin"
        let pinPlan = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [selected.identifier, filtered.identifier, stalePin],
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "DIAGNOSTICS PIN BEACON"
        )

        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Succeeded",
            immediateTitle: "Expose recap artifact pins",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: history,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: selected.identifier,
            runRecapShareArtifactPreviewSearchQuery: "DIAGNOSTICS PIN BEACON",
            runRecapShareArtifactPinnedEntryIdentifiers: [
                selected.identifier,
                filtered.identifier,
                stalePin
            ]
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-pins" })

        XCTAssertTrue(report.runRecapShareArtifactPins.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactPins.identifier, pinPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifactPins.exportIdentifier, pinPlan.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactPins.searchQuerySnippet, "diagnostics pin beacon")
        XCTAssertEqual(report.runRecapShareArtifactPins.pinnedEntryCount, 3)
        XCTAssertEqual(report.runRecapShareArtifactPins.retainedPinnedEntryCount, 2)
        XCTAssertEqual(report.runRecapShareArtifactPins.missingPinnedEntryIdentifiers, [stalePin])
        XCTAssertEqual(report.runRecapShareArtifactPins.filteredPinnedEntryIdentifiers, [filtered.identifier])
        XCTAssertEqual(report.runRecapShareArtifactPins.quickSelectEntryIdentifiers, [selected.identifier])
        XCTAssertEqual(report.runRecapShareArtifactPins.selectedPinStateIdentifier, "pinned")
        XCTAssertEqual(report.runRecapShareArtifactPins.exportTextLength, pinPlan.exportTextLength)
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-pins:\(pinPlan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-pins-export:\(pinPlan.exportIdentifier)"))
        XCTAssertTrue(row.detail.contains("available"))
        XCTAssertTrue(row.detail.contains("search diagnostics pin beacon"))
        XCTAssertTrue(row.detail.contains("pins 3"))
        XCTAssertTrue(row.detail.contains("retained pins 2"))
        XCTAssertTrue(row.detail.contains("missing pins 1"))
        XCTAssertTrue(row.detail.contains("filtered pins 1"))
        XCTAssertTrue(row.detail.contains("quick 1"))
        XCTAssertTrue(row.detail.contains("selected pin pinned"))
        XCTAssertTrue(row.detail.contains("copy \(pinPlan.exportTextLength) chars"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact pins: available"))
        XCTAssertTrue(summary.exportText.contains("missing pins 1"))
        XCTAssertTrue(summary.exportText.contains("filtered pins 1"))
        XCTAssertTrue(summary.exportText.contains("selected pin pinned"))
    }

    func testPinPlannerPreservesSiblingPlannerOutputs() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-invariant-pin-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Invariant Pin \(session)",
                    status: session == 4 ? "failed verify" : "succeeded",
                    commit: "Invariant pin commit \(session)",
                    body: [2, 4].contains(session) ? "invariant pin cluster" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 4 })
        let pinned = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let query = " INVARIANT   PIN "
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
        let comparisonBefore = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query
        )

        _ = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [selected.identifier, pinned.identifier, "missing-invariant-pin"],
            selectedEntryIdentifier: selected.identifier,
            searchQuery: query
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
            CinematicRunRecapShareArtifactComparisonPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: selected.identifier,
                searchQuery: query
            ),
            comparisonBefore
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
        - Filename: recap-share-pin-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Pinned detail
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
        let repoURL = try makeTemporaryGitRepository(prefix: "CinematicRunRecapShareArtifactPinningRepo")
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
