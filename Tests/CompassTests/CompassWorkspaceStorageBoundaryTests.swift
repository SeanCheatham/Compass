import Foundation
import Testing

@testable import Compass

struct CompassWorkspaceStorageBoundaryTests : ~Copyable {
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

    #require(boundary.kind == .repoLocalRecommended)
    #require(boundary.severity == .healthy)
    #require(boundary.label == "Repo-local boundary")
    #require(boundary.detail.contains("Active project state stays in repo-local .compass/"))
    #require(boundary.detail.contains("Application Support"))
    #require(boundary.recommendation.contains("No migration or mirroring needed by default"))
    #require(boundary.migrationCouldBeTechnicallyEligible)
    #require(boundary.assessmentKind == .repoLocalHealthy)
    #require(boundary.preflightKind == .migrationReady)
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

    #require(missingBoundary.kind == .repoLocalRepairFirst)
    #require(missingBoundary.severity == .warning)
    #require(missingBoundary.detail.contains(".compass/ is missing"))
    #require(missingBoundary.recommendation.contains("repo-local repair"))
    #require(!missingBoundary.migrationCouldBeTechnicallyEligible)

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

    #require(incompleteBoundary.kind == .repoLocalRepairFirst)
    #require(incompleteBoundary.severity == .failure)
    #require(incompleteBoundary.detail.contains(".compass/ is incomplete"))
    #require(!incompleteBoundary.migrationCouldBeTechnicallyEligible)
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

    #require(assessment.kind == .unignoredCompass)
    #require(preflight.kind == .migrationReady)
    #require(preflight.migrationWouldBeSafe)
    #require(boundary.kind == .repoLocalRepairFirst)
    #require(boundary.severity == .warning)
    #require(boundary.detail.contains("not ignored"))
    #require(boundary.recommendation.contains("repo-local repair"))
    #require(boundary.migrationCouldBeTechnicallyEligible)
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

    #require(boundary.kind == .applicationSupportInspectOnlyConflict)
    #require(boundary.severity == .warning)
    #require(boundary.label == "Inspect support data")
    #require(boundary.detail.contains("Active state remains in repo-local .compass/"))
    #require(boundary.detail.contains("inspect-only conflict"))
    #require(boundary.recommendation.contains("No migration or mirroring by default"))
    #require(!boundary.migrationCouldBeTechnicallyEligible)
    #require(boundary.preflightKind == .applicationSupportConflict)
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

    #require(boundary.label.count <= CompassWorkspaceStorageBoundary.labelLimit)
    #require(boundary.detail.count <= CompassWorkspaceStorageBoundary.detailLimit)
    #require(
      boundary.recommendation.count <= CompassWorkspaceStorageBoundary.recommendationLimit)
    #require(
      boundary.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    #require(!boundary.label.isEmpty)
    #require(!boundary.detail.isEmpty)
    #require(!boundary.recommendation.isEmpty)
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

    #require(boundary.projectStorageIdentifier == assessment.projectStorageIdentifier)
    #require(boundary.projectStorageIdentifier == preflight.projectStorageIdentifier)
    #require(
      boundary.currentApplicationSupportCandidateURL ==
      assessment.currentApplicationSupportCandidateURL)
    #require(
      boundary.currentApplicationSupportCandidateURL ==
      preflight.currentApplicationSupportCandidateURL)
    #require(
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

    #require(boundary.kind == .repoLocalRecommended)
    #require(boundary.migrationCouldBeTechnicallyEligible)
  }

  @Test func testBoundaryConstructionCreatesNoRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    #require(boundary.kind == .repoLocalRepairFirst)
    #require(try entries(in: repoURL) == repoEntriesBefore)
    #require(
      !FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    #require(!FileManager.default.fileExists(atPath: roots.current.path))
    #require(
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
