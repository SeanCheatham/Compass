import Foundation
@testable import Compass
import XCTest

final class AgentReadFileToolTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let tool = AgentReadFileTool()

    override func setUpWithError() throws {
        temporaryDirectory = try makeTempDir()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testReadsFullFileWithLineNumbers() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("hello.txt")
        try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke(["path": "hello.txt"], context: context)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("     1\talpha"))
        XCTAssertTrue(result.content.contains("     2\tbeta"))
        XCTAssertTrue(result.content.contains("     3\tgamma"))
    }

    func testOffsetAndLimitNarrowTheSlice() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("rows.txt")
        let lines = (1...10).map { "row\($0)" }.joined(separator: "\n")
        try lines.write(to: fileURL, atomically: true, encoding: .utf8)

        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke([
            "path": "rows.txt",
            "offset": 3,
            "limit": 2
        ], context: context)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("     3\trow3"))
        XCTAssertTrue(result.content.contains("     4\trow4"))
        XCTAssertFalse(result.content.contains("row5"))
        XCTAssertTrue(result.content.contains("6 more lines"))
    }

    func testRejectsBinaryFiles() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("binary.bin")
        try Data([0x89, 0x00, 0x01, 0xFF, 0x00]).write(to: fileURL)

        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke(["path": "binary.bin"], context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("binary"))
    }

    func testRejectsPathsThatEscapeTheWorkingDirectory() async throws {
        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke(["path": "../escape.txt"], context: context)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("escapes"))
    }

    func testReportsMissingFile() async throws {
        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke(["path": "ghost.txt"], context: context)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("not found"))
    }

    func testOffsetPastEndReturnsFriendlyMessage() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("short.txt")
        try "only".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke([
            "path": "short.txt",
            "offset": 100
        ], context: context)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("past the end"))
    }

    func testRejectsDirectoryAsRegularFile() async throws {
        let subdir = temporaryDirectory.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

        let context = AgentToolContext(workingDirectory: temporaryDirectory)
        let result = try await invoke(["path": "sub"], context: context)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("Not a regular file"))
    }

    private func invoke(_ args: [String: Any], context: AgentToolContext) async throws -> AgentToolInvocationResult {
        let data = try JSONSerialization.data(withJSONObject: args)
        return try await tool.invoke(arguments: data, context: context)
    }
}

func makeTempDir(file: StaticString = #file, line: UInt = #line) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CompassAgentToolTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
}
