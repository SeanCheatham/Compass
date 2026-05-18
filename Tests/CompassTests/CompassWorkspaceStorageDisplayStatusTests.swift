import Foundation
@testable import Compass
import XCTest

final class CompassWorkspaceStorageDisplayStatusTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testApplicationSupportActiveWithNoRepoLocalReportsSupportRoot() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        try resolver.workspace.initialize()

        let assessment = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
        let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
        let display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots,
            activeStorageRootURL: resolver.storageRootURL,
            assessment: assessment,
            preflight: preflight
        )

        XCTAssertEqual(assessment.kind, .missingWorkspace)
        XCTAssertEqual(preflight.repoLocalReadiness, .missingWorkspace)
        XCTAssertEqual(display.kind, .applicationSupportActive)
        XCTAssertEqual(display.severity, .healthy)
        XCTAssertEqual(display.activeRootHealth, .healthy)
        XCTAssertEqual(display.activeStorageRootURL, resolver.storageRootURL.standardizedFileURL)
        XCTAssertEqual(display.activeStorageDisplayName, "Application Support")
        XCTAssertTrue(display.detail.contains("Current Compass state root"))
        XCTAssertTrue(display.recommendation.contains("Application Support remains the active state root"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
    }

    func testApplicationSupportActiveReportsMissingSupportStorage() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )

        let display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(display.kind, .applicationSupportActiveMissing)
        XCTAssertEqual(display.severity, .warning)
        XCTAssertEqual(display.activeRootHealth, .missing)
        XCTAssertEqual(display.activeStorageRootURL, resolver.storageRootURL.standardizedFileURL)
        XCTAssertEqual(display.activeRootFacts.missingCoreFiles, CompassWorkspaceStorageAssessment.CoreFile.allCases)
        XCTAssertFalse(display.activeRootFacts.sessionsDirectoryExists)
        XCTAssertTrue(display.detail.contains("Active Application Support state root is missing"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver.storageRootURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
    }

    func testApplicationSupportActiveReportsIncompleteSupportStorage() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        let supportWorkspace = resolver.workspace
        try createDirectory(supportWorkspace.compassURL)
        try write("[]\n", to: supportWorkspace.sessionsRecordURL)

        let display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(display.kind, .applicationSupportActiveIncomplete)
        XCTAssertEqual(display.severity, .failure)
        XCTAssertEqual(display.activeRootHealth, .incomplete)
        XCTAssertTrue(display.activeRootFacts.presentCoreFiles.contains(.sessionsRecord))
        XCTAssertFalse(display.activeRootFacts.missingItems.contains("sessions.json"))
        XCTAssertTrue(display.activeRootFacts.missingItems.contains("state.json"))
        XCTAssertTrue(display.activeRootFacts.missingItems.contains("drafts.md"))
        XCTAssertTrue(display.activeRootFacts.missingItems.contains("lessons.md"))
        XCTAssertTrue(display.activeRootFacts.missingItems.contains("COMPASS.md"))
        XCTAssertTrue(display.activeRootFacts.missingItems.contains("sessions/"))
        XCTAssertTrue(display.detail.contains("Active Application Support state root is missing"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportWorkspace.repoLocalCompassURL.path))
    }

    func testRepoLocalDisplayStatusMatchesExistingBoundary() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        try CompassWorkspace(repoURL: repoURL).initialize()

        let assessment = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
        let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
        let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)
        let display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .repoLocal,
            applicationSupportRoots: roots,
            activeStorageRootURL: CompassWorkspace.repoLocalStorageRootURL(for: repoURL.standardizedFileURL),
            assessment: assessment,
            preflight: preflight
        )

        XCTAssertEqual(display.kind, .repoLocalRecommended)
        XCTAssertEqual(display.severity, boundary.severity)
        XCTAssertEqual(display.label, boundary.label)
        XCTAssertEqual(display.detail, boundary.detail)
        XCTAssertEqual(display.recommendation, boundary.recommendation)
        XCTAssertEqual(display.systemImage, boundary.systemImage)
        XCTAssertEqual(display.activeRootHealth, .healthy)
        XCTAssertEqual(display.repoLocalReadiness, .ready)
    }

    func testDisplayStatusTextAndIdentifiersStayBounded() throws {
        let longRepoPath = "/tmp/" + String(repeating: "Long Repository Name With Spaces/", count: 14)
        let longSupportPath = "/tmp/" + String(repeating: "Current Support Root/", count: 14)
        let roots = KnownProjectStore.ApplicationSupportRoots(
            current: URL(fileURLWithPath: longSupportPath),
            legacy: URL(fileURLWithPath: "/tmp/" + String(repeating: "Legacy Support Root/", count: 14))
        )
        let repoURL = URL(fileURLWithPath: longRepoPath)
        let facts = CompassWorkspaceStorageAssessment.Facts(
            compassDirectoryExists: false,
            presentCoreFiles: [],
            sessionsDirectoryExists: false,
            gitignoreContents: nil,
            currentApplicationSupportCandidateExists: true,
            legacyApplicationSupportCandidateExists: true
        )
        let assessment = CompassWorkspaceStorageAssessment(
            repoURL: repoURL,
            applicationSupportRoots: roots,
            facts: facts
        )
        let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
        let display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots,
            activeStorageRootURL: assessment.currentApplicationSupportCandidateURL,
            assessment: assessment,
            preflight: preflight,
            activeRootFacts: CompassWorkspaceStorageDisplayStatus.ActiveRootFacts(
                directoryExists: true,
                presentCoreFiles: [.state],
                sessionsDirectoryExists: false
            )
        )

        XCTAssertLessThanOrEqual(
            display.projectStorageIdentifier.count,
            CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
        )
        XCTAssertLessThanOrEqual(display.label.count, CompassWorkspaceStorageDisplayStatus.labelLimit)
        XCTAssertLessThanOrEqual(display.detail.count, CompassWorkspaceStorageDisplayStatus.detailLimit)
        XCTAssertLessThanOrEqual(
            display.recommendation.count,
            CompassWorkspaceStorageDisplayStatus.recommendationLimit
        )
        XCTAssertFalse(display.label.isEmpty)
        XCTAssertFalse(display.detail.isEmpty)
        XCTAssertFalse(display.recommendation.isEmpty)
    }

    func testHeaderActionVisibilityDistinguishesActiveStorageAndFeedback() {
        let repoLocalActions = CompassWorkspaceStorageHeaderActions(
            activeStorage: .repoLocal,
            candidatePreparationIsAvailable: true,
            candidatePreparationShouldShowFeedback: false,
            activationIsAvailable: true,
            activationShouldShowFeedback: false,
            activationIsIdle: true,
            repoLocalRepairActionIsAvailable: true
        )

        XCTAssertTrue(repoLocalActions.showsCandidatePreparation)
        XCTAssertTrue(repoLocalActions.showsActivation)
        XCTAssertTrue(repoLocalActions.showsRepoLocalRepair)

        let busyRepoLocalActions = CompassWorkspaceStorageHeaderActions(
            activeStorage: .repoLocal,
            candidatePreparationIsAvailable: true,
            candidatePreparationShouldShowFeedback: false,
            activationIsAvailable: true,
            activationShouldShowFeedback: false,
            activationIsIdle: false,
            repoLocalRepairActionIsAvailable: false
        )

        XCTAssertTrue(busyRepoLocalActions.showsCandidatePreparation)
        XCTAssertFalse(busyRepoLocalActions.showsActivation)
        XCTAssertFalse(busyRepoLocalActions.showsRepoLocalRepair)

        let supportActiveActions = CompassWorkspaceStorageHeaderActions(
            activeStorage: .applicationSupport,
            candidatePreparationIsAvailable: true,
            candidatePreparationShouldShowFeedback: false,
            activationIsAvailable: true,
            activationShouldShowFeedback: false,
            activationIsIdle: true,
            repoLocalRepairActionIsAvailable: true
        )

        XCTAssertFalse(supportActiveActions.showsCandidatePreparation)
        XCTAssertFalse(supportActiveActions.showsActivation)
        XCTAssertFalse(supportActiveActions.showsRepoLocalRepair)

        let supportFeedbackActions = CompassWorkspaceStorageHeaderActions(
            activeStorage: .applicationSupport,
            candidatePreparationIsAvailable: false,
            candidatePreparationShouldShowFeedback: true,
            activationIsAvailable: false,
            activationShouldShowFeedback: true,
            activationIsIdle: false,
            repoLocalRepairActionIsAvailable: true
        )

        XCTAssertTrue(supportFeedbackActions.showsCandidatePreparation)
        XCTAssertTrue(supportFeedbackActions.showsActivation)
        XCTAssertFalse(supportFeedbackActions.showsRepoLocalRepair)
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStorageDisplayStatusSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageDisplayStatusTests") throws -> URL {
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
}
