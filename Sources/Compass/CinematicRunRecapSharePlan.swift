import Foundation

struct CinematicRunRecapSharePlan: Equatable, Identifiable {
    static let identifierMaxCharacters = 320
    static let textMaxCharacters = 1_200
    static let eventSummaryLimit = CinematicRunRecapPlan.eventChipLimit
    static let eventSummaryMaxCharacters = 112
    static let visualDescriptorTokenLimit = 20
    static let visualDescriptorTokenMaxCharacters = 72
    static let visualDescriptorLineMaxCharacters = 360

    var id: String { identifier }

    var identifier: String
    var availabilityIdentifier: String
    var availabilityReason: String
    var isAvailable: Bool
    var recapIdentifier: String
    var recapFocusIdentifier: String?
    var endCardIdentifier: String?
    var title: String
    var detail: String
    var status: String
    var commitHighlight: String?
    var eventSummaries: [String]
    var visualDescriptorTokens: [String]
    var text: String

    var eventSummaryCount: Int { eventSummaries.count }
    var visualDescriptorTokenCount: Int { visualDescriptorTokens.count }
    var textLength: Int { text.count }
}

enum CinematicRunRecapSharePlanner {
    static func plan(
        recapPlan: CinematicRunRecapPlan,
        recapFocusDescriptor: CinematicRunRecapSceneFocusPlan.Descriptor? = nil,
        endCardDescriptor: CinematicRunRecapEndCardPlan.Descriptor? = nil
    ) -> CinematicRunRecapSharePlan {
        let title = bounded(
            recapPlan.title,
            limit: CinematicRunRecapPlan.titleLimit
        )
        let detail = bounded(
            recapPlan.detail,
            limit: CinematicRunRecapPlan.detailLimit
        )
        let status = bounded(
            recapPlan.status,
            limit: CinematicRunRecapPlan.statusLimit
        )
        let commitHighlight = recapPlan.newestCommitHighlight.map {
            bounded($0, limit: CinematicRunRecapPlan.commitHighlightLimit)
        }
        let eventSummaries = Array(
            recapPlan.eventChips.prefix(CinematicRunRecapSharePlan.eventSummaryLimit)
        ).map(eventSummary)
        let visualTokens = visualDescriptorTokens(
            recapPlan: recapPlan,
            recapFocusDescriptor: recapFocusDescriptor,
            endCardDescriptor: endCardDescriptor
        )
        let availabilityReason = recapPlan.isAvailable
            ? "available"
            : recapPlan.availabilityIdentifier
        let focusIdentifier = recapFocusDescriptor?.identifier
        let endCardIdentifier = endCardDescriptor?.identifier
        let identifier = bounded(
            [
                "run-recap-share",
                "availability:\(availabilityReason)",
                "recap:\(fingerprint(recapPlan.identifier))",
                "focus:\(fingerprint(focusIdentifier ?? "none"))",
                "end-card:\(fingerprint(endCardIdentifier ?? "none"))",
                "copy:\(fingerprint(copySignature(title, detail, status, commitHighlight, eventSummaries)))",
                "visual:\(fingerprint(visualTokens.joined(separator: ",")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapSharePlan.identifierMaxCharacters
        )
        let text = shareText(
            identifier: identifier,
            availabilityReason: availabilityReason,
            isAvailable: recapPlan.isAvailable,
            recapIdentifier: recapPlan.identifier,
            focusIdentifier: focusIdentifier,
            endCardIdentifier: endCardIdentifier,
            title: title,
            detail: detail,
            status: status,
            commitHighlight: commitHighlight,
            eventSummaries: eventSummaries,
            visualTokens: visualTokens
        )

        return CinematicRunRecapSharePlan(
            identifier: identifier,
            availabilityIdentifier: recapPlan.availabilityIdentifier,
            availabilityReason: availabilityReason,
            isAvailable: recapPlan.isAvailable,
            recapIdentifier: recapPlan.identifier,
            recapFocusIdentifier: focusIdentifier,
            endCardIdentifier: endCardIdentifier,
            title: title,
            detail: detail,
            status: status,
            commitHighlight: commitHighlight,
            eventSummaries: eventSummaries,
            visualDescriptorTokens: visualTokens,
            text: text
        )
    }

    private static func eventSummary(
        _ chip: CinematicRunRecapPlan.EventChip
    ) -> String {
        bounded(
            [
                chip.label,
                chip.detail,
                "source \(chip.sourceIdentifier)",
                "style \(chip.styleIdentifier)"
            ].joined(separator: " | "),
            limit: CinematicRunRecapSharePlan.eventSummaryMaxCharacters
        )
    }

    private static func visualDescriptorTokens(
        recapPlan: CinematicRunRecapPlan,
        recapFocusDescriptor: CinematicRunRecapSceneFocusPlan.Descriptor?,
        endCardDescriptor: CinematicRunRecapEndCardPlan.Descriptor?
    ) -> [String] {
        var tokens: [String] = [
            "style:\(recapPlan.style.rawValue)",
            "color:\(recapPlan.colorIdentifier)",
            "title-source:\(recapPlan.titleSourceIdentifier)",
            "flavor-state:\(recapPlan.flavorStateIdentifier)",
            "terminal:\(recapPlan.statusIdentifier)"
        ]

        if let recapFocusDescriptor {
            tokens.append("focus-shot:\(recapFocusDescriptor.cameraShotIdentifier)")
            tokens.append("focus-light:\(recapFocusDescriptor.lightFamilyIdentifier)")
            tokens.append("focus-effect:\(recapFocusDescriptor.arenaEffectIdentifier)")
        }

        if let endCardDescriptor {
            tokens.append("end-card-anchor:\(endCardDescriptor.anchorIdentifier)")
            tokens.append("end-card-treatment:\(endCardDescriptor.plaqueTreatmentAccentIdentifier)")
            tokens.append("end-card-glyph:\(endCardDescriptor.glyphIdentifier)")
            tokens.append("end-card-light:\(endCardDescriptor.lightFamilyIdentifier)")
            tokens.append("end-card-tint:\(endCardDescriptor.tintFamilyIdentifier)")
            tokens.append("end-card-route:\(endCardDescriptor.plaqueTreatmentRouteIdentifier)")
            tokens.append("end-card-recipe:\(endCardDescriptor.plaqueTreatmentRenderRecipeIdentifier)")
        }

        if let flavorIdentifier = recapPlan.flavorIdentifier {
            tokens.append("flavor-id:\(fingerprint(flavorIdentifier))")
        }
        if let flavorSourceIdentifier = recapPlan.flavorSourceIdentifier {
            tokens.append("flavor-source:\(fingerprint(flavorSourceIdentifier))")
        }

        if let recapFocusDescriptor {
            tokens.append(
                recapFocusDescriptor.usesFallbackTarget
                    ? "focus-target:fallback"
                    : "focus-target:commit"
            )
        }

        return Array(
            tokens
                .map {
                    bounded(
                        $0,
                        limit: CinematicRunRecapSharePlan.visualDescriptorTokenMaxCharacters
                    )
                }
                .prefix(CinematicRunRecapSharePlan.visualDescriptorTokenLimit)
        )
    }

    private static func shareText(
        identifier: String,
        availabilityReason: String,
        isAvailable: Bool,
        recapIdentifier: String,
        focusIdentifier: String?,
        endCardIdentifier: String?,
        title: String,
        detail: String,
        status: String,
        commitHighlight: String?,
        eventSummaries: [String],
        visualTokens: [String]
    ) -> String {
        let availability = isAvailable
            ? availabilityReason
            : "unavailable (\(availabilityReason))"
        let eventCopy = eventSummaries.isEmpty
            ? "none"
            : bounded(
                eventSummaries.joined(separator: "; "),
                limit: CinematicRunRecapSharePlan.visualDescriptorLineMaxCharacters
            )
        let visualCopy = visualTokens.isEmpty
            ? "none"
            : bounded(
                visualTokens.joined(separator: ", "),
                limit: CinematicRunRecapSharePlan.visualDescriptorLineMaxCharacters
            )
        let lines = [
            "Compass Run Recap",
            "Share: \(identifier)",
            "Availability: \(availability)",
            "Recap: \(bounded(recapIdentifier, limit: 180))",
            "Focus: \(bounded(focusIdentifier ?? "none", limit: 180))",
            "End card: \(bounded(endCardIdentifier ?? "none", limit: 180))",
            "Title: \(title)",
            "Status: \(status)",
            "Detail: \(detail)",
            "Commit: \(commitHighlight ?? "none")",
            "Events: \(eventCopy)",
            "Visual: \(visualCopy)"
        ]

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapSharePlan.textMaxCharacters
        )
    }

    private static func copySignature(
        _ title: String,
        _ detail: String,
        _ status: String,
        _ commitHighlight: String?,
        _ eventSummaries: [String]
    ) -> String {
        [
            title,
            detail,
            status,
            commitHighlight ?? "none",
            eventSummaries.joined(separator: ";")
        ].joined(separator: "|")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
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
