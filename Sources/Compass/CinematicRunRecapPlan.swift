import Foundation

struct CinematicRunRecapPlan: Equatable, Identifiable {
    static let titleLimit = 64
    static let detailLimit = 128
    static let statusLimit = 72
    static let completedSummaryLimit = 96
    static let commitHighlightLimit = 72
    static let eventChipLimit = 3
    static let eventChipLabelLimit = 34
    static let eventChipDetailLimit = 68

    var id: String { identifier }

    var identifier: String
    var availabilityIdentifier: String
    var isAvailable: Bool
    var sessionNumber: Int?
    var statusIdentifier: String
    var title: String
    var detail: String
    var status: String
    var systemImage: String
    var style: Style
    var latestCompletedSummary: String
    var newestCommitHighlight: String?
    var commitHighlightCount: Int
    var completedCount: Int
    var eventChips: [EventChip]

    var colorIdentifier: String {
        style.colorIdentifier
    }

    var eventChipCount: Int {
        eventChips.count
    }

    enum Style: String, Equatable {
        case success
        case failure
        case warning
        case paused
        case empty

        var colorIdentifier: String {
            switch self {
            case .success:
                return "green"
            case .failure:
                return "red"
            case .warning:
                return "orange"
            case .paused:
                return "blue"
            case .empty:
                return "secondary"
            }
        }
    }

    struct EventChip: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var sourceIdentifier: String
        var label: String
        var detail: String
        var systemImage: String
        var styleIdentifier: String
        var colorIdentifier: String
    }

    static func empty(reason: String) -> CinematicRunRecapPlan {
        let availability = normalizedIdentifierComponent(reason, fallback: "empty")
        return CinematicRunRecapPlan(
            identifier: "run-recap.empty|reason:\(availability)",
            availabilityIdentifier: availability,
            isAvailable: false,
            sessionNumber: nil,
            statusIdentifier: "none",
            title: boundedText("Run recap unavailable", limit: titleLimit),
            detail: boundedText(emptyDetail(for: availability), limit: detailLimit),
            status: boundedText("No recap", limit: statusLimit),
            systemImage: "clock.badge.questionmark",
            style: .empty,
            latestCompletedSummary: boundedText("No completed plan items recorded.", limit: completedSummaryLimit),
            newestCommitHighlight: nil,
            commitHighlightCount: 0,
            completedCount: 0,
            eventChips: []
        )
    }

    static func available(
        session: SessionRecord,
        latestCompletedSummary: String,
        newestCommitHighlight: String?,
        commitHighlightCount: Int,
        completedCount: Int,
        eventChips: [EventChip]
    ) -> CinematicRunRecapPlan {
        let statusCopy = statusText(for: session.status)
        let boundedCompletedSummary = boundedText(latestCompletedSummary, limit: completedSummaryLimit)
        let boundedCommitHighlight = newestCommitHighlight.map {
            boundedText($0, limit: commitHighlightLimit)
        }
        let boundedEventChips = Array(eventChips.prefix(eventChipLimit))
        let title = boundedText(
            "Run #\(session.session) \(statusCopy.lowercased())",
            limit: titleLimit
        )
        let status = boundedText(
            [
                countCopy(commitHighlightCount, singular: "commit highlight", plural: "commit highlights"),
                countCopy(completedCount, singular: "completed item", plural: "completed items"),
                countCopy(boundedEventChips.count, singular: "event", plural: "events")
            ].joined(separator: " - "),
            limit: statusLimit
        )
        let style = style(for: session.status)
        let identifier = [
            "run-recap",
            "session:\(session.session)",
            "status:\(session.status.rawValue)",
            "style:\(style.rawValue)",
            "completed:\(completedCount)",
            "summary:\(copyIdentifier(boundedCompletedSummary))",
            "commit-count:\(max(0, commitHighlightCount))",
            "commit:\(copyIdentifier(boundedCommitHighlight ?? "none"))",
            "events:\(boundedEventChips.map(\.identifier).joined(separator: ","))"
        ].joined(separator: "|")

        return CinematicRunRecapPlan(
            identifier: identifier,
            availabilityIdentifier: "available",
            isAvailable: true,
            sessionNumber: session.session,
            statusIdentifier: session.status.rawValue,
            title: title,
            detail: boundedText(boundedCompletedSummary, limit: detailLimit),
            status: status,
            systemImage: systemImage(for: session.status),
            style: style,
            latestCompletedSummary: boundedCompletedSummary,
            newestCommitHighlight: boundedCommitHighlight,
            commitHighlightCount: max(0, commitHighlightCount),
            completedCount: max(0, completedCount),
            eventChips: boundedEventChips
        )
    }

    static func eventChip(
        sourceIdentifier: String,
        label: String,
        detail: String,
        systemImage: String,
        styleIdentifier: String,
        colorIdentifier: String
    ) -> EventChip {
        let boundedLabel = boundedText(label, limit: eventChipLabelLimit)
        let boundedDetail = boundedText(detail, limit: eventChipDetailLimit)
        let boundedSystemImage = boundedText(systemImage, limit: 48)
        let boundedStyle = normalizedIdentifierComponent(styleIdentifier, fallback: "event")
        let boundedColor = normalizedIdentifierComponent(colorIdentifier, fallback: "secondary")
        let source = normalizedSourceIdentifier(sourceIdentifier)
        let identifier = [
            source,
            "style:\(boundedStyle)",
            "color:\(boundedColor)",
            "copy:\(copyIdentifier(boundedLabel, boundedDetail))"
        ].joined(separator: "|")

        return EventChip(
            identifier: identifier,
            sourceIdentifier: source,
            label: boundedLabel,
            detail: boundedDetail,
            systemImage: boundedSystemImage.isEmpty ? "circle.fill" : boundedSystemImage,
            styleIdentifier: boundedStyle,
            colorIdentifier: boundedColor
        )
    }

    static func boundedText(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = normalizedText(value)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }
        return normalized
            .prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    static func statusText(for status: SessionStatus) -> String {
        switch status {
        case .planning:
            return "Planning"
        case .awaitingApproval:
            return "Awaiting approval"
        case .developing:
            return "Developing"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .rejectedByPlan:
            return "Rejected by plan"
        case .skipped:
            return "Skipped"
        }
    }

    private static func emptyDetail(for availability: String) -> String {
        switch availability {
        case "active-run":
            return "Compass is still working on the active run."
        case "no-finished-session":
            return "No finished session is available to recap."
        default:
            return "No finished session is available to recap."
        }
    }

    private static func style(for status: SessionStatus) -> Style {
        switch status {
        case .succeeded:
            return .success
        case .failed, .rejectedByPlan:
            return .failure
        case .cancelled, .skipped:
            return .warning
        case .awaitingApproval:
            return .paused
        case .planning, .developing:
            return .empty
        }
    }

    private static func systemImage(for status: SessionStatus) -> String {
        switch status {
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "pause.circle.fill"
        case .rejectedByPlan:
            return "exclamationmark.triangle.fill"
        case .skipped:
            return "forward.end.circle"
        case .awaitingApproval:
            return "play.circle.fill"
        case .planning:
            return "clock"
        case .developing:
            return "hammer.circle"
        }
    }

    private static func countCopy(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(max(0, count)) \(plural)"
    }

    private static func normalizedSourceIdentifier(_ value: String) -> String {
        let normalized = normalizedText(value)
        return normalized.isEmpty ? "source:unknown" : normalized
    }

    private static func normalizedIdentifierComponent(_ value: String, fallback: String) -> String {
        let normalized = normalizedText(value)
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let collapsed = String(normalized)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? fallback : collapsed
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
}

enum CinematicRunRecapPlanner {
    static func plan(
        state: PlanState,
        sessions: [SessionRecord],
        isRunning: Bool,
        isAutoPlaying: Bool,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        commitConstellationPlan: CinematicCommitConstellationPlan,
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle
    ) -> CinematicRunRecapPlan {
        guard !isRunning && !isAutoPlaying else {
            return .empty(reason: "active-run")
        }

        guard let session = latestFinishedSession(in: sessions) else {
            return .empty(reason: "no-finished-session")
        }

        let latestCompletedSummary = state.completed.last.map {
            CinematicRunRecapPlan.boundedText(
                $0,
                limit: CinematicRunRecapPlan.completedSummaryLimit
            )
        } ?? "No completed plan items recorded."
        let eventChips = eventChips(
            recentRunCues: recentRunCues,
            nativeFeedbackLifecycle: nativeFeedbackLifecycle
        )

        return .available(
            session: session,
            latestCompletedSummary: latestCompletedSummary,
            newestCommitHighlight: commitConstellationPlan.newestSubject,
            commitHighlightCount: commitConstellationPlan.count,
            completedCount: state.completed.count,
            eventChips: eventChips
        )
    }

    private static func latestFinishedSession(in sessions: [SessionRecord]) -> SessionRecord? {
        sessions
            .filter { session in
                session.endedAt != nil && isFinishedStatus(session.status)
            }
            .max { lhs, rhs in
                let left = outcomeTime(lhs)
                let right = outcomeTime(rhs)
                if left == right {
                    return lhs.session < rhs.session
                }
                return left < right
            }
    }

    private static func isFinishedStatus(_ status: SessionStatus) -> Bool {
        switch status {
        case .succeeded, .failed, .cancelled, .rejectedByPlan, .skipped:
            return true
        case .planning, .awaitingApproval, .developing:
            return false
        }
    }

    private static func outcomeTime(_ session: SessionRecord) -> Double {
        max(session.endedAt ?? session.startedAt, session.startedAt)
    }

    private static func eventChips(
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle
    ) -> [CinematicRunRecapPlan.EventChip] {
        let runCueChips = recentRunCues
            .map { sessionNumber, cue in
                RunCueEntry(sessionNumber: sessionNumber, cue: cue)
            }
            .sorted(by: earlierRunCueEntry)
            .map(runCueChip)
        let nativeChips = nativeFeedbackHistoryChips(nativeFeedbackLifecycle)
        return Array((runCueChips + nativeChips).prefix(CinematicRunRecapPlan.eventChipLimit))
    }

    private struct RunCueEntry {
        var sessionNumber: Int
        var cue: PlanReliabilityFeedback.RunCue
    }

    private static func earlierRunCueEntry(_ lhs: RunCueEntry, _ rhs: RunCueEntry) -> Bool {
        let leftPriority = PlanReliabilityFeedback.priority(for: lhs.cue.kind)
        let rightPriority = PlanReliabilityFeedback.priority(for: rhs.cue.kind)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if lhs.cue.severity != rhs.cue.severity {
            return severityPriority(lhs.cue.severity) < severityPriority(rhs.cue.severity)
        }
        return lhs.sessionNumber > rhs.sessionNumber
    }

    private static func runCueChip(
        _ entry: RunCueEntry
    ) -> CinematicRunRecapPlan.EventChip {
        CinematicRunRecapPlan.eventChip(
            sourceIdentifier: "run-cue:\(entry.sessionNumber):\(entry.cue.kind.rawValue)",
            label: entry.cue.label,
            detail: entry.cue.detail,
            systemImage: entry.cue.systemImage,
            styleIdentifier: entry.cue.severity.rawValue,
            colorIdentifier: colorIdentifier(for: entry.cue.severity)
        )
    }

    private static func nativeFeedbackHistoryChips(
        _ lifecycle: CinematicNativeFeedbackCueLifecycle
    ) -> [CinematicRunRecapPlan.EventChip] {
        let activeChips = lifecycle.active.map { active in
            [
                CinematicRunRecapPlan.eventChip(
                    sourceIdentifier: "native-feedback:active:\(active.metadata.sequence):\(active.cue.milestoneIdentifier)",
                    label: active.cue.title,
                    detail: active.cue.detail,
                    systemImage: active.cue.systemImage,
                    styleIdentifier: active.cue.styleIdentifier,
                    colorIdentifier: active.cue.colorIdentifier
                )
            ]
        } ?? []

        let archiveChips = lifecycle.recentArchive.map { archived in
            CinematicRunRecapPlan.eventChip(
                sourceIdentifier: "native-feedback:archived:\(archived.sequence):\(archived.archiveReason.rawValue):\(archived.milestoneIdentifier)",
                label: "Feedback \(displayMilestone(archived.milestoneIdentifier))",
                detail: [
                    "archived/\(archived.archiveReason.rawValue)",
                    archived.sourceIdentifier
                ].filter { !$0.isEmpty }.joined(separator: " - "),
                systemImage: systemImage(forMilestone: archived.milestoneIdentifier),
                styleIdentifier: archived.styleIdentifier,
                colorIdentifier: colorIdentifier(forStyle: archived.styleIdentifier)
            )
        }

        return activeChips + archiveChips
    }

    private static func severityPriority(_ severity: PlanReliabilityFeedback.Severity) -> Int {
        switch severity {
        case .failure:
            return 0
        case .warning:
            return 1
        case .paused:
            return 2
        }
    }

    private static func colorIdentifier(for severity: PlanReliabilityFeedback.Severity) -> String {
        switch severity {
        case .failure:
            return "red"
        case .warning:
            return "orange"
        case .paused:
            return "blue"
        }
    }

    private static func colorIdentifier(forStyle styleIdentifier: String) -> String {
        switch styleIdentifier {
        case "success":
            return "green"
        case "warning":
            return "orange"
        case "failure":
            return "red"
        case "paused":
            return "blue"
        case "plan":
            return "indigo"
        case "develop":
            return "cyan"
        case "verify":
            return "yellow"
        default:
            return "secondary"
        }
    }

    private static func displayMilestone(_ milestoneIdentifier: String) -> String {
        let spaced = milestoneIdentifier.reduce(into: "") { result, character in
            if character.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        return spaced.capitalized
    }

    private static func systemImage(forMilestone milestoneIdentifier: String) -> String {
        switch milestoneIdentifier {
        case NativeFeedbackMilestone.planAccepted.rawValue:
            return "map.fill"
        case NativeFeedbackMilestone.developStarted.rawValue:
            return "hammer.fill"
        case NativeFeedbackMilestone.verifyStarted.rawValue:
            return "checkmark.seal"
        case NativeFeedbackMilestone.verifyPassed.rawValue:
            return "checkmark.circle.fill"
        case NativeFeedbackMilestone.developRetrying.rawValue:
            return "arrow.clockwise.circle.fill"
        case NativeFeedbackMilestone.postChecksFailed.rawValue:
            return "exclamationmark.triangle.fill"
        case NativeFeedbackMilestone.commitsPromoted.rawValue:
            return "arrow.triangle.branch"
        case NativeFeedbackMilestone.paused.rawValue:
            return "pause.circle.fill"
        case NativeFeedbackMilestone.stopped.rawValue:
            return "stop.circle.fill"
        case NativeFeedbackMilestone.noImmediateWork.rawValue:
            return "clock.badge.questionmark"
        default:
            return "circle.fill"
        }
    }
}
