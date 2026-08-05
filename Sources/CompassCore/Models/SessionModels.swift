import Foundation

public struct SessionCommit: Codable, Identifiable, Equatable {
  public var id: String { sha }
  public var sha: String
  public var short: String
  public var subject: String

  public init(sha: String, short: String, subject: String) {
    self.sha = sha
    self.short = short
    self.subject = subject
  }
}

public struct VerifyOutput: Codable, Equatable {
  public var command: String
  public var exitCode: Int?
  public var tail: String

  public init(command: String, exitCode: Int? = nil, tail: String) {
    self.command = command
    self.exitCode = exitCode
    self.tail = tail
  }
}

public struct SessionExecutionEnvironmentSnapshot: Codable, Equatable, Identifiable {
  public static let phaseLimit = 24
  public static let fieldLimit = 120
  public static let summaryLimit = 280

  public var phase: String
  public var phaseIdentifier: String
  public var attempt: Int?
  public var selectedPreferenceIdentifier: String
  public var selectedPreferenceTitle: String
  public var effectiveRouteIdentifier: String
  public var effectiveRouteTitle: String
  /// Captures the runtime readiness classification. Field name retained so on-disk
  /// snapshots remain decodable.
  public var supportClassificationIdentifier: String
  /// Retained for backward-compatibility with the previous snapshot schema; always empty.
  public var visibleSupportTokens: [String]
  public var omittedSupportTokenCount: Int
  public var imageLabel: String
  public var workspaceLabel: String
  public var fallbackReason: String?
  /// Runtime availability. Field name retained from the old provisioning slot.
  public var provisioningAvailabilityIdentifier: String?
  /// Runtime status. Field name retained.
  public var provisioningStatusIdentifier: String?
  /// Runtime action identifier. Field name retained.
  public var provisioningActionIdentifier: String?

  public var id: String {
    [
      phaseIdentifier,
      attempt.map { "attempt-\($0)" } ?? "attempt-none",
      selectedPreferenceIdentifier,
      effectiveRouteIdentifier,
      supportClassificationIdentifier,
    ].joined(separator: ".")
  }

  public var replacementKey: String {
    "\(phaseIdentifier)#\(attempt.map(String.init) ?? "none")"
  }

  public init(
    phase: String,
    attempt: Int? = nil,
    launchPlan: AgentExecutionLaunchPlan
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
    supportClassificationIdentifier =
      launchPlan.isVMRoute ? "macos-vm" : "host"
    visibleSupportTokens = []
    omittedSupportTokenCount = 0
    imageLabel = Self.sanitizedField(launchPlan.imageLabel, limit: Self.fieldLimit)
    workspaceLabel = Self.sanitizedField(launchPlan.workspaceLabel, limit: Self.fieldLimit)
    fallbackReason = Self.sanitizedOptionalField(
      launchPlan.fallbackReason,
      limit: AgentExecutionLaunchPlan.fallbackReasonLimit
    )
    provisioningAvailabilityIdentifier = launchPlan.isVMRoute ? "available" : nil
    provisioningStatusIdentifier = launchPlan.isVMRoute ? "ready" : nil
    provisioningActionIdentifier = nil
  }

  public var routeSummary: String {
    var pieces = [
      "\(phase)\(attempt.map { " attempt \($0)" } ?? "")",
      effectiveRouteTitle,
      "selected \(selectedPreferenceTitle)",
      "runtime \(supportClassificationIdentifier)",
    ]

    if !imageLabel.isEmpty, imageLabel != "none" {
      pieces.append("image \(imageLabel)")
    }
    if !workspaceLabel.isEmpty {
      pieces.append("workspace \(workspaceLabel)")
    }

    if let fallbackReason, !fallbackReason.isEmpty {
      pieces.append("fallback \(AgentExecutionLaunchPlan.userFacingFallbackReason(fallbackReason))")
    }

    if let provisioningAvailabilityIdentifier, let provisioningStatusIdentifier {
      pieces.append(
        "runtime \(provisioningAvailabilityIdentifier)/\(provisioningStatusIdentifier)")
    }

    return Self.boundedField(pieces.joined(separator: "; "), limit: Self.summaryLimit)
  }

  private static func phaseIdentifier(for phase: String) -> String {
    let normalized =
      phase
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    let filtered = String(
      normalized.unicodeScalars.map { scalar in
        if isASCIILetter(scalar) || isASCIIDigit(scalar) || scalar == "-" || scalar == "_" {
          return Character(scalar)
        }
        return "-"
      }
    )
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
    let sanitized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return boundedField(sanitized, limit: limit)
  }

  private static func boundedField(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
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

public struct AgentRunTokenUsage: Codable, Equatable, Sendable {
  public var inputTokens: Int
  public var outputTokens: Int
  public var totalTokens: Int
  public var estimatedTokens: Int
  public var streamedUsageAvailable: Bool
  public var compactionCount: Int
  public var summaryTokens: Int
  public var retryCount: Int
  public var durationMs: Int?

  public init(
    inputTokens: Int = 0,
    outputTokens: Int = 0,
    totalTokens: Int = 0,
    estimatedTokens: Int = 0,
    streamedUsageAvailable: Bool = false,
    compactionCount: Int = 0,
    summaryTokens: Int = 0,
    retryCount: Int = 0,
    durationMs: Int? = nil
  ) {
    self.inputTokens = max(0, inputTokens)
    self.outputTokens = max(0, outputTokens)
    self.totalTokens = max(0, totalTokens)
    self.estimatedTokens = max(0, estimatedTokens)
    self.streamedUsageAvailable = streamedUsageAvailable
    self.compactionCount = max(0, compactionCount)
    self.summaryTokens = max(0, summaryTokens)
    self.retryCount = max(0, retryCount)
    self.durationMs = durationMs.map { max(0, $0) }
  }

  public var hasUsage: Bool {
    totalTokens > 0 || inputTokens > 0 || outputTokens > 0
      || estimatedTokens > 0 || compactionCount > 0 || summaryTokens > 0
  }

  public var usesEstimate: Bool {
    estimatedTokens > 0 || !streamedUsageAvailable
  }

  public mutating func recordTurn(
    inputTokens: Int,
    outputTokens: Int,
    totalTokens: Int,
    isEstimated: Bool,
    streamedUsageAvailable: Bool
  ) {
    let normalizedInput = max(0, inputTokens)
    let normalizedOutput = max(0, outputTokens)
    let normalizedTotal = max(
      0, totalTokens == 0 ? normalizedInput + normalizedOutput : totalTokens)
    self.inputTokens += normalizedInput
    self.outputTokens += normalizedOutput
    self.totalTokens += normalizedTotal
    if isEstimated {
      estimatedTokens += normalizedTotal
    }
    self.streamedUsageAvailable = self.streamedUsageAvailable || streamedUsageAvailable
  }

  public mutating func recordCompaction(summaryTokens: Int) {
    compactionCount += 1
    self.summaryTokens += max(0, summaryTokens)
  }

  public static func estimated(
    inputCharacters: Int,
    outputCharacters: Int,
    charsPerToken: Int = 4,
    retryCount: Int = 0
  ) -> AgentRunTokenUsage {
    let input = estimateTokens(characters: inputCharacters, charsPerToken: charsPerToken)
    let output = estimateTokens(characters: outputCharacters, charsPerToken: charsPerToken)
    return AgentRunTokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: input + output,
      estimatedTokens: input + output,
      streamedUsageAvailable: false,
      retryCount: retryCount
    )
  }

  public static func estimateTokens(characters: Int, charsPerToken: Int) -> Int {
    guard characters > 0 else { return 0 }
    let divisor = max(1, charsPerToken)
    return (characters + divisor - 1) / divisor
  }
}

public struct SessionPhaseTokenUsage: Codable, Equatable, Sendable, Identifiable {
  public var id: String {
    [
      phase,
      proofActionKind ?? "",
      outcome ?? "",
      String(createdAt),
    ]
    .joined(separator: "|")
  }

  public var phase: String
  public var inputTokens: Int
  public var outputTokens: Int
  public var totalTokens: Int
  public var estimatedTokens: Int
  public var streamedUsageAvailable: Bool
  public var compactionCount: Int
  public var summaryTokens: Int
  public var proofActionKind: String?
  public var outcome: String?
  public var retryCount: Int
  public var durationMs: Int?
  public var createdAt: Double

  public init(
    phase: String,
    usage: AgentRunTokenUsage,
    proofActionKind: String? = nil,
    outcome: String? = nil,
    createdAt: Date = Date()
  ) {
    self.phase = phase
    inputTokens = usage.inputTokens
    outputTokens = usage.outputTokens
    totalTokens = usage.totalTokens
    estimatedTokens = usage.estimatedTokens
    streamedUsageAvailable = usage.streamedUsageAvailable
    compactionCount = usage.compactionCount
    summaryTokens = usage.summaryTokens
    self.proofActionKind = Self.normalizedOptional(proofActionKind, limit: 80)
    self.outcome = Self.normalizedOptional(outcome, limit: 80)
    retryCount = usage.retryCount
    durationMs = usage.durationMs
    self.createdAt = createdAt.timeIntervalSince1970 * 1000
  }

  public var usesEstimate: Bool {
    estimatedTokens > 0 || !streamedUsageAvailable
  }

  public var compactLabel: String {
    let suffix = usesEstimate ? " est." : ""
    return "\(Self.formatTokens(totalTokens)) tokens\(suffix)"
  }

  private static func normalizedOptional(_ value: String?, limit: Int) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit - 3)) + "..."
  }

  public static func formatTokens(_ count: Int) -> String {
    let count = max(0, count)
    if count >= 1_000_000 {
      let value = Double(count) / 1_000_000
      return String(format: "%.1fM", value)
    }
    if count >= 1_000 {
      let value = Double(count) / 1_000
      return String(format: "%.1fk", value)
    }
    return "\(count)"
  }
}

public struct SessionTokenSummary: Codable, Equatable, Sendable {
  public var phases: [SessionPhaseTokenUsage]

  public init(phases: [SessionPhaseTokenUsage] = []) {
    self.phases = phases
  }

  public var isEmpty: Bool { phases.isEmpty }
  public var totalInputTokens: Int { phases.reduce(0) { $0 + $1.inputTokens } }
  public var totalOutputTokens: Int { phases.reduce(0) { $0 + $1.outputTokens } }
  public var totalTokens: Int { phases.reduce(0) { $0 + $1.totalTokens } }
  public var estimatedTokens: Int { phases.reduce(0) { $0 + $1.estimatedTokens } }
  public var compactionCount: Int { phases.reduce(0) { $0 + $1.compactionCount } }
  public var summaryTokens: Int { phases.reduce(0) { $0 + $1.summaryTokens } }
  public var retryCount: Int { phases.reduce(0) { $0 + $1.retryCount } }
  public var usesEstimate: Bool { phases.contains { $0.usesEstimate } }

  public var latestProofActionKind: String? {
    phases.reversed().compactMap(\.proofActionKind).first
  }

  public var compactLabel: String? {
    guard !isEmpty else { return nil }
    let suffix = usesEstimate ? " est." : ""
    return "\(SessionPhaseTokenUsage.formatTokens(totalTokens)) tokens\(suffix)"
  }

  public mutating func record(_ usage: SessionPhaseTokenUsage) {
    guard usage.totalTokens > 0 || usage.compactionCount > 0 else { return }
    phases.append(usage)
  }
}

public enum SessionStatus: String, Codable, CaseIterable {
  case planning
  case awaitingApproval = "awaiting_approval"
  case developing
  case succeeded
  case failed
  case cancelled
  case rejectedByPlan = "rejected_by_plan"
  case skipped
}

public struct SessionRecord: Codable, Identifiable, Equatable {
  public var id: Int { session }
  public var session: Int
  public var startedAt: Double
  public var endedAt: Double?
  public var plan: String?
  public var verify: String?
  public var beforeSha: String?
  public var afterSha: String?
  public var commits: [SessionCommit]
  public var status: SessionStatus
  public var notes: [String]
  public var verifyOutput: VerifyOutput?
  public var feedback: String?
  public var executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot]
  public var tokenSummary: SessionTokenSummary

  public static func started(_ number: Int) -> SessionRecord {
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
      tokenSummary: SessionTokenSummary()
    )
  }

  public static let executionEnvironmentSnapshotLimit = 24

  public enum CodingKeys: String, CodingKey {
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
    case tokenSummary
  }

  public init(
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
    tokenSummary: SessionTokenSummary = SessionTokenSummary()
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
    self.tokenSummary = tokenSummary
  }

  public init(from decoder: Decoder) throws {
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
    tokenSummary =
      try container.decodeIfPresent(SessionTokenSummary.self, forKey: .tokenSummary)
      ?? SessionTokenSummary()
  }

  public func encode(to encoder: Encoder) throws {
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
    if !tokenSummary.isEmpty {
      try container.encode(tokenSummary, forKey: .tokenSummary)
    }
  }

  public var latestExecutionEnvironmentSnapshot: SessionExecutionEnvironmentSnapshot? {
    executionEnvironmentSnapshots.last
  }

  public mutating func recordExecutionEnvironmentSnapshot(
    _ snapshot: SessionExecutionEnvironmentSnapshot
  ) {
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

public struct DevelopSummary: Codable, Equatable {
  public var status: Status
  public var summary: String
  public var feedback: String
  public var bypassVerify: Bool?
  public var lessonEdits: [LessonEdit]

  public enum Status: String, Codable {
    case succeeded
    case blocked
    case failed

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let rawValue = try container.decode(String.self)
      switch FlexibleModelDecoder.normalizedIdentifier(rawValue) {
      case "succeeded", "success", "successful", "complete", "completed", "done":
        self = .succeeded
      case "blocked", "stuck":
        self = .blocked
      case "failed", "failure", "error":
        self = .failed
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "DevelopSummary status must be succeeded, blocked, or failed."
          )
        )
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  public enum CodingKeys: String, CodingKey {
    case status
    case result
    case outcome
    case completionStatus
    case completionStatusSnake = "completion_status"
    case summary
    case description
    case details
    case feedback
    case handoff
    case nextPlanHandoff
    case nextPlanHandoffSnake = "next_plan_handoff"
    case bypassVerify
    case bypassVerifySnake = "bypass_verify"
    case verifyBypass
    case verifyBypassSnake = "verify_bypass"
    case skipVerify
    case skipVerifySnake = "skip_verify"
    case skipVerification
    case skipVerificationSnake = "skip_verification"
    case verificationBypassed
    case verificationBypassedSnake = "verification_bypassed"
    case lessonEdits
    case lessonEditsSnake = "lesson_edits"
  }

  public init(
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

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = try FlexibleModelDecoder.decodeRequiredValue(
      from: container,
      preferredKey: .status,
      aliases: [.result, .outcome, .completionStatus, .completionStatusSnake],
      fieldName: "status"
    )
    summary = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .summary,
      aliases: [.description, .details],
      fieldName: "summary"
    )
    feedback = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .feedback,
      aliases: [.handoff, .nextPlanHandoff, .nextPlanHandoffSnake],
      fieldName: "feedback"
    )
    bypassVerify = Self.decodeBypassVerify(from: container)
    lessonEdits =
      try FlexibleModelDecoder.decodeLessonEditsIfPresent(
        from: container,
        preferredKey: .lessonEdits,
        aliases: [.lessonEditsSnake]
      ) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(status, forKey: .status)
    try container.encode(summary, forKey: .summary)
    try container.encode(feedback, forKey: .feedback)
    try container.encodeIfPresent(bypassVerify, forKey: .bypassVerify)
    try container.encode(lessonEdits, forKey: .lessonEdits)
  }

  private static func decodeBypassVerify(
    from container: KeyedDecodingContainer<CodingKeys>
  ) -> Bool? {
    for key in [
      CodingKeys.bypassVerify,
      .bypassVerifySnake,
      .verifyBypass,
      .verifyBypassSnake,
      .skipVerify,
      .skipVerifySnake,
      .skipVerification,
      .skipVerificationSnake,
      .verificationBypassed,
      .verificationBypassedSnake,
    ] {
      if let value = FlexibleModelDecoder.decodeBool(from: container, forKey: key) {
        return value
      }
    }
    return nil
  }
}

/// Result of one Critic pass — Compass's adversarial-review gate that
/// runs after Develop's post-checks pass. `verdict == .approve` ends the
/// iteration; `.requestChanges` causes Develop to re-run with the
/// critic's `feedback` appended to its prior-issues list. The outer
/// Develop loop bounds the number of critic-driven retries.
public struct CriticVerdict: Codable, Equatable {
  public enum Verdict: String, Codable {
    case approve
    case requestChanges = "request_changes"

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let rawValue = try container.decode(String.self)
      switch FlexibleModelDecoder.normalizedIdentifier(rawValue) {
      case "approve", "approved":
        self = .approve
      case "request_changes", "requestchanges", "changes_requested", "change_requested",
        "changes_required", "needs_changes", "needs_work", "needswork", "changes", "revise",
        "reject", "rejected":
        self = .requestChanges
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "Critic verdict must be approve or request_changes."
          )
        )
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  public var verdict: Verdict
  public var summary: String
  public var feedback: String

  public init(verdict: Verdict, summary: String, feedback: String) {
    self.verdict = verdict
    self.summary = summary
    self.feedback = feedback
  }

  public enum CodingKeys: String, CodingKey {
    case verdict
    case decision
    case status
    case result
    case summary
    case rationale
    case reason
    case details
    case notes
    case feedback
    case changes
    case requestedChanges
    case requestedChangesSnake = "requested_changes"
    case actionItems
    case actionItemsSnake = "action_items"
    case punchList
    case punchListSnake = "punch_list"
    case issues
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    verdict = try FlexibleModelDecoder.decodeRequiredValue(
      from: container,
      preferredKey: .verdict,
      aliases: [.decision, .status, .result],
      fieldName: "verdict"
    )
    summary =
      try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .summary,
        aliases: [.rationale, .reason, .details, .notes]
      ) ?? ""
    feedback =
      try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .feedback,
        aliases: [
          .changes, .requestedChanges, .requestedChangesSnake, .actionItems,
          .actionItemsSnake, .punchList, .punchListSnake, .issues,
        ]
      ) ?? ""
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(verdict, forKey: .verdict)
    try container.encode(summary, forKey: .summary)
    try container.encode(feedback, forKey: .feedback)
  }
}

