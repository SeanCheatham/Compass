import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactPreviewTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testPreviewDefaultsToLatestAndPreservesValidSelection() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-preview-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Preview Recap \(session)",
                    status: "succeeded",
                    commit: "Preview commit \(session)",
                    body: "Share body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let defaultPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history
        )
        let selectedEntry = try XCTUnwrap(history.entries.dropFirst().first)
        let selectedPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selectedEntry.identifier
        )
        let repeatedSelectedPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selectedEntry.identifier
        )

        XCTAssertTrue(defaultPreview.isAvailable)
        XCTAssertEqual(defaultPreview.availabilityReason, "available")
        XCTAssertEqual(defaultPreview.selectedEntryIdentifier, history.entries.first?.identifier)
        XCTAssertNil(defaultPreview.previousEntryIdentifier)
        XCTAssertEqual(defaultPreview.nextEntryIdentifier, history.entries.dropFirst().first?.identifier)
        XCTAssertEqual(defaultPreview.selectedIndex, 0)
        XCTAssertEqual(defaultPreview.selectedOrdinal, 1)
        XCTAssertEqual(defaultPreview.entryCount, 3)

        XCTAssertEqual(selectedPreview, repeatedSelectedPreview)
        XCTAssertEqual(selectedPreview.selectedEntryIdentifier, selectedEntry.identifier)
        XCTAssertEqual(selectedPreview.previousEntryIdentifier, history.entries.first?.identifier)
        XCTAssertEqual(selectedPreview.nextEntryIdentifier, history.entries.last?.identifier)
        XCTAssertEqual(selectedPreview.selectedIndex, 1)
        XCTAssertEqual(selectedPreview.selectedOrdinal, 2)
        XCTAssertEqual(selectedPreview.entryCount, 3)
        XCTAssertEqual(selectedPreview.sessionNumber, 2)
        XCTAssertEqual(selectedPreview.filename, "2-recap-share-preview-2.md")
        XCTAssertEqual(selectedPreview.titleSnippet, "Preview Recap 2")
        XCTAssertEqual(selectedPreview.statusSnippet, "succeeded")
        XCTAssertEqual(selectedPreview.commitSnippet, "Preview commit 2")
        XCTAssertEqual(selectedPreview.pathSnippet, selectedEntry.pathDisplayText)
        XCTAssertTrue(selectedPreview.bodyPreviewText.contains("Share body 2"))
        XCTAssertEqual(selectedPreview.markdownLength, selectedEntry.markdownLength)
        XCTAssertEqual(selectedPreview.warningStateIdentifier, "clear")
        XCTAssertEqual(selectedPreview.warningCount, 0)
        XCTAssertFalse(selectedPreview.hasWarnings)
        XCTAssertLessThanOrEqual(
            selectedPreview.identifier.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.identifierMaxCharacters
        )
    }

    func testPreviewFallsBackWhenSelectedEntryDisappearsAndRespectsNavigationBounds() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-navigation-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Navigation Recap \(session)",
                    status: "succeeded",
                    commit: "Navigation commit \(session)",
                    body: "Navigation body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let oldestEntry = try XCTUnwrap(history.entries.last)
        let oldestPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: oldestEntry.identifier
        )

        XCTAssertEqual(oldestPreview.selectedEntryIdentifier, oldestEntry.identifier)
        XCTAssertEqual(oldestPreview.previousEntryIdentifier, history.entries.dropLast().last?.identifier)
        XCTAssertNil(oldestPreview.nextEntryIdentifier)
        XCTAssertTrue(oldestPreview.canNavigatePrevious)
        XCTAssertFalse(oldestPreview.canNavigateNext)

        try FileManager.default.removeItem(at: oldestEntry.url)
        let refreshedHistory = workspace.refreshRunRecapShareArtifactHistory()
        let fallbackPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: refreshedHistory,
            selectedEntryIdentifier: oldestEntry.identifier
        )

        XCTAssertEqual(fallbackPreview.selectedEntryIdentifier, refreshedHistory.entries.first?.identifier)
        XCTAssertNil(fallbackPreview.previousEntryIdentifier)
        XCTAssertEqual(fallbackPreview.nextEntryIdentifier, refreshedHistory.entries.dropFirst().first?.identifier)
        XCTAssertEqual(fallbackPreview.selectedIndex, 0)
        XCTAssertEqual(fallbackPreview.selectedOrdinal, 1)
        XCTAssertEqual(fallbackPreview.entryCount, 2)
    }

    func testPreviewBoundsSnippetContentAndUnavailableEmptyHistory() throws {
        let emptyWorkspace = try makeInitializedWorkspace()
        let emptyHistory = emptyWorkspace.refreshRunRecapShareArtifactHistory()
        let emptyPreview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: emptyHistory
        )

        XCTAssertFalse(emptyPreview.isAvailable)
        XCTAssertEqual(emptyPreview.availabilityReason, "no-recap-share-artifacts")
        XCTAssertNil(emptyPreview.selectedEntryIdentifier)
        XCTAssertNil(emptyPreview.selectedIndex)
        XCTAssertNil(emptyPreview.selectedOrdinal)
        XCTAssertEqual(emptyPreview.entryCount, 0)
        XCTAssertNil(emptyPreview.previousEntryIdentifier)
        XCTAssertNil(emptyPreview.nextEntryIdentifier)
        XCTAssertEqual(emptyPreview.markdownLength, 0)
        XCTAssertEqual(emptyPreview.warningStateIdentifier, "clear")
        XCTAssertLessThanOrEqual(
            emptyPreview.bodyPreviewText.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.bodyPreviewMaxCharacters
        )

        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 11,
            name: "recap-share-long.md",
            contents: artifactMarkdown(
                session: 11,
                title: String(repeating: "Long title ", count: 30),
                status: String(repeating: "Long status ", count: 30),
                commit: String(repeating: "Long commit ", count: 30),
                body: String(repeating: "Long preview body ", count: 40)
            )
        )

        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: workspace.refreshRunRecapShareArtifactHistory()
        )

        XCTAssertTrue(preview.isAvailable)
        XCTAssertLessThanOrEqual(
            preview.titleSnippet.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            preview.statusSnippet.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            preview.commitSnippet?.count ?? 0,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            preview.pathSnippet.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.pathSnippetMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            preview.bodyPreviewText.count,
            CinematicRunRecapShareArtifactPreviewBrowserPlan.bodyPreviewMaxCharacters
        )
    }

    func testPreviewUsesHistoryWarningsAndPreservesCorruptAndForeignFiles() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 1
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-preserve-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Preserve Recap \(session)",
                    status: "succeeded",
                    commit: "Preserve commit \(session)",
                    body: "Preserve body \(session)"
                )
            )
        }
        let corruptURL = try workspace.writeSessionArtifact(
            session: 90,
            name: "recap-share-corrupt.md",
            contents: "corrupt preview artifact"
        )
        let foreignURL = workspace.sessionsURL.appending(path: "90-not-a-recap-share.md")
        try "foreign preview artifact".write(to: foreignURL, atomically: true, encoding: .utf8)

        let history = workspace.refreshRunRecapShareArtifactHistory()
        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history
        )
        let cleanup = workspace.cleanupRunRecapShareArtifacts()

        XCTAssertEqual(history.totalCount, artifactCount)
        XCTAssertEqual(history.entries.count, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(history.warningCount, 1)
        XCTAssertEqual(history.cleanupCandidateCount, 1)
        XCTAssertEqual(preview.entryCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(preview.selectedEntryIdentifier, history.entries.first?.identifier)
        XCTAssertEqual(preview.warningStateIdentifier, "warnings")
        XCTAssertEqual(preview.warningCount, 1)
        XCTAssertTrue(preview.hasWarnings)
        XCTAssertEqual(cleanup.status, .deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignURL.path))
        XCTAssertEqual(cleanup.refreshedHistory.warningCount, 1)
    }

    func testPreviewPlanningPreservesRecapTimelineAndIdleInputs() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 9,
            name: "recap-share-invariant.md",
            contents: artifactMarkdown(
                session: 9,
                title: "Invariant Recap",
                status: "succeeded",
                commit: "Invariant commit",
                body: "Invariant body"
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
            selectedEntryIdentifier: "missing-entry"
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
        - Filename: recap-share-preview-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Preview detail
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
            .appending(path: "CinematicRunRecapShareArtifactPreviewTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            plan: "Implement recap artifact preview",
            verify: "swift test --filter CinematicRunRecapShareArtifactPreviewTests",
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
