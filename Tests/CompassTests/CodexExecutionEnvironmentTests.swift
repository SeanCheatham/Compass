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
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .unavailable(reason: "2-guest cap reached")
        )
        let launchPlan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
        let presentation = environment.presentation(launchPlan: launchPlan)
        XCTAssertTrue(presentation.isWarning)
        XCTAssertTrue(presentation.detail.contains("2-guest cap reached"))
        XCTAssertEqual(launchPlan.effectiveRouteIdentifier, "native-macos")
    }

    func testMenuAndPreflightExposeUnsupportedFallbackTokens() throws {
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .installing(fractionCompleted: 0.4)
        )
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        XCTAssertEqual(menu.items.count, 2)
        XCTAssertTrue(menu.statusText.contains("installing"))
    }

    func testFeatureDiscoveryMenusExposeSanitizedFeatureCountsWithoutValues() throws {
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .codexLoginPending
        )
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        XCTAssertTrue(menu.helpText.contains("codex login"))
    }

    func testComposeDiscoveryMenusExposeSanitizedComposeTokensWithoutPaths() throws {
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .guestPrepping
        )
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        XCTAssertTrue(menu.statusText.contains("preparation"))
    }

    func testBuildRouteableDiscoveryAndPreflightExposeLocalImageWithoutPaths() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "ReadyDiscovery")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex"
        )
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let plan = environment.launchPlan(repoURL: repoURL) { _ in route }
        let preflight = plan.preflightSummary(phase: "Develop")
        XCTAssertTrue(preflight.contains("Shared VM"))
        XCTAssertTrue(preflight.contains("compass@192.0.2.10"))
        XCTAssertFalse(preflight.contains(repoURL.path))
    }

    func testContainerEnvDiagnosticsExposeNamesWithoutValues() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "EnvDiagnostics")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex",
            environmentVariables: ["SECRET_TOKEN": "super-secret"]
        )
        let plan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let report = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        XCTAssertFalse(report.copyText.contains("super-secret"))
        XCTAssertTrue(report.copyText.contains("effective-route: shared-vm"))
    }

    func testRuntimeDiagnosticsReportForImageRouteIsCopyableSanitizedAndStable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "DiagnosticsStable")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex"
        )
        let plan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let report = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        let report2 = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        XCTAssertEqual(report.copyIdentifier, report2.copyIdentifier)
        XCTAssertTrue(report.copyText.contains("vm-readiness: ready"))
    }

    func testRuntimeDiagnosticsReportForBuildRouteHidesBuildArgValuesAndPaths() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "DiagnosticsHidePaths")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex"
        )
        let plan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let environment = CodexExecutionEnvironment.discover(
            preference: .sharedVM,
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let report = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        XCTAssertFalse(report.copyText.contains(repoURL.path))
    }

    func testRuntimeDiagnosticsReportIncludesMutationReadinessWithoutLeaks() throws {
        let plan = CodexExecutionLaunchPlan.host()
        let environment = CodexExecutionEnvironment.discover(preference: .host, vmReadiness: .notProvisioned)
        var counts = RepositoryLanguageCounts()
        counts[.swift] = 1
        let mutationPlan = CodexMutationTestingPlan(
            immediate: PlanNext(plan: "Improve coverage", verify: "swift test"),
            languageProfile: RepositoryLanguageProfile(
                counts: counts,
                manifestHints: [],
                primaryLanguage: .swift,
                scannedFileCount: 1,
                scannedDirectoryCount: 1,
                wasTruncated: false
            ),
            launchPlan: plan
        )
        let report = CodexExecutionEnvironmentDiagnosticsReport(
            environment: environment,
            launchPlan: plan,
            mutationTestingPlan: mutationPlan
        )
        XCTAssertTrue(report.copyText.contains("mutation-language: swift"))
    }

    func testRuntimeDiagnosticsReportCoversMissingAndMalformedProvisioningStates() throws {
        let plan = CodexExecutionLaunchPlan.host()
        let environment = CodexExecutionEnvironment.discover(preference: .host, vmReadiness: .notProvisioned)
        let report = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        XCTAssertTrue(report.copyText.contains("vm-build-state:"))
    }

    func testRuntimeDiagnosticsReportSanitizesFallbackConfigsWithoutUnsupportedValues() throws {
        let plan = CodexExecutionLaunchPlan.host(fallbackReason: "Shared VM unavailable: 2-guest cap")
        let environment = CodexExecutionEnvironment.discover(preference: .sharedVM, vmReadiness: .unavailable(reason: "2-guest cap"))
        let report = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        XCTAssertTrue(report.copyText.contains("fallback:"))
    }

    func testRuntimeDiagnosticsReportIncludesOmittedSupportTokenCounts() throws {
        let plan = CodexExecutionLaunchPlan.host()
        let environment = CodexExecutionEnvironment.discover(preference: .sharedVM, vmReadiness: .notProvisioned)
        let report = CodexExecutionEnvironmentDiagnosticsReport(environment: environment, launchPlan: plan)
        XCTAssertEqual(report.effectiveRouteIdentifier, "native-macos")
    }

    func testMissingDevcontainerPresentationFallsBackToNativeMacOS() throws {
        let environment = CodexExecutionEnvironment.discover(preference: .host, vmReadiness: .notProvisioned)
        let presentation = environment.presentation
        XCTAssertEqual(presentation.title, "Native macOS")
        XCTAssertFalse(presentation.isWarning)
    }

    func testMalformedDevcontainerPresentationIsBoundedAndFallsBackToNativeMacOS() throws {
        let environment = CodexExecutionEnvironment.discover(preference: .sharedVM, vmReadiness: .error(detail: "boot failed"))
        let presentation = environment.presentation
        XCTAssertTrue(presentation.isWarning)
    }

    func testNativePreferenceKeepsDevcontainerOptionalWhenConfigIsPresent() throws {
        let environment = CodexExecutionEnvironment.discover(preference: .host, vmReadiness: .ready(sshDestination: "compass@192.0.2.10"))
        let menu = CodexExecutionEnvironmentMenu(environment: environment)
        XCTAssertTrue(menu.items.contains { $0.preference == .sharedVM })
    }

    func testDiscoveryDoesNotCreateDevcontainerFilesWhenConfigIsMissing() throws {
        let environment = CodexExecutionEnvironment.discover(preference: .sharedVM, vmReadiness: .notProvisioned)
        XCTAssertEqual(environment.readiness.vmReadiness, .notProvisioned)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }
}
