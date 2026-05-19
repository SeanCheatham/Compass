import Foundation
@testable import Compass
import XCTest

@MainActor
final class CinematicSceneLifecycleTests: XCTestCase {
    func testMainWorkspaceDoesNotMountHiddenOffscreenCinematicScene() throws {
        let source = try sourceFile(named: "ContentView.swift")

        XCTAssertFalse(source.contains("hasOpenedCinematic"))
        XCTAssertFalse(source.contains(".frame(width: 1, height: 1)"))
        XCTAssertFalse(source.contains(".opacity(0.01)"))
        XCTAssertFalse(source.contains("accessibilityHidden(true)"))
        XCTAssertFalse(source.contains("selectedTab != .cinematic"))
    }

    func testMountedLifecycleSnapshotReportsActiveCoordinatorState() {
        let cache = CinematicSceneCache(releaseDelay: 600)
        let projectID = UUID()
        let coordinator = cache.coordinator(for: projectID)
        coordinator.primeLifecycleForTesting(
            elapsedTime: 12,
            phase: .developing,
            isThinking: true
        )

        let snapshot = cache.lifecycleSnapshot(for: projectID)

        XCTAssertEqual(snapshot?.retainCount, 1)
        XCTAssertFalse(snapshot?.hasScheduledExpiry == true)
        XCTAssertFalse(snapshot?.coordinator.isOffscreen == true)
        XCTAssertTrue(snapshot?.coordinator.isInstalled == true)
        XCTAssertTrue(snapshot?.coordinator.hasDisplayTimer == true)
        XCTAssertTrue(snapshot?.coordinator.hasThinkingTimer == true)
        XCTAssertTrue(snapshot?.coordinator.hasDefenseTimer == true)
        XCTAssertEqual(snapshot?.coordinator.elapsedTime, 12)
        XCTAssertEqual(snapshot?.coordinator.phaseIdentifier, LoopPhase.developing.rawValue)

        cache.release(projectID)
        cache.expireReleasedCoordinator(for: projectID)
    }

    func testZeroRetainReleaseSuspendsTimersImmediately() {
        let cache = CinematicSceneCache(releaseDelay: 600)
        let projectID = UUID()
        let coordinator = cache.coordinator(for: projectID)
        coordinator.primeLifecycleForTesting(
            elapsedTime: 24,
            phase: .developing,
            isThinking: true
        )

        cache.release(projectID)

        let snapshot = cache.lifecycleSnapshot(for: projectID)
        XCTAssertEqual(snapshot?.retainCount, 0)
        XCTAssertTrue(snapshot?.hasScheduledExpiry == true)
        XCTAssertTrue(snapshot?.coordinator.isOffscreen == true)
        XCTAssertFalse(snapshot?.coordinator.hasDisplayTimer == true)
        XCTAssertFalse(snapshot?.coordinator.hasThinkingTimer == true)
        XCTAssertFalse(snapshot?.coordinator.hasDefenseTimer == true)
        XCTAssertEqual(snapshot?.coordinator.elapsedTime, 24)
        XCTAssertEqual(snapshot?.coordinator.phaseIdentifier, LoopPhase.developing.rawValue)

        cache.expireReleasedCoordinator(for: projectID)
    }

    func testReacquireCancelsExpiryAndResumesSameCoordinatorState() {
        let cache = CinematicSceneCache(releaseDelay: 600)
        let projectID = UUID()
        let coordinator = cache.coordinator(for: projectID)
        coordinator.primeLifecycleForTesting(
            elapsedTime: 42,
            phase: .verifying,
            isThinking: true
        )
        let stateBeforeRelease = coordinator.lifecycleSnapshot()

        cache.release(projectID)
        XCTAssertTrue(cache.lifecycleSnapshot(for: projectID)?.hasScheduledExpiry == true)

        let reacquired = cache.coordinator(for: projectID)
        let snapshot = cache.lifecycleSnapshot(for: projectID)

        XCTAssertTrue(reacquired === coordinator)
        XCTAssertEqual(snapshot?.retainCount, 1)
        XCTAssertFalse(snapshot?.hasScheduledExpiry == true)
        XCTAssertFalse(snapshot?.coordinator.isOffscreen == true)
        XCTAssertEqual(snapshot?.coordinator.coordinatorIdentifier, stateBeforeRelease.coordinatorIdentifier)
        XCTAssertEqual(snapshot?.coordinator.elapsedTime, stateBeforeRelease.elapsedTime)
        XCTAssertEqual(snapshot?.coordinator.phaseIdentifier, stateBeforeRelease.phaseIdentifier)
        XCTAssertEqual(
            snapshot?.coordinator.commitConstellationIdentifier,
            stateBeforeRelease.commitConstellationIdentifier
        )
        XCTAssertEqual(
            snapshot?.coordinator.planCompassFocusIdentifier,
            stateBeforeRelease.planCompassFocusIdentifier
        )
        XCTAssertEqual(snapshot?.coordinator.hasDisplayTimer, stateBeforeRelease.hasDisplayTimer)
        XCTAssertEqual(snapshot?.coordinator.hasThinkingTimer, stateBeforeRelease.hasThinkingTimer)
        XCTAssertEqual(snapshot?.coordinator.hasDefenseTimer, stateBeforeRelease.hasDefenseTimer)

        cache.release(projectID)
        cache.expireReleasedCoordinator(for: projectID)
    }

    func testExpiryFullyStopsAndDropsReleasedCoordinator() {
        let cache = CinematicSceneCache(releaseDelay: 600)
        let projectID = UUID()
        let coordinator = cache.coordinator(for: projectID)
        coordinator.primeLifecycleForTesting(
            elapsedTime: 73,
            phase: .succeeded,
            isThinking: true
        )
        let oldIdentifier = coordinator.lifecycleSnapshot().coordinatorIdentifier

        cache.release(projectID)
        cache.expireReleasedCoordinator(for: projectID)

        XCTAssertNil(cache.lifecycleSnapshot(for: projectID))
        let stoppedSnapshot = coordinator.lifecycleSnapshot()
        XCTAssertTrue(stoppedSnapshot.isOffscreen)
        XCTAssertFalse(stoppedSnapshot.hasDisplayTimer)
        XCTAssertFalse(stoppedSnapshot.hasThinkingTimer)
        XCTAssertFalse(stoppedSnapshot.hasDefenseTimer)

        let replacement = cache.coordinator(for: projectID)
        XCTAssertFalse(replacement === coordinator)
        XCTAssertNotEqual(replacement.lifecycleSnapshot().coordinatorIdentifier, oldIdentifier)
        XCTAssertEqual(replacement.lifecycleSnapshot().elapsedTime, 0)

        cache.release(projectID)
        cache.expireReleasedCoordinator(for: projectID)
    }

    func testLifecyclePolicySuspendsOnZeroRetainAndDropsOnlyExpiredZeroRetain() {
        let policy = CinematicSceneCacheLifecyclePolicy(resumeCacheDuration: 12)

        XCTAssertEqual(
            policy.acquirePlan(currentRetainCount: nil),
            .init(retainCount: 1, resumesCoordinator: true)
        )
        XCTAssertEqual(
            policy.releasePlan(currentRetainCount: 2),
            .init(retainCount: 1, suspendsCoordinator: false, expiryDelay: nil)
        )
        XCTAssertEqual(
            policy.releasePlan(currentRetainCount: 1),
            .init(retainCount: 0, suspendsCoordinator: true, expiryDelay: 12)
        )
        XCTAssertFalse(policy.expiryPlan(retainCount: 1).stopsAndDropsCoordinator)
        XCTAssertTrue(policy.expiryPlan(retainCount: 0).stopsAndDropsCoordinator)
    }

    func testCinematicTabPresentationStateIsOwnedByMainWorkspaceAcrossSwitches() throws {
        var state = CinematicTabPresentationState()
        state.overlayMode = .timeline
        state.selectedTimelineBeatID = "beat:session-3"
        state.selectedPlanCompassKind = .longTerm

        let preservedAcrossSwitch = state
        XCTAssertEqual(preservedAcrossSwitch.overlayMode, .timeline)
        XCTAssertEqual(preservedAcrossSwitch.selectedTimelineBeatID, "beat:session-3")
        XCTAssertEqual(preservedAcrossSwitch.selectedPlanCompassKind, .longTerm)

        let contentSource = try sourceFile(named: "ContentView.swift")
        let tabSource = try sourceFile(named: "CinematicTab.swift")
        let modelsSource = try sourceFile(named: "Models.swift")

        XCTAssertTrue(
            contentSource.contains(
                "@State private var cinematicPresentationState = CinematicTabPresentationState()"
            )
        )
        XCTAssertTrue(
            contentSource.contains(
                "CinematicTab(project: project, presentationState: $cinematicPresentationState)"
            )
        )
        XCTAssertTrue(tabSource.contains("@Binding var presentationState: CinematicTabPresentationState"))
        XCTAssertFalse(tabSource.contains("@State private var overlayMode"))
        XCTAssertFalse(tabSource.contains("@State private var selectedTimelineBeatID"))
        XCTAssertFalse(tabSource.contains("@State private var selectedPlanCompassKind"))
        XCTAssertFalse(modelsSource.contains("CinematicTabPresentationState"))
    }

    private func sourceFile(named filename: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Compass/\(filename)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
