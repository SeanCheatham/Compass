import Foundation
@testable import Compass
import XCTest

@MainActor
final class CompassProjectDraftRefinementTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testAcceptQueuesRefinedTextThroughActiveStorageWithoutSubmittingRun() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        let state = PlanState(
            completed: ["Keep existing plan state"],
            immediate: PlanNext(plan: "Maintain draft preview semantics", verify: "swift test"),
            midTerm: "Continue Compass polish",
            longTerm: "Autonomous software factory"
        )
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )
        let refinement = DraftRefinement(
            originalDraft: "add parser tests",
            refinedText: "Add parser tests.",
            source: .generated
        )

        try workspace.initialize()
        try workspace.writeState(state)
        await project.refresh()
        project.draftEntry = "add parser tests"

        await project.acceptDraftRefinement(refinement)

        XCTAssertEqual(workspace.readDrafts(), "- Add parser tests.\n")
        XCTAssertEqual(project.drafts, "- Add parser tests.\n")
        XCTAssertEqual(project.draftEntry, "")
        XCTAssertEqual(project.state, state)
        XCTAssertEqual(project.sessions, [])
        XCTAssertEqual(project.activeStorage, .applicationSupport)
        XCTAssertEqual(project.phase, .idle)
        XCTAssertFalse(project.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    func testModifyReplacesDraftEntryWithoutQueueing() throws {
        let repoURL = try makeTemporaryGitRepository()
        let workspace = CompassWorkspace(repoURL: repoURL)
        let project = CompassProject(repoURL: repoURL)
        let refinement = DraftRefinement(
            originalDraft: "add parser tests",
            refinedText: "Add parser tests.",
            source: .generated
        )
        let stateBefore = project.state
        let activeStorageBefore = project.activeStorage

        project.draftEntry = "add parser tests"

        project.modifyDraft(with: refinement)

        XCTAssertEqual(project.draftEntry, "Add parser tests.")
        XCTAssertEqual(project.drafts, "")
        XCTAssertEqual(project.state, stateBefore)
        XCTAssertEqual(project.sessions, [])
        XCTAssertEqual(project.liveLog, [])
        XCTAssertEqual(project.activeStorage, activeStorageBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.compassURL.path))
        XCTAssertFalse(project.isRunning)
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let base = try makeTemporaryDirectory(prefix: "CompassProjectDraftRefinementSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String = "CompassProjectDraftRefinementTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func applicationSupportWorkspace(
        repoURL: URL,
        roots: KnownProjectStore.ApplicationSupportRoots
    ) -> CompassWorkspace {
        CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        .workspace
    }
}
