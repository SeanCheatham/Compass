import Foundation

package enum FlexibleModelDecoder {
  package static func decodeRequiredString<Key: CodingKey>(
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

  package static func decodeRequiredString<Key: CodingKey>(
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

  package static func decodeStringIfPresent<Key: CodingKey>(
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

  package static func decodeStringIfPresent<Key: CodingKey>(
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

  package static func decodeStringArrayIfPresent<Key: CodingKey>(
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

  package static func decodeRequiredValue<Value: Decodable, Key: CodingKey>(
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

  package static func decodeRequiredEnum<Value, Key>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    aliases: [String: Value] = [:],
    fieldName: String
  ) throws -> Value
  where Value: CaseIterable & RawRepresentable, Value.RawValue == String {
    let rawValue = try decodeRequiredString(from: container, forKey: key)
    let normalized = normalizedIdentifier(rawValue)

    if let value = Value.allCases.first(where: {
      normalizedIdentifier($0.rawValue) == normalized
    }) {
      return value
    }
    if let value = aliases[normalized] {
      return value
    }

    let allowedValues = Value.allCases.map(\.rawValue).joined(separator: ", ")
    let aliasValues = aliases.keys.sorted().joined(separator: ", ")
    let aliasSuffix = aliasValues.isEmpty ? "" : " Accepted aliases: \(aliasValues)."
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: container.codingPath + [key],
        debugDescription:
          "\(fieldName) must be one of: \(allowedValues). Received `\(rawValue)`.\(aliasSuffix)"
      )
    )
  }

  package static func decodeValueIfPresent<Value: Decodable, Key: CodingKey>(
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

  package static func decodeIntIfPresent<Key: CodingKey>(
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

  package static func decodeBool<Key: CodingKey>(
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

  package static func normalizedIdentifier(_ rawValue: String) -> String {
    let camelSeparated =
      rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(
        of: #"([a-z0-9])([A-Z])"#,
        with: "$1_$2",
        options: .regularExpression
      )
    return
      camelSeparated
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

    package init(from decoder: Decoder) throws {
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

    package init(from decoder: Decoder) throws {
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

package struct PlanNext: Codable, Equatable {
  package var plan: String
  package var verify: String
  package var verifyTimeoutMs: Int?
  package var estimatedDifficulty: Difficulty?
  package var requiresHostXcode: Bool
  package var selectedBecause: String?
  package var source: Source?
  package var candidateID: String?

  package enum Difficulty: String, Codable, CaseIterable {
    case low
    case medium
    case high
  }

  package enum Source: String, Codable, CaseIterable {
    case draft
    case feedback
    case candidate
    case focus
    case repository
    case repair
  }

  package enum CodingKeys: String, CodingKey {
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

  package init(
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
    self.selectedBecause =
      selectedBecause?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    self.source = source
    self.candidateID = candidateID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  package init(from decoder: Decoder) throws {
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

  package func encode(to encoder: Encoder) throws {
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

package struct PlanCandidate: Codable, Equatable, Identifiable {
  package var id: String
  package var title: String
  package var outcome: String
  package var why: String
  package var category: Category
  package var origin: Origin
  package var priority: Priority
  package var status: Status
  package var evidence: [String]
  package var blockedBy: [String]
  package var risk: String?

  package enum CodingKeys: String, CodingKey {
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

  package enum Category: String, Codable, CaseIterable {
    case feature
    case test
    case cleanup
    case docs
    case bugHunt
    case reliability
    case exploration

    static let modelAliases: [String: Category] = [
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

  package enum Origin: String, Codable, CaseIterable {
    case draft
    case feedback
    case repository
    case plan
    case lesson
    case user

    static let modelAliases: [String: Origin] = [
      "current_brief": .user,
      "current_request": .user,
      "repo": .repository,
      "request": .user,
      "user_request": .user,
    ]
  }

  package enum Priority: String, Codable, CaseIterable {
    case low
    case medium
    case high

    static let modelAliases: [String: Priority] = [:]
  }

  package enum Status: String, Codable, CaseIterable {
    case available
    case active
    case blocked
    case deferred
    case done
    case stale

    static let modelAliases: [String: Status] = [
      "closed": .done,
      "complete": .done,
      "completed": .done,
      "in_progress": .active,
      "open": .available,
      "ready": .available,
      "todo": .available,
      "to_do": .available,
    ]

    var isActionable: Bool {
      switch self {
      case .available, .active:
        return true
      case .blocked, .deferred, .done, .stale:
        return false
      }
    }
  }

  package init(
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

  package init(from decoder: Decoder) throws {
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

package struct PlanStrategicContext: Codable, Equatable {
  package var summary: String
  package var targetUsers: [String]
  package var desiredOutcomes: [String]
  package var constraints: [String]
  package var acceptanceSignals: [String]

  package var thesis: String {
    get { summary }
    set { summary = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  package var principles: [String] {
    get { desiredOutcomes }
    set { desiredOutcomes = Self.cleaned(newValue) }
  }

  package var nonGoals: [String] {
    get { [] }
    set { _ = newValue }
  }

  package var risks: [String] {
    get { acceptanceSignals }
    set { acceptanceSignals = Self.cleaned(newValue) }
  }

  package enum CodingKeys: String, CodingKey {
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

  package static let empty = PlanStrategicContext(
    summary: "",
    targetUsers: [],
    desiredOutcomes: [],
    constraints: [],
    acceptanceSignals: []
  )

  package init(
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

  package init(from decoder: Decoder) throws {
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

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(summary, forKey: .summary)
    try container.encode(targetUsers, forKey: .targetUsers)
    try container.encode(desiredOutcomes, forKey: .desiredOutcomes)
    try container.encode(constraints, forKey: .constraints)
    try container.encode(acceptanceSignals, forKey: .acceptanceSignals)
  }

  package var digestLines: [String] {
    var lines: [String] = []
    if !summary.isEmpty {
      lines.append("Summary: \(summary)")
    }
    lines += targetUsers.prefix(5).map { "Target user: \($0)" }
    lines += desiredOutcomes.prefix(5).map { "Outcome: \($0)" }
    lines += constraints.prefix(5).map { "Constraint: \($0)" }
    lines += acceptanceSignals.prefix(5).map { "Acceptance signal: \($0)" }
    return lines
  }

  package var markdownSummary: String {
    var sections: [String] = []
    if !summary.isEmpty {
      sections.append(summary)
    }
    if !targetUsers.isEmpty {
      sections.append("Target users:\n" + targetUsers.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
    }
    if !desiredOutcomes.isEmpty {
      sections.append("Desired outcomes:\n" + desiredOutcomes.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
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

package struct PlanQuestion: Codable, Equatable, Identifiable {
  package var id: String
  package var question: String
  package var impact: String

  package init(id: String, question: String, impact: String = "") {
    self.id =
      id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? UUID().uuidString.lowercased()
    self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    self.impact = impact.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

package extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

package struct PlanState: Codable, Equatable {
  package var schemaVersion: Int
  package var completed: [String]
  package var immediate: PlanNext?
  package var queue: [PlanCandidate]
  package var brief: PlanStrategicContext
  package var openQuestions: [PlanQuestion]

  package static let empty = PlanState(
    schemaVersion: 1,
    completed: [],
    immediate: nil,
    queue: [],
    brief: .empty,
    openQuestions: []
  )

  package enum CodingKeys: String, CodingKey {
    case schemaVersion
    case brief
    case queue
    case completed
    case immediate
    case candidates
    case strategicContext
    case openQuestions
  }

  package init(
    schemaVersion: Int = 1,
    completed: [String],
    immediate: PlanNext?,
    queue: [PlanCandidate]? = nil,
    brief: PlanStrategicContext? = nil,
    candidates: [PlanCandidate] = [],
    strategicContext: PlanStrategicContext = .empty,
    openQuestions: [PlanQuestion] = []
  ) {
    self.schemaVersion = max(1, schemaVersion)
    self.completed = completed
    self.immediate = immediate
    self.queue = queue ?? candidates
    self.brief = brief ?? strategicContext
    self.openQuestions = openQuestions
  }

  package init(from decoder: Decoder) throws {
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
  }

  package func encode(to encoder: Encoder) throws {
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
  }

  package var candidates: [PlanCandidate] {
    get { queue }
    set { queue = newValue }
  }

  package var strategicContext: PlanStrategicContext {
    get { brief }
    set { brief = newValue }
  }

  package var candidatesMarkdown: String {
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

  package var strategicContextMarkdown: String {
    strategicContext.markdownSummary
  }

  package var actionableCandidates: [PlanCandidate] {
    candidates.filter { $0.status.isActionable }
  }

  package var proposal: PlanProposal {
    PlanProposal(from: self)
  }

  package func applying(proposal: PlanProposal) -> PlanState {
    proposal.applying(to: self)
  }
}

package typealias FactoryState = PlanState
package typealias FactoryBrief = PlanStrategicContext
package typealias FactoryWorkItem = PlanCandidate
package typealias FactoryImmediate = PlanNext
package typealias FactoryQuestion = PlanQuestion

package struct LessonEdit: Codable, Equatable {
  package var find: String
  package var replace: String
  package var replaceAll: Bool?

  package enum CodingKeys: String, CodingKey {
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

  package init(find: String, replace: String, replaceAll: Bool?) {
    self.find = find
    self.replace = replace
    self.replaceAll = replaceAll
  }

  package init(from decoder: Decoder) throws {
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

  package func encode(to encoder: Encoder) throws {
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

package extension FlexibleModelDecoder {
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

    package init(from decoder: Decoder) throws {
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

package struct PlanRunResult: Codable, Equatable {
  package var state: PlanProposal
  package var lessonEdits: [LessonEdit]

  package enum CodingKeys: String, CodingKey {
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

  package init(
    state: PlanProposal,
    lessonEdits: [LessonEdit] = []
  ) {
    self.state = state
    self.lessonEdits = lessonEdits
  }

  package init(from decoder: Decoder) throws {
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

  package func encode(to encoder: Encoder) throws {
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
  package var value: String?

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    value = try? container.decode(String.self)
  }
}

package struct SessionCommit: Codable, Identifiable, Equatable {
  package var id: String { sha }
  package var sha: String
  package var short: String
  package var subject: String

  package init(sha: String, short: String, subject: String) {
    self.sha = sha
    self.short = short
    self.subject = subject
  }
}

package struct VerifyOutput: Codable, Equatable {
  package var command: String
  package var exitCode: Int?
  package var tail: String

  package init(command: String, exitCode: Int?, tail: String) {
    self.command = command
    self.exitCode = exitCode
    self.tail = tail
  }
}

package struct SessionExecutionEnvironmentSnapshot: Codable, Equatable, Identifiable {
  package static let phaseLimit = 24
  package static let fieldLimit = 120
  package static let summaryLimit = 280
  /// Stable identifier retained for older snapshot schema compatibility.
  /// constant so consumers don't grow another magic string.
  package static let vmBuildActionIdentifier = "shared-vm.build"

  package var phase: String
  package var phaseIdentifier: String
  package var attempt: Int?
  package var selectedPreferenceIdentifier: String
  package var selectedPreferenceTitle: String
  package var effectiveRouteIdentifier: String
  package var effectiveRouteTitle: String
  /// Captures the runtime readiness classification. Field name retained so on-disk
  /// snapshots remain decodable.
  package var supportClassificationIdentifier: String
  /// Retained for forward-compatibility with the previous snapshot schema; always empty.
  package var visibleSupportTokens: [String]
  package var omittedSupportTokenCount: Int
  package var imageLabel: String
  package var workspaceLabel: String
  package var fallbackReason: String?
  /// Runtime availability. Field name retained from the old provisioning slot.
  package var provisioningAvailabilityIdentifier: String?
  /// Runtime status. Field name retained.
  package var provisioningStatusIdentifier: String?
  /// Runtime action identifier. Field name retained.
  package var provisioningActionIdentifier: String?

  package var id: String {
    [
      phaseIdentifier,
      attempt.map { "attempt-\($0)" } ?? "attempt-none",
      selectedPreferenceIdentifier,
      effectiveRouteIdentifier,
      supportClassificationIdentifier,
    ].joined(separator: ".")
  }

  package var replacementKey: String {
    "\(phaseIdentifier)#\(attempt.map(String.init) ?? "none")"
  }

  package init(
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
      launchPlan.isContainerRoute ? "containerized-linux" : "host"
    visibleSupportTokens = []
    omittedSupportTokenCount = 0
    imageLabel = Self.sanitizedField(launchPlan.imageLabel, limit: Self.fieldLimit)
    workspaceLabel = Self.sanitizedField(launchPlan.workspaceLabel, limit: Self.fieldLimit)
    fallbackReason = Self.sanitizedOptionalField(
      launchPlan.fallbackReason,
      limit: AgentExecutionLaunchPlan.fallbackReasonLimit
    )
    provisioningAvailabilityIdentifier = launchPlan.isContainerRoute ? "available" : nil
    provisioningStatusIdentifier = launchPlan.isContainerRoute ? "ready" : nil
    provisioningActionIdentifier = nil
  }

  package var routeSummary: String {
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

package struct AgentRunTokenUsage: Codable, Equatable, Sendable {
  package var inputTokens: Int
  package var outputTokens: Int
  package var totalTokens: Int
  package var estimatedTokens: Int
  package var streamedUsageAvailable: Bool
  package var compactionCount: Int
  package var summaryTokens: Int
  package var retryCount: Int
  package var durationMs: Int?

  package init(
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

  package var hasUsage: Bool {
    totalTokens > 0 || inputTokens > 0 || outputTokens > 0
      || estimatedTokens > 0 || compactionCount > 0 || summaryTokens > 0
  }

  package var usesEstimate: Bool {
    estimatedTokens > 0 || !streamedUsageAvailable
  }

  mutating func recordTurn(
    inputTokens: Int,
    outputTokens: Int,
    totalTokens: Int,
    isEstimated: Bool,
    streamedUsageAvailable: Bool
  ) {
    let normalizedInput = max(0, inputTokens)
    let normalizedOutput = max(0, outputTokens)
    let normalizedTotal = max(0, totalTokens == 0 ? normalizedInput + normalizedOutput : totalTokens)
    self.inputTokens += normalizedInput
    self.outputTokens += normalizedOutput
    self.totalTokens += normalizedTotal
    if isEstimated {
      estimatedTokens += normalizedTotal
    }
    self.streamedUsageAvailable = self.streamedUsageAvailable || streamedUsageAvailable
  }

  mutating func recordCompaction(summaryTokens: Int) {
    compactionCount += 1
    self.summaryTokens += max(0, summaryTokens)
  }

  package static func estimated(
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

  package static func estimateTokens(characters: Int, charsPerToken: Int) -> Int {
    guard characters > 0 else { return 0 }
    let divisor = max(1, charsPerToken)
    return (characters + divisor - 1) / divisor
  }
}

package struct SessionPhaseTokenUsage: Codable, Equatable, Sendable, Identifiable {
  package var id: String {
    [
      phase,
      proofActionKind ?? "",
      outcome ?? "",
      String(createdAt),
    ]
    .joined(separator: "|")
  }

  package var phase: String
  package var inputTokens: Int
  package var outputTokens: Int
  package var totalTokens: Int
  package var estimatedTokens: Int
  package var streamedUsageAvailable: Bool
  package var compactionCount: Int
  package var summaryTokens: Int
  package var proofActionKind: String?
  package var outcome: String?
  package var retryCount: Int
  package var durationMs: Int?
  package var createdAt: Double

  package init(
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

  package var usesEstimate: Bool {
    estimatedTokens > 0 || !streamedUsageAvailable
  }

  package var compactLabel: String {
    let suffix = usesEstimate ? " est." : ""
    return "\(Self.formatTokens(totalTokens)) tokens\(suffix)"
  }

  private static func normalizedOptional(_ value: String?, limit: Int) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit - 3)) + "..."
  }

  package static func formatTokens(_ count: Int) -> String {
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

package struct SessionTokenSummary: Codable, Equatable, Sendable {
  package var phases: [SessionPhaseTokenUsage]

  package init(phases: [SessionPhaseTokenUsage] = []) {
    self.phases = phases
  }

  package var isEmpty: Bool { phases.isEmpty }
  package var totalInputTokens: Int { phases.reduce(0) { $0 + $1.inputTokens } }
  package var totalOutputTokens: Int { phases.reduce(0) { $0 + $1.outputTokens } }
  package var totalTokens: Int { phases.reduce(0) { $0 + $1.totalTokens } }
  package var estimatedTokens: Int { phases.reduce(0) { $0 + $1.estimatedTokens } }
  package var compactionCount: Int { phases.reduce(0) { $0 + $1.compactionCount } }
  package var summaryTokens: Int { phases.reduce(0) { $0 + $1.summaryTokens } }
  package var retryCount: Int { phases.reduce(0) { $0 + $1.retryCount } }
  package var usesEstimate: Bool { phases.contains { $0.usesEstimate } }

  package var latestProofActionKind: String? {
    phases.reversed().compactMap(\.proofActionKind).first
  }

  package var latestPhase: SessionPhaseTokenUsage? {
    phases.max { $0.createdAt < $1.createdAt }
  }

  package var compactLabel: String? {
    guard !isEmpty else { return nil }
    let suffix = usesEstimate ? " est." : ""
    return "\(SessionPhaseTokenUsage.formatTokens(totalTokens)) tokens\(suffix)"
  }

  package mutating func record(_ usage: SessionPhaseTokenUsage) {
    guard usage.totalTokens > 0 || usage.compactionCount > 0 else { return }
    phases.append(usage)
  }
}

package enum SessionStatus: String, Codable, CaseIterable {
  case planning
  case awaitingApproval = "awaiting_approval"
  case developing
  case succeeded
  case failed
  case cancelled
  case rejectedByPlan = "rejected_by_plan"
  case skipped

  package var identifier: String { rawValue }
}

package struct SessionRecord: Codable, Identifiable, Equatable {
  package var id: Int { session }
  package var session: Int
  package var startedAt: Double
  package var endedAt: Double?
  package var plan: String?
  package var verify: String?
  package var beforeSha: String?
  package var afterSha: String?
  package var commits: [SessionCommit]
  package var changedPaths: [String]
  package var status: SessionStatus
  package var notes: [String]
  package var verifyOutput: VerifyOutput?
  package var feedback: String?
  package var executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot]
  package var tokenSummary: SessionTokenSummary

  package static func started(_ number: Int) -> SessionRecord {
    SessionRecord(
      session: number,
      startedAt: Date().timeIntervalSince1970 * 1000,
      endedAt: nil,
      plan: nil,
      verify: nil,
      beforeSha: nil,
      afterSha: nil,
      commits: [],
      changedPaths: [],
      status: .planning,
      notes: [],
      verifyOutput: nil,
      feedback: nil,
      executionEnvironmentSnapshots: [],
      tokenSummary: SessionTokenSummary()
    )
  }

  package static let executionEnvironmentSnapshotLimit = 24

  package enum CodingKeys: String, CodingKey {
    case session
    case startedAt
    case endedAt
    case plan
    case verify
    case beforeSha
    case afterSha
    case commits
    case changedPaths
    case status
    case notes
    case verifyOutput
    case feedback
    case executionEnvironmentSnapshots
    case tokenSummary
  }

  package init(
    session: Int,
    startedAt: Double,
    endedAt: Double?,
    plan: String?,
    verify: String?,
    beforeSha: String?,
    afterSha: String?,
    commits: [SessionCommit],
    changedPaths: [String] = [],
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
    self.changedPaths = changedPaths
    self.status = status
    self.notes = notes
    self.verifyOutput = verifyOutput
    self.feedback = feedback
    self.executionEnvironmentSnapshots = Self.normalizedExecutionEnvironmentSnapshots(
      executionEnvironmentSnapshots
    )
    self.tokenSummary = tokenSummary
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    session = try container.decodeIfPresent(Int.self, forKey: .session) ?? 0
    startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt) ?? 0
    endedAt = try container.decodeIfPresent(Double.self, forKey: .endedAt)
    plan = try container.decodeIfPresent(String.self, forKey: .plan)
    verify = try container.decodeIfPresent(String.self, forKey: .verify)
    beforeSha = try container.decodeIfPresent(String.self, forKey: .beforeSha)
    afterSha = try container.decodeIfPresent(String.self, forKey: .afterSha)
    commits = try container.decodeIfPresent([SessionCommit].self, forKey: .commits) ?? []
    changedPaths = try container.decodeIfPresent([String].self, forKey: .changedPaths) ?? []
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

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(session, forKey: .session)
    try container.encode(startedAt, forKey: .startedAt)
    try container.encodeIfPresent(endedAt, forKey: .endedAt)
    try container.encodeIfPresent(plan, forKey: .plan)
    try container.encodeIfPresent(verify, forKey: .verify)
    try container.encodeIfPresent(beforeSha, forKey: .beforeSha)
    try container.encodeIfPresent(afterSha, forKey: .afterSha)
    try container.encode(commits, forKey: .commits)
    try container.encode(changedPaths, forKey: .changedPaths)
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

  package var latestExecutionEnvironmentSnapshot: SessionExecutionEnvironmentSnapshot? {
    executionEnvironmentSnapshots.last
  }

  package mutating func recordExecutionEnvironmentSnapshot(_ snapshot: SessionExecutionEnvironmentSnapshot)
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

package struct DevelopSummary: Codable, Equatable {
  package var status: Status
  package var summary: String
  package var feedback: String
  package var bypassVerify: Bool?
  package var lessonEdits: [LessonEdit]

  package enum Status: String, Codable {
    case succeeded
    case blocked
    case failed

    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  package enum CodingKeys: String, CodingKey {
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

  package init(
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

  package init(from decoder: Decoder) throws {
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

  package func encode(to encoder: Encoder) throws {
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
package struct CriticVerdict: Codable, Equatable {
  package enum Verdict: String, Codable {
    case approve
    case requestChanges = "request_changes"

    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  package var verdict: Verdict
  package var summary: String
  package var feedback: String

  package init(verdict: Verdict, summary: String, feedback: String) {
    self.verdict = verdict
    self.summary = summary
    self.feedback = feedback
  }

  package enum CodingKeys: String, CodingKey {
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

  package init(from decoder: Decoder) throws {
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

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(verdict, forKey: .verdict)
    try container.encode(summary, forKey: .summary)
    try container.encode(feedback, forKey: .feedback)
  }
}

package struct LiveLine: Identifiable, Equatable {
  package var id = UUID()
  package var date = Date()
  package var level: Level
  package var text: String
  package var detail: String?
  package var kind: Kind = .message
  package var status: Status = .none
  package var correlationID: String?
  package var completedAt: Date?

  package enum Level {
    case info
    case success
    case warning
    case error
    case raw
  }

  package enum Kind {
    case message
    case lifecycle
    case command
    case agentMessage
    case fileChange
  }

  package enum Status {
    case none
    case running
    case completed
    case failed
  }

  package init(
    id: UUID = UUID(),
    date: Date = Date(),
    level: Level,
    text: String,
    detail: String? = nil,
    kind: Kind = .message,
    status: Status = .none,
    correlationID: String? = nil,
    completedAt: Date? = nil
  ) {
    self.id = id
    self.date = date
    self.level = level
    self.text = text
    self.detail = detail
    self.kind = kind
    self.status = status
    self.correlationID = correlationID
    self.completedAt = completedAt
  }
}

package struct LiveEvent: Equatable {
  package var level: LiveLine.Level
  package var text: String
  package var detail: String?
  package var kind: LiveLine.Kind
  package var status: LiveLine.Status
  package var correlationID: String?
  package var metadata: [String: String]?

  package init(
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

package enum PauseMode: String, Codable, CaseIterable, Identifiable {
  case immediate
  case afterIteration = "after_iteration"

  package var id: Self { self }

  package var label: String {
    switch self {
    case .immediate:
      return "Pause Now"
    case .afterIteration:
      return "Pause After Iteration"
    }
  }

  package var hint: String {
    switch self {
    case .immediate:
      return "Stop before the next phase gate."
    case .afterIteration:
      return "Let the current Plan and Develop finish first."
    }
  }

  package var identifier: String { rawValue }
}

package enum LoopPhase: String, CaseIterable {
  case idle = "Idle"
  case planning = "Planning"
  case developing = "Developing"
  case verifying = "Verifying"
  case reviewing = "Reviewing"
  case paused = "Paused"
  case failed = "Failed"
  case succeeded = "Succeeded"
  case cancelled = "Cancelled"

  package var identifier: String { rawValue }
}
