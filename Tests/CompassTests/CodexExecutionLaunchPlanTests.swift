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

    func testUnsupportedBuildConfigFallsBackToNative() throws {
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

        XCTAssertFalse(plan.isContainerRoute)
        XCTAssertEqual(
            plan.fallbackReason,
            "Unsupported devcontainer route: build-based tokens build."
        )
        XCTAssertEqual(plan.devcontainerSupportReport?.classification, .buildBased)
        XCTAssertEqual(plan.devcontainerSupportReport?.supportTokens, ["build"])
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
            ["compose", "build", "features", "extra:postCreateCommand", "extra:remoteUser"]
        )
        XCTAssertTrue(plan.fallbackReason?.contains("compose-based tokens compose,build,features") == true)

        let preflight = plan.preflightSummary(phase: "Develop")
        XCTAssertTrue(preflight.contains("devcontainer compose-based tokens compose,build,features"))
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
}
