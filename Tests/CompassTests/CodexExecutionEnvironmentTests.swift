import Foundation
@testable import Compass
import XCTest

final class CodexExecutionEnvironmentTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testDiscoveryReportsReadyDevcontainerConfigWithoutChangingEffectiveNativeExecution() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentReady")
        let configURL = repoURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")
        try write(#"{"name":"Compass Dev"}"#, to: configURL)

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )

        XCTAssertEqual(environment.preference, .devcontainerPreferred)
        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertEqual(environment.devcontainerDiscovery.status, .ready)
        XCTAssertEqual(environment.devcontainerDiscovery.name, "Compass Dev")
        XCTAssertEqual(environment.devcontainerDiscovery.configURL, configURL.standardizedFileURL)
        XCTAssertTrue(environment.presentation.status.contains("Devcontainer found"))
        XCTAssertTrue(environment.presentation.status.contains("native macOS"))
        XCTAssertFalse(environment.presentation.isWarning)
        XCTAssertTrue(
            environment.launchPreflightSummary(
                phase: "Plan",
                nativeExecutionURL: repoURL
            ).contains("native path \(repoURL.standardizedFileURL.path)")
        )
    }

    func testMissingDevcontainerPresentationFallsBackToNativeMacOS() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentMissing")

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )

        XCTAssertEqual(environment.devcontainerDiscovery.status, .missing)
        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertTrue(environment.presentation.status.contains("falling back to native macOS"))
        XCTAssertTrue(environment.presentation.status.contains("no config"))
        XCTAssertTrue(environment.presentation.isWarning)
        XCTAssertLessThanOrEqual(
            environment.presentation.status.count,
            CodexExecutionEnvironmentPresentation.statusLimit
        )
        XCTAssertLessThanOrEqual(
            environment.devcontainerDiscovery.detail.count,
            CodexExecutionEnvironmentDiscovery.detailLimit
        )
    }

    func testMalformedDevcontainerPresentationIsBoundedAndFallsBackToNativeMacOS() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentMalformed")
        let configURL = repoURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")
        try write("{", to: configURL)

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )

        XCTAssertEqual(environment.devcontainerDiscovery.status, .malformed)
        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertTrue(environment.presentation.status.contains("malformed"))
        XCTAssertTrue(environment.presentation.status.contains("falling back to native macOS"))
        XCTAssertTrue(environment.presentation.isWarning)
        XCTAssertLessThanOrEqual(
            environment.presentation.detail.count,
            CodexExecutionEnvironmentPresentation.detailLimit
        )
        XCTAssertLessThanOrEqual(
            environment.devcontainerDiscovery.reason?.count ?? 0,
            CodexExecutionEnvironmentDiscovery.reasonLimit
        )
    }

    func testNativePreferenceKeepsDevcontainerOptionalWhenConfigIsPresent() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentNative")
        try write(
            #"{"name":"Optional Devcontainer"}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(repoURL: repoURL)

        XCTAssertEqual(environment.preference, .nativeMacOS)
        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertEqual(environment.devcontainerDiscovery.status, .ready)
        XCTAssertTrue(environment.presentation.status.contains("Running on native macOS"))
        XCTAssertTrue(environment.presentation.status.contains("recommended"))
    }

    func testDiscoveryDoesNotCreateDevcontainerFilesWhenConfigIsMissing() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentReadOnly")
        let devcontainerURL = repoURL.appending(path: ".devcontainer", directoryHint: .isDirectory)
        let beforeContents = try FileManager.default.contentsOfDirectory(
            atPath: repoURL.path
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )

        let afterContents = try FileManager.default.contentsOfDirectory(
            atPath: repoURL.path
        )
        XCTAssertEqual(environment.devcontainerDiscovery.status, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: devcontainerURL.path))
        XCTAssertEqual(beforeContents, afterContents)
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
