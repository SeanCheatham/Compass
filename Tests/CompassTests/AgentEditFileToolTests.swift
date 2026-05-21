import Foundation
@testable import Compass
import XCTest

final class AgentEditFileToolTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let tool = AgentEditFileTool()

    override func setUpWithError() throws {
        temporaryDirectory = try makeTempDir()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testReplacesUniqueOccurrence() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await invoke([
            "path": "notes.txt",
            "oldString": "beta",
            "newString": "BETA"
        ])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("replaced 1 occurrence in notes.txt"))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nBETA\ngamma")
    }

    func testFailsWhenOldStringIsAmbiguous() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("dup.txt")
        try "foo\nfoo\nfoo".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await invoke([
            "path": "dup.txt",
            "oldString": "foo",
            "newString": "bar"
        ])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("matches 3 places"))
        XCTAssertTrue(result.content.contains("replaceAll"))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "foo\nfoo\nfoo")
    }

    func testReplaceAllReplacesEveryOccurrence() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("dup.txt")
        try "foo\nfoo\nfoo".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await invoke([
            "path": "dup.txt",
            "oldString": "foo",
            "newString": "bar",
            "replaceAll": true
        ])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("replaced 3 occurrences"))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "bar\nbar\nbar")
    }

    func testFailsWhenOldStringMissing() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await invoke([
            "path": "notes.txt",
            "oldString": "missing",
            "newString": "found"
        ])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("not found"))
    }

    func testFailsWhenStringsAreEqual() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await invoke([
            "path": "notes.txt",
            "oldString": "alpha",
            "newString": "alpha"
        ])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("identical"))
    }

    func testFailsWhenOldStringIsEmpty() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await invoke([
            "path": "notes.txt",
            "oldString": "",
            "newString": "anything"
        ])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("write_file"))
    }

    func testRejectsPathThatEscapesWorkingDirectory() async throws {
        let result = try await invoke([
            "path": "../escape.txt",
            "oldString": "a",
            "newString": "b"
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("escapes"))
    }

    func testRejectsMissingFile() async throws {
        let result = try await invoke([
            "path": "ghost.txt",
            "oldString": "a",
            "newString": "b"
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("not found"))
    }

    func testRejectsBinaryFile() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("binary.bin")
        try Data([0x01, 0x00, 0x02, 0x03]).write(to: fileURL)

        let result = try await invoke([
            "path": "binary.bin",
            "oldString": "a",
            "newString": "b"
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("binary"))
    }

    private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
        let data = try JSONSerialization.data(withJSONObject: args)
        return try await tool.invoke(
            arguments: data,
            context: AgentToolContext(workingDirectory: temporaryDirectory)
        )
    }
}
