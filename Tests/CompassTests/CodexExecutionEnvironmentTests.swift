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

    func testDiscoveryReportsUnsupportedDevcontainerConfigWithNativeFallbackDiagnostics() throws {
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
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .unsupportedExtraFields)
        XCTAssertTrue(environment.presentation.status.contains("falling back to native macOS"))
        XCTAssertTrue(environment.presentation.status.contains("native macOS"))
        XCTAssertTrue(environment.presentation.isWarning)

        let preflight = environment.launchPreflightSummary(
            phase: "Plan",
            nativeExecutionURL: repoURL
        )
        XCTAssertTrue(preflight.contains("selected Dev Container Preferred"))
        XCTAssertTrue(preflight.contains("devcontainer unsupported-extra-fields tokens missing-image"))
        XCTAssertTrue(preflight.contains("effective route Native macOS"))
        XCTAssertTrue(preflight.contains("fallback Only image-based devcontainer configs are supported. Tokens: missing-image."))
        XCTAssertFalse(preflight.contains(repoURL.standardizedFileURL.path))
    }

    func testMenuAndPreflightExposeUnsupportedFallbackTokens() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentMenuFallback")
        try write(
            #"{"image":"swift:6.0","build":{"dockerfile":"Dockerfile"},"features":{"ghcr.io/devcontainers/features/git:1":{}},"postCreateCommand":"swift test"}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        let preflight = environment.launchPreflightSummary(
            phase: "Verify",
            nativeExecutionURL: repoURL
        )
        let detail = environment.launchPreflightDetail

        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .buildBased)
        XCTAssertTrue(menu.statusText.contains("build-based"))
        XCTAssertTrue(menu.statusText.contains("dockerfile:Dockerfile"))
        XCTAssertTrue(menu.statusText.contains("features"))
        XCTAssertTrue(menu.statusText.contains("extra:postCreateCommand"))
        XCTAssertTrue(menu.items.first { $0.preference == .devcontainerPreferred }?.description.contains("build-based") == true)
        XCTAssertTrue(preflight.contains("devcontainer build-based tokens build,dockerfile:Dockerfile,features,extra:postCreateCommand"))
        XCTAssertTrue(detail.contains("Unsupported devcontainer route: build-based tokens build,dockerfile:Dockerfile,features,extra:postCreateCommand."))
    }

    func testContainerEnvDiagnosticsExposeNamesWithoutValues() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentEnv")
        let secretValue = "secret-menu-value"
        try write(
            #"{"image":"swift:6.0","containerEnv":{"ZETA":"\#(secretValue)","ALPHA":"plain"}}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        let plan = environment.launchPlan(
            repoURL: repoURL,
            containerToolResolver: { name in name == "container" ? "/usr/local/bin/container" : nil }
        )
        let diagnosticsText = [
            menu.helpText,
            menu.statusText,
            plan.preflightSummary(phase: "Verify"),
            plan.routeDetail()
        ].joined(separator: " ")

        XCTAssertEqual(environment.devcontainerDiscovery.status, .ready)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.supportTokens, [
            "image",
            "containerEnv:2",
            "env:ALPHA",
            "env:ZETA"
        ])
        XCTAssertTrue(diagnosticsText.contains("containerEnv:2"))
        XCTAssertTrue(diagnosticsText.contains("env:ALPHA"))
        XCTAssertTrue(diagnosticsText.contains("env:ZETA"))
        XCTAssertFalse(diagnosticsText.contains(secretValue))
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
            #"{"name":"Optional Devcontainer","image":"swift:6.0"}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(repoURL: repoURL)

        XCTAssertEqual(environment.preference, .nativeMacOS)
        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertEqual(environment.devcontainerDiscovery.status, .ready)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .imageRouteable)
        XCTAssertTrue(environment.presentation.status.contains("Running on native macOS"))
        XCTAssertTrue(environment.presentation.status.contains("image-routeable"))
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
