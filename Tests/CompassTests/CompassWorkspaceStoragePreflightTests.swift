import Foundation
import XCTest

@testable import Compass

final class CompassWorkspaceStoragePreflightTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testHealthyRepoLocalPreflightIsReadyForFutureMigration() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    XCTAssertEqual(preflight.repoLocalReadiness, .ready)
    XCTAssertTrue(preflight.missingCoreFiles.isEmpty)
    XCTAssertTrue(preflight.sessionsDirectoryExists)
    XCTAssertFalse(preflight.currentApplicationSupportCandidateIsOccupied)
    XCTAssertFalse(preflight.legacyApplicationSupportCandidateIsOccupied)
    XCTAssertTrue(preflight.migrationWouldBeSafe)
    XCTAssertEqual(preflight.kind, .migrationReady)
    XCTAssertEqual(preflight.label, "Preflight clear")
    XCTAssertTrue(preflight.detail.contains("candidate Application Support paths are empty"))
    XCTAssertTrue(preflight.recommendation.contains("without path conflicts"))
  }

  func testMissingAndIncompleteRepoLocalStorageBlockPreflight() throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()

    let missingPreflight = CompassWorkspaceStoragePreflight(
      repoURL: missingRepoURL,
      applicationSupportRoots: missingRoots
    )

    XCTAssertEqual(missingPreflight.repoLocalReadiness, .missingWorkspace)
    XCTAssertEqual(missingPreflight.kind, .repoLocalMissing)
    XCTAssertFalse(missingPreflight.migrationWouldBeSafe)
    XCTAssertEqual(
      missingPreflight.missingCoreFiles,
      CompassWorkspaceStorageAssessment.CoreFile.allCases
    )
    XCTAssertFalse(missingPreflight.sessionsDirectoryExists)
    XCTAssertTrue(missingPreflight.recommendation.contains("repo-local repair"))

    let incompleteRepoURL = try makeTemporaryGitRepository()
    let incompleteRoots = try makeApplicationSupportRoots()
    let incompleteWorkspace = CompassWorkspace(repoURL: incompleteRepoURL)
    try createDirectory(incompleteWorkspace.compassURL)
    try write("[]\n", to: incompleteWorkspace.sessionsRecordURL)

    let incompletePreflight = CompassWorkspaceStoragePreflight(
      repoURL: incompleteRepoURL,
      applicationSupportRoots: incompleteRoots
    )

    XCTAssertEqual(incompletePreflight.repoLocalReadiness, .incompleteWorkspace)
    XCTAssertEqual(incompletePreflight.kind, .repoLocalIncomplete)
    XCTAssertFalse(incompletePreflight.migrationWouldBeSafe)
    XCTAssertTrue(incompletePreflight.detail.contains("state.json"))
    XCTAssertTrue(incompletePreflight.detail.contains("drafts.md"))
    XCTAssertTrue(incompletePreflight.detail.contains("lessons.md"))
    XCTAssertTrue(incompletePreflight.detail.contains("COMPASS.md"))
    XCTAssertTrue(incompletePreflight.detail.contains("sessions/"))
    XCTAssertFalse(incompletePreflight.detail.contains("sessions.json"))
  }

  func testCurrentAndLegacyApplicationSupportConflictsAreInspectOnly() throws {
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
    try write(
      "legacy\n",
      to: seedPreflight.legacyApplicationSupportCandidateURL.appending(path: "state.json"))
    let repoEntriesBefore = try entries(in: repoURL)
    let currentEntriesBefore = try entries(in: seedPreflight.currentApplicationSupportCandidateURL)
    let legacyEntriesBefore = try entries(in: seedPreflight.legacyApplicationSupportCandidateURL)

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    XCTAssertEqual(preflight.repoLocalReadiness, .ready)
    XCTAssertEqual(preflight.kind, .applicationSupportConflict)
    XCTAssertFalse(preflight.migrationWouldBeSafe)
    XCTAssertTrue(preflight.currentApplicationSupportCandidateIsOccupied)
    XCTAssertTrue(preflight.legacyApplicationSupportCandidateIsOccupied)
    XCTAssertEqual(preflight.occupiedApplicationSupportCandidates.map(\.kind), [.current, .legacy])
    XCTAssertTrue(preflight.detail.contains("Inspect-only conflict"))
    XCTAssertTrue(preflight.recommendation.contains("Compass remains on repo-local .compass/"))
    XCTAssertEqual(try entries(in: repoURL), repoEntriesBefore)
    XCTAssertEqual(
      try entries(in: seedPreflight.currentApplicationSupportCandidateURL), currentEntriesBefore)
    XCTAssertEqual(
      try entries(in: seedPreflight.legacyApplicationSupportCandidateURL), legacyEntriesBefore)
    XCTAssertEqual(
      try String(
        contentsOf: seedPreflight.currentApplicationSupportCandidateURL.appending(
          path: "state.json"), encoding: .utf8),
      "current\n"
    )
    XCTAssertEqual(
      try String(
        contentsOf: seedPreflight.legacyApplicationSupportCandidateURL.appending(
          path: "state.json"), encoding: .utf8),
      "legacy\n"
    )
  }

  func testInjectedApplicationSupportWorkspaceDoesNotSatisfyRepoLocalPreflight() throws {
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

    XCTAssertEqual(preflight.repoLocalReadiness, .missingWorkspace)
    XCTAssertEqual(preflight.kind, .repoLocalMissing)
    XCTAssertFalse(preflight.migrationWouldBeSafe)
    XCTAssertTrue(preflight.currentApplicationSupportCandidateIsOccupied)
    XCTAssertTrue(FileManager.default.fileExists(atPath: externalWorkspace.compassURL.path))
    XCTAssertEqual(
      try String(contentsOf: externalWorkspace.draftsURL, encoding: .utf8), "external draft\n")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
  }

  func testPreflightDisplayTextAndIdentifiersStayBounded() throws {
    let longName = "Storage Migration Project " + String(repeating: "Segment ", count: 18)
    let repoURL = try makeTemporaryGitRepository(name: longName)
    let roots = KnownProjectStore.ApplicationSupportRoots(
      current: URL(
        fileURLWithPath: "/tmp/" + String(repeating: "Current Support Root/", count: 12)),
      legacy: URL(fileURLWithPath: "/tmp/" + String(repeating: "Legacy Support Root/", count: 12))
    )

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    XCTAssertLessThanOrEqual(
      preflight.projectStorageIdentifier.count,
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    XCTAssertLessThanOrEqual(preflight.label.count, CompassWorkspaceStoragePreflight.labelLimit)
    XCTAssertLessThanOrEqual(preflight.detail.count, CompassWorkspaceStoragePreflight.detailLimit)
    XCTAssertLessThanOrEqual(
      preflight.recommendation.count,
      CompassWorkspaceStoragePreflight.recommendationLimit
    )
    XCTAssertFalse(preflight.label.isEmpty)
    XCTAssertFalse(preflight.detail.isEmpty)
    XCTAssertFalse(preflight.recommendation.isEmpty)
  }

  func testProjectStorageIdentifierAndCandidateURLsAreStable() throws {
    let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
    let repoURL = try makeTemporaryGitRepository(
      name: longName.replacingOccurrences(of: "/", with: "-"))
    let roots = try makeApplicationSupportRoots()

    let first = CompassWorkspaceStoragePreflight(repoURL: repoURL, applicationSupportRoots: roots)
    let second = CompassWorkspaceStoragePreflight(repoURL: repoURL, applicationSupportRoots: roots)

    XCTAssertEqual(first.projectStorageIdentifier, second.projectStorageIdentifier)
    XCTAssertEqual(
      first.currentApplicationSupportCandidateURL, second.currentApplicationSupportCandidateURL)
    XCTAssertEqual(
      first.legacyApplicationSupportCandidateURL, second.legacyApplicationSupportCandidateURL)
    XCTAssertTrue(isSafeIdentifier(first.projectStorageIdentifier), first.projectStorageIdentifier)
    XCTAssertLessThanOrEqual(
      first.projectStorageIdentifier.count,
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    XCTAssertEqual(
      first.currentApplicationSupportCandidateURL.lastPathComponent, first.projectStorageIdentifier)
    XCTAssertEqual(
      first.legacyApplicationSupportCandidateURL.lastPathComponent, first.projectStorageIdentifier)
  }

  func testPreflightDoesNotCreateRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    let preflight = CompassWorkspaceStoragePreflight(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    XCTAssertEqual(try entries(in: repoURL), repoEntriesBefore)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: roots.current.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: roots.legacy.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: preflight.currentApplicationSupportCandidateURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: preflight.legacyApplicationSupportCandidateURL.path))
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
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
      legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
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
