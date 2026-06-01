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
