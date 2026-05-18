import Foundation

struct CinematicActivitySourceBeaconPlan: Equatable, Identifiable {
    static let identifierLimit = 260
    static let descriptorIdentifierLimit = 220
    static let entityNameLimit = 120
    static let labelLimit = 34
    static let detailLimit = 116
    static let copyTextLimit = 360
    static let routeIdentifierLimit = 96
    static let tintIdentifierLimit = CinematicActivitySourceCuePlan.tintIdentifierLimit

    static let hidden = CinematicActivitySourceBeaconPlan(snapshot: .notScanned())

    var id: String { identifier }

    var identifier: String
    var cueIdentifier: String
    var sourceIdentifier: String
    var statusIdentifier: String
    var kindIdentifier: String
    var activeStorageIdentifier: String
    var availabilityIdentifier: String
    var repoLocalSessionsStateIdentifier: String
    var repoLocalModeIdentifier: String
    var severityIdentifier: String
    var tintIdentifier: String
    var visibilityIdentifier: String
    var suppressionReason: String
    var descriptor: Descriptor?

    var isVisible: Bool { descriptor != nil }
    var isCritical: Bool { descriptor?.isCritical ?? false }
    var isQuietModeSuppressible: Bool { descriptor?.isQuietModeSuppressible ?? false }

    struct Descriptor: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var cueIdentifier: String
        var sourceIdentifier: String
        var statusIdentifier: String
        var kindIdentifier: String
        var activeStorageIdentifier: String
        var availabilityIdentifier: String
        var repoLocalSessionsStateIdentifier: String
        var repoLocalModeIdentifier: String
        var severityIdentifier: String
        var tintIdentifier: String
        var visibilityIdentifier: String
        var routeIdentifier: String
        var entityNamePrefix: String
        var rootEntityName: String
        var ringEntityName: String
        var coreEntityName: String
        var plateEntityName: String
        var labelEntityName: String
        var detailEntityName: String
        var label: String
        var detail: String
        var copyText: String
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var anchorPosition: SIMD3<Float>
        var phaseLightIntensity: Float
        var ringRadius: Float
        var coreRadius: Float
        var ringPipeRadius: Float
        var plateWidth: Float
        var plateHeight: Float
        var isCritical: Bool
        var isQuietModeSuppressible: Bool

        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var arenaEffectIdentifier: String { arenaEffect.rawValue }
        var cameraShotIdentifier: String { cameraShot.identifier }
    }

    init(
        snapshot: RepositoryActivitySourceSnapshot,
        status providedStatus: ProjectActivitySourceStatus? = nil,
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) {
        let status = providedStatus ?? ProjectActivitySourceStatus(snapshot: snapshot)
        let cue = CinematicActivitySourceCuePlan(snapshot: snapshot, status: status)
        cueIdentifier = cue.identifier
        sourceIdentifier = cue.sourceIdentifier
        statusIdentifier = cue.statusIdentifier
        kindIdentifier = cue.kindIdentifier
        activeStorageIdentifier = cue.activeStorageIdentifier
        availabilityIdentifier = cue.availabilityIdentifier
        repoLocalSessionsStateIdentifier = cue.repoLocalSessionsStateIdentifier
        repoLocalModeIdentifier = cue.repoLocalModeIdentifier
        severityIdentifier = cue.severityIdentifier
        tintIdentifier = Self.bounded(cue.tintIdentifier, limit: Self.tintIdentifierLimit)

        guard cue.isVisible else {
            visibilityIdentifier = "hidden"
            suppressionReason = "status-hidden"
            descriptor = nil
            identifier = Self.identifier(
                visibility: visibilityIdentifier,
                cueIdentifier: cue.identifier,
                kindIdentifier: cue.kindIdentifier,
                availabilityIdentifier: cue.availabilityIdentifier,
                severityIdentifier: cue.severityIdentifier
            )
            return
        }

        if influenceSettings.comfortMode == .quiet,
           cue.isQuietModeSuppressible {
            visibilityIdentifier = "suppressed-quiet-noncritical"
            suppressionReason = "quiet-noncritical"
            descriptor = nil
            identifier = Self.identifier(
                visibility: visibilityIdentifier,
                cueIdentifier: cue.identifier,
                kindIdentifier: cue.kindIdentifier,
                availabilityIdentifier: cue.availabilityIdentifier,
                severityIdentifier: cue.severityIdentifier
            )
            return
        }

        let visibility = cue.isCritical ? "visible-warning" : "visible"
        let lightFamily = Self.lightFamily(for: cue)
        let routeIdentifier = Self.bounded(
            [
                "activity-source-beacon",
                cue.kindIdentifier,
                cue.availabilityIdentifier,
                cue.severityIdentifier
            ].joined(separator: "."),
            limit: Self.routeIdentifierLimit
        )
        let entityNamePrefix = Self.bounded(
            [
                "activity-source-beacon",
                cue.kindIdentifier,
                cue.availabilityIdentifier
            ].joined(separator: "."),
            limit: Self.entityNameLimit - 12
        )
        let descriptorIdentifier = Self.bounded(
            [
                "activity-source-beacon",
                "visibility:\(visibility)",
                "cue:\(Self.fingerprint(cue.identifier))",
                "source:\(Self.fingerprint(cue.sourceIdentifier))",
                "status:\(Self.fingerprint(cue.statusIdentifier))",
                "kind:\(cue.kindIdentifier)",
                "storage:\(cue.activeStorageIdentifier)",
                "availability:\(cue.availabilityIdentifier)",
                "severity:\(cue.severityIdentifier)",
                "tint:\(cue.tintIdentifier)"
            ].joined(separator: "|"),
            limit: Self.descriptorIdentifierLimit
        )
        let anchor = Self.anchorPosition(for: cue)

        visibilityIdentifier = visibility
        suppressionReason = "none"
        descriptor = Descriptor(
            identifier: descriptorIdentifier,
            cueIdentifier: cue.identifier,
            sourceIdentifier: cue.sourceIdentifier,
            statusIdentifier: cue.statusIdentifier,
            kindIdentifier: cue.kindIdentifier,
            activeStorageIdentifier: cue.activeStorageIdentifier,
            availabilityIdentifier: cue.availabilityIdentifier,
            repoLocalSessionsStateIdentifier: cue.repoLocalSessionsStateIdentifier,
            repoLocalModeIdentifier: cue.repoLocalModeIdentifier,
            severityIdentifier: cue.severityIdentifier,
            tintIdentifier: Self.bounded(cue.tintIdentifier, limit: Self.tintIdentifierLimit),
            visibilityIdentifier: visibility,
            routeIdentifier: routeIdentifier,
            entityNamePrefix: entityNamePrefix,
            rootEntityName: Self.bounded("\(entityNamePrefix).root", limit: Self.entityNameLimit),
            ringEntityName: Self.bounded("\(entityNamePrefix).ring", limit: Self.entityNameLimit),
            coreEntityName: Self.bounded("\(entityNamePrefix).core", limit: Self.entityNameLimit),
            plateEntityName: Self.bounded("\(entityNamePrefix).plate", limit: Self.entityNameLimit),
            labelEntityName: Self.bounded("\(entityNamePrefix).label", limit: Self.entityNameLimit),
            detailEntityName: Self.bounded("\(entityNamePrefix).detail", limit: Self.entityNameLimit),
            label: Self.bounded(cue.label, limit: Self.labelLimit),
            detail: Self.bounded(cue.detail, limit: Self.detailLimit),
            copyText: Self.bounded(cue.copyText, limit: Self.copyTextLimit),
            lightFamily: lightFamily,
            arenaEffect: Self.arenaEffect(for: cue),
            cameraShot: Self.cameraShot(for: cue),
            lookTarget: Self.lookTarget(for: cue, anchor: anchor),
            anchorPosition: anchor,
            phaseLightIntensity: Self.phaseLightIntensity(for: cue),
            ringRadius: cue.isCritical ? 0.25 : 0.21,
            coreRadius: cue.isCritical ? 0.072 : 0.058,
            ringPipeRadius: cue.isCritical ? 0.0075 : 0.006,
            plateWidth: 1.58,
            plateHeight: cue.detail.isEmpty ? 0.2 : 0.34,
            isCritical: cue.isCritical,
            isQuietModeSuppressible: cue.isQuietModeSuppressible
        )
        identifier = Self.identifier(
            visibility: visibility,
            cueIdentifier: cue.identifier,
            kindIdentifier: cue.kindIdentifier,
            availabilityIdentifier: cue.availabilityIdentifier,
            severityIdentifier: cue.severityIdentifier
        )
    }

    private static func identifier(
        visibility: String,
        cueIdentifier: String,
        kindIdentifier: String,
        availabilityIdentifier: String,
        severityIdentifier: String
    ) -> String {
        Self.bounded(
            [
                "activity-source-beacon",
                "visibility:\(visibility)",
                "cue:\(Self.fingerprint(cueIdentifier))",
                "kind:\(kindIdentifier)",
                "availability:\(availabilityIdentifier)",
                "severity:\(severityIdentifier)"
            ].joined(separator: "|"),
            limit: identifierLimit
        )
    }

    private static func lightFamily(for cue: CinematicActivitySourceCuePlan) -> CinematicStageLightFamily {
        switch cue.severityIdentifier {
        case "failure":
            return .failure
        case "warning":
            return .pressure
        case "info":
            return cue.activeStorageIdentifier == KnownProjectActiveStorage.applicationSupport.rawValue
                ? .scan
                : .insight
        default:
            return .git
        }
    }

    private static func arenaEffect(for cue: CinematicActivitySourceCuePlan) -> CinematicStageArenaEffect {
        switch cue.severityIdentifier {
        case "failure":
            return .charge
        case "warning":
            return .activityPulse
        case "info":
            return cue.activeStorageIdentifier == KnownProjectActiveStorage.applicationSupport.rawValue
                ? .seal
                : .activityPulse
        default:
            return .none
        }
    }

    private static func cameraShot(for cue: CinematicActivitySourceCuePlan) -> CinematicCameraShot {
        switch cue.severityIdentifier {
        case "failure":
            return .wide
        case "warning":
            return .overhead
        default:
            return .castPrep
        }
    }

    private static func anchorPosition(for cue: CinematicActivitySourceCuePlan) -> SIMD3<Float> {
        switch cue.severityIdentifier {
        case "failure":
            return [-2.72, 0.78, 1.72]
        case "warning":
            return [-2.56, 0.76, 1.94]
        default:
            return [-2.36, 0.68, 2.12]
        }
    }

    private static func lookTarget(
        for cue: CinematicActivitySourceCuePlan,
        anchor: SIMD3<Float>
    ) -> SIMD3<Float> {
        let severityLift: Float
        switch cue.severityIdentifier {
        case "failure":
            severityLift = 0.38
        case "warning":
            severityLift = 0.32
        default:
            severityLift = 0.24
        }
        return anchor + [0.04, severityLift, -0.12]
    }

    private static func phaseLightIntensity(for cue: CinematicActivitySourceCuePlan) -> Float {
        switch cue.severityIdentifier {
        case "failure":
            return 820
        case "warning":
            return 720
        case "info":
            return 560
        default:
            return 440
        }
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "" }
        guard normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }
        return normalized.prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
