import Foundation

public struct PlanNext: Codable, Equatable {
  public var plan: String
  public var verify: String
  public var verifyTimeoutMs: Int?
  public var estimatedDifficulty: Difficulty?
  public var selectedBecause: String?
  public var source: Source?
  public var candidateID: String?

  public enum Difficulty: String, Codable, CaseIterable {
    case low
    case medium
    case high
  }

  public enum Source: String, Codable, CaseIterable {
    case draft
    case feedback
    case candidate
    case focus
    case repository
    case repair
  }

  public enum CodingKeys: String, CodingKey {
    case plan
    case implementationPlan
    case implementationPlanSnake = "implementation_plan"
    case handoff
    case verify
    case verifyCommand
    case verifyCommandSnake = "verify_command"
    case verification
    case verificationCommand
    case verificationCommandSnake = "verification_command"
    case verifyCmd
    case verifyCmdSnake = "verify_cmd"
    case test
    case testCommand
    case testCommandSnake = "test_command"
    case check
    case checkCommand
    case checkCommandSnake = "check_command"
    case validation
    case validationCommand
    case validationCommandSnake = "validation_command"
    case validationCmd
    case validationCmdSnake = "validation_cmd"
    case command
    case verifyTimeoutMs
    case verifyTimeoutMsSnake = "verify_timeout_ms"
    case estimatedDifficulty
    case estimatedDifficultySnake = "estimated_difficulty"
    case selectedBecause
    case selectedBecauseSnake = "selected_because"
    case source
    case candidateID
    case candidateIDSnake = "candidate_id"
  }

  public init(
    plan: String,
    verify: String,
    verifyTimeoutMs: Int? = nil,
    estimatedDifficulty: Difficulty? = nil,
    selectedBecause: String? = "Selected by Compass as the next useful slice.",
    source: Source? = .repository,
    candidateID: String? = nil
  ) {
    self.plan = plan.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verify = verify.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verifyTimeoutMs = verifyTimeoutMs
    self.estimatedDifficulty = estimatedDifficulty
    self.selectedBecause =
      selectedBecause?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    self.source = source
    self.candidateID = candidateID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let plan = try Self.decodeRequiredTrimmedString(
      from: container,
      preferredKey: .plan,
      aliases: [.implementationPlan, .implementationPlanSnake, .handoff],
      fieldName: "plan"
    )
    let verify = try Self.decodeRequiredTrimmedString(
      from: container,
      preferredKey: .verify,
      aliases: [
        .verifyCommand, .verifyCommandSnake, .verification, .verificationCommand,
        .verificationCommandSnake, .verifyCmd, .verifyCmdSnake, .test, .testCommand,
        .testCommandSnake, .check, .checkCommand, .checkCommandSnake, .validation,
        .validationCommand, .validationCommandSnake, .validationCmd, .validationCmdSnake,
        .command,
      ],
      fieldName: "verify"
    )

    self.plan = plan
    self.verify = verify
    self.verifyTimeoutMs = Self.decodePositiveInt(
      from: container,
      preferredKey: .verifyTimeoutMs,
      aliases: [.verifyTimeoutMsSnake]
    )
    self.estimatedDifficulty = Self.decodeDifficulty(
      from: container,
      preferredKey: .estimatedDifficulty,
      aliases: [.estimatedDifficultySnake]
    )
    self.selectedBecause = try FlexibleModelDecoder.decodeStringIfPresent(
      from: container,
      preferredKey: .selectedBecause,
      aliases: [.selectedBecauseSnake]
    )?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.source = Self.decodeSource(from: container)
    self.candidateID = try FlexibleModelDecoder.decodeStringIfPresent(
      from: container,
      preferredKey: .candidateID,
      aliases: [.candidateIDSnake]
    )?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(plan, forKey: .plan)
    try container.encode(verify, forKey: .verify)
    try container.encodeIfPresent(verifyTimeoutMs, forKey: .verifyTimeoutMs)
    try container.encodeIfPresent(estimatedDifficulty, forKey: .estimatedDifficulty)
    try container.encodeIfPresent(selectedBecause, forKey: .selectedBecause)
    try container.encodeIfPresent(source, forKey: .source)
    try container.encodeIfPresent(candidateID, forKey: .candidateID)
  }

  private static func decodePositiveInt(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) -> Int? {
    for key in [preferredKey] + aliases {
      if let value = decodePositiveInt(from: container, forKey: key) {
        return value
      }
    }
    return nil
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
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) -> Difficulty? {
    for key in [preferredKey] + aliases {
      if let value = decodeDifficulty(from: container, forKey: key) {
        return value
      }
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

  private static func decodeSource(from container: KeyedDecodingContainer<CodingKeys>) -> Source? {
    guard
      let rawValue = try? container.decodeIfPresent(String.self, forKey: .source)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
      return nil
    }
    return Source(rawValue: rawValue)
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
        let value = try FlexibleModelDecoder.decodeRequiredString(
          from: container,
          forKey: key
        )
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
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

public struct PlanCandidate: Codable, Equatable, Identifiable {
  public var id: String
  public var title: String
  public var outcome: String
  public var why: String
  public var category: Category
  public var origin: Origin
  public var priority: Priority
  public var status: Status
  public var evidence: [String]
  public var blockedBy: [String]
  public var risk: String?

  public enum CodingKeys: String, CodingKey {
    case id
    case title
    case outcome
    case why
    case category
    case origin
    case priority
    case status
    case evidence
    case blockedBy
    case risk
  }

  public enum Category: String, Codable, CaseIterable {
    case feature
    case test
    case cleanup
    case docs
    case bugHunt
    case reliability
    case exploration

    public static let modelAliases: [String: Category] = [
      "bug": .bugHunt,
      "bug_fix": .bugHunt,
      "bugfix": .bugHunt,
      "development": .feature,
      "documentation": .docs,
      "feature_work": .feature,
      "implementation": .feature,
      "maintenance": .cleanup,
      "refactor": .cleanup,
      "testing": .test,
      "tests": .test,
    ]
  }

  public enum Origin: String, Codable, CaseIterable {
    case draft
    case feedback
    case repository
    case plan
    case lesson
    case user

    public static let modelAliases: [String: Origin] = [
      "current_brief": .user,
      "current_request": .user,
      "repo": .repository,
      "request": .user,
      "user_request": .user,
    ]
  }

  public enum Priority: String, Codable, CaseIterable {
    case low
    case medium
    case high

    public static let modelAliases: [String: Priority] = [:]
  }

  public enum Status: String, Codable, CaseIterable {
    case available
    case active
    case blocked
    case deferred
    case done
    case stale

    public static let modelAliases: [String: Status] = [
      "closed": .done,
      "complete": .done,
      "completed": .done,
      "in_progress": .active,
      "open": .available,
      "ready": .available,
      "todo": .available,
      "to_do": .available,
    ]

    public var isActionable: Bool {
      switch self {
      case .available, .active:
        return true
      case .blocked, .deferred, .done, .stale:
        return false
      }
    }
  }

  public init(
    id: String,
    title: String,
    outcome: String,
    why: String = "",
    category: Category = .feature,
    origin: Origin = .plan,
    priority: Priority = .medium,
    status: Status = .available,
    evidence: [String] = [],
    blockedBy: [String] = [],
    risk: String? = nil
  ) {
    self.id = Self.normalizedID(id.isEmpty ? title : id)
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.outcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
    self.why = why.trimmingCharacters(in: .whitespacesAndNewlines)
    self.category = category
    self.origin = origin
    self.priority = priority
    self.status = status
    self.evidence = evidence.map(Self.trimmed).filter { !$0.isEmpty }
    self.blockedBy = blockedBy.map(Self.trimmed).filter { !$0.isEmpty }
    self.risk = risk.map(Self.trimmed)?.nilIfEmpty
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .id)
    let title = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .title)
    let outcome = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .outcome)
    let why =
      try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .why) ?? ""
    let category = try FlexibleModelDecoder.decodeRequiredEnum(
      from: container,
      forKey: .category,
      aliases: Category.modelAliases,
      fieldName: "PlanCandidate.category"
    )
    let origin = try FlexibleModelDecoder.decodeRequiredEnum(
      from: container,
      forKey: .origin,
      aliases: Origin.modelAliases,
      fieldName: "PlanCandidate.origin"
    )
    let priority = try FlexibleModelDecoder.decodeRequiredEnum(
      from: container,
      forKey: .priority,
      aliases: Priority.modelAliases,
      fieldName: "PlanCandidate.priority"
    )
    let status = try FlexibleModelDecoder.decodeRequiredEnum(
      from: container,
      forKey: .status,
      aliases: Status.modelAliases,
      fieldName: "PlanCandidate.status"
    )
    let evidence =
      try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: .evidence) ?? []
    let blockedBy =
      try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: .blockedBy) ?? []
    let risk = try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .risk)

    self.init(
      id: id,
      title: title,
      outcome: outcome,
      why: why,
      category: category,
      origin: origin,
      priority: priority,
      status: status,
      evidence: evidence,
      blockedBy: blockedBy,
      risk: risk
    )
  }

  private static func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizedID(_ value: String) -> String {
    let slug =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty ? UUID().uuidString.lowercased() : String(slug.prefix(64))
  }
}

public struct PlanStrategicContext: Codable, Equatable {
  public var summary: String
  public var targetUsers: [String]
  public var desiredOutcomes: [String]
  public var constraints: [String]
  public var acceptanceSignals: [String]

  public var thesis: String {
    get { summary }
    set { summary = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  public var principles: [String] {
    get { desiredOutcomes }
    set { desiredOutcomes = Self.cleaned(newValue) }
  }

  public var nonGoals: [String] {
    get { [] }
    set { _ = newValue }
  }

  public var risks: [String] {
    get { acceptanceSignals }
    set { acceptanceSignals = Self.cleaned(newValue) }
  }

  public enum CodingKeys: String, CodingKey {
    case summary
    case targetUsers
    case targetUsersSnake = "target_users"
    case desiredOutcomes
    case desiredOutcomesSnake = "desired_outcomes"
    case acceptanceSignals
    case acceptanceSignalsSnake = "acceptance_signals"
    case thesis
    case principles
    case constraints
    case nonGoals
    case nonGoalsSnake = "non_goals"
    case nonGoalsKebab = "non-goals"
    case risks
  }

  public static let empty = PlanStrategicContext(
    summary: "",
    targetUsers: [],
    desiredOutcomes: [],
    constraints: [],
    acceptanceSignals: []
  )

  public init(
    summary: String = "",
    targetUsers: [String] = [],
    desiredOutcomes: [String] = [],
    constraints: [String] = [],
    acceptanceSignals: [String] = [],
    thesis: String = "",
    principles: [String] = [],
    nonGoals: [String] = [],
    risks: [String] = []
  ) {
    self.summary =
      (summary.nilIfEmpty ?? thesis).trimmingCharacters(in: .whitespacesAndNewlines)
    self.targetUsers = Self.cleaned(targetUsers)
    self.desiredOutcomes = Self.cleaned(desiredOutcomes.isEmpty ? principles : desiredOutcomes)
    self.constraints = Self.cleaned(constraints)
    self.acceptanceSignals = Self.cleaned(acceptanceSignals.isEmpty ? risks : acceptanceSignals)
    _ = nonGoals
  }

  public init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
      let summary =
        try FlexibleModelDecoder.decodeStringIfPresent(
          from: container,
          preferredKey: .summary,
          aliases: [.thesis]
        ) ?? ""
      let targetUsers =
        try Self.decodeStringArrayIfPresent(
          from: container,
          preferredKey: .targetUsers,
          aliases: [.targetUsersSnake]
        ) ?? []
      let desiredOutcomes =
        try Self.decodeStringArrayIfPresent(
          from: container,
          preferredKey: .desiredOutcomes,
          aliases: [.desiredOutcomesSnake, .principles]
        ) ?? []
      let constraints =
        try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: .constraints)
        ?? []
      let acceptanceSignals =
        try Self.decodeStringArrayIfPresent(
          from: container,
          preferredKey: .acceptanceSignals,
          aliases: [.acceptanceSignalsSnake, .risks]
        ) ?? []

      self.init(
        summary: summary,
        targetUsers: targetUsers,
        desiredOutcomes: desiredOutcomes,
        constraints: constraints,
        acceptanceSignals: acceptanceSignals
      )
      return
    }

    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .empty
      return
    }
    let thesis = try container.decode(String.self)
    self.init(thesis: thesis)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(summary, forKey: .summary)
    try container.encode(targetUsers, forKey: .targetUsers)
    try container.encode(desiredOutcomes, forKey: .desiredOutcomes)
    try container.encode(constraints, forKey: .constraints)
    try container.encode(acceptanceSignals, forKey: .acceptanceSignals)
  }

  public var markdownSummary: String {
    var sections: [String] = []
    if !summary.isEmpty {
      sections.append(summary)
    }
    if !targetUsers.isEmpty {
      sections.append(
        "Target users:\n" + targetUsers.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !desiredOutcomes.isEmpty {
      sections.append(
        "Desired outcomes:\n" + desiredOutcomes.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !constraints.isEmpty {
      sections.append(
        "Constraints:\n" + constraints.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !acceptanceSignals.isEmpty {
      sections.append(
        "Acceptance signals:\n"
          + acceptanceSignals.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    return sections.joined(separator: "\n\n")
  }

  private static func cleaned(_ values: [String]) -> [String] {
    values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func decodeStringArrayIfPresent(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> [String]? {
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        return try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: key)
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

public struct PlanQuestion: Codable, Equatable, Identifiable {
  public var id: String
  public var question: String
  public var impact: String

  public init(id: String, question: String, impact: String = "") {
    self.id =
      id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? UUID().uuidString.lowercased()
    self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    self.impact = impact.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

public struct PlanState: Codable, Equatable {
  public var schemaVersion: Int
  public var completed: [String]
  public var immediate: PlanNext?
  public var queue: [PlanCandidate]
  public var brief: PlanStrategicContext
  public var openQuestions: [PlanQuestion]
  public var acceptanceGates: AcceptanceGates?
  /// Product surfaces on top of required `crates/core` (`cli` and/or `macos`).
  public var products: [GeneratedProduct]

  public static let empty = PlanState(
    schemaVersion: 1,
    completed: [],
    immediate: nil,
    queue: [],
    brief: .empty,
    openQuestions: [],
    products: GeneratedProducts.default
  )

  public enum CodingKeys: String, CodingKey {
    case schemaVersion
    case brief
    case queue
    case completed
    case immediate
    case candidates
    case strategicContext
    case openQuestions
    case acceptanceGates
    case products
  }

  public init(
    schemaVersion: Int = 1,
    completed: [String],
    immediate: PlanNext?,
    queue: [PlanCandidate]? = nil,
    brief: PlanStrategicContext? = nil,
    candidates: [PlanCandidate] = [],
    strategicContext: PlanStrategicContext = .empty,
    openQuestions: [PlanQuestion] = [],
    acceptanceGates: AcceptanceGates? = nil,
    products: [GeneratedProduct] = GeneratedProducts.default
  ) {
    self.schemaVersion = max(1, schemaVersion)
    self.completed = completed
    self.immediate = immediate
    self.queue = queue ?? candidates
    self.brief = brief ?? strategicContext
    self.openQuestions = openQuestions
    self.acceptanceGates = acceptanceGates
    self.products = GeneratedProducts.normalize(products)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = max(1, try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1)
    let completedValues =
      try container.decodeIfPresent([LossyString].self, forKey: .completed) ?? []
    completed = completedValues.compactMap(\.value)
    immediate = try container.decodeIfPresent(PlanNext.self, forKey: .immediate)
    queue =
      try container.decodeIfPresent([PlanCandidate].self, forKey: .queue)
      ?? container.decodeIfPresent([PlanCandidate].self, forKey: .candidates) ?? []
    brief =
      try container.decodeIfPresent(PlanStrategicContext.self, forKey: .brief)
      ?? container.decodeIfPresent(PlanStrategicContext.self, forKey: .strategicContext) ?? .empty
    openQuestions = try container.decodeIfPresent([PlanQuestion].self, forKey: .openQuestions) ?? []
    acceptanceGates = try container.decodeIfPresent(AcceptanceGates.self, forKey: .acceptanceGates)
    let decodedProducts =
      try container.decodeIfPresent([GeneratedProduct].self, forKey: .products)
      ?? GeneratedProducts.default
    products = GeneratedProducts.normalize(decodedProducts)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(brief, forKey: .brief)
    try container.encode(queue, forKey: .queue)
    try container.encodeIfPresent(immediate, forKey: .immediate)
    if immediate == nil {
      try container.encodeNil(forKey: .immediate)
    }
    try container.encode(completed, forKey: .completed)
    try container.encode(openQuestions, forKey: .openQuestions)
    try container.encodeIfPresent(acceptanceGates, forKey: .acceptanceGates)
    try container.encode(GeneratedProducts.normalize(products), forKey: .products)
  }

  public var candidates: [PlanCandidate] {
    get { queue }
    set { queue = newValue }
  }

  public var strategicContext: PlanStrategicContext {
    get { brief }
    set { brief = newValue }
  }

  public var candidatesMarkdown: String {
    candidates.map { candidate in
      let statusPrefix = candidate.status == .available ? "" : "[\(candidate.status.rawValue)] "
      let title = candidate.title.isEmpty ? candidate.outcome : candidate.title
      let outcome =
        candidate.outcome.isEmpty || candidate.outcome == title
        ? ""
        : " - \(candidate.outcome)"
      return "- \(statusPrefix)\(title)\(outcome)"
    }.joined(separator: "\n")
  }

  public var strategicContextMarkdown: String {
    strategicContext.markdownSummary
  }

  public var actionableCandidates: [PlanCandidate] {
    candidates.filter { $0.status.isActionable }
  }

  public var proposal: PlanProposal {
    PlanProposal(from: self)
  }

  public func applying(proposal: PlanProposal) -> PlanState {
    proposal.applying(to: self)
  }
}

public struct LessonEdit: Codable, Equatable {
  public var find: String
  public var replace: String
  public var replaceAll: Bool?

  public enum CodingKeys: String, CodingKey {
    case find
    case old
    case oldText
    case oldTextSnake = "old_text"
    case oldString
    case oldStringSnake = "old_string"
    case search
    case original
    case replace
    case new
    case newText
    case newTextSnake = "new_text"
    case newString
    case newStringSnake = "new_string"
    case replacement
    case to
    case replaceAll
    case replaceAllSnake = "replace_all"
    case all
    case global
  }

  public init(find: String, replace: String, replaceAll: Bool?) {
    self.find = find
    self.replace = replace
    self.replaceAll = replaceAll
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    find = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .find,
      aliases: [
        .old, .oldText, .oldTextSnake, .oldString, .oldStringSnake, .search, .original,
      ],
      fieldName: "find"
    )
    replace = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .replace,
      aliases: [
        .new, .newText, .newTextSnake, .newString, .newStringSnake, .replacement, .to,
      ],
      fieldName: "replace"
    )
    replaceAll = Self.decodeReplaceAll(from: container)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(find, forKey: .find)
    try container.encode(replace, forKey: .replace)
    try container.encodeIfPresent(replaceAll, forKey: .replaceAll)
  }

  private static func decodeReplaceAll(
    from container: KeyedDecodingContainer<CodingKeys>
  ) -> Bool? {
    for key in [
      CodingKeys.replaceAll,
      .replaceAllSnake,
      .all,
      .global,
    ] {
      if let value = FlexibleModelDecoder.decodeBool(from: container, forKey: key) {
        return value
      }
    }
    return nil
  }
}

extension FlexibleModelDecoder {
  public static func decodeLessonEditsIfPresent<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    preferredKey: Key,
    aliases: [Key]
  ) throws -> [LessonEdit]? {
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        if try container.decodeNil(forKey: key) {
          return []
        }
        if let edits = try? container.decode([LessonEdit].self, forKey: key) {
          return edits
        }
        if let edit = try? container.decode(LessonEdit.self, forKey: key) {
          return [edit]
        }
        if let emptyMarker = try? container.decode(String.self, forKey: key),
          isEmptyLessonEditMarker(emptyMarker)
        {
          return []
        }
        if let envelope = try? container.decode(LessonEditsEnvelope.self, forKey: key),
          let edits = envelope.lessonEdits
        {
          return edits
        }

        _ = try container.decode([LessonEdit].self, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }

    if let firstTypeError {
      throw firstTypeError
    }
    return nil
  }

  private static func isEmptyLessonEditMarker(_ rawValue: String) -> Bool {
    switch normalizedIdentifier(rawValue) {
    case "", "none", "null", "nil", "no", "no_change", "no_changes", "no_lesson_edits":
      return true
    default:
      return rawValue.trimmingCharacters(in: .whitespacesAndNewlines) == "[]"
    }
  }

  private struct LessonEditsEnvelope: Decodable {
    public var lessonEdits: [LessonEdit]?

    public enum CodingKeys: String, CodingKey {
      case lessonEdits
      case lessonEditsSnake = "lesson_edits"
      case edits
      case changes
      case items
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      for key in [
        CodingKeys.lessonEdits,
        .lessonEditsSnake,
        .edits,
        .changes,
        .items,
      ] where container.contains(key) {
        if try container.decodeNil(forKey: key) {
          lessonEdits = []
          return
        }
        if let edits = try? container.decode([LessonEdit].self, forKey: key) {
          lessonEdits = edits
          return
        }
        if let edit = try? container.decode(LessonEdit.self, forKey: key) {
          lessonEdits = [edit]
          return
        }
        if let emptyMarker = try? container.decode(String.self, forKey: key),
          FlexibleModelDecoder.isEmptyLessonEditMarker(emptyMarker)
        {
          lessonEdits = []
          return
        }
      }
      lessonEdits = nil
    }
  }
}

public struct PlanRunResult: Codable, Equatable {
  public var state: PlanProposal
  public var lessonEdits: [LessonEdit]

  public enum CodingKeys: String, CodingKey {
    case state
    case planState
    // swift-format-ignore: AlwaysUseLowerCamelCase
    case plan_state
    case planningState
    // swift-format-ignore: AlwaysUseLowerCamelCase
    case planning_state
    case proposal
    case lessonEdits
    case lessonEditsSnake = "lesson_edits"
  }

  public init(
    state: PlanProposal,
    lessonEdits: [LessonEdit] = []
  ) {
    self.state = state
    self.lessonEdits = lessonEdits
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    state = try Self.decodeRequiredPlanProposal(
      from: container,
      preferredKey: .state,
      aliases: [.planState, .plan_state, .planningState, .planning_state, .proposal],
      fieldName: "state"
    )
    lessonEdits =
      try FlexibleModelDecoder.decodeLessonEditsIfPresent(
        from: container,
        preferredKey: .lessonEdits,
        aliases: [.lessonEditsSnake]
      ) ?? []
  }

  public func encode(to encoder: Encoder) throws {
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
  public var value: String?

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    value = try? container.decode(String.self)
  }
}
