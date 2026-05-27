import Foundation
import Testing

@testable import Compass

@MainActor
struct CompassProjectActiveStorageTests : ~Copyable {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func resolverDefaultsToRepoLocalStorage() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )
    let standardizedRepoURL = repoURL.standardizedFileURL
    let repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: standardizedRepoURL)

    #require(resolver.activeStorage == .repoLocal)
    #require(resolver.repoURL == standardizedRepoURL)
    #require(resolver.storageRootURL == repoLocalURL)
    #require(resolver.workspace.repoURL == standardizedRepoURL)
    #require(resolver.workspace.compassURL == repoLocalURL)
  }

  @Test func resolverMapsApplicationSupportStorageToCurrentCandidate() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    let expectedURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
      for: repoURL.standardizedFileURL,
      applicationSupportRoots: roots
    )

    #require(resolver.storageRootURL == expectedURL)
    #require(resolver.workspace.repoURL == repoURL.standardizedFileURL)
    #require(resolver.workspace.compassURL == expectedURL)
    #require(!FileManager.default.fileExists(atPath: expectedURL.path))
    #require(
      !FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
  }

  @Test func projectDefaultsToRepoLocalStorage() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )
    let repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: repoURL.standardizedFileURL)
    let applicationSupportURL =
      CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
        for: repoURL.standardizedFileURL,
        applicationSupportRoots: roots
      )

    #require(project.activeStorage == .repoLocal)
    #require(project.compassPath == repoLocalURL.path)

    await project.initializeWorkspace()

    #require(FileManager.default.fileExists(atPath: repoLocalURL.path))
    #require(!FileManager.default.fileExists(atPath: applicationSupportURL.path))
  }

  @Test func applicationSupportActiveStorageRoundTripsCompassFilesWithoutRepoLocalCompass()
    async throws
  {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let project = CompassProject(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    let workspace = resolver.workspace
    let state = PlanState(
      completed: ["application support"],
      immediate: PlanNext(plan: "Honor active storage", verify: "swift test"),
      midTerm: "persist",
      longTerm: "factory"
    )
    let records = [
      SessionRecord(
        session: 7,
        startedAt: 10,
        endedAt: 20,
        plan: "Plan",
        verify: "true",
        beforeSha: nil,
        afterSha: nil,
        commits: [],
        status: .succeeded,
        notes: ["done"],
        verifyOutput: nil,
        feedback: "ok"
      )
    ]

    #require(project.compassPath == workspace.compassURL.path)

    await project.initializeWorkspace()
    try workspace.writeState(state)
    try workspace.writeDrafts("draft from support\n")
    try workspace.writeLessons("- lesson from support\n")
    try workspace.writeVision("vision from support\n")
    try workspace.writeSessions(records)

    await project.refresh()

    #require(project.state == state)
    #require(project.drafts == "draft from support\n")
    #require(project.lessons == "- lesson from support\n")
    #require(project.vision == "vision from support\n")
    #require(project.sessions == records)
    #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))

    project.drafts = "updated support draft\n"
    await project.saveDrafts()
    project.lessons = "- updated support lesson\n"
    await project.saveLessons()

    #require(workspace.readDrafts() == "updated support draft\n")
    #require(workspace.readLessons() == "- updated support lesson\n")
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
  }

  @Test func
    testApplicationSupportActiveStorageReadsSupportSessionsWhenRepoLocalSessionsMissing()
    async throws
  {
    let repoURL = try await makeInitializedGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    let supportState = PlanState(
      completed: ["scan support sessions"],
      immediate: PlanNext(plan: "Keep Plan state stable", verify: "swift test"),
      midTerm: "support activity",
      longTerm: "factory"
    )
    let supportSessions = [
      makeActivitySession(21, status: .failed, endedAt: 21_000, commits: 1),
      makeActivitySession(22, status: .succeeded, endedAt: 22_000, commits: 2),
      makeActivitySession(23, status: .succeeded, endedAt: 23_000, commits: 3),
    ]
    let project = CompassProject(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )

    try workspace.initialize()
    try workspace.writeState(supportState)
    try workspace.writeSessions(supportSessions)
    try write("pending repo worktree\n", to: repoURL.appending(path: "pending.txt"))
    project.state = supportState

    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))

    await project.refresh()

    let sourceSnapshot = project.activitySourceSnapshot

    #require(project.sessions == supportSessions)
    #require(sourceSnapshot.activeStorage == .applicationSupport)
    #require(sourceSnapshot.storageRootURL == workspace.compassURL.standardizedFileURL)
    #require(
      sourceSnapshot.sessionsRecordURL == workspace.sessionsRecordURL.standardizedFileURL)
    #require(sourceSnapshot.sourceAvailability == .available)
    #require(sourceSnapshot.repoLocalSessionsState == .ignoredMissing)
    #require(sourceSnapshot.ignoresRepoLocalSessions)
    #require(project.state == supportState)
    #require(project.activeStorage == .applicationSupport)
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
  }

  @Test func testApplicationSupportActiveStorageIgnoresStaleRepoLocalSessions()
    async throws
  {
    let repoURL = try await makeInitializedGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
    let supportSessions = [
      makeActivitySession(31, status: .failed, endedAt: 31_000, commits: 1),
      makeActivitySession(32, status: .succeeded, endedAt: 32_000, commits: 2),
    ]
    let staleRepoLocalSessions = [
      makeActivitySession(2, status: .failed, endedAt: 2_000, commits: 8),
      makeActivitySession(3, status: .failed, endedAt: 3_000, commits: 8),
    ]
    let project = CompassProject(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )

    try workspace.initialize()
    try workspace.writeSessions(supportSessions)
    try createDirectory(repoLocalWorkspace.compassURL)
    try repoLocalWorkspace.writeSessions(staleRepoLocalSessions)
    let staleRepoLocalText = try String(
      contentsOf: repoLocalWorkspace.sessionsRecordURL, encoding: .utf8)

    await project.refresh()

    let sourceSnapshot = project.activitySourceSnapshot

    #require(project.activeStorage == .applicationSupport)
    #require(project.sessions == supportSessions)
    #require(sourceSnapshot.sourceAvailability == .available)
    #require(sourceSnapshot.repoLocalSessionsState == .ignoredCompatible)
    #require(sourceSnapshot.ignoresRepoLocalSessions)
    #require(
      try String(contentsOf: repoLocalWorkspace.sessionsRecordURL, encoding: .utf8) ==
      staleRepoLocalText
    )
  }

  @Test func testActivitySourceDiagnosticsReportMissingActiveSupportRootReadOnly() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    let project = CompassProject(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )

    await project.refresh()

    let snapshot = project.activitySourceSnapshot
    let stateBeforeDiagnostics = project.state
    let activeStorageBeforeDiagnostics = project.activeStorage
    let sessionsBeforeDiagnostics = project.sessions

    #require(snapshot.activeStorage == .applicationSupport)
    #require(snapshot.storageRootURL == workspace.compassURL.standardizedFileURL)
    #require(snapshot.sessionsRecordURL == workspace.sessionsRecordURL.standardizedFileURL)
    #require(snapshot.sourceAvailability == .storageRootMissing)
    #require(snapshot.repoLocalSessionsState == .ignoredMissing)
    #require(project.state == stateBeforeDiagnostics)
    #require(project.activeStorage == activeStorageBeforeDiagnostics)
    #require(project.sessions == sessionsBeforeDiagnostics)
    #require(!FileManager.default.fileExists(atPath: workspace.compassURL.path))
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
  }

  @Test func testActivitySourceDiagnosticsReportNoRepositoryFallbackReadOnly() async throws {
    let parentURL = try makeTemporaryDirectory(prefix: "CompassProjectMissingRepoParent")
    let missingRepoURL = parentURL.appending(path: "MissingRepo", directoryHint: .isDirectory)
    let roots = try makeApplicationSupportRoots()
    let project = CompassProject(
      repoURL: missingRepoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )

    await project.refresh()

    let snapshot = project.activitySourceSnapshot
    let stateBeforeDiagnostics = project.state
    let activeStorageBeforeDiagnostics = project.activeStorage
    let sessionsBeforeDiagnostics = project.sessions

    #require(snapshot.activeStorage == .applicationSupport)
    #require(snapshot.storageRootURL == nil)
    #require(snapshot.sessionsRecordURL == nil)
    #require(snapshot.sourceAvailability == .noRepository)
    #require(snapshot.repoLocalSessionsState == .ignoredMissing)
    #require(project.state == stateBeforeDiagnostics)
    #require(project.activeStorage == activeStorageBeforeDiagnostics)
    #require(project.sessions == sessionsBeforeDiagnostics)
    #require(!FileManager.default.fileExists(atPath: missingRepoURL.path))
  }

  @Test func testInitializeWorkspaceRepairsActiveSupportStorageWithoutRepoLocalSideEffects() async throws
  {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let project = CompassProject(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)

    var display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )

    #require(display.supportRepairAction?.kind == .initializeApplicationSupportWorkspace)
    #require(display.supportRepairAction?.issueKind == .applicationSupportActiveMissing)
    #require(!FileManager.default.fileExists(atPath: workspace.compassURL.path))
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))

    await project.initializeWorkspace()

    #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.stateURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.lessonsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.visionURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsRecordURL.path))
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))

    display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    #require(display.supportRepairAction == nil)

    try write("- support lesson survives repair\n", to: workspace.lessonsURL)
    try FileManager.default.removeItem(at: workspace.draftsURL)
    try FileManager.default.removeItem(at: workspace.sessionsRecordURL)
    try FileManager.default.removeItem(at: workspace.sessionsURL)

    display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    #require(display.supportRepairAction?.kind == .initializeApplicationSupportWorkspace)
    #require(display.supportRepairAction?.issueKind == .applicationSupportActiveIncomplete)

    await project.initializeWorkspace()

    #require(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsRecordURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    #require(workspace.readLessons() == "- support lesson survives repair\n")
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
  }

  @Test func testActivationGatingRequiresIdleRepoLocalAndUsableCandidate() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )

    var plan = project.activeStorageActivationPlan()
    #require(!plan.isAvailable)
    #require(plan.kind == .candidateMissing)

    project.prepareActiveStorageActivationConfirmation()

    #require(project.activeStorageActivationConfirmation == nil)
    #require(project.activeStorageActivationState.phase == .blocked)

    let supportWorkspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    try supportWorkspace.initialize()

    plan = project.activeStorageActivationPlan()
    #require(plan.isAvailable)

    project.isRunning = true
    project.prepareActiveStorageActivationConfirmation()

    #require(project.activeStorageActivationConfirmation == nil)
    #require(project.activeStorageActivationState.phase == .blocked)

    project.isRunning = false
    project.activeStorage = .applicationSupport
    plan = project.activeStorageActivationPlan()

    #require(!plan.isAvailable)
    #require(plan.kind == .alreadyApplicationSupport)
  }

  @Test func testActivationPersistsThroughCallbackAndRefreshesSupportState() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    try workspace.initialize()
    let state = PlanState(
      completed: ["prepared"],
      immediate: PlanNext(plan: "Use support state", verify: "swift test"),
      midTerm: "storage",
      longTerm: "factory"
    )
    try workspace.writeState(state)
    try workspace.writeDrafts("support draft\n")
    try workspace.writeLessons("- support lesson\n")
    try workspace.writeVision("support vision\n")
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )

    project.prepareActiveStorageActivationConfirmation()
    let confirmation = #require(project.activeStorageActivationConfirmation)
    var persistedActiveStorage: [KnownProjectActiveStorage] = []

    await project.confirmActiveStorageActivation(confirmation) {
      persistedActiveStorage.append(project.activeStorage)
    }

    #require(persistedActiveStorage == [.applicationSupport])
    #require(project.activeStorage == .applicationSupport)
    #require(project.activeStorageActivationState.phase == .succeeded)
    #require(project.compassPath == workspace.compassURL.path)
    #require(project.state == state)
    #require(project.drafts == "support draft\n")
    #require(project.lessons == "- support lesson\n")
    #require(project.vision == "support vision\n")
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))

    project.drafts = "updated after activation\n"
    await project.saveDrafts()

    #require(workspace.readDrafts() == "updated after activation\n")
    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
  }

  @Test func testActivationRollsBackWhenPersistenceCallbackFails() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    try workspace.initialize()
    let project = CompassProject(
      repoURL: repoURL,
      storageApplicationSupportRoots: roots
    )

    project.prepareActiveStorageActivationConfirmation()
    let confirmation = #require(project.activeStorageActivationConfirmation)
    var persistedActiveStorage: [KnownProjectActiveStorage] = []

    await project.confirmActiveStorageActivation(confirmation) {
      persistedActiveStorage.append(project.activeStorage)
      throw ActiveStoragePersistenceTestError.failed("registry save failed")
    }

    #require(persistedActiveStorage == [.applicationSupport, .repoLocal])
    #require(project.activeStorage == .repoLocal)
    #require(project.activeStorageActivationState.phase == .failed)
    #require(project.errorMessage == project.activeStorageActivationState.detail)
    #require(
      project.activeStorageActivationState.label.count <= CompassProjectActiveStorageState.labelLimit)
    #require(
      project.activeStorageActivationState.detail.count <=
      CompassProjectActiveStorageState.detailLimit)
    #require(
      project.activeStorageActivationState.helpText.count <=
      CompassProjectActiveStorageState.helpLimit)
    #require(project.compassPath == workspace.repoLocalCompassURL.path)
  }

  @Test func testActivationReportsMissingAndInvalidCandidateFailuresWithoutSwitching() async throws {
    let missingRepoURL = try makeTemporaryGitRepository()
    let missingRoots = try makeApplicationSupportRoots()
    let missingProject = CompassProject(
      repoURL: missingRepoURL,
      storageApplicationSupportRoots: missingRoots
    )
    let missingConfirmation = CompassWorkspaceStorageActivationConfirmation(
      plan: missingProject.activeStorageActivationPlan()
    )
    var missingPersistCalls = 0

    await missingProject.confirmActiveStorageActivation(missingConfirmation) {
      missingPersistCalls += 1
    }

    #require(missingPersistCalls == 0)
    #require(missingProject.activeStorage == .repoLocal)
    #require(missingProject.activeStorageActivationState.phase == .failed)
    #require(missingProject.activeStorageActivationPlan().kind == .candidateMissing)

    let invalidRepoURL = try makeTemporaryGitRepository()
    let invalidRoots = try makeApplicationSupportRoots()
    let invalidWorkspace = applicationSupportWorkspace(repoURL: invalidRepoURL, roots: invalidRoots)
    try invalidWorkspace.initialize()
    try write("{", to: invalidWorkspace.stateURL)
    let invalidProject = CompassProject(
      repoURL: invalidRepoURL,
      storageApplicationSupportRoots: invalidRoots
    )

    invalidProject.prepareActiveStorageActivationConfirmation()

    #require(invalidProject.activeStorageActivationConfirmation == nil)
    #require(invalidProject.activeStorage == .repoLocal)
    #require(invalidProject.activeStorageActivationPlan().kind == .candidateInvalid)
    #require(invalidProject.activeStorageActivationState.phase == .blocked)
    #require(invalidProject.errorMessage == invalidProject.activeStorageActivationState.detail)
    #require(
      invalidProject.activeStorageActivationState.detail.count <=
      CompassProjectActiveStorageState.detailLimit)
  }

  private func makeTemporaryGitRepository() throws -> URL {
    let directory = try makeTemporaryDirectory()
    try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
    return directory
  }

  private func makeInitializedGitRepository() async throws -> URL {
    let directory = try makeTemporaryDirectory()
    let result = try await ProcessRunner.runEnv(
      "git",
      ["init", "-q"],
      workingDirectory: directory
    )
    guard result.exitCode == 0 else {
      throw ActiveStoragePersistenceTestError.failed(result.stderr)
    }
    return directory
  }

  private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = try makeTemporaryDirectory(prefix: "CompassProjectActiveStorageSupport")
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassProjectActiveStorageTests") throws
    -> URL
  {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(directory)
    try createDirectory(directory)
    return directory
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func write(_ contents: String, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func applicationSupportWorkspace(
    repoURL: URL,
    roots: KnownProjectStore.ApplicationSupportRoots
  ) -> CompassWorkspace {
    CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    .workspace
  }

  private func makeActivitySession(
    _ number: Int,
    status: SessionStatus,
    endedAt: Double,
    commits: Int
  ) -> SessionRecord {
    SessionRecord(
      session: number,
      startedAt: endedAt - 300,
      endedAt: endedAt,
      plan: "Activity scan \(number)",
      verify: "swift test",
      beforeSha: nil,
      afterSha: nil,
      commits: (0..<commits).map {
        SessionCommit(
          sha: "activity-\(number)-\($0)-abcdef1234567890",
          short: "a\(number)\($0)",
          subject: "Activity commit \(number)-\($0)"
        )
      },
      status: status,
      notes: [],
      verifyOutput: nil,
      feedback: nil
    )
  }

  // swift-format-ignore: AlwaysUseLowerCamelCase
  private func AssertDirectoryExists(
    _ url: URL
  ) {
    var isDirectory = ObjCBool(false)
    #require(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    )
    #require(isDirectory.boolValue)
  }

  // swift-format-ignore: AlwaysUseLowerCamelCase
  private func AssertFileExists(
    _ url: URL
  ) {
    var isDirectory = ObjCBool(false)
    #require(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    )
    #require(!isDirectory.boolValue)
  }
}

private enum ActiveStoragePersistenceTestError: LocalizedError {
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .failed(let message):
      return message
    }
  }
}
