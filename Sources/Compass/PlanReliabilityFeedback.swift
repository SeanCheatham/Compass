import Foundation

struct PlanReliabilityFeedback: Equatable {
    static let defaultNoticeLimit = 3
    static let defaultDetailLimit = 220
    static let defaultTailLimit = 260

    var notices: [Notice]
    var recentRunCues: [Int: RunCue]

    var isEmpty: Bool {
        notices.isEmpty
    }

    init(
        state: PlanState,
        sessions: [SessionRecord],
        historyItems: [PlanSessionHistoryItem]? = nil,
        noticeLimit: Int = Self.defaultNoticeLimit,
        detailLimit: Int = Self.defaultDetailLimit,
        tailLimit: Int = Self.defaultTailLimit
    ) {
        let sortedHistoryItems = historyItems ?? PlanSessionHistory.displayItems(for: sessions)
        var sessionByNumber: [Int: SessionRecord] = [:]
        for session in sessions {
            sessionByNumber[session.session] = session
        }

        let allNotices = sortedHistoryItems.flatMap { item in
            guard let session = sessionByNumber[item.sessionNumber] else {
                return [Notice]()
            }

            return Self.notices(
                for: session,
                item: item,
                state: state,
                detailLimit: detailLimit,
                tailLimit: tailLimit
            )
        }

        notices = Array(allNotices.prefix(max(0, noticeLimit)))

        var cues: [Int: RunCue] = [:]
        for notice in allNotices where cues[notice.sessionNumber] == nil {
            cues[notice.sessionNumber] = RunCue(notice: notice)
        }
        recentRunCues = cues
    }

    struct Notice: Identifiable, Equatable {
        var id: String
        var kind: Kind
        var severity: Severity
        var sessionNumber: Int
        var title: String
        var detail: String
        var actionLabel: String
        var metadata: String?
        var systemImage: String
    }

    struct RunCue: Equatable {
        var kind: Kind
        var severity: Severity
        var label: String
        var detail: String
        var systemImage: String

        init(notice: Notice) {
            kind = notice.kind
            severity = notice.severity
            label = notice.actionLabel
            detail = notice.detail
            systemImage = notice.systemImage
        }
    }

    enum Kind: String, Equatable {
        case rejectedPlan
        case developBlocked
        case developFailed
        case failedVerify
        case resumeDevelop
    }

    enum Severity: String, Equatable {
        case warning
        case failure
        case paused
    }

    private static func notices(
        for session: SessionRecord,
        item: PlanSessionHistoryItem,
        state: PlanState,
        detailLimit: Int,
        tailLimit: Int
    ) -> [Notice] {
        if let rejectionText = planRejectionText(in: session, detailLimit: detailLimit) {
            return [
                Notice(
                    id: "\(Kind.rejectedPlan.rawValue)-\(session.session)",
                    kind: .rejectedPlan,
                    severity: .failure,
                    sessionNumber: session.session,
                    title: "Plan rejected",
                    detail: rejectionText,
                    actionLabel: "Retry Plan",
                    metadata: "#\(session.session)",
                    systemImage: "exclamationmark.triangle.fill"
                )
            ]
        }

        if session.status == .awaitingApproval, state.immediate != nil {
            return [
                Notice(
                    id: "\(Kind.resumeDevelop.rawValue)-\(session.session)",
                    kind: .resumeDevelop,
                    severity: .paused,
                    sessionNumber: session.session,
                    title: "Develop ready",
                    detail: item.planExcerpt
                        ?? boundedPrefix(state.immediate?.plan, limit: detailLimit)
                        ?? "Plan is ready; Develop has not started.",
                    actionLabel: "Resume Develop",
                    metadata: "#\(session.session)",
                    systemImage: "play.circle.fill"
                )
            ]
        }

        var results: [Notice] = []

        if let blockerText = developBlockedText(in: session, detailLimit: detailLimit) {
            results.append(
                Notice(
                    id: "\(Kind.developBlocked.rawValue)-\(session.session)",
                    kind: .developBlocked,
                    severity: .warning,
                    sessionNumber: session.session,
                    title: "Develop blocked",
                    detail: blockerText,
                    actionLabel: retryDevelopLabel(for: state),
                    metadata: "#\(session.session)",
                    systemImage: "hand.raised.fill"
                )
            )
        } else if let failureText = developFailureText(in: session, detailLimit: detailLimit) {
            results.append(
                Notice(
                    id: "\(Kind.developFailed.rawValue)-\(session.session)",
                    kind: .developFailed,
                    severity: .failure,
                    sessionNumber: session.session,
                    title: "Develop failed",
                    detail: failureText,
                    actionLabel: retryDevelopLabel(for: state),
                    metadata: "#\(session.session)",
                    systemImage: "xmark.octagon.fill"
                )
            )
        }

        if let failedVerify = item.failedVerify {
            results.append(
                Notice(
                    id: "\(Kind.failedVerify.rawValue)-\(session.session)",
                    kind: .failedVerify,
                    severity: .failure,
                    sessionNumber: session.session,
                    title: "Verify failed",
                    detail: boundedSuffix(failedVerify.tail, limit: tailLimit) ?? "Verify failed without captured output.",
                    actionLabel: retryDevelopLabel(for: state),
                    metadata: verifyMetadata(failedVerify, limit: detailLimit),
                    systemImage: "checkmark.seal.fill"
                )
            )
        }

        return results
    }

    private static func planRejectionText(in session: SessionRecord, detailLimit: Int) -> String? {
        if session.status == .rejectedByPlan {
            return boundedPrefix(firstNonEmpty(rejectionCandidateTexts(in: session)), limit: detailLimit)
                ?? "Plan was rejected before state.json changed."
        }

        guard let text = firstMatchingText(in: rejectionCandidateTexts(in: session), containsAny: [
            "refusing to overwrite state.json",
            "placeholder verify command",
            "plan tried to",
            "plan transition",
            "rejected plan"
        ]) else {
            return nil
        }

        return boundedPrefix(text, limit: detailLimit)
    }

    private static func developBlockedText(in session: SessionRecord, detailLimit: Int) -> String? {
        guard session.status == .failed else { return nil }
        guard firstMatchingText(in: session.notes + optionalTexts(session.feedback), containsAny: [
            "develop reported it was blocked",
            "blocked but did not request verify bypass",
            "develop blocked",
            "blocked"
        ]) != nil else {
            return nil
        }

        return boundedPrefix(session.feedback, limit: detailLimit)
            ?? boundedPrefix(firstMatchingText(in: session.notes, containsAny: ["blocked"]), limit: detailLimit)
            ?? "Develop reported it was blocked."
    }

    private static func developFailureText(in session: SessionRecord, detailLimit: Int) -> String? {
        guard session.status == .failed else { return nil }
        let matchingNote = firstMatchingText(in: session.notes, containsAny: [
            "develop reported failure:",
            "develop failed"
        ])
        if let matchingNote {
            return boundedPrefix(session.feedback, limit: detailLimit)
                ?? boundedPrefix(
                    strippedDevelopFailurePrefix(from: matchingNote),
                    limit: detailLimit
                ) ?? "Develop reported failure."
        }

        guard session.verifyOutput == nil else { return nil }
        return boundedPrefix(session.feedback, limit: detailLimit)
    }

    private static func retryDevelopLabel(for state: PlanState) -> String {
        state.immediate == nil ? "Plan Next Step" : "Retry Develop"
    }

    private static func strippedDevelopFailurePrefix(from text: String) -> String {
        let prefix = "develop reported failure:"
        guard text.lowercased().hasPrefix(prefix) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prefixEnd = text.index(text.startIndex, offsetBy: prefix.count)
        return String(text[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func verifyMetadata(_ failedVerify: PlanSessionHistoryItem.FailedVerify, limit: Int) -> String {
        [
            boundedPrefix(failedVerify.command, limit: min(limit, 96)),
            failedVerify.exitCodeText
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private static func rejectionCandidateTexts(in session: SessionRecord) -> [String] {
        session.notes + optionalTexts(session.feedback)
    }

    private static func optionalTexts(_ value: String?) -> [String] {
        guard let value else { return [] }
        return [value]
    }

    private static func firstNonEmpty(_ values: [String]) -> String? {
        values.first { normalizedText($0) != nil }
    }

    private static func firstMatchingText(in values: [String], containsAny needles: [String]) -> String? {
        values.first { value in
            let normalized = value.lowercased()
            return needles.contains { normalized.contains($0) }
        }
    }

    private static func boundedPrefix(_ value: String?, limit: Int) -> String? {
        guard let normalized = normalizedText(value), limit > 0 else {
            return nil
        }

        guard normalized.count > limit else {
            return normalized
        }

        guard limit > 3 else {
            return String(normalized.prefix(limit))
        }

        return normalized.prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func boundedSuffix(_ value: String?, limit: Int) -> String? {
        guard let normalized = normalizedText(value), limit > 0 else {
            return nil
        }

        guard normalized.count > limit else {
            return normalized
        }

        guard limit > 3 else {
            return String(normalized.suffix(limit))
        }

        return "..." + normalized.suffix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

struct ProjectReliabilityStatus: Equatable {
    static let defaultDetailLimit = 180

    var primaryCue: String
    var severity: PlanReliabilityFeedback.Severity
    var countLabel: String
    var actionLabel: String
    var metadata: String?
    var detail: String
    var systemImage: String
    var noticeCount: Int

    var isEmpty: Bool {
        noticeCount == 0
    }

    init(
        feedback: PlanReliabilityFeedback,
        detailLimit: Int = Self.defaultDetailLimit
    ) {
        guard let primaryNotice = Self.primaryNotice(in: feedback.notices) else {
            primaryCue = ""
            severity = .warning
            countLabel = Self.countLabel(for: 0)
            actionLabel = ""
            metadata = nil
            detail = ""
            systemImage = "checkmark.circle"
            noticeCount = 0
            return
        }

        primaryCue = primaryNotice.title
        severity = primaryNotice.severity
        countLabel = Self.countLabel(for: feedback.notices.count)
        actionLabel = primaryNotice.actionLabel
        metadata = primaryNotice.metadata
        detail = Self.boundedDetail(primaryNotice.detail, limit: detailLimit)
        systemImage = primaryNotice.systemImage
        noticeCount = feedback.notices.count
    }

    private static func primaryNotice(in notices: [PlanReliabilityFeedback.Notice]) -> PlanReliabilityFeedback.Notice? {
        notices.enumerated().min { lhs, rhs in
            let leftPriority = priority(for: lhs.element.kind)
            let rightPriority = priority(for: rhs.element.kind)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.offset < rhs.offset
        }?.element
    }

    private static func priority(for kind: PlanReliabilityFeedback.Kind) -> Int {
        switch kind {
        case .rejectedPlan:
            return 0
        case .developBlocked:
            return 1
        case .developFailed:
            return 2
        case .failedVerify:
            return 3
        case .resumeDevelop:
            return 4
        }
    }

    private static func countLabel(for count: Int) -> String {
        "\(count) \(count == 1 ? "cue" : "cues")"
    }

    private static func boundedDetail(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard value.count > limit else { return value }
        guard limit > 3 else { return String(value.prefix(limit)) }

        return value.prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
