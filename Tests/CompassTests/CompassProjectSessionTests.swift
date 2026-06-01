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
}
