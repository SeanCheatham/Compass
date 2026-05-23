import Foundation
import XCTest

@testable import Compass

final class CompassWorkspaceStorageBoundaryTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testHealthyRepoLocalStorageIsRecommendedCurrentBoundary() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertEqual(boundary.kind, .repoLocalRecommended)
    XCTAssertEqual(boundary.severity, .healthy)
    XCTAssertEqual(boundary.label, "Repo-local boundary")
    XCTAssertTrue(boundary.detail.contains("Active project state stays in repo-local .compass/"))
    XCTAssertTrue(boundary.detail.contains("Application Support"))
    XCTAssertTrue(boundary.recommendation.contains("No migration or mirroring needed by default"))
    XCTAssertTrue(boundary.migrationCouldBeTechnicallyEligible)
    XCTAssertEqual(boundary.assessmentKind, .repoLocalHealthy)
    XCTAssertEqual(boundary.preflightKind, .migrationReady)
  }

  func testMissingAndIncompleteRepoLocalStorageAreRepairFirst() throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()
    let missingAssessment = CompassWorkspaceStorageAssessment(
      repoURL: missingRepoURL,
      applicationSupportRoots: missingRoots
    )
    let missingPreflight = CompassWorkspaceStoragePreflight(assessment: missingAssessment)
    let missingBoundary = CompassWorkspaceStorageBoundary(
      assessment: missingAssessment,
      preflight: missingPreflight
    )

    XCTAssertEqual(missingBoundary.kind, .repoLocalRepairFirst)
    XCTAssertEqual(missingBoundary.severity, .warning)
    XCTAssertTrue(missingBoundary.detail.contains(".compass/ is missing"))
    XCTAssertTrue(missingBoundary.recommendation.contains("repo-local repair"))
    XCTAssertFalse(missingBoundary.migrationCouldBeTechnicallyEligible)

    let incompleteRepoURL = try makeTemporaryGitRepository()
    let incompleteRoots = try makeApplicationSupportRoots()
    let incompleteWorkspace = CompassWorkspace(repoURL: incompleteRepoURL)
    try createDirectory(incompleteWorkspace.compassURL)
    try write(".compass/\n", to: incompleteRepoURL.appending(path: ".gitignore"))

    let incompleteAssessment = CompassWorkspaceStorageAssessment(
      repoURL: incompleteRepoURL,
      applicationSupportRoots: incompleteRoots
    )
    let incompletePreflight = CompassWorkspaceStoragePreflight(assessment: incompleteAssessment)
    let incompleteBoundary = CompassWorkspaceStorageBoundary(
      assessment: incompleteAssessment,
      preflight: incompletePreflight
    )

    XCTAssertEqual(incompleteBoundary.kind, .repoLocalRepairFirst)
    XCTAssertEqual(incompleteBoundary.severity, .failure)
    XCTAssertTrue(incompleteBoundary.detail.contains(".compass/ is incomplete"))
    XCTAssertFalse(incompleteBoundary.migrationCouldBeTechnicallyEligible)
  }

  func testUnignoredCompassIsRepairFirstEvenWhenPreflightIsTechnicallyEligible() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    try write("build\n", to: repoURL.appending(path: ".gitignore"))

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertEqual(assessment.kind, .unignoredCompass)
    XCTAssertEqual(preflight.kind, .migrationReady)
    XCTAssertTrue(preflight.migrationWouldBeSafe)
    XCTAssertEqual(boundary.kind, .repoLocalRepairFirst)
    XCTAssertEqual(boundary.severity, .warning)
    XCTAssertTrue(boundary.detail.contains("not ignored"))
    XCTAssertTrue(boundary.recommendation.contains("repo-local repair"))
    XCTAssertTrue(boundary.migrationCouldBeTechnicallyEligible)
  }

  func testCurrentAndLegacyApplicationSupportConflictsAreInspectOnly() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let seedAssessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    try write(
      "current\n",
      to: seedAssessment.currentApplicationSupportCandidateURL.appending(path: "state.json"))
    try write(
      "legacy\n",
      to: seedAssessment.legacyApplicationSupportCandidateURL.appending(path: "state.json"))

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertEqual(boundary.kind, .applicationSupportInspectOnlyConflict)
    XCTAssertEqual(boundary.severity, .warning)
    XCTAssertEqual(boundary.label, "Inspect support data")
    XCTAssertTrue(boundary.detail.contains("Active state remains in repo-local .compass/"))
    XCTAssertTrue(boundary.detail.contains("Current, Legacy"))
    XCTAssertTrue(boundary.detail.contains("inspect-only conflicts"))
    XCTAssertTrue(boundary.recommendation.contains("No migration or mirroring by default"))
    XCTAssertFalse(boundary.migrationCouldBeTechnicallyEligible)
    XCTAssertEqual(boundary.preflightKind, .applicationSupportConflict)
  }

  func testBoundaryDisplayTextAndIdentifiersStayBounded() throws {
    let longPath = "/tmp/" + String(repeating: "Long Repository Name With Spaces/", count: 12)
    let roots = KnownProjectStore.ApplicationSupportRoots(
      current: URL(
        fileURLWithPath: "/tmp/" + String(repeating: "Current Support Root/", count: 12)),
      legacy: URL(fileURLWithPath: "/tmp/" + String(repeating: "Legacy Support Root/", count: 12))
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
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertLessThanOrEqual(boundary.label.count, CompassWorkspaceStorageBoundary.labelLimit)
    XCTAssertLessThanOrEqual(boundary.detail.count, CompassWorkspaceStorageBoundary.detailLimit)
    XCTAssertLessThanOrEqual(
      boundary.recommendation.count, CompassWorkspaceStorageBoundary.recommendationLimit)
    XCTAssertLessThanOrEqual(
      boundary.projectStorageIdentifier.count,
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    XCTAssertFalse(boundary.label.isEmpty)
    XCTAssertFalse(boundary.detail.isEmpty)
    XCTAssertFalse(boundary.recommendation.isEmpty)
  }

  func testStableIdentifiersFlowThroughAssessmentPreflightAndBoundary() throws {
    let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
    let repoURL = try makeTemporaryGitRepository(
      name: longName.replacingOccurrences(of: "/", with: "-"))
    let roots = try makeApplicationSupportRoots()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertEqual(boundary.projectStorageIdentifier, assessment.projectStorageIdentifier)
    XCTAssertEqual(boundary.projectStorageIdentifier, preflight.projectStorageIdentifier)
    XCTAssertEqual(
      boundary.currentApplicationSupportCandidateURL,
      assessment.currentApplicationSupportCandidateURL)
    XCTAssertEqual(
      boundary.currentApplicationSupportCandidateURL,
      preflight.currentApplicationSupportCandidateURL)
    XCTAssertEqual(
      boundary.legacyApplicationSupportCandidateURL, assessment.legacyApplicationSupportCandidateURL
    )
    XCTAssertEqual(
      boundary.legacyApplicationSupportCandidateURL, preflight.legacyApplicationSupportCandidateURL)
    XCTAssertEqual(
      boundary.currentApplicationSupportCandidateURL.lastPathComponent,
      boundary.projectStorageIdentifier)
    XCTAssertEqual(
      boundary.legacyApplicationSupportCandidateURL.lastPathComponent,
      boundary.projectStorageIdentifier)
  }

  func testBoundaryConsumesProvidedSignalsWithoutRescanning() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    try createDirectory(assessment.currentApplicationSupportCandidateURL)
    try createDirectory(assessment.legacyApplicationSupportCandidateURL)

    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertEqual(boundary.kind, .repoLocalRecommended)
    XCTAssertTrue(boundary.migrationCouldBeTechnicallyEligible)
  }

  func testBoundaryConstructionCreatesNoRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    XCTAssertEqual(boundary.kind, .repoLocalRepairFirst)
    XCTAssertEqual(try entries(in: repoURL), repoEntriesBefore)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: roots.current.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: roots.legacy.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: boundary.currentApplicationSupportCandidateURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: boundary.legacyApplicationSupportCandidateURL.path))
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
    let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStorageBoundarySupport")
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
      legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageBoundaryTests")
    throws -> URL
  {
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
}
