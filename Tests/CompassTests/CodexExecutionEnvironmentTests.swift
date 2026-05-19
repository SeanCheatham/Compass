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
        let secretFeatureValue = "secret-feature-menu-value"
        try write(
            #"{"image":"swift:6.0","build":{"dockerfile":"Dockerfile"},"features":{"ghcr.io/devcontainers/features/git:1":{"version":"\#(secretFeatureValue)"}},"postCreateCommand":"swift test"}"#,
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
        XCTAssertTrue(menu.statusText.contains("features:1"))
        XCTAssertTrue(menu.statusText.contains("featureOptions:1"))
        XCTAssertTrue(menu.statusText.contains("feature:git:1"))
        XCTAssertTrue(menu.statusText.contains("extra:postCreateCommand"))
        XCTAssertTrue(menu.items.first { $0.preference == .devcontainerPreferred }?.description.contains("build-based") == true)
        XCTAssertTrue(preflight.contains("devcontainer build-based tokens build,dockerfile:Dockerfile,features:1,featureOptions:1,feature:git:1,extra:postCreateCommand"))
        XCTAssertTrue(detail.contains("Unsupported devcontainer route: build-based tokens build,dockerfile:Dockerfile,features:1,featureOptions:1,feature:git:1,extra:postCreateCommand."))
        XCTAssertFalse([menu.helpText, menu.statusText, preflight, detail].joined(separator: " ").contains(secretFeatureValue))
    }

    func testFeatureDiscoveryMenusExposeSanitizedFeatureCountsWithoutValues() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentFeatures")
        let secretValue = "secret-feature-environment-value"
        try write(
            #"{"image":"swift:6.0","features":{"aaa.example/custom/private feature":{"token":"hidden"},"ghcr.io/devcontainers/features/node:1":{"version":"\#(secretValue)"}}}"#,
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
        let diagnosticsText = [menu.helpText, menu.statusText, preflight, detail]
            .joined(separator: " ")

        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .featureBased)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.featureDescriptor?.featureCount, 2)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.featureDescriptor?.optionKeyCount, 2)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.supportTokens, [
            "features:2",
            "featureOptions:2",
            "feature:feature-1",
            "feature:node:1"
        ])
        XCTAssertTrue(menu.statusText.contains("feature-based"))
        XCTAssertTrue(menu.statusText.contains("features:2"))
        XCTAssertTrue(menu.items.first { $0.preference == .devcontainerPreferred }?.description.contains("feature:node:1") == true)
        XCTAssertTrue(preflight.contains("devcontainer feature-based tokens features:2"))
        XCTAssertTrue(detail.contains("Unsupported devcontainer route: feature-based tokens features:2"))
        XCTAssertFalse(diagnosticsText.contains(secretValue))
        XCTAssertFalse(diagnosticsText.contains("hidden"))
        XCTAssertFalse(diagnosticsText.contains("private feature"))
    }

    func testComposeDiscoveryMenusExposeSanitizedComposeTokensWithoutPaths() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentCompose")
        let absoluteComposePath = "/Users/private/project/compose.override.yml"
        try write(
            #"{"dockerComposeFile":["../compose.yml","\#(absoluteComposePath)"],"service":"api","runServices":["redis","db"]}"#,
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
        let diagnosticsText = [menu.helpText, menu.statusText, preflight, detail]
            .joined(separator: " ")

        XCTAssertEqual(environment.effectivePreference, .nativeMacOS)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .composeBased)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.supportTokens, [
            "compose",
            "composeFiles:2",
            "composeFile:compose.yml",
            "composeFile:compose.override.yml",
            "service:api",
            "runServices:2",
            "runService:db",
            "runService:redis"
        ])
        XCTAssertTrue(menu.statusText.contains("compose-based"))
        XCTAssertTrue(menu.statusText.contains("composeFiles:2"))
        XCTAssertTrue(menu.items.first { $0.preference == .devcontainerPreferred }?.description.contains("service:api") == true)
        XCTAssertTrue(preflight.contains("devcontainer compose-based tokens compose,composeFiles:2"))
        XCTAssertTrue(detail.contains("Unsupported devcontainer route: compose-based tokens compose,composeFiles:2"))
        XCTAssertFalse(diagnosticsText.contains("../compose.yml"))
        XCTAssertFalse(diagnosticsText.contains(absoluteComposePath))
        XCTAssertFalse(diagnosticsText.contains(repoURL.deletingLastPathComponent().standardizedFileURL.path))
    }

    func testBuildRouteableDiscoveryAndPreflightExposeLocalImageWithoutPaths() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentBuildRoute")
        let secretBuildArg = "secret-build-arg-menu-value"
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"runtime","args":{"TOKEN":"\#(secretBuildArg)"}}}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let plan = environment.launchPlan(
            repoURL: repoURL,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        let buildConfiguration = try XCTUnwrap(environment.devcontainerDiscovery.supportReport.buildConfiguration)
        let diagnosticsText = [
            environment.devcontainerDiscovery.detail,
            menu.items.first { $0.preference == .devcontainerPreferred }?.description ?? "",
            plan.preflightSummary(phase: "Develop"),
            plan.routeDetail()
        ].joined(separator: " ")

        XCTAssertTrue(plan.isContainerRoute)
        XCTAssertEqual(environment.devcontainerDiscovery.supportReport.classification, .buildBased)
        XCTAssertTrue(environment.devcontainerDiscovery.supportReport.isBuildRouteable)
        XCTAssertTrue(diagnosticsText.contains("build-based"))
        XCTAssertTrue(diagnosticsText.contains("local Apple container image"))
        XCTAssertTrue(diagnosticsText.contains(buildConfiguration.localImageTag))
        XCTAssertTrue(diagnosticsText.contains("buildArgs:1"))
        XCTAssertTrue(diagnosticsText.contains("arg:TOKEN"))
        XCTAssertFalse(diagnosticsText.contains(repoURL.standardizedFileURL.path))
        XCTAssertFalse(diagnosticsText.contains(secretBuildArg))
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

    func testRuntimeDiagnosticsReportForImageRouteIsCopyableSanitizedAndStable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentRuntimeImage")
        let secretValue = "secret-runtime-container-env"
        try write(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app","containerEnv":{"ZETA":"\#(secretValue)","ALPHA":"plain"}}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let launchPlan = environment.launchPlan(
            repoURL: repoURL,
            containerToolResolver: { name in name == "container" ? "/usr/local/bin/container" : nil }
        )
        let provisioningPlan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: .empty
        )
        let menu = CodexExecutionEnvironmentMenu(
            environment: environment,
            provisioningPlan: provisioningPlan,
            launchPlan: launchPlan
        )
        let action = menu.copyDiagnosticsAction
        let report = action.report

        XCTAssertEqual(action.id, CodexExecutionEnvironmentCopyDiagnosticsAction.actionIdentifier)
        XCTAssertEqual(action.title, "Copy Runtime Diagnostics")
        XCTAssertEqual(report.copyActionIdentifier, "runtime-diagnostics.copy")
        XCTAssertEqual(
            report.copyIdentifier,
            "runtime-diagnostics.copy.v1.devcontainer_preferred.apple-container.image-routeable.already-present"
        )
        XCTAssertEqual(report.selectedPreferenceIdentifier, "devcontainer_preferred")
        XCTAssertEqual(report.effectiveRouteIdentifier, "apple-container")
        XCTAssertEqual(report.supportClassificationIdentifier, "image-routeable")
        XCTAssertEqual(report.visibleSupportTokens, ["image", "containerEnv:2", "env:ALPHA", "env:ZETA"])
        XCTAssertEqual(report.omittedSupportTokenCount, 0)
        XCTAssertEqual(report.imageLabel, "swift:6.0")
        XCTAssertEqual(report.workspaceLabel, "/workspace/app")
        XCTAssertEqual(report.fallbackReason, "none")
        XCTAssertEqual(report.provisioningAvailabilityIdentifier, "unavailable")
        XCTAssertEqual(report.provisioningStatusIdentifier, "already-present")
        XCTAssertEqual(report.provisioningActionIdentifier, "devcontainer-provisioning.create")

        let copyText = action.copyText
        XCTAssertTrue(copyText.contains("copy-id: \(report.copyIdentifier)"))
        XCTAssertTrue(copyText.contains("effective-route: apple-container"))
        XCTAssertTrue(copyText.contains("support-tokens: image,containerEnv:2,env:ALPHA,env:ZETA"))
        XCTAssertFalse(copyText.contains(secretValue))
        XCTAssertFalse(copyText.contains(repoURL.standardizedFileURL.path))
        XCTAssertLessThanOrEqual(copyText.count, CodexExecutionEnvironmentDiagnosticsReport.copyTextLimit)
    }

    func testRuntimeDiagnosticsReportForBuildRouteHidesBuildArgValuesAndPaths() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentRuntimeBuild")
        let secretBuildArg = "secret-runtime-build-arg"
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"runtime","args":{"TOKEN":"\#(secretBuildArg)"}}}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let launchPlan = environment.launchPlan(
            repoURL: repoURL,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = CodexExecutionEnvironmentDiagnosticsReport(
            environment: environment,
            launchPlan: launchPlan,
            provisioningPlan: CodexDevcontainerProvisioningPlan.plan(repoURL: repoURL, languageProfile: .empty)
        )

        XCTAssertTrue(launchPlan.isContainerRoute)
        XCTAssertEqual(report.effectiveRouteIdentifier, "apple-container")
        XCTAssertEqual(report.supportClassificationIdentifier, "build-based")
        XCTAssertTrue(report.imageLabel.hasPrefix("compass-devcontainer:"))
        XCTAssertEqual(report.workspaceLabel, "/workspace")
        XCTAssertTrue(report.visibleSupportTokens.contains("buildArgs:1"))
        XCTAssertTrue(report.visibleSupportTokens.contains("arg:TOKEN"))
        XCTAssertTrue(report.copyText.contains("target:runtime"))
        XCTAssertFalse(report.copyText.contains(secretBuildArg))
        XCTAssertFalse(report.copyText.contains(repoURL.standardizedFileURL.path))
    }

    func testRuntimeDiagnosticsReportCoversMissingAndMalformedProvisioningStates() throws {
        let missingRepoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentRuntimeMissing")
        let missingEnvironment = CodexExecutionEnvironment.discover(
            repoURL: missingRepoURL,
            preference: .devcontainerPreferred
        )
        let missingLaunchPlan = missingEnvironment.launchPlan(
            repoURL: missingRepoURL,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let missingReport = CodexExecutionEnvironmentDiagnosticsReport(
            environment: missingEnvironment,
            launchPlan: missingLaunchPlan,
            provisioningPlan: CodexDevcontainerProvisioningPlan.plan(repoURL: missingRepoURL, languageProfile: .empty)
        )

        XCTAssertEqual(missingReport.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(missingReport.supportClassificationIdentifier, "missing")
        XCTAssertEqual(missingReport.provisioningAvailabilityIdentifier, "available")
        XCTAssertEqual(missingReport.provisioningStatusIdentifier, "available")
        XCTAssertEqual(
            missingReport.copyIdentifier,
            "runtime-diagnostics.copy.v1.devcontainer_preferred.native-macos.missing.available"
        )
        XCTAssertTrue(missingReport.copyText.contains("fallback: No .devcontainer/devcontainer.json was found."))
        XCTAssertFalse(missingReport.copyText.contains(missingRepoURL.standardizedFileURL.path))

        let malformedRepoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentRuntimeMalformed")
        try write(
            "{",
            to: malformedRepoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )
        let malformedEnvironment = CodexExecutionEnvironment.discover(
            repoURL: malformedRepoURL,
            preference: .devcontainerPreferred
        )
        let malformedReport = CodexExecutionEnvironmentDiagnosticsReport(
            environment: malformedEnvironment,
            launchPlan: malformedEnvironment.launchPlan(repoURL: malformedRepoURL),
            provisioningPlan: CodexDevcontainerProvisioningPlan.plan(repoURL: malformedRepoURL, languageProfile: .empty)
        )

        XCTAssertEqual(malformedReport.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(malformedReport.supportClassificationIdentifier, "malformed")
        XCTAssertEqual(malformedReport.provisioningAvailabilityIdentifier, "unavailable")
        XCTAssertEqual(malformedReport.provisioningStatusIdentifier, "malformed")
        XCTAssertTrue(malformedReport.copyText.contains("support-classification: malformed"))
        XCTAssertFalse(malformedReport.copyText.contains(malformedRepoURL.standardizedFileURL.path))
        XCTAssertLessThanOrEqual(
            malformedReport.copyText.count,
            CodexExecutionEnvironmentDiagnosticsReport.copyTextLimit
        )
    }

    func testRuntimeDiagnosticsReportSanitizesFallbackConfigsWithoutUnsupportedValues() throws {
        let absoluteComposePath = "/Users/private/project/compose.override.yml"
        let cases: [
            (
                prefix: String,
                json: String,
                classification: String,
                expectedToken: String,
                leakedValues: [String]
            )
        ] = [
            (
                "CodexExecutionEnvironmentRuntimeCompose",
                #"{"dockerComposeFile":["../compose.yml","\#(absoluteComposePath)"],"service":"api","runServices":["redis"]}"#,
                "compose-based",
                "composeFiles:2",
                [absoluteComposePath, "../compose.yml"]
            ),
            (
                "CodexExecutionEnvironmentRuntimeFeatures",
                #"{"image":"swift:6.0","features":{"ghcr.io/devcontainers/features/node:1":{"version":"secret-feature-version","nested":{"token":"secret-nested-token"}}}}"#,
                "feature-based",
                "featureOptions:2",
                ["secret-feature-version", "secret-nested-token", "nested"]
            ),
            (
                "CodexExecutionEnvironmentRuntimeUnsupported",
                #"{"image":"swift:6.0","remoteEnv":{"API_TOKEN":"secret-remote-token"}}"#,
                "unsupported-extra-fields",
                "extra:remoteEnv",
                ["secret-remote-token", "API_TOKEN"]
            )
        ]

        for testCase in cases {
            let repoURL = try makeTemporaryDirectory(prefix: testCase.prefix)
            try write(
                testCase.json,
                to: repoURL
                    .appending(path: ".devcontainer", directoryHint: .isDirectory)
                    .appending(path: "devcontainer.json")
            )

            let environment = CodexExecutionEnvironment.discover(
                repoURL: repoURL,
                preference: .devcontainerPreferred
            )
            let report = CodexExecutionEnvironmentDiagnosticsReport(
                environment: environment,
                launchPlan: environment.launchPlan(
                    repoURL: repoURL,
                    containerToolResolver: { _ in "/usr/local/bin/container" }
                ),
                provisioningPlan: CodexDevcontainerProvisioningPlan.plan(repoURL: repoURL, languageProfile: .empty)
            )

            XCTAssertEqual(report.effectiveRouteIdentifier, "native-macos")
            XCTAssertEqual(report.supportClassificationIdentifier, testCase.classification)
            XCTAssertTrue(report.copyText.contains(testCase.expectedToken))
            XCTAssertTrue(report.copyText.contains("fallback:"))
            XCTAssertFalse(report.copyText.contains(repoURL.standardizedFileURL.path))
            for leakedValue in testCase.leakedValues {
                XCTAssertFalse(report.copyText.contains(leakedValue), "Leaked \(leakedValue)")
            }
        }
    }

    func testRuntimeDiagnosticsReportIncludesOmittedSupportTokenCounts() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionEnvironmentRuntimeOmitted")
        let features = (0..<10)
            .reversed()
            .map { #""ghcr.io/devcontainers/features/feature-\#(String(format: "%02d", $0)):1":{"enabled":true}"# }
            .joined(separator: ",")
        try write(
            #"{"features":{\#(features)}}"#,
            to: repoURL
                .appending(path: ".devcontainer", directoryHint: .isDirectory)
                .appending(path: "devcontainer.json")
        )

        let environment = CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: .devcontainerPreferred
        )
        let report = CodexExecutionEnvironmentDiagnosticsReport(
            environment: environment,
            launchPlan: environment.launchPlan(repoURL: repoURL),
            provisioningPlan: CodexDevcontainerProvisioningPlan.plan(repoURL: repoURL, languageProfile: .empty)
        )

        XCTAssertEqual(report.visibleSupportTokens.count, CodexDevcontainerSupportReport.maxTokenCount)
        XCTAssertEqual(report.omittedSupportTokenCount, 4)
        XCTAssertTrue(report.copyText.contains("omitted-support-token-count: 4"))
        XCTAssertTrue(report.copyText.contains("feature:feature-05:1"))
        XCTAssertFalse(report.copyText.contains("feature:feature-09:1"))
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
