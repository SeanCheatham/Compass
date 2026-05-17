import Foundation
@testable import Compass
import XCTest

final class CinematicTuningCameraTests: XCTestCase {
    func testCameraFieldOfViewIsDistinctMonotonicAndClamped() {
        for shot in CinematicCameraShot.allCases {
            for intensity in cinematicIntensitySamples {
                let steady = fieldOfView(shot: shot, style: .steady, intensity: intensity)
                let follow = fieldOfView(shot: shot, style: .follow, intensity: intensity)
                let dramatic = fieldOfView(shot: shot, style: .dramatic, intensity: intensity)

                XCTAssertInRange(steady, CinematicTuning.cameraFieldOfViewRange)
                XCTAssertInRange(follow, CinematicTuning.cameraFieldOfViewRange)
                XCTAssertInRange(dramatic, CinematicTuning.cameraFieldOfViewRange)
                XCTAssertLessThan(steady, follow)
                XCTAssertLessThan(follow, dramatic)
            }

            for style in CinematicInfluenceSettings.CameraStyle.allCases {
                let low = fieldOfView(shot: shot, style: style, intensity: 0)
                let defaultValue = fieldOfView(shot: shot, style: style, intensity: CinematicInfluenceSettings.defaultIntensity)
                let high = fieldOfView(shot: shot, style: style, intensity: 1)

                XCTAssertLessThan(low, defaultValue)
                XCTAssertLessThan(defaultValue, high)
            }
        }
    }

    func testCameraPositionsStayFiniteAndDramaticPushesCloser() {
        for shot in CinematicCameraShot.allCases {
            for intensity in cinematicIntensitySamples {
                let steady = cameraPosition(shot: shot, style: .steady, intensity: intensity)
                let follow = cameraPosition(shot: shot, style: .follow, intensity: intensity)
                let dramatic = cameraPosition(shot: shot, style: .dramatic, intensity: intensity)

                XCTAssertFinite(steady)
                XCTAssertFinite(follow)
                XCTAssertFinite(dramatic)
                XCTAssertGreaterThanOrEqual(steady.y, 1.75)
                XCTAssertGreaterThanOrEqual(follow.y, 1.75)
                XCTAssertGreaterThanOrEqual(dramatic.y, 1.75)
                XCTAssertLessThan(dramatic.z, follow.z)
            }
        }
    }

    func testCameraMotionScalesAndDurationsAreOrderedAndClamped() {
        for intensity in cinematicIntensitySamples {
            let steady = cinematicSettings(style: .steady, intensity: intensity)
            let follow = cinematicSettings(style: .follow, intensity: intensity)
            let dramatic = cinematicSettings(style: .dramatic, intensity: intensity)

            XCTAssertLessThan(
                CinematicTuning.cameraFollowResponsiveness(settings: steady),
                CinematicTuning.cameraFollowResponsiveness(settings: follow)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraFollowResponsiveness(settings: follow),
                CinematicTuning.cameraFollowResponsiveness(settings: dramatic)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraDriftScale(settings: steady),
                CinematicTuning.cameraDriftScale(settings: follow)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraDriftScale(settings: follow),
                CinematicTuning.cameraDriftScale(settings: dramatic)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraShakeScale(settings: steady),
                CinematicTuning.cameraShakeScale(settings: follow)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraShakeScale(settings: follow),
                CinematicTuning.cameraShakeScale(settings: dramatic)
            )
            XCTAssertInRange(CinematicTuning.cameraShakeScale(settings: steady), CinematicTuning.cameraShakeScaleRange)
            XCTAssertInRange(CinematicTuning.cameraShakeScale(settings: follow), CinematicTuning.cameraShakeScaleRange)
            XCTAssertInRange(CinematicTuning.cameraShakeScale(settings: dramatic), CinematicTuning.cameraShakeScaleRange)

            for shot in CinematicCameraShot.allCases {
                let steadyDuration = CinematicTuning.cameraTransitionDuration(for: shot, settings: steady)
                let followDuration = CinematicTuning.cameraTransitionDuration(for: shot, settings: follow)
                let dramaticDuration = CinematicTuning.cameraTransitionDuration(for: shot, settings: dramatic)

                XCTAssertLessThan(dramaticDuration, followDuration)
                XCTAssertLessThan(followDuration, steadyDuration)
            }
        }

        for style in CinematicInfluenceSettings.CameraStyle.allCases {
            let low = cinematicSettings(style: style, intensity: 0)
            let defaultValue = cinematicSettings(style: style, intensity: CinematicInfluenceSettings.defaultIntensity)
            let high = cinematicSettings(style: style, intensity: 1)

            XCTAssertLessThan(
                CinematicTuning.cameraFollowResponsiveness(settings: low),
                CinematicTuning.cameraFollowResponsiveness(settings: defaultValue)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraFollowResponsiveness(settings: defaultValue),
                CinematicTuning.cameraFollowResponsiveness(settings: high)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraDriftScale(settings: low),
                CinematicTuning.cameraDriftScale(settings: defaultValue)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraDriftScale(settings: defaultValue),
                CinematicTuning.cameraDriftScale(settings: high)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraShakeScale(settings: low),
                CinematicTuning.cameraShakeScale(settings: defaultValue)
            )
            XCTAssertLessThan(
                CinematicTuning.cameraShakeScale(settings: defaultValue),
                CinematicTuning.cameraShakeScale(settings: high)
            )
        }
    }
}

final class CinematicTuningActivityTests: XCTestCase {
    func testActivityTuningIsDistinctMonotonicAndClamped() {
        let profiles = cinematicActivityProfiles()

        for style in CinematicInfluenceSettings.CameraStyle.allCases {
            for intensity in cinematicIntensitySamples {
                let settings = cinematicSettings(style: style, intensity: intensity)
                let cadences = profiles.map {
                    CinematicTuning.ambientSpawnCadence(activityProfile: $0.profile, settings: settings)
                }
                let enemyLimits = profiles.map {
                    CinematicTuning.ambientEnemyLimit(activityProfile: $0.profile, settings: settings)
                }
                let lightBoosts = profiles.map {
                    CinematicTuning.activityLightBoost(activityProfile: $0.profile, settings: settings)
                }

                cadences.forEach { XCTAssertInRange($0, CinematicTuning.ambientSpawnCadenceRange) }
                enemyLimits.forEach { XCTAssertInRange($0, CinematicTuning.ambientEnemyLimitRange) }
                lightBoosts.forEach { XCTAssertInRange($0, CinematicTuning.activityLightBoostRange) }

                XCTAssertGreaterThan(cadences[0], cadences[1])
                XCTAssertGreaterThan(cadences[1], cadences[2])
                XCTAssertGreaterThan(cadences[2], cadences[3])

                XCTAssertLessThan(enemyLimits[0], enemyLimits[1])
                XCTAssertLessThan(enemyLimits[1], enemyLimits[2])
                XCTAssertLessThan(enemyLimits[2], enemyLimits[3])

                XCTAssertLessThan(lightBoosts[0], lightBoosts[1])
                XCTAssertLessThan(lightBoosts[1], lightBoosts[2])
                XCTAssertLessThan(lightBoosts[2], lightBoosts[3])
            }
        }
    }

    func testIntensityChangesActivityPressureMonotonically() {
        for style in CinematicInfluenceSettings.CameraStyle.allCases {
            for entry in cinematicActivityProfiles() {
                let low = cinematicSettings(style: style, intensity: 0)
                let defaultValue = cinematicSettings(style: style, intensity: CinematicInfluenceSettings.defaultIntensity)
                let high = cinematicSettings(style: style, intensity: 1)

                XCTAssertGreaterThan(
                    CinematicTuning.ambientSpawnCadence(activityProfile: entry.profile, settings: low),
                    CinematicTuning.ambientSpawnCadence(activityProfile: entry.profile, settings: defaultValue),
                    entry.name
                )
                XCTAssertGreaterThan(
                    CinematicTuning.ambientSpawnCadence(activityProfile: entry.profile, settings: defaultValue),
                    CinematicTuning.ambientSpawnCadence(activityProfile: entry.profile, settings: high),
                    entry.name
                )
                XCTAssertLessThan(
                    CinematicTuning.ambientEnemyLimit(activityProfile: entry.profile, settings: low),
                    CinematicTuning.ambientEnemyLimit(activityProfile: entry.profile, settings: defaultValue),
                    entry.name
                )
                XCTAssertLessThan(
                    CinematicTuning.ambientEnemyLimit(activityProfile: entry.profile, settings: defaultValue),
                    CinematicTuning.ambientEnemyLimit(activityProfile: entry.profile, settings: high),
                    entry.name
                )

                if entry.profile.pressureScore > 0 {
                    XCTAssertLessThan(
                        CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: low),
                        CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: defaultValue),
                        entry.name
                    )
                    XCTAssertLessThan(
                        CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: defaultValue),
                        CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: high),
                        entry.name
                    )
                } else {
                    XCTAssertEqual(CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: low), 0)
                    XCTAssertEqual(CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: defaultValue), 0)
                    XCTAssertEqual(CinematicTuning.activityLightBoost(activityProfile: entry.profile, settings: high), 0)
                }
            }
        }
    }

    func testHardClampBoundariesAreEnforced() {
        let dramaticHigh = cinematicSettings(style: .dramatic, intensity: 1)
        let heavy = cinematicActivityProfiles().last!.profile

        XCTAssertEqual(
            CinematicTuning.cameraFieldOfView(for: .victory, settings: dramaticHigh),
            CinematicTuning.cameraFieldOfViewRange.upperBound,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CinematicTuning.ambientSpawnCadence(activityProfile: heavy, settings: dramaticHigh),
            CinematicTuning.ambientSpawnCadenceRange.lowerBound,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CinematicTuning.ambientEnemyLimit(activityProfile: heavy, settings: dramaticHigh),
            CinematicTuning.ambientEnemyLimitRange.upperBound
        )
        XCTAssertEqual(
            CinematicTuning.cameraShakeScale(settings: dramaticHigh),
            CinematicTuning.cameraShakeScaleRange.upperBound,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CinematicTuning.activityLightBoost(activityProfile: heavy, settings: dramaticHigh),
            CinematicTuning.activityLightBoostRange.upperBound,
            accuracy: 0.0001
        )
    }
}

private let cinematicIntensitySamples = [
    0,
    CinematicInfluenceSettings.defaultIntensity,
    1
]

private func cinematicSettings(
    style: CinematicInfluenceSettings.CameraStyle,
    intensity: Double
) -> CinematicInfluenceSettings {
    CinematicInfluenceSettings(cameraStyle: style, intensity: intensity)
}

private func fieldOfView(
    shot: CinematicCameraShot,
    style: CinematicInfluenceSettings.CameraStyle,
    intensity: Double
) -> Float {
    CinematicTuning.cameraFieldOfView(
        for: shot,
        settings: cinematicSettings(style: style, intensity: intensity)
    )
}

private func cameraPosition(
    shot: CinematicCameraShot,
    style: CinematicInfluenceSettings.CameraStyle,
    intensity: Double
) -> SIMD3<Float> {
    CinematicTuning.cameraPosition(
        for: shot,
        settings: cinematicSettings(style: style, intensity: intensity)
    )
}

private func cinematicActivityProfiles() -> [(name: String, profile: RepositoryActivityProfile)] {
    [
        ("clean", makeCinematicActivityProfile(worktreeChanges: RepositoryWorktreeChangeCounts())),
        ("light", makeCinematicActivityProfile(worktreeChanges: worktreeChanges(added: 2))),
        ("moderate", makeCinematicActivityProfile(worktreeChanges: worktreeChanges(modified: 8))),
        (
            "heavy",
            makeCinematicActivityProfile(
                worktreeChanges: worktreeChanges(modified: 16)
            )
        )
    ]
}

private func makeCinematicActivityProfile(
    worktreeChanges: RepositoryWorktreeChangeCounts,
    recentFailedCount: Int = 0,
    failureStreak: Int = 0
) -> RepositoryActivityProfile {
    RepositoryActivityProfile(
        isAvailable: true,
        worktreeChanges: worktreeChanges,
        recentSessionCount: recentFailedCount,
        recentSucceededCount: 0,
        recentFailedCount: recentFailedCount,
        recentCommitCount: 0,
        lastTerminalStatus: failureStreak > 0 ? .failed : nil,
        lastSuccessfulSession: nil,
        lastFailedSession: failureStreak > 0 ? 1 : nil,
        successStreak: 0,
        failureStreak: failureStreak,
        recoveredFromFailure: false
    )
}

private func worktreeChanges(
    added: Int = 0,
    modified: Int = 0,
    deleted: Int = 0,
    renamed: Int = 0,
    untracked: Int = 0,
    conflicted: Int = 0,
    other: Int = 0
) -> RepositoryWorktreeChangeCounts {
    var changes = RepositoryWorktreeChangeCounts()
    changes.added = added
    changes.modified = modified
    changes.deleted = deleted
    changes.renamed = renamed
    changes.untracked = untracked
    changes.conflicted = conflicted
    changes.other = other
    return changes
}

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}

private func XCTAssertFinite(
    _ value: SIMD3<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value.x.isFinite, file: file, line: line)
    XCTAssertTrue(value.y.isFinite, file: file, line: line)
    XCTAssertTrue(value.z.isFinite, file: file, line: line)
}
