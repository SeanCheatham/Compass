import Foundation
@testable import Compass
import XCTest

@MainActor
final class CompassProjectActiveStorageTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testResolverDefaultsToRepoLocalStorage() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            applicationSupportRoots: roots
        )
        let standardizedRepoURL = repoURL.standardizedFileURL
        let repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: standardizedRepoURL)

        XCTAssertEqual(resolver.activeStorage, .repoLocal)
        XCTAssertEqual(resolver.repoURL, standardizedRepoURL)
        XCTAssertEqual(resolver.storageRootURL, repoLocalURL)
        XCTAssertEqual(resolver.workspace.repoURL, standardizedRepoURL)
        XCTAssertEqual(resolver.workspace.compassURL, repoLocalURL)
    }

    func testResolverMapsApplicationSupportStorageToCurrentCandidate() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        let expectedURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
            for: repoURL.standardizedFileURL,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(resolver.storageRootURL, expectedURL)
        XCTAssertEqual(resolver.workspace.repoURL, repoURL.standardizedFileURL)
        XCTAssertEqual(resolver.workspace.compassURL, expectedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
    }

    func testProjectDefaultsToRepoLocalStorage() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            storageApplicationSupportRoots: roots
        )
        let repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: repoURL.standardizedFileURL)
        let applicationSupportURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
            for: repoURL.standardizedFileURL,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(project.activeStorage, .repoLocal)
        XCTAssertEqual(project.compassPath, repoLocalURL.path)

        await project.initializeWorkspace()

        XCTAssertDirectoryExists(repoLocalURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: applicationSupportURL.path))
    }

    func testApplicationSupportActiveStorageRoundTripsCompassFilesWithoutRepoLocalCompass() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        let workspace = resolver.workspace
        let state = PlanState(
            completed: ["application support"],
            immediate: PlanNext(plan: "Honor active storage", verify: "swift test"),
            midTerm: "persist",
            longTerm: "factory"
        )
        let records = [
            SessionRecord(
                session: 7,
                startedAt: 10,
                endedAt: 20,
                plan: "Plan",
                verify: "true",
                beforeSha: nil,
                afterSha: nil,
                commits: [],
                status: .succeeded,
                notes: ["done"],
                verifyOutput: nil,
                feedback: "ok"
            )
        ]

        XCTAssertEqual(project.compassPath, workspace.compassURL.path)

        await project.initializeWorkspace()
        try workspace.writeState(state)
        try workspace.writeDrafts("draft from support\n")
        try workspace.writeLessons("- lesson from support\n")
        try workspace.writeVision("vision from support\n")
        try workspace.writeSessions(records)

        await project.refresh()

        XCTAssertEqual(project.state, state)
        XCTAssertEqual(project.drafts, "draft from support\n")
        XCTAssertEqual(project.lessons, "- lesson from support\n")
        XCTAssertEqual(project.vision, "vision from support\n")
        XCTAssertEqual(project.sessions, records)
        XCTAssertDirectoryExists(workspace.compassURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))

        project.drafts = "updated support draft\n"
        await project.saveDrafts()
        project.lessons = "- updated support lesson\n"
        await project.saveLessons()

        XCTAssertEqual(workspace.readDrafts(), "updated support draft\n")
        XCTAssertEqual(workspace.readLessons(), "- updated support lesson\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let base = try makeTemporaryDirectory(prefix: "CompassProjectActiveStorageSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String = "CompassProjectActiveStorageTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func XCTAssertDirectoryExists(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            "Expected directory to exist at \(url.path).",
            file: file,
            line: line
        )
        XCTAssertTrue(isDirectory.boolValue, "Expected \(url.path) to be a directory.", file: file, line: line)
    }
}
