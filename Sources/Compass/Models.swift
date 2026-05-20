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

struct SessionMutationTestingExecution: Codable, Equatable, Identifiable {
    static let fieldLimit = 120
    static let commandLimit = CodexMutationTestingPlan.commandMaxCharacters
    static let outputTailLimit = 2_000

    var readinessIdentifier: String
    var statusIdentifier: String
    var routeIdentifier: String
    var languageIdentifier: String
    var seedCommandLabel: String
    var exitCode: Int?
    var startedAt: Double
    var endedAt: Double
    var outputTail: String

    var id: String {
        [
            readinessIdentifier,
            statusIdentifier,
            routeIdentifier,
            languageIdentifier,
            String(Int(startedAt)),
            exitCode.map(String.init) ?? "none"
        ].joined(separator: ".")
    }

    init(
        readiness: CodexMutationTestingPlan,
        exitCode: Int?,
        startedAt: Double,
        endedAt: Double,
        outputTail: String,
        launchPlan: CodexExecutionLaunchPlan
    ) {
        readinessIdentifier = Self.boundedField(
            readiness.identifier,
            limit: Self.fieldLimit
        )
        statusIdentifier = exitCode == 0 ? "succeeded" : "failed"
        routeIdentifier = Self.boundedField(
            readiness.routeIdentifier,
            limit: Self.fieldLimit
        )
        languageIdentifier = Self.boundedField(
            readiness.languageIdentifier,
            limit: Self.fieldLimit
        )
        seedCommandLabel = Self.boundedField(
            readiness.seedCommandLabel,
            limit: Self.commandLimit
        )
        self.exitCode = exitCode
        self.startedAt = max(0, startedAt)
        self.endedAt = max(self.startedAt, endedAt)
        self.outputTail = CodexMutationTestingMetadataSanitizer.sanitizedOutputTail(
            outputTail,
            launchPlan: launchPlan,
            limit: Self.outputTailLimit
        )
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
}

struct SessionExecutionEnvironmentSnapshot: Codable, Equatable, Identifiable {
    static let phaseLimit = 24
    static let fieldLimit = 120
    static let summaryLimit = 280
    /// Stable identifier the snapshot reports for the VM-build action surface. Retained as a
    /// constant so consumers don't grow another magic string.
    static let vmBuildActionIdentifier = "shared-vm.build"

    var phase: String
    var phaseIdentifier: String
    var attempt: Int?
    var selectedPreferenceIdentifier: String
    var selectedPreferenceTitle: String
    var effectiveRouteIdentifier: String
    var effectiveRouteTitle: String
    /// Captures the shared VM readiness classification. Field name retained from the previous
    /// devcontainer support classification slot so on-disk snapshots remain decodable.
    var supportClassificationIdentifier: String
    /// Retained for forward-compatibility with the previous snapshot schema; always empty
    /// for shared-VM-era snapshots.
    var visibleSupportTokens: [String]
    var omittedSupportTokenCount: Int
    var imageLabel: String
    var workspaceLabel: String
    var fallbackReason: String?
    /// VM-build availability ("available" when the bundle is provisioned and ready to use,
    /// "unavailable" otherwise). Field name retained from the devcontainer provisioning slot.
    var provisioningAvailabilityIdentifier: String?
    /// VM-build status (mirrors `SharedCompassVMReadiness` cases). Field name retained.
    var provisioningStatusIdentifier: String?
    /// VM-build action identifier (the menu action that surfaces "Build VM"). Field name retained.
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
        launchPlan: CodexExecutionLaunchPlan
    ) {
        self.phase = Self.sanitizedField(phase, limit: Self.phaseLimit)
        phaseIdentifier = Self.phaseIdentifier(for: phase)
        self.attempt = attempt.flatMap { $0 > 0 ? $0 : nil }
        selectedPreferenceIdentifier = launchPlan.selectedPreference.rawValue
        selectedPreferenceTitle = Self.sanitizedField(
            launchPlan.selectedPreference.title,
            limit: Self.fieldLimit
        )
        effectiveRouteIdentifier = launchPlan.effectiveRouteIdentifier
        effectiveRouteTitle = Self.sanitizedField(
            launchPlan.effectiveRouteTitle,
            limit: Self.fieldLimit
        )
        supportClassificationIdentifier = Self.vmSupportClassification(launchPlan.vmReadiness)
        visibleSupportTokens = []
        omittedSupportTokenCount = 0
        imageLabel = Self.sanitizedField(launchPlan.imageLabel, limit: Self.fieldLimit)
        workspaceLabel = Self.sanitizedField(launchPlan.workspaceLabel, limit: Self.fieldLimit)
        fallbackReason = Self.sanitizedOptionalField(
            launchPlan.fallbackReason,
            limit: CodexExecutionLaunchPlan.fallbackReasonLimit
        )

        if let readiness = launchPlan.vmReadiness {
            provisioningAvailabilityIdentifier = Self.vmAvailability(for: readiness)
            provisioningStatusIdentifier = Self.vmStatusIdentifier(for: readiness)
            provisioningActionIdentifier = Self.vmBuildActionIdentifier
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
            "vm \(supportClassificationIdentifier)"
        ]

        if !imageLabel.isEmpty, imageLabel != "none" {
            pieces.append("image \(imageLabel)")
        }
        if !workspaceLabel.isEmpty {
            pieces.append("workspace \(workspaceLabel)")
        }

        if let fallbackReason, !fallbackReason.isEmpty {
            pieces.append("fallback \(fallbackReason)")
        }

        if let provisioningAvailabilityIdentifier, let provisioningStatusIdentifier {
            pieces.append("vm-build \(provisioningAvailabilityIdentifier)/\(provisioningStatusIdentifier)")
        }

        return Self.boundedField(pieces.joined(separator: "; "), limit: Self.summaryLimit)
    }

    private static func vmSupportClassification(_ readiness: SharedCompassVMReadiness?) -> String {
        guard let readiness else { return "not-inspected" }
        switch readiness {
        case .unavailable:
            return "unavailable"
        case .notProvisioned:
            return "not-provisioned"
        case .downloadingIPSW:
            return "downloading-ipsw"
        case .installing:
            return "installing"
        case .guestPrepping:
            return "guest-prepping"
        case .codexLoginPending:
            return "codex-login-pending"
        case .ready:
            return "ready"
        case .error:
            return "error"
        }
    }

    private static func vmAvailability(for readiness: SharedCompassVMReadiness) -> String {
        switch readiness {
        case .ready:
            return "available"
        default:
            return "unavailable"
        }
    }

    private static func vmStatusIdentifier(for readiness: SharedCompassVMReadiness) -> String {
        vmSupportClassification(readiness)
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

    private static func sanitizedOptionalField(
        _ text: String?,
        limit: Int
    ) -> String? {
        let sanitized = sanitizedField(text ?? "", limit: limit)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func sanitizedField(
        _ text: String,
        limit: Int
    ) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    var mutationTestingExecutions: [SessionMutationTestingExecution]

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
            executionEnvironmentSnapshots: [],
            mutationTestingExecutions: []
        )
    }

    static let executionEnvironmentSnapshotLimit = 24
    static let mutationTestingExecutionLimit = 12

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
        case mutationTestingExecutions
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
        executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot] = [],
        mutationTestingExecutions: [SessionMutationTestingExecution] = []
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
        self.mutationTestingExecutions = Self.normalizedMutationTestingExecutions(
            mutationTestingExecutions
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
        mutationTestingExecutions = Self.normalizedMutationTestingExecutions(
            try container.decodeIfPresent(
                [SessionMutationTestingExecution].self,
                forKey: .mutationTestingExecutions
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
        if !mutationTestingExecutions.isEmpty {
            try container.encode(mutationTestingExecutions, forKey: .mutationTestingExecutions)
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

    mutating func recordMutationTestingExecution(_ execution: SessionMutationTestingExecution) {
        mutationTestingExecutions = Self.normalizedMutationTestingExecutions(
            mutationTestingExecutions + [execution]
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

    private static func normalizedMutationTestingExecutions(
        _ executions: [SessionMutationTestingExecution]
    ) -> [SessionMutationTestingExecution] {
        Array(executions.suffix(Self.mutationTestingExecutionLimit))
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
