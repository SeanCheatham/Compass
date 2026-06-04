import Foundation
import Testing

@testable import Compass

struct RustDesktopVisualVerifierTests {
  @Test func discoveryRecognizesPresentScaffold() throws {
    let result = ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
    try #require(RustDesktopVisualVerification.isPresent(result))
  }

  @Test func discoveryRejectsMissingScaffold() throws {
    let result = ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
    try #require(!RustDesktopVisualVerification.isPresent(result))
  }

  @Test func parsesScreenshotDataBetweenMarkers() throws {
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let encoded = bytes.base64EncodedString()
    let output = """
      before
      \(RustDesktopVisualVerification.screenshotBeginMarker)
      \(encoded)
      \(RustDesktopVisualVerification.screenshotEndMarker)
      after
      """

    try #require(RustDesktopVisualVerification.screenshotData(from: output) == bytes)
  }

  @Test func redactsScreenshotBase64FromLogs() throws {
    let output = """
      \(RustDesktopVisualVerification.screenshotBeginMarker)
      abc123
      \(RustDesktopVisualVerification.screenshotEndMarker)
      """

    let redacted = RustDesktopVisualVerification.redactedOutput(output)
    try #require(!redacted.contains("abc123"))
    try #require(redacted.contains("<base64 screenshot omitted>"))
  }

  @Test func parsesEngineScreenshotPath() throws {
    let output = """
      {"schema_version":1,"command":"visual-verify","ok":true,"data":{"ok":true,"screenshot_path":".compass/visual-verify/latest.png","log_tail":"ok"},"errors":[]}
      """

    #expect(
      RustDesktopVisualVerification.engineScreenshotPath(from: output)
        == ".compass/visual-verify/latest.png"
    )
  }

  @MainActor
  @Test func blessedDesktopScaffoldRequiresSharedVMRoute() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try RustProjectScaffold.write(to: root)

    let project = CompassProject(repoURL: root)
    let issues = await project.runRustDesktopVisualVerificationIfAvailable(
      workingDirectory: root,
      launchPlan: .host(),
      sessionIndex: 0,
      attempt: 1
    )

    try #require(issues == [RustDesktopVisualVerification.requiresSharedVMRouteIssue])
  }

  @MainActor
  @Test func sharedVMVerifyWithoutLiveMachineDoesNotFallbackToHost() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.44",
      hostWorktreeURL: root,
      guestWorkspacePath: "/Users/compass/Compass/Repos/test/worktree"
    )
    let launchPlan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let project = CompassProject(repoURL: root)

    let result = try await project.runVerifyCommand(
      command: "echo should-not-run-on-host",
      hostWorkingDirectory: root,
      timeoutSeconds: 1,
      launchPlan: launchPlan,
      hostRunner: { _, _, _, _, _ in
        Issue.record("Shared VM Verify fell back to the host runner")
        return ProcessResult(exitCode: 0, stdout: "host", stderr: "")
      }
    )

    try #require(result.exitCode == 73)
    try #require(result.stderr.contains("Refusing to run the guest-local command on the host"))
  }
}
