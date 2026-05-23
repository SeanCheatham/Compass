import Foundation
import XCTest

@testable import Compass

final class CompassWorkspacePersistenceTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    let fm = FileManager.default
    for url in temporaryDirectories {
      try? fm.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testInitializeCreatesCompassFilesAndGitignoreIdempotently() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)

    try workspace.initialize()
    try workspace.initialize()

    XCTAssertEqual(
      workspace.storageRootURL, repoURL.appending(path: ".compass", directoryHint: .isDirectory))
    XCTAssertEqual(workspace.compassURL, workspace.repoLocalCompassURL)
    XCTAssertTrue(workspace.isRepoLocalStorage)
    XCTAssertDirectoryExists(workspace.compassURL)
    XCTAssertDirectoryExists(workspace.sessionsURL)
    XCTAssertFileExists(workspace.stateURL)
    XCTAssertFileExists(workspace.draftsURL)
    XCTAssertFileExists(workspace.lessonsURL)
    XCTAssertFileExists(workspace.visionURL)
    XCTAssertFileExists(workspace.sessionsRecordURL)

    XCTAssertEqual(try workspace.readState(), .empty)
    XCTAssertEqual(try read(workspace.draftsURL), "")
    XCTAssertEqual(try read(workspace.lessonsURL), "")
    XCTAssertEqual(try read(workspace.visionURL), "")
    XCTAssertEqual(try read(workspace.sessionsRecordURL), "[]\n")

    let gitignore = try read(repoURL.appending(path: ".gitignore"))
    XCTAssertEqual(gitignore.components(separatedBy: ".compass/").count - 1, 1)
  }

  func testInjectedStorageRootRoundTripsFilesAndDoesNotCreateRepoLocalCompass() throws {
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

    XCTAssertEqual(workspace.repoURL, repoURL)
    XCTAssertEqual(workspace.storageRootURL, storageRootURL)
    XCTAssertEqual(workspace.compassURL, storageRootURL)
    XCTAssertFalse(workspace.isRepoLocalStorage)
    XCTAssertDirectoryExists(storageRootURL)
    XCTAssertDirectoryExists(workspace.sessionsURL)
    XCTAssertEqual(try workspace.readState(), state)
    XCTAssertEqual(try read(workspace.stateBackupURL), try CompassWorkspace.encodeState(state))
    XCTAssertEqual(workspace.readDrafts(), "draft entry\n")
    XCTAssertEqual(workspace.readLessons(), "- new lesson\n")
    XCTAssertEqual(workspace.readVision(), "vision entry\n")
    XCTAssertEqual(workspace.readSessions(), records)
    XCTAssertEqual(try read(artifactURL), "artifact body\n")
    XCTAssertEqual(artifactURL, workspace.sessionsURL.appending(path: "4-plan-prompt-1.md"))

    XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
  }

  func testSessionsJsonDecodesLegacyRecordsWithoutExecutionEnvironmentSnapshots() throws {
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

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].session, 7)
    XCTAssertEqual(records[0].status, .succeeded)
    XCTAssertEqual(records[0].notes, ["legacy"])
    XCTAssertTrue(records[0].executionEnvironmentSnapshots.isEmpty)
    XCTAssertTrue(records[0].mutationTestingExecutions.isEmpty)

    try workspace.writeSessions(records)
    let rewritten = try read(workspace.sessionsRecordURL)
    XCTAssertFalse(rewritten.contains("executionEnvironmentSnapshots"))
    XCTAssertFalse(rewritten.contains("mutationTestingExecutions"))
  }

  func testSessionsJsonRoundTripsExecutionEnvironmentSnapshotsWithoutLeakingRuntimePaths() throws {
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

    XCTAssertEqual(decoded, [record])
    XCTAssertEqual(decoded[0].latestExecutionEnvironmentSnapshot?.phaseIdentifier, "verify")
    XCTAssertEqual(
      decoded[0].latestExecutionEnvironmentSnapshot?.effectiveRouteIdentifier, "shared-vm")
    XCTAssertTrue(persistedText.contains("executionEnvironmentSnapshots"))
    XCTAssertFalse(persistedText.contains(repoURL.standardizedFileURL.path))
  }

  func testSessionExecutionEnvironmentSnapshotsReplaceDuplicatePhaseAttemptsAndStayBounded() throws
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

    XCTAssertEqual(duplicateRecord.executionEnvironmentSnapshots.count, 1)
    XCTAssertEqual(
      duplicateRecord.executionEnvironmentSnapshots[0].selectedPreferenceIdentifier,
      "shared_vm"
    )
    XCTAssertEqual(
      duplicateRecord.executionEnvironmentSnapshots[0].effectiveRouteIdentifier, "native-macos")
    XCTAssertTrue(
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

    XCTAssertEqual(
      boundedRecord.executionEnvironmentSnapshots.count,
      SessionRecord.executionEnvironmentSnapshotLimit
    )
    XCTAssertEqual(boundedRecord.executionEnvironmentSnapshots.first?.attempt, 4)
    XCTAssertEqual(
      boundedRecord.executionEnvironmentSnapshots.last?.attempt,
      SessionRecord.executionEnvironmentSnapshotLimit + 3
    )
  }

  func testInitializePreservesExistingCompassFilesAndRecognizesIgnoredCompassVariants() throws {
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

    XCTAssertEqual(try workspace.readState(), state)
    XCTAssertEqual(try read(workspace.draftsURL), "existing drafts\n")
    XCTAssertEqual(try read(workspace.lessonsURL), "existing lessons\n")
    XCTAssertEqual(try read(workspace.visionURL), "existing vision\n")
    XCTAssertEqual(try read(workspace.sessionsRecordURL), "[{\"session\":1}]\n")
    XCTAssertEqual(try read(repoURL.appending(path: ".gitignore")), "# keep\n.compass\n")
  }

  func testInitializeRepairsMissingCoreFilesAndGitignoreCoverageIdempotently() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(workspace.compassURL)

    let preservedState = makeState(completed: ["preserve"], midTerm: "next", longTerm: "later")
    try write(try CompassWorkspace.encodeState(preservedState), to: workspace.stateURL)
    try write("existing lessons\n", to: workspace.lessonsURL)
    try write("build", to: repoURL.appending(path: ".gitignore"))

    try workspace.initialize()
    try workspace.initialize()

    XCTAssertDirectoryExists(workspace.compassURL)
    XCTAssertDirectoryExists(workspace.sessionsURL)
    XCTAssertFileExists(workspace.stateURL)
    XCTAssertFileExists(workspace.draftsURL)
    XCTAssertFileExists(workspace.lessonsURL)
    XCTAssertFileExists(workspace.visionURL)
    XCTAssertFileExists(workspace.sessionsRecordURL)

    XCTAssertEqual(try workspace.readState(), preservedState)
    XCTAssertEqual(try read(workspace.lessonsURL), "existing lessons\n")
    XCTAssertEqual(try read(workspace.draftsURL), "")
    XCTAssertEqual(try read(workspace.visionURL), "")
    XCTAssertEqual(try read(workspace.sessionsRecordURL), "[]\n")

    let gitignore = try read(repoURL.appending(path: ".gitignore"))
    XCTAssertEqual(gitignore, "build\n.compass/\n")
    XCTAssertEqual(gitignore.components(separatedBy: ".compass/").count - 1, 1)
  }

  func testInitializeAppendsCompassIgnoreWithMissingTrailingNewline() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    let gitignoreURL = repoURL.appending(path: ".gitignore")
    try write("build", to: gitignoreURL)

    try workspace.initialize()
    try workspace.initialize()

    XCTAssertEqual(try read(gitignoreURL), "build\n.compass/\n")
  }

  func testWriteStateReadStateRoundTripAndBackupCreation() throws {
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
    XCTAssertEqual(try workspace.readState(), state)

    try workspace.backupStateFile()
    XCTAssertFileExists(workspace.stateBackupURL)
    XCTAssertEqual(try read(workspace.stateBackupURL), try CompassWorkspace.encodeState(state))
  }

  func testBackupStateFileDoesNothingWhenStateIsMissing() throws {
    let workspace = try makeInitializedWorkspace()
    try FileManager.default.removeItem(at: workspace.stateURL)

    try workspace.backupStateFile()

    XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.stateBackupURL.path))
  }

  func testAppendDraftAddsMarkdownBulletsAndSkipsEmptyText() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.appendDraft("  first draft  ")
    XCTAssertEqual(try read(workspace.draftsURL), "- first draft\n")

    try workspace.appendDraft("second draft")
    XCTAssertEqual(
      try read(workspace.draftsURL),
      "- first draft\n\n- second draft\n"
    )

    try workspace.appendDraft("   \n")
    XCTAssertEqual(try read(workspace.draftsURL), "- first draft\n\n- second draft\n")
  }

  func testAppendDraftSeparatorVariants() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.writeDrafts("- existing")
    try workspace.appendDraft("without trailing newline")
    XCTAssertEqual(try read(workspace.draftsURL), "- existing\n\n- without trailing newline\n")

    try workspace.writeDrafts("- existing\n")
    try workspace.appendDraft("with one trailing newline")
    XCTAssertEqual(try read(workspace.draftsURL), "- existing\n\n- with one trailing newline\n")

    try workspace.writeDrafts("- existing\n\n")
    try workspace.appendDraft("already separated")
    XCTAssertEqual(try read(workspace.draftsURL), "- existing\n\n- already separated\n")
  }

  func testSnapshotAndClearDraftsReturnsContentsClearsDraftsAndToleratesMissingFile() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeDrafts("- one\n\n- two\n")

    let snapshot = try workspace.snapshotAndClearDrafts()

    XCTAssertEqual(snapshot, "- one\n\n- two\n")
    XCTAssertEqual(try read(workspace.draftsURL), "")
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: workspace.draftsURL.appendingPathExtension("snapshot").path))

    try FileManager.default.removeItem(at: workspace.draftsURL)
    XCTAssertEqual(try workspace.snapshotAndClearDrafts(), "")
    XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
  }

  func testApplyLessonEditsSupportsExactReplacementReplaceAllAndEmptyFindForEmptyLessons() throws {
    let workspace = try makeInitializedWorkspace()

    XCTAssertEqual(
      try workspace.applyLessonEdits([
        LessonEdit(find: "", replace: "- Start here\n", replaceAll: nil)
      ]),
      1
    )
    XCTAssertEqual(workspace.readLessons(), "- Start here\n")

    XCTAssertEqual(
      try workspace.applyLessonEdits([
        LessonEdit(find: "Start here", replace: "Keep this convention", replaceAll: nil)
      ]),
      1
    )
    XCTAssertEqual(workspace.readLessons(), "- Keep this convention\n")

    try workspace.writeLessons("- repeated\n- repeated\n")
    XCTAssertEqual(
      try workspace.applyLessonEdits([
        LessonEdit(find: "repeated", replace: "updated", replaceAll: true)
      ]),
      1
    )
    XCTAssertEqual(workspace.readLessons(), "- updated\n- updated\n")
  }

  func testApplyLessonEditsRejectsEmptyFindWhenLessonsAreNonEmpty() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")

    assertLessonEditFailure(
      try workspace.applyLessonEdits([
        LessonEdit(find: "", replace: "- Replacement\n", replaceAll: nil)
      ]),
      contains: "Empty `find` is only allowed"
    )
    XCTAssertEqual(workspace.readLessons(), "- Existing\n")
  }

  func testApplyLessonEditsRejectsMissingFindAndPreservesLessons() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")

    assertLessonEditFailure(
      try workspace.applyLessonEdits([
        LessonEdit(find: "Missing", replace: "Replacement", replaceAll: nil)
      ]),
      contains: "was not found"
    )
    XCTAssertEqual(workspace.readLessons(), "- Existing\n")
  }

  func testApplyLessonEditsRejectsDuplicateFindWithoutReplaceAllAndPreservesLessons() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- duplicate\n- duplicate\n")

    assertLessonEditFailure(
      try workspace.applyLessonEdits([
        LessonEdit(find: "duplicate", replace: "replacement", replaceAll: nil)
      ]),
      contains: "matched 2 times"
    )
    XCTAssertEqual(workspace.readLessons(), "- duplicate\n- duplicate\n")
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
  private func XCTAssertFileExists(
    _ url: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var isDirectory: ObjCBool = false
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      "Expected file to exist at \(url.path).",
      file: file,
      line: line
    )
    XCTAssertFalse(
      isDirectory.boolValue, "Expected \(url.path) to be a file.", file: file, line: line)
  }

  // swift-format-ignore: AlwaysUseLowerCamelCase
  private func XCTAssertDirectoryExists(
    _ url: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var isDirectory: ObjCBool = false
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      "Expected directory to exist at \(url.path).",
      file: file,
      line: line
    )
    XCTAssertTrue(
      isDirectory.boolValue, "Expected \(url.path) to be a directory.", file: file, line: line)
  }

  private func assertLessonEditFailure<T>(
    _ expression: @autoclosure () throws -> T,
    contains expectedText: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      XCTAssertTrue(
        message.contains(expectedText),
        "Expected error containing `\(expectedText)`, got `\(message)`.",
        file: file,
        line: line
      )
    }
  }
}
