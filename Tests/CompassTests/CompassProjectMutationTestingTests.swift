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
        var capturedInvocation: AgentExecutionInvocation?
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
        let rawVerify = ["swift test", repoURL.path, secretEnv].joined(separator: " ")
        let state = makeState(verify: rawVerify)
        let workspace = try initializedWorkspace(repoURL: repoURL, state: state)
        let project = CompassProject(
            repoURL: repoURL,
            mutationTestingRunner: { _, _, _, _, _ in
                ProcessResult(
                    exitCode: 23,
                    stdout: """
                    failed in \(repoURL.path)
                    env \(secretEnv)
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

        let execution = try XCTUnwrap(session.mutationTestingExecutions.first)
        XCTAssertEqual(execution.statusIdentifier, "failed")
        XCTAssertEqual(execution.routeIdentifier, "native-route")
        XCTAssertEqual(execution.exitCode, 23)
        XCTAssertLessThanOrEqual(execution.outputTail.count, SessionMutationTestingExecution.outputTailLimit)
        XCTAssertLessThanOrEqual(execution.seedCommandLabel.count, AgentMutationTestingPlan.commandMaxCharacters)

        let persistedText = try read(workspace.sessionsRecordURL)
        let exposedText = [persistedText, execution.outputTail, execution.seedCommandLabel].joined(separator: "\n")
        for leaked in [repoURL.standardizedFileURL.path] {
            XCTAssertFalse(exposedText.contains(leaked), "Leaked \(leaked)")
        }

        let recovery = try XCTUnwrap(project.runtimeDiagnosticsMenu.mutationRecoveryDescriptor)
        XCTAssertEqual(recovery.stateIdentifier, "active")
        XCTAssertTrue(recovery.isActive)
        XCTAssertEqual(recovery.reviewActionLabel, "Review Mutation")
        let runtimeCopy = project.runtimeDiagnosticsMenu.copyDiagnosticsAction.copyText
        XCTAssertTrue(runtimeCopy.contains("mutation-recovery-state: active"))
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


    func testRuntimeMenuMutationActionDescriptorsCoverDisabledStatesAndNativeFallback() async throws {
        let repoURL = try await makeTemporaryGitRepository(prefix: "CompassProjectMutationMenu")
        let project = CompassProject(repoURL: repoURL)

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
        XCTAssertEqual(action.availabilityIdentifier, "ready")

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
