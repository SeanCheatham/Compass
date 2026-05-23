import Foundation
import XCTest

@testable import Compass

final class AgentExecutionEnvironmentTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testDiscoveryReportsUnsupportedDevcontainerConfigWithNativeFallbackDiagnostics() throws {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .unavailable(reason: "2-guest cap reached")
    )
    let launchPlan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: launchPlan)
    XCTAssertTrue(presentation.isWarning)
    XCTAssertTrue(presentation.detail.contains("2-guest cap reached"))
    XCTAssertEqual(launchPlan.effectiveRouteIdentifier, "native-macos")
  }

  func testMenuAndPreflightExposeUnsupportedFallbackTokens() throws {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .installing(fractionCompleted: 0.4)
    )
    let menu = AgentExecutionEnvironmentMenu(environment: environment)
    XCTAssertTrue(menu.statusText.contains("installing"))
  }

  func testComposeDiscoveryMenusExposeSanitizedComposeTokensWithoutPaths() throws {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .guestPrepping
    )
    let menu = AgentExecutionEnvironmentMenu(environment: environment)
    XCTAssertTrue(menu.statusText.contains("preparation") || menu.statusText.contains("preparing"))
  }

  func testBuildRouteableDiscoveryAndPreflightExposeLocalImageWithoutPaths() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "ReadyDiscovery")
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.10",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-AAA/worktree"
    )
    let environment = AgentExecutionEnvironment.discover(
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
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-AAA/worktree",
      environmentVariables: ["SECRET_TOKEN": "super-secret"]
    )
    let plan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    XCTAssertFalse(report.copyText.contains("super-secret"))
    XCTAssertTrue(report.copyText.contains("effective-route: shared-vm"))
  }

  func testRuntimeDiagnosticsReportForImageRouteIsCopyableSanitizedAndStable() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "DiagnosticsStable")
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.10",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-AAA/worktree"
    )
    let plan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    let report2 = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    XCTAssertEqual(report.copyIdentifier, report2.copyIdentifier)
    XCTAssertTrue(report.copyText.contains("vm-readiness: ready"))
  }

  func testRuntimeDiagnosticsReportForBuildRouteHidesBuildArgValuesAndPaths() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "DiagnosticsHidePaths")
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.10",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-AAA/worktree"
    )
    let plan = AgentExecutionLaunchPlan(
      selectedPreference: .sharedVM,
      effectiveRoute: .sharedVM(route),
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .ready(sshDestination: route.sshDestination)
    )
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    XCTAssertFalse(report.copyText.contains(repoURL.path))
  }

  func testRuntimeDiagnosticsReportIncludesMutationReadinessWithoutLeaks() throws {
    let plan = AgentExecutionLaunchPlan.host()
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    var counts = RepositoryLanguageCounts()
    counts[.swift] = 1
    let mutationPlan = AgentMutationTestingPlan(
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
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment,
      launchPlan: plan,
      mutationTestingPlan: mutationPlan
    )
    XCTAssertTrue(report.copyText.contains("mutation-language: swift"))
  }

  func testRuntimeDiagnosticsReportCoversMissingAndMalformedProvisioningStates() throws {
    let plan = AgentExecutionLaunchPlan.host()
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    XCTAssertTrue(report.copyText.contains("vm-build-state:"))
  }

  func testRuntimeDiagnosticsReportSanitizesFallbackConfigsWithoutUnsupportedValues() throws {
    let plan = AgentExecutionLaunchPlan.host(fallbackReason: "Shared VM unavailable: 2-guest cap")
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .unavailable(reason: "2-guest cap"))
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    XCTAssertTrue(report.copyText.contains("fallback:"))
  }

  func testRuntimeDiagnosticsReportIncludesOmittedSupportTokenCounts() throws {
    let plan = AgentExecutionLaunchPlan.host()
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    XCTAssertEqual(report.effectiveRouteIdentifier, "native-macos")
  }

  func testNotProvisionedReadinessPresentationIsWarning() throws {
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    let plan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: plan)
    XCTAssertEqual(presentation.title, "Shared VM")
    XCTAssertTrue(presentation.isWarning)
  }

  func testErrorReadinessPresentationIsWarning() throws {
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .error(detail: "boot failed"))
    let plan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: plan)
    XCTAssertTrue(presentation.isWarning)
  }

  func testReadyVMWithHostRouteIsInformationalNotAWarning() throws {
    // VM is ready, but the launch plan resolves to host because the
    // worktree path sits outside the workspaces share — the by-design
    // Plan/Reflect routing. The presentation should reflect a healthy
    // VM, not a warning.
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .ready(sshDestination: "compass@192.0.2.10")
    )
    let plan = AgentExecutionLaunchPlan.host(
      vmReadiness: .ready(sshDestination: "compass@192.0.2.10"),
      fallbackReason:
        "Worktree is outside the Shared VM workspaces share; this phase runs on the host."
    )
    let presentation = environment.presentation(launchPlan: plan)
    XCTAssertFalse(presentation.isWarning)
    XCTAssertTrue(presentation.status.contains("Develop iterations"))
    XCTAssertEqual(presentation.title, "Shared VM")
  }

  func testDiscoveryWithNotProvisionedReadinessPreservesReadiness() throws {
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    XCTAssertEqual(environment.readiness.vmReadiness, SharedCompassVMReadiness.notProvisioned)
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
