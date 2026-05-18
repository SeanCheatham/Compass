import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactLibraryContextTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    @MainActor
    func testCurrentDiagnosticsUsePersistedContextForPreviewAndSubsetExports() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-context-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Context Recap \(session)",
                    status: "succeeded",
                    commit: "Context commit \(session)",
                    body: session == 2 ? "persisted beacon body" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "Persisted Beacon"
        )
        let project = CompassProject(
            repoURL: workspace.repoURL,
            cinematicRunRecapShareArtifactLibraryContext: context
        )
        project.cinematicRunRecapShareArtifactHistory = history

        let expectedPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let expectedSelectedExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            scope: .selected
        )
        let expectedFilteredExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            scope: .filtered
        )
        let expectedTour = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: context
        )

        let report = CinematicDiagnostics.currentReport(for: project)
        let summary = CinematicDiagnosticsSummary(report: report)
        let previewRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-preview" })
        let tourRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-tour" })

        XCTAssertEqual(project.cinematicRunRecapShareArtifactLibraryContext, context)
        XCTAssertEqual(report.runRecapShareArtifactPreview.identifier, expectedPreview.identifier)
        XCTAssertEqual(report.runRecapShareArtifactTour.identifier, expectedTour.identifier)
        XCTAssertEqual(report.runRecapShareArtifactTour.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(report.runRecapShareArtifactTour.searchQuerySnippet, "persisted beacon")
        XCTAssertEqual(report.runRecapShareArtifactTour.matchingEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.searchQuerySnippet, "persisted beacon")
        XCTAssertEqual(report.runRecapShareArtifactPreview.matchCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.exportIdentifier, expectedSelectedExport.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.exportedEntryIdentifiers, [selected.identifier])
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.exportIdentifier, expectedFilteredExport.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.exportedEntryIdentifiers, [selected.identifier])
        XCTAssertTrue(previewRow.detail.contains("search persisted beacon"))
        XCTAssertTrue(previewRow.detail.contains("selected export available"))
        XCTAssertTrue(previewRow.detail.contains("filtered export available"))
        XCTAssertTrue(tourRow.detail.contains("state recent"))
        XCTAssertTrue(tourRow.detail.contains("search persisted beacon"))
    }

    @MainActor
    func testCurrentDiagnosticsExposePersistedNoMatchContextWithoutMutatingProject() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-context-nomatch.md",
            contents: artifactMarkdown(
                session: 1,
                title: "No Match Recap",
                status: "succeeded",
                commit: "No match commit",
                body: "available body"
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first)
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "missing query"
        )
        let project = CompassProject(
            repoURL: workspace.repoURL,
            cinematicRunRecapShareArtifactLibraryContext: context
        )
        project.cinematicRunRecapShareArtifactHistory = history

        let report = CinematicDiagnostics.currentReport(for: project)
        let preview = report.runRecapShareArtifactPreview

        XCTAssertEqual(project.cinematicRunRecapShareArtifactLibraryContext, context)
        XCTAssertFalse(preview.isAvailable)
        XCTAssertTrue(preview.isSearchActive)
        XCTAssertEqual(preview.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertNil(preview.selectedEntryIdentifier)
        XCTAssertNil(preview.selectedExport.selectedEntryIdentifier)
        XCTAssertFalse(preview.selectedExport.isAvailable)
        XCTAssertFalse(preview.filteredExport.isAvailable)
        XCTAssertEqual(preview.selectedExport.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(preview.filteredExport.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(preview.selectedFallbackReasonIdentifier, "no-match")
        XCTAssertFalse(report.runRecapShareArtifactTour.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactTour.stateIdentifier, "no-match")
        XCTAssertEqual(
            report.runRecapShareArtifactTour.noMatchAvailabilityReason,
            "no-matching-recap-share-artifacts"
        )
    }

    func testArtifactTourPrefersPinsFallsBackAndReportsPinStatesWithoutMutatingContext() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-context-tour-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Tour Recap \(session)",
                    status: "succeeded",
                    commit: "Tour commit \(session)",
                    body: session == 1 ? "filtered pin body" : "visible archive body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let newest = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let filteredPin = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let pinnedContext = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: newest.identifier,
            searchText: "visible archive",
            pinnedEntryIdentifiers: [filteredPin.identifier, "missing-tour-pin"]
        )
        let heldContext = pinnedContext.holdingSavedTourEntryIdentifier(held.identifier)
        let filteredHoldContext = pinnedContext.holdingSavedTourEntryIdentifier(filteredPin.identifier)
        let missingHoldContext = pinnedContext.holdingSavedTourEntryIdentifier("missing-tour-hold")

        let filteredPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: pinnedContext
        )
        let heldPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: heldContext
        )
        let filteredHoldPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: filteredHoldContext
        )
        let missingHoldPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: missingHoldContext
        )
        let staleOnlyPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: CinematicRunRecapShareArtifactLibraryContext(
                selectedEntryIdentifier: newest.identifier,
                pinnedEntryIdentifiers: ["missing-tour-pin"]
            )
        )

        XCTAssertEqual(filteredPlan.stateIdentifier, "filtered-pin")
        XCTAssertEqual(filteredPlan.selectionSourceIdentifier, "recent")
        XCTAssertEqual(filteredPlan.selectedEntryIdentifier, newest.identifier)
        XCTAssertEqual(filteredPlan.filteredPinnedEntryIdentifiers, [filteredPin.identifier])
        XCTAssertEqual(filteredPlan.missingPinnedEntryIdentifiers, ["missing-tour-pin"])
        XCTAssertEqual(heldPlan.stateIdentifier, "held")
        XCTAssertEqual(heldPlan.savedTourHoldStateIdentifier, "held")
        XCTAssertEqual(heldPlan.selectionSourceIdentifier, "held")
        XCTAssertEqual(heldPlan.selectedEntryIdentifier, held.identifier)
        XCTAssertEqual(heldPlan.retainedSavedTourHoldEntryIdentifier, held.identifier)
        XCTAssertEqual(filteredHoldPlan.stateIdentifier, "filtered-hold")
        XCTAssertEqual(filteredHoldPlan.savedTourHoldStateIdentifier, "filtered-hold")
        XCTAssertEqual(filteredHoldPlan.filteredSavedTourHoldEntryIdentifier, filteredPin.identifier)
        XCTAssertEqual(filteredHoldPlan.selectedEntryIdentifier, newest.identifier)
        XCTAssertEqual(missingHoldPlan.stateIdentifier, "missing-hold")
        XCTAssertEqual(missingHoldPlan.savedTourHoldStateIdentifier, "missing-hold")
        XCTAssertEqual(missingHoldPlan.requestedSavedTourHoldEntryIdentifier, "missing-tour-hold")
        XCTAssertEqual(missingHoldPlan.selectedEntryIdentifier, newest.identifier)
        XCTAssertEqual(staleOnlyPlan.stateIdentifier, "missing-pin")
        XCTAssertEqual(staleOnlyPlan.selectedEntryIdentifier, newest.identifier)
        XCTAssertEqual(pinnedContext.pinnedEntryIdentifiers, [filteredPin.identifier, "missing-tour-pin"])
        XCTAssertEqual(pinnedContext.searchText, "visible archive")
        XCTAssertNil(pinnedContext.savedTourHoldEntryIdentifier)
        XCTAssertEqual(filteredHoldContext.savedTourHoldEntryIdentifier, filteredPin.identifier)
    }

    func testContextResolvesSelectionFallbackAfterRetainedEntriesChange() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-context-fallback-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Fallback Recap \(session)",
                    status: "succeeded",
                    commit: "Fallback commit \(session)",
                    body: "fallback body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let oldest = try XCTUnwrap(history.entries.last)
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: oldest.identifier,
            searchText: "fallback body",
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: "stale-held-tour"
        )

        try FileManager.default.removeItem(at: oldest.url)
        let refreshedHistory = workspace.refreshRunRecapShareArtifactHistory()
        let resolvedContext = context.resolvingSelection(in: refreshedHistory)
        let resolvedPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: refreshedHistory,
            selectedEntryIdentifier: resolvedContext.selectedEntryIdentifier,
            searchQuery: resolvedContext.searchText
        )

        XCTAssertEqual(resolvedContext.searchText, "fallback body")
        XCTAssertEqual(resolvedContext.comparisonTargetMode, .pinnedReference)
        XCTAssertEqual(resolvedContext.savedTourHoldEntryIdentifier, "stale-held-tour")
        XCTAssertEqual(resolvedContext.selectedEntryIdentifier, refreshedHistory.entries.first?.identifier)
        XCTAssertEqual(resolvedPreview.selectedFallbackReasonIdentifier, "none")
        XCTAssertEqual(resolvedPreview.selectedEntryIdentifier, refreshedHistory.entries.first?.identifier)
    }

    @MainActor
    func testRelaunchStyleProjectReconstructionRestoresArtifactLibraryContext() throws {
        let roots = try makeApplicationSupportRoots()
        let workspace = try makeInitializedWorkspace()
        for session in 1...2 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-context-relaunch-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Relaunch Recap \(session)",
                    status: "succeeded",
                    commit: "Relaunch commit \(session)",
                    body: session == 1 ? "restored search body" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "restored search",
            savedTourHoldEntryIdentifier: selected.identifier
        )
        let record = KnownProjectRecord(
            id: UUID(uuidString: "71717171-7171-7171-7171-717171717171")!,
            path: workspace.repoURL.path,
            addedAt: 10,
            lastOpenedAt: 20,
            cinematicRunRecapShareArtifactLibraryContext: context
        )

        try KnownProjectStore.save([record], applicationSupportRoots: roots)
        let loaded = try XCTUnwrap(KnownProjectStore.load(applicationSupportRoots: roots).first)
        let reconstructed = CompassProject(
            id: loaded.id,
            repoURL: URL(fileURLWithPath: loaded.path),
            activeStorage: loaded.activeStorage,
            addedAt: Date(timeIntervalSince1970: loaded.addedAt),
            lastOpenedAt: Date(timeIntervalSince1970: loaded.lastOpenedAt),
            cinematicInfluenceSettings: loaded.cinematicInfluenceSettings,
            nativeFeedbackMode: loaded.nativeFeedbackMode,
            cinematicRunRecapShareArtifactLibraryContext: loaded.cinematicRunRecapShareArtifactLibraryContext
        )
        reconstructed.cinematicRunRecapShareArtifactHistory = history

        let report = CinematicDiagnostics.currentReport(for: reconstructed)

        XCTAssertEqual(loaded.cinematicRunRecapShareArtifactLibraryContext, context)
        XCTAssertEqual(reconstructed.cinematicRunRecapShareArtifactLibraryContext, context)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.searchQuerySnippet, "restored search")
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.exportedEntryIdentifiers, [selected.identifier])
        XCTAssertEqual(report.runRecapShareArtifactTour.savedTourHoldStateIdentifier, "held")
        XCTAssertEqual(report.runRecapShareArtifactTour.selectionSourceIdentifier, "held")
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
        - Filename: recap-share-context-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Context detail
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
        let directory = try makeTemporaryDirectory(prefix: "CinematicRunRecapShareArtifactLibraryContextRepo")
        try FileManager.default.createDirectory(
            at: directory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let base = try makeTemporaryDirectory(prefix: "CinematicRunRecapShareArtifactLibraryContextSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
