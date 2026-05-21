import Foundation
@testable import Compass
import XCTest

final class AgentBashRunnerTests: XCTestCase {

    // MARK: - HostBashRunner

    func testHostBashRunnerExecutesCommandInWorkingDirectory() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try "marker".write(
            to: tempDir.appendingPathComponent("flag.txt"),
            atomically: true,
            encoding: .utf8
        )
        let runner = AgentHostBashRunner()
        let result = try await runner.run(
            command: "cat flag.txt",
            workingDirectory: tempDir,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "marker")
    }

    // MARK: - SharedVMBashRunner

    func testSharedVMBashRunnerRejectsWorkingDirectoryOutsideMount() async throws {
        let mountURL = URL(fileURLWithPath: "/Users/test/Library/Caches/Compass/Worktrees/proj")
        let route = SharedVMRoute(
            sshDestination: "compass@vm",
            hostWorktreeURL: mountURL,
            guestWorkspacePath: "/opt/compass/workspaces/proj"
        )
        let runner = AgentSharedVMBashRunner(route: route)
        let result = try await runner.run(
            command: "true",
            workingDirectory: URL(fileURLWithPath: "/somewhere/else"),
            timeout: 5
        )
        XCTAssertEqual(result.exitCode, 127)
        XCTAssertTrue(result.stderr.contains("not under the host worktree mount"))
    }

    func testSharedVMBashRunnerBuildsRemoteCommandWithCdAndQuotedShell() {
        let remote = AgentSharedVMBashRunner.buildRemoteCommand(
            guestPath: "/opt/compass/workspaces/proj",
            command: "swift test"
        )
        XCTAssertEqual(remote, "cd /opt/compass/workspaces/proj && /bin/zsh -lc 'swift test'")
    }

    func testSharedVMBashRunnerQuotesPathsContainingSpaces() {
        let remote = AgentSharedVMBashRunner.buildRemoteCommand(
            guestPath: "/opt/compass/workspaces/project name",
            command: "swift test"
        )
        XCTAssertEqual(remote, "cd '/opt/compass/workspaces/project name' && /bin/zsh -lc 'swift test'")
    }

    func testSharedVMBashRunnerEmbedsEnvironmentVariablesSorted() {
        let remote = AgentSharedVMBashRunner.buildRemoteCommand(
            guestPath: "/opt/compass/workspaces/proj",
            command: "swift test",
            environmentVariables: ["FOO": "bar", "BAR": "baz with spaces"]
        )
        XCTAssertEqual(
            remote,
            "cd /opt/compass/workspaces/proj && env BAR='baz with spaces' FOO=bar /bin/zsh -lc 'swift test'"
        )
    }

    func testSharedVMBashRunnerQuotesCommandsContainingSingleQuotes() {
        let remote = AgentSharedVMBashRunner.buildRemoteCommand(
            guestPath: "/opt/compass/workspaces/proj",
            command: "echo 'hi'"
        )
        XCTAssertEqual(remote, "cd /opt/compass/workspaces/proj && /bin/zsh -lc 'echo '\\''hi'\\'''")
    }

    // MARK: - AgentBashTool wires the runner

    func testAgentBashToolDispatchesThroughInjectedRunner() async throws {
        final class RecordingRunner: AgentBashRunner, @unchecked Sendable {
            var lastCommand: String?
            var lastWorkingDirectory: URL?
            var lastTimeout: TimeInterval?
            func run(command: String, workingDirectory: URL, timeout: TimeInterval) async throws -> ProcessResult {
                lastCommand = command
                lastWorkingDirectory = workingDirectory
                lastTimeout = timeout
                return ProcessResult(exitCode: 0, stdout: "from-runner", stderr: "")
            }
        }
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let runner = RecordingRunner()
        let context = AgentToolContext(workingDirectory: tempDir, bashRunner: runner)
        let tool = AgentBashTool()
        let args = try JSONSerialization.data(withJSONObject: [
            "command": "echo hello",
            "timeoutMs": 5000
        ])
        let result = try await tool.invoke(arguments: args, context: context)
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("from-runner"))
        XCTAssertEqual(runner.lastCommand, "echo hello")
        XCTAssertEqual(runner.lastWorkingDirectory?.standardizedFileURL, tempDir)
        XCTAssertEqual(runner.lastTimeout, 5)
    }
}
