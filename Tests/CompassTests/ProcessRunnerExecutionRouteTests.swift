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
        var capturedInvocation: CodexExecutionInvocation?

        let result = try await ProcessRunner.runShell(
            "swift test",
            workingDirectory: repoURL,
            timeout: 42,
            launchPlan: .native(),
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

    func testContainerShellRouteUsesAppleContainerRunVolumeAndWorkspace() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerContainer")
        try write(#"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#, to: devcontainerURL(in: repoURL))
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        var capturedInvocation: CodexExecutionInvocation?

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
        XCTAssertEqual(invocation.executable, "/usr/local/bin/container")
        XCTAssertEqual(invocation.workingDirectory, repoURL.standardizedFileURL)
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .imageRouteable)
        XCTAssertEqual(invocation.arguments, [
            "run",
            "--rm",
            "--volume", "\(repoURL.standardizedFileURL.path):/workspace",
            "--workdir", "/workspace/app",
            "swift:6.0",
            "sh",
            "-lc",
            "swift test --filter CompassTests"
        ])
    }

    func testNativeFallbackPlanFeedsNativeVerifyInvocationAndBoundedDiagnostics() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerFallback")
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in nil }
        )
        var capturedInvocation: CodexExecutionInvocation?

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
        XCTAssertEqual(launchPlan.fallbackReason, "No .devcontainer/devcontainer.json was found.")
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .missing)
        XCTAssertFalse(launchPlan.preflightSummary(phase: "Verify").contains(repoURL.standardizedFileURL.path))
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }

    private func devcontainerURL(in repoURL: URL) -> URL {
        repoURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
