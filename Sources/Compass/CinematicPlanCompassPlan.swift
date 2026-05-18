import Foundation

struct CinematicPlanCompassPlan: Equatable {
    static let sectionExcerptMaxCharacters = 96
    static let sectionCopyMaxCharacters = 220
    static let completedWaypointLimit = 4
    static let completedWaypointExcerptMaxCharacters = 58
    static let completedWaypointCopyMaxCharacters = 112
    static let completedWaypointStripCopyMaxCharacters = 260
    static let copyTextMaxCharacters = 860
    static let identifierMaxCharacters = 360

    var identifier: String
    var copyIdentifier: String
    var exportIdentifier: String
    var completedCount: Int
    var completedLabel: String
    var completedWaypoints: [CompletedWaypointDescriptor]
    var completedWaypointCount: Int
    var latestCompletedWaypoint: CompletedWaypointDescriptor?
    var hiddenCompletedWaypointCount: Int
    var completedWaypointStripIdentifier: String
    var completedWaypointCopyText: String
    var latestWaypointStateIdentifier: String
    var historyStateIdentifier: String
    var immediate: SectionDescriptor
    var midTerm: SectionDescriptor
    var longTerm: SectionDescriptor
    var copyText: String

    var sections: [SectionDescriptor] {
        [immediate, midTerm, longTerm]
    }

    func section(for kind: PlanWorkflowOverview.Kind) -> SectionDescriptor {
        switch kind {
        case .immediate:
            return immediate
        case .midTerm:
            return midTerm
        case .longTerm:
            return longTerm
        }
    }

    init(state: PlanState) {
        self.init(
            overview: PlanWorkflowOverview(
                state: state,
                excerptLimit: Self.sectionExcerptMaxCharacters
            ),
            completed: state.completed
        )
    }

    init(overview: PlanWorkflowOverview) {
        self.init(overview: overview, completed: [])
    }

    private init(overview: PlanWorkflowOverview, completed: [String]) {
        let completedLabel = Self.completedLabel(for: overview.completedCount)
        let sections = overview.sections.map {
            SectionDescriptor(section: $0)
        }
        let completedHistory = Self.completedWaypointHistory(
            completed: completed,
            completedCount: overview.completedCount
        )
        let copyText = Self.copyText(
            completedLabel: completedLabel,
            completedWaypointCopyText: completedHistory.copyText,
            sections: sections
        )
        let identifier = Self.bounded(
            [
                "plan-compass",
                "completed:\(overview.completedCount)",
                "history:\(completedHistory.stripIdentifier)",
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
        completedWaypoints = completedHistory.waypoints
        completedWaypointCount = completedHistory.waypoints.count
        latestCompletedWaypoint = completedHistory.latestWaypoint
        hiddenCompletedWaypointCount = completedHistory.hiddenCount
        completedWaypointStripIdentifier = completedHistory.stripIdentifier
        completedWaypointCopyText = completedHistory.copyText
        latestWaypointStateIdentifier = completedHistory.latestStateIdentifier
        historyStateIdentifier = completedHistory.historyStateIdentifier
        immediate = sections.first { $0.kind == .immediate } ?? SectionDescriptor.fallback(kind: .immediate)
        midTerm = sections.first { $0.kind == .midTerm } ?? SectionDescriptor.fallback(kind: .midTerm)
        longTerm = sections.first { $0.kind == .longTerm } ?? SectionDescriptor.fallback(kind: .longTerm)
        self.copyText = copyText
    }

    struct CompletedWaypointDescriptor: Identifiable, Equatable {
        var id: String
        var ordinal: Int
        var ordinalLabel: String
        var stateIdentifier: String
        var displayText: String
        var contentIdentifier: String
        var copyIdentifier: String
        var exportIdentifier: String
        var copyText: String
        var diagnosticsDetail: String

        init(item: String, ordinal: Int, isLatest: Bool) {
            let stateIdentifier = isLatest ? "latest" : "history"
            let ordinalLabel = "#\(ordinal)"
            let displayText = CinematicPlanCompassPlan.boundedMultiline(
                item,
                limit: CinematicPlanCompassPlan.completedWaypointExcerptMaxCharacters
            )
            let contentIdentifier = CinematicPlanCompassPlan.bounded(
                [
                    "plan-compass.waypoint",
                    "ordinal:\(ordinal)",
                    "state:\(stateIdentifier)",
                    "text:\(CinematicPlanCompassPlan.fingerprint(displayText))"
                ].joined(separator: "|"),
                limit: CinematicPlanCompassPlan.identifierMaxCharacters
            )
            let copyText = CinematicPlanCompassPlan.boundedMultiline(
                "\(ordinalLabel) \(stateIdentifier): \(displayText)",
                limit: CinematicPlanCompassPlan.completedWaypointCopyMaxCharacters
            )
            let copyIdentifier = CinematicPlanCompassPlan.bounded(
                "plan-compass.copy.waypoint.\(ordinal)|\(CinematicPlanCompassPlan.fingerprint(copyText))",
                limit: CinematicPlanCompassPlan.identifierMaxCharacters
            )
            let exportIdentifier = CinematicPlanCompassPlan.bounded(
                "plan-compass.export.waypoint.\(ordinal)|\(CinematicPlanCompassPlan.fingerprint(contentIdentifier))",
                limit: CinematicPlanCompassPlan.identifierMaxCharacters
            )
            let diagnosticsDetail = CinematicPlanCompassPlan.boundedMultiline(
                [
                    ordinalLabel,
                    stateIdentifier,
                    "copy \(copyIdentifier)",
                    "export \(exportIdentifier)",
                    "text \(displayText)"
                ].joined(separator: " | "),
                limit: 360
            )

            id = "plan-compass-waypoint-\(ordinal)"
            self.ordinal = ordinal
            self.ordinalLabel = ordinalLabel
            self.stateIdentifier = stateIdentifier
            self.displayText = displayText
            self.contentIdentifier = contentIdentifier
            self.copyIdentifier = copyIdentifier
            self.exportIdentifier = exportIdentifier
            self.copyText = copyText
            self.diagnosticsDetail = diagnosticsDetail
        }
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
        completedWaypointCopyText: String,
        sections: [SectionDescriptor]
    ) -> String {
        let lines = [
            "Plan compass",
            "Completed: \(completedLabel)",
            completedWaypointCopyText
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

    private struct CompletedWaypointHistory {
        var waypoints: [CompletedWaypointDescriptor]
        var hiddenCount: Int
        var stripIdentifier: String
        var copyText: String
        var latestStateIdentifier: String
        var historyStateIdentifier: String

        var latestWaypoint: CompletedWaypointDescriptor? {
            waypoints.last { $0.stateIdentifier == "latest" }
        }
    }

    private static func completedWaypointHistory(
        completed: [String],
        completedCount: Int
    ) -> CompletedWaypointHistory {
        let sanitized = completed.map {
            boundedMultiline($0, limit: completedWaypointExcerptMaxCharacters)
        }
        let effectiveCount = max(completedCount, sanitized.count)
        let visibleStart = max(0, sanitized.count - completedWaypointLimit)
        let visibleItems = Array(sanitized.enumerated().dropFirst(visibleStart))
        let waypoints = visibleItems.map { index, item in
            CompletedWaypointDescriptor(
                item: item,
                ordinal: index + 1,
                isLatest: index == sanitized.count - 1
            )
        }
        let hiddenCount = max(0, effectiveCount - waypoints.count)
        let latestStateIdentifier = waypoints.isEmpty ? "none" : "latest"
        let historyStateIdentifier: String
        if waypoints.isEmpty {
            historyStateIdentifier = "empty"
        } else if hiddenCount > 0 {
            historyStateIdentifier = "truncated"
        } else {
            historyStateIdentifier = "complete"
        }
        let waypointIdentifierSummary = waypoints.map(\.contentIdentifier).joined(separator: ";")
        let stripIdentifier = bounded(
            [
                "plan-compass.history",
                "count:\(effectiveCount)",
                "visible:\(waypoints.count)",
                "hidden:\(hiddenCount)",
                "latest:\(latestStateIdentifier)",
                "state:\(historyStateIdentifier)",
                "items:\(fingerprint(waypointIdentifierSummary.isEmpty ? "none" : waypointIdentifierSummary))"
            ].joined(separator: "|"),
            limit: identifierMaxCharacters
        )
        let copyLines: [String]
        if waypoints.isEmpty {
            copyLines = [
                "History state: empty | latest none | hidden 0",
                "Completed history: none"
            ]
        } else {
            let latestWaypoint = waypoints.last { $0.stateIdentifier == "latest" }
            copyLines = [
                "History state: \(historyStateIdentifier) | latest \(latestStateIdentifier) | hidden \(hiddenCount)",
                latestWaypoint.map { "Latest waypoint: \($0.copyText)" },
                "Completed history: \(waypoints.map(\.copyText).joined(separator: " / "))"
            ].compactMap { $0 }
        }
        let copyText = boundedMultiline(
            copyLines.joined(separator: "\n"),
            limit: completedWaypointStripCopyMaxCharacters
        )

        return CompletedWaypointHistory(
            waypoints: waypoints,
            hiddenCount: hiddenCount,
            stripIdentifier: stripIdentifier,
            copyText: copyText,
            latestStateIdentifier: latestStateIdentifier,
            historyStateIdentifier: historyStateIdentifier
        )
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

struct CinematicPlanCompassCommandPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = 320
    static let commandLimit = 6
    static let labelMaxCharacters = 34
    static let helpMaxCharacters = 180
    static let shortcutHintMaxCharacters = 20

    var id: String { identifier }

    var identifier: String
    var sourcePlanIdentifier: String
    var sourcePlanCopyIdentifier: String
    var sourcePlanExportIdentifier: String
    var selectedKind: PlanWorkflowOverview.Kind
    var selectedRouteIdentifier: String
    var selectedSectionID: String
    var selectedSectionRowIdentifier: String
    var selectedSectionContentIdentifier: String
    var selectedSectionCopyIdentifier: String
    var selectedSectionExportIdentifier: String
    var selectedSectionStateIdentifier: String
    var selectedSectionIsEmpty: Bool
    var commands: [Command]
    var appLevelShortcutIdentifiers: [String]
    var appLevelShortcutCollisionIdentifiers: [String]
    var recapCommandShortcutIdentifiers: [String]
    var recapCommandShortcutCollisionIdentifiers: [String]

    var commandCount: Int { commands.count }
    var enabledCommandCount: Int { commands.filter(\.isEnabled).count }
    var disabledCommandCount: Int { commands.filter { !$0.isEnabled }.count }
    var appLevelShortcutCollisionStateIdentifier: String {
        appLevelShortcutCollisionIdentifiers.isEmpty ? "clear" : "collision"
    }
    var recapCommandShortcutCollisionStateIdentifier: String {
        recapCommandShortcutCollisionIdentifiers.isEmpty ? "clear" : "collision"
    }

    func commands(in section: Section) -> [Command] {
        commands.filter { $0.section == section }
    }

    func command(for actionKind: ActionKind) -> Command? {
        commands.first { $0.actionKind == actionKind }
    }

    enum Section: String, CaseIterable, Equatable, Identifiable {
        case overlay
        case focus
        case copy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overlay:
                return "Overlay"
            case .focus:
                return "Focus"
            case .copy:
                return "Copy"
            }
        }
    }

    enum ActionKind: String, CaseIterable, Equatable {
        case showPlanOverlay
        case focusImmediateRoute
        case focusMidTermRoute
        case focusLongTermRoute
        case copyFullPlanCompass
        case copySelectedRoute
    }

    struct Command: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var section: Section
        var label: String
        var help: String
        var isEnabled: Bool
        var actionKind: ActionKind
        var shortcut: Shortcut
    }

    struct Shortcut: Equatable, Hashable {
        var key: Key
        var modifiers: [Modifier]

        var identifier: String {
            let modifierText = modifiers.map(\.rawValue).joined(separator: "+")
            return "\(modifierText):\(key.rawValue)"
        }

        var displayText: String {
            let modifierText = modifiers.map(\.displayText)
            return (modifierText + [key.displayText]).joined(separator: "-")
        }

        enum Key: String, Equatable, Hashable {
            case leftBracket = "["
            case rightBracket = "]"
            case one = "1"
            case two = "2"
            case three = "3"
            case b = "b"
            case c = "c"
            case d = "d"
            case e = "e"
            case h = "h"
            case m = "m"
            case o = "o"
            case p = "p"
            case r = "r"
            case returnKey = "return"
            case t = "t"

            var displayText: String {
                switch self {
                case .leftBracket, .rightBracket:
                    return rawValue
                case .returnKey:
                    return "Return"
                default:
                    return rawValue.uppercased()
                }
            }
        }

        enum Modifier: String, Equatable, Hashable {
            case command
            case control
            case option
            case shift

            var displayText: String {
                switch self {
                case .command:
                    return "Cmd"
                case .control:
                    return "Ctrl"
                case .option:
                    return "Opt"
                case .shift:
                    return "Shift"
                }
            }
        }
    }
}

struct CinematicPlanCompassActionSurfaceDescriptor: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicPlanCompassCommandPlan.identifierMaxCharacters
    static let actionLimit = CinematicPlanCompassCommandPlan.commandLimit
    static let labelMaxCharacters = CinematicPlanCompassCommandPlan.labelMaxCharacters
    static let helpMaxCharacters = CinematicPlanCompassCommandPlan.helpMaxCharacters
    static let systemImageMaxCharacters = 64
    static let shortcutHintMaxCharacters = CinematicPlanCompassCommandPlan.shortcutHintMaxCharacters

    var id: String { identifier }

    var identifier: String
    var sourceCommandPlanIdentifier: String
    var sourcePlanIdentifier: String
    var selectedRouteIdentifier: String
    var actions: [Action]

    var actionCount: Int { actions.count }
    var enabledActionCount: Int { actions.filter(\.isEnabled).count }
    var disabledActionCount: Int { actions.filter { !$0.isEnabled }.count }

    func actions(in section: CinematicPlanCompassCommandPlan.Section) -> [Action] {
        actions.filter { $0.section == section }
    }

    func action(
        for sourceActionKind: CinematicPlanCompassCommandPlan.ActionKind
    ) -> Action? {
        actions.first { $0.sourceActionKind == sourceActionKind }
    }

    struct Action: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var sourceCommandIdentifier: String
        var section: CinematicPlanCompassCommandPlan.Section
        var label: String
        var systemImage: String
        var help: String
        var shortcutHint: String
        var isEnabled: Bool
        var isSelectedRoute: Bool
        var selectedRouteStateIdentifier: String
        var sourceActionKind: CinematicPlanCompassCommandPlan.ActionKind
    }
}

enum CinematicPlanCompassActionSurfacePlanner {
    static func descriptor(
        commandPlan: CinematicPlanCompassCommandPlan
    ) -> CinematicPlanCompassActionSurfaceDescriptor {
        let actions = Array(commandPlan.commands.prefix(CinematicPlanCompassActionSurfaceDescriptor.actionLimit))
            .map { action(command: $0, commandPlan: commandPlan) }
        let identifier = bounded(
            [
                "plan-compass-action-surface",
                "actions:\(actions.count)",
                "enabled:\(actions.filter(\.isEnabled).count)",
                "selected:\(commandPlan.selectedRouteIdentifier)",
                "command-plan:\(fingerprint(commandPlan.identifier))",
                "source-plan:\(fingerprint(commandPlan.sourcePlanIdentifier))",
                "content:\(fingerprint(actions.map(\.identifier).joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicPlanCompassActionSurfaceDescriptor.identifierMaxCharacters
        )

        return CinematicPlanCompassActionSurfaceDescriptor(
            identifier: identifier,
            sourceCommandPlanIdentifier: commandPlan.identifier,
            sourcePlanIdentifier: commandPlan.sourcePlanIdentifier,
            selectedRouteIdentifier: commandPlan.selectedRouteIdentifier,
            actions: actions
        )
    }

    private typealias Descriptor = CinematicPlanCompassActionSurfaceDescriptor
    private typealias Action = CinematicPlanCompassActionSurfaceDescriptor.Action
    private typealias Command = CinematicPlanCompassCommandPlan.Command
    private typealias ActionKind = CinematicPlanCompassCommandPlan.ActionKind

    private static func action(
        command: Command,
        commandPlan: CinematicPlanCompassCommandPlan
    ) -> Action {
        let selectedState = selectedRouteStateIdentifier(
            actionKind: command.actionKind,
            selectedKind: commandPlan.selectedKind,
            selectedRouteIdentifier: commandPlan.selectedRouteIdentifier
        )
        let isSelectedRoute = selectedState == "selected-route"
        let identifier = bounded(
            [
                "plan-compass-action",
                "kind:\(command.actionKind.rawValue)",
                "command:\(fingerprint(command.identifier))",
                "enabled:\(command.isEnabled)",
                "selected:\(selectedState)",
                "shortcut:\(command.shortcut.identifier)"
            ].joined(separator: "|"),
            limit: Descriptor.identifierMaxCharacters
        )

        return Action(
            identifier: identifier,
            sourceCommandIdentifier: command.identifier,
            section: command.section,
            label: bounded(command.label, limit: Descriptor.labelMaxCharacters),
            systemImage: bounded(systemImage(for: command.actionKind), limit: Descriptor.systemImageMaxCharacters),
            help: bounded(command.help, limit: Descriptor.helpMaxCharacters),
            shortcutHint: bounded(command.shortcut.displayText, limit: Descriptor.shortcutHintMaxCharacters),
            isEnabled: command.isEnabled,
            isSelectedRoute: isSelectedRoute,
            selectedRouteStateIdentifier: selectedState,
            sourceActionKind: command.actionKind
        )
    }

    private static func systemImage(for actionKind: ActionKind) -> String {
        switch actionKind {
        case .showPlanOverlay:
            return "safari"
        case .focusImmediateRoute:
            return "target"
        case .focusMidTermRoute:
            return "point.3.connected.trianglepath.dotted"
        case .focusLongTermRoute:
            return "mountain.2.fill"
        case .copyFullPlanCompass:
            return "doc.on.doc"
        case .copySelectedRoute:
            return "clipboard"
        }
    }

    private static func selectedRouteStateIdentifier(
        actionKind: ActionKind,
        selectedKind: PlanWorkflowOverview.Kind,
        selectedRouteIdentifier: String
    ) -> String {
        switch actionKind {
        case .focusImmediateRoute:
            return selectedKind == .immediate ? "selected-route" : "available-route"
        case .focusMidTermRoute:
            return selectedKind == .midTerm ? "selected-route" : "available-route"
        case .focusLongTermRoute:
            return selectedKind == .longTerm ? "selected-route" : "available-route"
        case .copySelectedRoute:
            return "selected-\(selectedRouteIdentifier)"
        case .showPlanOverlay, .copyFullPlanCompass:
            return "available"
        }
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

enum CinematicPlanCompassCommandPlanner {
    static func plan(
        planCompassPlan: CinematicPlanCompassPlan,
        selectedKind: PlanWorkflowOverview.Kind
    ) -> CinematicPlanCompassCommandPlan {
        let selectedSection = planCompassPlan.section(for: selectedKind)
        let commands = CinematicPlanCompassCommandPlan.ActionKind.allCases.compactMap { actionKind -> Command? in
            guard let shortcut = shortcut(for: actionKind) else { return nil }
            return command(
                actionKind: actionKind,
                planCompassPlan: planCompassPlan,
                selectedSection: selectedSection,
                shortcut: shortcut
            )
        }.prefix(CinematicPlanCompassCommandPlan.commandLimit)
        let boundedCommands = Array(commands)
        let shortcutIdentifiers = boundedCommands.map(\.shortcut.identifier)
        let appLevelShortcutIdentifiers = appLevelShortcuts().map(\.identifier)
        let appLevelShortcutIdentifierSet = Set(appLevelShortcutIdentifiers)
        let appLevelShortcutCollisionIdentifiers = shortcutIdentifiers.filter(appLevelShortcutIdentifierSet.contains)
        let recapCommandShortcutIdentifiers = recapCommandShortcuts().map(\.identifier)
        let recapCommandShortcutIdentifierSet = Set(recapCommandShortcutIdentifiers)
        let recapCommandShortcutCollisionIdentifiers = shortcutIdentifiers.filter(
            recapCommandShortcutIdentifierSet.contains
        )
        let identifier = bounded(
            [
                "plan-compass-commands",
                "commands:\(boundedCommands.count)",
                "selected:\(selectedKind.planCompassCommandRouteIdentifier)",
                "source:\(fingerprint(planCompassPlan.identifier))",
                "content:\(fingerprint(boundedCommands.map(\.identifier).joined(separator: "|")))",
                "app-collisions:\(fingerprint(appLevelShortcutCollisionIdentifiers.joined(separator: "|")))",
                "recap-collisions:\(fingerprint(recapCommandShortcutCollisionIdentifiers.joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CommandPlan.identifierMaxCharacters
        )

        return CinematicPlanCompassCommandPlan(
            identifier: identifier,
            sourcePlanIdentifier: planCompassPlan.identifier,
            sourcePlanCopyIdentifier: planCompassPlan.copyIdentifier,
            sourcePlanExportIdentifier: planCompassPlan.exportIdentifier,
            selectedKind: selectedKind,
            selectedRouteIdentifier: selectedKind.planCompassCommandRouteIdentifier,
            selectedSectionID: selectedSection.id,
            selectedSectionRowIdentifier: selectedSection.rowIdentifier,
            selectedSectionContentIdentifier: selectedSection.contentIdentifier,
            selectedSectionCopyIdentifier: selectedSection.copyIdentifier,
            selectedSectionExportIdentifier: selectedSection.exportIdentifier,
            selectedSectionStateIdentifier: selectedSection.stateIdentifier,
            selectedSectionIsEmpty: selectedSection.isEmpty,
            commands: boundedCommands,
            appLevelShortcutIdentifiers: appLevelShortcutIdentifiers,
            appLevelShortcutCollisionIdentifiers: appLevelShortcutCollisionIdentifiers,
            recapCommandShortcutIdentifiers: recapCommandShortcutIdentifiers,
            recapCommandShortcutCollisionIdentifiers: recapCommandShortcutCollisionIdentifiers
        )
    }

    static func shortcutHint(
        for actionKind: CinematicPlanCompassCommandPlan.ActionKind
    ) -> String? {
        shortcut(for: actionKind)?.displayText
    }

    static func shortcut(
        for actionKind: CinematicPlanCompassCommandPlan.ActionKind
    ) -> CinematicPlanCompassCommandPlan.Shortcut? {
        switch actionKind {
        case .showPlanOverlay:
            return Shortcut(key: .p, modifiers: [.command, .control])
        case .focusImmediateRoute:
            return Shortcut(key: .one, modifiers: [.command, .control])
        case .focusMidTermRoute:
            return Shortcut(key: .two, modifiers: [.command, .control])
        case .focusLongTermRoute:
            return Shortcut(key: .three, modifiers: [.command, .control])
        case .copyFullPlanCompass:
            return Shortcut(key: .c, modifiers: [.command, .control])
        case .copySelectedRoute:
            return Shortcut(key: .c, modifiers: [.command, .control, .shift])
        }
    }

    static func appLevelShortcuts() -> [CinematicPlanCompassCommandPlan.Shortcut] {
        [
            Shortcut(key: .o, modifiers: [.command]),
            Shortcut(key: .r, modifiers: [.command]),
            Shortcut(key: .returnKey, modifiers: [.command])
        ]
    }

    static func recapCommandShortcuts() -> [CinematicPlanCompassCommandPlan.Shortcut] {
        recapActionKinds.compactMap { actionKind in
            guard let shortcut = CinematicRunRecapShareArtifactCommandPlanner.shortcut(for: actionKind),
                  let key = Shortcut.Key(recapShortcutKey: shortcut.key),
                  shortcut.modifiers.allSatisfy({ Shortcut.Modifier(recapModifier: $0) != nil })
            else {
                return nil
            }
            let modifiers = shortcut.modifiers.compactMap(Shortcut.Modifier.init(recapModifier:))
            return Shortcut(key: key, modifiers: modifiers)
        }
    }

    private typealias CommandPlan = CinematicPlanCompassCommandPlan
    private typealias Command = CinematicPlanCompassCommandPlan.Command
    private typealias Shortcut = CinematicPlanCompassCommandPlan.Shortcut
    private typealias ActionKind = CinematicPlanCompassCommandPlan.ActionKind

    private static let recapActionKinds: [CinematicRunRecapShareArtifactActionMenuPlan.ActionKind] = [
        .navigatePrevious,
        .navigateNext,
        .revealSelected,
        .copySelectedExport,
        .copyFilteredExport,
        .copyLibraryExport,
        .copyRollupExport,
        .copyComparisonExport,
        .copyPinnedExport,
        .copyTourExport,
        .toggleComparisonTargetMode,
        .toggleSelectedPin,
        .toggleTourHold,
        .toggleSelectedTourHold,
        .promoteTourHold
    ]

    private static func command(
        actionKind: ActionKind,
        planCompassPlan: CinematicPlanCompassPlan,
        selectedSection: CinematicPlanCompassPlan.SectionDescriptor,
        shortcut: Shortcut
    ) -> Command {
        let descriptor = commandDescriptor(
            actionKind: actionKind,
            planCompassPlan: planCompassPlan,
            selectedSection: selectedSection
        )
        let identifier = bounded(
            [
                "plan-compass-command",
                "kind:\(actionKind.rawValue)",
                "section:\(descriptor.section.rawValue)",
                "enabled:\(descriptor.isEnabled)",
                "shortcut:\(shortcut.identifier)",
                "state:\(fingerprint(descriptor.stateIdentifier))"
            ].joined(separator: "|"),
            limit: CommandPlan.identifierMaxCharacters
        )

        return Command(
            identifier: identifier,
            section: descriptor.section,
            label: bounded(descriptor.label, limit: CommandPlan.labelMaxCharacters),
            help: bounded(descriptor.help, limit: CommandPlan.helpMaxCharacters),
            isEnabled: descriptor.isEnabled,
            actionKind: actionKind,
            shortcut: shortcut
        )
    }

    private struct CommandDescriptor {
        var section: CommandPlan.Section
        var label: String
        var help: String
        var isEnabled: Bool
        var stateIdentifier: String
    }

    private static func commandDescriptor(
        actionKind: ActionKind,
        planCompassPlan: CinematicPlanCompassPlan,
        selectedSection: CinematicPlanCompassPlan.SectionDescriptor
    ) -> CommandDescriptor {
        switch actionKind {
        case .showPlanOverlay:
            return CommandDescriptor(
                section: .overlay,
                label: "Show Plan Compass",
                help: "Show the Plan Compass overlay without changing the selected route.",
                isEnabled: true,
                stateIdentifier: planCompassPlan.exportIdentifier
            )
        case .focusImmediateRoute:
            return focusDescriptor(
                route: .immediate,
                targetSection: planCompassPlan.immediate,
                selectedSection: selectedSection
            )
        case .focusMidTermRoute:
            return focusDescriptor(
                route: .midTerm,
                targetSection: planCompassPlan.midTerm,
                selectedSection: selectedSection
            )
        case .focusLongTermRoute:
            return focusDescriptor(
                route: .longTerm,
                targetSection: planCompassPlan.longTerm,
                selectedSection: selectedSection
            )
        case .copyFullPlanCompass:
            return CommandDescriptor(
                section: .copy,
                label: "Copy Plan Compass",
                help: "Copy the full Plan Compass text \(planCompassPlan.copyIdentifier).",
                isEnabled: !planCompassPlan.copyText.isEmpty,
                stateIdentifier: planCompassPlan.copyIdentifier
            )
        case .copySelectedRoute:
            return CommandDescriptor(
                section: .copy,
                label: "Copy Selected Route",
                help: "Copy \(selectedSection.directionLabel.lowercased()) text \(selectedSection.copyIdentifier).",
                isEnabled: !selectedSection.copyText.isEmpty,
                stateIdentifier: selectedSection.copyIdentifier
            )
        }
    }

    private static func focusDescriptor(
        route: PlanWorkflowOverview.Kind,
        targetSection: CinematicPlanCompassPlan.SectionDescriptor,
        selectedSection: CinematicPlanCompassPlan.SectionDescriptor
    ) -> CommandDescriptor {
        CommandDescriptor(
            section: .focus,
            label: "Focus \(route.planCompassCommandTitle)",
            help: "Show the Plan Compass overlay and focus \(route.planCompassCommandHelpLabel).",
            isEnabled: true,
            stateIdentifier: [
                targetSection.contentIdentifier,
                selectedSection.kind == route ? "selected" : "available"
            ].joined(separator: "|")
        )
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

private extension CinematicPlanCompassCommandPlan.Shortcut.Key {
    init?(recapShortcutKey: CinematicRunRecapShareArtifactCommandPlan.Shortcut.Key) {
        switch recapShortcutKey {
        case .leftBracket:
            self = .leftBracket
        case .rightBracket:
            self = .rightBracket
        case .b:
            self = .b
        case .d:
            self = .d
        case .e:
            self = .e
        case .h:
            self = .h
        case .m:
            self = .m
        case .o:
            self = .o
        case .p:
            self = .p
        case .r:
            self = .r
        case .returnKey:
            self = .returnKey
        case .t:
            self = .t
        }
    }
}

private extension CinematicPlanCompassCommandPlan.Shortcut.Modifier {
    init?(recapModifier: CinematicRunRecapShareArtifactCommandPlan.Shortcut.Modifier) {
        switch recapModifier {
        case .command:
            self = .command
        case .control:
            self = .control
        case .option:
            self = .option
        case .shift:
            self = .shift
        }
    }
}

extension PlanWorkflowOverview.Kind {
    var planCompassCommandRouteIdentifier: String {
        switch self {
        case .immediate:
            return "immediate"
        case .midTerm:
            return "mid-term"
        case .longTerm:
            return "long-term"
        }
    }

    var planCompassCommandTitle: String {
        switch self {
        case .immediate:
            return "Immediate"
        case .midTerm:
            return "Mid-Term"
        case .longTerm:
            return "Long-Term"
        }
    }

    var planCompassCommandHelpLabel: String {
        switch self {
        case .immediate:
            return "the immediate route"
        case .midTerm:
            return "the mid-term route"
        case .longTerm:
            return "the long-term route"
        }
    }

    var planCompassFocusActionKind: CinematicPlanCompassCommandPlan.ActionKind {
        switch self {
        case .immediate:
            return .focusImmediateRoute
        case .midTerm:
            return .focusMidTermRoute
        case .longTerm:
            return .focusLongTermRoute
        }
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
