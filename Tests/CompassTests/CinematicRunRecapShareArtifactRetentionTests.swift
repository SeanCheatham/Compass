import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactRetentionTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testRetentionModelRetainsNewestValidArtifactsAndOrdersCleanupCandidates() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 3
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-retention-\(session).md",
                contents: artifactMarkdown(session: session)
            )
        }

        let plan = workspace.refreshRunRecapShareArtifactHistory()

        XCTAssertEqual(plan.retentionLimit, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(plan.totalCount, artifactCount)
        XCTAssertEqual(plan.entries.count, plan.retentionLimit)
        XCTAssertEqual(plan.entries.first?.sessionNumber, artifactCount)
        XCTAssertEqual(plan.entries.last?.sessionNumber, 4)
        XCTAssertEqual(plan.cleanupCandidateCount, 3)
        XCTAssertEqual(plan.hiddenCleanupCandidateCount, 0)
        XCTAssertEqual(plan.cleanupCandidateIdentifiers.count, 3)
        XCTAssertTrue(plan.cleanupCandidateIdentifiers[0].contains("session:3"))
        XCTAssertTrue(plan.cleanupCandidateIdentifiers[1].contains("session:2"))
        XCTAssertTrue(plan.cleanupCandidateIdentifiers[2].contains("session:1"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("- Retention limit: \(plan.retentionLimit)"))
        XCTAssertTrue(plan.combinedMarkdownExport.contains("- Cleanup candidates: 3"))
    }

    func testCleanupResultBoundsDeletedIdentifierListsWhileDeletingAllCandidates() throws {
        let workspace = try makeInitializedWorkspace()
        let candidateCount = CinematicRunRecapShareArtifactCleanupResult.identifierListLimit + 3
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + candidateCount
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-retention-\(session).md",
                contents: artifactMarkdown(session: session)
            )
        }

        let result = workspace.cleanupRunRecapShareArtifacts()

        XCTAssertEqual(result.status, .deleted)
        XCTAssertEqual(result.cleanupCandidateCount, candidateCount)
        XCTAssertEqual(result.deletedCount, candidateCount)
        XCTAssertEqual(result.deletedIdentifiers.count, CinematicRunRecapShareArtifactCleanupResult.identifierListLimit)
        XCTAssertEqual(result.hiddenDeletedCount, 3)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.refreshedHistory.totalCount, CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
        XCTAssertEqual(result.refreshedHistory.cleanupCandidateCount, 0)
        XCTAssertLessThanOrEqual(result.help.count, CinematicRunRecapShareArtifactCleanupResult.helpMaxCharacters)
    }

    private func artifactMarkdown(session: Int) -> String {
        """
        # Compass Run Recap Share

        - Artifact: artifact-\(session)
        - Availability: available
        - Session: \(session)
        - Filename: recap-share-retention-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: Retention Recap \(session)
        - Status: succeeded
        - Detail: Retention detail
        - Commit: Retention commit \(session)
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
            .appending(path: "CinematicRunRecapShareArtifactRetentionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
