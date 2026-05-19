import Foundation
@testable import Compass
import XCTest

final class CodexDevcontainerProvisioningTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testTemplateSelectionUsesRepositoryLanguageProfile() {
        XCTAssertEqual(
            CodexDevcontainerProvisioningTemplateCatalog.template(
                for: languageProfile(primaryLanguage: .swift)
            ).id,
            "swift"
        )
        XCTAssertEqual(
            CodexDevcontainerProvisioningTemplateCatalog.template(
                for: languageProfile(primaryLanguage: .typeScriptJavaScript)
            ).image,
            "node:22-bookworm"
        )
        XCTAssertEqual(
            CodexDevcontainerProvisioningTemplateCatalog.template(
                for: languageProfile(primaryLanguage: .python)
            ).image,
            "python:3.12-bookworm"
        )
        XCTAssertEqual(
            CodexDevcontainerProvisioningTemplateCatalog.template(
                for: languageProfile(primaryLanguage: .go)
            ).image,
            "golang:1.23-bookworm"
        )
        XCTAssertEqual(
            CodexDevcontainerProvisioningTemplateCatalog.template(
                for: languageProfile(primaryLanguage: .rust)
            ).image,
            "rust:1.82-bookworm"
        )
        XCTAssertEqual(
            CodexDevcontainerProvisioningTemplateCatalog.template(
                for: languageProfile(primaryLanguage: .unknown)
            ).id,
            "generic"
        )
    }

    func testManifestHintsCanSelectTemplateWhenPrimaryLanguageIsGeneric() {
        let profile = languageProfile(
            primaryLanguage: .markdown,
            manifestHints: [.packageJSON]
        )

        let template = CodexDevcontainerProvisioningTemplateCatalog.template(for: profile)

        XCTAssertEqual(template.id, "typescript-javascript")
        XCTAssertEqual(template.workspaceFolder, "/workspace")
    }

    func testGeneratedConfigurationIsSafeImageOnlyAndBoundedForPresentation() throws {
        let repoURL = try makeTemporaryDirectory(
            prefix: "CodexDevcontainerProvisioning" + String(repeating: "Long", count: 30)
        )
        let plan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: languageProfile(primaryLanguage: .swift)
        )
        let confirmation = CodexDevcontainerProvisioningConfirmation(plan: plan)
        let state = CompassProjectDevcontainerProvisioningState.awaitingConfirmation(confirmation)
        let menuAction = try XCTUnwrap(CodexDevcontainerProvisioningMenuAction(plan: plan))

        XCTAssertTrue(plan.isAvailable)
        XCTAssertEqual(plan.template.image, "swift:6.0")
        XCTAssertEqual(plan.template.workspaceFolder, "/workspace")
        XCTAssertLessThanOrEqual(plan.label.count, CodexDevcontainerProvisioningPlan.labelLimit)
        XCTAssertLessThanOrEqual(plan.detail.count, CodexDevcontainerProvisioningPlan.detailLimit)
        XCTAssertLessThanOrEqual(confirmation.title.count, CodexDevcontainerProvisioningConfirmation.titleLimit)
        XCTAssertLessThanOrEqual(confirmation.message.count, CodexDevcontainerProvisioningConfirmation.messageLimit)
        XCTAssertLessThanOrEqual(confirmation.confirmLabel.count, CodexDevcontainerProvisioningConfirmation.actionLabelLimit)
        XCTAssertLessThanOrEqual(confirmation.cancelLabel.count, CodexDevcontainerProvisioningConfirmation.actionLabelLimit)
        XCTAssertLessThanOrEqual(state.label.count, CompassProjectDevcontainerProvisioningState.labelLimit)
        XCTAssertLessThanOrEqual(state.detail.count, CompassProjectDevcontainerProvisioningState.detailLimit)
        XCTAssertLessThanOrEqual(state.helpText.count, CompassProjectDevcontainerProvisioningState.helpLimit)
        XCTAssertLessThanOrEqual(menuAction.title.count, CodexDevcontainerProvisioningMenuAction.titleLimit)
        XCTAssertLessThanOrEqual(menuAction.description.count, CodexDevcontainerProvisioningMenuAction.descriptionLimit)
        XCTAssertLessThanOrEqual(menuAction.helpText.count, CodexDevcontainerProvisioningMenuAction.helpLimit)
        XCTAssertTrue(confirmation.message.contains("Template: Swift image starter"))
        XCTAssertTrue(confirmation.message.contains("Image: swift:6.0"))
        XCTAssertTrue(confirmation.message.contains("Workspace: /workspace"))

        let object = try JSONSerialization.jsonObject(with: plan.configurationData())
        let dictionary = try XCTUnwrap(object as? [String: String])

        XCTAssertEqual(Set(dictionary.keys), ["image", "name", "workspaceFolder"])
        XCTAssertEqual(dictionary["image"], "swift:6.0")
        XCTAssertEqual(dictionary["workspaceFolder"], "/workspace")
        XCTAssertNil(dictionary["build"])
        XCTAssertNil(dictionary["dockerComposeFile"])
        XCTAssertNil(dictionary["features"])
    }

    func testRuntimeMenuDescriptorExposesCreateActionOnlyForMissingConfigs() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexDevcontainerProvisioningMenu")
        let profile = languageProfile(primaryLanguage: .python)
        let missingEnvironment = CodexExecutionEnvironment.discover(repoURL: repoURL)
        let missingPlan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: profile
        )
        let missingMenu = CodexExecutionEnvironmentMenu(
            environment: missingEnvironment,
            provisioningPlan: missingPlan
        )

        let action = try XCTUnwrap(missingMenu.createDevcontainerAction)
        XCTAssertEqual(action.title, "Create Dev Container")
        XCTAssertTrue(action.description.contains("Python image starter"))
        XCTAssertTrue(action.description.contains("python:3.12-bookworm"))
        XCTAssertTrue(action.description.contains("/workspace"))

        _ = try CodexDevcontainerProvisioner.write(plan: missingPlan)
        let readyEnvironment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let readyPlan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: profile
        )
        let readyMenu = CodexExecutionEnvironmentMenu(
            environment: readyEnvironment,
            provisioningPlan: readyPlan
        )
        let launchPlan = readyEnvironment.launchPlan(
            repoURL: repoURL,
            containerToolResolver: { name in name == "container" ? "/usr/local/bin/container" : nil }
        )

        XCTAssertNil(readyMenu.createDevcontainerAction)
        XCTAssertEqual(readyEnvironment.devcontainerDiscovery.status, .ready)
        XCTAssertTrue(launchPlan.isContainerRoute)
        XCTAssertEqual(launchPlan.imageLabel, "python:3.12-bookworm")
        XCTAssertEqual(launchPlan.workspaceLabel, "/workspace")
    }

    func testExistingComposeConfigKeepsProvisioningUnavailable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexDevcontainerProvisioningCompose")
        try write(
            #"{"dockerComposeFile":"compose.yml","service":"app"}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let plan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: languageProfile(primaryLanguage: .typeScriptJavaScript)
        )
        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let menu = CodexExecutionEnvironmentMenu(
            environment: environment,
            provisioningPlan: plan
        )

        XCTAssertFalse(plan.isAvailable)
        XCTAssertEqual(plan.status, .alreadyPresent)
        XCTAssertNil(menu.createDevcontainerAction)
        XCTAssertTrue(plan.detail.contains("will not overwrite"))
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .composeBased)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.supportTokens, [
            "compose",
            "composeFile:compose.yml",
            "service:app"
        ])
    }

    func testExistingFeatureConfigKeepsProvisioningUnavailable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexDevcontainerProvisioningFeatures")
        let secretFeatureValue = "secret-feature-provisioning-value"
        try write(
            #"{"image":"swift:6.0","features":{"ghcr.io/devcontainers/features/git:1":{"version":"\#(secretFeatureValue)"}}}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let plan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: languageProfile(primaryLanguage: .swift)
        )
        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let menu = CodexExecutionEnvironmentMenu(
            environment: environment,
            provisioningPlan: plan
        )
        let diagnosticsText = [
            plan.detail,
            environment.devcontainerDiscovery.detail,
            menu.statusText
        ].joined(separator: " ")

        XCTAssertFalse(plan.isAvailable)
        XCTAssertEqual(plan.status, .alreadyPresent)
        XCTAssertNil(menu.createDevcontainerAction)
        XCTAssertTrue(plan.detail.contains("will not overwrite"))
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .featureBased)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.supportTokens, [
            "features:1",
            "featureOptions:1",
            "feature:git:1"
        ])
        XCTAssertFalse(diagnosticsText.contains(secretFeatureValue))
    }

    private func languageProfile(
        primaryLanguage: RepositoryLanguage,
        manifestHints: [RepositoryManifestHint] = []
    ) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[primaryLanguage] = primaryLanguage == .unknown ? 0 : 1
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: manifestHints,
            primaryLanguage: primaryLanguage,
            scannedFileCount: primaryLanguage == .unknown ? 0 : 1,
            scannedDirectoryCount: 1,
            wasTruncated: false
        )
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
