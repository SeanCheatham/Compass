import Foundation
import Testing

@testable import Compass

final class CompassWorkspaceTests {
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

    try #require(
      workspace.storageRootURL == repoURL.appending(path: ".compass", directoryHint: .isDirectory))
    try #require(workspace.compassURL == workspace.repoLocalCompassURL)
    try #require(workspace.isRepoLocalStorage)
    try #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.stateURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.lessonsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.assumptionsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.visionURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.sessionsRecordURL.path))

    try #require(try workspace.readState() == .empty)
    try #require(try read(workspace.draftsURL) == "")
    try #require(try read(workspace.lessonsURL) == "")
    try #require(try workspace.readAssumptionLedger() == .empty)
    try #require(try read(workspace.visionURL) == "")
    try #require(try read(workspace.sessionsRecordURL) == "")

    let gitignore = try read(repoURL.appending(path: ".gitignore"))
    try #require(gitignore.components(separatedBy: ".compass/").count - 1 == 1)
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
      candidates: "next",
      strategicContext: "later"
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
    let assumption = try workspace.recordAssumption(
      AssumptionDraft(
        text: "The app ships outside the Mac App Store.",
        rationale: "The project documentation says App Sandbox is off.",
        evidence: ["README.md"],
        impact: "Signing choices depend on this.",
        invalidation: "User says App Store distribution is required.",
        scope: .project
      ),
      phase: .plan,
      sessionNumber: 4
    )
    try workspace.writeVision("vision entry\n")
    try workspace.writeSessions(records)
    let artifactURL = try workspace.writeSessionArtifact(
      session: 4,
      name: "plan/prompt:1.md",
      contents: "artifact body\n"
    )

    try #require(workspace.repoURL == repoURL)
    try #require(workspace.storageRootURL == storageRootURL)
    try #require(workspace.compassURL == storageRootURL)
    try #require(!workspace.isRepoLocalStorage)
    try #require(FileManager.default.fileExists(atPath: storageRootURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    try #require(try workspace.readState() == state)
    let encodedState = try CompassWorkspace.encodeState(state)
    try #require(try read(workspace.stateBackupURL) == encodedState)
    try #require(workspace.readDrafts() == "draft entry\n")
    try #require(workspace.readLessons() == "- new lesson\n")
    try #require(try workspace.readAssumptionLedger().assumptions == [assumption])
    try #require(workspace.readVision() == "vision entry\n")
    try #require(workspace.readSessions() == records)
    try #require(try read(artifactURL) == "artifact body\n")
    try #require(artifactURL == workspace.sessionsURL.appending(path: "4-plan-prompt-1.md"))

    try #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    try #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
  }

  @Test func testSessionsJSONLDecodesRecordsWithoutExecutionEnvironmentSnapshots() throws {
    let workspace = try makeInitializedWorkspace()
    var record = SessionRecord.started(7)
    record.startedAt = 1000
    record.status = .succeeded
    record.notes = ["legacy"]
    try workspace.writeSessions([record])

    let records = workspace.readSessions()

    try #require(records.count == 1)
    try #require(records[0].session == 7)
    try #require(records[0].status == .succeeded)
    try #require(records[0].notes == ["legacy"])
    try #require(records[0].executionEnvironmentSnapshots.isEmpty)

    try workspace.writeSessions(records)
    let rewritten = try read(workspace.sessionsRecordURL)
    try #require(!rewritten.contains("executionEnvironmentSnapshots"))
  }

  @Test func testSessionAuditWritesManifestEventsAndArtifacts() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.updateSessionAuditManifest(
      session: 4,
      status: .planning,
      startedAt: 1_000,
      endedAt: nil
    )
    try workspace.appendSessionAuditEvent(
      SessionAuditEvent(
        session: 4,
        sequence: 1,
        phase: "Planning",
        kind: "live_line",
        level: "info",
        text: "Plan input captured."
      )
    )
    let artifactURL = try workspace.writeSessionAuditArtifact(
      session: 4,
      name: "verify/attempt:1.log",
      kind: "verify_output",
      contents: "full verify output\n",
      note: "Full Verify output."
    )

    let manifest = try #require(workspace.readSessionAuditManifest(session: 4))
    let eventText = try read(workspace.sessionAuditEventsURL(session: 4))

    try #require(
      workspace.sessionAuditDirectoryURL(session: 4)
        == workspace.sessionsURL.appending(path: "000004", directoryHint: .isDirectory)
    )
    try #require(try read(artifactURL) == "full verify output\n")
    try #require(manifest.session == 4)
    try #require(manifest.status == .planning)
    try #require(manifest.startedAt == 1_000)
    try #require(manifest.artifacts.count == 1)
    try #require(manifest.artifacts[0].path == "sessions/000004/verify-attempt-1.log")
    try #require(manifest.artifacts[0].kind == "verify_output")
    try #require(eventText.contains(#""kind":"live_line""#))
    try #require(eventText.contains("Plan input captured."))
  }

  @Test func testAssumptionLedgerRecordsReviewsAndPreservesDeniedStatus() throws {
    let workspace = try makeInitializedWorkspace()
    let draft = AssumptionDraft(
      text: "The project targets macOS only.",
      rationale: "Package.swift declares only macOS.",
      evidence: ["Package.swift"],
      impact: "Plan should not add iOS-specific workflow.",
      invalidation: "User asks for iOS support.",
      scope: .project
    )

    let first = try workspace.recordAssumption(draft, phase: .plan, sessionNumber: 2)
    try #require(first.status == .implicit)

    let denied = try workspace.reviewAssumption(
      id: first.id,
      status: .denied,
      comment: "iOS support is planned next."
    )
    try #require(denied.status == .denied)
    try #require(denied.userComment == "iOS support is planned next.")

    let rerecorded = try workspace.recordAssumption(draft, phase: .develop, sessionNumber: 3)
    try #require(rerecorded.id == first.id)
    try #require(rerecorded.status == .denied)

    let summary = try workspace.readAssumptionLedger().formattedForPrompt()
    try #require(summary.contains("Denied assumptions"))
    try #require(summary.contains("do not rely"))
    try #require(summary.contains("Scope: Project"))
    try #require(summary.contains("Session: #2"))
    try #require(summary.contains("Evidence: Package.swift"))
    try #require(summary.contains("Invalidated by: User asks for iOS support."))
    try #require(summary.contains("iOS support is planned next."))
  }

  @Test func testAssumptionLedgerRejectsMissingRequiredDetail() throws {
    let workspace = try makeInitializedWorkspace()

    #expect(throws: AssumptionLedgerError.emptyRationale) {
      try workspace.recordAssumption(
        AssumptionDraft(
          text: "The project targets macOS only.",
          rationale: " ",
          impact: "Plan should not add iOS-specific workflow.",
          scope: .project
        ),
        phase: .plan,
        sessionNumber: 2
      )
    }

    #expect(throws: AssumptionLedgerError.emptyImpact) {
      try workspace.recordAssumption(
        AssumptionDraft(
          text: "The project targets macOS only.",
          rationale: "Package.swift declares only macOS.",
          impact: "",
          scope: .project
        ),
        phase: .plan,
        sessionNumber: 2
      )
    }

    try #require(try workspace.readAssumptionLedger().assumptions.isEmpty)
  }

  @Test func testSessionsJsonRoundTripsExecutionEnvironmentSnapshotsWithoutLeakingRuntimePaths()
    throws
  {
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

    try #require(decoded == [record])
    try #require(decoded[0].latestExecutionEnvironmentSnapshot?.phaseIdentifier == "verify")
    try #require(
      decoded[0].latestExecutionEnvironmentSnapshot?.effectiveRouteIdentifier == "shared-vm")
    try #require(persistedText.contains("executionEnvironmentSnapshots"))
    try #require(!persistedText.contains(repoURL.standardizedFileURL.path))
  }

  @Test func testSessionExecutionEnvironmentSnapshotsReplaceDuplicatePhaseAttemptsAndStayBounded()
    throws
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

    try #require(duplicateRecord.executionEnvironmentSnapshots.count == 1)
    try #require(
      duplicateRecord.executionEnvironmentSnapshots[0].selectedPreferenceIdentifier == "shared_vm"
    )
    try #require(
      duplicateRecord.executionEnvironmentSnapshots[0].effectiveRouteIdentifier == "native-macos")
    try #require(
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

    try #require(
      boundedRecord.executionEnvironmentSnapshots.count
        == SessionRecord.executionEnvironmentSnapshotLimit
    )
    try #require(boundedRecord.executionEnvironmentSnapshots.first?.attempt == 4)
    try #require(
      boundedRecord.executionEnvironmentSnapshots.last?.attempt == SessionRecord
        .executionEnvironmentSnapshotLimit + 3
    )
  }

  @Test func testInitializePreservesExistingCompassFilesAndRecognizesIgnoredCompassVariants() throws
  {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(workspace.compassURL)
    try createDirectory(workspace.sessionsURL)

    let state = makeState(completed: ["keep"], candidates: "queued", strategicContext: "vision")
    try write(try CompassWorkspace.encodeState(state), to: workspace.stateURL)
    try write("existing drafts\n", to: workspace.draftsURL)
    try write("existing lessons\n", to: workspace.lessonsURL)
    try write("existing vision\n", to: workspace.visionURL)
    try write("[{\"session\":1}]\n", to: workspace.sessionsRecordURL)
    try write("# keep\n.compass\n", to: repoURL.appending(path: ".gitignore"))

    try workspace.initialize()

    try #require(try workspace.readState() == state)
    try #require(try read(workspace.draftsURL) == "existing drafts\n")
    try #require(try read(workspace.lessonsURL) == "existing lessons\n")
    try #require(try read(workspace.visionURL) == "existing vision\n")
    try #require(try read(workspace.sessionsRecordURL) == "[{\"session\":1}]\n")
    try #require(try read(repoURL.appending(path: ".gitignore")) == "# keep\n.compass\n")
  }

  @Test func testInitializeRepairsMissingCoreFilesAndGitignoreCoverageIdempotently() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(workspace.compassURL)

    let preservedState = makeState(completed: ["preserve"], candidates: "next", strategicContext: "later")
    try write(try CompassWorkspace.encodeState(preservedState), to: workspace.stateURL)
    try write("existing lessons\n", to: workspace.lessonsURL)
    try write("build", to: repoURL.appending(path: ".gitignore"))

    try workspace.initialize()
    try workspace.initialize()

    try #require(FileManager.default.fileExists(atPath: workspace.compassURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.stateURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.draftsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.lessonsURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.visionURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.sessionsRecordURL.path))

    try #require(try workspace.readState() == preservedState)
    try #require(try read(workspace.lessonsURL) == "existing lessons\n")
    try #require(try read(workspace.draftsURL) == "")
    try #require(try read(workspace.visionURL) == "")
    try #require(try read(workspace.sessionsRecordURL) == "")

    let gitignore = try read(repoURL.appending(path: ".gitignore"))
    try #require(gitignore == "build\n.compass/\n")
    try #require(gitignore.components(separatedBy: ".compass/").count - 1 == 1)
  }

  @Test func testInitializeAppendsCompassIgnoreWithMissingTrailingNewline() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    let gitignoreURL = repoURL.appending(path: ".gitignore")
    try write("build", to: gitignoreURL)

    try workspace.initialize()
    try workspace.initialize()

    try #require(try read(gitignoreURL) == "build\n.compass/\n")
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
      candidates: "- Follow up",
      strategicContext: "Ship it"
    )

    try workspace.writeState(state)
    try #require(try workspace.readState() == state)

    try workspace.backupStateFile()
    try #require(FileManager.default.fileExists(atPath: workspace.stateBackupURL.path))
    let encodedState = try CompassWorkspace.encodeState(state)
    try #require(try read(workspace.stateBackupURL) == encodedState)
  }

  @Test func testBackupStateFileDoesNothingWhenStateIsMissing() throws {
    let workspace = try makeInitializedWorkspace()
    try FileManager.default.removeItem(at: workspace.stateURL)

    try workspace.backupStateFile()

    try #require(!FileManager.default.fileExists(atPath: workspace.stateBackupURL.path))
  }

  @Test func testAppendDraftAddsMarkdownBulletsAndSkipsEmptyText() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.appendDraft("  first draft  ")
    try #require(try read(workspace.draftsURL) == "- first draft\n")

    try workspace.appendDraft("second draft")
    try #require(
      try read(workspace.draftsURL) == "- first draft\n\n- second draft\n"
    )

    try workspace.appendDraft("   \n")
    try #require(try read(workspace.draftsURL) == "- first draft\n\n- second draft\n")
  }

  @Test func testAppendDraftSeparatorVariants() throws {
    let workspace = try makeInitializedWorkspace()

    try workspace.writeDrafts("- existing")
    try workspace.appendDraft("without trailing newline")
    try #require(try read(workspace.draftsURL) == "- existing\n\n- without trailing newline\n")

    try workspace.writeDrafts("- existing\n")
    try workspace.appendDraft("with one trailing newline")
    try #require(try read(workspace.draftsURL) == "- existing\n\n- with one trailing newline\n")

    try workspace.writeDrafts("- existing\n\n")
    try workspace.appendDraft("already separated")
    try #require(try read(workspace.draftsURL) == "- existing\n\n- already separated\n")
  }

  @Test func testSnapshotAndClearDraftsReturnsContentsClearsDraftsAndToleratesMissingFile() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeDrafts("- one\n\n- two\n")

    let snapshot = try workspace.snapshotAndClearDrafts()

    try #require(snapshot == "- one\n\n- two\n")
    try #require(try read(workspace.draftsURL) == "")
    try #require(
      !FileManager.default.fileExists(
        atPath: workspace.draftsURL.appendingPathExtension("snapshot").path))

    try FileManager.default.removeItem(at: workspace.draftsURL)
    try #require(try workspace.snapshotAndClearDrafts() == "")
    try #require(!FileManager.default.fileExists(atPath: workspace.draftsURL.path))
  }

  @Test func testApplyLessonEditsSupportsExactReplacementReplaceAllAndEmptyFindForEmptyLessons()
    throws
  {
    let workspace = try makeInitializedWorkspace()

    try #require(
      try workspace.applyLessonEdits([
        LessonEdit(find: "", replace: "- Start here\n", replaceAll: nil)
      ]) == 1
    )
    try #require(workspace.readLessons() == "- Start here\n")

    try #require(
      try workspace.applyLessonEdits([
        LessonEdit(find: "Start here", replace: "Keep this convention", replaceAll: nil)
      ]) == 1
    )
    try #require(workspace.readLessons() == "- Keep this convention\n")

    try workspace.writeLessons("- repeated\n- repeated\n")
    try #require(
      try workspace.applyLessonEdits([
        LessonEdit(find: "repeated", replace: "updated", replaceAll: true)
      ]) == 1
    )
    try #require(workspace.readLessons() == "- updated\n- updated\n")
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
    try #require(workspace.readLessons() == "- Existing\n")
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
    try #require(workspace.readLessons() == "- Existing\n")
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
    try #require(workspace.readLessons() == "- duplicate\n- duplicate\n")
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
    try #require(workspace.readLessons() == "- Existing\n")
  }

  @Test func testValidateSubmitResultLessonEditsDecodesPayloadWithoutApplying() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")
    let payload = """
      {"state":{"immediate":null,"candidates":[],"strategicContext":"x"},"lessonEdits":[{"find":"Missing","replace":"Replacement"}]}
      """

    try assertLessonEditFailure(
      try workspace.validateSubmitResultLessonEdits(Data(payload.utf8)),
      contains: "was not found"
    )
    try #require(workspace.readLessons() == "- Existing\n")
  }

  @Test func testValidateSubmitResultLessonEditsAcceptsSnakeCasePayloadWithoutApplying() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n- Existing\n")
    let payload = """
      {
        "state": {"immediate": null, "candidates": [], "strategicContext": "x"},
        "lesson_edits": [
          {
            "find": "Existing",
            "replace": "Replacement",
            "replace_all": "true"
          }
        ]
      }
      """

    try workspace.validateSubmitResultLessonEdits(Data(payload.utf8))
    try #require(workspace.readLessons() == "- Existing\n- Existing\n")
  }

  @Test func testValidateSubmitResultLessonEditsAcceptsEditFieldAliasesWithoutApplying() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n- Existing\n")
    let payload = """
      {
        "state": {"immediate": null, "candidates": [], "strategicContext": "x"},
        "lesson_edits": {
          "old_text": "Existing",
          "new_text": "Replacement",
          "global": "yes"
        }
      }
      """

    try workspace.validateSubmitResultLessonEdits(Data(payload.utf8))
    try #require(workspace.readLessons() == "- Existing\n- Existing\n")
  }

  @Test func testValidateSubmitResultLessonEditsAcceptsBenignEmptyString() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")
    let payload = """
      {"state":{"immediate":null,"candidates":[],"strategicContext":"x"},"lesson_edits":"no changes"}
      """

    try workspace.validateSubmitResultLessonEdits(Data(payload.utf8))
    try #require(workspace.readLessons() == "- Existing\n")
  }

  @Test func testValidateSubmitResultLessonEditsTreatsMissingFieldAsEmpty() throws {
    let workspace = try makeInitializedWorkspace()
    try workspace.writeLessons("- Existing\n")
    let payload = """
      {"state":{"immediate":null,"candidates":[],"strategicContext":"x"}}
      """

    try workspace.validateSubmitResultLessonEdits(Data(payload.utf8))
    try #require(workspace.readLessons() == "- Existing\n")
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
    candidates: String = "",
    strategicContext: String = ""
  ) -> PlanState {
    PlanState(
      completed: completed,
      immediate: immediate,
      candidates: candidates,
      strategicContext: strategicContext
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
    #expect(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    )
    #expect(!isDirectory.boolValue)
  }

  // swift-format-ignore: AlwaysUseLowerCamelCase
  private func AssertDirectoryExists(
    _ url: URL
  ) {
    var isDirectory: ObjCBool = false
    #expect(
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    )
    #expect(isDirectory.boolValue)
  }

  private func assertLessonEditFailure<T>(
    _ expression: @autoclosure () throws -> T,
    contains expectedText: String
  ) throws {
    do {
      _ = try expression()
      #expect(Bool(false), "Expected expression to throw")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      try #require(
        message.contains(expectedText),
        "Expected error containing `\(expectedText)`, got `\(message)`."
      )
    }
  }
}
