import Foundation

struct CinematicActivitySourceCuePlan: Equatable, Identifiable {
    static let identifierLimit = 220
    static let sourceIdentifierLimit = 260
    static let labelLimit = 38
    static let detailLimit = 180
    static let helpLimit = 420
    static let systemImageLimit = 64
    static let tintIdentifierLimit = 24
    static let copyTextLimit = 520

    var id: String { identifier }

    var identifier: String
    var sourceIdentifier: String
    var statusIdentifier: String
    var kindIdentifier: String
    var activeStorageIdentifier: String
    var availabilityIdentifier: String
    var repoLocalSessionsStateIdentifier: String
    var repoLocalModeIdentifier: String
    var label: String
    var detail: String
    var helpText: String
    var systemImage: String
    var severityIdentifier: String
    var tintIdentifier: String
    var copyText: String
    var isVisible: Bool
    var isCritical: Bool
    var isQuietModeSuppressible: Bool

    init(
        snapshot: RepositoryActivitySourceSnapshot,
        status providedStatus: ProjectActivitySourceStatus? = nil
    ) {
        let status = providedStatus ?? ProjectActivitySourceStatus(snapshot: snapshot)
        let visible = status.isVisible
        let severity = status.severity
        let stateIdentifier = [
            status.kind.rawValue,
            "storage:\(snapshot.activeStorageIdentifier)",
            "availability:\(snapshot.sourceAvailabilityIdentifier)",
            "repo-local:\(snapshot.repoLocalSessionsStateIdentifier)",
            "repo-local-mode:\(snapshot.repoLocalSessionsIgnoredIdentifier)"
        ].joined(separator: "|")
        let resolvedIdentifier = Self.boundedText(
            "activity-source-cue|\(stateIdentifier)",
            limit: Self.identifierLimit
        )
        let resolvedLabel = visible
            ? Self.boundedText(status.label, limit: Self.labelLimit)
            : ""
        let resolvedDetail = visible
            ? Self.boundedText(status.detail, limit: Self.detailLimit)
            : ""
        let resolvedHelp = visible
            ? Self.boundedText(status.helpText, limit: Self.helpLimit)
            : ""

        identifier = resolvedIdentifier
        sourceIdentifier = Self.boundedText(snapshot.identifier, limit: Self.sourceIdentifierLimit)
        statusIdentifier = Self.boundedText(status.identifier, limit: Self.identifierLimit)
        kindIdentifier = status.kind.rawValue
        activeStorageIdentifier = snapshot.activeStorageIdentifier
        availabilityIdentifier = snapshot.sourceAvailabilityIdentifier
        repoLocalSessionsStateIdentifier = snapshot.repoLocalSessionsStateIdentifier
        repoLocalModeIdentifier = snapshot.repoLocalSessionsIgnoredIdentifier
        label = resolvedLabel
        detail = resolvedDetail
        helpText = resolvedHelp
        systemImage = Self.boundedText(status.systemImage, limit: Self.systemImageLimit)
        severityIdentifier = severity.rawValue
        tintIdentifier = Self.boundedText(Self.tintIdentifier(for: severity), limit: Self.tintIdentifierLimit)
        isVisible = visible
        isCritical = severity == .warning || severity == .failure
        isQuietModeSuppressible = visible
            && !isCritical
            && snapshot.sourceAvailability == .available
        copyText = visible
            ? Self.boundedText(
                [
                    resolvedLabel,
                    resolvedDetail,
                    "storage \(snapshot.activeStorageIdentifier)",
                    "availability \(snapshot.sourceAvailabilityIdentifier)",
                    "repo-local \(snapshot.repoLocalSessionsStateIdentifier)",
                    "policy-source \(status.kind.rawValue)"
                ]
                    .filter { !$0.isEmpty }
                    .joined(separator: " | "),
                limit: Self.copyTextLimit
            )
            : ""
    }

    private static func tintIdentifier(
        for severity: CompassWorkspaceStorageAssessment.Severity
    ) -> String {
        switch severity {
        case .healthy:
            return "green"
        case .info:
            return "blue"
        case .warning:
            return "orange"
        case .failure:
            return "red"
        }
    }

    private static func boundedText(_ value: String, limit: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "" }
        guard normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }
        return normalized.prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
