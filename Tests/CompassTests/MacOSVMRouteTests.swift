import CompassCore
import Foundation
import Testing

struct MacOSVMRouteTests {

  // MARK: - Launch plan route model

  @Test
  func macOSVMRouteIsMarkedAsVMRoute() {
    let plan = AgentExecutionLaunchPlan.macOSVM(repoURL: URL(fileURLWithPath: "/tmp/repo"))
    #expect(plan.isVMRoute)
    #expect(!plan.isContainerRoute)
    #expect(plan.selectedPreference == .macOSVM)
    #expect(plan.effectiveRouteIdentifier == "macos-vm")
    #expect(plan.effectiveRouteTitle == "macOS VM")
  }

  @Test
  func containerRouteIsNotVMRoute() {
    let plan = AgentExecutionLaunchPlan.containerizedLinux(
      repoURL: URL(fileURLWithPath: "/tmp/repo"))
    #expect(!plan.isVMRoute)
    #expect(plan.isContainerRoute)
  }

  @Test
  func planWithPreferenceSelectsVMRoute() {
    let repo = URL(fileURLWithPath: "/tmp/repo")
    let vmPlan = AgentExecutionLaunchPlan.plan(repoURL: repo, preference: .macOSVM)
    #expect(vmPlan.isVMRoute)
    let containerPlan = AgentExecutionLaunchPlan.plan(repoURL: repo, preference: .containerizedLinux)
    #expect(containerPlan.isContainerRoute)
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
  func legacySharedVMIdentifierMigratesToMacOSVM() throws {
    let decoded = try JSONDecoder().decode(
      AgentExecutionEnvironmentPreference.self,
      from: Data(#""shared_vm""#.utf8)
    )
    #expect(decoded == .macOSVM)
  }

  @Test
  func macOSVMIdentifierRoundTrips() throws {
    let encoded = try JSONEncoder().encode(AgentExecutionEnvironmentPreference.macOSVM)
    let decoded = try JSONDecoder().decode(
      AgentExecutionEnvironmentPreference.self, from: encoded)
    #expect(decoded == .macOSVM)
  }

  @Test
  func unknownIdentifierFallsBackToContainer() throws {
    let decoded = try JSONDecoder().decode(
      AgentExecutionEnvironmentPreference.self,
      from: Data(#""something_else""#.utf8)
    )
    #expect(decoded == .containerizedLinux)
  }

  // MARK: - Bash runtime selection

  @Test
  func bashRuntimeSelectionParsesVMIdentifiers() {
    #expect(
      HeadlessCompassRunner.bashRuntimeSelection(environment: ["COMPASS_BASH_RUNTIME": "macos_vm"])
        == .macOSVM)
    #expect(
      HeadlessCompassRunner.bashRuntimeSelection(environment: ["COMPASS_BASH_RUNTIME": "shared_vm"])
        == .macOSVM)
    #expect(
      HeadlessCompassRunner.bashRuntimeSelection(environment: ["COMPASS_BASH_RUNTIME": "host"])
        == .host)
    #expect(HeadlessCompassRunner.bashRuntimeSelection(environment: [:]) == .containerizedLinux)
  }

  // MARK: - macOS verify runtime preference

  @Test
  func verifyRuntimeDefaultsToVM() {
    let suite = UserDefaults(suiteName: "MacOSVMRouteTests.verifyRuntimeDefaultsToVM")!
    #expect(MacOSVerifyRuntime.current(environment: [:], defaults: suite) == .vm)
  }

  @Test
  func verifyRuntimeHonorsEnvironmentOverride() {
    #expect(
      MacOSVerifyRuntime.current(environment: ["COMPASS_MACOS_VERIFY_RUNTIME": "host"]) == .host)
    #expect(
      MacOSVerifyRuntime.current(environment: ["COMPASS_MACOS_VERIFY_RUNTIME": " vm "]) == .vm)
  }

  @Test
  func verifyRuntimeHonorsDefaultsOverride() {
    let suiteName = "MacOSVMRouteTests.verifyRuntimeHonorsDefaultsOverride"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.set("host", forKey: MacOSVerifyRuntime.defaultsKey)
    defer { suite.removePersistentDomain(forName: suiteName) }
    #expect(MacOSVerifyRuntime.current(environment: [:], defaults: suite) == .host)
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
