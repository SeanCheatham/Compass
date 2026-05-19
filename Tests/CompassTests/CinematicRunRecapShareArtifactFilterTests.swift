import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactFilterTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSearchNormalizesWhitespaceAndCaseAndMatchesPreviewFields() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-title-probe.md",
            contents: artifactMarkdown(
                title: "Alpha Forge",
                status: "succeeded",
                commit: "Title commit",
                body: "Plain body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 2,
            name: "recap-share-status-probe.md",
            contents: artifactMarkdown(
                title: "Status Recap",
                status: "Blocked By Smoke",
                commit: "Status commit",
                body: "Status body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 3,
            name: "recap-share-commit-probe.md",
            contents: artifactMarkdown(
                title: "Commit Recap",
                status: "succeeded",
                commit: "Commit Beacon",
                body: "Commit body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 4,
            name: "recap-share-file-probe.md",
            contents: artifactMarkdown(
                title: "File Recap",
                status: "succeeded",
                commit: "File commit",
                body: "File body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 5,
            name: "recap-share-body-probe.md",
            contents: artifactMarkdown(
                title: "Body Recap",
                status: "succeeded",
                commit: "Body commit",
                body: "The body beacon glows in the share text."
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let defaultPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(historyPlan: history)
        let blankPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: " \n\t "
        )

        XCTAssertEqual(blankPreview, defaultPreview)
        XCTAssertFalse(blankPreview.isSearchActive)
        XCTAssertEqual(blankPreview.searchQuerySnippet, "none")
        XCTAssertEqual(blankPreview.searchQueryFingerprint, "none")
        XCTAssertEqual(blankPreview.matchCount, history.entries.count)
        XCTAssertEqual(blankPreview.unfilteredVisibleCount, history.entries.count)

        XCTAssertEqual(selectedSession(in: history, query: " ALPHA   FORGE "), 1)
        XCTAssertEqual(selectedSession(in: history, query: "blocked by smoke"), 2)
        XCTAssertEqual(selectedSession(in: history, query: "commit beacon"), 3)
        XCTAssertEqual(selectedSession(in: history, query: "sessions/4-recap-share-file-probe"), 4)
        XCTAssertEqual(selectedSession(in: history, query: "body beacon glows"), 5)

        let normalized = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: " ALPHA   FORGE "
        )
        XCTAssertEqual(normalized.searchQuerySnippet, "alpha forge")
        XCTAssertNotEqual(normalized.searchQueryFingerprint, "none")
        XCTAssertTrue(normalized.identifier.contains("matches:1"))
        XCTAssertTrue(normalized.identifier.contains("unfiltered:5"))
    }

    func testSearchNoMatchAndEmptyHistoryUseDistinctAvailabilityReasons() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-available.md",
            contents: artifactMarkdown(
                title: "Available Recap",
                status: "succeeded",
                commit: "Available commit",
                body: "Available body"
            )
        )
        let noMatch = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: workspace.refreshRunRecapShareArtifactHistory(),
            searchQuery: "missing query"
        )

        XCTAssertFalse(noMatch.isAvailable)
        XCTAssertTrue(noMatch.isSearchActive)
        XCTAssertEqual(noMatch.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatch.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatch.matchCount, 0)
        XCTAssertEqual(noMatch.unfilteredVisibleCount, 1)
        XCTAssertEqual(noMatch.entryCount, 0)
        XCTAssertNil(noMatch.selectedEntryIdentifier)
        XCTAssertNil(noMatch.previousEntryIdentifier)
        XCTAssertNil(noMatch.nextEntryIdentifier)
        XCTAssertTrue(noMatch.bodyPreviewText.contains("No saved recap share artifacts match"))

        let emptyWorkspace = try makeInitializedWorkspace()
        let empty = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: emptyWorkspace.refreshRunRecapShareArtifactHistory(),
            searchQuery: "missing query"
        )

        XCTAssertFalse(empty.isAvailable)
        XCTAssertTrue(empty.isSearchActive)
        XCTAssertEqual(empty.availabilityReason, "no-recap-share-artifacts")
        XCTAssertNil(empty.noMatchAvailabilityReason)
        XCTAssertEqual(empty.matchCount, 0)
        XCTAssertEqual(empty.unfilteredVisibleCount, 0)
    }

    func testWarningPulseFilterScopesPreviewExportsPinsAndTours() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-quiet-warning-pulse.md",
            contents: artifactMarkdown(
                title: "Quiet Pulse Recap",
                status: "succeeded",
                commit: "Quiet pulse commit",
                body: "Quiet body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 2,
            name: "recap-share-active-warning-pulse.md",
            contents: artifactMarkdown(
                title: "Active Pulse Recap",
                status: "succeeded",
                commit: "Active pulse commit",
                body: "Active warning pulse body",
                warningPulseSection: warningPulseSection(state: "active", suffix: "active")
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 3,
            name: "recap-share-snoozed-warning-pulse.md",
            contents: artifactMarkdown(
                title: "Snoozed Pulse Recap",
                status: "succeeded",
                commit: "Snoozed pulse commit",
                body: "Snoozed warning pulse body",
                warningPulseSection: warningPulseSection(state: "snoozed", suffix: "snoozed")
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let quietEntry = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let activeEntry = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let snoozedEntry = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })

        let anyPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            warningPulseFilter: .any
        )
        XCTAssertEqual(anyPreview.warningPulseFilterIdentifier, "any")
        XCTAssertEqual(anyPreview.warningPulseFilterMatchCount, 2)
        XCTAssertEqual(anyPreview.warningPulseAnyCount, 2)
        XCTAssertEqual(anyPreview.warningPulseActiveCount, 1)
        XCTAssertEqual(anyPreview.warningPulseSnoozedCount, 1)
        XCTAssertEqual(anyPreview.warningPulseUnknownCount, 0)
        XCTAssertEqual(anyPreview.matchCount, 2)
        XCTAssertEqual(anyPreview.unfilteredVisibleCount, 2)
        XCTAssertEqual(anyPreview.selectedEntryIdentifier, snoozedEntry.identifier)

        let activePreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: snoozedEntry.identifier,
            warningPulseFilter: .active
        )
        XCTAssertEqual(activePreview.warningPulseFilterIdentifier, "active")
        XCTAssertEqual(activePreview.matchCount, 1)
        XCTAssertEqual(activePreview.selectedEntryIdentifier, activeEntry.identifier)
        XCTAssertEqual(activePreview.selectedFallbackEntryIdentifier, activeEntry.identifier)
        XCTAssertEqual(activePreview.selectedFallbackReasonIdentifier, "filtered-selection")

        let activeSearchNoMatch = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: "snoozed",
            warningPulseFilter: .active
        )
        XCTAssertEqual(activeSearchNoMatch.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(activeSearchNoMatch.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(activeSearchNoMatch.warningPulseFilterMatchCount, 1)

        let filteredExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            scope: .filtered,
            warningPulseFilter: .active
        )
        XCTAssertEqual(filteredExport.warningPulseFilterIdentifier, "active")
        XCTAssertEqual(filteredExport.exportedEntryIdentifiers, [activeEntry.identifier])
        XCTAssertEqual(filteredExport.warningPulseAuditCount, 1)
        XCTAssertTrue(filteredExport.markdownContents.contains("- Warning pulse filter: active"))

        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            warningPulseFilter: .any
        )
        XCTAssertEqual(rollup.warningPulseFilterIdentifier, "any")
        XCTAssertEqual(rollup.matchingEntryCount, 2)
        XCTAssertEqual(rollup.warningPulseAuditCount, 2)
        XCTAssertTrue(rollup.exportText.contains("- Warning pulse filter: any"))

        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: snoozedEntry.identifier,
            warningPulseFilter: .any
        )
        XCTAssertEqual(comparison.warningPulseFilterIdentifier, "any")
        XCTAssertEqual(comparison.matchingEntryCount, 2)
        XCTAssertEqual(comparison.compareEntryIdentifier, activeEntry.identifier)
        XCTAssertTrue(comparison.exportText.contains("- Warning pulse filter: any"))

        let pins = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [quietEntry.identifier, activeEntry.identifier, snoozedEntry.identifier],
            warningPulseFilter: .active
        )
        XCTAssertEqual(pins.warningPulseFilterIdentifier, "active")
        XCTAssertEqual(pins.retainedPinnedEntryCount, 3)
        XCTAssertEqual(pins.quickSelectEntryIdentifiers, [activeEntry.identifier])
        XCTAssertEqual(Set(pins.filteredPinnedEntryIdentifiers), Set([quietEntry.identifier, snoozedEntry.identifier]))
        XCTAssertTrue(pins.exportText.contains("- Warning pulse filter: active"))

        let tour = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: CinematicRunRecapShareArtifactLibraryContext(
                selectedEntryIdentifier: quietEntry.identifier,
                pinnedEntryIdentifiers: [quietEntry.identifier, activeEntry.identifier, snoozedEntry.identifier],
                savedTourHoldEntryIdentifier: quietEntry.identifier,
                warningPulseFilter: .active
            )
        )
        XCTAssertEqual(tour.warningPulseFilterIdentifier, "active")
        XCTAssertEqual(tour.selectedEntryIdentifier, activeEntry.identifier)
        XCTAssertEqual(tour.selectionSourceIdentifier, "pinned")
        XCTAssertEqual(tour.filteredSavedTourHoldEntryIdentifier, quietEntry.identifier)
        XCTAssertEqual(Set(tour.filteredPinnedEntryIdentifiers), Set([quietEntry.identifier, snoozedEntry.identifier]))

        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Succeeded",
            immediateTitle: "Filter warning pulse artifacts",
            completedCount: 3,
            latestEvent: nil,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: history,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: quietEntry.identifier,
            runRecapShareArtifactWarningPulseFilter: .active,
            runRecapShareArtifactPinnedEntryIdentifiers: [
                quietEntry.identifier,
                activeEntry.identifier,
                snoozedEntry.identifier
            ],
            runRecapShareArtifactSavedTourHoldEntryIdentifier: quietEntry.identifier
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let previewRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-preview" })
        XCTAssertEqual(report.runRecapShareArtifactPreview.warningPulseFilterIdentifier, "active")
        XCTAssertEqual(report.runRecapShareArtifactPreview.warningPulseFilterMatchCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningPulseFilterIdentifier, "active")
        XCTAssertEqual(report.runRecapShareArtifactTour.warningPulseFilterIdentifier, "active")
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-preview-warning-filter:active"))
        XCTAssertTrue(previewRow.detail.contains("pulse filter active on m1"))
        XCTAssertTrue(summary.exportText.contains("pulse filter active on m1"))

        let quietOnlyWorkspace = try makeInitializedWorkspace()
        _ = try quietOnlyWorkspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-quiet-only.md",
            contents: artifactMarkdown(
                title: "Quiet Only",
                status: "succeeded",
                commit: "Quiet only commit",
                body: "No warning pulse"
            )
        )
        let quietOnlyPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: quietOnlyWorkspace.refreshRunRecapShareArtifactHistory(),
            warningPulseFilter: .active
        )
        XCTAssertEqual(quietOnlyPreview.availabilityReason, "no-matching-warning-pulse-artifacts")
        XCTAssertEqual(quietOnlyPreview.noMatchAvailabilityReason, "no-matching-warning-pulse-artifacts")
        XCTAssertTrue(quietOnlyPreview.bodyPreviewText.contains("active warning-pulse filter"))
    }

    func testSearchPreservesMatchingSelectionAndFallsBackToNewestMatchingArtifact() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            let body: String
            switch session {
            case 2:
                body = "needle two selected body"
            case 3, 4:
                body = "fallback cluster body"
            default:
                body = "ordinary body"
            }
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-fallback-\(session).md",
                contents: artifactMarkdown(
                    title: "Fallback Recap \(session)",
                    status: "succeeded",
                    commit: "Fallback commit \(session)",
                    body: body
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let newestFallback = try XCTUnwrap(history.entries.first { $0.sessionNumber == 4 })

        let preserved = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "needle two"
        )
        let fallback = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "fallback cluster"
        )
        let noMatch = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "missing cluster"
        )

        XCTAssertEqual(preserved.selectedEntryIdentifier, selected.identifier)
        XCTAssertNil(preserved.selectedFallbackEntryIdentifier)
        XCTAssertEqual(preserved.selectedFallbackReasonIdentifier, "none")
        XCTAssertEqual(preserved.matchCount, 1)

        XCTAssertEqual(fallback.selectedEntryIdentifier, newestFallback.identifier)
        XCTAssertEqual(fallback.selectedFallbackEntryIdentifier, newestFallback.identifier)
        XCTAssertEqual(fallback.selectedFallbackReasonIdentifier, "filtered-selection")
        XCTAssertEqual(fallback.selectedIndex, 0)
        XCTAssertEqual(fallback.selectedOrdinal, 1)
        XCTAssertEqual(fallback.matchCount, 2)

        XCTAssertFalse(noMatch.isAvailable)
        XCTAssertNil(noMatch.selectedEntryIdentifier)
        XCTAssertNil(noMatch.selectedFallbackEntryIdentifier)
        XCTAssertEqual(noMatch.selectedFallbackReasonIdentifier, "no-match")
    }

    func testFilteredNavigationStaysInsideMatchingResults() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...5 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-navigation-\(session).md",
                contents: artifactMarkdown(
                    title: "Navigation Recap \(session)",
                    status: "succeeded",
                    commit: "Navigation commit \(session)",
                    body: [1, 3, 5].contains(session) ? "nav-match body" : "plain body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let newest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 5 })
        let middle = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let oldest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })

        let newestPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: "nav-match"
        )
        let middlePreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: middle.identifier,
            searchQuery: "nav-match"
        )
        let oldestPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: oldest.identifier,
            searchQuery: "nav-match"
        )

        XCTAssertEqual(newestPreview.selectedEntryIdentifier, newest.identifier)
        XCTAssertNil(newestPreview.previousEntryIdentifier)
        XCTAssertEqual(newestPreview.nextEntryIdentifier, middle.identifier)
        XCTAssertEqual(newestPreview.entryCount, 3)
        XCTAssertEqual(newestPreview.matchCount, 3)
        XCTAssertEqual(newestPreview.unfilteredVisibleCount, 5)

        XCTAssertEqual(middlePreview.previousEntryIdentifier, newest.identifier)
        XCTAssertEqual(middlePreview.nextEntryIdentifier, oldest.identifier)
        XCTAssertEqual(middlePreview.selectedIndex, 1)
        XCTAssertEqual(middlePreview.selectedOrdinal, 2)
        XCTAssertTrue(middlePreview.canNavigatePrevious)
        XCTAssertTrue(middlePreview.canNavigateNext)

        XCTAssertEqual(oldestPreview.previousEntryIdentifier, middle.identifier)
        XCTAssertNil(oldestPreview.nextEntryIdentifier)
        XCTAssertTrue(oldestPreview.canNavigatePrevious)
        XCTAssertFalse(oldestPreview.canNavigateNext)
    }

    func testSearchBoundsQueryAndBodySnippets() throws {
        let workspace = try makeInitializedWorkspace()
        let repeatedNeedle = String(repeating: "Bounded Needle ", count: 20)
        _ = try workspace.writeSessionArtifact(
            session: 8,
            name: "recap-share-bounds.md",
            contents: artifactMarkdown(
                title: "Bounds Recap",
                status: "succeeded",
                commit: "Bounds commit",
                body: repeatedNeedle + String(repeating: "long preview body ", count: 80)
            )
        )

        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: workspace.refreshRunRecapShareArtifactHistory(),
            searchQuery: repeatedNeedle
        )

        XCTAssertTrue(preview.isAvailable)
        XCTAssertLessThanOrEqual(
            preview.searchQuerySnippet.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            preview.bodyPreviewText.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.bodyPreviewMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            preview.identifier.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.identifierMaxCharacters
        )
        XCTAssertNotEqual(preview.searchQueryFingerprint, "none")
    }

    func testSearchMetadataFlowsIntoDiagnosticsRowsAndExportText() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 6,
            name: "recap-share-diagnostics-a.md",
            contents: artifactMarkdown(
                title: "Diagnostics Match",
                status: "succeeded",
                commit: "Diagnostics commit",
                body: "diagnostics beacon body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 5,
            name: "recap-share-diagnostics-b.md",
            contents: artifactMarkdown(
                title: "Diagnostics Other",
                status: "succeeded",
                commit: "Other commit",
                body: "ordinary body"
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: "DIAGNOSTICS  BEACON"
        )
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Succeeded",
            immediateTitle: "Expose filtered recap artifact preview",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: history,
            runRecapShareArtifactPreviewSearchQuery: "DIAGNOSTICS  BEACON"
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-preview" })

        XCTAssertEqual(report.runRecapShareArtifactPreview.identifier, preview.identifier)
        XCTAssertTrue(report.runRecapShareArtifactPreview.isSearchActive)
        XCTAssertEqual(report.runRecapShareArtifactPreview.searchQuerySnippet, "diagnostics beacon")
        XCTAssertEqual(report.runRecapShareArtifactPreview.matchCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.unfilteredVisibleCount, 2)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedFallbackReasonIdentifier, "none")
        XCTAssertTrue(report.runRecapShareArtifactPreview.selectedExport.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.scopeIdentifier, "selected")
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.exportEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.searchQuerySnippet, "diagnostics beacon")
        XCTAssertTrue(report.runRecapShareArtifactPreview.filteredExport.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.scopeIdentifier, "filtered")
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.exportEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.filteredCount, 1)
        XCTAssertTrue(row.detail.contains("search diagnostics beacon"))
        XCTAssertTrue(row.detail.contains("matches 1/2"))
        XCTAssertTrue(row.detail.contains("fallback reason none"))
        XCTAssertTrue(row.detail.contains("selected export available"))
        XCTAssertTrue(row.detail.contains("filtered export available"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact preview: available"))
        XCTAssertTrue(summary.exportText.contains("search diagnostics beacon"))
        XCTAssertTrue(summary.exportText.contains("matches 1/2"))
        XCTAssertTrue(summary.exportText.contains("filtered export available"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact library: available"))
        XCTAssertTrue(summary.exportText.contains("retention \(history.retentionLimit)"))
        XCTAssertTrue(summary.exportText.contains("cleanup candidates 0"))
        XCTAssertTrue(summary.exportText.contains("warnings 0"))
    }

    func testSearchPreservesCorruptAndForeignFilesThroughHistoryModel() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 1
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-preserve-\(session).md",
                contents: artifactMarkdown(
                    title: "Preserve Recap \(session)",
                    status: "succeeded",
                    commit: "Preserve commit \(session)",
                    body: "preserve search body"
                )
            )
        }
        let corruptURL = try workspace.writeSessionArtifact(
            session: 90,
            name: "recap-share-corrupt.md",
            contents: "corrupt filtered artifact"
        )
        let foreignURL = workspace.sessionsURL.appending(path: "90-not-a-recap-share.md")
        try "foreign filtered artifact".write(to: foreignURL, atomically: true, encoding: .utf8)

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: "preserve search"
        )
        let cleanup = workspace.cleanupRunRecapShareArtifacts()

        XCTAssertEqual(history.totalCount, artifactCount)
        XCTAssertEqual(history.warningCount, 1)
        XCTAssertEqual(history.cleanupCandidateCount, 1)
        XCTAssertEqual(preview.matchCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(preview.unfilteredVisibleCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(cleanup.status, .deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignURL.path))
        XCTAssertEqual(cleanup.refreshedHistory.warningCount, 1)
    }

    func testSearchPlanningPreservesRecapTimelineAndIdleInputs() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 9,
            name: "recap-share-invariant.md",
            contents: artifactMarkdown(
                title: "Invariant Recap",
                status: "succeeded",
                commit: "Invariant commit",
                body: "invariant search body"
            )
        )
        let session = makeSession(9, endedAt: 9_500)
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = CinematicRunRecapPlan.empty(reason: "active-run")
        let recapBefore = recapPlan
        let shareBefore = CinematicRunRecapSharePlanner.plan(recapPlan: recapPlan)
        let timelineBefore = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: CinematicSessionTimelinePlan(sessions: [session]).beats.first?.stableID
        )
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelineBefore
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let idleInput = CinematicIdleStoryCyclePlan.SessionInput(
            elapsedTime: 42,
            sessionOrdinal: session.session
        )
        let idleBefore = CinematicIdleStoryCyclePlanner.plan(
            session: idleInput,
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: CinematicInfluenceSettings(),
            commitConstellationPlan: commitPlan,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: recapPlan,
            runRecapSceneFocusPlan: focusPlan,
            runRecapEndCardPlan: endCardPlan
        )

        _ = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: workspace.refreshRunRecapShareArtifactHistory(),
            selectedEntryIdentifier: "missing-entry",
            searchQuery: "invariant search"
        )

        XCTAssertEqual(recapPlan, recapBefore)
        XCTAssertEqual(CinematicRunRecapSharePlanner.plan(recapPlan: recapPlan), shareBefore)
        XCTAssertEqual(
            CinematicSessionTimelinePlan(
                sessions: [session],
                selectedBeatID: timelineBefore.selectedBeatID
            ),
            timelineBefore
        )
        XCTAssertEqual(
            CinematicIdleStoryCyclePlanner.plan(
                session: idleInput,
                isLiveFollowActive: false,
                hasExplicitUserFocus: false,
                influenceSettings: CinematicInfluenceSettings(),
                commitConstellationPlan: commitPlan,
                timelineSceneFocusPlan: .none,
                nativeFeedbackCue: nil,
                nativeFeedbackPlaqueDescriptor: nil,
                runRecapPlan: recapPlan,
                runRecapSceneFocusPlan: focusPlan,
                runRecapEndCardPlan: endCardPlan
            ),
            idleBefore
        )
    }

    private func selectedSession(
        in history: CinematicRunRecapShareArtifactHistoryPlan,
        query: String
    ) -> Int? {
        CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: query
        ).sessionNumber
    }

    private func artifactMarkdown(
        title: String,
        status: String,
        commit: String,
        body: String,
        warningPulseSection: String = ""
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
        \(body)
        ```

        \(warningPulseSection)
        """
    }

    private func warningPulseSection(state: String, suffix: String) -> String {
        """
        ## Diagnostics Warning Pulse

        - Warning pulse audit: filter-warning-pulse-\(suffix)
        - State: \(state)
        - Bundle: filter-warning-bundle-\(suffix)
        - Quieting status: \(state)
        - Sequence: 1
        - Capture count: 2
        - Target count: 1
        - Warning count: 2
        - Warning identifiers: visual-smoke.filter-warning-pulse-\(suffix)-a, visual-smoke.filter-warning-pulse-\(suffix)-b
        - Omitted warning identifiers: 0
        - Target anchors: visual-smoke-check-filter-warning-pulse-\(suffix)
        - Omitted target anchors: 0
        - Related rows: diagnostics-row-run-recap-share-artifact-tour
        - Omitted related rows: 0
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
            .appending(path: "CinematicRunRecapShareArtifactFilterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus = .succeeded,
        commits: [SessionCommit] = [],
        endedAt: Double? = nil
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Implement recap artifact filters",
            verify: "swift test --filter CinematicRunRecapShareArtifactFilterTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }
}
