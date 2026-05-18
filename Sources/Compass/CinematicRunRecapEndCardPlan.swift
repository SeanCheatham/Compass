import Foundation

struct CinematicRunRecapEndCardPlan: Equatable {
    typealias LayoutDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor
    typealias PlaqueTreatmentDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor

    static let identifierMaxCharacters = 280
    static let titleMaxCharacters = CinematicRunRecapPlan.titleLimit
    static let detailMaxCharacters = CinematicRunRecapPlan.detailLimit
    static let statusMaxCharacters = CinematicRunRecapPlan.statusLimit
    static let scaleRange: ClosedRange<Float> = 0.78...1.22
    static let cadenceRange: ClosedRange<TimeInterval> = 2.2...5.4

    static let none = CinematicRunRecapEndCardPlan(
        identifier: "run-recap-end-card.none",
        descriptor: nil
    )

    var identifier: String
    var descriptor: Descriptor?

    var isActive: Bool { descriptor != nil }

    struct Descriptor: Equatable {
        var identifier: String
        var recapIdentifier: String
        var title: String
        var detail: String
        var status: String
        var titleSourceIdentifier: String
        var flavorStateIdentifier: String
        var flavorIdentifier: String?
        var flavorSourceIdentifier: String?
        var styleIdentifier: String
        var colorIdentifier: String
        var anchor: CinematicNarrativeCueAnchor
        var scale: Float
        var cadence: TimeInterval
        var lightFamily: CinematicStageLightFamily
        var tintFamily: CinematicStageLightFamily
        var glyphIdentifier: String
        var layout: LayoutDescriptor
        var plaqueTreatment: PlaqueTreatmentDescriptor

        var anchorIdentifier: String { anchor.rawValue }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var tintFamilyIdentifier: String { tintFamily.rawValue }
        var plaqueTreatmentIdentifier: String { plaqueTreatment.identifier }
        var plaqueTreatmentAccentIdentifier: String { plaqueTreatment.accentIdentifier }
        var plaqueTreatmentRouteIdentifier: String { plaqueTreatment.routeIdentifier }
        var plaqueTreatmentRenderRecipeIdentifier: String { plaqueTreatment.renderRecipe.identifier }
        var plaqueTreatmentRenderPrimitiveIdentifiers: [String] {
            plaqueTreatment.renderRecipe.primitiveIdentifiers
        }
        var plaqueTreatmentRenderPrimitiveCount: Int { plaqueTreatment.renderRecipe.primitiveCount }
        var titleLength: Int { title.count }
        var detailLength: Int { detail.count }
        var statusLength: Int { status.count }
    }

    fileprivate init(
        identifier: String,
        descriptor: Descriptor?
    ) {
        self.identifier = identifier
        self.descriptor = descriptor
    }
}

enum CinematicRunRecapEndCardPlanner {
    private typealias LayoutDescriptor = CinematicRunRecapEndCardPlan.LayoutDescriptor
    private typealias PlaqueTreatmentDescriptor = CinematicRunRecapEndCardPlan.PlaqueTreatmentDescriptor

    static func plan(
        isRecapOverlaySelected: Bool,
        recapPlan: CinematicRunRecapPlan
    ) -> CinematicRunRecapEndCardPlan {
        guard isRecapOverlaySelected, recapPlan.isAvailable else {
            return .none
        }

        let treatment = treatment(for: recapPlan.style)
        let title = CinematicRunRecapPlan.boundedText(
            recapPlan.title,
            limit: CinematicRunRecapEndCardPlan.titleMaxCharacters
        )
        let detail = CinematicRunRecapPlan.boundedText(
            recapPlan.detail,
            limit: CinematicRunRecapEndCardPlan.detailMaxCharacters
        )
        let status = CinematicRunRecapPlan.boundedText(
            recapPlan.status,
            limit: CinematicRunRecapEndCardPlan.statusMaxCharacters
        )
        let layout = layoutDescriptor(
            for: treatment.anchor,
            style: recapPlan.style
        )
        let copySignature = copyIdentifier(title, detail, status)
        let descriptorIdentifier = bounded(
            [
                "run-recap-end-card",
                "recap:\(fingerprint(recapPlan.identifier))",
                "source:\(fingerprint(recapPlan.sourceIdentifier ?? "none"))",
                "flavor:\(recapPlan.flavorStateIdentifier)",
                "flavor-id:\(fingerprint(recapPlan.flavorIdentifier ?? "none"))",
                "flavor-source:\(fingerprint(recapPlan.flavorSourceIdentifier ?? "none"))",
                "title-source:\(recapPlan.titleSourceIdentifier)",
                "copy:\(fingerprint(copySignature))",
                "lengths:\(title.count),\(detail.count),\(status.count)",
                "style:\(recapPlan.style.rawValue)",
                "color:\(recapPlan.colorIdentifier)",
                "anchor:\(treatment.anchor.rawValue)",
                "scale:\(fixed(treatment.scale))",
                "cadence:\(fixed(treatment.cadence))",
                "glyph:\(treatment.glyphIdentifier)",
                "layout:\(fingerprint(layout.identifier))",
                "plate:\(fingerprint(treatment.plaqueTreatment.identifier))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapEndCardPlan.identifierMaxCharacters
        )
        let descriptor = CinematicRunRecapEndCardPlan.Descriptor(
            identifier: descriptorIdentifier,
            recapIdentifier: recapPlan.identifier,
            title: title,
            detail: detail,
            status: status,
            titleSourceIdentifier: recapPlan.titleSourceIdentifier,
            flavorStateIdentifier: recapPlan.flavorStateIdentifier,
            flavorIdentifier: recapPlan.flavorIdentifier,
            flavorSourceIdentifier: recapPlan.flavorSourceIdentifier,
            styleIdentifier: recapPlan.style.rawValue,
            colorIdentifier: recapPlan.colorIdentifier,
            anchor: treatment.anchor,
            scale: clamp(treatment.scale, to: CinematicRunRecapEndCardPlan.scaleRange),
            cadence: clamp(treatment.cadence, to: CinematicRunRecapEndCardPlan.cadenceRange),
            lightFamily: treatment.lightFamily,
            tintFamily: treatment.tintFamily,
            glyphIdentifier: treatment.glyphIdentifier,
            layout: layout,
            plaqueTreatment: treatment.plaqueTreatment
        )

        return CinematicRunRecapEndCardPlan(
            identifier: bounded(
                [
                    "run-recap-end-card",
                    "descriptor:\(descriptor.identifier)"
                ].joined(separator: "|"),
                limit: CinematicRunRecapEndCardPlan.identifierMaxCharacters
            ),
            descriptor: descriptor
        )
    }

    private struct Treatment {
        var anchor: CinematicNarrativeCueAnchor
        var lightFamily: CinematicStageLightFamily
        var tintFamily: CinematicStageLightFamily
        var glyphIdentifier: String
        var scale: Float
        var cadence: TimeInterval
        var plaqueTreatment: PlaqueTreatmentDescriptor
    }

    private static func treatment(for style: CinematicRunRecapPlan.Style) -> Treatment {
        switch style {
        case .success:
            return Treatment(
                anchor: .victoryArch,
                lightFamily: .verify,
                tintFamily: .git,
                glyphIdentifier: "recap.success.seal",
                scale: 1.13,
                cadence: 3.1,
                plaqueTreatment: plaqueTreatment(
                    accent: .verifySeal,
                    routeIdentifier: "recap.success",
                    emissionBoost: 0.1,
                    edgeRailOpacity: 0.5,
                    braceOpacity: 0.18,
                    fractureOpacity: 0,
                    pulseScale: 1.02
                )
            )
        case .failure:
            return Treatment(
                anchor: .fractureGate,
                lightFamily: .failure,
                tintFamily: .failure,
                glyphIdentifier: "recap.failure.fracture",
                scale: 1.16,
                cadence: 2.35,
                plaqueTreatment: plaqueTreatment(
                    accent: .failureFracture,
                    routeIdentifier: "recap.failure",
                    emissionBoost: 0.26,
                    edgeRailOpacity: 0.74,
                    braceOpacity: 0.56,
                    fractureOpacity: 0.64,
                    pulseScale: 1.08
                )
            )
        case .warning:
            return Treatment(
                anchor: .rightWarningPylon,
                lightFamily: .pressure,
                tintFamily: .failure,
                glyphIdentifier: "recap.warning.rails",
                scale: 1.06,
                cadence: 2.75,
                plaqueTreatment: plaqueTreatment(
                    accent: .warningRails,
                    routeIdentifier: "recap.warning",
                    emissionBoost: 0.16,
                    edgeRailOpacity: 0.64,
                    braceOpacity: 0.34,
                    fractureOpacity: 0.2,
                    pulseScale: 1.04
                )
            )
        case .paused:
            return Treatment(
                anchor: .idleArchive,
                lightFamily: .lifecycle,
                tintFamily: .insight,
                glyphIdentifier: "recap.paused.gate",
                scale: 0.98,
                cadence: 4.2,
                plaqueTreatment: plaqueTreatment(
                    accent: .retryBraces,
                    routeIdentifier: "recap.paused",
                    emissionBoost: 0.14,
                    edgeRailOpacity: 0.46,
                    braceOpacity: 0.54,
                    fractureOpacity: 0.18,
                    pulseScale: 1.03
                )
            )
        case .empty:
            return Treatment(
                anchor: .idleArchive,
                lightFamily: .lifecycle,
                tintFamily: .lifecycle,
                glyphIdentifier: "recap.empty",
                scale: 0.9,
                cadence: 5.0,
                plaqueTreatment: .none
            )
        }
    }

    private static func plaqueTreatment(
        accent: PlaqueTreatmentDescriptor.Accent,
        routeIdentifier: String,
        emissionBoost: Float,
        edgeRailOpacity: Float,
        braceOpacity: Float,
        fractureOpacity: Float,
        pulseScale: Float
    ) -> PlaqueTreatmentDescriptor {
        PlaqueTreatmentDescriptor(
            accent: accent,
            routeIdentifier: routeIdentifier,
            emissionBoost: emissionBoost,
            edgeRailOpacity: edgeRailOpacity,
            braceOpacity: braceOpacity,
            fractureOpacity: fractureOpacity,
            pulseScale: pulseScale
        )
    }

    private static func layoutDescriptor(
        for anchor: CinematicNarrativeCueAnchor,
        style: CinematicRunRecapPlan.Style
    ) -> LayoutDescriptor {
        let position = anchorPosition(for: anchor)
        let isFailure = style == .failure
        let hasWarning = style == .warning || style == .paused
        let plateWidth: Float = isFailure ? 3.82 : 3.66
        let plateHeight: Float = hasWarning ? 0.74 : 0.7
        return LayoutDescriptor(
            anchorPosition: position,
            facingMode: .arenaCamera,
            plateSize: [plateWidth, plateHeight],
            primaryTextWidth: 2.88,
            secondaryTextWidth: 3.02,
            primaryFontSize: isFailure ? 0.142 : 0.148,
            secondaryFontSize: 0.072,
            backingOpacity: isFailure ? 0.34 : 0.3,
            glyphSide: .leading,
            glyphOffset: [-1.55, 0.03, 0.058],
            plateDepth: 0.046,
            plateZOffset: -0.024,
            primaryTextOffset: [0.18, 0.17, 0.052],
            secondaryTextOffset: [0.18, -0.048, 0.056]
        )
    }

    private static func anchorPosition(for anchor: CinematicNarrativeCueAnchor) -> SIMD3<Float> {
        switch anchor {
        case .victoryArch:
            return [0, 2.0, -3.45]
        case .fractureGate:
            return [-0.55, 1.66, -3.85]
        case .rightWarningPylon:
            return [4.35, 1.62, -0.85]
        case .idleArchive:
            return [-4.25, 1.34, 1.15]
        case .leftScoutPylon:
            return [-4.15, 1.34, -0.55]
        case .leftForgePylon:
            return [-4.45, 1.5, -1.05]
        case .leftSealPylon:
            return [-3.75, 1.74, -2.2]
        case .arenaCenter:
            return [0, 0.38, 0]
        case .arenaFront:
            return [0, 0.48, 2.4]
        case .arenaRear:
            return [0, 0.48, -2.4]
        case .rightPylon:
            return [4.15, 1.4, 0.9]
        case .rightHistoryPylon:
            return [4.35, 1.5, -2.2]
        }
    }

    private static func copyIdentifier(_ values: String...) -> String {
        values.map(normalizedText).joined(separator: "/")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    private static func fixed(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }
}
