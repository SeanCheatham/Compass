import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactHistoryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testHistoryScanOrdersNewestArtifactsAndExportsCombinedMarkdown() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 2,
            name: "recap-share-old.md",
            contents: artifactMarkdown(title: "Old Recap", status: "succeeded", commit: "Old commit")
        )
        _ = try workspace.writeSessionArtifact(
            session: 4,
            name: "recap-share-alpha.md",
            contents: artifactMarkdown(title: "Alpha Recap", status: "failed", commit: "Alpha commit")
        )
        _ = try workspace.writeSessionArtifact(
            session: 4,
            name: "recap-share-zeta.md",
            contents: artifactMarkdown(title: "Zeta Recap", status: "succeeded", commit: "Zeta commit")
        )

        let plan = workspace.refreshRunRecapShareArtifactHistory()

        XCTAssertTrue(plan.isAvailable)
        XCTAssertEqual(plan.availabilityReason, "available")
        XCTAssertEqual(plan.totalCount, 3)
        XCTAssertEqual(plan.hiddenCount, 0)
        XCTAssertEqual(plan.warningCount, 0)
        XCTAssertEqual(
            plan.entries.map(\.filename),
            [
                "4-recap-share-zeta.md",
                "4-recap-share-alpha.md",
                "2-recap-share-old.md"
            ]
        )
        let latest = try XCTUnwrap(plan.latestEntry)
        XCTAssertEqual(latest.sessionNumber, 4)
        XCTAssertEqual(latest.filename, "4-recap-share-zeta.md")
        XCTAssertEqual(latest.pathDisplayText, "sessions/4-recap-share-zeta.md")
        XCTAssertEqual(latest.titleSnippet, "Zeta Recap")
        XCTAssertEqual(latest.statusSnippet, "succeeded")
        XCTAssertEqual(latest.commitSnippet, "Zeta commit")
        XCTAssertTrue(plan.combinedMarkdownExport.contains("# Compass Recap Share Artifact Library"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("## Session 4 - 4-recap-share-zeta.md"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("Alpha Recap"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("Old Recap"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("- Latest filename: 4-recap-share-zeta.md"))
        XCTAssertLessThanOrEqual(
            plan.identifier.count,
            CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            plan.exportIdentifier.count,
            CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            plan.combinedMarkdownLength,
            CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
    }

    func testHistoryCapsEntriesFilenamesContentAndHiddenCounts() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.entryLimit + 2
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-\(String(repeating: "long-name-", count: 18))\(session).md",
                contents: artifactMarkdown(
                    title: String(repeating: "Very long title ", count: 20),
                    status: String(repeating: "Very long status ", count: 20),
                    commit: String(repeating: "Very long commit ", count: 20),
                    body: String(repeating: "large artifact body\n", count: 400)
                )
            )
        }

        let plan = workspace.refreshRunRecapShareArtifactHistory()

        XCTAssertEqual(plan.totalCount, artifactCount)
        XCTAssertEqual(plan.entries.count, CinematicRunRecapShareArtifactHistoryPlan.entryLimit)
        XCTAssertEqual(plan.hiddenCount, 2)
        XCTAssertTrue(
            plan.entries.allSatisfy {
                $0.filename.count <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
                    && $0.pathDisplayText.count <= CinematicRunRecapShareArtifactHistoryPlan.pathDisplayMaxCharacters
                    && $0.titleSnippet.count <= CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
                    && $0.statusSnippet.count <= CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
                    && ($0.commitSnippet?.count ?? 0) <= CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
                    && $0.markdownContents.count <= CinematicRunRecapShareArtifactHistoryPlan.entryMarkdownMaxCharacters
            }
        )
        XCTAssertLessThanOrEqual(
            plan.combinedMarkdownLength,
            CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
        XCTAssertTrue(plan.combinedMarkdownExport.contains("- Hidden artifacts: 2"))
    }

    func testHistoryToleratesMissingAndCorruptArtifactFilesWithBoundedWarnings() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 5,
            name: "recap-share-valid.md",
            contents: artifactMarkdown(title: "Valid Recap", status: "succeeded", commit: "Valid commit")
        )
        _ = try workspace.writeSessionArtifact(
            session: 6,
            name: "recap-share-corrupt.md",
            contents: "not a recap share artifact"
        )
        try FileManager.default.createSymbolicLink(
            atPath: workspace.sessionsURL.appending(path: "7-recap-share-missing.md").path,
            withDestinationPath: workspace.sessionsURL.appending(path: "missing-target.md").path
        )

        let plan = workspace.refreshRunRecapShareArtifactHistory()

        XCTAssertTrue(plan.isAvailable)
        XCTAssertEqual(plan.totalCount, 1)
        XCTAssertEqual(plan.latestEntry?.filename, "5-recap-share-valid.md")
        XCTAssertEqual(plan.warningCount, 2)
        XCTAssertEqual(plan.warnings.count, 2)
        XCTAssertTrue(plan.hasWarnings)
        XCTAssertTrue(plan.warnings.contains { $0.message.contains("expected Markdown header") })
        XCTAssertTrue(plan.warnings.contains { $0.message.contains("Could not read") })
        XCTAssertTrue(
            plan.warnings.allSatisfy {
                $0.identifier.count <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                    && $0.fileDisplayText.count <= CinematicRunRecapShareArtifactHistoryPlan.pathDisplayMaxCharacters
                    && $0.message.count <= CinematicRunRecapShareArtifactHistoryPlan.warningMaxCharacters
            }
        )
        XCTAssertTrue(plan.combinedMarkdownExport.contains("## Warnings"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("Valid Recap"))
    }

    func testHistoryUsesActiveStorageSessionsDirectoryWithoutRepoLocalSideEffects() throws {
        let repoURL = try makeTemporaryGitRepository()
        let storageRootURL = try makeTemporaryDirectory(prefix: "RecapShareHistorySupport")
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: "project-storage", directoryHint: .isDirectory)
        let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
        try workspace.initialize()
        _ = try workspace.writeSessionArtifact(
            session: 8,
            name: "recap-share-support.md",
            contents: artifactMarkdown(title: "Support Recap", status: "succeeded", commit: "Support commit")
        )

        let plan = workspace.refreshRunRecapShareArtifactHistory()
        let latest = try XCTUnwrap(plan.latestEntry)

        XCTAssertEqual(plan.totalCount, 1)
        XCTAssertTrue(latest.url.standardizedFileURL.path.hasPrefix(storageRootURL.standardizedFileURL.path))
        XCTAssertFalse(
            latest.url.standardizedFileURL.path.hasPrefix(workspace.repoLocalCompassURL.standardizedFileURL.path)
        )
        XCTAssertTrue(plan.storageRootDisplayText.contains("project-storage"))
        XCTAssertTrue(plan.sessionsDisplayText.contains("sessions"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    }

    func testHistoryUnavailableWhenSessionsDirectoryHasNoArtifacts() throws {
        let workspace = try makeInitializedWorkspace()

        let plan = workspace.refreshRunRecapShareArtifactHistory()

        XCTAssertFalse(plan.isAvailable)
        XCTAssertEqual(plan.availabilityReason, "no-recap-share-artifacts")
        XCTAssertEqual(plan.totalCount, 0)
        XCTAssertNil(plan.latestEntry)
        XCTAssertTrue(plan.combinedMarkdownExport.contains("No recap share artifacts"))
    }

    func testHistoryRefreshDoesNotEnableUnavailableCurrentRecapOrMutateTimelineAndIdleInputs() throws {
        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 9,
            name: "recap-share-saved.md",
            contents: artifactMarkdown(title: "Saved Recap", status: "succeeded", commit: "Saved commit")
        )
        let session = makeSession(9, endedAt: 9_500)
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = CinematicRunRecapPlan.empty(reason: "active-run")
        let recapBefore = recapPlan
        let sharePlan = CinematicRunRecapSharePlanner.plan(recapPlan: recapPlan)
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

        XCTAssertTrue(history.isAvailable)
        XCTAssertFalse(sharePlan.isAvailable)
        XCTAssertEqual(sharePlan.availabilityReason, "active-run")
        XCTAssertEqual(recapPlan, recapBefore)
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
        title: String,
        status: String,
        commit: String,
        body: String = "Compass recap body."
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

    private func makeTemporaryDirectory(prefix: String = "CinematicRunRecapShareArtifactHistoryTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
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
            plan: "Implement recap artifact history",
            verify: "swift test --filter CinematicRunRecapShareArtifactHistoryTests",
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
