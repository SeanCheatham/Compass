import Foundation

struct CinematicPlanCompassSceneFocusPlan: Equatable {
    static let identifierMaxCharacters = 280
    static let plaqueTitleMaxCharacters = 54
    static let plaqueDetailMaxCharacters = 116
    static let plaqueStatusMaxCharacters = 88
    static let ringCopyMaxCharacters = 96
    static let targetXRange = CinematicTimelineSceneFocusPlan.targetXRange
    static let targetYRange = CinematicTimelineSceneFocusPlan.targetYRange
    static let targetZRange = CinematicTimelineSceneFocusPlan.targetZRange

    static let none = CinematicPlanCompassSceneFocusPlan(
        identifier: "plan-compass-focus.none",
        descriptor: nil
    )

    var identifier: String
    var descriptor: Descriptor?

    var isActive: Bool { descriptor != nil }

    struct Descriptor: Equatable {
        var identifier: String
        var planIdentifier: String
        var planCopyIdentifier: String
        var planExportIdentifier: String
        var selectedSectionID: String
        var selectedSectionRouteIdentifier: String
        var selectedSectionRowIdentifier: String
        var selectedSectionContentIdentifier: String
        var selectedSectionCopyIdentifier: String
        var selectedSectionExportIdentifier: String
        var selectedSectionStateIdentifier: String
        var selectedSectionIsEmpty: Bool
        var readinessIdentifier: String?
        var readinessStatusIdentifier: String?
        var readinessWarningStateIdentifier: String?
        var readinessVerifyCommand: String?
        var usesFallbackSection: Bool
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
        var plaqueTitle: String
        var plaqueDetail: String
        var plaqueStatus: String
        var ringCopy: String
        var triadIdentifiers: [String]
        var completedWaypointCount: Int
        var latestCompletedWaypointID: String?
        var latestCompletedWaypointOrdinalLabel: String?
        var latestCompletedWaypointText: String?
        var hiddenCompletedWaypointCount: Int
        var completedWaypointIdentifiers: [String]
        var completedWaypointCopyIdentifiers: [String]
        var completedWaypointExportIdentifiers: [String]
        var waypointHistoryStateIdentifier: String
        var waypointLatestStateIdentifier: String
        var waypointRailIdentifier: String
        var diagnosticsIdentifier: String
        var diagnosticsRowIdentifier: String

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

enum CinematicPlanCompassSceneFocusPlanner {
    static func plan(
        isPlanOverlaySelected: Bool,
        planCompassPlan: CinematicPlanCompassPlan,
        readinessPlan: CinematicPlanCompassReadinessPlan? = nil,
        selectedKind: PlanWorkflowOverview.Kind? = nil
    ) -> CinematicPlanCompassSceneFocusPlan {
        guard isPlanOverlaySelected else { return .none }

        let selectedSection = selectedKind.map { planCompassPlan.section(for: $0) }
            ?? planCompassPlan.sections.first { !$0.isEmpty }
            ?? planCompassPlan.immediate
        let selectedReadiness = selectedSection.kind == .immediate ? readinessPlan : nil
        let selectedRoute = routeIdentifier(for: selectedSection.kind)
        let usesFallbackSection = selectedKind == nil && selectedSection.kind != .immediate
        let treatment = treatment(for: selectedSection)
        let lookTarget = boundedTarget(treatment.lookTarget)
        let plaqueTitle = bounded(
            selectedSection.directionLabel,
            limit: CinematicPlanCompassSceneFocusPlan.plaqueTitleMaxCharacters
        )
        let plaqueDetail = boundedMultiline(
            selectedSection.displayText,
            limit: CinematicPlanCompassSceneFocusPlan.plaqueDetailMaxCharacters
        )
        let plaqueStatus = bounded(
            [
                selectedSection.label,
                selectedSection.selectedStateCopy,
                selectedReadiness?.statusLabel,
                planCompassPlan.completedLabel
            ].compactMap { $0 }.joined(separator: " | "),
            limit: CinematicPlanCompassSceneFocusPlan.plaqueStatusMaxCharacters
        )
        let ringCopy = bounded(
            selectedReadiness?.focusRingCopy
                ?? [
                    selectedSection.directionLabel,
                    selectedSection.stateIdentifier,
                    selectedSection.metadataSummary
                ].joined(separator: " | "),
            limit: CinematicPlanCompassSceneFocusPlan.ringCopyMaxCharacters
        )
        let triadIdentifiers = planCompassPlan.sections.map {
            bounded(
                [
                    "plan-compass-triad",
                    routeIdentifier(for: $0.kind),
                    $0.stateIdentifier,
                    fingerprint($0.contentIdentifier)
                ].joined(separator: "."),
                limit: CinematicPlanCompassSceneFocusPlan.identifierMaxCharacters
            )
        }
        let waypointIdentifiers = planCompassPlan.completedWaypoints.map(\.contentIdentifier)
        let waypointCopyIdentifiers = planCompassPlan.completedWaypoints.map(\.copyIdentifier)
        let waypointExportIdentifiers = planCompassPlan.completedWaypoints.map(\.exportIdentifier)
        let waypointRailIdentifier = bounded(
            [
                "plan-compass-focus",
                selectedRoute,
                "waypoints",
                planCompassPlan.historyStateIdentifier,
                "visible:\(planCompassPlan.completedWaypointCount)",
                "hidden:\(planCompassPlan.hiddenCompletedWaypointCount)",
                "ids:\(fingerprint(waypointIdentifiers.joined(separator: "|")))"
            ].joined(separator: "."),
            limit: CinematicPlanCompassSceneFocusPlan.identifierMaxCharacters
        )
        let diagnosticsIdentifier = bounded(
            [
                "plan-compass-focus.diagnostics",
                "route:\(selectedRoute)",
                "state:\(selectedSection.stateIdentifier)",
                "copy:\(fingerprint(selectedSection.copyIdentifier))",
                "export:\(fingerprint(selectedSection.exportIdentifier))",
                "waypoints:\(planCompassPlan.completedWaypointCount)",
                "hidden:\(planCompassPlan.hiddenCompletedWaypointCount)",
                "history:\(planCompassPlan.historyStateIdentifier)",
                "latest:\(planCompassPlan.latestWaypointStateIdentifier)"
            ].joined(separator: "|"),
            limit: CinematicPlanCompassSceneFocusPlan.identifierMaxCharacters
        )
        let descriptorIdentifier = bounded(
            [
                "plan-compass-focus",
                "plan:\(fingerprint(planCompassPlan.identifier))",
                "route:\(selectedRoute)",
                "state:\(selectedSection.stateIdentifier)",
                "section:\(fingerprint(selectedSection.contentIdentifier))",
                "copy:\(fingerprint(selectedSection.copyIdentifier))",
                "export:\(fingerprint(selectedSection.exportIdentifier))",
                "shot:\(treatment.cameraShot.identifier)",
                "target:\(positionIdentifier(lookTarget))",
                "light:\(treatment.lightFamily.rawValue)",
                "effect:\(treatment.arenaEffect.rawValue)",
                "phase:\(fixed(treatment.phaseLightIntensity))",
                "waypoints:\(fingerprint(planCompassPlan.completedWaypointStripIdentifier))",
                "waypoint-rail:\(fingerprint(waypointRailIdentifier))",
                "readiness:\(fingerprint(selectedReadiness?.identifier ?? "none"))",
                "readiness-status:\(selectedReadiness?.statusIdentifier ?? "none")",
                "plaque:\(fingerprint([plaqueTitle, plaqueDetail, plaqueStatus, ringCopy].joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicPlanCompassSceneFocusPlan.identifierMaxCharacters
        )

        let descriptor = CinematicPlanCompassSceneFocusPlan.Descriptor(
            identifier: descriptorIdentifier,
            planIdentifier: planCompassPlan.identifier,
            planCopyIdentifier: planCompassPlan.copyIdentifier,
            planExportIdentifier: planCompassPlan.exportIdentifier,
            selectedSectionID: selectedSection.id,
            selectedSectionRouteIdentifier: selectedRoute,
            selectedSectionRowIdentifier: selectedSection.rowIdentifier,
            selectedSectionContentIdentifier: selectedSection.contentIdentifier,
            selectedSectionCopyIdentifier: selectedSection.copyIdentifier,
            selectedSectionExportIdentifier: selectedSection.exportIdentifier,
            selectedSectionStateIdentifier: selectedSection.stateIdentifier,
            selectedSectionIsEmpty: selectedSection.isEmpty,
            readinessIdentifier: selectedReadiness?.identifier,
            readinessStatusIdentifier: selectedReadiness?.statusIdentifier,
            readinessWarningStateIdentifier: selectedReadiness?.warningStateIdentifier,
            readinessVerifyCommand: selectedReadiness?.verifyCommand,
            usesFallbackSection: usesFallbackSection,
            cameraShot: treatment.cameraShot,
            lookTarget: lookTarget,
            lightFamily: treatment.lightFamily,
            arenaEffect: treatment.arenaEffect,
            phaseLightIntensity: clamp(
                treatment.phaseLightIntensity,
                to: CinematicRecoveryCuePlan.phaseLightIntensityRange
            ),
            plaqueTitle: plaqueTitle,
            plaqueDetail: plaqueDetail,
            plaqueStatus: plaqueStatus,
            ringCopy: ringCopy,
            triadIdentifiers: triadIdentifiers,
            completedWaypointCount: planCompassPlan.completedWaypointCount,
            latestCompletedWaypointID: planCompassPlan.latestCompletedWaypoint?.contentIdentifier,
            latestCompletedWaypointOrdinalLabel: planCompassPlan.latestCompletedWaypoint?.ordinalLabel,
            latestCompletedWaypointText: planCompassPlan.latestCompletedWaypoint?.displayText,
            hiddenCompletedWaypointCount: planCompassPlan.hiddenCompletedWaypointCount,
            completedWaypointIdentifiers: waypointIdentifiers,
            completedWaypointCopyIdentifiers: waypointCopyIdentifiers,
            completedWaypointExportIdentifiers: waypointExportIdentifiers,
            waypointHistoryStateIdentifier: planCompassPlan.historyStateIdentifier,
            waypointLatestStateIdentifier: planCompassPlan.latestWaypointStateIdentifier,
            waypointRailIdentifier: waypointRailIdentifier,
            diagnosticsIdentifier: diagnosticsIdentifier,
            diagnosticsRowIdentifier: "plan-compass-focus"
        )

        return CinematicPlanCompassSceneFocusPlan(
            identifier: bounded(
                [
                    "plan-compass-focus.active",
                    "descriptor:\(descriptor.identifier)"
                ].joined(separator: "|"),
                limit: CinematicPlanCompassSceneFocusPlan.identifierMaxCharacters
            ),
            descriptor: descriptor
        )
    }

    private struct Treatment {
        var cameraShot: CinematicCameraShot
        var lookTarget: SIMD3<Float>
        var lightFamily: CinematicStageLightFamily
        var arenaEffect: CinematicStageArenaEffect
        var phaseLightIntensity: Float
    }

    private static func treatment(
        for section: CinematicPlanCompassPlan.SectionDescriptor
    ) -> Treatment {
        guard !section.isEmpty else {
            return Treatment(
                cameraShot: .home,
                lookTarget: [0, 1.08, -1.54],
                lightFamily: .lifecycle,
                arenaEffect: .activityPulse,
                phaseLightIntensity: 380
            )
        }

        switch section.kind {
        case .immediate:
            return Treatment(
                cameraShot: .castPrep,
                lookTarget: [1.18, 1.18, -1.62],
                lightFamily: .scan,
                arenaEffect: .seal,
                phaseLightIntensity: 620
            )
        case .midTerm:
            return Treatment(
                cameraShot: .wide,
                lookTarget: [0.0, 1.34, -2.42],
                lightFamily: .insight,
                arenaEffect: .activityPulse,
                phaseLightIntensity: 560
            )
        case .longTerm:
            return Treatment(
                cameraShot: .overhead,
                lookTarget: [-1.32, 1.64, -3.12],
                lightFamily: .verify,
                arenaEffect: .historyChains,
                phaseLightIntensity: 600
            )
        }
    }

    private static func routeIdentifier(for kind: PlanWorkflowOverview.Kind) -> String {
        switch kind {
        case .immediate:
            return "immediate"
        case .midTerm:
            return "mid-term"
        case .longTerm:
            return "long-term"
        }
    }

    private static func boundedTarget(_ target: SIMD3<Float>) -> SIMD3<Float> {
        [
            clamp(target.x, to: CinematicPlanCompassSceneFocusPlan.targetXRange),
            clamp(target.y, to: CinematicPlanCompassSceneFocusPlan.targetYRange),
            clamp(target.z, to: CinematicPlanCompassSceneFocusPlan.targetZRange)
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

    private static func boundedMultiline(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map {
                $0.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension CinematicPlanCompassPlan.SectionDescriptor {
    var selectedStateCopy: String {
        isEmpty ? emptyStateLabel : stateIdentifier
    }
}
