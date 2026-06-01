import Foundation

enum FlexibleModelDecoder {
  static func decodeRequiredString<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) throws -> String {
    guard container.contains(key) else {
      throw DecodingError.keyNotFound(
        key,
        .init(
          codingPath: container.codingPath,
          debugDescription: "Missing required string field."
        )
      )
    }
    if try container.decodeNil(forKey: key) {
      throw DecodingError.valueNotFound(
        String.self,
        .init(
          codingPath: container.codingPath + [key],
          debugDescription: "Expected string but found null."
        )
      )
    }
    if let value = try? container.decode(String.self, forKey: key) {
      return value
    }
    if let value = try? decodeStringArray(from: container, forKey: key) {
      return value
    }
    return try container.decode(String.self, forKey: key)
  }

  static func decodeStringIfPresent<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) throws -> String? {
    guard container.contains(key) else { return nil }
    if try container.decodeNil(forKey: key) { return nil }
    if let value = try? container.decode(String.self, forKey: key) {
      return value
    }
    if let value = try? decodeStringArray(from: container, forKey: key) {
      return value
    }
    return try container.decode(String.self, forKey: key)
  }

  static func decodeBool<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) -> Bool? {
    if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
      return value
    }
    if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
      if value == 1 { return true }
      if value == 0 { return false }
    }
    guard let rawValue = try? container.decodeIfPresent(String.self, forKey: key) else {
      return nil
    }

    switch normalizedIdentifier(rawValue) {
    case "true", "yes", "y", "1":
      return true
    case "false", "no", "n", "0":
      return false
    default:
      return nil
    }
  }

  static func normalizedIdentifier(_ rawValue: String) -> String {
    let camelSeparated = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(
        of: #"([a-z0-9])([A-Z])"#,
        with: "$1_$2",
        options: .regularExpression
      )
    return camelSeparated
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  }

  private static func decodeStringArray<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) throws -> String {
    let values = try container.decode([String].self, forKey: key)
    return values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }
}

struct PlanNext: Codable, Equatable {
  var plan: String
  var verify: String
  var verifyTimeoutMs: Int?
  var estimatedDifficulty: Difficulty?
  var requiresHostXcode: Bool

  enum Difficulty: String, Codable, CaseIterable {
    case low
    case medium
    case high
  }

  enum CodingKeys: String, CodingKey {
    case plan
    case implementationPlan
    case handoff
    case verify
    case verifyCommand
    case verification
    case verificationCommand
    case verifyCmd
    case verifyTimeoutMs
    case estimatedDifficulty
    case requiresHostXcode
  }

  init(
    plan: String,
    verify: String,
    verifyTimeoutMs: Int? = nil,
    estimatedDifficulty: Difficulty? = nil,
    requiresHostXcode: Bool = false
  ) {
    self.plan = plan.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verify = verify.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verifyTimeoutMs = verifyTimeoutMs
    self.estimatedDifficulty = estimatedDifficulty
    self.requiresHostXcode = requiresHostXcode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let plan = try Self.decodeRequiredTrimmedString(
      from: container,
      preferredKey: .plan,
      aliases: [.implementationPlan, .handoff],
      fieldName: "plan"
    )
    let verify = try Self.decodeRequiredTrimmedString(
      from: container,
      preferredKey: .verify,
      aliases: [.verifyCommand, .verification, .verificationCommand, .verifyCmd],
      fieldName: "verify"
    )

    self.plan = plan
    self.verify = verify
    self.verifyTimeoutMs = Self.decodePositiveInt(from: container, forKey: .verifyTimeoutMs)
    self.estimatedDifficulty = Self.decodeDifficulty(from: container, forKey: .estimatedDifficulty)
    self.requiresHostXcode =
      FlexibleModelDecoder.decodeBool(from: container, forKey: .requiresHostXcode) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(plan, forKey: .plan)
    try container.encode(verify, forKey: .verify)
    try container.encodeIfPresent(verifyTimeoutMs, forKey: .verifyTimeoutMs)
    try container.encodeIfPresent(estimatedDifficulty, forKey: .estimatedDifficulty)
    if requiresHostXcode {
      try container.encode(true, forKey: .requiresHostXcode)
    }
  }

  private static func decodePositiveInt(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> Int? {
    if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
      return value > 0 ? value : nil
    }
    if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
      return value > 0 ? Int(value) : nil
    }
    guard
      let rawValue = try? container.decodeIfPresent(String.self, forKey: key)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !rawValue.isEmpty
    else {
      return nil
    }
    if let value = Int(rawValue) {
      return value > 0 ? value : nil
    }
    if let value = Double(rawValue) {
      return value > 0 ? Int(value) : nil
    }
    return nil
  }

  private static func decodeDifficulty(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> Difficulty? {
    guard
      let rawValue = try? container.decodeIfPresent(String.self, forKey: key)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
      return nil
    }
    return Difficulty(rawValue: rawValue)
  }

  private static func decodeRequiredTrimmedString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys],
    fieldName: String
  ) throws -> String {
    var sawPresentKey = false
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      sawPresentKey = true
      do {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
          let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            return trimmed
          }
        }
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }

    if !sawPresentKey {
      throw DecodingError.keyNotFound(
        preferredKey,
        .init(
          codingPath: container.codingPath,
          debugDescription: "PlanNext requires \(fieldName)."
        )
      )
    }
    if let firstTypeError {
      throw firstTypeError
    }
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: container.codingPath,
        debugDescription: "PlanNext requires non-empty \(fieldName)."
      )
    )
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
    let completedValues =
      try container.decodeIfPresent([LossyString].self, forKey: .completed) ?? []
    completed = completedValues.compactMap(\.value)
    immediate = try container.decodeIfPresent(PlanNext.self, forKey: .immediate)
    midTerm = try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .midTerm) ?? ""
    longTerm =
      try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .longTerm) ?? ""
  }

  var proposal: PlanProposal {
    PlanProposal(from: self)
  }

  func applying(proposal: PlanProposal) -> PlanState {
    proposal.applying(to: self)
  }
}

struct LessonEdit: Codable, Equatable {
  var find: String
  var replace: String
  var replaceAll: Bool?

  enum CodingKeys: String, CodingKey {
    case find
    case replace
    case replaceAll
  }

  init(find: String, replace: String, replaceAll: Bool?) {
    self.find = find
    self.replace = replace
    self.replaceAll = replaceAll
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    find = try container.decode(String.self, forKey: .find)
    replace = try container.decode(String.self, forKey: .replace)
    replaceAll = FlexibleModelDecoder.decodeBool(from: container, forKey: .replaceAll)
  }
}

struct PlanRunResult: Codable, Equatable {
  var state: PlanProposal
  var lessonEdits: [LessonEdit]

  enum CodingKeys: String, CodingKey {
    case state
    case planState
    case plan_state
    case planningState
    case planning_state
    case proposal
    case lessonEdits
  }

  init(state: PlanProposal, lessonEdits: [LessonEdit] = []) {
    self.state = state
    self.lessonEdits = lessonEdits
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    state = try Self.decodeRequiredPlanProposal(
      from: container,
      preferredKey: .state,
      aliases: [.planState, .plan_state, .planningState, .planning_state, .proposal],
      fieldName: "state"
    )
    lessonEdits = try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(state, forKey: .state)
    try container.encode(lessonEdits, forKey: .lessonEdits)
  }

  private static func decodeRequiredPlanProposal(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys],
    fieldName: String
  ) throws -> PlanProposal {
    var sawPresentKey = false
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      sawPresentKey = true
      do {
        return try container.decode(PlanProposal.self, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }

    if !sawPresentKey {
      throw DecodingError.keyNotFound(
        preferredKey,
        .init(
          codingPath: container.codingPath,
          debugDescription: "PlanRunResult requires \(fieldName)."
        )
      )
    }
    if let firstTypeError {
      throw firstTypeError
    }
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: container.codingPath,
        debugDescription: "PlanRunResult requires a planning state object."
      )
    )
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
  var state: PlanProposal?
  var summary: String
  var lessonEdits: [LessonEdit]

  enum CodingKeys: String, CodingKey {
    case state
    case planState
    case plan_state
    case planningState
    case planning_state
    case proposal
    case summary
    case lessonEdits
  }

  init(state: PlanProposal?, summary: String, lessonEdits: [LessonEdit] = []) {
    self.state = state
    self.summary = summary
    self.lessonEdits = lessonEdits
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    state = try Self.decodeOptionalPlanProposal(
      from: container,
      preferredKey: .state,
      aliases: [.planState, .plan_state, .planningState, .planning_state, .proposal]
    )
    summary = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .summary)
    lessonEdits = try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(state, forKey: .state)
    if state == nil {
      try container.encodeNil(forKey: .state)
    }
    try container.encode(summary, forKey: .summary)
    try container.encode(lessonEdits, forKey: .lessonEdits)
  }

  private static func decodeOptionalPlanProposal(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> PlanProposal? {
    var firstTypeError: Error?
    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        if let state = try container.decodeIfPresent(PlanProposal.self, forKey: key) {
          return state
        }
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return nil
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
      supportClassificationIdentifier,
    ].joined(separator: ".")
  }

  var replacementKey: String {
    "\(phaseIdentifier)#\(attempt.map(String.init) ?? "none")"
  }

  init(
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
    supportClassificationIdentifier = Self.vmSupportClassification(launchPlan.vmReadiness)
    visibleSupportTokens = []
    omittedSupportTokenCount = 0
    imageLabel = Self.sanitizedField(launchPlan.imageLabel, limit: Self.fieldLimit)
    workspaceLabel = Self.sanitizedField(launchPlan.workspaceLabel, limit: Self.fieldLimit)
    fallbackReason = Self.sanitizedOptionalField(
      launchPlan.fallbackReason,
      limit: AgentExecutionLaunchPlan.fallbackReasonLimit
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
      "vm \(supportClassificationIdentifier)",
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
      pieces.append(
        "vm-build \(provisioningAvailabilityIdentifier)/\(provisioningStatusIdentifier)")
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
    case .provisioningDevTools:
      return "provisioning-dev-tools"
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

  mutating func recordExecutionEnvironmentSnapshot(_ snapshot: SessionExecutionEnvironmentSnapshot)
  {
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
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
    summary = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .summary)
    feedback = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .feedback)
    bypassVerify = FlexibleModelDecoder.decodeBool(from: container, forKey: .bypassVerify)
    lessonEdits = try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? []
  }
}

/// Result of one Critic pass — Compass's adversarial-review gate that
/// runs after Develop's post-checks pass. `verdict == .approve` ends the
/// iteration; `.requestChanges` causes Develop to re-run with the
/// critic's `feedback` appended to its prior-issues list. The outer
/// Develop loop bounds the number of critic-driven retries.
struct CriticVerdict: Codable, Equatable {
  enum Verdict: String, Codable {
    case approve
    case requestChanges = "request_changes"

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let rawValue = try container.decode(String.self)
      switch FlexibleModelDecoder.normalizedIdentifier(rawValue) {
      case "approve", "approved":
        self = .approve
      case "request_changes", "requestchanges", "changes_requested", "change_requested",
        "changes_required", "needs_changes", "reject", "rejected":
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

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  var verdict: Verdict
  var summary: String
  var feedback: String

  init(verdict: Verdict, summary: String, feedback: String) {
    self.verdict = verdict
    self.summary = summary
    self.feedback = feedback
  }

  enum CodingKeys: String, CodingKey {
    case verdict
    case summary
    case feedback
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    verdict = try container.decode(Verdict.self, forKey: .verdict)
    summary = try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .summary) ?? ""
    feedback = try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .feedback) ?? ""
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
  case reviewing = "Reviewing"
  case paused = "Paused"
  case failed = "Failed"
  case succeeded = "Succeeded"
  case cancelled = "Cancelled"
}
