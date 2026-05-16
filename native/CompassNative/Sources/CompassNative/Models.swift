import Foundation

struct PlanNext: Codable, Equatable {
    var plan: String
    var verify: String
    var verifyTimeoutMs: Int?
    var estimatedDifficulty: Difficulty?

    enum Difficulty: String, Codable, CaseIterable {
        case low
        case medium
        case high
    }
}

struct PlanState: Codable, Equatable {
    var completed: [String]
    var immediate: PlanNext?
    var midTerm: String
    var longTerm: String

    static let empty = PlanState(
        completed: [],
        immediate: nil,
        midTerm: "",
        longTerm: ""
    )
}

struct SessionCommit: Codable, Identifiable, Equatable {
    var id: String { sha }
    var sha: String
    var short: String
    var subject: String
}

struct VerifyOutput: Codable, Equatable {
    var command: String
    var exitCode: Int?
    var tail: String
}

enum SessionStatus: String, Codable, CaseIterable {
    case planning
    case awaitingApproval = "awaiting_approval"
    case developing
    case succeeded
    case failed
    case cancelled
    case rejectedByPlan = "rejected_by_plan"
    case skipped
}

struct SessionRecord: Codable, Identifiable, Equatable {
    var id: Int { session }
    var session: Int
    var startedAt: Double
    var endedAt: Double?
    var plan: String?
    var verify: String?
    var beforeSha: String?
    var afterSha: String?
    var commits: [SessionCommit]
    var status: SessionStatus
    var notes: [String]
    var verifyOutput: VerifyOutput?
    var feedback: String?

    static func started(_ number: Int) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Date().timeIntervalSince1970 * 1000,
            endedAt: nil,
            plan: nil,
            verify: nil,
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .planning,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }
}

struct DevelopSummary: Codable, Equatable {
    var status: Status
    var summary: String
    var feedback: String
    var bypassVerify: Bool?

    enum Status: String, Codable {
        case succeeded
        case blocked
        case failed
    }
}

struct ActivityLine: Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var level: Level
    var text: String

    enum Level {
        case info
        case success
        case warning
        case error
        case raw
    }
}

enum LoopPhase: String {
    case idle = "Idle"
    case planning = "Planning"
    case developing = "Developing"
    case verifying = "Verifying"
    case failed = "Failed"
    case succeeded = "Succeeded"
    case cancelled = "Cancelled"
}
