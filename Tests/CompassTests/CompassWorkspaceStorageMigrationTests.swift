import Foundation
@testable import Compass
import XCTest

final class CompassWorkspaceStorageMigrationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSuccessfulMigrationCopiesCoreAndSessionArtifactsAndWritesManifest() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        try write("draft entry\n", to: workspace.draftsURL)
        try write("lesson entry\n", to: workspace.lessonsURL)
        try write("vision entry\n", to: workspace.visionURL)
        try write("[{\"session\":1}]\n", to: workspace.sessionsRecordURL)
        let artifactURL = try workspace.writeSessionArtifact(
            session: 1,
            name: "develop-output.txt",
            contents: "artifact body\n"
        )
        let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)

        XCTAssertTrue(plan.isAvailable)

        let result = try CompassWorkspaceStorageMigrator(
            now: { Date(timeIntervalSince1970: 0) },
            makeTransactionIdentifier: { "success" }
        )
        .migrate(plan: plan)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.destinationURL.path))
        XCTAssertEqual(try read(plan.destinationURL.appending(path: "drafts.md")), "draft entry\n")
        XCTAssertEqual(try read(plan.destinationURL.appending(path: "lessons.md")), "lesson entry\n")
        XCTAssertEqual(try read(plan.destinationURL.appending(path: "COMPASS.md")), "vision entry\n")
        XCTAssertEqual(try read(plan.destinationURL.appending(path: "sessions.json")), "[{\"session\":1}]\n")
        XCTAssertEqual(
            try read(plan.destinationURL.appending(path: "sessions").appending(path: artifactURL.lastPathComponent)),
            "artifact body\n"
        )

        let manifest = try decodeManifest(at: plan.manifestURL)
        XCTAssertEqual(manifest.repoPath, repoURL.path)
        XCTAssertEqual(manifest.storageIdentifier, plan.projectStorageIdentifier)
        XCTAssertEqual(manifest.sourcePath, workspace.compassURL.path)
        XCTAssertEqual(manifest.destinationPath, plan.destinationURL.path)
        XCTAssertEqual(manifest.copiedFileCount, 6)
        XCTAssertEqual(manifest.migratedAt, "1970-01-01T00:00:00Z")

        XCTAssertEqual(result.manifest, manifest)
        XCTAssertEqual(result.copiedFileCount, 6)
        XCTAssertTrue(result.repoLocalSourcePreserved)
        XCTAssertFalse(result.activeStorageDidChange)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: plan.stagingParentURL
                    .appending(path: ".\(plan.projectStorageIdentifier)-migration-success")
                    .path
            )
        )
    }

    func testMissingAndIncompleteRepoLocalStorageBlockMigration() throws {
        let missingRepoURL = try makeTemporaryGitRepository()
        let missingRoots = try makeApplicationSupportRoots()
        let missingPlan = makeMigrationPlan(repoURL: missingRepoURL, roots: missingRoots)

        XCTAssertFalse(missingPlan.isAvailable)
        XCTAssertEqual(missingPlan.kind, .repoLocalMissing)
        XCTAssertThrowsError(try CompassWorkspaceStorageMigrator().migrate(plan: missingPlan)) { error in
            XCTAssertEqual(
                error as? CompassWorkspaceStorageMigrationError,
                .unavailable(kind: .repoLocalMissing, detail: missingPlan.detail)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingPlan.destinationURL.path))

        let incompleteRepoURL = try makeTemporaryGitRepository()
        let incompleteRoots = try makeApplicationSupportRoots()
        let incompleteWorkspace = CompassWorkspace(repoURL: incompleteRepoURL)
        try createDirectory(incompleteWorkspace.compassURL)
        try write("[]\n", to: incompleteWorkspace.sessionsRecordURL)
        let incompletePlan = makeMigrationPlan(repoURL: incompleteRepoURL, roots: incompleteRoots)

        XCTAssertFalse(incompletePlan.isAvailable)
        XCTAssertEqual(incompletePlan.kind, .repoLocalIncomplete)
        XCTAssertTrue(incompletePlan.detail.contains("state.json"))
        XCTAssertThrowsError(try CompassWorkspaceStorageMigrator().migrate(plan: incompletePlan)) { error in
            XCTAssertEqual(
                error as? CompassWorkspaceStorageMigrationError,
                .unavailable(kind: .repoLocalIncomplete, detail: incompletePlan.detail)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: incompletePlan.destinationURL.path))
    }

    func testOccupiedCurrentOrLegacyApplicationSupportCandidateBlocksMigration() throws {
        let currentRepoURL = try makeTemporaryGitRepository()
        let currentRoots = try makeApplicationSupportRoots()
        try CompassWorkspace(repoURL: currentRepoURL).initialize()
        let currentSeedPlan = makeMigrationPlan(repoURL: currentRepoURL, roots: currentRoots)
        try write("occupied\n", to: currentSeedPlan.destinationURL.appending(path: "state.json"))

        let currentPlan = makeMigrationPlan(repoURL: currentRepoURL, roots: currentRoots)

        XCTAssertFalse(currentPlan.isAvailable)
        XCTAssertEqual(currentPlan.kind, .applicationSupportOccupied)
        XCTAssertTrue(currentPlan.detail.contains("Current"))
        XCTAssertThrowsError(try CompassWorkspaceStorageMigrator().migrate(plan: currentPlan)) { error in
            XCTAssertEqual(
                error as? CompassWorkspaceStorageMigrationError,
                .unavailable(kind: .applicationSupportOccupied, detail: currentPlan.detail)
            )
        }

        let legacyRepoURL = try makeTemporaryGitRepository()
        let legacyRoots = try makeApplicationSupportRoots()
        try CompassWorkspace(repoURL: legacyRepoURL).initialize()
        let legacySeedPlan = makeMigrationPlan(repoURL: legacyRepoURL, roots: legacyRoots)
        try write("legacy occupied\n", to: legacySeedPlan.legacyCandidateURL.appending(path: "state.json"))

        let legacyPlan = makeMigrationPlan(repoURL: legacyRepoURL, roots: legacyRoots)

        XCTAssertFalse(legacyPlan.isAvailable)
        XCTAssertEqual(legacyPlan.kind, .applicationSupportOccupied)
        XCTAssertTrue(legacyPlan.detail.contains("Legacy"))
        XCTAssertThrowsError(try CompassWorkspaceStorageMigrator().migrate(plan: legacyPlan)) { error in
            XCTAssertEqual(
                error as? CompassWorkspaceStorageMigrationError,
                .unavailable(kind: .applicationSupportOccupied, detail: legacyPlan.detail)
            )
        }
    }

    func testMigrationPlanKeepsRepoLocalSourceWhenExternalStorageIsInjected() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
        try repoLocalWorkspace.initialize()
        try repoLocalWorkspace.writeLessons("repo-local lesson\n")

        let seedPlan = makeMigrationPlan(repoURL: repoURL, roots: roots)
        let externalWorkspace = CompassWorkspace(repoURL: repoURL, storageRootURL: seedPlan.destinationURL)
        try externalWorkspace.initialize()
        try externalWorkspace.writeLessons("external lesson\n")

        let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)

        XCTAssertEqual(plan.sourceCompassURL, repoLocalWorkspace.compassURL)
        XCTAssertEqual(plan.kind, .applicationSupportOccupied)
        XCTAssertFalse(plan.isAvailable)
        XCTAssertEqual(try read(repoLocalWorkspace.lessonsURL), "repo-local lesson\n")
        XCTAssertEqual(try read(externalWorkspace.lessonsURL), "external lesson\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoLocalWorkspace.compassURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalWorkspace.compassURL.path))
    }

    func testRollbackCleansStagingAfterInjectedCopyFailureAndPreservesSource() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        try write("source draft\n", to: workspace.draftsURL)
        let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)
        let expectedStagingURL = plan.stagingParentURL
            .appending(path: ".\(plan.projectStorageIdentifier)-migration-copy-fail")

        let migrator = CompassWorkspaceStorageMigrator(
            makeTransactionIdentifier: { "copy-fail" },
            copyCompassContents: { _, stagingURL, fileManager in
                try "partial\n".write(
                    to: stagingURL.appending(path: "partial.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                _ = fileManager
                throw InjectedMigrationError.copy
            }
        )

        XCTAssertThrowsError(try migrator.migrate(plan: plan)) { error in
            XCTAssertEqual(error as? InjectedMigrationError, .copy)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedStagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.destinationURL.path))
        XCTAssertEqual(try read(workspace.draftsURL), "source draft\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    }

    func testRollbackCleansStagingAndPartialDestinationAfterInjectedPromoteFailure() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        try write("source lesson\n", to: workspace.lessonsURL)
        let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)
        let expectedStagingURL = plan.stagingParentURL
            .appending(path: ".\(plan.projectStorageIdentifier)-migration-promote-fail")

        let migrator = CompassWorkspaceStorageMigrator(
            makeTransactionIdentifier: { "promote-fail" },
            promoteStaging: { _, destinationURL, fileManager in
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                try "partial\n".write(
                    to: destinationURL.appending(path: "partial.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                throw InjectedMigrationError.promote
            }
        )

        XCTAssertThrowsError(try migrator.migrate(plan: plan)) { error in
            XCTAssertEqual(error as? InjectedMigrationError, .promote)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedStagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.destinationURL.path))
        XCTAssertEqual(try read(workspace.lessonsURL), "source lesson\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    }

    func testMigrationPreservesRepoLocalStorageAsActiveSourceOfTruth() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        try write("source state\n", to: workspace.stateURL)
        try write("source session\n", to: workspace.sessionsURL.appending(path: "2-transcript.txt"))
        let sourceEntriesBefore = try recursiveFilePaths(in: workspace.compassURL)
        let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)

        let result = try CompassWorkspaceStorageMigrator(
            makeTransactionIdentifier: { "source-preserved" }
        )
        .migrate(plan: plan)

        XCTAssertTrue(result.repoLocalSourcePreserved)
        XCTAssertFalse(result.activeStorageDidChange)
        XCTAssertEqual(try read(workspace.stateURL), "source state\n")
        XCTAssertEqual(try read(workspace.sessionsURL.appending(path: "2-transcript.txt")), "source session\n")
        XCTAssertEqual(try recursiveFilePaths(in: workspace.compassURL), sourceEntriesBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.destinationURL.path))
    }

    func testMigrationManifestPlanAndResultTextStayBounded() throws {
        let longText = String(repeating: "very-long-segment-", count: 80)
        let manifest = CompassWorkspaceStorageMigrationManifest(
            repoPath: "/tmp/\(longText)",
            storageIdentifier: longText,
            sourcePath: "/tmp/source/\(longText)",
            destinationPath: "/tmp/destination/\(longText)",
            copiedFileCount: -4,
            migratedAt: longText
        )

        XCTAssertLessThanOrEqual(manifest.repoPath.count, CompassWorkspaceStorageMigrationManifest.pathLimit)
        XCTAssertLessThanOrEqual(manifest.storageIdentifier.count, CompassWorkspaceStorageMigrationManifest.identifierLimit)
        XCTAssertLessThanOrEqual(manifest.sourcePath.count, CompassWorkspaceStorageMigrationManifest.pathLimit)
        XCTAssertLessThanOrEqual(manifest.destinationPath.count, CompassWorkspaceStorageMigrationManifest.pathLimit)
        XCTAssertLessThanOrEqual(manifest.migratedAt.count, CompassWorkspaceStorageMigrationManifest.timestampLimit)
        XCTAssertEqual(manifest.copiedFileCount, 0)

        let repoURL = try makeTemporaryGitRepository(
            name: "Bounded Storage Migration " + String(repeating: "Segment ", count: 12)
        )
        let roots = try makeApplicationSupportRoots()
        try CompassWorkspace(repoURL: repoURL).initialize()
        let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)

        XCTAssertLessThanOrEqual(plan.label.count, CompassWorkspaceStorageMigrationPlan.labelLimit)
        XCTAssertLessThanOrEqual(plan.detail.count, CompassWorkspaceStorageMigrationPlan.detailLimit)
        XCTAssertLessThanOrEqual(plan.recommendation.count, CompassWorkspaceStorageMigrationPlan.recommendationLimit)

        let result = try CompassWorkspaceStorageMigrator(
            makeTransactionIdentifier: { "bounded" }
        )
        .migrate(plan: plan)

        XCTAssertLessThanOrEqual(result.summary.count, CompassWorkspaceStorageMigrationResult.summaryLimit)
        XCTAssertLessThanOrEqual(result.detail.count, CompassWorkspaceStorageMigrationResult.detailLimit)
    }

    private func makeMigrationPlan(
        repoURL: URL,
        roots: KnownProjectStore.ApplicationSupportRoots
    ) -> CompassWorkspaceStorageMigrationPlan {
        let assessment = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
        let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
        let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)
        return CompassWorkspaceStorageMigrationPlan(
            assessment: assessment,
            preflight: preflight,
            boundary: boundary
        )
    }

    private func makeTemporaryGitRepository(name: String? = nil) throws -> URL {
        let base = try makeTemporaryDirectory()
        let repoURL: URL
        if let name {
            repoURL = base.appending(path: name, directoryHint: .isDirectory)
            try createDirectory(repoURL)
        } else {
            repoURL = base
        }
        try createDirectory(repoURL.appending(path: ".git", directoryHint: .isDirectory))
        return repoURL
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStorageMigrationSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageMigrationTests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(url)
        try createDirectory(url)
        return url
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func write(_ contents: String, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func decodeManifest(at url: URL) throws -> CompassWorkspaceStorageMigrationManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CompassWorkspaceStorageMigrationManifest.self, from: data)
    }

    private func recursiveFilePaths(in url: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var paths: [String] = []
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relativePath = childURL.path
                .replacingOccurrences(of: url.path + "/", with: "")
            paths.append(relativePath)
        }
        return paths.sorted()
    }
}

private enum InjectedMigrationError: Error, Equatable {
    case copy
    case promote
}
