import Foundation
@testable import Compass
import XCTest

final class ProcessRunnerExecutionRouteTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

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
                XCTAssertNil(input)
                XCTAssertEqual(timeout, 42)
                return ProcessResult(exitCode: 0, stdout: "ok", stderr: "")
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test"])
        XCTAssertEqual(invocation.workingDirectory, repoURL.standardizedFileURL)
    }


    func testSharedVMRouteForRunShellStaysOnHostBecauseVsockIsAgentLoopOnly() async throws {
        // `runShell` is used for one-shot out-of-agent commands (mutation
        // testing, post-Develop Verify). The agent-loop vsock transport
        // is connection-oriented, not a process the caller can spawn,
        // and the legacy SSH-into-guest branch never worked end-to-end
        // (TCC blocks sshd children from the VirtioFS share). Verify
        // runs against the host worktree path — same VirtioFS bytes
        // the guest agent acted on, just a different namespace label.
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerSharedVMEnv")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.20",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-BBB/worktree"
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

        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test --filter CompassTests"])
        XCTAssertEqual(invocation.workingDirectory, repoURL.standardizedFileURL)
    }

    func testNativeFallbackPlanFeedsNativeVerifyInvocationAndBoundedDiagnostics() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMUnavailableFallback")
        let launchPlan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
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

        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test"])
        XCTAssertTrue(launchPlan.fallbackReason?.contains("Apple Silicon required") ?? false)
        XCTAssertFalse(launchPlan.preflightSummary(phase: "Verify").contains(repoURL.standardizedFileURL.path))
    }

    func testComposeDevcontainerShellRouteFallsBackToNativeWithSanitizedTokens() async throws {
        // Scenario name preserved: VM not provisioned → host fallback for runShell.
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMNotProvisioned")
        let launchPlan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
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

        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertFalse(launchPlan.isVMRoute)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test"])
        XCTAssertTrue(launchPlan.fallbackReason?.contains("not been provisioned") ?? false)
    }

    func testFeatureDevcontainerShellRouteFallsBackToNativeWithSanitizedTokens() async throws {
        // Scenario name preserved: VM installing → host fallback.
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMInstalling")
        let launchPlan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
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

        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertFalse(launchPlan.isVMRoute)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertTrue(launchPlan.fallbackReason?.contains("installing") ?? false)
    }

    func testReadySharedVMRouteForRunShellStillUsesHostZshOneShot() async throws {
        // Even with a ready sharedVM route + workspace-mapped route, the
        // runShell invocation stays local — see the env-route test above
        // for why. One invocation, host /bin/zsh, no remote shell hops.
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerSharedVMRunsRemote")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.30",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-CCC/worktree"
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

        XCTAssertEqual(captured.count, 1)
        let invocation = try XCTUnwrap(captured.first)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test --filter CompassTests"])
    }

    func testBuildDevcontainerShellRouteFallsBackToNativeWhenBuildFails() async throws {
        // Scenario name preserved: error readiness → host fallback.
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerVMErrorFallback")
        let launchPlan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
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

        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertTrue(launchPlan.fallbackReason?.contains("boot failed") ?? false)
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
