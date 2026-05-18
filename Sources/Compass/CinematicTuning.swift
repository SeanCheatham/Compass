import Foundation

enum CinematicCameraShot: CaseIterable, Equatable {
    case home
    case wide
    case castPrep
    case overShoulder
    case impact
    case overhead
    case commitConstellation
    case failure
    case victory

    var identifier: String {
        switch self {
        case .home:
            return "home"
        case .wide:
            return "wide"
        case .castPrep:
            return "cast-prep"
        case .overShoulder:
            return "over-shoulder"
        case .impact:
            return "impact"
        case .overhead:
            return "overhead"
        case .commitConstellation:
            return "commit-constellation"
        case .failure:
            return "failure"
        case .victory:
            return "victory"
        }
    }

    var position: SIMD3<Float> {
        switch self {
        case .home:
            return [0, 4.8, 9.8]
        case .wide:
            return [-5.8, 5.6, 10.5]
        case .castPrep:
            return [-2.15, 2.65, 4.85]
        case .overShoulder:
            return [0.95, 2.45, 4.35]
        case .impact:
            return [2.1, 2.85, 4.75]
        case .overhead:
            return [0, 8.9, 3.6]
        case .commitConstellation:
            return [0.25, 3.45, 1.15]
        case .failure:
            return [0.55, 2.05, 3.55]
        case .victory:
            return [0, 6.1, 12.2]
        }
    }

    var fieldOfView: Float {
        switch self {
        case .castPrep, .overShoulder, .failure:
            return 34
        case .impact:
            return 35
        case .overhead:
            return 48
        case .commitConstellation:
            return 44
        case .victory:
            return 50
        case .home, .wide:
            return 42
        }
    }

    var duration: TimeInterval {
        switch self {
        case .failure:
            return 0.22
        case .impact, .castPrep, .overShoulder:
            return 0.48
        case .victory:
            return 1.2
        case .commitConstellation:
            return 0.72
        case .home, .wide, .overhead:
            return 0.82
        }
    }
}

enum CinematicTuning {
    static let cameraFieldOfViewRange: ClosedRange<Float> = 30...56
    static let cameraFollowFieldOfViewRange: ClosedRange<Float> = 34...48
    static let ambientSpawnCadenceRange: ClosedRange<TimeInterval> = 0.85...7.5
    static let ambientEnemyLimitRange: ClosedRange<Int> = 3...14
    static let cameraShakeScaleRange: ClosedRange<Float> = 0.12...1.85
    static let activityLightBoostRange: ClosedRange<Float> = 0...560

    static func cameraPosition(
        for shot: CinematicCameraShot,
        settings: CinematicInfluenceSettings
    ) -> SIMD3<Float> {
        let base = shot.position
        let intensity = clampedIntensity(settings)

        switch settings.cameraStyle {
        case .steady:
            let homeBlend = 0.28 + (1 - intensity) * 0.22
            var position = mix(base, CinematicCameraShot.home.position, homeBlend)
            position.y += 0.18 + (1 - intensity) * 0.24
            return position
        case .follow:
            let adjustment = intensity - 0.5
            return [
                base.x * (1 + adjustment * 0.08),
                base.y + adjustment * 0.22,
                base.z * (1 - adjustment * 0.06)
            ]
        case .dramatic:
            let push = 0.13 + intensity * 0.15
            return [
                base.x * (1 + intensity * 0.08),
                max(1.75, base.y - 0.18 - intensity * 0.34),
                base.z * (1 - push)
            ]
        }
    }

    static func cameraFieldOfView(
        for shot: CinematicCameraShot,
        settings: CinematicInfluenceSettings
    ) -> Float {
        let base = shot.fieldOfView
        let intensity = clampedIntensity(settings)
        let adjusted: Float

        switch settings.cameraStyle {
        case .steady:
            adjusted = base - 2.8 + intensity * 2.0
        case .follow:
            adjusted = base + (intensity - 0.5) * 2.0
        case .dramatic:
            adjusted = base + 2.6 + intensity * 3.8
        }

        return clamp(adjusted, to: cameraFieldOfViewRange)
    }

    static func cameraTransitionDuration(
        for shot: CinematicCameraShot,
        settings: CinematicInfluenceSettings
    ) -> TimeInterval {
        let intensity = Double(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        let multiplier: Double

        switch settings.cameraStyle {
        case .steady:
            multiplier = 1.3 + (1 - intensity) * 0.45
        case .follow:
            multiplier = 1
        case .dramatic:
            multiplier = 0.86 - intensity * 0.18
        }

        return max(0.16, shot.duration * multiplier) * transitionComfortScale(settings)
    }

    static func cameraOrbitScale(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        let base: Float
        switch settings.cameraStyle {
        case .steady:
            base = 0.16 + intensity * 0.24
        case .follow:
            base = 0.7 + intensity * 0.6
        case .dramatic:
            base = 1.08 + intensity * 0.57
        }
        return max(0.04, base * motionComfortScale(settings))
    }

    static func cameraPullbackScale(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        switch settings.cameraStyle {
        case .steady:
            return 1.2 - intensity * 0.04
        case .follow:
            return 1
        case .dramatic:
            return 0.94 - intensity * 0.06
        }
    }

    static func cameraHeightOffset(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        switch settings.cameraStyle {
        case .steady:
            return 0.24 - intensity * 0.08
        case .follow:
            return 0
        case .dramatic:
            return -0.14 - intensity * 0.18
        }
    }

    static func cameraFollowResponsiveness(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        let base: Float
        switch settings.cameraStyle {
        case .steady:
            base = 2.2 + intensity * 0.6
        case .follow:
            base = 3.2 + intensity * 2.0
        case .dramatic:
            base = 4.7 + intensity * 1.6
        }
        return max(0.1, base * followComfortScale(settings))
    }

    static func cameraFollowFieldOfView(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        let adjusted: Float
        switch settings.cameraStyle {
        case .steady:
            adjusted = 35 + intensity * 2.0
        case .follow:
            adjusted = 38.5 + intensity * 2.0
        case .dramatic:
            adjusted = 42 + intensity * 4.0
        }
        return clamp(adjusted, to: cameraFollowFieldOfViewRange)
    }

    static func cameraDriftScale(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        let base: Float
        switch settings.cameraStyle {
        case .steady:
            base = 0.1 + intensity * 0.25
        case .follow:
            base = 0.65 + intensity * 0.7
        case .dramatic:
            base = 1.0 + intensity * 0.65
        }
        return max(0.03, base * motionComfortScale(settings))
    }

    static func cameraShakeScale(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        let base: Float
        switch settings.cameraStyle {
        case .steady:
            base = 0.12 + intensity * 0.28
        case .follow:
            base = 0.55 + intensity * 0.9
        case .dramatic:
            base = 1.0 + intensity * 0.85
        }
        let adjusted = base * shakeComfortScale(settings)
        return clamp(adjusted, to: cameraShakeScaleRange)
    }

    static func ambientSpawnCadence(
        activityProfile: RepositoryActivityProfile,
        settings: CinematicInfluenceSettings
    ) -> TimeInterval {
        let pressureScale = Double(activityPressureScale(settings: settings))
        let base: TimeInterval

        guard !activityProfile.isEmpty else {
            return clamp(2.6 / pressureScale, to: ambientSpawnCadenceRange)
        }

        switch activityProfile.pressureLevel {
        case .clean:
            base = activityProfile.successStreak > 1 ? 3.4 : 3.0
        case .light:
            base = 2.25
        case .moderate:
            base = 1.7
        case .heavy:
            base = 1.18
        }

        return clamp(base / pressureScale, to: ambientSpawnCadenceRange)
    }

    static func ambientEnemyLimit(
        activityProfile: RepositoryActivityProfile,
        settings: CinematicInfluenceSettings
    ) -> Int {
        let base: Int
        guard !activityProfile.isEmpty else {
            base = 8
            return clampedEnemyLimit(base: base, settings: settings)
        }

        switch activityProfile.pressureLevel {
        case .clean:
            base = 5
        case .light:
            base = 7
        case .moderate:
            base = 9
        case .heavy:
            base = 11
        }

        return clampedEnemyLimit(base: base, settings: settings)
    }

    static func activityLightBoost(
        activityProfile: RepositoryActivityProfile,
        settings: CinematicInfluenceSettings
    ) -> Float {
        guard !activityProfile.isEmpty else { return 0 }
        let pressureBoost = min(Float(activityProfile.pressureScore) * 24, 440)
        let streakBoost = Float(max(activityProfile.successStreak - 1, 0)) * 18
        let adjusted = (pressureBoost + streakBoost)
            * activityPressureScale(settings: settings)
            * activityLightComfortScale(settings)
        return clamp(adjusted, to: activityLightBoostRange)
    }

    static func activityPressureScale(settings: CinematicInfluenceSettings) -> Float {
        let intensity = clampedIntensity(settings)
        let base: Float
        switch settings.cameraStyle {
        case .steady:
            base = 0.42 + intensity * 0.28
        case .follow:
            base = 0.72 + intensity * 0.56
        case .dramatic:
            base = 1.12 + intensity * 0.53
        }
        return max(0.18, base * pressureComfortScale(settings))
    }

    private static func clampedEnemyLimit(
        base: Int,
        settings: CinematicInfluenceSettings
    ) -> Int {
        let intensity = CinematicInfluenceSettings.clampedIntensity(settings.intensity)
        let offset: Double
        switch settings.cameraStyle {
        case .steady:
            offset = -2 + intensity * 2
        case .follow:
            offset = -1 + intensity * 2
        case .dramatic:
            offset = 1 + intensity * 2
        }
        let adjusted = Double(base) + offset + Double(enemyLimitComfortOffset(settings))
        return clamp(Int(adjusted.rounded()), to: ambientEnemyLimitRange)
    }

    private static func motionComfortScale(_ settings: CinematicInfluenceSettings) -> Float {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 0.58
        case .quiet:
            return 0.34
        }
    }

    private static func followComfortScale(_ settings: CinematicInfluenceSettings) -> Float {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 0.86
        case .quiet:
            return 0.68
        }
    }

    private static func shakeComfortScale(_ settings: CinematicInfluenceSettings) -> Float {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 0.56
        case .quiet:
            return 0.32
        }
    }

    private static func pressureComfortScale(_ settings: CinematicInfluenceSettings) -> Float {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 0.72
        case .quiet:
            return 0.48
        }
    }

    private static func activityLightComfortScale(_ settings: CinematicInfluenceSettings) -> Float {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 0.82
        case .quiet:
            return 0.64
        }
    }

    private static func transitionComfortScale(_ settings: CinematicInfluenceSettings) -> Double {
        switch settings.comfortMode {
        case .standard:
            return 1
        case .reducedMotion:
            return 1.18
        case .quiet:
            return 1.42
        }
    }

    private static func enemyLimitComfortOffset(_ settings: CinematicInfluenceSettings) -> Int {
        switch settings.comfortMode {
        case .standard:
            return 0
        case .reducedMotion:
            return -1
        case .quiet:
            return -3
        }
    }

    private static func clampedIntensity(_ settings: CinematicInfluenceSettings) -> Float {
        Float(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * t
    }
}
