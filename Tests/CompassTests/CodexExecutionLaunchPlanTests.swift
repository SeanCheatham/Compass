import Foundation
@testable import Compass
import XCTest

final class CodexExecutionLaunchPlanTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testImageDevcontainerRoutesThroughAppleContainerWhenToolIsAvailable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanReady")
        try write(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { name in name == "container" ? "/usr/local/bin/container" : nil }
        )

        XCTAssertTrue(plan.isContainerRoute)
        XCTAssertNil(plan.fallbackReason)
        XCTAssertEqual(plan.effectiveRouteTitle, "Apple container")
        XCTAssertEqual(plan.imageLabel, "swift:6.0")
        XCTAssertEqual(plan.workspaceLabel, "/workspace/app")

        guard case let .appleContainer(route) = plan.effectiveRoute else {
            return XCTFail("Expected Apple container route.")
        }
        XCTAssertEqual(route.toolPath, "/usr/local/bin/container")
        XCTAssertEqual(route.volumeArgument, "\(repoURL.standardizedFileURL.path):/workspace")
        XCTAssertEqual(route.workspaceFolder, "/workspace/app")

        let preflight = plan.preflightSummary(phase: "Plan")
        XCTAssertTrue(preflight.contains("selected Dev Container Preferred"))
        XCTAssertTrue(preflight.contains("effective route Apple container"))
        XCTAssertTrue(preflight.contains("image swift:6.0"))
        XCTAssertFalse(preflight.contains(repoURL.standardizedFileURL.path))
    }

    func testImageDevcontainerContainerEnvRoutesWithSanitizedSupportTokens() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanEnv")
        let secretValue = "super-secret-token"
        try write(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app","containerEnv":{"ZETA":"\#(secretValue)","ALPHA":"plain"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { name in name == "container" ? "/usr/local/bin/container" : nil }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)
        let config = try XCTUnwrap(plan.devcontainer)

        XCTAssertTrue(plan.isContainerRoute)
        XCTAssertEqual(config.containerEnv.map(\.name), ["ALPHA", "ZETA"])
        XCTAssertEqual(config.containerEnv.map(\.value), ["plain", secretValue])
        XCTAssertEqual(report.classification, .imageRouteable)
        XCTAssertEqual(report.supportTokens, ["image", "containerEnv:2", "env:ALPHA", "env:ZETA"])

        guard case let .appleContainer(route) = plan.effectiveRoute else {
            return XCTFail("Expected Apple container route.")
        }
        XCTAssertEqual(route.environmentArguments, [
            "--env", "ALPHA=plain",
            "--env", "ZETA=\(secretValue)"
        ])

        let diagnosticsText = [
            report.supportSummary,
            plan.preflightSummary(phase: "Develop"),
            plan.routeDetail()
        ].joined(separator: " ")
        XCTAssertTrue(diagnosticsText.contains("containerEnv:2"))
        XCTAssertTrue(diagnosticsText.contains("env:ALPHA"))
        XCTAssertTrue(diagnosticsText.contains("env:ZETA"))
        XCTAssertFalse(diagnosticsText.contains(secretValue))
    }

    func testNativePreferenceStaysNativeEvenWhenSupportedConfigAndToolExist() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanNative")
        try write(#"{"image":"swift:6.0"}"#, to: devcontainerURL(in: repoURL))

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .nativeMacOS,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.effectiveRouteTitle, "Native macOS")
        XCTAssertEqual(plan.imageLabel, "swift:6.0")
        XCTAssertEqual(plan.workspaceLabel, "host")
        XCTAssertNil(plan.fallbackReason)
    }

    func testMissingConfigFallsBackToNativeWithBoundedReason() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanMissing")

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.effectiveRouteTitle, "Native macOS")
        XCTAssertEqual(plan.fallbackReason, "No .devcontainer/devcontainer.json was found.")
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .missing)
        XCTAssertLessThanOrEqual(
            plan.fallbackReason?.count ?? 0,
            CodexExecutionLaunchPlan.fallbackReasonLimit
        )
    }

    func testMalformedConfigFallsBackToNativeWithBoundedReason() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanMalformed")
        try write("{", to: devcontainerURL(in: repoURL))

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertTrue(plan.fallbackReason?.contains("malformed") == true)
        XCTAssertLessThanOrEqual(
            plan.fallbackReason?.count ?? 0,
            CodexExecutionLaunchPlan.fallbackReasonLimit
        )
    }

    func testBuildConfigRoutesThroughAppleContainerWhenToolIsAvailable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBuild")
        try write(
            #"{"build":{"dockerfile":"Dockerfile"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)
        let buildConfiguration = try XCTUnwrap(report.buildConfiguration)

        XCTAssertTrue(plan.isContainerRoute)
        XCTAssertNil(plan.fallbackReason)
        XCTAssertEqual(plan.imageLabel, buildConfiguration.localImageTag)
        XCTAssertEqual(plan.workspaceLabel, "/workspace")
        XCTAssertEqual(report.classification, .buildBased)
        XCTAssertEqual(report.supportTokens, ["build", "dockerfile:Dockerfile"])
        XCTAssertTrue(plan.preflightSummary(phase: "Develop").contains("image compass-devcontainer:"))
        XCTAssertFalse(plan.preflightSummary(phase: "Develop").contains(repoURL.standardizedFileURL.path))

        guard case let .appleContainer(route) = plan.effectiveRoute else {
            return XCTFail("Expected Apple container route.")
        }
        XCTAssertEqual(route.image, buildConfiguration.localImageTag)
        XCTAssertEqual(route.workspaceFolder, "/workspace")
        XCTAssertEqual(route.buildConfiguration, buildConfiguration)
    }

    func testBuildStringAndTopLevelDockerfileFormsExposeSanitizedDescriptorTokens() throws {
        let cases: [
            (
                prefix: String,
                json: String,
                expectedTokens: [String],
                expectedDockerfile: String?,
                expectedDockerfilePath: String?,
                expectsBuildConfiguration: Bool
            )
        ] = [
            (
                "CodexExecutionLaunchPlanBuildString",
                #"{"build":"docker/Dockerfile.dev"}"#,
                ["build", "dockerfile:Dockerfile.dev"],
                "Dockerfile.dev",
                ".devcontainer/docker/Dockerfile.dev",
                true
            ),
            (
                "CodexExecutionLaunchPlanTopLevelDockerFile",
                #"{"dockerFile":"../Dockerfile"}"#,
                ["build", "dockerfile:Dockerfile"],
                "Dockerfile",
                "Dockerfile",
                true
            ),
            (
                "CodexExecutionLaunchPlanTopLevelDockerfile",
                #"{"dockerfile":"/tmp/private-repo/Dockerfile.secret"}"#,
                ["build", "dockerfile:absolute"],
                "absolute",
                nil,
                false
            )
        ]

        for testCase in cases {
            let repoURL = try makeTemporaryDirectory(prefix: testCase.prefix)
            try write(testCase.json, to: devcontainerURL(in: repoURL))

            let plan = CodexExecutionLaunchPlan.plan(
                repoURL: repoURL,
                preference: .devcontainerPreferred,
                containerToolResolver: { _ in "/usr/local/bin/container" }
            )
            let report = try XCTUnwrap(plan.devcontainerSupportReport)

            XCTAssertEqual(plan.isContainerRoute, testCase.expectsBuildConfiguration)
            XCTAssertEqual(report.classification, .buildBased)
            XCTAssertEqual(report.supportTokens, testCase.expectedTokens)
            XCTAssertEqual(report.buildDescriptor?.dockerfileLabel, testCase.expectedDockerfile)
            XCTAssertEqual(report.buildConfiguration != nil, testCase.expectsBuildConfiguration)
            if let expectedDockerfilePath = testCase.expectedDockerfilePath {
                XCTAssertEqual(
                    report.buildConfiguration?.dockerfileURL,
                    repoRelativeURL(expectedDockerfilePath, in: repoURL)
                )
                XCTAssertEqual(
                    report.buildConfiguration?.contextURL,
                    repoURL.appending(path: ".devcontainer", directoryHint: .isDirectory).standardizedFileURL
                )
                XCTAssertEqual(plan.imageLabel, report.buildConfiguration?.localImageTag)
            } else {
                XCTAssertFalse(plan.isContainerRoute)
            }
            XCTAssertFalse(report.supportSummary.contains("/tmp/private-repo"))
        }
    }

    func testSafeBuildObjectCreatesDeterministicBuildConfigurationAndRoutesLocalImage() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBuildPlan")
        try write(
            #"{"build":{"target":"runtime","context":"..","dockerfile":"Dockerfile"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let firstPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let secondPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(firstPlan.devcontainerSupportReport)
        let buildConfiguration = try XCTUnwrap(report.buildConfiguration)
        let repeatedConfiguration = try XCTUnwrap(secondPlan.devcontainerSupportReport?.buildConfiguration)
        let invocation = buildConfiguration.buildInvocation(containerToolPath: "/usr/local/bin/container")

        XCTAssertTrue(firstPlan.isContainerRoute)
        XCTAssertEqual(report.classification, .buildBased)
        XCTAssertEqual(report.buildDescriptor?.dockerfileLabel, "Dockerfile")
        XCTAssertEqual(report.buildDescriptor?.contextLabel, "repo-root")
        XCTAssertEqual(report.buildDescriptor?.targetLabel, "runtime")
        XCTAssertEqual(buildConfiguration.dockerfileURL, repoRelativeURL(".devcontainer/Dockerfile", in: repoURL))
        XCTAssertEqual(buildConfiguration.contextURL, repoURL.standardizedFileURL)
        XCTAssertEqual(buildConfiguration.target, "runtime")
        XCTAssertEqual(buildConfiguration.localImageTag, repeatedConfiguration.localImageTag)
        XCTAssertTrue(buildConfiguration.localImageTag.hasPrefix("compass-devcontainer:"))
        XCTAssertEqual(firstPlan.imageLabel, buildConfiguration.localImageTag)
        XCTAssertEqual(firstPlan.workspaceLabel, "/workspace")
        XCTAssertEqual(invocation.executable, "/usr/local/bin/container")
        XCTAssertEqual(invocation.workingDirectory, repoURL.standardizedFileURL)
        XCTAssertEqual(invocation.arguments, [
            "build",
            "--tag", buildConfiguration.localImageTag,
            "--file", repoRelativeURL(".devcontainer/Dockerfile", in: repoURL).path,
            "--target", "runtime",
            repoURL.standardizedFileURL.path
        ])

        guard case let .appleContainer(route) = firstPlan.effectiveRoute else {
            return XCTFail("Expected Apple container route.")
        }
        XCTAssertEqual(route.image, buildConfiguration.localImageTag)
        XCTAssertEqual(route.buildConfiguration, buildConfiguration)
    }

    func testBuildObjectExposesSortedBuildArgNamesWithoutValues() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBuildObject")
        let secretValue = "secret-build-arg-value"
        let secondSecretValue = "second-secret-build-value"
        try write(
            #"{"build":{"dockerfile":"docker/Dockerfile.runtime","context":"..","target":"runtime","args":{"ZETA":"\#(secretValue)","ALPHA":"plain"},"buildArgs":{"BETA":"\#(secondSecretValue)"}}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)
        let descriptor = try XCTUnwrap(report.buildDescriptor)
        let diagnosticsText = [
            report.supportSummary,
            plan.preflightSummary(phase: "Develop"),
            plan.routeDetail()
        ].joined(separator: " ")

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertNil(plan.devcontainer)
        XCTAssertEqual(report.classification, .buildBased)
        XCTAssertEqual(descriptor.dockerfileLabel, "Dockerfile.runtime")
        XCTAssertEqual(descriptor.contextLabel, "repo-root")
        XCTAssertEqual(descriptor.targetLabel, "runtime")
        XCTAssertNil(report.buildConfiguration)
        XCTAssertEqual(descriptor.buildArgNames, ["ALPHA", "BETA", "ZETA"])
        XCTAssertEqual(report.supportTokens, [
            "build",
            "dockerfile:Dockerfile.runtime",
            "context:repo-root",
            "target:runtime",
            "buildArgs:3",
            "arg:ALPHA",
            "arg:BETA",
            "arg:ZETA"
        ])
        XCTAssertTrue(diagnosticsText.contains("buildArgs:3"))
        XCTAssertTrue(diagnosticsText.contains("arg:ALPHA"))
        XCTAssertTrue(diagnosticsText.contains("arg:BETA"))
        XCTAssertTrue(diagnosticsText.contains("arg:ZETA"))
        XCTAssertFalse(diagnosticsText.contains(secretValue))
        XCTAssertFalse(diagnosticsText.contains(secondSecretValue))
    }

    func testBuildDescriptorTokensAreDeterministicallyOrderedAndBounded() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBuildBounded")
        let args = (0..<10)
            .map { #""ARG\#(String(format: "%02d", $0))":"value""# }
            .joined(separator: ",")
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":".","target":"builder","args":{\#(args)}}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)

        XCTAssertEqual(report.supportTokens, [
            "build",
            "dockerfile:Dockerfile",
            "context:.devcontainer",
            "target:builder",
            "buildArgs:10",
            "arg:ARG00",
            "arg:ARG01",
            "arg:ARG02"
        ])
        XCTAssertEqual(report.omittedTokenCount, 7)
        XCTAssertTrue(report.tokenSummary.contains("+7-more"))
    }

    func testMalformedBuildArgsFallBackWithoutLeakingValues() throws {
        let cases: [(prefix: String, json: String, reasonToken: String, leakedValue: String)] = [
            (
                "CodexExecutionLaunchPlanBuildArgsArray",
                #"{"build":{"dockerfile":"Dockerfile","args":["SECRET_TOKEN"]}}"#,
                "build args must be an object",
                "SECRET_TOKEN"
            ),
            (
                "CodexExecutionLaunchPlanBuildArgsValue",
                #"{"build":{"dockerfile":"Dockerfile","args":{"SAFE_ARG":true}}}"#,
                "build args values must be strings",
                "true"
            ),
            (
                "CodexExecutionLaunchPlanBuildArgsName",
                #"{"build":{"dockerfile":"Dockerfile","args":{"BAD-NAME":"secret-value"}}}"#,
                "build args contain an unsafe name",
                "secret-value"
            )
        ]

        for testCase in cases {
            let repoURL = try makeTemporaryDirectory(prefix: testCase.prefix)
            try write(testCase.json, to: devcontainerURL(in: repoURL))

            let plan = CodexExecutionLaunchPlan.plan(
                repoURL: repoURL,
                preference: .devcontainerPreferred,
                containerToolResolver: { _ in "/usr/local/bin/container" }
            )
            let report = try XCTUnwrap(plan.devcontainerSupportReport)

            XCTAssertFalse(plan.isContainerRoute)
            XCTAssertEqual(report.classification, .malformed)
            XCTAssertTrue(plan.fallbackReason?.contains(testCase.reasonToken) == true)
            XCTAssertFalse(plan.fallbackReason?.contains(testCase.leakedValue) == true)
            XCTAssertLessThanOrEqual(
                plan.fallbackReason?.count ?? 0,
                CodexExecutionLaunchPlan.fallbackReasonLimit
            )
        }
    }

    func testMalformedBuildShapesFallBackWithBoundedReasons() throws {
        let cases: [(prefix: String, json: String, reasonToken: String)] = [
            (
                "CodexExecutionLaunchPlanBuildBoolean",
                #"{"build":true}"#,
                "build must be a string or object"
            ),
            (
                "CodexExecutionLaunchPlanBuildContextArray",
                #"{"build":{"dockerfile":"Dockerfile","context":["/tmp/secret-context"]}}"#,
                "build.context must be a string"
            ),
            (
                "CodexExecutionLaunchPlanBuildTargetEmpty",
                #"{"build":{"dockerfile":"Dockerfile","target":" "}}"#,
                "build.target must not be empty"
            )
        ]

        for testCase in cases {
            let repoURL = try makeTemporaryDirectory(prefix: testCase.prefix)
            try write(testCase.json, to: devcontainerURL(in: repoURL))

            let plan = CodexExecutionLaunchPlan.plan(
                repoURL: repoURL,
                preference: .devcontainerPreferred,
                containerToolResolver: { _ in "/usr/local/bin/container" }
            )

            XCTAssertFalse(plan.isContainerRoute)
            XCTAssertEqual(plan.devcontainerSupportReport?.classification, .malformed)
            XCTAssertTrue(plan.fallbackReason?.contains(testCase.reasonToken) == true)
            XCTAssertFalse(plan.fallbackReason?.contains("/tmp/secret-context") == true)
            XCTAssertLessThanOrEqual(
                plan.fallbackReason?.count ?? 0,
                CodexExecutionLaunchPlan.fallbackReasonLimit
            )
        }
    }

    func testBuildContextDiagnosticsDoNotExposeAbsoluteRepoPaths() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBuildPath")
        let rawContext = repoURL
            .appending(path: "secret-context", directoryHint: .isDirectory)
            .path
        try write(
            #"{"build":{"dockerfile":"\#(rawContext)/Dockerfile","context":"\#(rawContext)","target":"runtime","args":{"TOKEN":"secret-value"}}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)
        let diagnosticsText = [
            report.supportSummary,
            plan.preflightSummary(phase: "Verify"),
            plan.routeDetail()
        ].joined(separator: " ")

        XCTAssertEqual(report.supportTokens, [
            "build",
            "dockerfile:absolute",
            "context:absolute",
            "target:runtime",
            "buildArgs:1",
            "arg:TOKEN"
        ])
        XCTAssertFalse(diagnosticsText.contains(rawContext))
        XCTAssertFalse(diagnosticsText.contains("secret-value"))
    }

    func testUnsafeBuildPathsDisableBuildConfigurationWithoutLeakingPaths() throws {
        let cases: [(prefix: String, json: String, expectedTokens: [String], leakedPathToken: String)] = [
            (
                "CodexExecutionLaunchPlanBuildAbsolutePath",
                #"{"build":{"dockerfile":"/tmp/private/Dockerfile","context":".."}}"#,
                ["build", "dockerfile:absolute", "context:repo-root"],
                "/tmp/private"
            ),
            (
                "CodexExecutionLaunchPlanBuildOutOfRepoContext",
                #"{"build":{"dockerfile":"Dockerfile","context":"../.."}}"#,
                ["build", "dockerfile:Dockerfile", "context:out-of-repo"],
                "../.."
            )
        ]

        for testCase in cases {
            let repoURL = try makeTemporaryDirectory(prefix: testCase.prefix)
            try write(testCase.json, to: devcontainerURL(in: repoURL))

            let plan = CodexExecutionLaunchPlan.plan(
                repoURL: repoURL,
                preference: .devcontainerPreferred,
                containerToolResolver: { _ in "/usr/local/bin/container" }
            )
            let report = try XCTUnwrap(plan.devcontainerSupportReport)
            let diagnosticsText = [
                report.supportSummary,
                plan.preflightSummary(phase: "Develop"),
                plan.routeDetail()
            ].joined(separator: " ")

            XCTAssertFalse(plan.isContainerRoute)
            XCTAssertEqual(report.classification, .buildBased)
            XCTAssertNil(report.buildConfiguration)
            XCTAssertEqual(report.supportTokens, testCase.expectedTokens)
            XCTAssertFalse(diagnosticsText.contains(testCase.leakedPathToken))
            XCTAssertFalse(diagnosticsText.contains(repoURL.deletingLastPathComponent().standardizedFileURL.path))
        }
    }

    func testUnsupportedComposeConfigFallsBackToNative() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanCompose")
        try write(
            #"{"dockerComposeFile":"compose.yml","service":"app"}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(
            plan.fallbackReason,
            "Unsupported devcontainer route: compose-based tokens compose,extra:service."
        )
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .composeBased)
        XCTAssertEqual(plan.devcontainerSupportReport?.supportTokens, ["compose", "extra:service"])
    }

    func testMixedUnsupportedConfigReportsDeterministicSupportTokens() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanMixed")
        try write(
            #"{"image":"swift:6.0","dockerComposeFile":"compose.yml","build":{"dockerfile":"Dockerfile"},"features":{"ghcr.io/devcontainers/features/git:1":{}},"postCreateCommand":"swift test","remoteUser":"vscode"}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .composeBased)
        XCTAssertEqual(
            plan.devcontainerSupportReport?.supportTokens,
            ["compose", "build", "dockerfile:Dockerfile", "features", "extra:postCreateCommand", "extra:remoteUser"]
        )
        XCTAssertTrue(plan.fallbackReason?.contains("compose-based tokens compose,build,dockerfile:Dockerfile") == true)

        let preflight = plan.preflightSummary(phase: "Develop")
        XCTAssertTrue(preflight.contains("devcontainer compose-based tokens compose,build,dockerfile:Dockerfile"))
        XCTAssertTrue(preflight.contains("extra:postCreateCommand"))
        XCTAssertTrue(preflight.contains("extra:remoteUser"))
    }

    func testFeaturesOnlyConfigFallsBackWithoutRouting() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanFeatures")
        try write(
            #"{"features":{"ghcr.io/devcontainers/features/node:1":{}}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .featureBased)
        XCTAssertEqual(plan.devcontainerSupportReport?.supportTokens, ["features"])
        XCTAssertEqual(plan.fallbackReason, "Unsupported devcontainer route: feature-based tokens features.")
    }

    func testOversizedContainerEnvValueIsMalformedWithoutLeakingValue() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanEnvOversized")
        let secretValue = "secret-value-" + String(
            repeating: "x",
            count: CodexDevcontainerEnvironmentVariable.valueLimit
        )
        try write(
            #"{"image":"swift:6.0","containerEnv":{"SAFE_NAME":"\#(secretValue)"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(report.classification, .malformed)
        XCTAssertTrue(plan.fallbackReason?.contains("containerEnv value exceeds") == true)
        XCTAssertFalse(plan.fallbackReason?.contains("secret-value") == true)
        XCTAssertLessThanOrEqual(
            plan.fallbackReason?.count ?? 0,
            CodexExecutionLaunchPlan.fallbackReasonLimit
        )
    }

    func testInvalidContainerEnvShapesFallBackToNative() throws {
        let cases: [(prefix: String, json: String, reasonToken: String)] = [
            (
                "CodexExecutionLaunchPlanEnvArray",
                #"{"image":"swift:6.0","containerEnv":["SAFE_NAME"]}"#,
                "containerEnv must be an object"
            ),
            (
                "CodexExecutionLaunchPlanEnvBoolean",
                #"{"image":"swift:6.0","containerEnv":{"SAFE_NAME":true}}"#,
                "containerEnv values must be strings"
            )
        ]

        for testCase in cases {
            let repoURL = try makeTemporaryDirectory(prefix: testCase.prefix)
            try write(testCase.json, to: devcontainerURL(in: repoURL))

            let plan = CodexExecutionLaunchPlan.plan(
                repoURL: repoURL,
                preference: .devcontainerPreferred,
                containerToolResolver: { _ in "/usr/local/bin/container" }
            )

            XCTAssertFalse(plan.isContainerRoute)
            XCTAssertEqual(plan.devcontainerSupportReport?.classification, .malformed)
            XCTAssertTrue(plan.fallbackReason?.contains(testCase.reasonToken) == true)
            XCTAssertLessThanOrEqual(
                plan.fallbackReason?.count ?? 0,
                CodexExecutionLaunchPlan.fallbackReasonLimit
            )
        }
    }

    func testUnsafeContainerEnvNameIsMalformedWithoutLeakingValue() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanEnvUnsafe")
        try write(
            #"{"image":"swift:6.0","containerEnv":{"BAD-NAME":"secret-value"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .malformed)
        XCTAssertTrue(plan.fallbackReason?.contains("unsafe variable name") == true)
        XCTAssertFalse(plan.fallbackReason?.contains("secret-value") == true)
    }

    func testRemoteEnvStillFallsBackToNativeWithoutLeakingValues() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanRemoteEnv")
        try write(
            #"{"image":"swift:6.0","containerEnv":{"SAFE_NAME":"ok"},"remoteEnv":{"API_TOKEN":"remote-secret"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)
        let diagnosticsText = [
            report.supportSummary,
            plan.preflightSummary(phase: "Develop"),
            plan.routeDetail()
        ].joined(separator: " ")

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(report.classification, .unsupportedExtraFields)
        XCTAssertEqual(report.supportTokens, ["containerEnv:1", "env:SAFE_NAME", "extra:remoteEnv"])
        XCTAssertTrue(plan.fallbackReason?.contains("extra:remoteEnv") == true)
        XCTAssertTrue(diagnosticsText.contains("env:SAFE_NAME"))
        XCTAssertFalse(diagnosticsText.contains("remote-secret"))
    }

    func testSupportSummaryAndReasonsStayBoundedForManyUnsupportedKeys() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBounded")
        let extraFields = (0..<18)
            .map { #""custom\#(String(format: "%02d", $0))":true"# }
            .joined(separator: ",")
        try write(
            #"{"image":"swift:6.0",\#(extraFields)}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )
        let report = try XCTUnwrap(plan.devcontainerSupportReport)

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(report.classification, .unsupportedExtraFields)
        XCTAssertEqual(report.omittedTokenCount, 10)
        XCTAssertTrue(report.tokenSummary.contains("+10-more"))
        XCTAssertLessThanOrEqual(report.supportSummary.count, CodexDevcontainerSupportReport.supportSummaryLimit)
        XCTAssertLessThanOrEqual(plan.fallbackReason?.count ?? 0, CodexExecutionLaunchPlan.fallbackReasonLimit)
    }

    func testNoContainerToolFallsBackToNative() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanNoTool")
        try write(#"{"image":"swift:6.0"}"#, to: devcontainerURL(in: repoURL))

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in nil }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.imageLabel, "swift:6.0")
        XCTAssertEqual(plan.fallbackReason, "Apple container CLI is unavailable.")
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .imageRouteable)
    }

    func testBuildConfigFallsBackToNativeWhenContainerToolIsUnavailable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanBuildNoTool")
        try write(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"runtime"}}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in nil }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(plan.fallbackReason, "Apple container CLI is unavailable.")
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .buildBased)
        XCTAssertNotNil(plan.devcontainerSupportReport?.buildConfiguration)
    }

    func testWorkspaceOutsideMountedWorkspaceFallsBackToNative() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexExecutionLaunchPlanWorkspace")
        try write(
            #"{"image":"swift:6.0","workspaceFolder":"/workspaces/project"}"#,
            to: devcontainerURL(in: repoURL)
        )

        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .devcontainerPreferred,
            containerToolResolver: { _ in "/usr/local/bin/container" }
        )

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(
            plan.fallbackReason,
            "workspaceFolder must be an absolute /workspace path for Apple container routing. Tokens: workspaceFolder."
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }

    private func devcontainerURL(in repoURL: URL) -> URL {
        repoURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func repoRelativeURL(_ relativePath: String, in repoURL: URL) -> URL {
        URL(fileURLWithPath: relativePath, relativeTo: repoURL)
            .standardizedFileURL
    }
}
