import Foundation
@testable import Compass
import XCTest

final class AgentExecutionLaunchPlanTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    // MARK: - Routing

    func testReadySharedVMFallsBackToHostUntilVsockTransportLands() throws {
        // The SSH-into-guest transport is TCC-blocked from reading the
        // VirtioFS-mounted worktree on macOS guests, so even a fully
        // provisioned + ready Shared VM falls back to host today. The
        // planner still consults the route factory (so workspace-resolution
        // failures surface in diagnostics), but the effective route is
        // host with an explanatory `fallbackReason`. Once the vsock guest
        // agent lands, this assertion flips back to `.isVMRoute == true`.
        let repoURL = try makeTemporaryDirectory(prefix: "VMReadyRoutes")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree"
        )
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .ready(sshDestination: route.sshDestination),
            sharedVMRouteFactory: { _ in route }
        )

        XCTAssertFalse(plan.isVMRoute)
        XCTAssertEqual(plan.effectiveRouteIdentifier, "native-macos")
        XCTAssertTrue(plan.fallbackReason?.contains("vsock") ?? false)
    }


    func testNativePreferenceStaysNativeEvenWhenSupportedConfigAndToolExist() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "HostPreference")
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .host,
            vmReadiness: .ready(sshDestination: "compass@192.0.2.99")
        )
        XCTAssertEqual(plan.effectiveRouteIdentifier, "native-macos")
        XCTAssertFalse(plan.isVMRoute)
    }

    func testNativePreferenceStaysNativeForRouteableBuildArgsConfig() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "HostPreferenceVMReady")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree"
        )
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .host,
            vmReadiness: .ready(sshDestination: route.sshDestination),
            sharedVMRouteFactory: { _ in route }
        )
        XCTAssertFalse(plan.isVMRoute)
    }

    func testMissingConfigFallsBackToNativeWithBoundedReason() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "VMNotProvisioned")
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .notProvisioned
        )
        XCTAssertFalse(plan.isVMRoute)
        XCTAssertTrue(plan.fallbackReason?.contains("not been provisioned") ?? false)
    }

    func testMalformedConfigFallsBackToNativeWithBoundedReason() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "VMError")
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .error(detail: "ssh probe failed")
        )
        XCTAssertFalse(plan.isVMRoute)
        XCTAssertTrue(plan.fallbackReason?.contains("ssh probe failed") ?? false)
    }

    func testReadyButNoRouteableFactoryStillFallsBackToHost() throws {
        // Pre-Phase-R this asserted a workspace-share-membership fallback
        // reason. Now every ready+sharedVM run falls back to host with
        // the vsock-pending reason, regardless of whether the factory
        // produces a route. The route factory is still invoked (so the
        // route-membership check runs and any future telemetry sees it),
        // but its result is ignored. Re-tighten when vsock lands.
        let repoURL = try makeTemporaryDirectory(prefix: "VMReadyNoRoute")
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: .ready(sshDestination: "compass@192.0.2.10"),
            sharedVMRouteFactory: { _ in nil }
        )
        XCTAssertFalse(plan.isVMRoute)
        XCTAssertTrue(plan.fallbackReason?.contains("vsock") ?? false)
    }

    func testBuildConfigFallsBackToNativeWhenContainerToolIsUnavailable() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "VMReadinessMissing")
        let plan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: .sharedVM,
            vmReadiness: nil
        )
        XCTAssertFalse(plan.isVMRoute)
        XCTAssertTrue(plan.fallbackReason?.contains("readiness has not been evaluated") ?? false)
    }

    // MARK: - Migration

    func testLegacyDevcontainerPreferredRawValueDecodesToHost() throws {
        let json = #"{"value":"devcontainer_preferred"}"#
        struct Wrapper: Decodable {
            var value: AgentExecutionEnvironmentPreference
        }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.value, .host)
    }

    func testLegacyNativeMacOSRawValueDecodesToHost() throws {
        let json = #"{"value":"native_macos"}"#
        struct Wrapper: Decodable {
            var value: AgentExecutionEnvironmentPreference
        }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.value, .host)
    }

    func testSharedVMRawValueRoundTrips() throws {
        let encoded = try JSONEncoder().encode(AgentExecutionEnvironmentPreference.sharedVM)
        let string = String(decoding: encoded, as: UTF8.self)
        XCTAssertEqual(string, "\"shared_vm\"")
        let decoded = try JSONDecoder().decode(AgentExecutionEnvironmentPreference.self, from: encoded)
        XCTAssertEqual(decoded, .sharedVM)
    }

    // MARK: - Snapshot

    func testExecutionEnvironmentSnapshotForImageRouteIsCodableBoundedAndSanitized() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "SnapshotRoundtrip")
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree"
        )
        let plan = AgentExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let snapshot = SessionExecutionEnvironmentSnapshot(phase: "Develop", attempt: 1, launchPlan: plan)
        XCTAssertEqual(snapshot.effectiveRouteIdentifier, "shared-vm")
        XCTAssertEqual(snapshot.provisioningAvailabilityIdentifier, "available")
        XCTAssertEqual(snapshot.provisioningStatusIdentifier, "ready")
        XCTAssertEqual(snapshot.provisioningActionIdentifier, SessionExecutionEnvironmentSnapshot.vmBuildActionIdentifier)

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionExecutionEnvironmentSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, snapshot)
    }

    func testExecutionEnvironmentSnapshotSummariesCoverNativeBuildComposeAndFeatureRoutesWithoutLeaks() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "SnapshotSummaries")
        let scenarios: [(SharedCompassVMReadiness?, expectedClassification: String)] = [
            (nil, "not-inspected"),
            (.notProvisioned, "not-provisioned"),
            (.installing(fractionCompleted: 0.5), "installing"),
            (.guestPrepping, "guest-prepping"),
            (.unavailable(reason: "Intel"), "unavailable")
        ]
        for (readiness, expectedClassification) in scenarios {
            let plan = AgentExecutionLaunchPlan.plan(
                repoURL: repoURL,
                preference: .sharedVM,
                vmReadiness: readiness
            )
            let snapshot = SessionExecutionEnvironmentSnapshot(phase: "Plan", launchPlan: plan)
            XCTAssertEqual(snapshot.effectiveRouteIdentifier, "native-macos")
            XCTAssertEqual(snapshot.supportClassificationIdentifier, expectedClassification)
            XCTAssertFalse(snapshot.routeSummary.contains(repoURL.path))
        }
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
