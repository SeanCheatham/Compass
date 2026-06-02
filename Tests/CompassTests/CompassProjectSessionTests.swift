import Foundation
import Testing

@testable import Compass

@MainActor
struct CompassProjectSessionTests {
  @Test func testRejectedPlanCleanupRecordsRejectedByPlanStatus() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let sessionIndex = project.startSession()

    project.performSessionErrorCleanup(
      sessionIndex: sessionIndex,
      error: AppModelError.rejectedPlan("Verify command must collect test coverage.")
    )

    try #require(project.sessions[sessionIndex].status == .rejectedByPlan)
    try #require(
      project.sessions[sessionIndex].notes == [
        "Verify command must collect test coverage."
      ])
    try #require(project.phase == .failed)
    try #require(project.errorMessage == "Verify command must collect test coverage.")
    try #require(!project.isRunning)
  }

  @Test func testGenericErrorCleanupStillRecordsFailedStatus() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let sessionIndex = project.startSession()

    project.performSessionErrorCleanup(
      sessionIndex: sessionIndex,
      error: AppModelError.internalInvariant("Unexpected failure.")
    )

    try #require(project.sessions[sessionIndex].status == .failed)
    try #require(project.sessions[sessionIndex].notes == ["Unexpected failure."])
    try #require(project.phase == .failed)
    try #require(project.errorMessage == "Unexpected failure.")
  }

  @Test func testSessionLifecycleWritesAuditManifestAndEvents() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let sessionIndex = project.startSession()

    project.log("Captured live message.", level: .info)
    project.appendSessionNote("Captured session note.", to: sessionIndex)
    project.endSession(sessionIndex, status: .succeeded)

    let workspace = CompassWorkspace(repoURL: repoURL)
    let session = project.sessions[sessionIndex].session
    let manifest = try #require(workspace.readSessionAuditManifest(session: session))
    let events = try String(
      contentsOf: workspace.sessionAuditEventsURL(session: session),
      encoding: .utf8
    )

    try #require(manifest.status == .succeeded)
    try #require(manifest.startedAt == project.sessions[sessionIndex].startedAt)
    try #require(manifest.endedAt == project.sessions[sessionIndex].endedAt)
    try #require(events.contains(#""kind":"session_started""#))
    try #require(events.contains(#""kind":"live_line""#))
    try #require(events.contains("Captured live message."))
    try #require(events.contains(#""kind":"session_note""#))
    try #require(events.contains("Captured session note."))
    try #require(events.contains(#""kind":"session_ended""#))
  }

  @Test func testVerifyAuditOutputWritesFullArtifactAndEvents() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let sessionIndex = project.startSession()

    project.recordVerifyAuditOutput(
      command: "swift test --filter ExampleTests",
      result: ProcessResult(exitCode: 1, stdout: "stdout body\n", stderr: "stderr body\n"),
      sessionIndex: sessionIndex,
      attempt: 1,
      durationMs: 42
    )

    let workspace = CompassWorkspace(repoURL: repoURL)
    let session = project.sessions[sessionIndex].session
    let manifest = try #require(workspace.readSessionAuditManifest(session: session))
    let artifact = try #require(manifest.artifacts.first)
    let artifactURL = workspace.compassURL.appending(path: artifact.path)
    let artifactText = try String(contentsOf: artifactURL, encoding: .utf8)
    let events = try String(
      contentsOf: workspace.sessionAuditEventsURL(session: session),
      encoding: .utf8
    )

    try #require(artifact.kind == "verify_output")
    try #require(artifact.path == "sessions/000001/verify-attempt-1-full.log")
    try #require(artifactText.contains("swift test --filter ExampleTests"))
    try #require(artifactText.contains("stdout body"))
    try #require(artifactText.contains("stderr body"))
    try #require(events.contains(#""kind":"verify_output_saved""#))
    try #require(events.contains(#""kind":"verify_result""#))
    try #require(events.contains(#""exitCode":"1""#))
    try #require(events.contains(#""durationMs":"42""#))
  }

  @Test func testPostChecksHandVerifyBypassBackToPlan() async throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let sessionIndex = project.startSession()

    let result = try await project.runPostChecks(
      next: PlanNext(
        plan: """
          ## Outcome
          Keep bypassed Verify from landing.

          ## Acceptance checks
          - Plan receives the verify-command problem.
          """,
        verify: "swift test --filter RemovedSuite"
      ),
      summary: DevelopSummary(
        status: .succeeded,
        summary: "Implemented the slice; the planned verify command targets a removed suite.",
        feedback: """
          Verify command is wrong because RemovedSuite no longer exists; \
          next Plan should replace it with the current safety tests.
          """,
        bypassVerify: true
      ),
      workingDirectory: repoURL,
      launchPlan: .host(),
      sessionIndex: sessionIndex,
      attempt: 1,
      beforeSha: nil
    )

    try #require(!result.ok)
    try #require(result.requiresPlanRepair)
    try #require(result.verifyOutput == nil)
    try #require(result.gitStatusIssues.isEmpty)
    let issue = try #require(result.verifyIssues.first)
    try #require(issue.contains("Verify was skipped"))
    try #require(issue.contains("swift test --filter RemovedSuite"))
    try #require(issue.contains("Plan should replace the verify command"))
  }
}
