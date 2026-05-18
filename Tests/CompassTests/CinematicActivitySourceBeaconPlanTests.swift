import Foundation
@testable import Compass
import XCTest

final class CinematicActivitySourceBeaconPlanTests: XCTestCase {
    func testRepoLocalAvailableBaselineIsHidden() {
        let snapshot = makeActivitySourceSnapshot(
            activeStorage: .repoLocal,
            sourceAvailability: .available,
            repoLocalSessionsState: .activeSource
        )

        let plan = CinematicActivitySourceBeaconPlan(snapshot: snapshot)

        XCTAssertFalse(plan.isVisible)
        XCTAssertNil(plan.descriptor)
        XCTAssertEqual(plan.visibilityIdentifier, "hidden")
        XCTAssertEqual(plan.suppressionReason, "status-hidden")
        XCTAssertEqual(plan.kindIdentifier, "hidden")
        XCTAssertEqual(plan.activeStorageIdentifier, "repo_local")
        XCTAssertEqual(plan.availabilityIdentifier, "available")
        XCTAssertEqual(plan.severityIdentifier, "healthy")
        XCTAssertEqual(plan.tintIdentifier, "green")
        assertBounded(plan)
    }

    func testApplicationSupportAvailableCreatesCompactDescriptor() throws {
        let snapshot = makeActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            sourceAvailability: .available,
            repoLocalSessionsState: .ignoredCompatible
        )

        let plan = CinematicActivitySourceBeaconPlan(snapshot: snapshot)
        let descriptor = try XCTUnwrap(plan.descriptor)

        XCTAssertTrue(plan.isVisible)
        XCTAssertFalse(plan.isCritical)
        XCTAssertTrue(plan.isQuietModeSuppressible)
        XCTAssertEqual(plan.visibilityIdentifier, "visible")
        XCTAssertEqual(descriptor.kindIdentifier, "application-support-active")
        XCTAssertEqual(descriptor.lightFamily, .scan)
        XCTAssertEqual(descriptor.arenaEffect, .seal)
        XCTAssertEqual(descriptor.cameraShot, .castPrep)
        XCTAssertTrue(descriptor.label.contains("Support"))
        XCTAssertTrue(descriptor.detail.contains("Application Support"))
        XCTAssertTrue(descriptor.copyText.contains("policy-source application-support-active"))
        XCTAssertTrue(descriptor.rootEntityName.hasPrefix("activity-source-beacon."))
        XCTAssertNotEqual(descriptor.ringEntityName, descriptor.coreEntityName)
        assertBounded(plan)
    }

    func testQuietModeSuppressesNonCriticalSupportBeaconButKeepsWarningsVisible() throws {
        let quietSettings = CinematicInfluenceSettings(
            cameraStyle: .follow,
            comfortMode: .quiet,
            intensity: 0.4
        )
        let supportAvailable = makeActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            sourceAvailability: .available,
            repoLocalSessionsState: .ignoredCompatible
        )
        let missingRecord = makeActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            sourceAvailability: .sessionsRecordMissing,
            repoLocalSessionsState: .ignoredMissing
        )

        let quietSupport = CinematicActivitySourceBeaconPlan(
            snapshot: supportAvailable,
            influenceSettings: quietSettings
        )
        let quietWarning = CinematicActivitySourceBeaconPlan(
            snapshot: missingRecord,
            influenceSettings: quietSettings
        )
        let warningDescriptor = try XCTUnwrap(quietWarning.descriptor)

        XCTAssertFalse(quietSupport.isVisible)
        XCTAssertEqual(quietSupport.visibilityIdentifier, "suppressed-quiet-noncritical")
        XCTAssertEqual(quietSupport.suppressionReason, "quiet-noncritical")
        XCTAssertTrue(quietWarning.isVisible)
        XCTAssertTrue(quietWarning.isCritical)
        XCTAssertEqual(quietWarning.visibilityIdentifier, "visible-warning")
        XCTAssertEqual(warningDescriptor.lightFamily, .pressure)
        XCTAssertEqual(warningDescriptor.arenaEffect, .activityPulse)
        XCTAssertEqual(warningDescriptor.tintIdentifier, "orange")
        assertBounded(quietSupport)
        assertBounded(quietWarning)
    }

    func testUnreadableAndOversizedSourcesUseFailureTreatment() throws {
        for availability in [
            RepositoryActivitySourceSnapshot.SourceAvailability.sessionsRecordUnreadable,
            .sessionsRecordOversized
        ] {
            let plan = CinematicActivitySourceBeaconPlan(
                snapshot: makeActivitySourceSnapshot(
                    activeStorage: .applicationSupport,
                    sourceAvailability: availability,
                    repoLocalSessionsState: .ignoredMissing
                )
            )
            let descriptor = try XCTUnwrap(plan.descriptor)

            XCTAssertTrue(plan.isVisible, availability.rawValue)
            XCTAssertTrue(plan.isCritical, availability.rawValue)
            XCTAssertEqual(plan.severityIdentifier, "failure", availability.rawValue)
            XCTAssertEqual(descriptor.lightFamily, .failure, availability.rawValue)
            XCTAssertEqual(descriptor.arenaEffect, .charge, availability.rawValue)
            XCTAssertEqual(descriptor.tintIdentifier, "red", availability.rawValue)
            XCTAssertEqual(descriptor.cameraShot, .wide, availability.rawValue)
            assertBounded(plan)
        }
    }

    func testIdlePlannerUsesBeaconAsIdleOnlyCandidate() throws {
        let beacon = CinematicActivitySourceBeaconPlan(
            snapshot: makeActivitySourceSnapshot(
                activeStorage: .applicationSupport,
                sourceAvailability: .available,
                repoLocalSessionsState: .ignoredMissing
            )
        )

        let idle = CinematicIdleStoryCyclePlanner.plan(
            session: .init(),
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: .init(),
            activitySourceBeaconPlan: beacon,
            commitConstellationPlan: .empty,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: .empty(reason: "source-beacon-only"),
            runRecapSceneFocusPlan: .none,
            runRecapEndCardPlan: .none
        )
        let liveFollow = CinematicIdleStoryCyclePlanner.plan(
            session: .init(),
            isLiveFollowActive: true,
            hasExplicitUserFocus: false,
            influenceSettings: .init(),
            activitySourceBeaconPlan: beacon,
            commitConstellationPlan: .empty,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: .empty(reason: "source-beacon-only"),
            runRecapSceneFocusPlan: .none,
            runRecapEndCardPlan: .none
        )
        let userFocus = CinematicIdleStoryCyclePlanner.plan(
            session: .init(),
            isLiveFollowActive: false,
            hasExplicitUserFocus: true,
            influenceSettings: .init(),
            activitySourceBeaconPlan: beacon,
            commitConstellationPlan: .empty,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: .empty(reason: "source-beacon-only"),
            runRecapSceneFocusPlan: .none,
            runRecapEndCardPlan: .none
        )
        let descriptor = try XCTUnwrap(idle.descriptor)

        XCTAssertEqual(descriptor.phase, .activitySourceBeacon)
        XCTAssertEqual(descriptor.activitySourceBeaconDescriptor?.identifier, beacon.descriptor?.identifier)
        XCTAssertEqual(descriptor.targetKindIdentifier, "activity-source-beacon-application-support-active-available")
        XCTAssertEqual(descriptor.lightFamily, .scan)
        XCTAssertEqual(descriptor.arenaEffect, .seal)
        XCTAssertFalse(liveFollow.isActive)
        XCTAssertEqual(liveFollow.suppressionReason, "live-follow")
        XCTAssertFalse(userFocus.isActive)
        XCTAssertEqual(userFocus.suppressionReason, "user-focus")
    }

    func testIdentifiersAndCopyAreBoundedForLongPaths() throws {
        let longComponent = String(repeating: "BeaconStoragePath", count: 24)
        let repoURL = URL(fileURLWithPath: "/tmp/\(longComponent)", isDirectory: true)
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: longComponent, directoryHint: .isDirectory)
        let snapshot = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .sessionsRecordUnreadable,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredUnreadable
        )

        let plan = CinematicActivitySourceBeaconPlan(snapshot: snapshot)
        let descriptor = try XCTUnwrap(plan.descriptor)

        XCTAssertTrue(plan.identifier.contains("activity-source-beacon"))
        XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicActivitySourceBeaconPlan.descriptorIdentifierLimit)
        XCTAssertLessThanOrEqual(descriptor.copyText.count, CinematicActivitySourceBeaconPlan.copyTextLimit)
        assertBounded(plan)
    }

    private func assertBounded(
        _ plan: CinematicActivitySourceBeaconPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(plan.identifier.count, CinematicActivitySourceBeaconPlan.identifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(plan.cueIdentifier.count, CinematicActivitySourceCuePlan.identifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(plan.sourceIdentifier.count, CinematicActivitySourceCuePlan.sourceIdentifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(plan.statusIdentifier.count, CinematicActivitySourceCuePlan.identifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(plan.tintIdentifier.count, CinematicActivitySourceBeaconPlan.tintIdentifierLimit, file: file, line: line)
        guard let descriptor = plan.descriptor else { return }
        XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicActivitySourceBeaconPlan.descriptorIdentifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.routeIdentifier.count, CinematicActivitySourceBeaconPlan.routeIdentifierLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.entityNamePrefix.count, CinematicActivitySourceBeaconPlan.entityNameLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.rootEntityName.count, CinematicActivitySourceBeaconPlan.entityNameLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.ringEntityName.count, CinematicActivitySourceBeaconPlan.entityNameLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.coreEntityName.count, CinematicActivitySourceBeaconPlan.entityNameLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.labelEntityName.count, CinematicActivitySourceBeaconPlan.entityNameLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.detailEntityName.count, CinematicActivitySourceBeaconPlan.entityNameLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.label.count, CinematicActivitySourceBeaconPlan.labelLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.detail.count, CinematicActivitySourceBeaconPlan.detailLimit, file: file, line: line)
        XCTAssertLessThanOrEqual(descriptor.copyText.count, CinematicActivitySourceBeaconPlan.copyTextLimit, file: file, line: line)
    }

    private func makeActivitySourceSnapshot(
        activeStorage: KnownProjectActiveStorage,
        sourceAvailability: RepositoryActivitySourceSnapshot.SourceAvailability,
        repoLocalSessionsState: RepositoryActivitySourceSnapshot.RepoLocalSessionsState
    ) -> RepositoryActivitySourceSnapshot {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassCinematicActivitySourceBeacon", isDirectory: true)
        let repoLocalRoot = repoURL.appending(path: ".compass", directoryHint: .isDirectory)
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        let activeRoot = activeStorage == .repoLocal ? repoLocalRoot : supportRoot

        return RepositoryActivitySourceSnapshot(
            activeStorage: activeStorage,
            storageRootURL: activeRoot,
            sessionsRecordURL: activeRoot.appending(path: "sessions.json"),
            sourceAvailability: sourceAvailability,
            repoLocalSessionsRecordURL: repoLocalRoot.appending(path: "sessions.json"),
            repoLocalSessionsState: repoLocalSessionsState
        )
    }
}
