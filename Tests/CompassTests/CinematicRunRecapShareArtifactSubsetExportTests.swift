import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactSubsetExportTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSelectedScopeExportsOnlyCurrentSelectedRetainedArtifact() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-selected.md",
            contents: artifactMarkdown(
                session: 1,
                title: "Selected Recap",
                status: "succeeded",
                commit: "Selected commit",
                body: "selected body"
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 2,
            name: "recap-share-newest.md",
            contents: artifactMarkdown(
                session: 2,
                title: "Newest Recap",
                status: "succeeded",
                commit: "Newest commit",
                body: "newest body"
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })

        let export = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            scope: .selected
        )

        XCTAssertTrue(export.isAvailable)
        XCTAssertEqual(export.scope, .selected)
        XCTAssertEqual(export.availabilityReason, "available")
        XCTAssertEqual(export.exportEntryCount, 1)
        XCTAssertEqual(export.selectedCount, 1)
        XCTAssertEqual(export.filteredCount, 2)
        XCTAssertEqual(export.unfilteredVisibleCount, 2)
        XCTAssertEqual(export.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(export.exportedEntryIdentifiers, [selected.identifier])
        XCTAssertTrue(export.markdownContents.contains("- Scope: selected"))
        XCTAssertTrue(export.markdownContents.contains("- Selected artifacts: 1"))
        XCTAssertTrue(export.markdownContents.contains("Selected Recap"))
        XCTAssertFalse(export.markdownContents.contains("Newest Recap"))
        XCTAssertEqual(export.copyLabel, "Copy selected export")
        XCTAssertTrue(export.copyHelp.contains("1 retained recap share artifact"))
        XCTAssertLessThanOrEqual(export.identifier.count, CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(export.exportIdentifier.count, CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(export.markdownLength, CinematicRunRecapShareArtifactSubsetExportPlan.markdownMaxCharacters)
    }

    func testFilteredScopeExportsMatchingRetainedEntries() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-filtered-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Filtered Recap \(session)",
                    status: "succeeded",
                    commit: "Filtered commit \(session)",
                    body: [2, 4].contains(session) ? "filtered beacon body" : "ordinary body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let expectedEntries = history.entries.filter { [2, 4].contains($0.sessionNumber) }

        let export = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: " FILTERED   BEACON ",
            scope: .filtered
        )

        XCTAssertTrue(export.isAvailable)
        XCTAssertEqual(export.scope, .filtered)
        XCTAssertEqual(export.exportEntryCount, 2)
        XCTAssertEqual(export.selectedCount, 1)
        XCTAssertEqual(export.filteredCount, 2)
        XCTAssertEqual(export.searchQuerySnippet, "filtered beacon")
        XCTAssertNotEqual(export.searchQueryFingerprint, "none")
        XCTAssertEqual(export.exportedEntryIdentifiers, expectedEntries.map(\.identifier))
        XCTAssertTrue(export.markdownContents.contains("## Session 4 - 4-recap-share-filtered-4.md"))
        XCTAssertTrue(export.markdownContents.contains("## Session 2 - 2-recap-share-filtered-2.md"))
        XCTAssertFalse(export.markdownContents.contains("## Session 3 - 3-recap-share-filtered-3.md"))
        XCTAssertFalse(export.markdownContents.contains("## Session 1 - 1-recap-share-filtered-1.md"))
        XCTAssertTrue(export.copyHelp.contains("2 retained recap share artifacts"))
        XCTAssertTrue(export.copyHelp.contains("2/4 retained"))
    }

    func testNoMatchAndEmptyHistoryAvailabilityReasons() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 1,
            name: "recap-share-available.md",
            contents: artifactMarkdown(
                session: 1,
                title: "Available Recap",
                status: "succeeded",
                commit: "Available commit",
                body: "available body"
            )
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let noMatchFiltered = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: "missing query",
            scope: .filtered
        )
        let noMatchSelected = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: "missing query",
            scope: .selected
        )

        XCTAssertFalse(noMatchFiltered.isAvailable)
        XCTAssertFalse(noMatchSelected.isAvailable)
        XCTAssertEqual(noMatchFiltered.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchSelected.availabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchFiltered.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchSelected.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(noMatchFiltered.exportEntryCount, 0)
        XCTAssertEqual(noMatchSelected.exportEntryCount, 0)
        XCTAssertEqual(noMatchFiltered.filteredCount, 0)
        XCTAssertEqual(noMatchSelected.selectedCount, 0)
        XCTAssertTrue(noMatchFiltered.markdownContents.contains("unavailable (no-matching-recap-share-artifacts)"))

        let emptyWorkspace = try makeInitializedWorkspace()
        let emptyHistory = emptyWorkspace.refreshRunRecapShareArtifactHistory()
        let emptyFiltered = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: emptyHistory,
            searchQuery: "missing query",
            scope: .filtered
        )
        let emptySelected = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: emptyHistory,
            searchQuery: "missing query",
            scope: .selected
        )

        XCTAssertFalse(emptyFiltered.isAvailable)
        XCTAssertFalse(emptySelected.isAvailable)
        XCTAssertEqual(emptyFiltered.availabilityReason, "no-recap-share-artifacts")
        XCTAssertEqual(emptySelected.availabilityReason, "no-recap-share-artifacts")
        XCTAssertNil(emptyFiltered.noMatchAvailabilityReason)
        XCTAssertNil(emptySelected.noMatchAvailabilityReason)
        XCTAssertEqual(emptyFiltered.retainedEntryCount, 0)
        XCTAssertEqual(emptySelected.retainedEntryCount, 0)
    }

    func testSubsetExportBoundsMarkdownQueryWarningsAndCopyHelpers() throws {
        let workspace = try makeInitializedWorkspace()
        let repeatedNeedle = String(repeating: "Bounded Needle ", count: 24)
        _ = try workspace.writeSessionArtifact(
            session: 8,
            name: "recap-share-bounded.md",
            contents: artifactMarkdown(
                session: 8,
                title: String(repeating: "Bounded title ", count: 20),
                status: String(repeating: "Bounded status ", count: 20),
                commit: String(repeating: "Bounded commit ", count: 20),
                body: repeatedNeedle + String(repeating: "long subset export body\n", count: 500)
            )
        )
        _ = try workspace.writeSessionArtifact(
            session: 9,
            name: "recap-share-corrupt.md",
            contents: "corrupt subset export artifact"
        )

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let export = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: repeatedNeedle,
            scope: .filtered
        )

        XCTAssertTrue(export.isAvailable)
        XCTAssertTrue(export.hasWarnings)
        XCTAssertEqual(export.warningStateIdentifier, "warnings")
        XCTAssertEqual(export.warningCount, 1)
        XCTAssertEqual(export.warningIdentifiers.count, 1)
        XCTAssertLessThanOrEqual(export.identifier.count, CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(export.exportIdentifier.count, CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(export.markdownLength, CinematicRunRecapShareArtifactSubsetExportPlan.markdownMaxCharacters)
        XCTAssertLessThanOrEqual(export.searchQuerySnippet.count, CinematicRunRecapShareArtifactSubsetExportPlan.searchQuerySnippetMaxCharacters)
        XCTAssertLessThanOrEqual(export.copyLabel.count, CinematicRunRecapShareArtifactSubsetExportPlan.labelMaxCharacters)
        XCTAssertLessThanOrEqual(export.copyHelp.count, CinematicRunRecapShareArtifactSubsetExportPlan.helpMaxCharacters)
        XCTAssertTrue(export.markdownContents.contains("## Warnings"))
        XCTAssertTrue(export.markdownContents.contains(try XCTUnwrap(export.warningIdentifiers.first)))
        XCTAssertTrue(export.copyHelp.contains("Copy 1 retained recap share artifact"))
    }

    func testFilteredExportUsesActiveStorageRetainedEntriesOnly() throws {
        let repoURL = try makeTemporaryGitRepository()
        let storageRootURL = try makeTemporaryDirectory(prefix: "SubsetExportSupport")
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: "project-storage", directoryHint: .isDirectory)
        let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
        try workspace.initialize()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 2
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-active-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Active Storage Recap \(session)",
                    status: "succeeded",
                    commit: "Active commit \(session)",
                    body: "active storage retained beacon"
                )
            )
        }

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let fullLibraryExport = history.combinedMarkdownExport
        let filtered = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: "active storage retained beacon",
            scope: .filtered
        )
        let blankFiltered = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            searchQuery: " \n\t ",
            scope: .filtered
        )
        let defaultPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(historyPlan: history)
        let blankPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            searchQuery: " \n\t "
        )

        XCTAssertEqual(defaultPreview, blankPreview)
        XCTAssertEqual(history.combinedMarkdownExport, fullLibraryExport)
        XCTAssertEqual(history.totalCount, artifactCount)
        XCTAssertEqual(history.entries.count, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(history.cleanupCandidateCount, 2)
        XCTAssertEqual(filtered.exportEntryCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(filtered.filteredCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(filtered.exportedEntryIdentifiers, history.entries.map(\.identifier))
        XCTAssertEqual(blankFiltered.exportEntryCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertTrue(filtered.markdownContents.contains("- Hidden artifacts: 2"))
        XCTAssertTrue(filtered.markdownContents.contains("## Session \(artifactCount) - \(artifactCount)-recap-share-active-\(artifactCount).md"))
        XCTAssertFalse(filtered.markdownContents.contains("## Session 1 - 1-recap-share-active-1.md"))
        XCTAssertFalse(filtered.markdownContents.contains("## Session 2 - 2-recap-share-active-2.md"))
        XCTAssertTrue(
            history.entries.allSatisfy {
                $0.url.standardizedFileURL.path.hasPrefix(storageRootURL.standardizedFileURL.path)
                    && !$0.url.standardizedFileURL.path.hasPrefix(workspace.repoLocalCompassURL.standardizedFileURL.path)
            }
        )
    }

    func testSubsetExportPlanningPreservesRecapTimelineAndIdleInputs() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 9,
            name: "recap-share-invariant.md",
            contents: artifactMarkdown(
                session: 9,
                title: "Invariant Recap",
                status: "succeeded",
                commit: "Invariant commit",
                body: "invariant subset body"
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
        let history = workspace.refreshRunRecapShareArtifactHistory()

        _ = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: "missing-entry",
            searchQuery: "invariant subset",
            scope: .selected
        )
        _ = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: "missing-entry",
            searchQuery: "invariant subset",
            scope: .filtered
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
        - Detail: Subset detail
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

    private func makeTemporaryDirectory(prefix: String = "CinematicRunRecapShareArtifactSubsetExportTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            plan: "Implement recap artifact subset exports",
            verify: "swift test --filter CinematicRunRecapShareArtifactSubsetExportTests",
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
