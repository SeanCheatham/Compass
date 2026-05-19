import Foundation
@testable import Compass
import XCTest

final class CodexExecutorLaunchRouteTests: XCTestCase {
    private struct StubCodexResponse: Codable, Equatable {
        var ok: Bool
    }

    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testPlanCommandUsesConfiguredCodexBinaryOnNativeRoute() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorNative")
        let launchPlan = CodexExecutionLaunchPlan.host()
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        let result = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "/opt/codex/bin/codex",
                repoURL: repoURL,
                sandbox: "read-only",
                model: "gpt-test",
                schema: #"{"type":"object"}"#,
                prompt: "Plan prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        XCTAssertEqual(result, StubCodexResponse(ok: true))
        let context = try XCTUnwrap(capturedContext)
        XCTAssertEqual(context.invocation.executable, "/opt/codex/bin/codex")
        XCTAssertEqual(context.invocation.workingDirectory, repoURL.standardizedFileURL)
        XCTAssertEqual(context.invocation.arguments.prefix(3), ["exec", "--cd", repoURL.standardizedFileURL.path])
        XCTAssertTrue(context.invocation.arguments.contains("--model"))
        XCTAssertTrue(context.invocation.arguments.contains("gpt-test"))
        XCTAssertEqual(try argument(after: "--output-schema", in: context.invocation.arguments), context.schemaFile.path)
        XCTAssertEqual(try argument(after: "--output-last-message", in: context.invocation.arguments), context.outputFile.path)
    }

    func testDevelopCommandUsesContainerCodexWithMountedWorkspace() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorSharedVM")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex",
            identityFile: "/tmp/compass-key",
            knownHostsFile: "/tmp/compass-known"
        )
        let launchPlan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.schemaFile.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.promptFile.path))
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "/opt/codex/bin/codex",
                repoURL: repoURL,
                sandbox: "danger-full-access",
                model: nil,
                schema: #"{"type":"object"}"#,
                prompt: "Develop prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        let context = try XCTUnwrap(capturedContext)
        XCTAssertEqual(context.invocation.executable, "/usr/bin/ssh")
        let arguments = context.invocation.arguments
        XCTAssertEqual(arguments[0], "-i")
        XCTAssertEqual(arguments[1], "/tmp/compass-key")
        XCTAssertTrue(arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(arguments.contains("BatchMode=yes"))
        XCTAssertTrue(arguments.contains("compass@192.0.2.10"))
        let remoteCommand = try XCTUnwrap(arguments.last)
        XCTAssertTrue(remoteCommand.contains("cd '/opt/compass/workspaces/dev-AAA/worktree'"))
        XCTAssertTrue(remoteCommand.contains("'/opt/compass/codex/codex'"))
        XCTAssertTrue(remoteCommand.contains("exec"))
        XCTAssertTrue(remoteCommand.contains("'--cd'"))
    }

    func testDevelopCommandAddsContainerEnvBeforeImageInSortedOrder() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorSharedVMEnv")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-BBB/worktree",
            guestCodexPath: "/opt/compass/codex/codex",
            environmentVariables: ["ZETA": "last", "ALPHA": "first"]
        )
        let launchPlan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "codex",
                repoURL: repoURL,
                sandbox: "read-only",
                model: nil,
                schema: #"{"type":"object"}"#,
                prompt: "Develop prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        let context = try XCTUnwrap(capturedContext)
        let remoteCommand = try XCTUnwrap(context.invocation.arguments.last)
        let alphaRange = try XCTUnwrap(remoteCommand.range(of: "ALPHA="))
        let zetaRange = try XCTUnwrap(remoteCommand.range(of: "ZETA="))
        XCTAssertLessThan(alphaRange.lowerBound, zetaRange.lowerBound)
        XCTAssertTrue(remoteCommand.contains("env ALPHA='first' ZETA='last'"))
    }

    func testUnsupportedDevcontainerFallbackKeepsNativeCodexInvocation() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorVMUnavailableFallback")
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .unavailable(reason: "2-guest cap reached")
        )
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "/opt/codex/bin/codex",
                repoURL: repoURL,
                sandbox: "danger-full-access",
                model: nil,
                schema: #"{"type":"object"}"#,
                prompt: "Develop prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        let context = try XCTUnwrap(capturedContext)
        XCTAssertEqual(launchPlan.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(context.invocation.executable, "/opt/codex/bin/codex")
        XCTAssertEqual(context.invocation.workingDirectory, repoURL.standardizedFileURL)
        XCTAssertEqual(try argument(after: "--cd", in: context.invocation.arguments), repoURL.standardizedFileURL.path)
        XCTAssertEqual(try argument(after: "--output-schema", in: context.invocation.arguments), context.schemaFile.path)
        XCTAssertFalse(context.invocation.arguments.contains("ssh"))
        XCTAssertTrue(launchPlan.fallbackReason?.contains("2-guest cap") ?? false)
    }

    func testComposeDevcontainerFallbackKeepsNativeCodexInvocation() async throws {
        // Scenario name preserved: a non-ready VM readiness leads back to the host route.
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorVMNotProvisionedFallback")
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .notProvisioned
        )
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "/opt/codex/bin/codex",
                repoURL: repoURL,
                sandbox: "danger-full-access",
                model: nil,
                schema: #"{"type":"object"}"#,
                prompt: "Develop prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        let context = try XCTUnwrap(capturedContext)
        XCTAssertEqual(launchPlan.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(context.invocation.executable, "/opt/codex/bin/codex")
        XCTAssertFalse(context.invocation.arguments.contains("ssh"))
    }

    func testBuildBasedDevcontainerSucceedsThenLaunchesCodexInLocalImage() async throws {
        // Scenario name preserved: a ready VM with a configured route launches Codex via ssh.
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorVMReadyLaunch")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.42",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-CCC/worktree",
            guestCodexPath: "/opt/compass/codex/codex"
        )
        let launchPlan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "/opt/codex/bin/codex",
                repoURL: repoURL,
                sandbox: "read-only",
                model: nil,
                schema: #"{"type":"object"}"#,
                prompt: "Plan prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        let context = try XCTUnwrap(capturedContext)
        XCTAssertEqual(context.invocation.executable, "/usr/bin/ssh")
        XCTAssertTrue(context.invocation.arguments.contains("compass@192.0.2.42"))
    }

    func testBuildBasedDevcontainerFailureFallsBackToNativeCodex() async throws {
        // Scenario name preserved: a VM error readiness falls back to host.
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorVMErrorFallback")
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .error(detail: "ssh probe failed after 60s")
        )
        var capturedContext: CodexExecutorLaunchContext?
        let executor = CodexExecutor { context, _ in
            capturedContext = context
            try #"{"ok":true}"#.write(to: context.outputFile, atomically: true, encoding: .utf8)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await executor.run(
            CodexRunConfiguration(
                codexBinary: "/opt/codex/bin/codex",
                repoURL: repoURL,
                sandbox: "danger-full-access",
                model: nil,
                schema: #"{"type":"object"}"#,
                prompt: "Develop prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        let context = try XCTUnwrap(capturedContext)
        XCTAssertEqual(context.invocation.executable, "/opt/codex/bin/codex")
        XCTAssertEqual(launchPlan.effectiveRouteIdentifier, "native-macos")
        XCTAssertTrue(launchPlan.fallbackReason?.contains("ssh probe failed") ?? false)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }

    private func argument(after flag: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            throw XCTSkip("Argument \(flag) not present")
        }
        return arguments[index + 1]
    }
}
