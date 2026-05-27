import Foundation
import Testing

@testable import Compass

struct CompassWorkspaceStoragePreflightTests : ~Copyable {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testHealthyRepoLocalPreflightIsReadyForFutureMigration() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    #require(preflight.repoLocalReadiness == .ready)
    #require(preflight.missingCoreFiles.isEmpty)
    #require(preflight.sessionsDirectoryExists)
    #require(!preflight.currentApplicationSupportCandidateIsOccupied)
    #require(preflight.migrationWouldBeSafe)
    #require(preflight.kind == .migrationReady)
    #require(preflight.label == "Preflight clear")
    #require(preflight.detail.contains("Application Support candidate path is empty"))
    #require(preflight.recommendation.contains("without path conflicts"))
  }

  @Test func testMissingAndIncompleteRepoLocalStorageBlockPreflight() throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()

    let missingPreflight = CompassWorkspaceStoragePreflight(
      repoURL: missingRepoURL,
      applicationSupportRoots: missingRoots
    )

    #require(missingPreflight.repoLocalReadiness == .missingWorkspace)
    #require(missingPreflight.kind == .repoLocalMissing)
    #require(!missingPreflight.migrationWouldBeSafe)
    #require(
      missingPreflight.missingCoreFiles ==
      CompassWorkspaceStorageAssessment.CoreFile.allCases
    )
    #require(!missingPreflight.sessionsDirectoryExists)
    #require(missingPreflight.recommendation.contains("repo-local repair"))

    let incompleteRepoURL = try makeTemporaryGitRepository()
    let incompleteRoots = try makeApplicationSupportRoots()
    let incompleteWorkspace = CompassWorkspace(repoURL: incompleteRepoURL)
    try createDirectory(incompleteWorkspace.compassURL)
    try write("[]\n", to: incompleteWorkspace.sessionsRecordURL)

    let incompletePreflight = CompassWorkspaceStoragePreflight(
      repoURL: incompleteRepoURL,
      applicationSupportRoots: incompleteRoots
    )

    #require(incompletePreflight.repoLocalReadiness == .incompleteWorkspace)
    #require(incompletePreflight.kind == .repoLocalIncomplete)
    #require(!incompletePreflight.migrationWouldBeSafe)
    #require(incompletePreflight.detail.contains("state.json"))
    #require(incompletePreflight.detail.contains("drafts.md"))
    #require(incompletePreflight.detail.contains("lessons.md"))
    #require(incompletePreflight.detail.contains("COMPASS.md"))
    #require(incompletePreflight.detail.contains("sessions/"))
    #require(!incompletePreflight.detail.contains("sessions.json"))
  }

  @Test func testApplicationSupportConflictIsInspectOnly() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let seedPreflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )
    try write(
      "current\n",
      to: seedPreflight.currentApplicationSupportCandidateURL.appending(path: "state.json"))
    let repoEntriesBefore = try entries(in: repoURL)
    let currentEntriesBefore = try entries(in: seedPreflight.currentApplicationSupportCandidateURL)

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    #require(preflight.repoLocalReadiness == .ready)
    #require(preflight.kind == .applicationSupportConflict)
    #require(!preflight.migrationWouldBeSafe)
    #require(preflight.currentApplicationSupportCandidateIsOccupied)
    #require(preflight.occupiedApplicationSupportCandidates.count == 1)
    #require(preflight.detail.contains("Inspect-only conflict"))
    #require(preflight.recommendation.contains("Compass remains on repo-local .compass/"))
    #require(try entries(in: repoURL) == repoEntriesBefore)
    #require(
      try entries(in: seedPreflight.currentApplicationSupportCandidateURL) == currentEntriesBefore)
    #require(
      try String(
        contentsOf: seedPreflight.currentApplicationSupportCandidateURL.appending(
          path: "state.json"), encoding: .utf8) ==
      "current\n"
    )
  }

  @Test func testInjectedApplicationSupportWorkspaceDoesNotSatisfyRepoLocalPreflight() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let candidateURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
      for: repoURL,
      applicationSupportRoots: roots
    )
    let externalWorkspace = CompassWorkspace(repoURL: repoURL, storageRootURL: candidateURL)
    try externalWorkspace.initialize()
    try externalWorkspace.writeDrafts("external draft\n")

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    #require(preflight.repoLocalReadiness == .missingWorkspace)
    #require(preflight.kind == .repoLocalMissing)
    #require(!preflight.migrationWouldBeSafe)
    #require(preflight.currentApplicationSupportCandidateIsOccupied)
    #require(FileManager.default.fileExists(atPath: externalWorkspace.compassURL.path))
    #require(
      try String(contentsOf: externalWorkspace.draftsURL, encoding: .utf8) == "external draft\n")
    #require(
      !FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
  }

  @Test func testPreflightDisplayTextAndIdentifiersStayBounded() throws {
    let longName = "Storage Migration Project " + String(repeating: "Segment ", count: 18)
    let repoURL = try makeTemporaryGitRepository(name: longName)
    let roots = KnownProjectStore.ApplicationSupportRoots(
      current: URL(
        fileURLWithPath: "/tmp/" + String(repeating: "Current Support Root/", count: 12))
    )

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    #require(
      preflight.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    #require(preflight.label.count <= CompassWorkspaceStoragePreflight.labelLimit)
    #require(preflight.detail.count <= CompassWorkspaceStoragePreflight.detailLimit)
    #require(
      preflight.recommendation.count <=
      CompassWorkspaceStoragePreflight.recommendationLimit
    )
    #require(!preflight.label.isEmpty)
    #require(!preflight.detail.isEmpty)
    #require(!preflight.recommendation.isEmpty)
  }

  @Test func testProjectStorageIdentifierAndCandidateURLsAreStable() throws {
    let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
    let repoURL = try makeTemporaryGitRepository(
      name: longName.replacingOccurrences(of: "/", with: "-"))
    let roots = try makeApplicationSupportRoots()

    let first = CompassWorkspaceStoragePreflight(repoURL: repoURL, applicationSupportRoots: roots)
    let second = CompassWorkspaceStoragePreflight(repoURL: repoURL, applicationSupportRoots: roots)

    #require(first.projectStorageIdentifier == second.projectStorageIdentifier)
    #require(
      first.currentApplicationSupportCandidateURL == second.currentApplicationSupportCandidateURL)
    #require(isSafeIdentifier(first.projectStorageIdentifier))
    #require(
      first.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    #require(
      first.currentApplicationSupportCandidateURL.lastPathComponent == first.projectStorageIdentifier)
  }

  @Test func testPreflightDoesNotCreateRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    #require(try entries(in: repoURL) == repoEntriesBefore)
    #require(
      !FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    #require(!FileManager.default.fileExists(atPath: roots.current.path))
    #require(
      !FileManager.default.fileExists(atPath: preflight.currentApplicationSupportCandidateURL.path))
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
    let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStoragePreflightSupport")
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStoragePreflightTests")
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
