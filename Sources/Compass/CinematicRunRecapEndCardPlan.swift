import Foundation

struct CinematicRunRecapEndCardPlan: Equatable {
    typealias LayoutDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor
    typealias PlaqueTreatmentDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor

    static let identifierMaxCharacters = 280
    static let titleMaxCharacters = CinematicRunRecapPlan.titleLimit
    static let detailMaxCharacters = CinematicRunRecapPlan.detailLimit
    static let statusMaxCharacters = CinematicRunRecapPlan.statusLimit
    static let pinnedComparisonLabelMaxCharacters = 58
    static let pinnedComparisonDetailMaxCharacters = 118
    static let pinnedComparisonDeltaLabelMaxCharacters = 28
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
        var pinnedComparisonCue: PinnedComparisonCue?
        var pinnedComparisonCueModeIdentifier: String
        var pinnedComparisonCueStateIdentifier: String
        var pinnedComparisonCueNoMatchStateIdentifier: String

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
        var hasPinnedComparisonCue: Bool { pinnedComparisonCue != nil }
    }

    struct PinnedComparisonCue: Equatable {
        var identifier: String
        var comparisonIdentifier: String
        var comparisonExportIdentifier: String
        var modeIdentifier: String
        var stateIdentifier: String
        var targetDirectionIdentifier: String
        var selectedEntryIdentifier: String
        var targetEntryIdentifier: String
        var selectedSessionNumber: Int
        var targetSessionNumber: Int
        var deltaLabel: String
        var pinnedEntryCount: Int
        var retainedPinnedEntryCount: Int
        var missingPinnedEntryCount: Int
        var filteredPinnedEntryCount: Int
        var promotedHoldStateIdentifier: String
        var promotedHoldEntryIdentifier: String?
        var warningStateIdentifier: String
        var noMatchStateIdentifier: String
        var glyphIdentifier: String
        var railTreatmentIdentifier: String
        var label: String
        var detail: String

        var labelLength: Int { label.count }
        var detailLength: Int { detail.count }
        var deltaLabelLength: Int { deltaLabel.count }
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
        recapPlan: CinematicRunRecapPlan,
        artifactComparisonPlan: CinematicRunRecapShareArtifactComparisonPlan? = nil
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
        let pinnedComparisonCueState = pinnedComparisonCueState(
            for: artifactComparisonPlan
        )
        let copySignature = copyIdentifier(title, detail, status)
        var descriptorIdentifierParts = ["run-recap-end-card"]
        if let cue = pinnedComparisonCueState.cue {
            descriptorIdentifierParts.append("pinned-cue:\(fingerprint(cue.identifier))")
        }
        descriptorIdentifierParts += [
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
        ]
        let descriptorIdentifier = bounded(
            descriptorIdentifierParts.joined(separator: "|"),
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
            plaqueTreatment: treatment.plaqueTreatment,
            pinnedComparisonCue: pinnedComparisonCueState.cue,
            pinnedComparisonCueModeIdentifier: pinnedComparisonCueState.modeIdentifier,
            pinnedComparisonCueStateIdentifier: pinnedComparisonCueState.stateIdentifier,
            pinnedComparisonCueNoMatchStateIdentifier: pinnedComparisonCueState.noMatchStateIdentifier
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

    private struct PinnedComparisonCueState {
        var modeIdentifier: String
        var stateIdentifier: String
        var noMatchStateIdentifier: String
        var cue: CinematicRunRecapEndCardPlan.PinnedComparisonCue?
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

    private static func pinnedComparisonCueState(
        for plan: CinematicRunRecapShareArtifactComparisonPlan?
    ) -> PinnedComparisonCueState {
        guard let plan else {
            return PinnedComparisonCueState(
                modeIdentifier: "none",
                stateIdentifier: "inactive",
                noMatchStateIdentifier: "none",
                cue: nil
            )
        }

        let modeIdentifier = plan.targetModeIdentifier
        let stateIdentifier = plan.targetMode == .pinnedReference
            ? plan.pinnedTargetStateIdentifier
            : "inactive"
        let noMatchStateIdentifier = plan.noMatchAvailabilityReason ?? "none"

        guard plan.targetMode == .pinnedReference,
              let selectedEntryIdentifier = plan.selectedEntryIdentifier,
              let targetEntryIdentifier = plan.pinnedTargetEntryIdentifier,
              targetEntryIdentifier != selectedEntryIdentifier,
              plan.retainedPinnedEntryIdentifiers.contains(targetEntryIdentifier),
              let selectedSessionNumber = plan.selectedSessionNumber,
              let targetSessionNumber = plan.compareSessionNumber else {
            return PinnedComparisonCueState(
                modeIdentifier: modeIdentifier,
                stateIdentifier: stateIdentifier,
                noMatchStateIdentifier: noMatchStateIdentifier,
                cue: nil
            )
        }

        let deltaLabel = bounded(
            deltaLabel(for: plan.sessionDelta),
            limit: CinematicRunRecapEndCardPlan.pinnedComparisonDeltaLabelMaxCharacters
        )
        let isPromotedHoldTarget = plan.promotedHoldStateIdentifier == "retained-promoted-hold-target"
            || plan.promotedHoldStateIdentifier == "filtered-promoted-hold-target"
        let label = bounded(
            isPromotedHoldTarget
                ? "Promoted hold S\(selectedSessionNumber) to S\(targetSessionNumber)"
                : "Pinned compare S\(selectedSessionNumber) to S\(targetSessionNumber)",
            limit: CinematicRunRecapEndCardPlan.pinnedComparisonLabelMaxCharacters
        )
        let detail = bounded(
            [
                deltaLabel,
                isPromotedHoldTarget ? "held artifact" : nil,
                "pins \(plan.retainedPinnedEntryCount)/\(plan.pinnedEntryCount)",
                plan.filteredPinnedEntryCount > 0 ? "filtered \(plan.filteredPinnedEntryCount)" : nil,
                plan.missingPinnedEntryCount > 0 ? "stale \(plan.missingPinnedEntryCount)" : nil,
                plan.warningStateIdentifier == "warnings" ? "warnings" : nil
            ].compactMap { $0 }.joined(separator: " | "),
            limit: CinematicRunRecapEndCardPlan.pinnedComparisonDetailMaxCharacters
        )
        let glyphIdentifier = glyphIdentifier(for: plan)
        let railTreatmentIdentifier = railTreatmentIdentifier(for: plan)
        let cueIdentifier = bounded(
            [
                "run-recap-end-card-pinned-comparison",
                "comparison:\(fingerprint(plan.identifier))",
                "export:\(fingerprint(plan.exportIdentifier))",
                "mode:\(modeIdentifier)",
                "state:\(stateIdentifier)",
                "selected:\(fingerprint(selectedEntryIdentifier))",
                "target:\(fingerprint(targetEntryIdentifier))",
                "sessions:\(selectedSessionNumber)-\(targetSessionNumber)",
                "delta:\(plan.sessionDelta.map(String.init) ?? "none")",
                "pins:\(plan.pinnedEntryCount),\(plan.retainedPinnedEntryCount),\(plan.missingPinnedEntryCount),\(plan.filteredPinnedEntryCount)",
                "promoted-hold:\(plan.promotedHoldStateIdentifier)",
                "promoted-hold-entry:\(fingerprint(plan.retainedSavedTourHoldEntryIdentifier ?? "none"))",
                "warning:\(plan.warningStateIdentifier)",
                "no-match:\(noMatchStateIdentifier)",
                "glyph:\(glyphIdentifier)",
                "rail:\(railTreatmentIdentifier)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapEndCardPlan.identifierMaxCharacters
        )

        return PinnedComparisonCueState(
            modeIdentifier: modeIdentifier,
            stateIdentifier: stateIdentifier,
            noMatchStateIdentifier: noMatchStateIdentifier,
            cue: CinematicRunRecapEndCardPlan.PinnedComparisonCue(
                identifier: cueIdentifier,
                comparisonIdentifier: bounded(
                    plan.identifier,
                    limit: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
                ),
                comparisonExportIdentifier: bounded(
                    plan.exportIdentifier,
                    limit: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
                ),
                modeIdentifier: modeIdentifier,
                stateIdentifier: stateIdentifier,
                targetDirectionIdentifier: plan.targetDirectionIdentifier,
                selectedEntryIdentifier: bounded(
                    selectedEntryIdentifier,
                    limit: CinematicRunRecapEndCardPlan.identifierMaxCharacters
                ),
                targetEntryIdentifier: bounded(
                    targetEntryIdentifier,
                    limit: CinematicRunRecapEndCardPlan.identifierMaxCharacters
                ),
                selectedSessionNumber: selectedSessionNumber,
                targetSessionNumber: targetSessionNumber,
                deltaLabel: deltaLabel,
                pinnedEntryCount: plan.pinnedEntryCount,
                retainedPinnedEntryCount: plan.retainedPinnedEntryCount,
                missingPinnedEntryCount: plan.missingPinnedEntryCount,
                filteredPinnedEntryCount: plan.filteredPinnedEntryCount,
                promotedHoldStateIdentifier: plan.promotedHoldStateIdentifier,
                promotedHoldEntryIdentifier: plan.retainedSavedTourHoldEntryIdentifier,
                warningStateIdentifier: plan.warningStateIdentifier,
                noMatchStateIdentifier: noMatchStateIdentifier,
                glyphIdentifier: glyphIdentifier,
                railTreatmentIdentifier: railTreatmentIdentifier,
                label: label,
                detail: detail
            )
        )
    }

    private static func deltaLabel(for delta: Int?) -> String {
        guard let delta else { return "delta none" }
        return delta == 1 ? "delta 1 session" : "delta \(delta) sessions"
    }

    private static func glyphIdentifier(
        for plan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        if plan.promotedHoldStateIdentifier == "filtered-promoted-hold-target" {
            return "hold.pin.bridge.filtered"
        }
        if plan.promotedHoldStateIdentifier == "retained-promoted-hold-target" {
            return plan.warningStateIdentifier == "warnings"
                ? "hold.pin.bridge.warning"
                : "hold.pin.bridge.active"
        }
        if plan.pinnedTargetStateIdentifier == "filtered-pinned-target" {
            return "pin.bridge.filtered"
        }
        if plan.warningStateIdentifier == "warnings" {
            return "pin.bridge.warning"
        }
        if plan.missingPinnedEntryCount > 0 {
            return "pin.bridge.stale"
        }
        return "pin.bridge.active"
    }

    private static func railTreatmentIdentifier(
        for plan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        if plan.promotedHoldStateIdentifier == "filtered-promoted-hold-target" {
            return "filtered-promoted-hold-rail"
        }
        if plan.promotedHoldStateIdentifier == "retained-promoted-hold-target" {
            return plan.warningStateIdentifier == "warnings"
                ? "warning-promoted-hold-rail"
                : "promoted-hold-rail"
        }
        if plan.pinnedTargetStateIdentifier == "filtered-pinned-target" {
            return "filtered-pin-rail"
        }
        if plan.warningStateIdentifier == "warnings" {
            return "warning-pin-rail"
        }
        if plan.missingPinnedEntryCount > 0 {
            return "stale-pin-rail"
        }
        return "pin-bridge-rail"
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
