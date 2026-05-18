import Foundation

struct CinematicNativeFeedbackCuePlan: Equatable, Identifiable {
    static let titleLimit = 72
    static let detailLimit = 118
    static let statusLimit = 44

    var id: String { identifier }

    var identifier: String
    var baseIdentifier: String
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
    var lifecycleIdentifier: String
    var lifecycleStateIdentifier: String
    var lifecycleDisplayDuration: TimeInterval
    var lifecycleRecordedAt: Date?
    var lifecycleExpiresAt: Date?
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
        lifecycleIdentifier = "detached"
        lifecycleStateIdentifier = "detached"
        lifecycleDisplayDuration = 0
        lifecycleRecordedAt = nil
        lifecycleExpiresAt = nil
        self.runCueKind = runCueKind
        self.runCueSessionNumber = runCueSessionNumber
        baseIdentifier = Self.makeIdentifier(
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
        identifier = baseIdentifier
    }

    func applyingLifecycle(
        _ metadata: CinematicNativeFeedbackCueLifecycle.Metadata
    ) -> CinematicNativeFeedbackCuePlan {
        var copy = self
        copy.lifecycleIdentifier = metadata.identifier
        copy.lifecycleStateIdentifier = metadata.state.rawValue
        copy.lifecycleDisplayDuration = metadata.displayDuration
        copy.lifecycleRecordedAt = metadata.recordedAt
        copy.lifecycleExpiresAt = metadata.expiresAt
        copy.identifier = [
            copy.baseIdentifier,
            metadata.identifier
        ].joined(separator: "|")
        return copy
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

struct CinematicNativeFeedbackCueLifecycle: Equatable {
    static let standardDisplayDuration: TimeInterval = 8
    static let criticalDisplayDuration: TimeInterval = 24
    static let displayDurationRange: ClosedRange<TimeInterval> = 4...30
    static let recentArchiveLimit = 5

    var active: ActiveCue?
    var recentArchive: [ArchivedCue]
    var sequenceCounter: Int

    init(
        active: ActiveCue? = nil,
        recentArchive: [ArchivedCue] = [],
        sequenceCounter: Int = 0
    ) {
        self.active = active
        self.recentArchive = Array(recentArchive.prefix(Self.recentArchiveLimit))
        self.sequenceCounter = max(0, sequenceCounter)
    }

    var activeCue: CinematicNativeFeedbackCuePlan? {
        active?.cue
    }

    var hasState: Bool {
        active != nil || !recentArchive.isEmpty
    }

    var stateIdentifier: String {
        if active != nil {
            return Metadata.State.active.rawValue
        }
        if let latestArchive = recentArchive.first {
            return latestArchive.archiveReason == .expired
                ? ArchiveReason.expired.rawValue
                : Metadata.State.archived.rawValue
        }
        return "empty"
    }

    var identifier: String {
        [
            "native-feedback-cue-lifecycle",
            "state:\(stateIdentifier)",
            "active:\(active?.lifecycleIdentifier ?? "none")",
            "archive-count:\(recentArchive.count)",
            "archive:\(recentArchive.map(\.lifecycleIdentifier).joined(separator: ","))"
        ].joined(separator: "|")
    }

    var recentArchiveIdentifiers: [String] {
        recentArchive.map(\.lifecycleIdentifier)
    }

    @discardableResult
    mutating func record(
        _ cue: CinematicNativeFeedbackCuePlan,
        now: Date
    ) -> CinematicNativeFeedbackCuePlan {
        archiveActive(reason: .replaced, now: now)
        sequenceCounter += 1

        let duration = Self.displayDuration(for: cue)
        let metadata = Metadata(
            state: .active,
            sequence: sequenceCounter,
            displayDuration: duration,
            recordedAt: now,
            expiresAt: now.addingTimeInterval(duration),
            archivedAt: nil,
            archiveReason: nil
        )
        let activeCue = cue.applyingLifecycle(metadata)
        active = ActiveCue(cue: activeCue, metadata: metadata)
        return activeCue
    }

    @discardableResult
    mutating func expire(now: Date) -> Bool {
        guard let active, now >= active.expiresAt else { return false }
        archiveActive(reason: .expired, now: now)
        return true
    }

    mutating func clear(reason: ArchiveReason, now: Date) {
        archiveActive(reason: reason, now: now)
    }

    static func displayDuration(for cue: CinematicNativeFeedbackCuePlan) -> TimeInterval {
        let duration = cue.isCriticalCinematicBanner
            ? criticalDisplayDuration
            : standardDisplayDuration
        return min(max(duration, displayDurationRange.lowerBound), displayDurationRange.upperBound)
    }

    private mutating func archiveActive(reason: ArchiveReason, now: Date) {
        guard let active else { return }
        let archivedMetadata = active.metadata.archived(reason: reason, at: now)
        recentArchive.insert(
            ArchivedCue(cue: active.cue, metadata: archivedMetadata),
            at: 0
        )
        recentArchive = Array(recentArchive.prefix(Self.recentArchiveLimit))
        self.active = nil
    }

    struct ActiveCue: Equatable {
        var cue: CinematicNativeFeedbackCuePlan
        var metadata: Metadata

        var lifecycleIdentifier: String { metadata.identifier }
        var cueIdentifier: String { cue.identifier }
        var expiresAt: Date { metadata.expiresAt }
        var displayDuration: TimeInterval { metadata.displayDuration }
    }

    struct ArchivedCue: Equatable {
        var cueIdentifier: String
        var baseCueIdentifier: String
        var lifecycleIdentifier: String
        var stateIdentifier: String
        var archiveReason: ArchiveReason
        var milestoneIdentifier: String
        var displayDuration: TimeInterval
        var recordedAt: Date
        var expiresAt: Date
        var archivedAt: Date
        var sequence: Int

        init(cue: CinematicNativeFeedbackCuePlan, metadata: Metadata) {
            cueIdentifier = cue.identifier
            baseCueIdentifier = cue.baseIdentifier
            lifecycleIdentifier = metadata.identifier
            stateIdentifier = metadata.state.rawValue
            archiveReason = metadata.archiveReason ?? .cleared
            milestoneIdentifier = cue.milestoneIdentifier
            displayDuration = metadata.displayDuration
            recordedAt = metadata.recordedAt
            expiresAt = metadata.expiresAt
            archivedAt = metadata.archivedAt ?? metadata.expiresAt
            sequence = metadata.sequence
        }
    }

    struct Metadata: Equatable {
        enum State: String, Equatable {
            case active
            case archived
        }

        var state: State
        var sequence: Int
        var displayDuration: TimeInterval
        var recordedAt: Date
        var expiresAt: Date
        var archivedAt: Date?
        var archiveReason: ArchiveReason?

        var identifier: String {
            [
                "lifecycle:\(state.rawValue)",
                "seq:\(sequence)",
                "duration:\(Self.fixed(displayDuration))",
                "recorded:\(Self.dateIdentifier(recordedAt))",
                "expires:\(Self.dateIdentifier(expiresAt))",
                archiveReason.map { "reason:\($0.rawValue)" },
                archivedAt.map { "archived:\(Self.dateIdentifier($0))" }
            ].compactMap { $0 }.joined(separator: ":")
        }

        func archived(reason: ArchiveReason, at archivedAt: Date) -> Metadata {
            Metadata(
                state: .archived,
                sequence: sequence,
                displayDuration: displayDuration,
                recordedAt: recordedAt,
                expiresAt: expiresAt,
                archivedAt: archivedAt,
                archiveReason: reason
            )
        }

        private static func dateIdentifier(_ date: Date) -> String {
            fixed(date.timeIntervalSinceReferenceDate)
        }

        private static func fixed(_ value: TimeInterval) -> String {
            String(format: "%.4f", value)
        }
    }

    enum ArchiveReason: String, Equatable {
        case replaced
        case expired
        case modeOff = "mode-off"
        case cleared
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
