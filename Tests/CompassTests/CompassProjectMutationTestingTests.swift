import Foundation
@testable import Compass
import XCTest

@MainActor
final class CompassProjectMutationTestingTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSuccessfulExecutionUsesInjectedRunnerAndPersistsMutationRecord() async throws {
        let repoURL = try await makeTemporaryGitRepository(prefix: "CompassProjectMutationSuccess")
        let state = makeState(verify: "swift test --filter CompassProjectMutationTestingTests")
        let workspace = try initializedWorkspace(repoURL: repoURL, state: state)
        try workspace.writeLessons("- keep mutation execution records sanitized\n")
        var capturedInvocation: CodexExecutionInvocation?
        let project = CompassProject(
            repoURL: repoURL,
            mutationTestingRunner: { invocation, input, timeout, _, _ in
                capturedInvocation = invocation
                XCTAssertNil(input)
                XCTAssertEqual(timeout, 120)
                return ProcessResult(exitCode: 0, stdout: "mutation ok\n", stderr: "")
            }
        )
        await project.refresh()
        project.languageProfile = profile(.swift)

        await project.runMutationTesting()

        let invocation = try XCTUnwrap(capturedInvocation)
        XCTAssertEqual(invocation.executable, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-lc", "swift test --filter CompassProjectMutationTestingTests"])
        XCTAssertEqual(invocation.workingDirectory, repoURL.standardizedFileURL)
        XCTAssertFalse(project.isRunning)
        XCTAssertEqual(project.phase, .succeeded)
        XCTAssertEqual(try workspace.readState(), state)
        XCTAssertEqual(workspace.readLessons(), "- keep mutation execution records sanitized\n")

        let session = try XCTUnwrap(workspace.readSessions().first)
        XCTAssertEqual(session.status, .succeeded)
        XCTAssertNil(session.verifyOutput)
        XCTAssertNil(session.verify)
        XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.phaseIdentifier, "mutation")
        XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.effectiveRouteIdentifier, "native-macos")

        let execution = try XCTUnwrap(session.mutationTestingExecutions.first)
        XCTAssertEqual(execution.statusIdentifier, "succeeded")
        XCTAssertEqual(execution.routeIdentifier, "native-route")
        XCTAssertEqual(execution.languageIdentifier, "swift")
        XCTAssertEqual(execution.seedCommandLabel, "swift test --filter CompassProjectMutationTestingTests")
        XCTAssertEqual(execution.exitCode, 0)
        XCTAssertEqual(execution.outputTail, "mutation ok")
        XCTAssertGreaterThanOrEqual(execution.endedAt, execution.startedAt)

        let recovery = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationRecoveryDescriptor)
        XCTAssertEqual(recovery.stateIdentifier, "succeeded")
        XCTAssertFalse(recovery.isActive)
        XCTAssertTrue(project.runtimeDiagnosticsMenu.copyDiagnosticsAction.copyText.contains("mutation-recovery-state: succeeded"))
    }

    func testFailingExecutionRecordsBoundedRedactedMetadataWithoutLeakingRuntimeValues() async throws {
        let repoURL = try await makeTemporaryGitRepository(prefix: "CompassProjectMutationFailure")
        let secretEnv = "secret-mutation-container-env"
        let secretBuildArg = "secret-mutation-build-arg"
        let secretFeatureValue = "secret-mutation-feature-option"
        let secretNestedValue = "secret-mutation-nested-option"
        let absoluteComposePath = "/Users/private/project/compose.override.yml"
        let containerToolPath = "/private/tooling/container"
        try write(
            """
            {
              "image": "swift:6.0",
              "containerEnv": { "TOKEN": "\(secretEnv)" },
              "build": { "dockerfile": "Dockerfile", "context": "..", "args": { "TOKEN": "\(secretBuildArg)" } },
              "features": {
                "ghcr.io/devcontainers/features/node:1": {
                  "version": "\(secretFeatureValue)",
                  "nested": { "token": "\(secretNestedValue)" }
                }
              },
              "dockerComposeFile": ["../compose.yml", "\(absoluteComposePath)"],
              "service": "api",
              "runServices": ["db"]
            }
            """,
            to: devcontainerURL(in: repoURL)
        )
        let rawVerify = [
            "swift test",
            repoURL.path,
            secretEnv,
            secretBuildArg,
            secretFeatureValue,
            secretNestedValue,
            absoluteComposePath,
            containerToolPath,
            ".devcontainer/devcontainer.json"
        ].joined(separator: " ")
        let state = makeState(verify: rawVerify)
        let workspace = try initializedWorkspace(repoURL: repoURL, state: state)
        let project = CompassProject(
            repoURL: repoURL,
            codexExecutionEnvironmentPreference: .devcontainerPreferred,
            containerToolResolver: { _ in containerToolPath },
            mutationTestingRunner: { _, _, _, _, _ in
                ProcessResult(
                    exitCode: 23,
                    stdout: """
                    failed in \(repoURL.path)
                    env \(secretEnv)
                    arg \(secretBuildArg)
                    feature \(secretFeatureValue)
                    nested \(secretNestedValue)
                    compose ../compose.yml \(absoluteComposePath)
                    config .devcontainer/devcontainer.json
                    tool \(containerToolPath)
                    \(String(repeating: "x", count: 2_400))
                    """,
                    stderr: ""
                )
            }
        )
        await project.refresh()
        project.languageProfile = profile(.swift)

        await project.runMutationTesting()

        let session = try XCTUnwrap(workspace.readSessions().first)
        XCTAssertEqual(session.status, .failed)
        XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.phaseIdentifier, "mutation")
        XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.supportClassificationIdentifier, "compose-based")

        let execution = try XCTUnwrap(session.mutationTestingExecutions.first)
        XCTAssertEqual(execution.statusIdentifier, "failed")
        XCTAssertEqual(execution.routeIdentifier, "native-fallback")
        XCTAssertEqual(execution.exitCode, 23)
        XCTAssertLessThanOrEqual(execution.outputTail.count, SessionMutationTestingExecution.outputTailLimit)
        XCTAssertLessThanOrEqual(execution.seedCommandLabel.count, CodexMutationTestingPlan.commandMaxCharacters)

        let persistedText = try read(workspace.sessionsRecordURL)
        let exposedText = [persistedText, execution.outputTail, execution.seedCommandLabel].joined(separator: "\n")
        for leaked in [
            repoURL.standardizedFileURL.path,
            secretEnv,
            secretBuildArg,
            secretFeatureValue,
            secretNestedValue,
            absoluteComposePath,
            containerToolPath,
            ".devcontainer/devcontainer.json",
            "../compose.yml",
            "ghcr.io/devcontainers/features/node:1"
        ] {
            XCTAssertFalse(exposedText.contains(leaked), "Leaked \(leaked)")
        }

        let recovery = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationRecoveryDescriptor)
        XCTAssertEqual(recovery.stateIdentifier, "active")
        XCTAssertTrue(recovery.isActive)
        XCTAssertEqual(recovery.reviewActionLabel, "Review Mutation")
        let runtimeCopy = project.runtimeDiagnosticsMenu.copyDiagnosticsAction.copyText
        XCTAssertTrue(runtimeCopy.contains("mutation-recovery-state: active"))
        XCTAssertFalse(runtimeCopy.contains(repoURL.standardizedFileURL.path))
        XCTAssertFalse(runtimeCopy.contains(secretEnv))
    }

    func testReadinessBlockingDoesNotStartRunnerOrMutateSessions() async throws {
        let repoURL = try await makeTemporaryGitRepository(prefix: "CompassProjectMutationBlocked")
        let state = PlanState(completed: [], immediate: nil, midTerm: "", longTerm: "")
        let workspace = try initializedWorkspace(repoURL: repoURL, state: state)
        let project = CompassProject(
            repoURL: repoURL,
            mutationTestingRunner: { _, _, _, _, _ in
                XCTFail("Readiness blocking must not invoke the runner.")
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
        )
        await project.refresh()
        project.languageProfile = profile(.swift)

        await project.runMutationTesting()

        XCTAssertTrue(workspace.readSessions().isEmpty)
        XCTAssertEqual(try workspace.readState(), state)
        XCTAssertTrue(project.errorMessage?.contains("immediate") == true)
        XCTAssertEqual(project.runtimeDiagnosticsMenu.mutationRecoveryDescriptor?.stateIdentifier, "readiness-only")
    }

    func testNativeAppleContainerAndFallbackRoutesPropagateToRecordsAndSnapshots() async throws {
        let cases: [(String, CodexExecutionEnvironmentPreference, String?, String, String, String)] = [
            ("native", .nativeMacOS, nil, "native-route", "native-macos", "missing"),
            ("apple", .devcontainerPreferred, #"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#, "apple-container-route", "apple-container", "image-routeable"),
            ("fallback", .devcontainerPreferred, nil, "native-fallback", "native-macos", "missing")
        ]

        for testCase in cases {
            let repoURL = try await makeTemporaryGitRepository(prefix: "CompassProjectMutationRoute-\(testCase.0)")
            if let devcontainerJSON = testCase.2 {
                try write(devcontainerJSON, to: devcontainerURL(in: repoURL))
            }
            let workspace = try initializedWorkspace(
                repoURL: repoURL,
                state: makeState(verify: "swift test --filter \(testCase.0)")
            )
            let project = CompassProject(
                repoURL: repoURL,
                codexExecutionEnvironmentPreference: testCase.1,
                containerToolResolver: { _ in "/usr/local/bin/container" },
                mutationTestingRunner: { _, _, _, _, _ in
                    ProcessResult(exitCode: 0, stdout: testCase.0, stderr: "")
                }
            )
            await project.refresh()
            project.languageProfile = profile(.swift)

            await project.runMutationTesting()

            let session = try XCTUnwrap(workspace.readSessions().first, testCase.0)
            let execution = try XCTUnwrap(session.mutationTestingExecutions.first, testCase.0)
            XCTAssertEqual(execution.routeIdentifier, testCase.3, testCase.0)
            XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.phaseIdentifier, "mutation", testCase.0)
            XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.effectiveRouteIdentifier, testCase.4, testCase.0)
            XCTAssertEqual(session.latestExecutionEnvironmentSnapshot?.supportClassificationIdentifier, testCase.5, testCase.0)
        }
    }

    func testRuntimeMenuMutationActionDescriptorsCoverDisabledStatesAndNativeFallback() async throws {
        let repoURL = try await makeTemporaryGitRepository(prefix: "CompassProjectMutationMenu")
        let project = CompassProject(
            repoURL: repoURL,
            codexExecutionEnvironmentPreference: .devcontainerPreferred,
            containerToolResolver: { _ in nil }
        )

        project.state = PlanState(completed: [], immediate: nil, midTerm: "", longTerm: "")
        project.languageProfile = profile(.swift)
        var action = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationTestingAction)
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.availabilityIdentifier, "missing-immediate")
        XCTAssertTrue(action.helpText.contains("immediate"))

        project.state = makeState(verify: " ")
        action = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationTestingAction)
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.availabilityIdentifier, "missing-verify")
        XCTAssertTrue(action.helpText.contains("verify command"))

        project.state = makeState(verify: "markdownlint README.md")
        project.languageProfile = profile(.markdown)
        action = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationTestingAction)
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.availabilityIdentifier, "unsupported-language")
        XCTAssertTrue(action.helpText.contains("unavailable"))

        project.state = makeState(verify: "swift test")
        project.languageProfile = profile(.swift)
        action = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationTestingAction)
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.availabilityIdentifier, "native-fallback")
        XCTAssertTrue(action.helpText.contains("native macOS fallback"))

        project.isRunning = true
        action = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationTestingAction)
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.availabilityIdentifier, "running")
        XCTAssertTrue(action.helpText.contains("running"))

        project.isRunning = false
        project.isPaused = true
        action = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationTestingAction)
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.availabilityIdentifier, "paused")
        XCTAssertTrue(action.helpText.contains("paused"))
    }

    private func initializedWorkspace(repoURL: URL, state: PlanState) throws -> CompassWorkspace {
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        try workspace.writeState(state)
        return workspace
    }

    private func makeState(verify: String) -> PlanState {
        PlanState(
            completed: ["Existing work"],
            immediate: PlanNext(
                plan: "Run mutation testing",
                verify: verify,
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "",
            longTerm: ""
        )
    }

    private func profile(_ language: RepositoryLanguage) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = language == .unknown ? 0 : 1
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: [],
            primaryLanguage: language,
            scannedFileCount: language == .unknown ? 0 : 1,
            scannedDirectoryCount: 1,
            wasTruncated: false
        )
    }

    private func makeTemporaryGitRepository(prefix: String) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let result = try await ProcessRunner.runEnv("git", ["init"], workingDirectory: url)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
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

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
