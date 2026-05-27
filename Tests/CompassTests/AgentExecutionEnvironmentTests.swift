import Foundation
import Testing

@testable import Compass

struct AgentExecutionEnvironmentTests: ~Copyable {
  private var temporaryDirectories: [URL] = []

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
  }

  @Test func testDiscoveryReportsUnsupportedDevcontainerConfigWithNativeFallbackDiagnostics() throws {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .unavailable(reason: "2-guest cap reached")
    )
    let launchPlan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: launchPlan)
    #require(presentation.isWarning)
    #require(presentation.detail.contains("2-guest cap reached"))
    #require(launchPlan.effectiveRouteIdentifier == "native-macos")
  }

  @Test func testMenuAndPreflightExposeUnsupportedFallbackTokens() throws {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .installing(fractionCompleted: 0.4)
    )
    let menu = AgentExecutionEnvironmentMenu(environment: environment)
    #require(menu.statusText.contains("installing"))
  }

  @Test func testComposeDiscoveryMenusExposeSanitizedComposeTokensWithoutPaths() throws {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .guestPrepping
    )
    let menu = AgentExecutionEnvironmentMenu(environment: environment)
    #require(menu.statusText.contains("preparation") || menu.statusText.contains("preparing"))
  }

  @Test func testBuildRouteableDiscoveryAndPreflightExposeLocalImageWithoutPaths() throws {
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
    #require(preflight.contains("Shared VM"))
    #require(preflight.contains("compass@192.0.2.10"))
    #require(!preflight.contains(repoURL.path))
  }

  @Test func testContainerEnvDiagnosticsExposeNamesWithoutValues() throws {
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
    #require(!report.copyText.contains("super-secret"))
    #require(report.copyText.contains("effective-route: shared-vm"))
  }

  @Test func testRuntimeDiagnosticsReportForImageRouteIsCopyableSanitizedAndStable() throws {
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
    #require(report.copyIdentifier == report2.copyIdentifier)
    #require(report.copyText.contains("vm-readiness: ready"))
  }

  @Test func testRuntimeDiagnosticsReportForBuildRouteHidesBuildArgValuesAndPaths() throws {
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
    #require(!report.copyText.contains(repoURL.path))
  }

  @Test func testRuntimeDiagnosticsReportCoversMissingAndMalformedProvisioningStates() throws {
    let plan = AgentExecutionLaunchPlan.host()
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    #require(report.copyText.contains("vm-build-state:"))
  }

  @Test func testRuntimeDiagnosticsReportSanitizesFallbackConfigsWithoutUnsupportedValues() throws {
    let plan = AgentExecutionLaunchPlan.host(fallbackReason: "Shared VM unavailable: 2-guest cap")
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .unavailable(reason: "2-guest cap"))
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    #require(report.copyText.contains("fallback:"))
  }

  @Test func testRuntimeDiagnosticsReportIncludesOmittedSupportTokenCounts() throws {
    let plan = AgentExecutionLaunchPlan.host()
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    let report = AgentExecutionEnvironmentDiagnosticsReport(
      environment: environment, launchPlan: plan)
    #require(report.effectiveRouteIdentifier == "native-macos")
  }

  @Test func testNotProvisionedReadinessPresentationIsWarning() throws {
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    let plan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: plan)
    #require(presentation.title == "Shared VM")
    #require(presentation.isWarning)
  }

  @Test func testErrorReadinessPresentationIsWarning() throws {
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .error(detail: "boot failed"))
    let plan = environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
    let presentation = environment.presentation(launchPlan: plan)
    #require(presentation.isWarning)
  }

  @Test func testReadyVMWithHostRouteIsInformationalNotAWarning() throws {
    // VM is ready, but the launch plan resolves to host as an internal
    // fallback. The presentation should reflect a healthy VM, not a warning.
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: .ready(sshDestination: "compass@192.0.2.10")
    )
    let plan = AgentExecutionLaunchPlan.host(
      vmReadiness: .ready(sshDestination: "compass@192.0.2.10"),
      fallbackReason:
        "Guest workspace catalog could not map this repo."
    )
    let presentation = environment.presentation(launchPlan: plan)
    #require(!presentation.isWarning)
    #require(presentation.status.contains("internal fallback"))
    #require(presentation.title == "Shared VM")
  }

  @Test func testDiscoveryWithNotProvisionedReadinessPreservesReadiness() throws {
    let environment = AgentExecutionEnvironment.discover(vmReadiness: .notProvisioned)
    #require(environment.readiness.vmReadiness == SharedCompassVMReadiness.notProvisioned)
  }

  // MARK: - Helpers

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
  }
}
