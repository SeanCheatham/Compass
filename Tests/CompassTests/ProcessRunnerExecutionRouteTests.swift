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

    func testContainerShellRouteAddsContainerEnvBeforeImageInSortedOrder() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerContainerEnv")
        try write(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app","containerEnv":{"ZETA":"last","ALPHA":"first"}}"#,
            to: devcontainerURL(in: repoURL)
        )
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
        XCTAssertEqual(invocation.arguments, [
            "run",
            "--rm",
            "--volume", "\(repoURL.standardizedFileURL.path):/workspace",
            "--workdir", "/workspace/app",
            "--env", "ALPHA=first",
            "--env", "ZETA=last",
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

    func testComposeDevcontainerShellRouteFallsBackToNativeWithSanitizedTokens() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerComposeFallback")
        try write(
            #"{"dockerComposeFile":"../compose.yml","service":"app","runServices":["db"]}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
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
        XCTAssertFalse(launchPlan.isContainerRoute)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test"])
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .composeBased)
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.supportTokens, [
            "compose",
            "composeFile:compose.yml",
            "service:app",
            "runServices:1",
            "runService:db"
        ])
        XCTAssertFalse(launchPlan.routeDetail().contains("../compose.yml"))
    }

    func testFeatureDevcontainerShellRouteFallsBackToNativeWithSanitizedTokens() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerFeatureFallback")
        let secretFeatureValue = "secret-feature-runner-value"
        try write(
            #"{"image":"swift:6.0","features":{"ghcr.io/devcontainers/features/node:1":{"version":"\#(secretFeatureValue)"}}}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
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
        XCTAssertFalse(launchPlan.isContainerRoute)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test"])
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .featureBased)
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.supportTokens, [
            "features:1",
            "featureOptions:1",
            "feature:node:1"
        ])
        XCTAssertFalse(launchPlan.routeDetail().contains(secretFeatureValue))
    }

    func testBuildDevcontainerShellRouteBuildsThenRunsLocalImage() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerBuildRoute")
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"verify","args":{"ZETA":"last","ALPHA":"first"}}}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let buildConfiguration = try XCTUnwrap(launchPlan.devcontainerSupportReport?.buildConfiguration)
        var capturedInvocations: [CodexExecutionInvocation] = []

        _ = try await ProcessRunner.runShell(
            "swift test",
            workingDirectory: repoURL,
            launchPlan: launchPlan,
            runner: { invocation, _, _, _, _ in
                capturedInvocations.append(invocation)
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        XCTAssertEqual(capturedInvocations.count, 2)
        let buildInvocation = capturedInvocations[0]
        let shellInvocation = capturedInvocations[1]
        XCTAssertTrue(launchPlan.isContainerRoute)
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .buildBased)
        XCTAssertEqual(buildInvocation.executable, "/usr/local/bin/container")
        XCTAssertEqual(buildConfiguration.buildArguments, [
            "build",
            "--tag", buildConfiguration.localImageTag,
            "--file", repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "Dockerfile")
                .standardizedFileURL
                .path,
            "--target", "verify",
            "--build-arg", "ALPHA=first",
            "--build-arg", "ZETA=last",
            repoURL.standardizedFileURL.path
        ])
        XCTAssertEqual(buildInvocation.arguments, buildConfiguration.buildArguments)
        XCTAssertEqual(shellInvocation.executable, "/usr/local/bin/container")
        XCTAssertEqual(shellInvocation.arguments, [
            "run",
            "--rm",
            "--volume", "\(repoURL.standardizedFileURL.path):/workspace",
            "--workdir", "/workspace",
            buildConfiguration.localImageTag,
            "sh",
            "-lc",
            "swift test"
        ])
    }

    func testBuildDevcontainerShellRouteFallsBackToNativeWhenBuildFails() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ProcessRunnerBuildFailure")
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"verify"}}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        var capturedInvocations: [CodexExecutionInvocation] = []

        let result = try await ProcessRunner.runShell(
            "swift test",
            workingDirectory: repoURL,
            launchPlan: launchPlan,
            runner: { invocation, _, _, _, _ in
                capturedInvocations.append(invocation)
                if capturedInvocations.count == 1 {
                    return ProcessResult(exitCode: 77, stdout: "ignored", stderr: "private failure")
                }
                return ProcessResult(exitCode: 0, stdout: "native-ok", stderr: "")
            }
        )

        XCTAssertEqual(result.stdout, "native-ok")
        XCTAssertEqual(capturedInvocations.count, 2)
        XCTAssertEqual(capturedInvocations[0].executable, "/usr/local/bin/container")
        XCTAssertEqual(capturedInvocations[1].executable, "/bin/zsh")
        XCTAssertEqual(capturedInvocations[1].arguments, ["-lc", "swift test"])
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
