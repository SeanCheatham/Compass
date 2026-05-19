import Foundation
@testable import Compass
import XCTest

@MainActor
final class CompassProjectDevcontainerProvisioningTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testMissingConfigCreationWritesStarterAndSelectsDevcontainerPreference() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let project = CompassProject(repoURL: repoURL)
        project.languageProfile = languageProfile(primaryLanguage: .typeScriptJavaScript)

        project.prepareDevcontainerProvisioningConfirmation()
        let confirmation = try XCTUnwrap(project.devcontainerProvisioningConfirmation)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .awaitingConfirmation)
        XCTAssertTrue(confirmation.message.contains("TypeScript/JavaScript image starter"))
        XCTAssertTrue(confirmation.message.contains("node:22-bookworm"))
        XCTAssertTrue(confirmation.message.contains("Workspace: /workspace"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: devcontainerURL(in: repoURL).path))

        var persisted = false
        await project.confirmDevcontainerProvisioning(confirmation) {
            persisted = true
        }

        XCTAssertTrue(persisted)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .succeeded)
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .devcontainerPreferred)
        XCTAssertTrue(FileManager.default.fileExists(atPath: devcontainerURL(in: repoURL).path))
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("Native macOS remains selectable"))

        let dictionary = try devcontainerDictionary(in: repoURL)
        XCTAssertEqual(Set(dictionary.keys), ["image", "name", "workspaceFolder"])
        XCTAssertEqual(dictionary["image"], "node:22-bookworm")
        XCTAssertEqual(dictionary["workspaceFolder"], "/workspace")
        XCTAssertNil(dictionary["features"])
        XCTAssertNil(dictionary["build"])
        XCTAssertNil(dictionary["dockerComposeFile"])

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: project.codexExecutionEnvironmentPreference
        )
        let launchPlan = environment.launchPlan(
            repoURL: repoURL,
            containerToolResolver: { name in name == "container" ? "/usr/local/bin/container" : nil }
        )

        XCTAssertEqual(environment.devcontainerDiscovery.status, .ready)
        XCTAssertTrue(launchPlan.isContainerRoute)
        XCTAssertEqual(launchPlan.imageLabel, "node:22-bookworm")
        XCTAssertEqual(launchPlan.workspaceLabel, "/workspace")
    }

    func testExistingConfigBlocksPreparationWithoutOverwrite() throws {
        let repoURL = try makeTemporaryGitRepository()
        let configURL = devcontainerURL(in: repoURL)
        try write(#"{"image":"manual:1","workspaceFolder":"/workspace"}"#, to: configURL)
        let original = try read(configURL)
        let project = CompassProject(
            repoURL: repoURL,
            devcontainerProvisioningAction: { _ in
                XCTFail("Existing configs must block before provisioning action.")
                throw CodexDevcontainerProvisioningError.unavailable("unexpected")
            }
        )
        project.languageProfile = languageProfile(primaryLanguage: .python)

        project.prepareDevcontainerProvisioningConfirmation()

        XCTAssertNil(project.devcontainerProvisioningConfirmation)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .blocked)
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("will not overwrite"))
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
        XCTAssertEqual(try read(configURL), original)
    }

    func testExistingBuildConfigBlocksProvisioningWithoutMutation() throws {
        let repoURL = try makeTemporaryGitRepository()
        let configURL = devcontainerURL(in: repoURL)
        try write(
            #"{"build":{"dockerfile":"Dockerfile","args":{"TOKEN":"secret-value"}}}"#,
            to: configURL
        )
        let original = try read(configURL)
        let project = CompassProject(
            repoURL: repoURL,
            devcontainerProvisioningAction: { _ in
                XCTFail("Build configs must block before provisioning action.")
                throw CodexDevcontainerProvisioningError.unavailable("unexpected")
            }
        )
        project.languageProfile = languageProfile(primaryLanguage: .swift)

        project.prepareDevcontainerProvisioningConfirmation()

        XCTAssertNil(project.devcontainerProvisioningConfirmation)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .blocked)
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("will not overwrite"))
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
        XCTAssertEqual(try read(configURL), original)
    }

    func testExistingComposeConfigBlocksProvisioningWithoutMutation() throws {
        let repoURL = try makeTemporaryGitRepository()
        let configURL = devcontainerURL(in: repoURL)
        try write(
            #"{"dockerComposeFile":"compose.yml","service":"app","runServices":["db"]}"#,
            to: configURL
        )
        let original = try read(configURL)
        let project = CompassProject(
            repoURL: repoURL,
            devcontainerProvisioningAction: { _ in
                XCTFail("Compose configs must block before provisioning action.")
                throw CodexDevcontainerProvisioningError.unavailable("unexpected")
            }
        )
        project.languageProfile = languageProfile(primaryLanguage: .typeScriptJavaScript)

        project.prepareDevcontainerProvisioningConfirmation()

        XCTAssertNil(project.devcontainerProvisioningConfirmation)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .blocked)
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("will not overwrite"))
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
        XCTAssertEqual(try read(configURL), original)
    }

    func testConfirmingStaleMissingPlanRefusesToOverwriteNewConfig() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let configURL = devcontainerURL(in: repoURL)
        var actionCallCount = 0
        let project = CompassProject(
            repoURL: repoURL,
            devcontainerProvisioningAction: { _ in
                actionCallCount += 1
                throw CodexDevcontainerProvisioningError.unavailable("unexpected")
            }
        )
        project.languageProfile = languageProfile(primaryLanguage: .go)

        project.prepareDevcontainerProvisioningConfirmation()
        let confirmation = try XCTUnwrap(project.devcontainerProvisioningConfirmation)
        try write(#"{"image":"manual:2","workspaceFolder":"/workspace"}"#, to: configURL)
        let original = try read(configURL)

        await project.confirmDevcontainerProvisioning(confirmation) {
            XCTFail("Stale overwrite block should not persist project registry.")
        }

        XCTAssertEqual(actionCallCount, 0)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .blocked)
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("will not overwrite"))
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
        XCTAssertEqual(try read(configURL), original)
    }

    func testBusyProjectBlocksProvisioningWithoutCreatingFiles() throws {
        let repoURL = try makeTemporaryGitRepository()
        let project = CompassProject(repoURL: repoURL)
        project.languageProfile = languageProfile(primaryLanguage: .rust)
        project.isRunning = true

        project.prepareDevcontainerProvisioningConfirmation()

        XCTAssertNil(project.devcontainerProvisioningConfirmation)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .blocked)
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("active Compass run"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: devcontainerURL(in: repoURL).path))
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
    }

    func testMalformedConfigBlocksWithoutMutation() throws {
        let repoURL = try makeTemporaryGitRepository()
        let configURL = devcontainerURL(in: repoURL)
        try write("{", to: configURL)
        let original = try read(configURL)
        let project = CompassProject(repoURL: repoURL)
        project.languageProfile = languageProfile(primaryLanguage: .swift)

        project.prepareDevcontainerProvisioningConfirmation()

        XCTAssertNil(project.devcontainerProvisioningConfirmation)
        XCTAssertEqual(project.devcontainerProvisioningState.phase, .blocked)
        XCTAssertTrue(project.devcontainerProvisioningState.detail.contains("will not replace malformed"))
        XCTAssertEqual(try read(configURL), original)
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
    }

    func testInjectedProvisioningFailureShowsBoundedFeedbackAndKeepsNativePreference() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let project = CompassProject(
            repoURL: repoURL,
            devcontainerProvisioningAction: { _ in
                throw InjectedProvisioningError.failed(String(repeating: "long-failure-detail-", count: 80))
            }
        )
        project.languageProfile = languageProfile(primaryLanguage: .python)

        project.prepareDevcontainerProvisioningConfirmation()
        let confirmation = try XCTUnwrap(project.devcontainerProvisioningConfirmation)

        await project.confirmDevcontainerProvisioning(confirmation) {
            XCTFail("Failed provisioning should not persist project registry.")
        }

        XCTAssertEqual(project.devcontainerProvisioningState.phase, .failed)
        XCTAssertEqual(project.codexExecutionEnvironmentPreference, .nativeMacOS)
        XCTAssertFalse(FileManager.default.fileExists(atPath: devcontainerURL(in: repoURL).path))
        XCTAssertLessThanOrEqual(
            project.devcontainerProvisioningState.label.count,
            CompassProjectDevcontainerProvisioningState.labelLimit
        )
        XCTAssertLessThanOrEqual(
            project.devcontainerProvisioningState.detail.count,
            CompassProjectDevcontainerProvisioningState.detailLimit
        )
        XCTAssertLessThanOrEqual(
            project.devcontainerProvisioningState.helpText.count,
            CompassProjectDevcontainerProvisioningState.helpLimit
        )
        XCTAssertEqual(project.errorMessage, project.devcontainerProvisioningState.detail)
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CompassProjectDevcontainerProvisioning-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }

    private func devcontainerURL(in repoURL: URL) -> URL {
        repoURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")
    }

    private func languageProfile(primaryLanguage: RepositoryLanguage) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[primaryLanguage] = primaryLanguage == .unknown ? 0 : 1
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: [],
            primaryLanguage: primaryLanguage,
            scannedFileCount: primaryLanguage == .unknown ? 0 : 1,
            scannedDirectoryCount: 1,
            wasTruncated: false
        )
    }

    private func devcontainerDictionary(in repoURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: devcontainerURL(in: repoURL))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: String])
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

private enum InjectedProvisioningError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
