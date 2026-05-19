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
        let launchPlan = CodexExecutionLaunchPlan.native()
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
        XCTAssertFalse(context.invocation.arguments.contains("container"))
        XCTAssertEqual(try argument(after: "--output-schema", in: context.invocation.arguments), context.schemaFile.path)
        XCTAssertEqual(try argument(after: "--output-last-message", in: context.invocation.arguments), context.outputFile.path)
    }

    func testDevelopCommandUsesContainerCodexWithMountedWorkspace() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorContainer")
        try write(#"{"image":"swift:6.0"}"#, to: devcontainerURL(in: repoURL))
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
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
        let expectedPrefix = [
            "run",
            "--rm",
            "--volume", "\(repoURL.standardizedFileURL.path):/workspace",
            "--workdir", "/workspace",
            "swift:6.0",
            "codex",
            "exec",
            "--cd", "/workspace"
        ]
        XCTAssertEqual(Array(context.invocation.arguments.prefix(expectedPrefix.count)), expectedPrefix)
        XCTAssertEqual(context.invocation.executable, "/usr/local/bin/container")
        XCTAssertFalse(context.invocation.arguments.contains("/opt/codex/bin/codex"))
        XCTAssertTrue(try argument(after: "--output-schema", in: context.invocation.arguments).hasPrefix("/workspace/.compass-codex-run-"))
        XCTAssertTrue(try argument(after: "--output-last-message", in: context.invocation.arguments).hasPrefix("/workspace/.compass-codex-run-"))
    }

    func testDevelopCommandAddsContainerEnvBeforeImageInSortedOrder() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorContainerEnv")
        try write(
            #"{"image":"swift:6.0","containerEnv":{"ZETA":"last","ALPHA":"first"}}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
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
        let imageIndex = try XCTUnwrap(context.invocation.arguments.firstIndex(of: "swift:6.0"))
        XCTAssertEqual(Array(context.invocation.arguments.prefix(imageIndex)), [
            "run",
            "--rm",
            "--volume", "\(repoURL.standardizedFileURL.path):/workspace",
            "--workdir", "/workspace",
            "--env", "ALPHA=first",
            "--env", "ZETA=last"
        ])
        XCTAssertEqual(context.invocation.arguments[imageIndex + 1], "codex")
    }

    func testUnsupportedDevcontainerFallbackKeepsNativeCodexInvocation() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorUnsupportedFallback")
        try write(
            #"{"features":{"ghcr.io/devcontainers/features/git:1":{}}}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
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
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .featureBased)
        XCTAssertEqual(context.invocation.executable, "/opt/codex/bin/codex")
        XCTAssertEqual(context.invocation.workingDirectory, repoURL.standardizedFileURL)
        XCTAssertEqual(try argument(after: "--cd", in: context.invocation.arguments), repoURL.standardizedFileURL.path)
        XCTAssertEqual(try argument(after: "--output-schema", in: context.invocation.arguments), context.schemaFile.path)
        XCTAssertFalse(context.invocation.arguments.contains("container"))
    }

    func testBuildDevcontainerConfigurationKeepsCodexInvocationNativeForNow() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorBuildFallback")
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"develop"}}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
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
        XCTAssertNotNil(launchPlan.devcontainerSupportReport?.buildConfiguration)
        XCTAssertEqual(launchPlan.devcontainerSupportReport?.classification, .buildBased)
        XCTAssertEqual(context.invocation.executable, "/opt/codex/bin/codex")
        XCTAssertEqual(try argument(after: "--cd", in: context.invocation.arguments), repoURL.standardizedFileURL.path)
        XCTAssertFalse(context.invocation.arguments.contains("container"))
    }

    func testContainerCommandUsesWorkspaceFolderForCodexCd() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutorWorkspace")
        try write(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#,
            to: devcontainerURL(in: repoURL)
        )
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        var capturedArguments: [String] = []
        let executor = CodexExecutor { context, _ in
            capturedArguments = context.invocation.arguments
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
                prompt: "Reflect prompt",
                launchPlan: launchPlan
            ),
            decode: StubCodexResponse.self,
            onEvent: { _ in }
        )

        XCTAssertEqual(try argument(after: "--workdir", in: capturedArguments), "/workspace/app")
        XCTAssertEqual(try argument(after: "--cd", in: capturedArguments), "/workspace/app")
    }

    private func argument(after flag: String, in arguments: [String]) throws -> String {
        let index = try XCTUnwrap(arguments.firstIndex(of: flag))
        let valueIndex = arguments.index(after: index)
        XCTAssertLessThan(valueIndex, arguments.endIndex)
        return arguments[valueIndex]
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
