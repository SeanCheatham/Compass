import Foundation
@testable import Compass
import XCTest

final class AgentBashToolTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let tool = AgentBashTool()

    override func setUpWithError() throws {
        temporaryDirectory = try makeTempDir()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testCommandSucceedsAndReportsStdoutAndExit() async throws {
        let result = try await invoke(["command": "echo hello"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[stdout]\nhello"))
        XCTAssertTrue(result.content.contains("[exit 0]"))
        XCTAssertFalse(result.content.contains("[stderr]"))
    }

    func testCommandStderrIsCapturedSeparately() async throws {
        let result = try await invoke(["command": "echo out; echo err 1>&2; exit 0"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[stdout]\nout"))
        XCTAssertTrue(result.content.contains("[stderr]\nerr"))
        XCTAssertTrue(result.content.contains("[exit 0]"))
    }

    func testNonZeroExitIsReported() async throws {
        let result = try await invoke(["command": "exit 7"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[exit 7]"))
    }

    func testCommandRunsInsideWorkingDirectory() async throws {
        try "marker".write(
            to: temporaryDirectory.appendingPathComponent("ping.txt"),
            atomically: true,
            encoding: .utf8
        )
        let result = try await invoke(["command": "cat ping.txt"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("marker"))
    }

    func testCwdMustResolveInsideWorkingDirectory() async throws {
        let result = try await invoke([
            "command": "pwd",
            "cwd": "../escape"
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("escapes"))
    }

    func testCwdSubdirectoryIsHonored() async throws {
        let subdir = temporaryDirectory.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)
        try "deep".write(
            to: subdir.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await invoke([
            "command": "cat file.txt",
            "cwd": "inner"
        ])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("deep"))
    }

    func testTimeoutTerminatesLongRunningCommand() async throws {
        let result = try await invoke([
            "command": "sleep 5",
            "timeoutMs": 500
        ])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(
            result.content.contains("timed out"),
            "expected timeout note, got: \(result.content)"
        )
    }

    func testEmptyCommandFails() async throws {
        let result = try await invoke(["command": "   "])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("command is empty"))
    }

    private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
        let data = try JSONSerialization.data(withJSONObject: args)
        return try await tool.invoke(
            arguments: data,
            context: AgentToolContext(workingDirectory: temporaryDirectory)
        )
    }
}
