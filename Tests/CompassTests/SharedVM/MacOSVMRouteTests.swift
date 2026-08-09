import CompassCore
import Foundation
import Testing

struct MacOSVMRouteTests {

  // MARK: - Launch plan route model

  @Test
  func macOSVMRouteIsMarkedAsVMRoute() {
    let plan = AgentExecutionLaunchPlan.macOSVM(repoURL: URL(fileURLWithPath: "/tmp/repo"))
    #expect(plan.isVMRoute)
    #expect(plan.selectedPreference == .macOSVM)
    #expect(plan.effectiveRouteIdentifier == "macos-vm")
    #expect(plan.effectiveRouteTitle == "macOS VM")
  }

  @Test
  func planAlwaysSelectsVMRoute() {
    let repo = URL(fileURLWithPath: "/tmp/repo")
    let vmPlan = AgentExecutionLaunchPlan.plan(repoURL: repo, preference: .macOSVM)
    #expect(vmPlan.isVMRoute)
    #expect(AgentExecutionLaunchPlan.plan(repoURL: repo).isVMRoute)
  }

  @Test
  func macOSVMRouteDefaultsGuestWorkspaceToLayoutContract() {
    let plan = AgentExecutionLaunchPlan.macOSVM(repoURL: URL(fileURLWithPath: "/tmp/repo"))
    guard case .macOSVM(let route) = plan.effectiveRoute else {
      Issue.record("expected macOSVM route")
      return
    }
    #expect(route.guestWorkspacePath == SharedCompassVMGuestLayout.current.reposRoot)
    #expect(route.hostWorkspacePath == "/tmp/repo")
  }

  // MARK: - Preference decoding

  @Test
  func macOSVMIdentifierRoundTrips() throws {
    let encoded = try JSONEncoder().encode(AgentExecutionEnvironmentPreference.macOSVM)
    let decoded = try JSONDecoder().decode(
      AgentExecutionEnvironmentPreference.self, from: encoded)
    #expect(decoded == .macOSVM)
  }

  @Test
  func unknownPreferenceIdentifierFailsDecode() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        AgentExecutionEnvironmentPreference.self,
        from: Data(#""shared_vm""#.utf8)
      )
    }
  }

  // MARK: - Bash runtime

  @Test
  func bashRuntimeIsAlwaysMacOSVM() {
    #expect(HeadlessCompassRunner.bashRuntimeName == "macos_vm")
    #expect(HeadlessCompassRunner.bashRuntimeDescription == "embedded macOS VM")
  }

  // MARK: - Guest working directory mapping

  @Test
  func guestWorkingDirectoryMapsRepoRootAndSubdirectories() throws {
    let runner = AgentMacOSVMBashRunner(repoRoot: URL(fileURLWithPath: "/tmp/repo"))
    #expect(
      try runner.guestWorkingDirectory(
        for: URL(fileURLWithPath: "/tmp/repo"),
        guestWorktreePath: "/Users/compass/Compass/Repos/abc/worktree"
      ) == "/Users/compass/Compass/Repos/abc/worktree")
    #expect(
      try runner.guestWorkingDirectory(
        for: URL(fileURLWithPath: "/tmp/repo/apps/macos"),
        guestWorktreePath: "/Users/compass/Compass/Repos/abc/worktree"
      ) == "/Users/compass/Compass/Repos/abc/worktree/apps/macos")
  }

  @Test
  func guestWorkingDirectoryRejectsPathsOutsideRepo() {
    let runner = AgentMacOSVMBashRunner(repoRoot: URL(fileURLWithPath: "/tmp/repo"))
    #expect(throws: AgentMacOSVMBashRunner.VMRunnerError.self) {
      try runner.guestWorkingDirectory(
        for: URL(fileURLWithPath: "/tmp/other"),
        guestWorktreePath: "/Users/compass/Compass/Repos/abc/worktree"
      )
    }
  }

  @Test
  func readinessTimeoutParsesEnvironment() {
    #expect(AgentMacOSVMBashRunner.readinessTimeoutSeconds(environment: [:]) == 1800)
    #expect(
      AgentMacOSVMBashRunner.readinessTimeoutSeconds(
        environment: ["COMPASS_MACOS_VM_READY_TIMEOUT": "60"]) == 60)
    #expect(
      AgentMacOSVMBashRunner.readinessTimeoutSeconds(
        environment: ["COMPASS_MACOS_VM_READY_TIMEOUT": "-5"]) == 1800)
  }
}
