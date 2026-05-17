import Foundation
@testable import Compass
import XCTest

final class PlanTransitionValidatorTests: XCTestCase {
    func testRejectsShrinkingCompletedHistory() {
        let current = makeState(completed: ["one", "two"])
        let next = makeState(completed: ["one"])

        assertTransitionRejected(from: current, to: next, contains: "shrink completed history")
    }

    func testRejectsClearingMidTermWithoutCompletion() {
        let current = makeState(completed: ["done"], midTerm: "- Next queued item")
        let next = makeState(completed: ["done"], midTerm: "   \n")

        assertTransitionRejected(from: current, to: next, contains: "clear a non-empty midTerm queue")
    }

    func testRejectsPlaceholderVerifyCommands() {
        let current = makeState()
        let next = makeState(immediate: PlanNext(plan: "Do work", verify: " true "))

        assertTransitionRejected(from: current, to: next, contains: "placeholder verify command")
    }

    func testAcceptsNormalImmediateWork() throws {
        let current = makeState(midTerm: "- Build the next slice")
        let next = makeState(
            immediate: PlanNext(plan: "Build the next slice", verify: "swift test"),
            midTerm: "- Build the next slice\n- Polish follow-up"
        )

        try PlanTransitionValidator.validate(from: current, to: next)
    }

    func testAcceptsCompletionPlusMidTermRewrite() throws {
        let current = makeState(completed: ["First slice"], midTerm: "- Old queue")
        let next = makeState(
            completed: ["First slice", "Second slice"],
            immediate: PlanNext(plan: "Take the rewritten next step", verify: "swift test"),
            midTerm: "- Rewritten queue"
        )

        try PlanTransitionValidator.validate(from: current, to: next)
    }

    func testAcceptsNoImmediateWorkState() throws {
        let current = makeState(completed: ["Everything shipped"], midTerm: "")
        let next = makeState(completed: ["Everything shipped"], immediate: nil, midTerm: "", longTerm: "")

        try PlanTransitionValidator.validate(from: current, to: next)
    }

    private func makeState(
        completed: [String] = [],
        immediate: PlanNext? = nil,
        midTerm: String = "",
        longTerm: String = "Long-term direction"
    ) -> PlanState {
        PlanState(
            completed: completed,
            immediate: immediate,
            midTerm: midTerm,
            longTerm: longTerm
        )
    }

    private func assertTransitionRejected(
        from current: PlanState,
        to next: PlanState,
        contains expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PlanTransitionValidator.validate(from: current, to: next),
            file: file,
            line: line
        ) { error in
            let message = (error as? PlanTransitionValidationError)?.message
                ?? (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            XCTAssertTrue(
                message.contains(expectedText),
                "Expected error containing `\(expectedText)`, got `\(message)`.",
                file: file,
                line: line
            )
        }
    }
}

final class PlanNextDecoderTests: XCTestCase {
    func testDecoderTrimsPlanAndVerifyAndKeepsPositiveTimeout() throws {
        let json = """
        {
          "plan": "  Build the slice\\n",
          "verify": "\\n swift test  ",
          "verifyTimeoutMs": 120000,
          "estimatedDifficulty": "medium"
        }
        """

        let next = try decodePlanNext(json)

        XCTAssertEqual(next.plan, "Build the slice")
        XCTAssertEqual(next.verify, "swift test")
        XCTAssertEqual(next.verifyTimeoutMs, 120000)
        XCTAssertEqual(next.estimatedDifficulty, .medium)
    }

    func testDecoderDropsNonPositiveTimeouts() throws {
        let zeroTimeout = try decodePlanNext("""
        {
          "plan": "Build",
          "verify": "swift test",
          "verifyTimeoutMs": 0
        }
        """)
        let negativeTimeout = try decodePlanNext("""
        {
          "plan": "Build",
          "verify": "swift test",
          "verifyTimeoutMs": -1
        }
        """)

        XCTAssertNil(zeroTimeout.verifyTimeoutMs)
        XCTAssertNil(negativeTimeout.verifyTimeoutMs)
    }

    private func decodePlanNext(_ json: String) throws -> PlanNext {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(PlanNext.self, from: data)
    }
}

final class RepositoryLanguageProfileServiceTests: XCTestCase {
    func testDetectsSwiftPackageWhileIgnoringBuildDirectories() throws {
        let repoURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        try write("let package = Package(name: \"Fixture\")\n", to: repoURL.appending(path: "Package.swift"))
        try createDirectory(repoURL.appending(path: "Sources/App", directoryHint: .isDirectory))
        try write("print(\"hello\")\n", to: repoURL.appending(path: "Sources/App/main.swift"))
        try createDirectory(repoURL.appending(path: ".build/generated", directoryHint: .isDirectory))
        try write("console.log('ignored')\n", to: repoURL.appending(path: ".build/generated/ignored.ts"))
        try createDirectory(repoURL.appending(path: "build/generated", directoryHint: .isDirectory))
        try write("print('ignored')\n", to: repoURL.appending(path: "build/generated/ignored.py"))

        let profile = RepositoryLanguageProfileService.scan(repoURL: repoURL)

        XCTAssertEqual(profile.primaryLanguage, .swift)
        XCTAssertEqual(profile.manifestHints, [.packageSwift])
        XCTAssertEqual(profile.counts.swift, 2)
        XCTAssertEqual(profile.counts.typeScriptJavaScript, 0)
        XCTAssertEqual(profile.counts.python, 0)
        XCTAssertEqual(profile.scannedFileCount, 2)
        XCTAssertFalse(profile.wasTruncated)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CompassTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
