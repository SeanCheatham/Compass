import Foundation
import XCTest

@testable import Compass

@MainActor
final class CompassWorkspaceStorageMigrationActionTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testAvailablePlanPreparesConfirmationWithoutMigrating() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )

    let plan = project.storageMigrationPlan()
    XCTAssertTrue(plan.isAvailable)

    project.prepareStorageMigrationConfirmation()

    let confirmation = try XCTUnwrap(project.storageMigrationConfirmation)
    XCTAssertEqual(project.storageMigrationState.phase, .awaitingConfirmation)
    XCTAssertTrue(confirmation.message.contains("Source: \(plan.sourceCompassURL.path)"))
    XCTAssertTrue(confirmation.message.contains("Destination:"))
    XCTAssertTrue(confirmation.message.contains(plan.destinationURL.lastPathComponent))
    XCTAssertTrue(confirmation.message.contains("Manifest:"))
    XCTAssertTrue(confirmation.message.contains(plan.manifestURL.lastPathComponent))
    XCTAssertTrue(confirmation.message.contains("repo-local .compass/ remains the source of truth"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: plan.destinationURL.path))
  }

  func testConfirmingAvailablePlanPreparesCandidateStorage() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try write("queued draft\n", to: workspace.draftsURL)
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )

    project.prepareStorageMigrationConfirmation()
    let confirmation = try XCTUnwrap(project.storageMigrationConfirmation)
    await project.confirmStorageMigration(confirmation)

    let plan = confirmation.plan
    XCTAssertEqual(project.storageMigrationState.phase, .succeeded)
    XCTAssertTrue(FileManager.default.fileExists(atPath: plan.destinationURL.path))
    XCTAssertEqual(try read(plan.destinationURL.appending(path: "drafts.md")), "queued draft\n")
    XCTAssertTrue(FileManager.default.fileExists(atPath: plan.manifestURL.path))
    XCTAssertEqual(try decodeManifest(at: plan.manifestURL).sourcePath, workspace.compassURL.path)
    XCTAssertEqual(try read(workspace.draftsURL), "queued draft\n")
    XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.compassURL.path))
  }

  func testInjectedMigrationFailureShowsBoundedFailureFeedback() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    var callCount = 0
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots,
      storageMigrationAction: { _ in
        callCount += 1
        throw InjectedMigrationActionError.failed(String(repeating: "failure-detail-", count: 80))
      }
    )

    project.prepareStorageMigrationConfirmation()
    let confirmation = try XCTUnwrap(project.storageMigrationConfirmation)
    await project.confirmStorageMigration(confirmation)

    XCTAssertEqual(callCount, 1)
    XCTAssertEqual(project.storageMigrationState.phase, .failed)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.label.count, CompassProjectStorageMigrationState.labelLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.detail.count, CompassProjectStorageMigrationState.detailLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.helpText.count, CompassProjectStorageMigrationState.helpLimit)
    XCTAssertEqual(project.errorMessage, project.storageMigrationState.detail)
    XCTAssertFalse(FileManager.default.fileExists(atPath: confirmation.plan.destinationURL.path))
  }

  func testUnavailableAndRunningPlansBlockWithoutCallingMigrator() async throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()
    let missingProject = CompassProject(
      repoURL: missingRepoURL,
      storageApplicationSupportRoots: missingRoots,
      storageMigrationAction: { _ in
        XCTFail("Unavailable migration should not call the migrator.")
        throw InjectedMigrationActionError.failed("unexpected")
      }
    )

    missingProject.prepareStorageMigrationConfirmation()

    XCTAssertNil(missingProject.storageMigrationConfirmation)
    XCTAssertEqual(missingProject.storageMigrationState.phase, .blocked)
    XCTAssertEqual(missingProject.storageMigrationPlan().kind, .repoLocalMissing)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: missingProject.storageMigrationPlan().destinationURL.path))

    let runningRepoURL = try makeTemporaryGitRepository()
    let runningRoots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: runningRepoURL).initialize()
    var callCount = 0
    let runningProject = CompassProject(
      repoURL: runningRepoURL,
      storageApplicationSupportRoots: runningRoots,
      storageMigrationAction: { _ in
        callCount += 1
        throw InjectedMigrationActionError.failed("unexpected")
      }
    )
    runningProject.isRunning = true

    runningProject.prepareStorageMigrationConfirmation()

    XCTAssertNil(runningProject.storageMigrationConfirmation)
    XCTAssertEqual(runningProject.storageMigrationState.phase, .blocked)
    XCTAssertEqual(callCount, 0)

    let availableConfirmation = CompassWorkspaceStorageMigrationConfirmation(
      plan: runningProject.storageMigrationPlan()
    )
    await runningProject.confirmStorageMigration(availableConfirmation)
    XCTAssertEqual(callCount, 0)
  }

  func testConfirmationAndStateTextStayBounded() async throws {
    let longName = "Storage Migration Action " + String(repeating: "Segment ", count: 24)
    let repoURL = try makeTemporaryGitRepository(name: longName)
    let roots = try makeApplicationSupportRoots(
      prefix: "CompassWorkspaceStorageMigrationActionSupport"
        + String(repeating: "LongSegment", count: 12)
    )
    try CompassWorkspace(repoURL: repoURL).initialize()
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots,
      storageMigrationAction: { _ in
        throw InjectedMigrationActionError.failed(
          String(repeating: "long-user-facing-error-", count: 70))
      }
    )

    project.prepareStorageMigrationConfirmation()
    let confirmation = try XCTUnwrap(project.storageMigrationConfirmation)

    XCTAssertLessThanOrEqual(
      confirmation.title.count, CompassWorkspaceStorageMigrationConfirmation.titleLimit)
    XCTAssertLessThanOrEqual(
      confirmation.message.count, CompassWorkspaceStorageMigrationConfirmation.messageLimit)
    XCTAssertLessThanOrEqual(
      confirmation.confirmLabel.count, CompassWorkspaceStorageMigrationConfirmation.actionLabelLimit
    )
    XCTAssertLessThanOrEqual(
      confirmation.cancelLabel.count, CompassWorkspaceStorageMigrationConfirmation.actionLabelLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.label.count, CompassProjectStorageMigrationState.labelLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.detail.count, CompassProjectStorageMigrationState.detailLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.helpText.count, CompassProjectStorageMigrationState.helpLimit)

    await project.confirmStorageMigration(confirmation)

    XCTAssertEqual(project.storageMigrationState.phase, .failed)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.label.count, CompassProjectStorageMigrationState.labelLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.detail.count, CompassProjectStorageMigrationState.detailLimit)
    XCTAssertLessThanOrEqual(
      project.storageMigrationState.helpText.count, CompassProjectStorageMigrationState.helpLimit)
  }

  func testActionPreservesRepoLocalStorageAndDoesNotSwitchActiveStorage() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try write("source state\n", to: workspace.stateURL)
    try write("source lesson\n", to: workspace.lessonsURL)
    try write("source artifact\n", to: workspace.sessionsURL.appending(path: "1-transcript.txt"))
    let sourceEntriesBefore = try recursiveFilePaths(in: workspace.compassURL)
    var capturedResult: CompassWorkspaceStorageMigrationResult?
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots,
      storageMigrationAction: { plan in
        let result = try CompassWorkspaceStorageMigrator(
          makeTransactionIdentifier: { "action-source-preserved" }
        )
        .migrate(plan: plan)
        capturedResult = result
        return result
      }
    )

    project.prepareStorageMigrationConfirmation()
    let confirmation = try XCTUnwrap(project.storageMigrationConfirmation)
    await project.confirmStorageMigration(confirmation)

    let result = try XCTUnwrap(capturedResult)
    XCTAssertTrue(result.repoLocalSourcePreserved)
    XCTAssertFalse(result.activeStorageDidChange)
    XCTAssertEqual(project.compassPath, workspace.compassURL.path)
    XCTAssertEqual(try read(workspace.stateURL), "source state\n")
    XCTAssertEqual(try read(workspace.lessonsURL), "source lesson\n")
    XCTAssertEqual(
      try read(workspace.sessionsURL.appending(path: "1-transcript.txt")), "source artifact\n")
    XCTAssertEqual(try recursiveFilePaths(in: workspace.compassURL), sourceEntriesBefore)
    XCTAssertTrue(FileManager.default.fileExists(atPath: confirmation.plan.destinationURL.path))
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

  private func makeApplicationSupportRoots(
    prefix: String = "CompassWorkspaceStorageMigrationActionSupport"
  ) throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = try makeTemporaryDirectory(prefix: prefix)
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(
    prefix: String = "CompassWorkspaceStorageMigrationActionTests"
  ) throws -> URL {
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
      paths.append(childURL.path.replacingOccurrences(of: url.path + "/", with: ""))
    }
    return paths.sorted()
  }
}

private enum InjectedMigrationActionError: LocalizedError, Equatable {
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .failed(let message):
      return message
    }
  }
}
