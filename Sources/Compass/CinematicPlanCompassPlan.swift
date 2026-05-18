import Foundation

struct CinematicPlanCompassPlan: Equatable {
    static let sectionExcerptMaxCharacters = 96
    static let sectionCopyMaxCharacters = 220
    static let copyTextMaxCharacters = 760
    static let identifierMaxCharacters = 360

    var identifier: String
    var copyIdentifier: String
    var exportIdentifier: String
    var completedCount: Int
    var completedLabel: String
    var immediate: SectionDescriptor
    var midTerm: SectionDescriptor
    var longTerm: SectionDescriptor
    var copyText: String

    var sections: [SectionDescriptor] {
        [immediate, midTerm, longTerm]
    }

    init(state: PlanState) {
        self.init(
            overview: PlanWorkflowOverview(
                state: state,
                excerptLimit: Self.sectionExcerptMaxCharacters
            )
        )
    }

    init(overview: PlanWorkflowOverview) {
        let completedLabel = Self.completedLabel(for: overview.completedCount)
        let sections = overview.sections.map {
            SectionDescriptor(section: $0)
        }
        let copyText = Self.copyText(
            completedLabel: completedLabel,
            sections: sections
        )
        let identifier = Self.bounded(
            [
                "plan-compass",
                "completed:\(overview.completedCount)",
                sections.map(\.contentIdentifier).joined(separator: ";")
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
        let copyIdentifier = Self.bounded(
            "plan-compass.copy|\(Self.fingerprint(copyText))",
            limit: Self.identifierMaxCharacters
        )
        let exportIdentifier = Self.bounded(
            "plan-compass.export|\(Self.fingerprint(identifier))|\(Self.fingerprint(copyText))",
            limit: Self.identifierMaxCharacters
        )

        self.identifier = identifier
        self.copyIdentifier = copyIdentifier
        self.exportIdentifier = exportIdentifier
        completedCount = overview.completedCount
        self.completedLabel = completedLabel
        immediate = sections.first { $0.kind == .immediate } ?? SectionDescriptor.fallback(kind: .immediate)
        midTerm = sections.first { $0.kind == .midTerm } ?? SectionDescriptor.fallback(kind: .midTerm)
        longTerm = sections.first { $0.kind == .longTerm } ?? SectionDescriptor.fallback(kind: .longTerm)
        self.copyText = copyText
    }

    struct SectionDescriptor: Identifiable, Equatable {
        var id: String
        var kind: PlanWorkflowOverview.Kind
        var rowIdentifier: String
        var contentIdentifier: String
        var copyIdentifier: String
        var exportIdentifier: String
        var directionLabel: String
        var title: String
        var label: String
        var systemImage: String
        var stateIdentifier: String
        var isEmpty: Bool
        var emptyStateLabel: String
        var displayText: String
        var bodyExcerpt: String?
        var verifyCommand: String?
        var verifyTimeoutLabel: String?
        var estimatedDifficultyLabel: String?
        var completedCount: Int
        var metadataSummary: String
        var copyText: String
        var diagnosticsDetail: String

        init(section: PlanWorkflowOverview.Section) {
            let slug = section.kind.planCompassSlug
            let directionLabel = section.kind.planCompassDirectionLabel
            let stateIdentifier = section.isEmpty ? "empty" : "active"
            let displayText = CinematicPlanCompassPlan.boundedMultiline(
                section.excerpt ?? section.emptyMessage,
                limit: CinematicPlanCompassPlan.sectionExcerptMaxCharacters
            )
            let emptyStateLabel = section.kind.planCompassEmptyStateLabel
            let metadata = Self.metadataTokens(section: section)
            let metadataSummary = metadata.isEmpty ? "metadata none" : metadata.joined(separator: " | ")
            let contentIdentifier = CinematicPlanCompassPlan.bounded(
                [
                    "plan-compass.section.\(slug)",
                    "state:\(stateIdentifier)",
                    "body:\(CinematicPlanCompassPlan.fingerprint(section.body))",
                    "text:\(CinematicPlanCompassPlan.fingerprint(displayText))",
                    "verify:\(CinematicPlanCompassPlan.fingerprint(section.verifyCommand ?? "none"))",
                    "timeout:\(CinematicPlanCompassPlan.fingerprint(section.verifyTimeoutLabel ?? "none"))",
                    "difficulty:\(section.estimatedDifficulty?.rawValue ?? "none")",
                    "completed:\(section.completedCount)"
                ].joined(separator: "|"),
                limit: CinematicPlanCompassPlan.identifierMaxCharacters
            )
            let copyText = CinematicPlanCompassPlan.boundedMultiline(
                [
                    "\(directionLabel): \(displayText)",
                    metadataSummary
                ].joined(separator: "\n"),
                limit: CinematicPlanCompassPlan.sectionCopyMaxCharacters
            )
            let copyIdentifier = CinematicPlanCompassPlan.bounded(
                "plan-compass.copy.\(slug)|\(CinematicPlanCompassPlan.fingerprint(copyText))",
                limit: CinematicPlanCompassPlan.identifierMaxCharacters
            )
            let exportIdentifier = CinematicPlanCompassPlan.bounded(
                "plan-compass.export.\(slug)|\(CinematicPlanCompassPlan.fingerprint(contentIdentifier))",
                limit: CinematicPlanCompassPlan.identifierMaxCharacters
            )
            let diagnosticsDetail = CinematicPlanCompassPlan.boundedMultiline(
                [
                    stateIdentifier,
                    "copy \(copyIdentifier)",
                    "export \(exportIdentifier)",
                    metadataSummary,
                    "text \(displayText)"
                ].joined(separator: " | "),
                limit: 512
            )

            id = "plan-compass-\(slug)"
            kind = section.kind
            rowIdentifier = "plan-compass-\(slug)"
            self.contentIdentifier = contentIdentifier
            self.copyIdentifier = copyIdentifier
            self.exportIdentifier = exportIdentifier
            self.directionLabel = directionLabel
            title = section.title
            label = section.label
            systemImage = section.systemImage
            self.stateIdentifier = stateIdentifier
            isEmpty = section.isEmpty
            self.emptyStateLabel = emptyStateLabel
            self.displayText = displayText
            bodyExcerpt = section.excerpt
            verifyCommand = section.verifyCommand
            verifyTimeoutLabel = section.verifyTimeoutLabel
            estimatedDifficultyLabel = section.estimatedDifficultyLabel
            completedCount = section.completedCount
            self.metadataSummary = metadataSummary
            self.copyText = copyText
            self.diagnosticsDetail = diagnosticsDetail
        }

        static func fallback(kind: PlanWorkflowOverview.Kind) -> SectionDescriptor {
            SectionDescriptor(
                section: PlanWorkflowOverview.Section(
                    kind: kind,
                    title: kind.planCompassDirectionLabel,
                    label: kind.planCompassFallbackLabel,
                    systemImage: kind.planCompassFallbackSystemImage,
                    rawBody: "",
                    emptyMessage: kind.planCompassFallbackMessage,
                    completedCount: 0,
                    excerptLimit: CinematicPlanCompassPlan.sectionExcerptMaxCharacters
                )
            )
        }

        private static func metadataTokens(section: PlanWorkflowOverview.Section) -> [String] {
            [
                "completed \(section.completedCount)",
                section.estimatedDifficultyLabel.map { "difficulty \($0.lowercased())" },
                section.verifyTimeoutLabel.map { "verify \($0)" },
                section.verifyCommand.map {
                    "command \(CinematicPlanCompassPlan.bounded($0, limit: 72))"
                }
            ].compactMap { $0 }
        }
    }

    private static func copyText(
        completedLabel: String,
        sections: [SectionDescriptor]
    ) -> String {
        let lines = [
            "Plan compass",
            "Completed: \(completedLabel)"
        ] + sections.map(\.copyText)

        return boundedMultiline(
            lines.joined(separator: "\n"),
            limit: copyTextMaxCharacters
        )
    }

    private static func completedLabel(for count: Int) -> String {
        switch count {
        case 0:
            return "No completed iterations"
        case 1:
            return "1 completed iteration"
        default:
            return "\(count) completed iterations"
        }
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "" }
        guard limit > 0, normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }

        let prefix = normalized
            .prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
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
        guard !normalized.isEmpty else { return "" }
        guard limit > 0, normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }

        let prefix = normalized
            .prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
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

private extension PlanWorkflowOverview.Kind {
    var planCompassSlug: String {
        switch self {
        case .immediate:
            return "immediate"
        case .midTerm:
            return "mid-term"
        case .longTerm:
            return "long-term"
        }
    }

    var planCompassDirectionLabel: String {
        switch self {
        case .immediate:
            return "Immediate direction"
        case .midTerm:
            return "Mid-term direction"
        case .longTerm:
            return "Long-term direction"
        }
    }

    var planCompassEmptyStateLabel: String {
        switch self {
        case .immediate:
            return "No immediate direction"
        case .midTerm:
            return "No mid-term direction"
        case .longTerm:
            return "No long-term direction"
        }
    }

    var planCompassFallbackLabel: String {
        switch self {
        case .immediate:
            return "Current"
        case .midTerm:
            return "Next Up"
        case .longTerm:
            return "Destination"
        }
    }

    var planCompassFallbackMessage: String {
        switch self {
        case .immediate:
            return "No immediate plan. The factory is ready for the next scoped implementation."
        case .midTerm:
            return "No mid-term queue. Future planning has no staged direction yet."
        case .longTerm:
            return "No long-term arc. Add the larger product direction when it becomes clear."
        }
    }

    var planCompassFallbackSystemImage: String {
        switch self {
        case .immediate:
            return "target"
        case .midTerm:
            return "point.3.connected.trianglepath.dotted"
        case .longTerm:
            return "mountain.2.fill"
        }
    }
}
