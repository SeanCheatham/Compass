import Foundation

struct CinematicSessionTimelinePlan: Equatable {
    static let defaultRecentSessionLimit = 6
    static let defaultMaximumBeatCount = 36
    static let detailLimit = 132

    var identifier: String
    var beats: [Beat]
    var selectedBeatID: String?
    var sessionCount: Int
    var countLabel: String

    var isEmpty: Bool {
        beats.isEmpty
    }

    var selectedBeat: Beat? {
        guard let selectedBeatID else { return nil }
        return beats.first { $0.stableID == selectedBeatID }
    }

    init(
        sessions: [SessionRecord],
        runCues: [Int: PlanReliabilityFeedback.RunCue] = [:],
        selectedBeatID preferredSelectedBeatID: String? = nil,
        recentSessionLimit: Int = Self.defaultRecentSessionLimit,
        maximumBeatCount: Int = Self.defaultMaximumBeatCount
    ) {
        let boundedSessionLimit = max(0, recentSessionLimit)
        let boundedBeatLimit = max(0, maximumBeatCount)
        guard boundedSessionLimit > 0, boundedBeatLimit > 0 else {
            self = Self.empty()
            return
        }

        let recentSessions = sessions
            .sorted(by: Self.moreRecentSession)
            .prefix(boundedSessionLimit)

        let rawBeats = recentSessions.flatMap { session in
            Self.beats(for: session, runCue: runCues[session.session])
        }
        let sortedBeats = rawBeats.sorted(by: Self.earlierBeat)
        let boundedBeats = Array(sortedBeats.suffix(boundedBeatLimit))
        let positionedBeats = Self.positioned(boundedBeats)
        let selectedBeatID = Self.normalizedSelection(
            preferredID: preferredSelectedBeatID,
            beats: positionedBeats
        )

        identifier = Self.identifier(for: positionedBeats)
        beats = positionedBeats
        self.selectedBeatID = selectedBeatID
        sessionCount = Set(positionedBeats.map(\.sessionNumber)).count
        countLabel = Self.countLabel(beatCount: positionedBeats.count, sessionCount: sessionCount)
    }

    struct Beat: Identifiable, Equatable {
        enum Moment: String, CaseIterable, Equatable {
            case plan
            case develop
            case verify
            case outcome
            case commit

            var sortOrder: Int {
                switch self {
                case .plan:
                    return 0
                case .develop:
                    return 1
                case .verify:
                    return 2
                case .outcome:
                    return 3
                case .commit:
                    return 4
                }
            }

            var shortTitle: String {
                switch self {
                case .plan:
                    return "Plan"
                case .develop:
                    return "Develop"
                case .verify:
                    return "Verify"
                case .outcome:
                    return "Outcome"
                case .commit:
                    return "Commit"
                }
            }
        }

        enum Style: String, Equatable {
            case neutral
            case active
            case success
            case warning
            case failure
            case paused
            case commit
        }

        var id: String { stableID }

        var stableID: String
        var sessionNumber: Int
        var moment: Moment
        var title: String
        var label: String
        var detail: String
        var metadata: String?
        var timestamp: Date
        var chronologyIndex: Int
        var position: Double
        var style: Style
        var systemImage: String
        var attentionLabel: String?
        var attentionDetail: String?

        var hasAttention: Bool {
            attentionLabel != nil
        }
    }

    private static func empty() -> CinematicSessionTimelinePlan {
        CinematicSessionTimelinePlan(
            identifier: "session-timeline.empty",
            beats: [],
            selectedBeatID: nil,
            sessionCount: 0,
            countLabel: "0 beats"
        )
    }

    private init(
        identifier: String,
        beats: [Beat],
        selectedBeatID: String?,
        sessionCount: Int,
        countLabel: String
    ) {
        self.identifier = identifier
        self.beats = beats
        self.selectedBeatID = selectedBeatID
        self.sessionCount = sessionCount
        self.countLabel = countLabel
    }

    private static func beats(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> [Beat] {
        var beats: [Beat] = [
            planBeat(for: session, runCue: runCue)
        ]

        if shouldIncludeDevelopBeat(for: session, runCue: runCue) {
            beats.append(developBeat(for: session, runCue: runCue))
        }

        if shouldIncludeVerifyBeat(for: session, runCue: runCue) {
            beats.append(verifyBeat(for: session, runCue: runCue))
        }

        if shouldIncludeOutcomeBeat(for: session, runCue: runCue) {
            beats.append(outcomeBeat(for: session, runCue: runCue))
        }

        beats.append(contentsOf: commitBeats(for: session, runCue: runCue))
        return beats
    }

    private static func planBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Beat {
        let detail = boundedText(session.plan) ?? "No plan text was recorded for this run."
        return beat(
            stableID: "session-\(session.session)-plan",
            session: session,
            moment: .plan,
            title: "Plan #\(session.session)",
            label: "Plan #\(session.session)",
            detail: detail,
            metadata: statusText(for: session.status),
            timeOffset: 0,
            style: style(for: .plan, session: session, runCue: runCue),
            systemImage: systemImage(for: .plan, session: session, runCue: runCue),
            runCue: runCue
        )
    }

    private static func developBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Beat {
        let title: String
        if session.status == .awaitingApproval || runCue?.kind == .resumeDevelop {
            title = "Develop ready #\(session.session)"
        } else {
            title = "Develop #\(session.session)"
        }

        let detail = targetedDetail(
            for: .develop,
            session: session,
            runCue: runCue
        ) ?? boundedText(session.feedback)
            ?? "Codex moved from plan into implementation."

        return beat(
            stableID: "session-\(session.session)-develop",
            session: session,
            moment: .develop,
            title: title,
            label: "Develop #\(session.session)",
            detail: detail,
            metadata: statusText(for: session.status),
            timeOffset: 0.34,
            style: style(for: .develop, session: session, runCue: runCue),
            systemImage: systemImage(for: .develop, session: session, runCue: runCue),
            runCue: runCue
        )
    }

    private static func verifyBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Beat {
        let command = boundedText(session.verifyOutput?.command)
            ?? boundedText(session.verify)
            ?? "Verify command was not recorded."
        let detail = targetedDetail(
            for: .verify,
            session: session,
            runCue: runCue
        ) ?? command
        let metadata = verifyMetadata(for: session)

        return beat(
            stableID: "session-\(session.session)-verify",
            session: session,
            moment: .verify,
            title: "Verify #\(session.session)",
            label: "Verify #\(session.session)",
            detail: detail,
            metadata: metadata,
            timeOffset: 0.68,
            style: style(for: .verify, session: session, runCue: runCue),
            systemImage: systemImage(for: .verify, session: session, runCue: runCue),
            runCue: runCue
        )
    }

    private static func outcomeBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Beat {
        let title = "\(statusText(for: session.status)) #\(session.session)"
        let detail = targetedDetail(
            for: .outcome,
            session: session,
            runCue: runCue
        ) ?? boundedText(session.feedback)
            ?? boundedText(session.notes.last)
            ?? "Run status: \(statusText(for: session.status).lowercased())."

        return beat(
            stableID: "session-\(session.session)-outcome",
            session: session,
            moment: .outcome,
            title: title,
            label: title,
            detail: detail,
            metadata: session.commits.isEmpty ? nil : "\(session.commits.count) \(session.commits.count == 1 ? "commit" : "commits")",
            timeOffset: 1,
            style: style(for: .outcome, session: session, runCue: runCue),
            systemImage: systemImage(for: .outcome, session: session, runCue: runCue),
            runCue: runCue
        )
    }

    private static func commitBeats(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> [Beat] {
        var seenCommitIDs = Set<String>()

        return session.commits.enumerated().map { index, commit in
            let commitID = uniqueCommitID(
                for: commit,
                fallbackIndex: index,
                seenCommitIDs: &seenCommitIDs
            )
            let shortHash = displayShortHash(commit)
            let subject = CinematicCommitContext.displaySubject(from: commit.subject)
                ?? "Untitled commit"
            let label = [shortHash, subject]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            return beat(
                stableID: "session-\(session.session)-commit-\(commitID)",
                session: session,
                moment: .commit,
                title: "Commit \(shortHash)",
                label: label,
                detail: subject,
                metadata: "#\(session.session)",
                timeOffset: 1 + (Double(index + 1) * 0.01),
                style: .commit,
                systemImage: "arrow.triangle.branch",
                runCue: runCue
            )
        }
    }

    private static func beat(
        stableID: String,
        session: SessionRecord,
        moment: Beat.Moment,
        title: String,
        label: String,
        detail: String,
        metadata: String?,
        timeOffset: Double,
        style: Beat.Style,
        systemImage: String,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Beat {
        let timestamp = Date(timeIntervalSince1970: syntheticTime(
            for: session,
            offset: timeOffset
        ) / 1_000)

        return Beat(
            stableID: stableID,
            sessionNumber: session.session,
            moment: moment,
            title: title,
            label: label,
            detail: detail,
            metadata: metadata,
            timestamp: timestamp,
            chronologyIndex: 0,
            position: 0.5,
            style: style,
            systemImage: systemImage,
            attentionLabel: runCue?.label,
            attentionDetail: runCue?.detail
        )
    }

    private static func shouldIncludeDevelopBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Bool {
        switch session.status {
        case .planning, .rejectedByPlan:
            return runCue?.kind == .developBlocked || runCue?.kind == .developFailed
        case .awaitingApproval, .developing, .succeeded, .failed, .cancelled, .skipped:
            return true
        }
    }

    private static func shouldIncludeVerifyBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Bool {
        boundedText(session.verify) != nil
            || boundedText(session.verifyOutput?.command) != nil
            || runCue?.kind == .failedVerify
    }

    private static func shouldIncludeOutcomeBeat(
        for session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Bool {
        switch session.status {
        case .planning, .developing:
            return runCue != nil
        case .awaitingApproval, .succeeded, .failed, .cancelled, .rejectedByPlan, .skipped:
            return true
        }
    }

    private static func style(
        for moment: Beat.Moment,
        session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> Beat.Style {
        if moment == .commit {
            return .commit
        }

        if let runCue, cue(runCue, targets: moment) {
            return style(for: runCue.severity)
        }

        if moment == .verify, hasFailedVerify(session) {
            return .failure
        }

        switch session.status {
        case .planning:
            return moment == .plan ? .active : .neutral
        case .awaitingApproval:
            return moment == .develop || moment == .outcome ? .paused : .neutral
        case .developing:
            return moment == .develop ? .active : .neutral
        case .succeeded:
            return moment == .outcome || moment == .verify ? .success : .neutral
        case .failed, .rejectedByPlan:
            return moment == .outcome ? .failure : .neutral
        case .cancelled, .skipped:
            return moment == .outcome ? .warning : .neutral
        }
    }

    private static func style(for severity: PlanReliabilityFeedback.Severity) -> Beat.Style {
        switch severity {
        case .warning:
            return .warning
        case .failure:
            return .failure
        case .paused:
            return .paused
        }
    }

    private static func systemImage(
        for moment: Beat.Moment,
        session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> String {
        if let runCue, cue(runCue, targets: moment) {
            return runCue.systemImage
        }

        switch moment {
        case .plan:
            return "map"
        case .develop:
            return "hammer"
        case .verify:
            return hasFailedVerify(session) ? "checkmark.seal.fill" : "checkmark.seal"
        case .outcome:
            return outcomeSystemImage(for: session.status)
        case .commit:
            return "arrow.triangle.branch"
        }
    }

    private static func cue(
        _ runCue: PlanReliabilityFeedback.RunCue,
        targets moment: Beat.Moment
    ) -> Bool {
        switch runCue.kind {
        case .rejectedPlan:
            return moment == .plan || moment == .outcome
        case .developBlocked, .developFailed, .resumeDevelop:
            return moment == .develop || moment == .outcome
        case .failedVerify:
            return moment == .verify || moment == .outcome
        }
    }

    private static func targetedDetail(
        for moment: Beat.Moment,
        session: SessionRecord,
        runCue: PlanReliabilityFeedback.RunCue?
    ) -> String? {
        if let runCue, cue(runCue, targets: moment) {
            return boundedText(runCue.detail)
        }

        if moment == .verify, hasFailedVerify(session) {
            return boundedText(session.verifyOutput?.tail)
        }

        return nil
    }

    private static func verifyMetadata(for session: SessionRecord) -> String? {
        let command = boundedText(session.verifyOutput?.command) ?? boundedText(session.verify)
        let exitCode = session.verifyOutput?.exitCode.map { "exit \($0)" }
        return [command, exitCode]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private static func hasFailedVerify(_ session: SessionRecord) -> Bool {
        guard let verifyOutput = session.verifyOutput else { return false }
        if let exitCode = verifyOutput.exitCode {
            return exitCode != 0
        }
        return session.status == .failed && boundedText(verifyOutput.tail) != nil
    }

    private static func outcomeSystemImage(for status: SessionStatus) -> String {
        switch status {
        case .planning:
            return "clock"
        case .awaitingApproval:
            return "play.circle.fill"
        case .developing:
            return "hammer.circle"
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
        }
    }

    private static func moreRecentSession(_ lhs: SessionRecord, _ rhs: SessionRecord) -> Bool {
        let lhsTime = outcomeTime(lhs)
        let rhsTime = outcomeTime(rhs)
        if lhsTime == rhsTime {
            return lhs.session > rhs.session
        }
        return lhsTime > rhsTime
    }

    private static func earlierBeat(_ lhs: Beat, _ rhs: Beat) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.sessionNumber != rhs.sessionNumber {
            return lhs.sessionNumber < rhs.sessionNumber
        }
        if lhs.moment.sortOrder != rhs.moment.sortOrder {
            return lhs.moment.sortOrder < rhs.moment.sortOrder
        }
        return lhs.stableID < rhs.stableID
    }

    private static func positioned(_ beats: [Beat]) -> [Beat] {
        guard !beats.isEmpty else { return [] }
        let denominator = max(beats.count - 1, 1)

        return beats.enumerated().map { index, beat in
            var copy = beat
            copy.chronologyIndex = index
            copy.position = beats.count == 1 ? 0.5 : Double(index) / Double(denominator)
            return copy
        }
    }

    private static func normalizedSelection(
        preferredID: String?,
        beats: [Beat]
    ) -> String? {
        guard !beats.isEmpty else { return nil }
        let beatIDs = Set(beats.map(\.stableID))
        if let preferredID, beatIDs.contains(preferredID) {
            return preferredID
        }

        if let preferredID,
           let preferredSessionNumber = sessionNumber(from: preferredID),
           let sameSessionBeat = beats.last(where: { $0.sessionNumber == preferredSessionNumber }) {
            return sameSessionBeat.stableID
        }

        return beats.last?.stableID
    }

    private static func sessionNumber(from beatID: String) -> Int? {
        let prefix = "session-"
        guard beatID.hasPrefix(prefix) else { return nil }

        let suffix = beatID.dropFirst(prefix.count)
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func identifier(for beats: [Beat]) -> String {
        guard !beats.isEmpty else { return "session-timeline.empty" }

        return [
            "session-timeline",
            "beats:\(beats.map(\.stableID).joined(separator: ","))"
        ].joined(separator: "|")
    }

    private static func countLabel(beatCount: Int, sessionCount: Int) -> String {
        guard beatCount > 0 else { return "0 beats" }
        let beatWord = beatCount == 1 ? "beat" : "beats"
        let runWord = sessionCount == 1 ? "run" : "runs"
        return "\(beatCount) \(beatWord) · \(sessionCount) \(runWord)"
    }

    private static func syntheticTime(for session: SessionRecord, offset: Double) -> Double {
        let start = session.startedAt
        let end = max(session.endedAt ?? start, start)
        let span = max(end - start, 1)
        return start + (span * offset)
    }

    private static func outcomeTime(_ session: SessionRecord) -> Double {
        max(session.endedAt ?? session.startedAt, session.startedAt)
    }

    private static func statusText(for status: SessionStatus) -> String {
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

    private static func uniqueCommitID(
        for commit: SessionCommit,
        fallbackIndex: Int,
        seenCommitIDs: inout Set<String>
    ) -> String {
        let base = sanitizedCommitIdentifier(commit.sha)
            ?? sanitizedCommitIdentifier(commit.short)
            ?? "item\(fallbackIndex + 1)"
        guard seenCommitIDs.contains(base) else {
            seenCommitIDs.insert(base)
            return base
        }

        let unique = "\(base)-\(fallbackIndex + 1)"
        seenCommitIDs.insert(unique)
        return unique
    }

    private static func sanitizedCommitIdentifier(_ raw: String) -> String? {
        let sanitized = raw
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        guard !sanitized.isEmpty else { return nil }
        return String(sanitized.prefix(16))
    }

    private static func displayShortHash(_ commit: SessionCommit) -> String {
        let short = commit.short.trimmingCharacters(in: .whitespacesAndNewlines)
        if !short.isEmpty {
            return String(short.prefix(10))
        }

        let sha = commit.sha.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sha.prefix(10))
    }

    private static func boundedText(_ value: String?) -> String? {
        guard let normalized = normalizedText(value) else { return nil }
        guard normalized.count > detailLimit else { return normalized }

        return normalized.prefix(detailLimit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func normalizedText(_ value: String?) -> String? {
        let normalized = value?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return normalized.isEmpty ? nil : normalized
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
