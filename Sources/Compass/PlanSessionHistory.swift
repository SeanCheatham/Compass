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
