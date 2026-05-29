import Foundation
import Testing

@testable import Compass

final class CompassWorkspaceStorageMigrationTests {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testSuccessfulMigrationCopiesCoreAndSessionArtifactsAndWritesManifest() throws {
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

    try #require(plan.isAvailable)

    let result = try CompassWorkspaceStorageMigrator(
      now: { Date(timeIntervalSince1970: 0) },
      makeTransactionIdentifier: { "success" }
    )
    .migrate(plan: plan)

    try #require(FileManager.default.fileExists(atPath: plan.destinationURL.path))
    try #require(try read(plan.destinationURL.appending(path: "drafts.md")) == "draft entry\n")
    try #require(try read(plan.destinationURL.appending(path: "lessons.md")) == "lesson entry\n")
    try #require(try read(plan.destinationURL.appending(path: "COMPASS.md")) == "vision entry\n")
    try #require(
      try read(plan.destinationURL.appending(path: "sessions.json")) == "[{\"session\":1}]\n")
    try #require(
      try read(
        plan.destinationURL.appending(path: "sessions").appending(
          path: artifactURL.lastPathComponent)) ==
      "artifact body\n"
    )

    let manifest = try decodeManifest(at: plan.manifestURL)
    try #require(manifest.repoPath == repoURL.path)
    try #require(manifest.storageIdentifier == plan.projectStorageIdentifier)
    try #require(manifest.sourcePath == workspace.compassURL.path)
    try #require(manifest.destinationPath == plan.destinationURL.path)
    try #require(manifest.copiedFileCount == 6)
    try #require(manifest.migratedAt == "1970-01-01T00:00:00Z")

    try #require(result.manifest == manifest)
    try #require(result.copiedFileCount == 6)
    try #require(result.repoLocalSourcePreserved)
    try #require(!result.activeStorageDidChange)
    try #require(
      !FileManager.default.fileExists(
        atPath: plan.stagingParentURL
          .appending(path: ".\(plan.projectStorageIdentifier)-migration-success")
          .path
      )
    )
  }

  @Test func testMissingAndIncompleteRepoLocalStorageBlockMigration() throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()
    let missingPlan = makeMigrationPlan(repoURL: missingRepoURL, roots: missingRoots)

    try #require(!missingPlan.isAvailable)
    try #require(missingPlan.kind == .repoLocalMissing)
    do {
      try CompassWorkspaceStorageMigrator().migrate(plan: missingPlan)
      try #require(false)
    } catch {
      try #require(
        error as? CompassWorkspaceStorageMigrationError ==
        .unavailable(kind: .repoLocalMissing, detail: missingPlan.detail)
      )
    }
    try #require(!FileManager.default.fileExists(atPath: missingPlan.destinationURL.path))

    let incompleteRepoURL = try makeTemporaryGitRepository()
    let incompleteRoots = try makeApplicationSupportRoots()
    let incompleteWorkspace = CompassWorkspace(repoURL: incompleteRepoURL)
    try createDirectory(incompleteWorkspace.compassURL)
    try write("[]\n", to: incompleteWorkspace.sessionsRecordURL)
    let incompletePlan = makeMigrationPlan(repoURL: incompleteRepoURL, roots: incompleteRoots)

    try #require(!incompletePlan.isAvailable)
    try #require(incompletePlan.kind == .repoLocalIncomplete)
    try #require(incompletePlan.detail.contains("state.json"))
    do {
      try CompassWorkspaceStorageMigrator().migrate(plan: incompletePlan)
      try #require(false)
    } catch {
      try #require(
        error as? CompassWorkspaceStorageMigrationError ==
        .unavailable(kind: .repoLocalIncomplete, detail: incompletePlan.detail)
      )
    }
    try #require(!FileManager.default.fileExists(atPath: incompletePlan.destinationURL.path))
  }

  @Test func testOccupiedApplicationSupportCandidateBlocksMigration() throws {
    let currentRepoURL = try makeTemporaryGitRepository()
    let currentRoots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: currentRepoURL).initialize()
    let currentSeedPlan = makeMigrationPlan(repoURL: currentRepoURL, roots: currentRoots)
    try write("occupied\n", to: currentSeedPlan.destinationURL.appending(path: "state.json"))

    let currentPlan = makeMigrationPlan(repoURL: currentRepoURL, roots: currentRoots)

    try #require(!currentPlan.isAvailable)
    try #require(currentPlan.kind == .applicationSupportOccupied)
    try #require(currentPlan.detail.contains("occupied"))
    do {
      try CompassWorkspaceStorageMigrator().migrate(plan: currentPlan)
      try #require(false)
    } catch {
      try #require(
        error as? CompassWorkspaceStorageMigrationError ==
        .unavailable(kind: .applicationSupportOccupied, detail: currentPlan.detail)
      )
    }
  }

  @Test func testMigrationPlanKeepsRepoLocalSourceWhenExternalStorageIsInjected() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
    try repoLocalWorkspace.initialize()
    try repoLocalWorkspace.writeLessons("repo-local lesson\n")

    let seedPlan = makeMigrationPlan(repoURL: repoURL, roots: roots)
    let externalWorkspace = CompassWorkspace(
      repoURL: repoURL, storageRootURL: seedPlan.destinationURL)
    try externalWorkspace.initialize()
    try externalWorkspace.writeLessons("external lesson\n")

    let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)

    try #require(plan.sourceCompassURL == repoLocalWorkspace.compassURL)
    try #require(plan.kind == .applicationSupportOccupied)
    try #require(!plan.isAvailable)
    try #require(try read(repoLocalWorkspace.lessonsURL) == "repo-local lesson\n")
    try #require(try read(externalWorkspace.lessonsURL) == "external lesson\n")
    try #require(FileManager.default.fileExists(atPath: repoLocalWorkspace.compassURL.path))
    try #require(FileManager.default.fileExists(atPath: externalWorkspace.compassURL.path))
  }

  @Test func testRollbackCleansStagingAfterInjectedCopyFailureAndPreservesSource() throws {
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

    do {
      try migrator.migrate(plan: plan)
      try #require(false)
    } catch {
      try #require(error as? InjectedMigrationError == .copy)
    }
    try #require(!FileManager.default.fileExists(atPath: expectedStagingURL.path))
    try #require(!FileManager.default.fileExists(atPath: plan.destinationURL.path))
    try #require(try read(workspace.draftsURL) == "source draft\n")
    try #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
  }

  @Test func testRollbackCleansStagingAndPartialDestinationAfterInjectedPromoteFailure() throws {
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

    do {
      try migrator.migrate(plan: plan)
      try #require(false)
    } catch {
      try #require(error as? InjectedMigrationError == .promote)
    }
    try #require(!FileManager.default.fileExists(atPath: expectedStagingURL.path))
    try #require(!FileManager.default.fileExists(atPath: plan.destinationURL.path))
    try #require(try read(workspace.lessonsURL) == "source lesson\n")
    try #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
  }

  @Test func testMigrationPreservesRepoLocalStorageAsActiveSourceOfTruth() throws {
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

    try #require(result.repoLocalSourcePreserved)
    try #require(!result.activeStorageDidChange)
    try #require(try read(workspace.stateURL) == "source state\n")
    try #require(
      try read(workspace.sessionsURL.appending(path: "2-transcript.txt")) == "source session\n")
    try #require(try recursiveFilePaths(in: workspace.compassURL) == sourceEntriesBefore)
    try #require(FileManager.default.fileExists(atPath: plan.destinationURL.path))
  }

  @Test func testMigrationManifestPlanAndResultTextStayBounded() throws {
    let longText = String(repeating: "very-long-segment-", count: 80)
    let manifest = CompassWorkspaceStorageMigrationManifest(
      repoPath: "/tmp/\(longText)",
      storageIdentifier: longText,
      sourcePath: "/tmp/source/\(longText)",
      destinationPath: "/tmp/destination/\(longText)",
      copiedFileCount: -4,
      migratedAt: longText
    )

    try #require(
      manifest.repoPath.count <= CompassWorkspaceStorageMigrationManifest.pathLimit)
    try #require(
      manifest.storageIdentifier.count <= CompassWorkspaceStorageMigrationManifest.identifierLimit)
    try #require(
      manifest.sourcePath.count <= CompassWorkspaceStorageMigrationManifest.pathLimit)
    try #require(
      manifest.destinationPath.count <= CompassWorkspaceStorageMigrationManifest.pathLimit)
    try #require(
      manifest.migratedAt.count <= CompassWorkspaceStorageMigrationManifest.timestampLimit)
    try #require(manifest.copiedFileCount == 0)

    let repoURL = try makeTemporaryGitRepository(
      name: "Bounded Storage Migration " + String(repeating: "Segment ", count: 12)
    )
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    let plan = makeMigrationPlan(repoURL: repoURL, roots: roots)

    try #require(plan.label.count <= CompassWorkspaceStorageMigrationPlan.labelLimit)
    try #require(plan.detail.count <= CompassWorkspaceStorageMigrationPlan.detailLimit)
    try #require(
      plan.recommendation.count <= CompassWorkspaceStorageMigrationPlan.recommendationLimit)

    let result = try CompassWorkspaceStorageMigrator(
      makeTransactionIdentifier: { "bounded" }
    )
    .migrate(plan: plan)

    try #require(
      result.summary.count <= CompassWorkspaceStorageMigrationResult.summaryLimit)
    try #require(
      result.detail.count <= CompassWorkspaceStorageMigrationResult.detailLimit)
  }

  private func makeMigrationPlan(
    repoURL: URL,
    roots: KnownProjectStore.ApplicationSupportRoots
  ) -> CompassWorkspaceStorageMigrationPlan {
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
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
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageMigrationTests")
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

  private func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  private func decodeManifest(at url: URL) throws -> CompassWorkspaceStorageMigrationManifest {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CompassWorkspaceStorageMigrationManifest.self, from: data)
  }

  private func recursiveFilePaths(in url: URL) throws -> [String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.isDirectoryKey])
    else {
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
