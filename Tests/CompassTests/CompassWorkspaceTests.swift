import Foundation
import Testing

@testable import Compass

struct CompassWorkspaceTests : ~Copyable {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testInitializeCreatesCompassFilesAndGitignoreIdempotently() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)

    try workspace.initialize()
    try workspace.initialize()

    #require(
      workspace.storageRootURL == repoURL.appending(path: ".compass", directoryHint: .isDirectory))
    #require(workspace.compassURL == workspace.repoLocalCompassURL)
    #require(workspace.isRepoLocalStorage)
    #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.stateURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.lessonsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.visionURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsRecordURL.path))

    #require(try workspace.readState() == .empty)
    #require(try read(workspace.draftsURL) == "")
    #require(try read(workspace.lessonsURL) == "")
    #require(try read(workspace.visionURL) == "")
    #require(try read(workspace.sessionsRecordURL) == "[]\n")

    let gitignore = try read(repoURL.appending(path: ".gitignore"))
    #require(gitignore.components(separatedBy: ".compass/").count - 1 == 1)
  }

  @Test func testInjectedStorageRootRoundTripsFilesAndDoesNotCreateRepoLocalCompass() throws {
    let repoURL = try makeTemporaryGitRepository()
    let storageRootURL = try makeTemporaryDirectory(prefix: "CompassWorkspaceExternalStorage")
      .appending(path: "Compass", directoryHint: .isDirectory)
      .appending(path: "Projects", directoryHint: .isDirectory)
      .appending(path: "project-storage", directoryHint: .isDirectory)
    let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
    let state = makeState(
      completed: ["external"],
      immediate: PlanNext(plan: "Use injected storage", verify: "swift test"),
      midTerm: "next",
      longTerm: "later"
    )
    let records = [SessionRecord.started(4)]

    try workspace.initialize()
    try workspace.writeState(state)
    try workspace.backupStateFile()
    try workspace.writeDrafts("draft entry\n")
    try workspace.writeLessons("- old lesson\n")
    try workspace.applyLessonEdits([
      LessonEdit(find: "old lesson", replace: "new lesson", replaceAll: nil)
    ])
    try workspace.writeVision("vision entry\n")
    try workspace.writeSessions(records)
    let artifactURL = try workspace.writeSessionArtifact(
      session: 4,
      name: "plan/prompt:1.md",
      contents: "artifact body\n"
    )

    #require(workspace.repoURL == repoURL)
    #require(workspace.storageRootURL == storageRootURL)
    #require(workspace.compassURL == storageRootURL)
    #require(!workspace.isRepoLocalStorage)
    #require(FileManager.default.fileExists(atPath: storageRootURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    #require(try workspace.readState() == state)
    #require(try read(workspace.stateBackupURL) == try CompassWorkspace.encodeState(state))
    #require(workspace.readDrafts() == "draft entry\n")
    #require(workspace.readLessons() == "- new lesson\n")
    #require(workspace.readVision() == "vision entry\n")
    #require(workspace.readSessions() == records)
    #require(try read(artifactURL) == "artifact body\n")
    #require(artifactURL == workspace.sessionsURL.appending(path: "4-plan-prompt-1.md"))

    #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
  }

  @Test func testSessionsJsonDecodesLegacyRecordsWithoutExecutionEnvironmentSnapshots() throws {
    let workspace = try makeInitializedWorkspace()
    try write(
      """
      [
        {
          "session": 7,
          "startedAt": 1000,
          "status": "succeeded",
          "notes": ["legacy"],
          "commits": []
        }
      ]

      """,
      to: workspace.sessionsRecordURL
    )

    let records = workspace.readSessions()

    #require(records.count == 1)
    #require(records[0].session == 7)
    #require(records[0].status == .succeeded)
    #require(records[0].notes == ["legacy"])
    #require(records[0].executionEnvironmentSnapshots.isEmpty)

    try workspace.writeSessions(records)
    let rewritten = try read(workspace.sessionsRecordURL)
    #require(!rewritten.contains("executionEnvironmentSnapshots"))
  }

  @Test func testSessionsJsonRoundTripsExecutionEnvironmentSnapshotsWithoutLeakingRuntimePaths() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.10",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-AAA/worktree"
    )
    let launchPlan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    var record = SessionRecord.started(9)
    record.recordExecutionEnvironmentSnapshot(
      SessionExecutionEnvironmentSnapshot(
        phase: "Verify",
        attempt: 1,
        launchPlan: launchPlan
      )
    )

    try workspace.writeSessions([record])
    let decoded = workspace.readSessions()
    let persistedText = try read(workspace.sessionsRecordURL)

    #require(decoded == [record])
    #require(decoded[0].latestExecutionEnvironmentSnapshot?.phaseIdentifier == "verify")
    #require(
      decoded[0].latestExecutionEnvironmentSnapshot?.effectiveRouteIdentifier == "shared-vm")
    #require(persistedText.contains("executionEnvironmentSnapshots"))
    #require(!persistedText.contains(repoURL.standardizedFileURL.path))
  }

  @Test func testSessionExecutionEnvironmentSnapshotsReplaceDuplicatePhaseAttemptsAndStayBounded() throws
  {
    let repoURL = try makeTemporaryGitRepository()
    let nativePlan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .ready(sshDestination: "compass@192.0.2.10")
    )
    let fallbackPlan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .notProvisioned
    )
    var duplicateRecord = SessionRecord.started(1)

    duplicateRecord.recordExecutionEnvironmentSnapshot(
      SessionExecutionEnvironmentSnapshot(
        phase: "Develop",
        attempt: 1,
        launchPlan: nativePlan
      )
    )
    duplicateRecord.recordExecutionEnvironmentSnapshot(
      SessionExecutionEnvironmentSnapshot(
        phase: "Develop",
        attempt: 1,
        launchPlan: fallbackPlan
      )
    )

    #require(duplicateRecord.executionEnvironmentSnapshots.count == 1)
    #require(
      duplicateRecord.executionEnvironmentSnapshots[0].selectedPreferenceIdentifier ==
      "shared_vm"
    )
    #require(
      duplicateRecord.executionEnvironmentSnapshots[0].effectiveRouteIdentifier == "native-macos")
    #require(
      duplicateRecord.executionEnvironmentSnapshots[0].fallbackReason?.contains(
        "not been provisioned") ?? false
    )

    var boundedRecord = SessionRecord.started(2)
    for attempt in 1...(SessionRecord.executionEnvironmentSnapshotLimit + 3) {
      boundedRecord.recordExecutionEnvironmentSnapshot(
        SessionExecutionEnvironmentSnapshot(
          phase: "Develop",
          attempt: attempt,
          launchPlan: nativePlan
        )
      )
    }

    #require(
      boundedRecord.executionEnvironmentSnapshots.count ==
      SessionRecord.executionEnvironmentSnapshotLimit
    )
    #require(boundedRecord.executionEnvironmentSnapshots.first?.attempt == 4)
    #require(
      boundedRecord.executionEnvironmentSnapshots.last?.attempt ==
      SessionRecord.executionEnvironmentSnapshotLimit + 3
    )
  }

  @Test func testInitializePreservesExistingCompassFilesAndRecognizesIgnoredCompassVariants() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(workspace.compassURL)
    try createDirectory(workspace.sessionsURL)

    let state = makeState(completed: ["keep"], midTerm: "queued", longTerm: "vision")
    try write(try CompassWorkspace.encodeState(state), to: workspace.stateURL)
    try write("existing drafts\n", to: workspace.draftsURL)
    try write("existing lessons\n", to: workspace.lessonsURL)
    try write("existing vision\n", to: workspace.visionURL)
    try write("[{\"session\":1}]\n", to: workspace.sessionsRecordURL)
    try write("# keep\n.compass\n", to: repoURL.appending(path: ".gitignore"))

    try workspace.initialize()

    #require(try workspace.readState() == state)
    #require(try read(workspace.draftsURL) == "existing drafts\n")
    #require(try read(workspace.lessonsURL) == "existing lessons\n")
    #require(try read(workspace.visionURL) == "existing vision\n")
    #require(try read(workspace.sessionsRecordURL) == "[{\"session\":1}]\n")
    #require(try read(repoURL.appending(path: ".gitignore")) == "# keep\n.compass\n")
  }

  @Test func testInitializeRepairsMissingCoreFilesAndGitignoreCoverageIdempotently() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(workspace.compassURL)

    let preservedState = makeState(completed: ["preserve"], midTerm: "next", longTerm: "later")
    try write(try CompassWorkspace.encodeState(preservedState), to: workspace.stateURL)
    try write("existing lessons\n", to: workspace.lessonsURL)
    try write("build", to: repoURL.appending(path: ".gitignore"))

    try workspace.initialize()
    try workspace.initialize()

    #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.stateURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.lessonsURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.visionURL.path))
    #require(FileManager.default.fileExists(atPath: workspace.sessionsRecordURL.path))

    #require(try workspace.readState() == preservedState)
    #require(try read(workspace.lessonsURL) == "existing lessons\n")
    #require(try read(workspace.draftsURL) == "")
    #require(try read(workspace.visionURL) == "")
    #require(try read(workspace.sessionsRecordURL) == "[]\n")

    let gitignore = try read(repoURL.appending(path: ".gitignore"))
    #require(gitignore == "build\n.compass/\n")
    #require(gitignore.components(separatedBy: ".compass/").count - 1 == 1)
  }

  @Test func testInitializeAppendsCompassIgnoreWithMissingTrailingNewline() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    let gitignoreURL = repoURL.appending(path: ".gitignore")
    try write("build", to: gitignoreURL)

    try workspace.initialize()
    try workspace.initialize()

    #require(try read(gitignoreURL) == "build\n.compass/\n")
  }

  @Test func testWriteStateReadStateRoundTripAndBackupCreation() throws {
    let workspace = try makeInitializedWorkspace()
    let state = makeState(
      completed: ["first", "second"],
      immediate: PlanNext(
        plan: "Build workspace tests",
        verify: "swift test",
        verifyTimeoutMs: 120_000,
        estimatedDifficulty: .medium
      ),
      midTerm: "- Follow up",
      longTerm: "Ship it"
    )

    try workspace.writeState(state)
    #require(try workspace.readState() == state)

    try workspace.backupStateFile()
    #require(FileManager.default.fileExists(atPath: workspace.stateBackupURL.path))
    #require(try read(workspace.stateBackupURL) == try CompassWorkspace.encodeState(state))
  }

  @Test func testBackupStateFileDoesNothingWhenStateIsMissing() throws {
    let workspace = try makeInitializedWorkspace()
    try FileManager.default.removeItem(at: workspace.stateURL)

    try workspace.backupStateFile()

    #require(!FileManager.default.fileExists(atPath: workspace.stateBackupURL.path))
  }

  @Test func testAppendDraftAddsMarkdownBulletsAndSkipsEmptyText() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.appendDraft("  first draft  ")
    #require(try read(workspace.draftsURL) == "- first draft\n")

    try workspace.appendDraft("second draft")
    #require(
      try read(workspace.draftsURL) ==
      "- first draft\n\n- second draft\n"
    )

    try workspace.appendDraft("   \n")
    #require(try read(workspace.draftsURL) == "- first draft\n\n- second draft\n")
  }

  @Test func testAppendDraftSeparatorVariants() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.writeDrafts("- existing")
    try workspace.appendDraft("without trailing newline")
    #require(try read(workspace.draftsURL) == "- existing\n\n- without trailing newline\n")

    try workspace.writeDrafts("- existing\n")
    try workspace.appendDraft("with one trailing newline")
    #require(try read(workspace.draftsURL) == "- existing\n\n- with one trailing newline\n")

    try workspace.writeDrafts("- existing\n\n")
    try workspace.appendDraft("already separated")
    #require(try read(workspace.draftsURL) == "- existing\n\n- already separated\n")
  }

  @Test func testSnapshotAndClearDraftsReturnsContentsClearsDraftsAndToleratesMissingFile() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeDrafts("- one\n\n- two\n")

    let snapshot = try workspace.snapshotAndClearDrafts()

    #require(snapshot == "- one\n\n- two\n")
    #require(try read(workspace.draftsURL) == "")
    #require(
      !FileManager.default.fileExists(
        atPath: workspace.draftsURL.appendingPathExtension("snapshot").path))

    try FileManager.default.removeItem(at: workspace.draftsURL)
    #require(try workspace.snapshotAndClearDrafts() == "")
    #require(!FileManager.default.fileExists(atPath: workspace.draftsURL.path))
  }

  @Test func testApplyLessonEditsSupportsExactReplacementReplaceAllAndEmptyFindForEmptyLessons() throws {
    let workspace = try makeInitializedWorkspace()

    #require(
      try workspace.applyLessonEdits([
        LessonEdit(find: "", replace: "- Start here\n", replaceAll: nil)
      ]) ==
      1
    )
    #require(workspace.readLessons() == "- Start here\n")

    #require(
      try workspace.applyLessonEdits([
        LessonEdit(find: "Start here", replace: "Keep this convention", replaceAll: nil)
      ]) ==
      1
    )
    #require(workspace.readLessons() == "- Keep this convention\n")

    try workspace.writeLessons("- repeated\n- repeated\n")
    #require(
      try workspace.applyLessonEdits([
        LessonEdit(find: "repeated", replace: "updated", replaceAll: true)
      ]) ==
      1
    )
    #require(workspace.readLessons() == "- updated\n- updated\n")
  }

  @Test func testApplyLessonEditsRejectsEmptyFindWhenLessonsAreNonEmpty() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")

    try assertLessonEditFailure(
      try workspace.applyLessonEdits([
        LessonEdit(find: "", replace: "- Replacement\n", replaceAll: nil)
      ]),
      contains: "Empty `find` is only allowed"
    )
    #require(workspace.readLessons() == "- Existing\n")
  }

  @Test func testApplyLessonEditsRejectsMissingFindAndPreservesLessons() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")

    try assertLessonEditFailure(
      try workspace.applyLessonEdits([
        LessonEdit(find: "Missing", replace: "Replacement", replaceAll: nil)
      ]),
      contains: "was not found"
    )
    #require(workspace.readLessons() == "- Existing\n")
  }

  @Test func testApplyLessonEditsRejectsDuplicateFindWithoutReplaceAllAndPreservesLessons() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- duplicate\n- duplicate\n")

    try assertLessonEditFailure(
      try workspace.applyLessonEdits([
        LessonEdit(find: "duplicate", replace: "replacement", replaceAll: nil)
      ]),
      contains: "matched 2 times"
    )
    #require(workspace.readLessons() == "- duplicate\n- duplicate\n")
  }

  @Test func testValidateLessonEditsRejectsMissingFindWithoutWriting() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")

    try assertLessonEditFailure(
      try workspace.validateLessonEdits([
        LessonEdit(find: "Missing", replace: "Replacement", replaceAll: nil)
      ]),
      contains: "was not found"
    )
    #require(workspace.readLessons() == "- Existing\n")
  }

  @Test func testValidateSubmitResultLessonEditsDecodesPayloadWithoutApplying() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")
    let payload = """
      {"state":{"immediate":null,"midTerm":[],"longTerm":"x"},"lessonEdits":[{"find":"Missing","replace":"Replacement"}]}
      """

    try assertLessonEditFailure(
      try workspace.validateSubmitResultLessonEdits(Data(payload.utf8)),
      contains: "was not found"
    )
    #require(workspace.readLessons() == "- Existing\n")
  }

  private func makeInitializedWorkspace() throws -> CompassWorkspace {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()
    return workspace
  }

  private func makeTemporaryGitRepository() throws -> URL {
    let directory = try makeTemporaryDirectory()
    try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
    return directory
  }

  private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceTests") throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(directory)
    try createDirectory(directory)
    return directory
  }

  private func makeState(
    completed: [String] = [],
    immediate: PlanNext? = nil,
    midTerm: String = "",
    longTerm: String = ""
  ) -> PlanState {
    PlanState(
      completed: completed,
      immediate: immediate,
      midTerm: midTerm,
      longTerm: longTerm
    )
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  private func write(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func writeDevcontainer(_ contents: String, in repoURL: URL) throws {
    let url =
      repoURL
      .appending(path: ".devcontainer", directoryHint: .isDirectory)
      .appending(path: "devcontainer.json")
    try createDirectory(url.deletingLastPathComponent())
    try write(contents, to: url)
  }

  // swift-format-ignore: AlwaysUseLowerCamelCase
  private func AssertFileExists(
    _ url: URL
  ) {
    var isDirectory: ObjCBool = false
    #require(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    )
    #require(!isDirectory.boolValue)
  }

  // swift-format-ignore: AlwaysUseLowerCamelCase
  private func AssertDirectoryExists(
    _ url: URL
  ) {
    var isDirectory: ObjCBool = false
    #require(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    )
    #require(isDirectory.boolValue)
  }

  private func assertLessonEditFailure<T>(
    _ expression: @autoclosure () throws -> T,
    contains expectedText: String
  ) throws {
    do {
      _ = try expression()
      #require(false, "Expected expression to throw")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      #require(
        message.contains(expectedText),
        "Expected error containing `\(expectedText)`, got `\(message)`."
      )
    }
  }
}
