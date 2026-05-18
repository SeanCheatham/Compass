import Foundation

struct CinematicNativeFeedbackCuePlan: Equatable, Identifiable {
    static let titleLimit = 72
    static let detailLimit = 118
    static let statusLimit = 44

    var id: String { identifier }

    var identifier: String
    var milestone: NativeFeedbackMilestone
    var phase: LoopPhase
    var feedbackMode: NativeFeedbackMode
    var title: String
    var detail: String
    var status: String
    var systemImage: String
    var style: Style
    var priority: Int
    var sourceIdentifier: String
    var runCueKind: PlanReliabilityFeedback.Kind?
    var runCueSessionNumber: Int?

    var styleIdentifier: String { style.rawValue }
    var colorIdentifier: String { style.colorIdentifier }
    var feedbackModeIdentifier: String { feedbackMode.rawValue }
    var milestoneIdentifier: String { milestone.rawValue }
    var phaseLabel: String { phase.rawValue }
    var isCriticalCinematicBanner: Bool {
        switch style {
        case .warning, .failure:
            return true
        case .plan, .develop, .verify, .success, .paused, .idle:
            return milestone == .developRetrying || milestone == .postChecksFailed
        }
    }

    enum Style: String, Equatable {
        case plan
        case develop
        case verify
        case success
        case warning
        case failure
        case paused
        case idle

        var colorIdentifier: String {
            switch self {
            case .plan:
                return "indigo"
            case .develop:
                return "cyan"
            case .verify:
                return "yellow"
            case .success:
                return "green"
            case .warning:
                return "orange"
            case .failure:
                return "red"
            case .paused:
                return "blue"
            case .idle:
                return "secondary"
            }
        }
    }

    init(
        milestone: NativeFeedbackMilestone,
        phase: LoopPhase,
        feedbackMode: NativeFeedbackMode,
        title: String,
        detail: String,
        status: String,
        systemImage: String,
        style: Style,
        priority: Int,
        sourceIdentifier: String,
        runCueKind: PlanReliabilityFeedback.Kind? = nil,
        runCueSessionNumber: Int? = nil
    ) {
        self.milestone = milestone
        self.phase = phase
        self.feedbackMode = feedbackMode
        self.title = Self.boundedText(title, limit: Self.titleLimit)
        self.detail = Self.boundedText(detail, limit: Self.detailLimit)
        self.status = Self.boundedText(status, limit: Self.statusLimit)
        self.systemImage = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.style = style
        self.priority = priority
        self.sourceIdentifier = sourceIdentifier
        self.runCueKind = runCueKind
        self.runCueSessionNumber = runCueSessionNumber
        identifier = Self.makeIdentifier(
            milestone: milestone,
            phase: phase,
            feedbackMode: feedbackMode,
            title: self.title,
            detail: self.detail,
            status: self.status,
            systemImage: self.systemImage,
            style: style,
            priority: priority,
            sourceIdentifier: sourceIdentifier
        )
    }

    private static func makeIdentifier(
        milestone: NativeFeedbackMilestone,
        phase: LoopPhase,
        feedbackMode: NativeFeedbackMode,
        title: String,
        detail: String,
        status: String,
        systemImage: String,
        style: Style,
        priority: Int,
        sourceIdentifier: String
    ) -> String {
        [
            "native-feedback:\(milestone.rawValue)",
            "mode:\(feedbackMode.rawValue)",
            "phase:\(phase.rawValue)",
            "style:\(style.rawValue)",
            "color:\(style.colorIdentifier)",
            "image:\(systemImage.isEmpty ? "circle" : systemImage)",
            "priority:\(priority)",
            "source:\(sourceIdentifier)",
            "copy:\(copyIdentifier(title, detail, status))"
        ].joined(separator: "|")
    }

    private static func copyIdentifier(_ values: String...) -> String {
        values
            .map(normalizedText)
            .joined(separator: "/")
    }

    private static func boundedText(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = normalizedText(value)
        guard normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }
        return normalized
            .prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CinematicNativeFeedbackCuePlanner {
    private static let runCuePriorityBase = 10

    static func plan(
        milestone: NativeFeedbackMilestone,
        content: NativeFeedbackContent,
        phase: LoopPhase,
        feedbackMode: NativeFeedbackMode,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue]
    ) -> CinematicNativeFeedbackCuePlan? {
        guard feedbackMode != .off else { return nil }

        let selectedRunCue = selectedRunCue(
            for: milestone,
            recentRunCues: recentRunCues
        )
        let title = selectedRunCue?.cue.label ?? content.title
        let detail = selectedRunCue?.cue.detail ?? content.body
        let systemImage = selectedRunCue?.cue.systemImage ?? systemImage(for: milestone)
        let cueStyle = selectedRunCue
            .map { style(for: $0.cue.severity) }
            ?? style(for: milestone, phase: phase)
        let priority = selectedRunCue
            .map { runCuePriorityBase + PlanReliabilityFeedback.priority(for: $0.cue.kind) }
            ?? priority(for: milestone)
        let sourceIdentifier = selectedRunCue
            .map { "run-cue:\($0.sessionNumber):\($0.cue.kind.rawValue)" }
            ?? "native:\(milestone.rawValue)"
        let status = [
            phase.rawValue,
            feedbackMode.title
        ].joined(separator: " - ")

        return CinematicNativeFeedbackCuePlan(
            milestone: milestone,
            phase: phase,
            feedbackMode: feedbackMode,
            title: title,
            detail: detail,
            status: status,
            systemImage: systemImage,
            style: cueStyle,
            priority: priority,
            sourceIdentifier: sourceIdentifier,
            runCueKind: selectedRunCue?.cue.kind,
            runCueSessionNumber: selectedRunCue?.sessionNumber
        )
    }

    private struct SelectedRunCue {
        var sessionNumber: Int
        var cue: PlanReliabilityFeedback.RunCue
    }

    private static func selectedRunCue(
        for milestone: NativeFeedbackMilestone,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue]
    ) -> SelectedRunCue? {
        guard milestone == .developRetrying || milestone == .postChecksFailed else {
            return nil
        }

        return recentRunCues
            .map { SelectedRunCue(sessionNumber: $0.key, cue: $0.value) }
            .min { lhs, rhs in
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
    }

    private static func priority(for milestone: NativeFeedbackMilestone) -> Int {
        switch milestone {
        case .postChecksFailed:
            return 20
        case .developRetrying:
            return 24
        case .paused, .stopped:
            return 32
        case .verifyStarted:
            return 40
        case .developStarted:
            return 46
        case .verifyPassed, .commitsPromoted:
            return 54
        case .planAccepted:
            return 58
        case .noImmediateWork:
            return 64
        }
    }

    private static func style(
        for milestone: NativeFeedbackMilestone,
        phase: LoopPhase
    ) -> CinematicNativeFeedbackCuePlan.Style {
        if phase == .paused {
            return .paused
        }

        switch milestone {
        case .planAccepted:
            return .plan
        case .developStarted, .developRetrying:
            return .develop
        case .verifyStarted:
            return .verify
        case .verifyPassed, .commitsPromoted:
            return .success
        case .postChecksFailed:
            return .failure
        case .paused, .stopped:
            return .paused
        case .noImmediateWork:
            return .idle
        }
    }

    private static func style(
        for severity: PlanReliabilityFeedback.Severity
    ) -> CinematicNativeFeedbackCuePlan.Style {
        switch severity {
        case .warning:
            return .warning
        case .failure:
            return .failure
        case .paused:
            return .paused
        }
    }

    private static func systemImage(for milestone: NativeFeedbackMilestone) -> String {
        switch milestone {
        case .planAccepted:
            return "map.fill"
        case .developStarted:
            return "hammer.fill"
        case .verifyStarted:
            return "checkmark.seal"
        case .verifyPassed:
            return "checkmark.circle.fill"
        case .developRetrying:
            return "arrow.clockwise.circle.fill"
        case .postChecksFailed:
            return "exclamationmark.triangle.fill"
        case .commitsPromoted:
            return "arrow.triangle.branch"
        case .paused:
            return "pause.circle.fill"
        case .stopped:
            return "stop.circle.fill"
        case .noImmediateWork:
            return "clock.badge.questionmark"
        }
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
}
