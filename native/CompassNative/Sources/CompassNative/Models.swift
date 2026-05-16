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

    enum CodingKeys: String, CodingKey {
        case plan
        case verify
        case verifyTimeoutMs
        case estimatedDifficulty
    }

    init(
        plan: String,
        verify: String,
        verifyTimeoutMs: Int? = nil,
        estimatedDifficulty: Difficulty? = nil
    ) {
        self.plan = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        self.verify = verify.trimmingCharacters(in: .whitespacesAndNewlines)
        self.verifyTimeoutMs = verifyTimeoutMs
        self.estimatedDifficulty = estimatedDifficulty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let plan = try container.decode(String.self, forKey: .plan)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let verify = try container.decode(String.self, forKey: .verify)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plan.isEmpty, !verify.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "PlanNext requires non-empty plan and verify.")
            )
        }

        let rawTimeout = try container.decodeIfPresent(Int.self, forKey: .verifyTimeoutMs)
        self.plan = plan
        self.verify = verify
        self.verifyTimeoutMs = rawTimeout.flatMap { $0 > 0 ? $0 : nil }
        self.estimatedDifficulty = try container.decodeIfPresent(Difficulty.self, forKey: .estimatedDifficulty)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plan, forKey: .plan)
        try container.encode(verify, forKey: .verify)
        try container.encodeIfPresent(verifyTimeoutMs, forKey: .verifyTimeoutMs)
        try container.encodeIfPresent(estimatedDifficulty, forKey: .estimatedDifficulty)
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

    enum CodingKeys: String, CodingKey {
        case completed
        case immediate
        case midTerm
        case longTerm
    }

    init(completed: [String], immediate: PlanNext?, midTerm: String, longTerm: String) {
        self.completed = completed
        self.immediate = immediate
        self.midTerm = midTerm
        self.longTerm = longTerm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let completedValues = try container.decode([LossyString].self, forKey: .completed)
        completed = completedValues.compactMap(\.value)
        immediate = try container.decodeIfPresent(PlanNext.self, forKey: .immediate)
        midTerm = try container.decodeIfPresent(String.self, forKey: .midTerm) ?? ""
        longTerm = try container.decodeIfPresent(String.self, forKey: .longTerm) ?? ""
    }
}

private struct LossyString: Decodable {
    var value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(String.self)
    }
}

struct ReflectSummary: Codable, Equatable {
    var state: PlanState?
    var summary: String
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
