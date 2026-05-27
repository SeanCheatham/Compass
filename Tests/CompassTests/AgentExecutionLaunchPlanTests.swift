import Foundation
import Testing

@testable import Compass

struct AgentExecutionLaunchPlanTests: ~Copyable {
  private var temporaryDirectories: [URL] = []

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Routing

  @Test func testReadySharedVMRoutesThroughVsockWhenFactoryProducesARoute() throws {
    // With the vsock guest agent in place, a ready run with a route
    // factory that returns a workspace-mapped route promotes to a real
    // .sharedVM effective route. AppModel then opens a vsock connection
    // to the guest agent for each tool call.
    let repoURL = try makeTemporaryDirectory(prefix: "VMReadyRoutes")
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.10",
      hostWorktreeURL: repoURL,
      guestWorkspacePath: "/Users/compass/Compass/Worktrees/dev-AAA/worktree"
    )
    let plan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .ready(sshDestination: route.sshDestination),
      sharedVMRouteFactory: { _ in route }
    )

    #require(plan.isVMRoute)
    #require(plan.effectiveRouteIdentifier == "shared-vm")
    #require(plan.fallbackReason == nil)
    #require(plan.workspaceLabel == "/Users/compass/Compass/Worktrees/dev-AAA/worktree")
  }

  @Test func testMissingConfigFallsBackToNativeWithBoundedReason() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "VMNotProvisioned")
    let plan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .notProvisioned
    )
    #require(!plan.isVMRoute)
    #require(plan.fallbackReason?.contains("not been provisioned") ?? false)
  }

  @Test func testMalformedConfigFallsBackToNativeWithBoundedReason() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "VMError")
    let plan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .error(detail: "ssh probe failed")
    )
    #require(!plan.isVMRoute)
    #require(plan.fallbackReason?.contains("ssh probe failed") ?? false)
  }

  @Test func testReadyButNoRouteableFactoryFallsBackToHost() throws {
    // When the VM is ready but the worktree isn't under the workspace
    // mount (factory returns nil), the planner falls back to host with
    // a workspace-share-membership reason. This is the internal-only
    // fallback the planner still keeps for Plan/Reflect on the main repo.
    let repoURL = try makeTemporaryDirectory(prefix: "VMReadyNoRoute")
    let plan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: .ready(sshDestination: "compass@192.0.2.10"),
      sharedVMRouteFactory: { _ in nil }
    )
    #require(!plan.isVMRoute)
    #require(plan.fallbackReason?.contains("outside the Shared VM workspaces share") ?? false)
  }

  @Test func testBuildConfigFallsBackToNativeWhenContainerToolIsUnavailable() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "VMReadinessMissing")
    let plan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: nil
    )
    #require(!plan.isVMRoute)
    #require(plan.fallbackReason?.contains("readiness has not been evaluated") ?? false)
  }

  // MARK: - Decoding

  @Test func testStoredPreferenceRawValuesDecodeToSharedVM() throws {
    for raw in ["devcontainer_preferred", "native_macos", "shared_vm"] {
      let json = #"{"value":"\#(raw)"}"#
      struct Wrapper: Decodable {
        var value: AgentExecutionEnvironmentPreference
      }
      let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
      #require(decoded.value == .sharedVM)
    }
  }

  @Test func testSharedVMRawValueRoundTrips() throws {
    let encoded = try JSONEncoder().encode(AgentExecutionEnvironmentPreference.sharedVM)
    let string = String(decoding: encoded, as: UTF8.self)
    #require(string == "\"shared_vm\"")
    let decoded = try JSONDecoder().decode(AgentExecutionEnvironmentPreference.self, from: encoded)
    #require(decoded == .sharedVM)
  }

  // MARK: - Snapshot

  @Test func testExecutionEnvironmentSnapshotForImageRouteIsCodableBoundedAndSanitized() throws {
    let repoURL = try makeTemporaryDirectory(prefix: "SnapshotRoundtrip")
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
    let snapshot = SessionExecutionEnvironmentSnapshot(
      phase: "Develop", attempt: 1, launchPlan: plan)
    #require(snapshot.effectiveRouteIdentifier == "shared-vm")
    #require(snapshot.provisioningAvailabilityIdentifier == "available")
    #require(snapshot.provisioningStatusIdentifier == "ready")
    #require(
      snapshot.provisioningActionIdentifier ==
      SessionExecutionEnvironmentSnapshot.vmBuildActionIdentifier)

    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(SessionExecutionEnvironmentSnapshot.self, from: encoded)
    #require(decoded == snapshot)
  }

  @Test func
    testExecutionEnvironmentSnapshotSummariesCoverNativeBuildComposeAndFeatureRoutesWithoutLeaks()
    throws
  {
    let repoURL = try makeTemporaryDirectory(prefix: "SnapshotSummaries")
    let scenarios: [(SharedCompassVMReadiness?, expectedClassification: String)] = [
      (nil, "not-inspected"),
      (.notProvisioned, "not-provisioned"),
      (.installing(fractionCompleted: 0.5), "installing"),
      (.guestPrepping, "guest-prepping"),
      (.unavailable(reason: "Intel"), "unavailable"),
    ]
    for (readiness, expectedClassification) in scenarios {
      let plan = AgentExecutionLaunchPlan.plan(
        repoURL: repoURL,
        vmReadiness: readiness
      )
      let snapshot = SessionExecutionEnvironmentSnapshot(phase: "Plan", launchPlan: plan)
      #require(snapshot.effectiveRouteIdentifier == "native-macos")
      #require(snapshot.supportClassificationIdentifier == expectedClassification)
      #require(!snapshot.routeSummary.contains(repoURL.path))
    }
  }

  // MARK: - Helpers

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
  }
}
