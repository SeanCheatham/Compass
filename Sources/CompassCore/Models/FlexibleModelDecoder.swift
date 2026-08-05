import Foundation

public enum FlexibleModelDecoder {
  public static func decodeRequiredString<Key: CodingKey>(
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

  public static func decodeRequiredString<Key: CodingKey>(
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
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: container.codingPath,
        debugDescription: "Missing usable \(fieldName) field."
      )
    )
  }

  public static func decodeStringIfPresent<Key: CodingKey>(
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

  public static func decodeStringIfPresent<Key: CodingKey>(
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

  public static func decodeStringArrayIfPresent<Key: CodingKey>(
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

  public static func decodeRequiredValue<Value: Decodable, Key: CodingKey>(
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

  public static func decodeRequiredEnum<Value, Key>(
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

  public static func decodeValueIfPresent<Value: Decodable, Key: CodingKey>(
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

  public static func decodeIntIfPresent<Key: CodingKey>(
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

  public static func decodeBool<Key: CodingKey>(
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

  public static func normalizedIdentifier(_ rawValue: String) -> String {
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
    public var values: [String]

    public init(from decoder: Decoder) throws {
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

    public init(from decoder: Decoder) throws {
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

    public var stringArrayValue: [String] {
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

