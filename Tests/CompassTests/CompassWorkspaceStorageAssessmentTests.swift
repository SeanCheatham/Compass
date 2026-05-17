import Foundation
@testable import Compass
import XCTest

final class CompassWorkspaceStorageAssessmentTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testHealthyRepoLocalStorageReportsNoActionNeeded() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()

        let assessment = CompassWorkspaceStorageAssessment(
            repoURL: repoURL,
            applicationSupportRoots: roots
        )

        XCTAssertTrue(assessment.isHealthy)
        XCTAssertTrue(assessment.issues.isEmpty)
        XCTAssertEqual(assessment.kind, .repoLocalHealthy)
        XCTAssertEqual(assessment.severity, .healthy)
        XCTAssertEqual(assessment.label, "Repo-local healthy")
        XCTAssertTrue(assessment.detail.contains("core files"))
        XCTAssertTrue(assessment.recommendation.contains("No storage action"))
    }

    func testMissingWorkspaceReportsUninitializedRepoLocalStorage() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()

        let assessment = CompassWorkspaceStorageAssessment(
            repoURL: repoURL,
            applicationSupportRoots: roots
        )

        XCTAssertFalse(assessment.isHealthy)
        XCTAssertEqual(assessment.kind, .missingWorkspace)
        XCTAssertEqual(assessment.severity, .warning)
        XCTAssertTrue(assessment.detail.contains(".compass/ has not been initialized"))
        XCTAssertTrue(assessment.recommendation.contains("Initialize"))
    }

    func testIncompleteCoreFilesReportMissingCoreAndSessionStorage() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try createDirectory(workspace.compassURL)
        try write(".compass/\n", to: repoURL.appending(path: ".gitignore"))
        try write("[]\n", to: workspace.sessionsRecordURL)

        let assessment = CompassWorkspaceStorageAssessment(
            repoURL: repoURL,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(assessment.kind, .incompleteCoreFiles)
        XCTAssertEqual(assessment.severity, .failure)
        XCTAssertTrue(assessment.detail.contains("state.json"))
        XCTAssertTrue(assessment.detail.contains("drafts.md"))
        XCTAssertTrue(assessment.detail.contains("lessons.md"))
        XCTAssertTrue(assessment.detail.contains("COMPASS.md"))
        XCTAssertTrue(assessment.detail.contains("sessions/"))
        XCTAssertFalse(assessment.detail.contains("sessions.json"))
    }

    func testGitignoreVariantsRecognizeCompassCoverageAndFlagMissingCoverage() throws {
        let coveredVariants = [
            ".compass\n",
            ".compass/\n",
            "  /.compass  \n",
            "# build output\nbuild\n  /.compass/  \n"
        ]

        for gitignoreText in coveredVariants {
            let repoURL = try makeTemporaryGitRepository()
            let roots = try makeApplicationSupportRoots()
            let workspace = CompassWorkspace(repoURL: repoURL)
            try workspace.initialize()
            try write(gitignoreText, to: repoURL.appending(path: ".gitignore"))

            let assessment = CompassWorkspaceStorageAssessment(
                repoURL: repoURL,
                applicationSupportRoots: roots
            )

            XCTAssertEqual(assessment.kind, .repoLocalHealthy, gitignoreText)
        }

        let unignoredRepoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: unignoredRepoURL)
        try workspace.initialize()
        try write("# .compass/\nbuild\n", to: unignoredRepoURL.appending(path: ".gitignore"))

        let assessment = CompassWorkspaceStorageAssessment(
            repoURL: unignoredRepoURL,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(assessment.kind, .unignoredCompass)
        XCTAssertEqual(assessment.severity, .warning)
        XCTAssertTrue(assessment.recommendation.contains(".gitignore"))
    }

    func testCandidateApplicationSupportPathIsStableSanitizedAndBounded() throws {
        let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
        let repoURL = try makeTemporaryGitRepository(name: longName.replacingOccurrences(of: "/", with: "-"))
        let roots = try makeApplicationSupportRoots()

        let first = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
        let second = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)

        XCTAssertEqual(first.projectStorageIdentifier, second.projectStorageIdentifier)
        XCTAssertEqual(first.currentApplicationSupportCandidateURL, second.currentApplicationSupportCandidateURL)
        XCTAssertEqual(first.legacyApplicationSupportCandidateURL, second.legacyApplicationSupportCandidateURL)
        XCTAssertLessThanOrEqual(
            first.projectStorageIdentifier.count,
            CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
        )
        XCTAssertTrue(isSafeIdentifier(first.projectStorageIdentifier), first.projectStorageIdentifier)
        XCTAssertEqual(first.currentApplicationSupportCandidateURL.lastPathComponent, first.projectStorageIdentifier)
        XCTAssertEqual(first.legacyApplicationSupportCandidateURL.lastPathComponent, first.projectStorageIdentifier)
    }

    func testCurrentAndLegacyApplicationSupportCandidatesAreReported() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()

        let seedAssessment = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
        try createDirectory(seedAssessment.currentApplicationSupportCandidateURL)
        try createDirectory(seedAssessment.legacyApplicationSupportCandidateURL)

        let assessment = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
        let issueKinds = assessment.issues.map(\.kind)

        XCTAssertEqual(assessment.kind, .currentApplicationSupportCandidateExists)
        XCTAssertTrue(issueKinds.contains(.currentApplicationSupportCandidateExists))
        XCTAssertTrue(issueKinds.contains(.legacyApplicationSupportCandidateExists))
        XCTAssertTrue(assessment.detail.contains("Future storage candidate"))
        XCTAssertEqual(assessment.severity, .warning)
    }

    func testAssessmentDisplayTextAndIdentifiersStayBounded() throws {
        let longPath = "/tmp/" + String(repeating: "Long Repository Name With Spaces/", count: 12)
        let roots = KnownProjectStore.ApplicationSupportRoots(
            current: URL(fileURLWithPath: "/tmp/" + String(repeating: "Current Support Root/", count: 10)),
            legacy: URL(fileURLWithPath: "/tmp/" + String(repeating: "Legacy Support Root/", count: 10))
        )
        let facts = CompassWorkspaceStorageAssessment.Facts(
            compassDirectoryExists: true,
            presentCoreFiles: Set(CompassWorkspaceStorageAssessment.CoreFile.allCases),
            sessionsDirectoryExists: true,
            gitignoreContents: ".compass/\n",
            currentApplicationSupportCandidateExists: true,
            legacyApplicationSupportCandidateExists: true
        )

        let assessment = CompassWorkspaceStorageAssessment(
            repoURL: URL(fileURLWithPath: longPath),
            applicationSupportRoots: roots,
            facts: facts
        )

        XCTAssertLessThanOrEqual(
            assessment.projectStorageIdentifier.count,
            CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
        )
        for issue in [assessment.primaryIssue] + assessment.issues {
            XCTAssertLessThanOrEqual(issue.label.count, CompassWorkspaceStorageAssessment.labelLimit)
            XCTAssertLessThanOrEqual(issue.detail.count, CompassWorkspaceStorageAssessment.detailLimit)
            XCTAssertLessThanOrEqual(issue.recommendation.count, CompassWorkspaceStorageAssessment.recommendationLimit)
        }
    }

    func testAssessingDoesNotCreateRepoOrApplicationSupportFiles() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let repoEntriesBefore = try entries(in: repoURL)

        _ = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)

        XCTAssertEqual(try entries(in: repoURL), repoEntriesBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: roots.current.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: roots.legacy.path))
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
        let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStorageAssessmentSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageAssessmentTests") throws -> URL {
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

    private func entries(in url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    private func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("-"), !value.hasSuffix("-") else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar.value == 45
        }
    }
}
