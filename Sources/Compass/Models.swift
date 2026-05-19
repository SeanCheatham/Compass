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

struct LessonEdit: Codable, Equatable {
    var find: String
    var replace: String
    var replaceAll: Bool?
}

struct PlanRunResult: Codable, Equatable {
    var state: PlanState
    var lessonEdits: [LessonEdit]

    enum CodingKeys: String, CodingKey {
        case state
        case lessonEdits
    }

    init(state: PlanState, lessonEdits: [LessonEdit] = []) {
        self.state = state
        self.lessonEdits = lessonEdits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(PlanState.self, forKey: .state)
        lessonEdits = try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? []
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
    var lessonEdits: [LessonEdit]

    enum CodingKeys: String, CodingKey {
        case state
        case summary
        case lessonEdits
    }

    init(state: PlanState?, summary: String, lessonEdits: [LessonEdit] = []) {
        self.state = state
        self.summary = summary
        self.lessonEdits = lessonEdits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(PlanState.self, forKey: .state)
        summary = try container.decode(String.self, forKey: .summary)
        lessonEdits = try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? []
    }
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

struct SessionExecutionEnvironmentSnapshot: Codable, Equatable, Identifiable {
    static let phaseLimit = 24
    static let fieldLimit = 120
    static let summaryLimit = 280

    var phase: String
    var phaseIdentifier: String
    var attempt: Int?
    var selectedPreferenceIdentifier: String
    var selectedPreferenceTitle: String
    var effectiveRouteIdentifier: String
    var effectiveRouteTitle: String
    var supportClassificationIdentifier: String
    var visibleSupportTokens: [String]
    var omittedSupportTokenCount: Int
    var imageLabel: String
    var workspaceLabel: String
    var fallbackReason: String?
    var provisioningAvailabilityIdentifier: String?
    var provisioningStatusIdentifier: String?
    var provisioningActionIdentifier: String?

    var id: String {
        [
            phaseIdentifier,
            attempt.map { "attempt-\($0)" } ?? "attempt-none",
            selectedPreferenceIdentifier,
            effectiveRouteIdentifier,
            supportClassificationIdentifier
        ].joined(separator: ".")
    }

    var replacementKey: String {
        "\(phaseIdentifier)#\(attempt.map(String.init) ?? "none")"
    }

    init(
        phase: String,
        attempt: Int? = nil,
        launchPlan: CodexExecutionLaunchPlan,
        provisioningPlan: CodexDevcontainerProvisioningPlan? = nil
    ) {
        let supportReport = launchPlan.devcontainerSupportReport
        let configURL = supportReport?.configURL
        let repoURL = configURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL

        self.phase = Self.sanitizedField(
            phase,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.phaseLimit
        )
        phaseIdentifier = Self.phaseIdentifier(for: phase)
        self.attempt = attempt.flatMap { $0 > 0 ? $0 : nil }
        selectedPreferenceIdentifier = launchPlan.selectedPreference.rawValue
        selectedPreferenceTitle = Self.sanitizedField(
            launchPlan.selectedPreference.title,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        effectiveRouteIdentifier = launchPlan.effectiveRouteIdentifier
        effectiveRouteTitle = Self.sanitizedField(
            launchPlan.effectiveRouteTitle,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        supportClassificationIdentifier = supportReport?.classification.rawValue ?? "not-inspected"
        visibleSupportTokens = (supportReport?.supportTokens ?? [])
            .prefix(CodexDevcontainerSupportReport.maxTokenCount)
            .map {
                Self.sanitizedSupportToken(
                    $0,
                    repoURL: repoURL,
                    configURL: configURL
                )
            }
            .filter { !$0.isEmpty }
        omittedSupportTokenCount = max(0, supportReport?.omittedTokenCount ?? 0)
        imageLabel = Self.sanitizedField(
            launchPlan.imageLabel,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        workspaceLabel = Self.sanitizedField(
            launchPlan.workspaceLabel,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        fallbackReason = Self.sanitizedOptionalField(
            launchPlan.fallbackReason,
            repoURL: repoURL,
            configURL: configURL,
            limit: CodexExecutionLaunchPlan.fallbackReasonLimit
        )

        if let provisioningPlan {
            provisioningAvailabilityIdentifier = provisioningPlan.isAvailable ? "available" : "unavailable"
            provisioningStatusIdentifier = Self.provisioningStatusIdentifier(provisioningPlan.status)
            provisioningActionIdentifier = CodexDevcontainerProvisioningMenuAction.actionIdentifier
        } else {
            provisioningAvailabilityIdentifier = nil
            provisioningStatusIdentifier = nil
            provisioningActionIdentifier = nil
        }
    }

    var routeSummary: String {
        var pieces = [
            "\(phase)\(attempt.map { " attempt \($0)" } ?? "")",
            effectiveRouteTitle,
            "selected \(selectedPreferenceTitle)",
            "support \(supportClassificationIdentifier)"
        ]

        if !imageLabel.isEmpty, imageLabel != "none" {
            pieces.append("image \(imageLabel)")
        }
        if !workspaceLabel.isEmpty {
            pieces.append("workspace \(workspaceLabel)")
        }

        if !visibleSupportTokens.isEmpty {
            var tokenText = visibleSupportTokens.joined(separator: ",")
            if omittedSupportTokenCount > 0 {
                tokenText += ",+\(omittedSupportTokenCount)-more"
            }
            pieces.append("tokens \(tokenText)")
        } else if omittedSupportTokenCount > 0 {
            pieces.append("tokens +\(omittedSupportTokenCount)-more")
        }

        if let fallbackReason, !fallbackReason.isEmpty {
            pieces.append("fallback \(fallbackReason)")
        }

        if let provisioningAvailabilityIdentifier, let provisioningStatusIdentifier {
            pieces.append("provisioning \(provisioningAvailabilityIdentifier)/\(provisioningStatusIdentifier)")
        }

        return Self.boundedField(pieces.joined(separator: "; "), limit: Self.summaryLimit)
    }

    private static func provisioningStatusIdentifier(_ status: CodexDevcontainerProvisioningPlan.Status) -> String {
        switch status {
        case .available:
            return "available"
        case .alreadyPresent:
            return "already-present"
        case .malformed:
            return "malformed"
        }
    }

    private static func phaseIdentifier(for phase: String) -> String {
        let normalized = phase
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let filtered = String(normalized.unicodeScalars.map { scalar in
            if isASCIILetter(scalar) || isASCIIDigit(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "-"
        })
        .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return filtered.isEmpty ? "phase" : String(filtered.prefix(Self.phaseLimit))
    }

    private static func sanitizedSupportToken(
        _ token: String,
        repoURL: URL?,
        configURL: URL?
    ) -> String {
        let sanitized = sanitizedField(
            token,
            repoURL: repoURL,
            configURL: configURL,
            limit: CodexDevcontainerSupportReport.tokenLimit
        )
        guard !sanitized.isEmpty else { return "" }
        guard sanitized.unicodeScalars.allSatisfy(isStableTokenScalar) else {
            return "token"
        }
        return sanitized
    }

    private static func sanitizedOptionalField(
        _ text: String?,
        repoURL: URL?,
        configURL: URL?,
        limit: Int
    ) -> String? {
        let sanitized = sanitizedField(
            text ?? "",
            repoURL: repoURL,
            configURL: configURL,
            limit: limit
        )
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func sanitizedField(
        _ text: String,
        repoURL: URL?,
        configURL: URL?,
        limit: Int
    ) -> String {
        var sanitized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var replacements: [(String, String)] = []
        if let configURL {
            replacements.append((configURL.standardizedFileURL.path, "[devcontainer-json]"))
            replacements.append((configURL.deletingLastPathComponent().standardizedFileURL.path, "[devcontainer-dir]"))
        }
        if let repoURL {
            replacements.append((repoURL.standardizedFileURL.path, "[repo]"))
        }

        for (path, replacement) in replacements.sorted(by: { $0.0.count > $1.0.count }) where !path.isEmpty {
            let pathPrefix = path.hasSuffix("/") ? path : path + "/"
            sanitized = sanitized.replacingOccurrences(of: pathPrefix, with: "\(replacement)/")
            sanitized = sanitized.replacingOccurrences(of: path, with: replacement)
        }

        return boundedField(sanitized, limit: limit)
    }

    private static func boundedField(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isStableTokenScalar(_ scalar: UnicodeScalar) -> Bool {
        isASCIILetter(scalar)
            || isASCIIDigit(scalar)
            || scalar == ":"
            || scalar == "."
            || scalar == "_"
            || scalar == "-"
            || scalar == "@"
            || scalar == "+"
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(Int(scalar.value))
    }
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
    var executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot]

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
            feedback: nil,
            executionEnvironmentSnapshots: []
        )
    }

    static let executionEnvironmentSnapshotLimit = 24

    enum CodingKeys: String, CodingKey {
        case session
        case startedAt
        case endedAt
        case plan
        case verify
        case beforeSha
        case afterSha
        case commits
        case status
        case notes
        case verifyOutput
        case feedback
        case executionEnvironmentSnapshots
    }

    init(
        session: Int,
        startedAt: Double,
        endedAt: Double?,
        plan: String?,
        verify: String?,
        beforeSha: String?,
        afterSha: String?,
        commits: [SessionCommit],
        status: SessionStatus,
        notes: [String],
        verifyOutput: VerifyOutput?,
        feedback: String?,
        executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot] = []
    ) {
        self.session = session
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plan = plan
        self.verify = verify
        self.beforeSha = beforeSha
        self.afterSha = afterSha
        self.commits = commits
        self.status = status
        self.notes = notes
        self.verifyOutput = verifyOutput
        self.feedback = feedback
        self.executionEnvironmentSnapshots = Self.normalizedExecutionEnvironmentSnapshots(
            executionEnvironmentSnapshots
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decodeIfPresent(Int.self, forKey: .session) ?? 0
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt) ?? 0
        endedAt = try container.decodeIfPresent(Double.self, forKey: .endedAt)
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        verify = try container.decodeIfPresent(String.self, forKey: .verify)
        beforeSha = try container.decodeIfPresent(String.self, forKey: .beforeSha)
        afterSha = try container.decodeIfPresent(String.self, forKey: .afterSha)
        commits = try container.decodeIfPresent([SessionCommit].self, forKey: .commits) ?? []
        status = try container.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .planning
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        verifyOutput = try container.decodeIfPresent(VerifyOutput.self, forKey: .verifyOutput)
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
        executionEnvironmentSnapshots = Self.normalizedExecutionEnvironmentSnapshots(
            try container.decodeIfPresent(
                [SessionExecutionEnvironmentSnapshot].self,
                forKey: .executionEnvironmentSnapshots
            ) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(session, forKey: .session)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(verify, forKey: .verify)
        try container.encodeIfPresent(beforeSha, forKey: .beforeSha)
        try container.encodeIfPresent(afterSha, forKey: .afterSha)
        try container.encode(commits, forKey: .commits)
        try container.encode(status, forKey: .status)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(verifyOutput, forKey: .verifyOutput)
        try container.encodeIfPresent(feedback, forKey: .feedback)
        if !executionEnvironmentSnapshots.isEmpty {
            try container.encode(executionEnvironmentSnapshots, forKey: .executionEnvironmentSnapshots)
        }
    }

    var latestExecutionEnvironmentSnapshot: SessionExecutionEnvironmentSnapshot? {
        executionEnvironmentSnapshots.last
    }

    mutating func recordExecutionEnvironmentSnapshot(_ snapshot: SessionExecutionEnvironmentSnapshot) {
        executionEnvironmentSnapshots = Self.recording(
            snapshot,
            in: executionEnvironmentSnapshots
        )
    }

    private static func recording(
        _ snapshot: SessionExecutionEnvironmentSnapshot,
        in snapshots: [SessionExecutionEnvironmentSnapshot]
    ) -> [SessionExecutionEnvironmentSnapshot] {
        var updated = snapshots
        if let index = updated.firstIndex(where: { $0.replacementKey == snapshot.replacementKey }) {
            updated[index] = snapshot
        } else {
            updated.append(snapshot)
        }
        return Array(updated.suffix(Self.executionEnvironmentSnapshotLimit))
    }

    private static func normalizedExecutionEnvironmentSnapshots(
        _ snapshots: [SessionExecutionEnvironmentSnapshot]
    ) -> [SessionExecutionEnvironmentSnapshot] {
        snapshots.reduce(into: []) { partialResult, snapshot in
            partialResult = recording(snapshot, in: partialResult)
        }
    }
}

struct DevelopSummary: Codable, Equatable {
    var status: Status
    var summary: String
    var feedback: String
    var bypassVerify: Bool?
    var lessonEdits: [LessonEdit]

    enum Status: String, Codable {
        case succeeded
        case blocked
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case status
        case summary
        case feedback
        case bypassVerify
        case lessonEdits
    }

    init(
        status: Status,
        summary: String,
        feedback: String,
        bypassVerify: Bool? = nil,
        lessonEdits: [LessonEdit] = []
    ) {
        self.status = status
        self.summary = summary
        self.feedback = feedback
        self.bypassVerify = bypassVerify
        self.lessonEdits = lessonEdits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        summary = try container.decode(String.self, forKey: .summary)
        feedback = try container.decode(String.self, forKey: .feedback)
        bypassVerify = try container.decodeIfPresent(Bool.self, forKey: .bypassVerify)
        lessonEdits = try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? []
    }
}

struct LiveLine: Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var level: Level
    var text: String
    var detail: String?
    var kind: Kind = .message
    var status: Status = .none
    var correlationID: String?
    var completedAt: Date?

    enum Level {
        case info
        case success
        case warning
        case error
        case raw
    }

    enum Kind {
        case message
        case lifecycle
        case command
        case agentMessage
        case fileChange
    }

    enum Status {
        case none
        case running
        case completed
        case failed
    }
}

struct LiveEvent: Equatable {
    var level: LiveLine.Level
    var text: String
    var detail: String?
    var kind: LiveLine.Kind
    var status: LiveLine.Status
    var correlationID: String?

    init(
        level: LiveLine.Level = .info,
        text: String,
        detail: String? = nil,
        kind: LiveLine.Kind = .message,
        status: LiveLine.Status = .none,
        correlationID: String? = nil
    ) {
        self.level = level
        self.text = text
        self.detail = detail
        self.kind = kind
        self.status = status
        self.correlationID = correlationID
    }
}

enum PauseMode: String, Codable, CaseIterable, Identifiable {
    case immediate
    case afterIteration = "after_iteration"

    var id: Self { self }

    var label: String {
        switch self {
        case .immediate:
            return "Pause Now"
        case .afterIteration:
            return "Pause After Iteration"
        }
    }

    var hint: String {
        switch self {
        case .immediate:
            return "Stop before the next phase gate."
        case .afterIteration:
            return "Let the current Plan and Develop finish first."
        }
    }
}

enum LoopPhase: String, CaseIterable {
    case idle = "Idle"
    case planning = "Planning"
    case developing = "Developing"
    case verifying = "Verifying"
    case paused = "Paused"
    case failed = "Failed"
    case succeeded = "Succeeded"
    case cancelled = "Cancelled"
}
