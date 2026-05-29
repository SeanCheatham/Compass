import Foundation
import Testing

@testable import Compass

final class ProcessRunnerExecutionRouteTests {
  private var temporaryDirectories: [URL] = []

  func cleanup() {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test
  func testNativeShellRoutePreservesZshCommandConstruction() async throws {
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerNative")
    var capturedInvocation: AgentExecutionInvocation?

    let result = try await ProcessRunner.runShell(
      "swift test",
      workingDirectory: repoURL,
      timeout: 42,
      launchPlan: .host(),
      runner: { invocation, input, timeout, _, _ in
        capturedInvocation = invocation
        try #require(input == nil)
        try #require(timeout == 42)
        return ProcessResult(exitCode: 0, stdout: "ok", stderr: "")
      }
    )

    try #require(result.exitCode == 0)
    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    try #require(invocation.arguments == ["-lc", "swift test"])
    try #require(invocation.workingDirectory == repoURL.standardizedFileURL)
  }

  @Test
  func testSharedVMRouteForRunShellStaysOnHostBecauseVsockIsAgentLoopOnly() async throws {
    // `runShell` is used for one-shot out-of-agent commands (mutation
    // testing, post-Develop Verify). The agent-loop vsock transport
    // is connection-oriented, not a process the caller can spawn, and
    // the legacy SSH-into-guest branch never worked end-to-end (TCC
    // blocks sshd children from AppleVirtIOFS mounts). Verify runs
    // against the host worktree path — same files the agent acted on,
    // because AppModel.pullDevelopWorktreeIfNeeded copies the guest's
    // changes back to the host worktree at the end of each attempt.
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerSharedVMEnv")
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.20",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-BBB/worktree"
    )
    let launchPlan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    var capturedInvocation: AgentExecutionInvocation?

    _ = try await ProcessRunner.runShell(
      "swift test --filter CompassTests",
      workingDirectory: repoURL,
      launchPlan: launchPlan,
      runner: { invocation, _, _, _, _ in
        capturedInvocation = invocation
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    try #require(invocation.arguments == ["-lc", "swift test --filter CompassTests"])
    try #require(invocation.workingDirectory == repoURL.standardizedFileURL)
  }

  @Test
  func testNativeFallbackPlanFeedsNativeVerifyInvocationAndBoundedDiagnostics() async throws {
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMUnavailableFallback")
    let launchPlan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .unavailable(reason: "Apple Silicon required")
    )
    var capturedInvocation: AgentExecutionInvocation?

    _ = try await ProcessRunner.runShell(
      "swift test",
      workingDirectory: repoURL,
      launchPlan: launchPlan,
      runner: { invocation, _, _, _, _ in
        capturedInvocation = invocation
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    try #require(invocation.arguments == ["-lc", "swift test"])
    try #require(launchPlan.fallbackReason?.contains("Apple Silicon required") == true)
    try #require(
      !launchPlan.preflightSummary(phase: "Verify").contains(repoURL.standardizedFileURL.path))
  }

  @Test
  func testComposeDevcontainerShellRouteFallsBackToNativeWithSanitizedTokens() async throws {
    // Scenario name preserved: VM not provisioned → host fallback for runShell.
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMNotProvisioned")
    let launchPlan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .notProvisioned
    )
    var capturedInvocation: AgentExecutionInvocation?

    _ = try await ProcessRunner.runShell(
      "swift test",
      workingDirectory: repoURL,
      launchPlan: launchPlan,
      runner: { invocation, _, _, _, _ in
        capturedInvocation = invocation
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    let invocation = try #require(capturedInvocation)
    try #require(!launchPlan.isVMRoute)
    try #require(invocation.executable == "/bin/zsh")
    try #require(invocation.arguments == ["-lc", "swift test"])
    try #require(launchPlan.fallbackReason?.contains("not been provisioned") == true)
  }

  @Test
  func testFeatureDevcontainerShellRouteFallsBackToNativeWithSanitizedTokens() async throws {
    // Scenario name preserved: VM installing → host fallback.
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMInstalling")
    let launchPlan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .installing(fractionCompleted: 0.3)
    )
    var capturedInvocation: AgentExecutionInvocation?

    _ = try await ProcessRunner.runShell(
      "swift test",
      workingDirectory: repoURL,
      launchPlan: launchPlan,
      runner: { invocation, _, _, _, _ in
        capturedInvocation = invocation
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    let invocation = try #require(capturedInvocation)
    try #require(!launchPlan.isVMRoute)
    try #require(invocation.executable == "/bin/zsh")
    try #require(launchPlan.fallbackReason?.contains("installing") == true)
  }

  @Test
  func testReadySharedVMRouteForRunShellStillUsesHostZshOneShot() async throws {
    // Even with a ready sharedVM route + workspace-mapped route, the
    // runShell invocation stays local — see the env-route test above
    // for why. One invocation, host /bin/zsh, no remote shell hops.
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerSharedVMRunsRemote")
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.30",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-CCC/worktree"
    )
    let launchPlan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    var captured: [AgentExecutionInvocation] = []

    _ = try await ProcessRunner.runShell(
      "swift test --filter CompassTests",
      workingDirectory: repoURL,
      launchPlan: launchPlan,
      runner: { invocation, _, _, _, _ in
        captured.append(invocation)
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    try #require(captured.count == 1)
    let invocation = try #require(captured.first)
    try #require(invocation.executable == "/bin/zsh")
    try #require(invocation.arguments == ["-lc", "swift test --filter CompassTests"])
  }

  @Test
  func testBuildDevcontainerShellRouteFallsBackToNativeWhenBuildFails() async throws {
    // Scenario name preserved: error readiness → host fallback.
    let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMErrorFallback")
    let launchPlan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .error(detail: "boot failed 3x")
    )
    var capturedInvocation: AgentExecutionInvocation?

    _ = try await ProcessRunner.runShell(
      "swift test",
      workingDirectory: repoURL,
      launchPlan: launchPlan,
      runner: { invocation, _, _, _, _ in
        capturedInvocation = invocation
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    let invocation = try #require(capturedInvocation)
    try #require(invocation.executable == "/bin/zsh")
    try #require(launchPlan.fallbackReason?.contains("boot failed") == true)
  }

  // MARK: - Helpers

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url.standardizedFileURL
  }
}
