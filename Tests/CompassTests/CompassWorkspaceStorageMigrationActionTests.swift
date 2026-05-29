import Foundation
import Testing

@testable import Compass

@MainActor
final class CompassWorkspaceStorageMigrationActionTests {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testAvailablePlanPreparesConfirmationWithoutMigrating() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )

    let plan = project.storageMigrationPlan()
    try #require(plan.isAvailable)

    project.prepareStorageMigrationConfirmation()

    let confirmation = try #require(project.storageMigrationConfirmation)
    try #require(project.storageMigrationState.phase == .awaitingConfirmation)
    try #require(confirmation.message.contains("Source: \(plan.sourceCompassURL.path)"))
    try #require(confirmation.message.contains("Destination:"))
    try #require(confirmation.message.contains(plan.destinationURL.lastPathComponent))
    try #require(confirmation.message.contains("Manifest:"))
    try #require(confirmation.message.contains(plan.manifestURL.lastPathComponent))
    try #require(confirmation.message.contains("repo-local .compass/ remains the source of truth"))
    try #require(!FileManager.default.fileExists(atPath: plan.destinationURL.path))
  }

  @Test func testConfirmingAvailablePlanPreparesCandidateStorage() async throws {
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
    let confirmation = try #require(project.storageMigrationConfirmation)
    await project.confirmStorageMigration(confirmation)

    let plan = confirmation.plan
    try #require(project.storageMigrationState.phase == .succeeded)
    try #require(FileManager.default.fileExists(atPath: plan.destinationURL.path))
    try #require(try read(plan.destinationURL.appending(path: "drafts.md")) == "queued draft\n")
    try #require(FileManager.default.fileExists(atPath: plan.manifestURL.path))
    try #require(try decodeManifest(at: plan.manifestURL).sourcePath == workspace.compassURL.path)
    try #require(try read(workspace.draftsURL) == "queued draft\n")
    try #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
  }

  @Test func testInjectedMigrationFailureShowsBoundedFailureFeedback() async throws {
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
    let confirmation = try #require(project.storageMigrationConfirmation)
    await project.confirmStorageMigration(confirmation)

    try #require(callCount == 1)
    try #require(project.storageMigrationState.phase == .failed)
    try #require(
      project.storageMigrationState.label.count <=
      CompassProjectStorageMigrationState.labelLimit)
    try #require(
      project.storageMigrationState.detail.count <=
      CompassProjectStorageMigrationState.detailLimit)
    try #require(
      project.storageMigrationState.helpText.count <=
      CompassProjectStorageMigrationState.helpLimit)
    try #require(project.errorMessage == project.storageMigrationState.detail)
    try #require(!FileManager.default.fileExists(atPath: confirmation.plan.destinationURL.path))
  }

  @Test func testUnavailableAndRunningPlansBlockWithoutCallingMigrator() async throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()
    let missingProject = CompassProject(
      repoURL: missingRepoURL,
      storageApplicationSupportRoots: missingRoots,
      storageMigrationAction: { _ in
        #expect(Bool(false), "Unavailable migration should not call the migrator.")
        throw InjectedMigrationActionError.failed("unexpected")
      }
    )

    missingProject.prepareStorageMigrationConfirmation()

    try #require(missingProject.storageMigrationConfirmation == nil)
    try #require(missingProject.storageMigrationState.phase == .blocked)
    try #require(missingProject.storageMigrationPlan().kind == .repoLocalMissing)
    try #require(
      !FileManager.default.fileExists(
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

    try #require(runningProject.storageMigrationConfirmation == nil)
    try #require(runningProject.storageMigrationState.phase == .blocked)
    try #require(callCount == 0)

    let availableConfirmation = CompassWorkspaceStorageMigrationConfirmation(
      plan: runningProject.storageMigrationPlan()
    )
    await runningProject.confirmStorageMigration(availableConfirmation)
    try #require(callCount == 0)
  }

  @Test func testConfirmationAndStateTextStayBounded() async throws {
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
    let confirmation = try #require(project.storageMigrationConfirmation)

    try #require(
      confirmation.title.count <= CompassWorkspaceStorageMigrationConfirmation.titleLimit)
    try #require(
      confirmation.message.count <= CompassWorkspaceStorageMigrationConfirmation.messageLimit)
    try #require(
      confirmation.confirmLabel.count <=
      CompassWorkspaceStorageMigrationConfirmation.actionLabelLimit
    )
    try #require(
      confirmation.cancelLabel.count <=
      CompassWorkspaceStorageMigrationConfirmation.actionLabelLimit)
    try #require(
      project.storageMigrationState.label.count <=
      CompassProjectStorageMigrationState.labelLimit)
    try #require(
      project.storageMigrationState.detail.count <=
      CompassProjectStorageMigrationState.detailLimit)
    try #require(
      project.storageMigrationState.helpText.count <=
      CompassProjectStorageMigrationState.helpLimit)

    await project.confirmStorageMigration(confirmation)

    try #require(project.storageMigrationState.phase == .failed)
    try #require(
      project.storageMigrationState.label.count <=
      CompassProjectStorageMigrationState.labelLimit)
    try #require(
      project.storageMigrationState.detail.count <=
      CompassProjectStorageMigrationState.detailLimit)
    try #require(
      project.storageMigrationState.helpText.count <=
      CompassProjectStorageMigrationState.helpLimit)
  }

  @Test func testActionPreservesRepoLocalStorageAndDoesNotSwitchActiveStorage() async throws {
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
    let confirmation = try #require(project.storageMigrationConfirmation)
    await project.confirmStorageMigration(confirmation)

    let result = try #require(capturedResult)
    try #require(result.repoLocalSourcePreserved)
    try #require(!result.activeStorageDidChange)
    try #require(project.compassPath == workspace.compassURL.path)
    try #require(try read(workspace.stateURL) == "source state\n")
    try #require(try read(workspace.lessonsURL) == "source lesson\n")
    try #require(
      try read(workspace.sessionsURL.appending(path: "1-transcript.txt")) == "source artifact\n")
    try #require(try recursiveFilePaths(in: workspace.compassURL) == sourceEntriesBefore)
    try #require(FileManager.default.fileExists(atPath: confirmation.plan.destinationURL.path))
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
