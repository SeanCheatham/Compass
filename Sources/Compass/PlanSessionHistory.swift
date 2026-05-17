import Foundation

struct PlanSessionHistoryItem: Identifiable, Equatable {
    struct FailedVerify: Equatable {
        var command: String
        var exitCodeText: String
        var tail: String
    }

    var id: Int { sessionNumber }

    var sessionNumber: Int
    var status: SessionStatus
    var statusText: String
    var startedAt: Date
    var planExcerpt: String?
    var verifyCommand: String?
    var feedback: String?
    var notes: [String]
    var commits: [SessionCommit]
    var failedVerify: FailedVerify?
}

enum PlanSessionHistoryFilter: String, CaseIterable, Identifiable, Equatable, Hashable {
    case all
    case attention
    case activePaused
    case failedRejected
    case completedFinished

    struct Option: Identifiable, Equatable {
        var filter: PlanSessionHistoryFilter
        var count: Int

        var id: PlanSessionHistoryFilter.ID {
            filter.id
        }
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .attention:
            return "Attention"
        case .activePaused:
            return "Active/Paused"
        case .failedRejected:
            return "Failed/Rejected"
        case .completedFinished:
            return "Completed"
        }
    }

    var emptyStateName: String {
        switch self {
        case .all:
            return "runs"
        case .attention:
            return "attention runs"
        case .activePaused:
            return "active or paused runs"
        case .failedRejected:
            return "failed or rejected runs"
        case .completedFinished:
            return "completed runs"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .attention:
            return "exclamationmark.triangle"
        case .activePaused:
            return "playpause.circle"
        case .failedRejected:
            return "xmark.octagon"
        case .completedFinished:
            return "checkmark.circle"
        }
    }

    static func options(
        for items: [PlanSessionHistoryItem],
        runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
    ) -> [Option] {
        allCases.map { filter in
            Option(
                filter: filter,
                count: items.filter { item in
                    filter.matches(item, runCue: runCues[item.sessionNumber])
                }.count
            )
        }
    }

    func matches(
        _ item: PlanSessionHistoryItem,
        runCue: PlanReliabilityFeedback.RunCue? = nil
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .attention:
            return runCue != nil
        case .activePaused:
            return item.status == .planning
                || item.status == .developing
                || item.status == .awaitingApproval
                || runCue?.severity == .paused
        case .failedRejected:
            return item.status == .failed
                || item.status == .rejectedByPlan
                || runCue?.kind == .rejectedPlan
                || runCue?.kind == .developFailed
                || runCue?.kind == .failedVerify
                || runCue?.kind == .dirtyWorktree
                || runCue?.kind == .promotionFailed
        case .completedFinished:
            return item.status == .succeeded
                || item.status == .cancelled
                || item.status == .skipped
        }
    }
}

struct PlanSessionHistoryDisplay: Equatable {
    enum Mode: Equatable {
        case recent
        case all
    }

    static let defaultRecentLimit = 8

    var mode: Mode
    var filter: PlanSessionHistoryFilter
    var recentLimit: Int
    var filterOptions: [PlanSessionHistoryFilter.Option]
    var visibleItems: [PlanSessionHistoryItem]
    var unfilteredTotalCount: Int
    var totalCount: Int
    var hiddenCount: Int
    var hiddenStatusSummary: String?
    var shouldOfferModeToggle: Bool
    var countSummary: String

    var visibleCount: Int {
        visibleItems.count
    }

    init(
        items: [PlanSessionHistoryItem],
        mode: Mode = .recent,
        recentLimit: Int = Self.defaultRecentLimit,
        filter: PlanSessionHistoryFilter = .all,
        runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
    ) {
        let boundedRecentLimit = max(0, recentLimit)
        let filterOptions = PlanSessionHistoryFilter.options(for: items, runCues: runCues)
        let filteredItems = items.filter { item in
            filter.matches(item, runCue: runCues[item.sessionNumber])
        }

        let visibleItems: [PlanSessionHistoryItem]
        switch mode {
        case .recent:
            visibleItems = Array(filteredItems.prefix(boundedRecentLimit))
        case .all:
            visibleItems = filteredItems
        }

        let hiddenItems = Array(filteredItems.dropFirst(visibleItems.count))
        let shouldOfferModeToggle = filteredItems.count > boundedRecentLimit

        self.mode = mode
        self.filter = filter
        self.recentLimit = boundedRecentLimit
        self.filterOptions = filterOptions
        self.visibleItems = visibleItems
        unfilteredTotalCount = items.count
        totalCount = filteredItems.count
        hiddenCount = hiddenItems.count
        hiddenStatusSummary = Self.hiddenStatusSummary(for: hiddenItems)
        self.shouldOfferModeToggle = shouldOfferModeToggle
        countSummary = Self.countSummary(
            totalCount: filteredItems.count,
            visibleCount: visibleItems.count,
            hiddenCount: hiddenItems.count,
            mode: mode,
            shouldOfferModeToggle: shouldOfferModeToggle,
            filter: filter
        )
    }

    private static func countSummary(
        totalCount: Int,
        visibleCount: Int,
        hiddenCount: Int,
        mode: Mode,
        shouldOfferModeToggle: Bool,
        filter: PlanSessionHistoryFilter
    ) -> String {
        guard totalCount > 0 else {
            return filter == .all ? "0 runs" : "0 matching runs"
        }

        if hiddenCount > 0 {
            let suffix = filter == .all ? "" : " matching"
            return "Showing latest \(visibleCount) of \(totalCount)\(suffix)"
        }

        if mode == .all, shouldOfferModeToggle {
            let suffix = filter == .all ? "" : " matching"
            return "Showing all \(totalCount)\(suffix)"
        }

        if filter != .all {
            return "\(totalCount) matching \(runWord(for: totalCount))"
        }

        return "\(totalCount) \(runWord(for: totalCount))"
    }

    private static func hiddenStatusSummary(for items: [PlanSessionHistoryItem]) -> String? {
        guard !items.isEmpty else {
            return nil
        }

        var orderedStatuses: [String] = []
        var counts: [String: Int] = [:]
        for item in items {
            let statusText = item.statusText.lowercased()
            if counts[statusText] == nil {
                orderedStatuses.append(statusText)
            }
            counts[statusText, default: 0] += 1
        }

        return orderedStatuses.compactMap { statusText in
            guard let count = counts[statusText] else {
                return nil
            }
            return "\(count) \(statusText)"
        }
        .joined(separator: ", ")
    }

    static func runWord(for count: Int) -> String {
        count == 1 ? "run" : "runs"
    }
}

enum PlanSessionHistory {
    static let defaultPlanExcerptLimit = 280

    static func displayItems(
        for sessions: [SessionRecord],
        planExcerptLimit: Int = defaultPlanExcerptLimit
    ) -> [PlanSessionHistoryItem] {
        sessions
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.session > rhs.session
                }
                return lhs.startedAt > rhs.startedAt
            }
            .map { session in
                PlanSessionHistoryItem(
                    sessionNumber: session.session,
                    status: session.status,
                    statusText: statusText(for: session.status),
                    startedAt: Date(timeIntervalSince1970: session.startedAt / 1000),
                    planExcerpt: excerpt(session.plan, limit: planExcerptLimit),
                    verifyCommand: nonEmpty(session.verify),
                    feedback: nonEmpty(session.feedback),
                    notes: session.notes,
                    commits: session.commits,
                    failedVerify: failedVerify(from: session)
                )
            }
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

    private static func excerpt(_ value: String?, limit: Int) -> String? {
        guard limit > 0,
              let normalized = value?
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " "),
              !normalized.isEmpty else {
            return nil
        }
        guard normalized.count > limit else {
            return normalized
        }
        guard limit > 3 else {
            return String(normalized.prefix(limit))
        }
        return String(normalized.prefix(limit - 3))
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func failedVerify(from session: SessionRecord) -> PlanSessionHistoryItem.FailedVerify? {
        guard let output = session.verifyOutput,
              let tail = nonEmpty(output.tail) else {
            return nil
        }
        return PlanSessionHistoryItem.FailedVerify(
            command: nonEmpty(output.command) ?? nonEmpty(session.verify) ?? "verify",
            exitCodeText: output.exitCode.map { "exit \($0)" } ?? "exit unknown",
            tail: tail
        )
    }
}
