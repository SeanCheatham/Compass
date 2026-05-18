import Foundation

struct CinematicRunRecapSceneFocusPlan: Equatable {
    static let identifierMaxCharacters = 240
    static let targetXRange = CinematicTimelineSceneFocusPlan.targetXRange
    static let targetYRange = CinematicTimelineSceneFocusPlan.targetYRange
    static let targetZRange = CinematicTimelineSceneFocusPlan.targetZRange

    static let none = CinematicRunRecapSceneFocusPlan(
        identifier: "run-recap-scene-focus.none",
        descriptor: nil
    )

    var identifier: String
    var descriptor: Descriptor?

    var isActive: Bool { descriptor != nil }

    struct Descriptor: Equatable {
        var identifier: String
        var recapIdentifier: String
        var terminalBeatID: String?
        var terminalStatusIdentifier: String
        var terminalStyleIdentifier: String
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
        var commitNodeIdentifier: String?
        var fallbackTargetIdentifier: String?
        var usesFallbackTarget: Bool

        var cameraShotIdentifier: String { cameraShot.identifier }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var arenaEffectIdentifier: String { arenaEffect.rawValue }
    }

    fileprivate init(
        identifier: String,
        descriptor: Descriptor?
    ) {
        self.identifier = identifier
        self.descriptor = descriptor
    }
}

enum CinematicRunRecapSceneFocusPlanner {
    static func plan(
        isRecapOverlaySelected: Bool,
        recapPlan: CinematicRunRecapPlan,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelinePlan: CinematicSessionTimelinePlan
    ) -> CinematicRunRecapSceneFocusPlan {
        guard isRecapOverlaySelected, recapPlan.isAvailable else {
            return .none
        }

        let terminalBeat = terminalBeat(for: recapPlan, timelinePlan: timelinePlan)
        let terminalStyle = terminalStyle(recapPlan: recapPlan, terminalBeat: terminalBeat)
        let treatment = treatment(for: terminalStyle)
        let focusPlan = commitConstellationPlan.focusPlan
        let newestNode = commitConstellationPlan.nodes.first
        let lookTarget = boundedTarget(newestNode?.position ?? focusPlan.lookTarget)
        let usesFallback = newestNode == nil || focusPlan.isFallback
        let fallbackTargetIdentifier = usesFallback ? focusPlan.identifier : nil
        let descriptorIdentifier = bounded(
            [
                "run-recap-scene-focus",
                "recap:\(fingerprint(recapPlan.identifier))",
                "session:\(recapPlan.sessionNumber.map(String.init) ?? "none")",
                "status:\(recapPlan.statusIdentifier)",
                "terminal:\(terminalBeat?.stableID ?? "none")",
                "style:\(terminalStyle.rawValue)",
                "shot:\(treatment.cameraShot.identifier)",
                "target:\(positionIdentifier(lookTarget))",
                "node:\(newestNode?.stableID ?? "fallback")",
                "light:\(treatment.lightFamily.rawValue)",
                "effect:\(treatment.arenaEffect.rawValue)",
                "phase:\(fixed(treatment.phaseLightIntensity))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapSceneFocusPlan.identifierMaxCharacters
        )
        let descriptor = CinematicRunRecapSceneFocusPlan.Descriptor(
            identifier: descriptorIdentifier,
            recapIdentifier: recapPlan.identifier,
            terminalBeatID: terminalBeat?.stableID,
            terminalStatusIdentifier: recapPlan.statusIdentifier,
            terminalStyleIdentifier: terminalStyle.rawValue,
            cameraShot: treatment.cameraShot,
            lookTarget: lookTarget,
            lightFamily: treatment.lightFamily,
            arenaEffect: treatment.arenaEffect,
            phaseLightIntensity: clamp(
                treatment.phaseLightIntensity,
                to: CinematicRecoveryCuePlan.phaseLightIntensityRange
            ),
            commitNodeIdentifier: newestNode?.stableID,
            fallbackTargetIdentifier: fallbackTargetIdentifier,
            usesFallbackTarget: usesFallback
        )

        return CinematicRunRecapSceneFocusPlan(
            identifier: bounded(
                [
                    "run-recap-scene-focus",
                    "descriptor:\(descriptor.identifier)"
                ].joined(separator: "|"),
                limit: CinematicRunRecapSceneFocusPlan.identifierMaxCharacters
            ),
            descriptor: descriptor
        )
    }

    private struct Treatment {
        var cameraShot: CinematicCameraShot
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
    }

    private static func terminalBeat(
        for recapPlan: CinematicRunRecapPlan,
        timelinePlan: CinematicSessionTimelinePlan
    ) -> CinematicSessionTimelinePlan.Beat? {
        guard let sessionNumber = recapPlan.sessionNumber else {
            return timelinePlan.beats.last
        }

        return timelinePlan.beats.last {
            $0.sessionNumber == sessionNumber && $0.moment == .outcome
        } ?? timelinePlan.beats.last {
            $0.sessionNumber == sessionNumber
        } ?? timelinePlan.beats.last
    }

    private static func terminalStyle(
        recapPlan: CinematicRunRecapPlan,
        terminalBeat: CinematicSessionTimelinePlan.Beat?
    ) -> CinematicRunRecapPlan.Style {
        guard let terminalBeat else { return recapPlan.style }

        switch terminalBeat.style {
        case .success:
            return .success
        case .failure:
            return .failure
        case .warning:
            return .warning
        case .paused:
            return .paused
        case .neutral, .active, .commit:
            return recapPlan.style
        }
    }

    private static func treatment(for style: CinematicRunRecapPlan.Style) -> Treatment {
        switch style {
        case .success:
            return Treatment(
                cameraShot: .victory,
                lightFamily: .verify,
                arenaEffect: .victory,
                phaseLightIntensity: 820
            )
        case .failure:
            return Treatment(
                cameraShot: .failure,
                lightFamily: .failure,
                arenaEffect: .charge,
                phaseLightIntensity: 900
            )
        case .warning:
            return Treatment(
                cameraShot: .wide,
                lightFamily: .pressure,
                arenaEffect: .activityPulse,
                phaseLightIntensity: 680
            )
        case .paused:
            return Treatment(
                cameraShot: .home,
                lightFamily: .lifecycle,
                arenaEffect: .none,
                phaseLightIntensity: 420
            )
        case .empty:
            return Treatment(
                cameraShot: .home,
                lightFamily: .lifecycle,
                arenaEffect: .none,
                phaseLightIntensity: 360
            )
        }
    }

    private static func boundedTarget(_ target: SIMD3<Float>) -> SIMD3<Float> {
        [
            clamp(target.x, to: CinematicRunRecapSceneFocusPlan.targetXRange),
            clamp(target.y, to: CinematicRunRecapSceneFocusPlan.targetYRange),
            clamp(target.z, to: CinematicRunRecapSceneFocusPlan.targetZRange)
        ]
    }

    private static func positionIdentifier(_ value: SIMD3<Float>) -> String {
        [
            fixed(value.x),
            fixed(value.y),
            fixed(value.z)
        ].joined(separator: ",")
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }
}
