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

  static func decodeRequiredString<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    preferredKey: Key,
    aliases: [Key],
    fieldName: String
  ) throws -> String {
    var sawPresentKey = false
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      sawPresentKey = true
      do {
        return try decodeRequiredString(from: container, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }

    if !sawPresentKey {
      throw DecodingError.keyNotFound(
        preferredKey,
        .init(
          codingPath: container.codingPath,
          debugDescription: "Missing required \(fieldName) field."
        )
      )
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return ""
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

  static func decodeStringIfPresent<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    preferredKey: Key,
    aliases: [Key]
  ) throws -> String? {
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        if let value = try decodeStringIfPresent(from: container, forKey: key) {
          return value
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

  static func decodeStringArrayIfPresent<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) throws -> [String]? {
    guard container.contains(key) else { return nil }
    if try container.decodeNil(forKey: key) {
      return []
    }
    if let values = try? container.decode([String].self, forKey: key) {
      return cleanedStringArray(values)
    }
    if let rawValue = try? container.decode(String.self, forKey: key) {
      return cleanedStringArrayValue(rawValue)
    }
    if let value = try? container.decode(LossyStringArrayValue.self, forKey: key) {
      return cleanedStringArray(value.values)
    }
    return try container.decode([String].self, forKey: key)
  }

  static func decodeRequiredValue<Value: Decodable, Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    preferredKey: Key,
    aliases: [Key],
    fieldName: String
  ) throws -> Value {
    var sawPresentKey = false
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      sawPresentKey = true
      do {
        if let value = try container.decodeIfPresent(Value.self, forKey: key) {
          return value
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
          debugDescription: "Missing required \(fieldName) field."
        )
      )
    }
    if let firstTypeError {
      throw firstTypeError
    }
    throw DecodingError.valueNotFound(
      Value.self,
      .init(
        codingPath: container.codingPath + [preferredKey],
        debugDescription: "Expected non-null \(fieldName)."
      )
    )
  }

  static func decodeValueIfPresent<Value: Decodable, Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    preferredKey: Key,
    aliases: [Key]
  ) throws -> Value? {
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        if let value = try container.decodeIfPresent(Value.self, forKey: key) {
          return value
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

  static func decodeIntIfPresent<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    preferredKey: Key,
    aliases: [Key]
  ) throws -> Int? {
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        if let value = try decodeIntIfPresent(from: container, forKey: key) {
          return value
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

  private static func decodeIntIfPresent<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) throws -> Int? {
    guard container.contains(key) else { return nil }
    if try container.decodeNil(forKey: key) { return nil }
    if let value = try? container.decode(Int.self, forKey: key) {
      return value
    }
    if let value = try? container.decode(Double.self, forKey: key),
      value.isFinite,
      value >= Double(Int.min),
      value <= Double(Int.max)
    {
      return Int(value)
    }
    if let rawValue = try? container.decode(String.self, forKey: key) {
      let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if let value = Int(trimmed) {
        return value
      }
      if let value = Double(trimmed),
        value.isFinite,
        value >= Double(Int.min),
        value <= Double(Int.max)
      {
        return Int(value)
      }
    }
    return try container.decode(Int.self, forKey: key)
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
    return cleanedStringArray(values).joined(separator: "\n")
  }

  private static func cleanedStringArray(_ values: [String]) -> [String] {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func cleanedStringArrayValue(_ rawValue: String) -> [String] {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    switch normalizedIdentifier(trimmed) {
    case "", "none", "null", "nil", "no", "no_change", "no_changes":
      return []
    default:
      return [trimmed].filter { !$0.isEmpty }
    }
  }

  private struct LossyStringArrayValue: Decodable {
    var values: [String]

    init(from decoder: Decoder) throws {
      let value = try LossyJSONValue(from: decoder)
      values = value.stringArrayValue
    }
  }

  private enum LossyJSONValue: Decodable {
    case null
    case string(String)
    case number(String)
    case bool(Bool)
    case array([LossyJSONValue])
    case object([String: LossyJSONValue])

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() {
        self = .null
      } else if let value = try? container.decode(String.self) {
        self = .string(value)
      } else if let value = try? container.decode(Int.self) {
        self = .number(String(value))
      } else if let value = try? container.decode(Double.self), value.isFinite {
        self = .number(String(value))
      } else if let value = try? container.decode(Bool.self) {
        self = .bool(value)
      } else if let value = try? container.decode([LossyJSONValue].self) {
        self = .array(value)
      } else {
        self = .object(try container.decode([String: LossyJSONValue].self))
      }
    }

    var stringArrayValue: [String] {
      switch self {
      case .null:
        return []
      case .array(let values):
        return values.flatMap(\.stringArrayItemValues)
      default:
        return stringArrayItemValues
      }
    }

    private var stringArrayItemValues: [String] {
      switch self {
      case .null:
        return []
      case .string(let value), .number(let value):
        return [value]
      case .bool(let value):
        return [value ? "true" : "false"]
      case .array(let values):
        return values.flatMap(\.stringArrayItemValues)
      case .object:
        return [rendered]
      }
    }

    private var rendered: String {
      switch self {
      case .null:
        return "null"
      case .string(let value), .number(let value):
        return value
      case .bool(let value):
        return value ? "true" : "false"
      case .array(let values):
        return values.map(\.rendered).joined(separator: "; ")
      case .object(let object):
        return object.keys.sorted().map { key in
          "\(key): \(object[key]?.rendered ?? "")"
        }.joined(separator: "; ")
      }
    }
  }
}

struct PlanNext: Codable, Equatable {
  var plan: String
  var verify: String
  var verifyTimeoutMs: Int?
  var estimatedDifficulty: Difficulty?
  var requiresHostXcode: Bool
  var selectedBecause: String?
  var source: Source?
  var candidateID: String?

  enum Difficulty: String, Codable, CaseIterable {
    case low
    case medium
    case high
  }

  enum Source: String, Codable, CaseIterable {
    case draft
    case feedback
    case candidate
    case focus
    case repository
    case repair
  }

  enum CodingKeys: String, CodingKey {
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
    case requiresHostXcode
    case requiresHostXcodeSnake = "requires_host_xcode"
    case selectedBecause
    case selectedBecauseSnake = "selected_because"
    case source
    case candidateID
    case candidateIDSnake = "candidate_id"
  }

  init(
    plan: String,
    verify: String,
    verifyTimeoutMs: Int? = nil,
    estimatedDifficulty: Difficulty? = nil,
    requiresHostXcode: Bool = false,
    selectedBecause: String? = "Selected by Compass as the next useful slice.",
    source: Source? = .repository,
    candidateID: String? = nil
  ) {
    self.plan = plan.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verify = verify.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verifyTimeoutMs = verifyTimeoutMs
    self.estimatedDifficulty = estimatedDifficulty
    self.requiresHostXcode = requiresHostXcode
    self.selectedBecause = selectedBecause?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    self.source = source
    self.candidateID = candidateID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  init(from decoder: Decoder) throws {
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
    self.requiresHostXcode =
      Self.decodeBool(
        from: container,
        preferredKey: .requiresHostXcode,
        aliases: [.requiresHostXcodeSnake]
      ) ?? false
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

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(plan, forKey: .plan)
    try container.encode(verify, forKey: .verify)
    try container.encodeIfPresent(verifyTimeoutMs, forKey: .verifyTimeoutMs)
    try container.encodeIfPresent(estimatedDifficulty, forKey: .estimatedDifficulty)
    if requiresHostXcode {
      try container.encode(true, forKey: .requiresHostXcode)
    }
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

  private static func decodeBool(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) -> Bool? {
    for key in [preferredKey] + aliases {
      if let value = FlexibleModelDecoder.decodeBool(from: container, forKey: key) {
        return value
      }
    }
    return nil
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

struct PlanCandidate: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var outcome: String
  var why: String
  var category: Category
  var origin: Origin
  var priority: Priority
  var status: Status
  var evidence: [String]
  var blockedBy: [String]
  var risk: String?

  enum CodingKeys: String, CodingKey {
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

  enum Category: String, Codable, CaseIterable {
    case feature
    case test
    case cleanup
    case docs
    case bugHunt
    case reliability
    case exploration
  }

  enum Origin: String, Codable, CaseIterable {
    case draft
    case feedback
    case repository
    case plan
    case reflect
    case lesson
    case user
  }

  enum Priority: String, Codable, CaseIterable {
    case low
    case medium
    case high
  }

  enum Status: String, Codable, CaseIterable {
    case available
    case active
    case blocked
    case deferred
    case done
    case stale

    var isActionable: Bool {
      switch self {
      case .available, .active:
        return true
      case .blocked, .deferred, .done, .stale:
        return false
      }
    }
  }

  init(
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .id)
    let title = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .title)
    let outcome = try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: .outcome)
    let why =
      try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .why) ?? ""
    let category = try container.decode(Category.self, forKey: .category)
    let origin = try container.decode(Origin.self, forKey: .origin)
    let priority = try container.decode(Priority.self, forKey: .priority)
    let status = try container.decode(Status.self, forKey: .status)
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

struct PlanStrategicContext: Codable, Equatable {
  var thesis: String
  var principles: [String]
  var constraints: [String]
  var nonGoals: [String]
  var risks: [String]

  enum CodingKeys: String, CodingKey {
    case thesis
    case principles
    case constraints
    case nonGoals
    case nonGoalsSnake = "non_goals"
    case nonGoalsKebab = "non-goals"
    case risks
  }

  static let empty = PlanStrategicContext(
    thesis: "",
    principles: [],
    constraints: [],
    nonGoals: [],
    risks: []
  )

  init(
    thesis: String = "",
    principles: [String] = [],
    constraints: [String] = [],
    nonGoals: [String] = [],
    risks: [String] = []
  ) {
    self.thesis = thesis.trimmingCharacters(in: .whitespacesAndNewlines)
    self.principles = Self.cleaned(principles)
    self.constraints = Self.cleaned(constraints)
    self.nonGoals = Self.cleaned(nonGoals)
    self.risks = Self.cleaned(risks)
  }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
      let thesis =
        try FlexibleModelDecoder.decodeStringIfPresent(from: container, forKey: .thesis) ?? ""
      let principles =
        try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: .principles)
        ?? []
      let constraints =
        try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: .constraints)
        ?? []
      let nonGoals =
        try Self.decodeStringArrayIfPresent(
          from: container,
          preferredKey: .nonGoals,
          aliases: [.nonGoalsSnake, .nonGoalsKebab]
        ) ?? []
      let risks =
        try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: .risks) ?? []

      self.init(
        thesis: thesis,
        principles: principles,
        constraints: constraints,
        nonGoals: nonGoals,
        risks: risks
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

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(thesis, forKey: .thesis)
    try container.encode(principles, forKey: .principles)
    try container.encode(constraints, forKey: .constraints)
    try container.encode(nonGoals, forKey: .nonGoals)
    try container.encode(risks, forKey: .risks)
  }

  var digestLines: [String] {
    var lines: [String] = []
    if !thesis.isEmpty {
      lines.append("Thesis: \(thesis)")
    }
    lines += principles.prefix(5).map { "Principle: \($0)" }
    lines += constraints.prefix(5).map { "Constraint: \($0)" }
    lines += nonGoals.prefix(4).map { "Non-goal: \($0)" }
    lines += risks.prefix(4).map { "Risk: \($0)" }
    return lines
  }

  var markdownSummary: String {
    var sections: [String] = []
    if !thesis.isEmpty {
      sections.append(thesis)
    }
    if !principles.isEmpty {
      sections.append(principles.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !constraints.isEmpty {
      sections.append("Constraints:\n" + constraints.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !nonGoals.isEmpty {
      sections.append("Non-goals:\n" + nonGoals.prefix(4).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !risks.isEmpty {
      sections.append("Risks:\n" + risks.prefix(4).map { "- \($0)" }.joined(separator: "\n"))
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

struct PlanQuestion: Codable, Equatable, Identifiable {
  var id: String
  var question: String
  var impact: String

  init(id: String, question: String, impact: String = "") {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? UUID().uuidString.lowercased()
    self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    self.impact = impact.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

struct PlanState: Codable, Equatable {
  var completed: [String]
  var immediate: PlanNext?
  var candidates: [PlanCandidate]
  var strategicContext: PlanStrategicContext
  var openQuestions: [PlanQuestion]

  static let empty = PlanState(
    completed: [],
    immediate: nil,
    candidates: [],
    strategicContext: .empty,
    openQuestions: []
  )

  enum CodingKeys: String, CodingKey {
    case completed
    case immediate
    case candidates
    case strategicContext
    case openQuestions
  }

  init(
    completed: [String],
    immediate: PlanNext?,
    candidates: [PlanCandidate] = [],
    strategicContext: PlanStrategicContext = .empty,
    openQuestions: [PlanQuestion] = []
  ) {
    self.completed = completed
    self.immediate = immediate
    self.candidates = candidates
    self.strategicContext = strategicContext
    self.openQuestions = openQuestions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let completedValues =
      try container.decodeIfPresent([LossyString].self, forKey: .completed) ?? []
    completed = completedValues.compactMap(\.value)
    immediate = try container.decodeIfPresent(PlanNext.self, forKey: .immediate)
    candidates = try container.decodeIfPresent([PlanCandidate].self, forKey: .candidates) ?? []
    strategicContext =
      try container.decodeIfPresent(PlanStrategicContext.self, forKey: .strategicContext) ?? .empty
    openQuestions = try container.decodeIfPresent([PlanQuestion].self, forKey: .openQuestions) ?? []
  }

  var candidatesMarkdown: String {
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

  var strategicContextMarkdown: String {
    strategicContext.markdownSummary
  }

  var actionableCandidates: [PlanCandidate] {
    candidates.filter { $0.status.isActionable }
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

  init(find: String, replace: String, replaceAll: Bool?) {
    self.find = find
    self.replace = replace
    self.replaceAll = replaceAll
  }

  init(from decoder: Decoder) throws {
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

  func encode(to encoder: Encoder) throws {
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
  static func decodeLessonEditsIfPresent<Key: CodingKey>(
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
    var lessonEdits: [LessonEdit]?

    enum CodingKeys: String, CodingKey {
      case lessonEdits
      case lessonEditsSnake = "lesson_edits"
      case edits
      case changes
      case items
    }

    init(from decoder: Decoder) throws {
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
    case lessonEditsSnake = "lesson_edits"
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
    lessonEdits =
      try FlexibleModelDecoder.decodeLessonEditsIfPresent(
        from: container,
        preferredKey: .lessonEdits,
        aliases: [.lessonEditsSnake]
      ) ?? []
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
  var productDecisionUpdates: [ProductizationReflectDecisionUpdate]

  enum CodingKeys: String, CodingKey {
    case state
    case planState
    case plan_state
    case planningState
    case planning_state
    case proposal
    case summary
    case reflection
    case result
    case outcome
    case details
    case notes
    case lessonEdits
    case lessonEditsSnake = "lesson_edits"
    case productDecisionUpdates
    case productDecisionUpdatesSnake = "product_decision_updates"
  }

  init(
    state: PlanProposal?,
    summary: String,
    lessonEdits: [LessonEdit] = [],
    productDecisionUpdates: [ProductizationReflectDecisionUpdate] = []
  ) {
    self.state = state
    self.summary = summary
    self.lessonEdits = lessonEdits
    self.productDecisionUpdates = productDecisionUpdates
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    state = try Self.decodeOptionalPlanProposal(
      from: container,
      preferredKey: .state,
      aliases: [.planState, .plan_state, .planningState, .planning_state, .proposal]
    )
    summary = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .summary,
      aliases: [.reflection, .result, .outcome, .details, .notes],
      fieldName: "summary"
    )
    lessonEdits =
      try FlexibleModelDecoder.decodeLessonEditsIfPresent(
        from: container,
        preferredKey: .lessonEdits,
        aliases: [.lessonEditsSnake]
      ) ?? []
    productDecisionUpdates = try Self.decodeProductDecisionUpdates(
      from: container,
      preferredKey: .productDecisionUpdates,
      aliases: [.productDecisionUpdatesSnake]
    ) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(state, forKey: .state)
    if state == nil {
      try container.encodeNil(forKey: .state)
    }
    try container.encode(summary, forKey: .summary)
    try container.encode(lessonEdits, forKey: .lessonEdits)
    try container.encode(productDecisionUpdates, forKey: .productDecisionUpdates)
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

  private static func decodeProductDecisionUpdates(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> [ProductizationReflectDecisionUpdate]? {
    var firstTypeError: Error?
    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        return try container.decodeIfPresent(
          [ProductizationReflectDecisionUpdate].self,
          forKey: key
        )
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
      pieces.append("fallback \(AgentExecutionLaunchPlan.userFacingFallbackReason(fallbackReason))")
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
  var productExperimentID: String?
  var productSolutionID: String?
  var productPainID: String?
  var productExperimentBranchName: String?
  var productExperimentCommitSha: String?
  var productExperimentBeforeSha: String?
  var productExperimentAfterSha: String?
  var productEvidenceRunIDs: [String]
  var productDecision: ProductExperimentDecision?

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
      productExperimentID: nil,
      productSolutionID: nil,
      productPainID: nil,
      productExperimentBranchName: nil,
      productExperimentCommitSha: nil,
      productExperimentBeforeSha: nil,
      productExperimentAfterSha: nil,
      productEvidenceRunIDs: [],
      productDecision: nil
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
    case productExperimentID
    case productSolutionID
    case productPainID
    case productExperimentBranchName
    case productExperimentCommitSha
    case productExperimentBeforeSha
    case productExperimentAfterSha
    case productEvidenceRunIDs
    case productDecision
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
    productExperimentID: String? = nil,
    productSolutionID: String? = nil,
    productPainID: String? = nil,
    productExperimentBranchName: String? = nil,
    productExperimentCommitSha: String? = nil,
    productExperimentBeforeSha: String? = nil,
    productExperimentAfterSha: String? = nil,
    productEvidenceRunIDs: [String] = [],
    productDecision: ProductExperimentDecision? = nil
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
    self.productExperimentID = Self.normalizedOptionalProductizationField(
      productExperimentID,
      limit: 120
    )
    self.productSolutionID = Self.normalizedOptionalProductizationField(
      productSolutionID,
      limit: 120
    )
    self.productPainID = Self.normalizedOptionalProductizationField(
      productPainID,
      limit: 120
    )
    self.productExperimentBranchName = Self.normalizedOptionalProductizationField(
      productExperimentBranchName,
      limit: 240
    )
    self.productExperimentCommitSha = Self.normalizedOptionalProductizationField(
      productExperimentCommitSha,
      limit: 80
    )
    self.productExperimentBeforeSha = Self.normalizedOptionalProductizationField(
      productExperimentBeforeSha,
      limit: 80
    )
    self.productExperimentAfterSha = Self.normalizedOptionalProductizationField(
      productExperimentAfterSha,
      limit: 80
    )
    self.productEvidenceRunIDs = Self.normalizedProductizationFields(
      productEvidenceRunIDs,
      limit: 120,
      maxCount: 20
    )
    self.productDecision = productDecision
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
    productExperimentID = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productExperimentID),
      limit: 120
    )
    productSolutionID = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productSolutionID),
      limit: 120
    )
    productPainID = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productPainID),
      limit: 120
    )
    productExperimentBranchName = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productExperimentBranchName),
      limit: 240
    )
    productExperimentCommitSha = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productExperimentCommitSha),
      limit: 80
    )
    productExperimentBeforeSha = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productExperimentBeforeSha),
      limit: 80
    )
    productExperimentAfterSha = Self.normalizedOptionalProductizationField(
      try container.decodeIfPresent(String.self, forKey: .productExperimentAfterSha),
      limit: 80
    )
    productEvidenceRunIDs = Self.normalizedProductizationFields(
      try container.decodeIfPresent([String].self, forKey: .productEvidenceRunIDs) ?? [],
      limit: 120,
      maxCount: 20
    )
    productDecision = try container.decodeIfPresent(
      ProductExperimentDecision.self,
      forKey: .productDecision
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
    try container.encodeIfPresent(productExperimentID, forKey: .productExperimentID)
    try container.encodeIfPresent(productSolutionID, forKey: .productSolutionID)
    try container.encodeIfPresent(productPainID, forKey: .productPainID)
    try container.encodeIfPresent(productExperimentBranchName, forKey: .productExperimentBranchName)
    try container.encodeIfPresent(productExperimentCommitSha, forKey: .productExperimentCommitSha)
    try container.encodeIfPresent(productExperimentBeforeSha, forKey: .productExperimentBeforeSha)
    try container.encodeIfPresent(productExperimentAfterSha, forKey: .productExperimentAfterSha)
    if !productEvidenceRunIDs.isEmpty {
      try container.encode(productEvidenceRunIDs, forKey: .productEvidenceRunIDs)
    }
    try container.encodeIfPresent(productDecision, forKey: .productDecision)
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

  private static func normalizedOptionalProductizationField(_ value: String?, limit: Int)
    -> String?
  {
    let bounded = StringUtils.boundedText(value ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }

  private static func normalizedProductizationFields(
    _ values: [String],
    limit: Int,
    maxCount: Int
  ) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let bounded = StringUtils.boundedText(value, limit: limit)
      guard !bounded.isEmpty, seen.insert(bounded).inserted else { continue }
      result.append(bounded)
      if result.count >= maxCount { break }
    }
    return result
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

  func encode(to encoder: Encoder) throws {
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

  init(from decoder: Decoder) throws {
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

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(verdict, forKey: .verdict)
    try container.encode(summary, forKey: .summary)
    try container.encode(feedback, forKey: .feedback)
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
  var metadata: [String: String]?

  init(
    level: LiveLine.Level = .info,
    text: String,
    detail: String? = nil,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none,
    correlationID: String? = nil,
    metadata: [String: String]? = nil
  ) {
    self.level = level
    self.text = text
    self.detail = detail
    self.kind = kind
    self.status = status
    self.correlationID = correlationID
    self.metadata = metadata
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
