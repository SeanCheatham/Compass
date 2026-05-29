import Foundation
import Testing

@testable import Compass

final class CompassWorkspaceStorageBoundaryTests {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testHealthyRepoLocalStorageIsRecommendedCurrentBoundary() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(boundary.kind == .repoLocalRecommended)
    try #require(boundary.severity == .healthy)
    try #require(boundary.label == "Repo-local boundary")
    try #require(boundary.detail.contains("Active project state stays in repo-local .compass/"))
    try #require(boundary.detail.contains("Application Support"))
    try #require(boundary.recommendation.contains("No migration or mirroring needed by default"))
    try #require(boundary.migrationCouldBeTechnicallyEligible)
    try #require(boundary.assessmentKind == .repoLocalHealthy)
    try #require(boundary.preflightKind == .migrationReady)
  }

  @Test func testMissingAndIncompleteRepoLocalStorageAreRepairFirst() throws {
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

    try #require(missingBoundary.kind == .repoLocalRepairFirst)
    try #require(missingBoundary.severity == .warning)
    try #require(missingBoundary.detail.contains(".compass/ is missing"))
    try #require(missingBoundary.recommendation.contains("repo-local repair"))
    try #require(!missingBoundary.migrationCouldBeTechnicallyEligible)

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

    try #require(incompleteBoundary.kind == .repoLocalRepairFirst)
    try #require(incompleteBoundary.severity == .failure)
    try #require(incompleteBoundary.detail.contains(".compass/ is incomplete"))
    try #require(!incompleteBoundary.migrationCouldBeTechnicallyEligible)
  }

  @Test func testUnignoredCompassIsRepairFirstEvenWhenPreflightIsTechnicallyEligible() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    try write("build\n", to: repoURL.appending(path: ".gitignore"))

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(assessment.kind == .unignoredCompass)
    try #require(preflight.kind == .migrationReady)
    try #require(preflight.migrationWouldBeSafe)
    try #require(boundary.kind == .repoLocalRepairFirst)
    try #require(boundary.severity == .warning)
    try #require(boundary.detail.contains("not ignored"))
    try #require(boundary.recommendation.contains("repo-local repair"))
    try #require(boundary.migrationCouldBeTechnicallyEligible)
  }

  @Test func testApplicationSupportConflictIsInspectOnly() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let seedAssessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    try write(
      "current\n",
      to: seedAssessment.currentApplicationSupportCandidateURL.appending(path: "state.json"))

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(boundary.kind == .applicationSupportInspectOnlyConflict)
    try #require(boundary.severity == .warning)
    try #require(boundary.label == "Inspect support data")
    try #require(boundary.detail.contains("Active state remains in repo-local .compass/"))
    try #require(boundary.detail.contains("inspect-only conflict"))
    try #require(boundary.recommendation.contains("No migration or mirroring by default"))
    try #require(!boundary.migrationCouldBeTechnicallyEligible)
    try #require(boundary.preflightKind == .applicationSupportConflict)
  }

  @Test func testBoundaryDisplayTextAndIdentifiersStayBounded() throws {
    let longPath = "/tmp/" + String(repeating: "Long Repository Name With Spaces/", count: 12)
    let roots = KnownProjectStore.ApplicationSupportRoots(
      current: URL(
        fileURLWithPath: "/tmp/" + String(repeating: "Current Support Root/", count: 12))
    )
    let facts = CompassWorkspaceStorageAssessment.Facts(
      compassDirectoryExists: true,
      presentCoreFiles: Set(CompassWorkspaceStorageAssessment.CoreFile.allCases),
      sessionsDirectoryExists: true,
      gitignoreContents: ".compass/\n",
      currentApplicationSupportCandidateExists: true
    )
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: URL(fileURLWithPath: longPath),
      applicationSupportRoots: roots,
      facts: facts
    )
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(boundary.label.count <= CompassWorkspaceStorageBoundary.labelLimit)
    try #require(boundary.detail.count <= CompassWorkspaceStorageBoundary.detailLimit)
    try #require(
      boundary.recommendation.count <= CompassWorkspaceStorageBoundary.recommendationLimit)
    try #require(
      boundary.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    try #require(!boundary.label.isEmpty)
    try #require(!boundary.detail.isEmpty)
    try #require(!boundary.recommendation.isEmpty)
  }

  @Test func testStableIdentifiersFlowThroughAssessmentPreflightAndBoundary() throws {
    let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
    let repoURL = try makeTemporaryGitRepository(
      name: longName.replacingOccurrences(of: "/", with: "-"))
    let roots = try makeApplicationSupportRoots()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(boundary.projectStorageIdentifier == assessment.projectStorageIdentifier)
    try #require(boundary.projectStorageIdentifier == preflight.projectStorageIdentifier)
    try #require(
      boundary.currentApplicationSupportCandidateURL ==
      assessment.currentApplicationSupportCandidateURL)
    try #require(
      boundary.currentApplicationSupportCandidateURL ==
      preflight.currentApplicationSupportCandidateURL)
    try #require(
      boundary.currentApplicationSupportCandidateURL.lastPathComponent ==
      boundary.projectStorageIdentifier)
  }

  @Test func testBoundaryConsumesProvidedSignalsWithoutRescanning() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    try createDirectory(assessment.currentApplicationSupportCandidateURL)

    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(boundary.kind == .repoLocalRecommended)
    try #require(boundary.migrationCouldBeTechnicallyEligible)
  }

  @Test func testBoundaryConstructionCreatesNoRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    try #require(boundary.kind == .repoLocalRepairFirst)
    try #require(try entries(in: repoURL) == repoEntriesBefore)
    try #require(
      !FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    try #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    try #require(!FileManager.default.fileExists(atPath: roots.current.path))
    try #require(
      !FileManager.default.fileExists(atPath: boundary.currentApplicationSupportCandidateURL.path))
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
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
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
