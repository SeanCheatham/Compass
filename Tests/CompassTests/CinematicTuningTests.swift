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

    func testCommitConstellationShotFramesConstellationBounds() throws {
        let shot = CinematicCameraShot.commitConstellation
        let plan = CinematicCommitConstellationPlan(
            sessions: [
                makeTuningSession(
                    commits: (1...CinematicCommitConstellationPlan.maxCommitCount).map {
                        makeTuningCommit(subject: "Constellation commit \($0)")
                    }
                )
            ]
        )
        let focusPlan = plan.focusPlan
        let maxFocusAngle = try XCTUnwrap(
            plan.nodes.map { angle(from: shot.position, toward: focusPlan.lookTarget, to: $0.position) }.max()
        )

        XCTAssertEqual(focusPlan.shot, shot)
        XCTAssertEqual(focusPlan.lookTarget, plan.nodes[0].position)
        XCTAssertGreaterThan(shot.position.z, CinematicCommitConstellationPlan.positionZRange.upperBound)
        XCTAssertInRange(shot.position.y, 1.75...CinematicCameraShot.overhead.position.y)
        XCTAssertInRange(shot.fieldOfView, CinematicTuning.cameraFieldOfViewRange)
        XCTAssertLessThanOrEqual(maxFocusAngle, radians(shot.fieldOfView))
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

    func testComfortModesDampCameraMotionAndTransitionUrgency() {
        let standard = cinematicSettings(style: .dramatic, comfortMode: .standard, intensity: 1)
        let reduced = cinematicSettings(style: .dramatic, comfortMode: .reducedMotion, intensity: 1)
        let quiet = cinematicSettings(style: .dramatic, comfortMode: .quiet, intensity: 1)

        XCTAssertEqual(
            standard,
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )
        XCTAssertLessThan(CinematicTuning.cameraOrbitScale(settings: reduced), CinematicTuning.cameraOrbitScale(settings: standard))
        XCTAssertLessThan(CinematicTuning.cameraOrbitScale(settings: quiet), CinematicTuning.cameraOrbitScale(settings: reduced))
        XCTAssertLessThan(CinematicTuning.cameraDriftScale(settings: reduced), CinematicTuning.cameraDriftScale(settings: standard))
        XCTAssertLessThan(CinematicTuning.cameraDriftScale(settings: quiet), CinematicTuning.cameraDriftScale(settings: reduced))
        XCTAssertLessThan(CinematicTuning.cameraShakeScale(settings: reduced), CinematicTuning.cameraShakeScale(settings: standard))
        XCTAssertLessThan(CinematicTuning.cameraShakeScale(settings: quiet), CinematicTuning.cameraShakeScale(settings: reduced))
        XCTAssertLessThan(
            CinematicTuning.cameraFollowResponsiveness(settings: quiet),
            CinematicTuning.cameraFollowResponsiveness(settings: standard)
        )

        for shot in CinematicCameraShot.allCases {
            XCTAssertGreaterThan(
                CinematicTuning.cameraTransitionDuration(for: shot, settings: reduced),
                CinematicTuning.cameraTransitionDuration(for: shot, settings: standard),
                shot.identifier
            )
            XCTAssertGreaterThan(
                CinematicTuning.cameraTransitionDuration(for: shot, settings: quiet),
                CinematicTuning.cameraTransitionDuration(for: shot, settings: reduced),
                shot.identifier
            )
            XCTAssertEqual(
                CinematicTuning.cameraFieldOfView(for: shot, settings: quiet),
                CinematicTuning.cameraFieldOfView(for: shot, settings: standard),
                accuracy: 0.0001,
                shot.identifier
            )
            XCTAssertEqual(
                CinematicTuning.cameraPosition(for: shot, settings: quiet),
                CinematicTuning.cameraPosition(for: shot, settings: standard),
                shot.identifier
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

    func testComfortModesReduceAmbientPressureAndActivityLightBoost() {
        let heavy = cinematicActivityProfiles().last!.profile
        let standard = cinematicSettings(style: .dramatic, comfortMode: .standard, intensity: 1)
        let reduced = cinematicSettings(style: .dramatic, comfortMode: .reducedMotion, intensity: 1)
        let quiet = cinematicSettings(style: .dramatic, comfortMode: .quiet, intensity: 1)

        XCTAssertGreaterThan(
            CinematicTuning.ambientSpawnCadence(activityProfile: heavy, settings: reduced),
            CinematicTuning.ambientSpawnCadence(activityProfile: heavy, settings: standard)
        )
        XCTAssertGreaterThan(
            CinematicTuning.ambientSpawnCadence(activityProfile: heavy, settings: quiet),
            CinematicTuning.ambientSpawnCadence(activityProfile: heavy, settings: reduced)
        )
        XCTAssertLessThan(
            CinematicTuning.ambientEnemyLimit(activityProfile: heavy, settings: reduced),
            CinematicTuning.ambientEnemyLimit(activityProfile: heavy, settings: standard)
        )
        XCTAssertLessThan(
            CinematicTuning.ambientEnemyLimit(activityProfile: heavy, settings: quiet),
            CinematicTuning.ambientEnemyLimit(activityProfile: heavy, settings: reduced)
        )
        XCTAssertLessThan(
            CinematicTuning.activityPressureScale(settings: reduced),
            CinematicTuning.activityPressureScale(settings: standard)
        )
        XCTAssertLessThan(
            CinematicTuning.activityPressureScale(settings: quiet),
            CinematicTuning.activityPressureScale(settings: reduced)
        )
        XCTAssertLessThan(
            CinematicTuning.activityLightBoost(activityProfile: heavy, settings: reduced),
            CinematicTuning.activityLightBoost(activityProfile: heavy, settings: standard)
        )
        XCTAssertLessThan(
            CinematicTuning.activityLightBoost(activityProfile: heavy, settings: quiet),
            CinematicTuning.activityLightBoost(activityProfile: heavy, settings: reduced)
        )

        XCTAssertInRange(CinematicTuning.ambientSpawnCadence(activityProfile: heavy, settings: quiet), CinematicTuning.ambientSpawnCadenceRange)
        XCTAssertInRange(CinematicTuning.ambientEnemyLimit(activityProfile: heavy, settings: quiet), CinematicTuning.ambientEnemyLimitRange)
        XCTAssertInRange(CinematicTuning.activityLightBoost(activityProfile: heavy, settings: quiet), CinematicTuning.activityLightBoostRange)
    }
}

private let cinematicIntensitySamples = [
    0,
    CinematicInfluenceSettings.defaultIntensity,
    1
]

private func cinematicSettings(
    style: CinematicInfluenceSettings.CameraStyle,
    comfortMode: CinematicInfluenceSettings.ComfortMode = .standard,
    intensity: Double
) -> CinematicInfluenceSettings {
    CinematicInfluenceSettings(cameraStyle: style, comfortMode: comfortMode, intensity: intensity)
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

private func makeTuningSession(commits: [SessionCommit]) -> SessionRecord {
    SessionRecord(
        session: 1,
        startedAt: 100,
        endedAt: 200,
        plan: nil,
        verify: nil,
        beforeSha: nil,
        afterSha: nil,
        commits: commits,
        status: .succeeded,
        notes: [],
        verifyOutput: nil,
        feedback: nil
    )
}

private func makeTuningCommit(subject: String) -> SessionCommit {
    let checksum = subject.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 1_000_000 }
    let short = String(("0000000" + String(checksum)).suffix(7))
    return SessionCommit(
        sha: "feedbeef\(short)",
        short: short,
        subject: subject
    )
}

private func angle(
    from origin: SIMD3<Float>,
    toward target: SIMD3<Float>,
    to point: SIMD3<Float>
) -> Float {
    let targetDirection = normalized(target - origin)
    let pointDirection = normalized(point - origin)
    let dotProduct = targetDirection.x * pointDirection.x
        + targetDirection.y * pointDirection.y
        + targetDirection.z * pointDirection.z
    return acos(min(max(dotProduct, -1), 1))
}

private func normalized(_ value: SIMD3<Float>) -> SIMD3<Float> {
    let length = sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    guard length > 0.0001 else { return .zero }
    return value / length
}

private func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
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
